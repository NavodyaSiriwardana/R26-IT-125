from app.database import neo4j_conn

# ─────────────────────────────────────────────
# DFS ENGINE — TEMPORAL TRAVERSAL
# ─────────────────────────────────────────────

MAX_TIME_GAP_HOURS = 24


class DFSEngine:

    # ─────────────────────────────────────────
    # FETCH ENTRY CHAIN FROM AURADB
    # ─────────────────────────────────────────

    def fetch_entry_chain(self, user_id: str):
        query = """
        MATCH (u:User {userId: $userId})
              -[:HAS_ENTRY]->(e:DiaryEntry)
        OPTIONAL MATCH (e)-[:HAS_CATEGORY]->(c:ActivityCategory)
        OPTIONAL MATCH (e)-[:WITH_SOCIAL_CONTEXT]->(s:SocialContext)
        OPTIONAL MATCH (e)-[:MOOD_BEFORE]->(mb:Mood)
        OPTIONAL MATCH (e)-[:MOOD_AFTER]->(ma:Mood)
        OPTIONAL MATCH (e)-[:HAS_PRODUCTIVITY]->(p:Productivity)
        OPTIONAL MATCH (e)-[:HAS_HEALTH_STATUS]->(h:HealthStatus)
        OPTIONAL MATCH (e)-[:HAS_TASK_OUTCOME]->(t:TaskOutcome)
        OPTIONAL MATCH (e)-[:MET_WITH]->(person:Person)
        RETURN
            e.entryId        AS entryId,
            e.entryDate      AS entryDate,
            e.entryDateTime  AS entryDateTime,
            e.timePeriod     AS timePeriod,
            e.specificPerson AS specificPerson,
            c.name           AS activityCategory,
            s.withWhom       AS withWhom,
            mb.value         AS moodBefore,
            ma.value         AS moodAfter,
            p.level          AS productivityLevel,
            h.status         AS healthStatus,
            t.outcome        AS taskOutcome,
            person.name      AS personNode
        ORDER BY e.entryDateTime ASC
        """
        with neo4j_conn.get_session() as session:
            result = session.run(query, {"userId": user_id})
            entries = [record.data() for record in result]

        print(f"[DFSEngine] Fetched {len(entries)} entries for {user_id}")
        return entries

    # ─────────────────────────────────────────
    # CALCULATE HOUR GAP
    # ─────────────────────────────────────────

    def _get_hour_gap(self, from_dt: str, to_dt: str):
        try:
            from datetime import datetime
            def parse(s):
                s = str(s)[:19]
                for fmt in [
                    "%Y-%m-%dT%H:%M:%S",
                    "%Y-%m-%dT%H:%M",
                ]:
                    try:
                        return datetime.strptime(s, fmt)
                    except:
                        continue
                return None
            a = parse(from_dt)
            b = parse(to_dt)
            if a and b:
                return (b - a).total_seconds() / 3600
            return 999
        except:
            return 999

    # ─────────────────────────────────────────
    # VALIDATE SAME ENTRY PATTERN
    # ─────────────────────────────────────────

    def validate_same_entry(
        self,
        entries: list,
        trigger_category: str,
        trigger_time_period: str,
        trigger_with_whom: str,
        trigger_mood_before: str,
        outcome_field: str,
        outcome_value: str,
        specific_person: str = "",
    ):
        """
        Validates that trigger and outcome
        appear in the SAME diary entry.
        Confirms same-entry pattern consistency.
        """
        total     = 0
        confirmed = 0
        dates     = []

        for entry in entries:
            cat    = str(entry.get("activityCategory", "")).strip()
            period = str(entry.get("timePeriod",       "")).strip()
            whom   = str(entry.get("withWhom",          "")).strip()
            mood   = str(entry.get("moodBefore",        "")).strip()
            person = str(entry.get("specificPerson",    "")).strip()

            if trigger_category    and cat    != trigger_category:    continue
            if trigger_time_period and period != trigger_time_period: continue
            if trigger_with_whom   and whom   != trigger_with_whom:   continue
            if trigger_mood_before and mood   != trigger_mood_before: continue
            if specific_person     and person != specific_person:     continue

            total += 1
            value = str(entry.get(outcome_field, "")).strip()
            if value == outcome_value:
                confirmed += 1
                d = entry.get("entryDate", "")
                if d and d not in dates:
                    dates.append(d)

        score = round(confirmed / total, 4) if total > 0 else 0.0
        print(f"[DFSEngine] Same-entry {trigger_category}->{outcome_value}: "
              f"{confirmed}/{total} score={score}")

        return {
            "dfsScore"      : score,
            "confirmed"     : confirmed,
            "totalTriggers" : total,
            "evidenceDates" : sorted(dates),
            "patternType"   : "same_entry",
        }

    # ─────────────────────────────────────────
    # VALIDATE CROSS ENTRY PATTERN
    # ─────────────────────────────────────────

    def validate_cross_entry(
        self,
        entries: list,
        trigger_category: str,
        trigger_time_period: str,
        trigger_with_whom: str,
        outcome_field: str,
        outcome_value: str,
        max_gap_hours: int = MAX_TIME_GAP_HOURS,
        specific_person: str = "",
    ):
        """
        DFS walks NEXT_ENTRY chain forward
        from each trigger entry and checks
        if outcome appears within time window.
        Detects cross-entry patterns like
        Play Night -> next morning Headache.
        """
        total     = 0
        confirmed = 0
        dates     = []

        for i, entry in enumerate(entries):
            cat    = str(entry.get("activityCategory", "")).strip()
            period = str(entry.get("timePeriod",       "")).strip()
            whom   = str(entry.get("withWhom",          "")).strip()
            person = str(entry.get("specificPerson",    "")).strip()

            if trigger_category    and cat    != trigger_category:    continue
            if trigger_time_period and period != trigger_time_period: continue
            if trigger_with_whom   and whom   != trigger_with_whom:   continue
            if specific_person     and person != specific_person:     continue

            total += 1
            trigger_dt = entry.get("entryDateTime", "")

            # Walk forward through next entries
            for j in range(i + 1, len(entries)):
                next_entry = entries[j]
                next_dt    = next_entry.get("entryDateTime", "")
                gap        = self._get_hour_gap(trigger_dt, next_dt)

                if gap > max_gap_hours:
                    break  # Too far — stop

                value = str(next_entry.get(outcome_field, "")).strip()
                if value == outcome_value:
                    confirmed += 1
                    d = next_entry.get("entryDate", "")
                    if d and d not in dates:
                        dates.append(d)
                    break  # Found — move to next trigger

        score = round(confirmed / total, 4) if total > 0 else 0.0
        print(f"[DFSEngine] Cross-entry {trigger_category}->{outcome_value}: "
              f"{confirmed}/{total} score={score}")

        return {
            "dfsScore"      : score,
            "confirmed"     : confirmed,
            "totalTriggers" : total,
            "evidenceDates" : sorted(dates),
            "patternType"   : "cross_entry",
        }


dfs_engine = DFSEngine()