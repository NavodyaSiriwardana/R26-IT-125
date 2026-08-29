import firebase_admin
from firebase_admin import firestore
import os
import sys

sys.path.append(os.path.join(
    os.path.dirname(__file__),
    '..', '..', '..', '..'
))

from app.database import db
from datetime import datetime, timezone


class FirebaseService:

    def save_diary_entry(self, diary_entry: dict) -> str:
        try:
            data = {
                **diary_entry,
                "created_at": datetime.utcnow().isoformat(),
            }
            entry_id = diary_entry.get("entry_id")
            if entry_id:
                db.collection("manual_diary_entries").document(entry_id).set(data)
                return entry_id
            else:
                doc_ref = db.collection("manual_diary_entries").add(data)
                return doc_ref[1].id
        except Exception as e:
            return f"ERROR: {str(e)}"

    def save_sensor_data(self, sensor_data: dict) -> str:
        try:
            data = {
                **sensor_data,
                "created_at": datetime.utcnow().isoformat(),
            }
            entry_id = sensor_data.get("entry_id")
            if entry_id:
                db.collection("auto_sensor_data").document(entry_id).set(data)
                return entry_id
            else:
                doc_ref = db.collection("auto_sensor_data").add(data)
                return doc_ref[1].id
        except Exception as e:
            return f"ERROR: {str(e)}"

    def save_bias_result(self, result: dict) -> str:
        try:
            data = {
                **result,
                "created_at": datetime.utcnow().isoformat(),
            }
            doc_ref = db.collection("bias_results").add(data)
            doc_id = doc_ref[1].id
            print(f"Saved to Firebase: {doc_id}", flush=True)
            return doc_id
        except Exception as e:
            print(f"Firebase save error: {e}", flush=True)
            return ""

    def get_user_history(
        self, user_id: str, limit: int = 10
    ) -> list:
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(limit)
                .stream()
            )
            return [
                {"id": doc.id, **doc.to_dict()}
                for doc in docs
            ]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return []

    def get_recent_history(self, user_id: str, limit: int = 5) -> list:
        """Same `bias_results` data as get_user_history, but sorted
        newest-first in Python. Firestore would need a composite index
        for a where(user_id) + order_by(created_at) query, which this
        project's Firestore instance doesn't have provisioned, so the
        ordering is done client-side over a capped unordered fetch."""
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(50)
                .stream()
            )
            results = [{"id": doc.id, **doc.to_dict()} for doc in docs]
            results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            return results[:limit]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return []

    def get_latest_diary_entry(self, user_id: str) -> dict | None:
        """Fetches the most recent entry from the team's shared
        `diaryEntries` collection (owned by the group leader's component,
        camelCase schema) for this user_id. No order_by — same reasoning
        as get_recent_history: avoids needing a Firestore composite index
        this project doesn't have, sorts newest-first in Python instead."""
        try:
            docs = (
                db.collection("diaryEntries")
                .where("userId", "==", user_id)
                .limit(50)
                .stream()
            )
            results = [doc.to_dict() for doc in docs]
            if not results:
                return None
            # createdAt is a Firestore Timestamp (-> datetime) on the
            # leader's side, not a string like our own created_at — sort
            # with a tz-aware epoch fallback so a missing field can't
            # crash the comparison against real datetimes.
            epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
            results.sort(key=lambda r: r.get("createdAt") or epoch, reverse=True)
            return results[0]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return None

    def create_test_diary_entry(self, entry: dict) -> str:
        """Writes a document into the shared `diaryEntries` collection in
        the leader's own schema (camelCase) — used only by the frontend's
        Test Entry screen to generate real diaryEntries documents without
        needing the leader's separate app/codebase to test the
        analyze-from-diary integration end to end."""
        try:
            data = {
                **entry,
                "createdAt": datetime.now(timezone.utc),
            }
            doc_ref = db.collection("diaryEntries").add(data)
            return doc_ref[1].id
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return ""

    def get_user_locations(self, user_id: str) -> dict:
        try:
            doc = db.collection("user_locations").document(user_id).get()
            if not doc.exists:
                return {}
            return doc.to_dict().get("locations", {})
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return {}

    def save_location(
        self, user_id: str, name: str, lat: float, lng: float, radius_m: float
    ) -> None:
        db.collection("user_locations").document(user_id).set(
            {"locations": {name: {"lat": lat, "lng": lng, "radius_m": radius_m}}},
            merge=True,
        )

    def delete_location(self, user_id: str, name: str) -> None:
        db.collection("user_locations").document(user_id).update(
            {f"locations.{name}": firestore.DELETE_FIELD}
        )

    def get_weekly_summary(self, user_id: str) -> dict:
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(21)
                .stream()
            )
            results = [doc.to_dict() for doc in docs]
            if not results:
                return {
                    "avg_pas": 0,
                    "total_entries": 0,
                    "user_id": user_id
                }
            avg_pas = sum(
                r.get("pas_score", 0) for r in results
            ) / len(results)
            return {
                "avg_pas": round(avg_pas, 1),
                "total_entries": len(results),
                "user_id": user_id,
            }
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return {}