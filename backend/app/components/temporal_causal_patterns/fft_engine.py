import numpy as np
from datetime import datetime, timedelta
from app.database import neo4j_conn


# ─────────────────────────────────────────────
# FFT ENGINE — REPETITION ANALYSIS
# ─────────────────────────────────────────────

MIN_ENTRIES_FOR_FFT = 14
MIN_DAYS_SPAN       = 7


class FFTEngine:

    # ─────────────────────────────────────────
    # FETCH TRIGGER DATES FROM AURADB
    # ─────────────────────────────────────────

    def fetch_trigger_dates(
        self,
        user_id: str,
        trigger_category: str,
        trigger_time_period: str = "",
        specific_person: str = "",
    ):
        """
        Fetch all entryDateTime values for
        entries matching the trigger pattern
        for one user from AuraDB.
        Uses edge entryDateTime values.
        """
        query = """
        MATCH (u:User {userId: $userId})
              -[:HAS_ENTRY]->(e:DiaryEntry)
        MATCH (e)-[r:HAS_CATEGORY]->(c:ActivityCategory)
        WHERE c.name = $triggerCategory
        RETURN
            e.entryDate     AS entryDate,
            e.entryDateTime AS entryDateTime,
            e.timePeriod    AS timePeriod,
            e.specificPerson AS specificPerson,
            r.entryDateTime AS edgeDateTime
        ORDER BY e.entryDateTime ASC
        """
        with neo4j_conn.get_session() as session:
            result = session.run(query, {
                "userId"          : user_id,
                "triggerCategory" : trigger_category,
            })
            records = [record.data() for record in result]

        # Filter by timePeriod if provided
        if trigger_time_period:
            records = [
                r for r in records
                if str(r.get("timePeriod", "")).strip() == trigger_time_period
            ]

        # Filter by specificPerson if provided
        if specific_person:
            records = [
                r for r in records
                if str(r.get("specificPerson", "")).strip() == specific_person
            ]

        print(f"[FFTEngine] Found {len(records)} trigger dates "
              f"for {trigger_category} user {user_id}")
        return records

    # ─────────────────────────────────────────
    # PARSE DATETIME STRING
    # ─────────────────────────────────────────

    def _parse_date(self, date_str: str):
        """Parse entryDate string to date object."""
        try:
            return datetime.strptime(str(date_str)[:10], "%Y-%m-%d").date()
        except:
            return None

    # ─────────────────────────────────────────
    # BUILD BINARY TIME SERIES
    # ─────────────────────────────────────────

    def _build_time_series(
        self,
        trigger_records: list,
        all_dates: list,
    ):
        """
        Build binary array where:
        1 = trigger occurred on that day
        0 = trigger did not occur

        Array spans from first to last
        diary entry date.
        """
        if not all_dates:
            return np.array([]), None, None

        start_date = min(all_dates)
        end_date   = max(all_dates)
        total_days = (end_date - start_date).days + 1

        if total_days < 1:
            return np.array([]), start_date, end_date

        # Create binary array
        series = np.zeros(total_days)

        trigger_dates = set()
        for record in trigger_records:
            d = self._parse_date(record.get("entryDate", ""))
            if d:
                trigger_dates.add(d)

        for i in range(total_days):
            day = start_date + timedelta(days=i)
            if day in trigger_dates:
                series[i] = 1

        return series, start_date, end_date

    # ─────────────────────────────────────────
    # DETECT WEEKLY CYCLE USING FFT
    # ─────────────────────────────────────────

    def _detect_weekly_cycle(self, series: np.ndarray):
        """
        Run numpy FFT on binary time series.
        Check if dominant frequency peak
        corresponds to 7-day weekly cycle.
        Returns normalised fftScore 0-1.
        """
        if len(series) < 7:
            return 0.0, 0

        # Run FFT
        fft_result    = np.fft.fft(series)
        fft_magnitude = np.abs(fft_result)
        n             = len(series)

        # Ignore DC component (index 0)
        fft_magnitude[0] = 0

        # Find dominant frequency
        dominant_idx = np.argmax(fft_magnitude[:n // 2])
        peak_amp     = fft_magnitude[dominant_idx]
        max_amp      = np.max(fft_magnitude[:n // 2])

        # Calculate period of dominant frequency
        if dominant_idx > 0:
            dominant_period = n / dominant_idx
        else:
            dominant_period = 0

        # Check if weekly cycle (6-8 day range)
        is_weekly = 6 <= dominant_period <= 8

        # Normalise score
        if max_amp > 0:
            fft_score = float(peak_amp / max_amp)
        else:
            fft_score = 0.0

        # Boost score if weekly cycle confirmed
        if is_weekly:
            fft_score = min(fft_score * 1.2, 1.0)

        fft_score = round(fft_score, 4)

        print(f"[FFTEngine] Dominant period={dominant_period:.1f} days "
              f"weekly={is_weekly} fftScore={fft_score}")

        return fft_score, dominant_period

    # ─────────────────────────────────────────
    # SIMPLE WEEKLY COUNT FALLBACK
    # ─────────────────────────────────────────

    def _simple_weekly_score(self, trigger_records: list):
        """
        Fallback when not enough data for FFT.
        Count how many unique weeks have
        at least one trigger occurrence.
        Score = weeks with trigger / total weeks.
        """
        if not trigger_records:
            return 0.0

        weeks_with_trigger = set()
        for record in trigger_records:
            d = self._parse_date(record.get("entryDate", ""))
            if d:
                week_number = d.isocalendar()[1]
                year        = d.isocalendar()[0]
                weeks_with_trigger.add((year, week_number))

        # Estimate total weeks in data span
        dates = [
            self._parse_date(r.get("entryDate", ""))
            for r in trigger_records
            if self._parse_date(r.get("entryDate", ""))
        ]

        if not dates:
            return 0.0

        span_days  = (max(dates) - min(dates)).days + 1
        total_weeks = max(span_days / 7, 1)
        score       = round(len(weeks_with_trigger) / total_weeks, 4)
        score       = min(score, 1.0)

        print(f"[FFTEngine] Simple weekly fallback: "
              f"{len(weeks_with_trigger)} trigger weeks / "
              f"{total_weeks:.1f} total weeks = {score}")

        return score

    # ─────────────────────────────────────────
    # MAIN — ANALYSE REPETITION
    # ─────────────────────────────────────────

    def analyse_repetition(
        self,
        user_id: str,
        trigger_category: str,
        trigger_time_period: str = "",
        specific_person: str = "",
        all_entry_dates: list = None,
    ):
        """
        Main FFT analysis function.
        Fetches trigger dates from AuraDB,
        builds time series, runs FFT or
        fallback weekly counting.
        Returns fftScore 0-1.
        """
        # Fetch trigger occurrence dates
        trigger_records = self.fetch_trigger_dates(
            user_id          = user_id,
            trigger_category = trigger_category,
            trigger_time_period = trigger_time_period,
            specific_person  = specific_person,
        )

        if not trigger_records:
            print(f"[FFTEngine] No trigger records found — score=0.0")
            return {
                "fftScore"       : 0.0,
                "method"         : "no_data",
                "dominantPeriod" : 0,
                "isWeeklyCycle"  : False,
            }

        # Parse all dates for time series span
        if all_entry_dates:
            all_dates = [
                self._parse_date(d) for d in all_entry_dates
                if self._parse_date(d)
            ]
        else:
            all_dates = [
                self._parse_date(r.get("entryDate", ""))
                for r in trigger_records
                if self._parse_date(r.get("entryDate", ""))
            ]

        all_dates = [d for d in all_dates if d]

        # Check if enough data for FFT
        span_days = (max(all_dates) - min(all_dates)).days + 1 if all_dates else 0

        if len(trigger_records) >= MIN_ENTRIES_FOR_FFT and span_days >= MIN_DAYS_SPAN:
            # Use FFT
            series, start, end = self._build_time_series(
                trigger_records, all_dates
            )

            if len(series) >= 7:
                fft_score, dominant_period = self._detect_weekly_cycle(series)
                is_weekly = 6 <= dominant_period <= 8

                return {
                    "fftScore"       : fft_score,
                    "method"         : "fft",
                    "dominantPeriod" : round(dominant_period, 1),
                    "isWeeklyCycle"  : is_weekly,
                }

        # Fallback to simple weekly counting
        fft_score = self._simple_weekly_score(trigger_records)

        return {
            "fftScore"       : fft_score,
            "method"         : "weekly_count_fallback",
            "dominantPeriod" : 7.0,
            "isWeeklyCycle"  : fft_score >= 0.5,
        }


fft_engine = FFTEngine()