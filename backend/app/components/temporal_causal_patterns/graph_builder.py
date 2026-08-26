from datetime import datetime, timezone
from uuid import uuid4
from app.database import neo4j_conn
from app.components.temporal_causal_patterns.cypher_queries import (
    CREATE_USER_CONSTRAINT,
    CREATE_ENTRY_CONSTRAINT,
    CREATE_ENTRY_DATETIME_INDEX,
    CREATE_MOOD_INDEX,
    CREATE_CATEGORY_INDEX,
    CREATE_PERSON_INDEX,
    MERGE_USER_NODE,
    CREATE_DIARY_ENTRY,
    MERGE_ACTIVITY_CATEGORY,
    MERGE_SOCIAL_CONTEXT,
    MERGE_MOOD_BEFORE,
    MERGE_MOOD_AFTER,
    MERGE_PRODUCTIVITY,
    MERGE_HEALTH_STATUS,
    MERGE_TASK_OUTCOME,
    MERGE_SPECIFIC_PERSON,
    DELETE_USER_NEXT_ENTRY,
    GET_USER_ENTRIES_ORDERED,
    CREATE_NEXT_ENTRY_LINK,
    FETCH_USER_DIARY_DATA,
    CREATE_PATTERN_INSIGHT,
    LINK_USER_TO_PATTERN,
    LINK_PATTERN_TO_EVIDENCE,
    FETCH_USER_PATTERNS,
)


def get_now():
    return datetime.now(timezone.utc).isoformat()


