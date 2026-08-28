from collections import defaultdict
from app.components.temporal_causal_patterns.graph_builder import graph_builder
from app.components.temporal_causal_patterns.dfs_engine import dfs_engine
from app.components.temporal_causal_patterns.louvain_engine import louvain_engine
from app.components.temporal_causal_patterns.fft_engine import fft_engine
from app.components.temporal_causal_patterns.normaliser import normaliser
from app.components.temporal_causal_patterns.htgps_engine import htgps_engine


# ─────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────

MIN_TRIGGER_RECORDS = 3
MIN_CONFIDENCE_PP1  = 0.60
STRONG_THRESHOLD    = 0.75
MODERATE_THRESHOLD  = 0.50


# ─────────────────────────────────────────────
# PATTERN ENGINE — FULL HTGPS PIPELINE
# ─────────────────────────────────────────────

class PatternEngine:

    # ─────────────────────────────────────────
    # MAIN ENTRY POINT
    # ─────────────────────────────────────────

    def analyse(self, user_id: str):
        print(f"[PatternEngine] Starting HTGPS analysis for: {user_id}")

        # Step 1 — fetch diary data from AuraDB
        entries = graph_builder.fetch_user_diary_data(user_id)

        if not entries:
            print(f"[PatternEngine] No entries found for: {user_id}")
            return []

        print(f"[PatternEngine] Fetched {len(entries)} entries")

        # Step 2 — fetch full entry chain for DFS
        dfs_entries = dfs_engine.fetch_entry_chain(user_id)

        # Step 3 — get all entry dates for FFT
        all_entry_dates = [
            e.get("entryDate", "")
            for e in entries
            if e.get("entryDate")
        ]

        # Step 4 — group by trigger combination
        trigger_groups = self._group_by_trigger(entries)

        # Step 5 — detect and score each pattern
        patterns = []
        for trigger_key, group_entries in trigger_groups.items():
            detected = self._detect_and_score(
                trigger_key     = trigger_key,
                group_entries   = group_entries,
                dfs_entries     = dfs_entries,
                all_entry_dates = all_entry_dates,
                user_id         = user_id,
            )
            patterns.extend(detected)

        # Step 6 — filter weak patterns
        patterns = [
            p for p in patterns
            if p.get("htgpsScore", 0) >= MODERATE_THRESHOLD
        ]

        print(f"[PatternEngine] Total patterns after HTGPS: {len(patterns)}")
        return patterns

    # ─────────────────────────────────────────
    # GROUP BY TRIGGER
    # ─────────────────────────────────────────

    def _group_by_trigger(self, entries: list):
        """
        Group entries by 5-field trigger key:
        activityCategory + timePeriod
        + withWhom + moodBefore + specificPerson
        """
        groups = defaultdict(list)

        for entry in entries:
            trigger_key = (
                str(entry.get("activityCategory", "")).strip(),
                str(entry.get("timePeriod",       "")).strip(),
                str(entry.get("withWhom",          "")).strip(),
                str(entry.get("moodBefore",        "")).strip(),
                str(entry.get("specificPerson",    "")).strip(),
            )
            groups[trigger_key].append(entry)

        print(f"[PatternEngine] Trigger groups: {len(groups)}")
        return groups

    # ─────────────────────────────────────────
    # DETECT AND SCORE PATTERNS
    # ─────────────────────────────────────────

    def _detect_and_score(
        self,
        trigger_key    : tuple,
        group_entries  : list,
        dfs_entries    : list,
        all_entry_dates: list,
        user_id        : str,
    ):
        """
        For each trigger group:
        1. Frequency counting finds candidates
        2. DFS validates time order
        3. Louvain validates cluster
        4. FFT validates repetition
        5. HTGPS combines all scores
        """
        detected = []

        if len(group_entries) < MIN_TRIGGER_RECORDS:
            return detected

        category, time_period, with_whom, mood_before, specific_person = trigger_key
        total_count = len(group_entries)

        outcome_fields = [
            ("moodAfter",         "mood changes to"),
            ("productivityLevel", "productivity becomes"),
            ("healthStatus",      "health status becomes"),
            ("taskOutcome",       "task outcome is"),
        ]

        for outcome_field, outcome_label in outcome_fields:
            outcome_counts = self._count_outcomes(group_entries, outcome_field)

            for outcome_value, matched_count in outcome_counts.items():

                confidence = matched_count / total_count

                if confidence < MIN_CONFIDENCE_PP1:
                    continue
                if not outcome_value or outcome_value == "None":
                    continue

                # Get base evidence dates
                base_dates = self._get_evidence_dates(
                    group_entries, outcome_field, outcome_value
                )

                # Build base pattern (PP1 baseline)
                base_pattern = {
                    "insightText"         : self._generate_insight(
                        trigger_key, outcome_label,
                        outcome_value, matched_count, total_count
                    ),
                    "trigger"             : self._build_trigger_string(trigger_key),
                    "outcome"             : f"{outcome_field} = {outcome_value}",
                    "matchedCount"        : matched_count,
                    "totalTriggerCount"   : total_count,
                    "confidencePercentage": round(confidence * 100, 2),
                    "patternLevel"        : self._get_pattern_level(confidence),
                    "evidenceDates"       : base_dates,
                }

                # ── DFS VALIDATION ──────────────
                dfs_result = dfs_engine.validate_same_entry(
                    entries              = dfs_entries,
                    trigger_category     = category,
                    trigger_time_period  = time_period,
                    trigger_with_whom    = with_whom,
                    trigger_mood_before  = mood_before,
                    outcome_field        = outcome_field,
                    outcome_value        = outcome_value,
                    specific_person      = specific_person,
                )

                # Also check cross-entry DFS
                cross_dfs = dfs_engine.validate_cross_entry(
                    entries              = dfs_entries,
                    trigger_category     = category,
                    trigger_time_period  = time_period,
                    trigger_with_whom    = with_whom,
                    outcome_field        = outcome_field,
                    outcome_value        = outcome_value,
                    specific_person      = specific_person,
                )

                # Use best DFS score
                if cross_dfs["dfsScore"] > dfs_result["dfsScore"]:
                    dfs_result = cross_dfs

                # ── LOUVAIN VALIDATION ───────────
                louvain_result = louvain_engine.validate_cluster(
                    user_id         = user_id,
                    trigger_concept = category if category else with_whom,
                    outcome_concept = outcome_value,
                )

                # ── FFT VALIDATION ───────────────
                fft_result = fft_engine.analyse_repetition(
                    user_id             = user_id,
                    trigger_category    = category,
                    trigger_time_period = time_period,
                    specific_person     = specific_person,
                    all_entry_dates     = all_entry_dates,
                )

                # ── NORMALISE SCORES ─────────────
                dfs_score     = normaliser.normalise_dfs(dfs_result)
                louvain_score = normaliser.normalise_louvain(louvain_result)
                fft_score     = normaliser.normalise_fft(fft_result)

                normaliser.validate_all(dfs_score, louvain_score, fft_score)

                # ── HTGPS COMBINE ────────────────
                enhanced = htgps_engine.analyse_pattern(
                    dfs_score      = dfs_score,
                    louvain_score  = louvain_score,
                    fft_score      = fft_score,
                    dfs_result     = dfs_result,
                    louvain_result = louvain_result,
                    fft_result     = fft_result,
                    base_pattern   = base_pattern,
                )

                detected.append(enhanced)

        return detected

    # ─────────────────────────────────────────
    # HELPER METHODS
    # ─────────────────────────────────────────

    def _count_outcomes(self, entries: list, outcome_field: str):
        counts = defaultdict(int)
        for entry in entries:
            value = str(entry.get(outcome_field, "")).strip()
            if value and value != "None":
                counts[value] += 1
        return counts

    def _get_evidence_dates(
        self, entries: list,
        outcome_field: str,
        outcome_value: str
    ):
        dates = []
        for entry in entries:
            value = str(entry.get(outcome_field, "")).strip()
            if value == outcome_value:
                date = entry.get("entryDate", "")
                if date and date not in dates:
                    dates.append(date)
        return sorted(dates)

    def _get_pattern_level(self, confidence: float):
        if confidence >= STRONG_THRESHOLD:
            return "Strong"
        elif confidence >= MODERATE_THRESHOLD:
            return "Moderate"
        return "Weak"

    def _build_trigger_string(self, trigger_key: tuple):
        category, time_period, with_whom, mood_before, specific_person = trigger_key
        parts = []
        if category:       parts.append(category)
        if time_period:    parts.append(time_period)
        if with_whom:      parts.append(with_whom)
        if mood_before:    parts.append(mood_before)
        if specific_person: parts.append(f"with {specific_person}")
        return " + ".join(parts)

    def _generate_insight(
        self,
        trigger_key  : tuple,
        outcome_label: str,
        outcome_value: str,
        matched_count: int,
        total_count  : int,
    ):
        category, time_period, with_whom, mood_before, specific_person = trigger_key
        parts = []
        if category:        parts.append(f"{category} activities")
        if time_period:     parts.append(f"during {time_period}")
        if specific_person: parts.append(f"with {specific_person} specifically")
        elif with_whom:     parts.append(f"with {with_whom}")
        if mood_before:     parts.append(f"starting with {mood_before} mood")
        trigger_desc = ", ".join(parts) if parts else "these activities"

        return (
            f"When the user engages in {trigger_desc}, "
            f"{outcome_label} {outcome_value} "
            f"in {matched_count} out of {total_count} records."
        )


pattern_engine = PatternEngine()