import firebase_admin
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
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            entry_id = diary_entry.get("entry_id")
            if entry_id:
                db.collection("manual_diary_entries").document(entry_id).set(data)
                return entry_id
            else:
                doc_ref = db.collection("manual_diary_entries").add(data)
                return doc_ref[1].id
        except Exception as e:
            print(f"Firebase save error (diary entry): {e}", flush=True)
            return ""

    def save_sensor_data(self, sensor_data: dict) -> str:
        try:
            data = {
                **sensor_data,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            entry_id = sensor_data.get("entry_id")
            if entry_id:
                db.collection("auto_sensor_data").document(entry_id).set(data)
                return entry_id
            else:
                doc_ref = db.collection("auto_sensor_data").add(data)
                return doc_ref[1].id
        except Exception as e:
            print(f"Firebase save error (sensor data): {e}", flush=True)
            return ""

    def save_bias_result(self, result: dict) -> str:
        try:
            data = {
                **result,
                "created_at": datetime.now(timezone.utc).isoformat(),
            }
            doc_ref = db.collection("bias_results").add(data)
            doc_id = doc_ref[1].id
            print(f"Saved to Firebase: {doc_id}", flush=True)
            return doc_id
        except Exception as e:
            print(f"Firebase save error: {e}", flush=True)
            return ""

    @staticmethod
    def _strip_face_image(doc: dict) -> dict:
        """Drops the base64-encoded cropped-face image from a bias_results
        doc before it goes into a bulk list response. Nothing on the
        history/all-entries list screens renders it (only the live capture
        screen does, from its own API response) — left in, every list
        fetch balloons to hundreds of KB per entry and, over a slow link,
        risks the request failing entirely and the list rendering empty."""
        facial_emotion = doc.get("comparison", {}).get("facial_emotion")
        if isinstance(facial_emotion, dict) and "cropped_face_base64" in facial_emotion:
            facial_emotion = {**facial_emotion}
            facial_emotion.pop("cropped_face_base64", None)
            doc = {**doc, "comparison": {**doc["comparison"], "facial_emotion": facial_emotion}}
        return doc

    def get_user_history(
        self, user_id: str, limit: int = 10, strict: bool = False
    ) -> list:
        """Newest-first. With strict=True a Firestore failure is raised
        instead of returned as an empty list, so a caller can tell "no
        entries" from "could not load"."""
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(200)
                .stream()
            )
            results = [
                self._strip_face_image({"id": doc.id, **doc.to_dict()})
                for doc in docs
            ]
            results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            return results[:limit]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            if strict:
                raise
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
            results = [
                self._strip_face_image({"id": doc.id, **doc.to_dict()})
                for doc in docs
            ]
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
            # The document id is kept (as `_doc_id`) so an analysis can be tied
            # to the exact diary entry it was made from.
            results = [{**doc.to_dict(), "_doc_id": doc.id} for doc in docs]
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

    def find_result_for_diary_entry(self, user_id: str, source_doc_id: str) -> dict | None:
        """The saved analysis made from this exact diary document, if any, so
        the same entry is not analysed (and stored) twice."""
        if not source_doc_id:
            return None
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(300)
                .stream()
            )
            matches = [
                {"id": doc.id, **doc.to_dict()}
                for doc in docs
                if doc.to_dict().get("source_doc_id") == source_doc_id
            ]
            if not matches:
                return None
            matches.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            return matches[0]
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

    def save_mood_reset(self, reset: dict) -> str:
        try:
            data = {**reset, "created_at": datetime.now(timezone.utc).isoformat()}
            doc_ref = db.collection("mood_resets").add(data)
            return doc_ref[1].id
        except Exception as e:
            print(f"Firebase save error: {e}", flush=True)
            return ""

    def get_mood_resets(
        self, user_id: str, limit: int = 20, strict: bool = False
    ) -> list:
        """Newest-first, sorted in Python (no composite index provisioned).
        strict=True raises on a Firestore failure instead of returning []."""
        try:
            docs = (
                db.collection("mood_resets")
                .where("user_id", "==", user_id)
                .limit(300)
                .stream()
            )
            results = [{"id": doc.id, **doc.to_dict()} for doc in docs]
            results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            return results[:limit]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            if strict:
                raise
            return []

    def save_face_check(self, check: dict) -> str:
        """A camera scan taken with no diary entry to compare against. Kept in
        its own collection so it never counts towards bias history or PAS."""
        try:
            data = {**check, "created_at": datetime.now(timezone.utc).isoformat()}
            doc_ref = db.collection("face_checks").add(data)
            return doc_ref[1].id
        except Exception as e:
            print(f"Firebase save error (face check): {e}", flush=True)
            return ""

    def get_face_checks(
        self, user_id: str, limit: int = 20, strict: bool = False
    ) -> list:
        """Newest-first, sorted in Python (no composite index provisioned).
        strict=True raises on a Firestore failure instead of returning []."""
        try:
            docs = (
                db.collection("face_checks")
                .where("user_id", "==", user_id)
                .limit(300)
                .stream()
            )
            results = [{"id": doc.id, **doc.to_dict()} for doc in docs]
            results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            return results[:limit]
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            if strict:
                raise
            return []

    def save_consent(self, user_id: str, agreed: bool, version: str,
                     study_mode: bool) -> bool:
        try:
            db.collection("consents").document(user_id).set({
                "user_id": user_id,
                "agreed": agreed,
                "version": version,
                "study_mode": study_mode,
                "recorded_at": datetime.now(timezone.utc).isoformat(),
            })
            return True
        except Exception as e:
            print(f"Firebase save error (consent): {e}", flush=True)
            return False

    def get_consent(self, user_id: str) -> dict | None:
        try:
            doc = db.collection("consents").document(user_id).get()
            return doc.to_dict() if doc.exists else None
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return None

    # Collections this component owns, keyed by a `user_id` field. The shared
    # `diaryEntries` collection belongs to the group leader's component and is
    # deliberately NOT touched here.
    OWNED_BY_USER_ID_FIELD = (
        "bias_results", "manual_diary_entries", "auto_sensor_data", "mood_resets",
        "face_checks", "entry_locations",
    )
    OWNED_BY_DOC_ID = ("consents", "user_locations")

    def delete_user_data(self, user_id: str) -> dict:
        """Withdraws a participant: removes everything this component stored
        about them. Returns how many documents were deleted per collection."""
        deleted = {}
        for name in self.OWNED_BY_USER_ID_FIELD:
            count = 0
            for doc in db.collection(name).where("user_id", "==", user_id).stream():
                doc.reference.delete()
                count += 1
            deleted[name] = count
        for name in self.OWNED_BY_DOC_ID:
            ref = db.collection(name).document(user_id)
            if ref.get().exists:
                ref.delete()
                deleted[name] = 1
            else:
                deleted[name] = 0
        return deleted

    def save_entry_location(self, user_id: str, doc_id: str, data: dict) -> bool:
        """Where the phone was when one diary entry was written. The first
        capture for an entry is kept: a second one would be taken later, further
        from the activity."""
        try:
            ref = db.collection("entry_locations").document(f"{user_id}__{doc_id}")
            if ref.get().exists:
                return True
            ref.set({
                **data,
                "user_id": user_id,
                "source_doc_id": doc_id,
                "created_at": datetime.now(timezone.utc).isoformat(),
            })
            return True
        except Exception as e:
            print(f"Firebase save error (entry location): {e}", flush=True)
            return False

    def get_entry_location(self, user_id: str, doc_id: str) -> dict | None:
        if not doc_id:
            return None
        try:
            doc = db.collection("entry_locations").document(f"{user_id}__{doc_id}").get()
            return doc.to_dict() if doc.exists else None
        except Exception as e:
            print(f"Firebase error: {e}", flush=True)
            return None

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
        # Not update({"locations.<name>": DELETE_FIELD}): Firestore splits that
        # path on every "." so a name like "Home.Study" would never match.
        ref = db.collection("user_locations").document(user_id)
        doc = ref.get()
        if not doc.exists:
            return
        locations = doc.to_dict().get("locations", {})
        if name in locations:
            del locations[name]
            ref.set({"locations": locations})

    def get_weekly_summary(self, user_id: str) -> dict:
        try:
            docs = (
                db.collection("bias_results")
                .where("user_id", "==", user_id)
                .limit(200)
                .stream()
            )
            results = [doc.to_dict() for doc in docs]
            results.sort(key=lambda r: r.get("created_at", ""), reverse=True)
            results = results[:21]
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