class GraphBuilder:

    # ─────────────────────────────────────────
    # SCHEMA SETUP
    # ─────────────────────────────────────────

    def setup_schema(self):
        queries = [
            CREATE_USER_CONSTRAINT,
            CREATE_ENTRY_CONSTRAINT,
            CREATE_ENTRY_DATETIME_INDEX,
            CREATE_MOOD_INDEX,
            CREATE_CATEGORY_INDEX,
            CREATE_PERSON_INDEX,
        ]
        with neo4j_conn.get_session() as session:
            for query in queries:
                session.run(query)
        print("[GraphBuilder] Schema setup complete")
        return {"status": "Schema setup complete"}

    # ─────────────────────────────────────────
    # INSERT DIARY ENTRY
    # ─────────────────────────────────────────

    def insert_diary_entry(self, data: dict):
        now        = get_now()
        entry_id   = str(uuid4())
        user_id    = data["userId"]

        entry_datetime = f"{data['entryDate']}T{data['startTime']}:00+00:00"

        with neo4j_conn.get_session() as session:

            # Step 1 — merge user node
            session.run(MERGE_USER_NODE, {
                "userId"    : user_id,
                "createdAt" : now,
                "source"    : "diary_template",
                "version"   : 1,
            })

            # Step 2 — create diary entry node
            session.run(CREATE_DIARY_ENTRY, {
                "entryId"        : entry_id,
                "userId"         : user_id,
                "activityName"   : data.get("activityName", ""),
                "entryDate"      : data["entryDate"],
                "startTime"      : data["startTime"],
                "endTime"        : data.get("endTime", ""),
                "timePeriod"     : data.get("timePeriod", ""),
                "duration"       : data.get("duration", ""),
                "locationType"   : data.get("locationType", ""),
                "customLocation" : data.get("customLocation", ""),
                "specificPerson" : data.get("specificPerson", ""),
                "notes"          : data.get("notes", ""),
                "entryDateTime"  : entry_datetime,
                "createdAt"      : now,
                "updatedAt"      : now,
                "version"        : 1,
                "source"         : "diary_template",
            })

            # Step 3 — merge shared nodes with edge metadata
            edge_meta = {
                "entryId"      : entry_id,
                "userId"       : user_id,
                "entryDateTime": entry_datetime,
                "createdAt"    : now,
                "version"      : 1,
                "source"       : "diary_template",
            }

            session.run(MERGE_ACTIVITY_CATEGORY, {
                **edge_meta,
                "activityCategory": data.get("activityCategory", ""),
            })

            session.run(MERGE_SOCIAL_CONTEXT, {
                **edge_meta,
                "withWhom": data.get("withWhom", ""),
            })

            session.run(MERGE_MOOD_BEFORE, {
                **edge_meta,
                "moodBefore": data.get("moodBefore", ""),
            })

            session.run(MERGE_MOOD_AFTER, {
                **edge_meta,
                "moodAfter": data.get("moodAfter", ""),
            })

            session.run(MERGE_PRODUCTIVITY, {
                **edge_meta,
                "productivityLevel": data.get("productivityLevel", ""),
            })

            session.run(MERGE_HEALTH_STATUS, {
                **edge_meta,
                "healthStatus": data.get("healthStatus", ""),
            })

            session.run(MERGE_TASK_OUTCOME, {
                **edge_meta,
                "taskOutcome": data.get("taskOutcome", ""),
            })

            # Step 3b — merge specific person only if provided
            specific_person = data.get("specificPerson", "")
            if specific_person:
                session.run(MERGE_SPECIFIC_PERSON, {
                    **edge_meta,
                    "specificPerson": specific_person,
                })

        # Step 4 — rebuild NEXT_ENTRY chain
        self._rebuild_next_entry_chain(user_id)

        print(f"[GraphBuilder] Entry inserted — entryId: {entry_id}")
        return {"entryId": entry_id, "userId": user_id, "status": "inserted"}

    # ─────────────────────────────────────────
    # NEXT_ENTRY CHAIN
    # ─────────────────────────────────────────

    def _rebuild_next_entry_chain(self, user_id: str):
        now = get_now()

        with neo4j_conn.get_session() as session:

            # Delete existing NEXT_ENTRY links for this user
            session.run(DELETE_USER_NEXT_ENTRY, {"userId": user_id})

            # Fetch all entries ordered by entryDateTime
            result = session.run(
                GET_USER_ENTRIES_ORDERED,
                {"userId": user_id}
            )
            entries = [record.data() for record in result]

            # Create NEXT_ENTRY links in time order
            for i in range(len(entries) - 1):
                current = entries[i]
                next_e  = entries[i + 1]

                session.run(CREATE_NEXT_ENTRY_LINK, {
                    "fromEntryId"  : current["entryId"],
                    "toEntryId"    : next_e["entryId"],
                    "userId"       : user_id,
                    "fromDateTime" : current["entryDateTime"],
                    "toDateTime"   : next_e["entryDateTime"],
                    "createdAt"    : now,
                    "version"      : 1,
                    "source"       : "diary_template",
                })

        print(f"[GraphBuilder] NEXT_ENTRY chain rebuilt — {len(entries)} entries")

    # ─────────────────────────────────────────
    # FETCH DIARY DATA FOR PATTERN ENGINE
    # ─────────────────────────────────────────

    def fetch_user_diary_data(self, user_id: str):
        from app.components.temporal_causal_patterns.cypher_queries import (
            FETCH_USER_DIARY_DATA,
        )
        with neo4j_conn.get_session() as session:
            result = session.run(
                FETCH_USER_DIARY_DATA,
                {"userId": user_id}
            )
            entries = [record.data() for record in result]

        print(f"[GraphBuilder] Fetched {len(entries)} entries for user {user_id}")
        return entries

    # ─────────────────────────────────────────
    # SAVE PATTERN INSIGHTS TO GRAPH
    # ─────────────────────────────────────────

    def save_pattern_insights(
        self,
        user_id: str,
        patterns: list
    ):
        """
        Save detected patterns as PatternInsight
        nodes in AuraDB with full traceability.
        Each pattern links back to evidence
        diary entries via SUPPORTED_BY edges.
        """
        from uuid import uuid4
        now = get_now()

        saved_count = 0

        with neo4j_conn.get_session() as session:
            for pattern in patterns:

                # Generate unique pattern ID
                pattern_id = str(uuid4())

                # Create PatternInsight node
                session.run(CREATE_PATTERN_INSIGHT, {
                    "patternId"            : pattern_id,
                    "userId"               : user_id,
                    "insightText"          : pattern["insightText"],
                    "trigger"              : pattern["trigger"],
                    "outcome"              : pattern["outcome"],
                    "matchedCount"         : pattern["matchedCount"],
                    "totalTriggerCount"    : pattern["totalTriggerCount"],
                    "confidencePercentage" : pattern["confidencePercentage"],
                    "patternLevel"         : pattern["patternLevel"],
                    "createdAt"            : now,
                    "version"              : 1,
                })

                # Link User → HAS_PATTERN → PatternInsight
                session.run(LINK_USER_TO_PATTERN, {
                    "userId"    : user_id,
                    "patternId" : pattern_id,
                    "createdAt" : now,
                    "version"   : 1,
                })

                # Link PatternInsight → SUPPORTED_BY → DiaryEntry
                for evidence_date in pattern.get("evidenceDates", []):
                    session.run(LINK_PATTERN_TO_EVIDENCE, {
                        "patternId" : pattern_id,
                        "userId"    : user_id,
                        "entryDate" : evidence_date,
                        "createdAt" : now,
                        "version"   : 1,
                    })

                saved_count += 1

        print(f"[GraphBuilder] Saved {saved_count} pattern insights for user {user_id}")
        return saved_count

    # ─────────────────────────────────────────
    # FETCH SAVED PATTERNS FROM GRAPH
    # ─────────────────────────────────────────

    def fetch_user_patterns(self, user_id: str):
        """
        Fetch all saved PatternInsight nodes
        for a specific user from AuraDB.
        """
        with neo4j_conn.get_session() as session:
            result = session.run(
                FETCH_USER_PATTERNS,
                {"userId": user_id}
            )
            patterns = [record.data() for record in result]

        print(f"[GraphBuilder] Fetched {len(patterns)} saved patterns for user {user_id}")
        return patterns     


graph_builder = GraphBuilder()