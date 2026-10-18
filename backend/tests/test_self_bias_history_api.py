"""History endpoints: a limit option, newest-first order, and a 503 (not an
empty list) when Firestore is unreachable.

Firebase and the facial model are replaced with stubs, and `sys.modules` is
restored afterwards so other tests still see the real application package.
"""
import os
import pathlib
import sys
import types

import pytest

BACKEND = pathlib.Path(__file__).resolve().parents[1]
COMP = "app.components.self_bias_identification"


class _Snap:
    def __init__(self, ref, data):
        self.id = ref.i
        self.reference = ref
        self.exists = data is not None
        self._d = data

    def to_dict(self):
        return self._d


class _Ref:
    def __init__(self, store, col, i):
        self.store, self.col, self.i = store, col, i

    def get(self):
        return _Snap(self, self.store.docs.get((self.col, self.i)))

    def set(self, data, **kwargs):
        self.store.docs[(self.col, self.i)] = data

    def delete(self):
        self.store.docs.pop((self.col, self.i), None)


class _Query:
    def __init__(self, store, name, flt=None):
        self.store, self.name, self.flt = store, name, flt

    def document(self, i):
        return _Ref(self.store, self.name, i)

    def where(self, field, op, value):
        return _Query(self.store, self.name, (field, value))

    def limit(self, n):
        return self

    def stream(self):
        if self.store.down:
            raise RuntimeError("firestore unreachable")
        return [
            _Snap(_Ref(self.store, c, i), d)
            for (c, i), d in list(self.store.docs.items())
            if c == self.name and (self.flt is None or d.get(self.flt[0]) == self.flt[1])
        ]

    def add(self, data):
        n = len([k for k in self.store.docs if k[0] == self.name])
        self.store.docs[(self.name, f"{self.name}-{n}")] = data
        return (None, types.SimpleNamespace(id=f"{self.name}-{n}"))


class _Store:
    def __init__(self):
        self.docs = {}
        self.down = False

    def collection(self, name):
        return _Query(self, name)


@pytest.fixture(scope="module")
def api():
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    store = _Store()
    saved = dict(sys.modules)
    pkg = types.ModuleType("app")
    pkg.__path__ = [str(BACKEND / "app")]
    db_mod = types.ModuleType("app.database")
    db_mod.db = store
    face = types.ModuleType(f"{COMP}.services.facial_service")
    face.analyze_facial_expression = lambda image: {"status": "error"}
    sys.modules.update({"app": pkg, "app.database": db_mod, face.__name__: face})
    sys.path.insert(0, str(BACKEND))
    try:
        from app.components.self_bias_identification.routes import bias_routes

        app = FastAPI()
        app.include_router(bias_routes.router, prefix="/api/bias")
        yield TestClient(app), store
    finally:
        sys.path.remove(str(BACKEND))
        # Only the application's own modules are rolled back. Compiled
        # third-party modules (numpy, xgboost) cannot be imported twice.
        for name in list(sys.modules):
            if (name == "app" or name.startswith("app.")) and name not in saved:
                del sys.modules[name]
        for name, module in saved.items():
            if name == "app" or name.startswith("app."):
                sys.modules[name] = module


@pytest.fixture()
def client(api):
    client, store = api
    store.docs.clear()
    store.down = False
    return client, store


def _seed(store, collection, n, user="u1", **extra):
    for i in range(n):
        store.docs[(collection, f"{collection}-{user}-{i}")] = {
            "user_id": user,
            "created_at": f"2026-10-{1 + i // 24:02d}T{i % 24:02d}:00:00+00:00",
            "entry_id": f"ENT_{i}",
            **extra,
        }


def test_history_defaults_to_ten_so_existing_screens_are_unchanged(client):
    c, store = client
    _seed(store, "bias_results", 25)
    assert len(c.get("/api/bias/history/u1").json()["history"]) == 10


def test_history_limit_returns_more(client):
    c, store = client
    _seed(store, "bias_results", 25)
    assert len(c.get("/api/bias/history/u1?limit=20").json()["history"]) == 20
    assert len(c.get("/api/bias/history/u1?limit=200").json()["history"]) == 25


def test_history_is_newest_first(client):
    c, store = client
    _seed(store, "bias_results", 5)
    ids = [h["entry_id"] for h in c.get("/api/bias/history/u1?limit=5").json()["history"]]
    assert ids == ["ENT_4", "ENT_3", "ENT_2", "ENT_1", "ENT_0"]


def test_history_only_returns_that_users_entries(client):
    c, store = client
    _seed(store, "bias_results", 3, user="u1")
    _seed(store, "bias_results", 4, user="someone_else")
    assert len(c.get("/api/bias/history/u1?limit=50").json()["history"]) == 3


@pytest.mark.parametrize("limit", [0, -1, 201, "many"])
def test_history_rejects_a_bad_limit(client, limit):
    c, _ = client
    assert c.get(f"/api/bias/history/u1?limit={limit}").status_code == 422


def test_no_entries_is_an_empty_list_not_an_error(client):
    c, _ = client
    r = c.get("/api/bias/history/u1")
    assert r.status_code == 200 and r.json()["history"] == []


def test_firestore_down_is_a_503_not_an_empty_list(client):
    c, store = client
    store.down = True
    r = c.get("/api/bias/history/u1")
    assert r.status_code == 503
    assert "history" not in r.json()


def test_mood_resets_limit_order_and_failure(client):
    c, store = client
    _seed(store, "mood_resets", 30, condition="breathing")
    assert len(c.get("/api/bias/mood-resets/u1").json()["resets"]) == 20
    assert len(c.get("/api/bias/mood-resets/u1?limit=30").json()["resets"]) == 30
    first = c.get("/api/bias/mood-resets/u1?limit=1").json()["resets"][0]
    assert first["entry_id"] == "ENT_29"
    assert c.get("/api/bias/mood-resets/u1?limit=999").status_code == 422
    store.down = True
    assert c.get("/api/bias/mood-resets/u1").status_code == 503


_FACE = {
    "status": "success", "dominant_emotion": "fear", "confidence": 0.7,
    "stress_indicator": 0.48, "emotion_scores": {"fear": 0.48, "neutral": 0.4},
}


def test_face_check_gives_mood_support_without_bias_or_pas(client):
    c, store = client
    r = c.post("/api/bias/face-check/u1", json={"facial_emotion": _FACE})
    body = r.json()
    assert r.status_code == 200 and body["status"] == "success"
    assert body["entry_id"].startswith("FACE_")
    assert body["mood_support"]["mood"]["state"] == "uneasy"
    assert "pas_score" not in body and "primary_bias" not in body
    assert body["saved"] is True


def test_face_check_is_kept_out_of_bias_history(client):
    c, store = client
    c.post("/api/bias/face-check/u1", json={"facial_emotion": _FACE})
    assert c.get("/api/bias/history/u1").json()["history"] == []
    checks = c.get("/api/bias/face-checks/u1").json()["checks"]
    assert len(checks) == 1 and checks[0]["kind"] == "face_only"


def test_face_check_without_a_usable_face_is_not_saved(client):
    c, store = client
    for facial in (None, {"status": "no_face"}, {"status": "low_light"}):
        r = c.post("/api/bias/face-check/u1", json={"facial_emotion": facial})
        assert r.json()["status"] == "no_face"
    assert c.get("/api/bias/face-checks/u1").json()["checks"] == []


def test_face_check_never_stores_the_photo(client):
    c, store = client
    face = {**_FACE, "cropped_face_base64": "AAAA"}
    c.post("/api/bias/face-check/u1", json={"facial_emotion": face})
    saved = c.get("/api/bias/face-checks/u1").json()["checks"][0]
    assert "cropped_face_base64" not in saved["comparison"]["facial_emotion"]


def test_face_checks_limit_order_and_failure(client):
    c, store = client
    _seed(store, "face_checks", 30, kind="face_only")
    assert len(c.get("/api/bias/face-checks/u1").json()["checks"]) == 20
    assert c.get("/api/bias/face-checks/u1?limit=1").json()["checks"][0]["entry_id"] == "ENT_29"
    assert c.get("/api/bias/face-checks/u1?limit=999").status_code == 422
    store.down = True
    assert c.get("/api/bias/face-checks/u1").status_code == 503


def test_withdrawal_also_deletes_face_checks(client):
    c, store = client
    c.post("/api/bias/face-check/u1", json={"facial_emotion": _FACE})
    r = c.delete("/api/bias/participant/u1/data")
    assert r.json()["deleted"]["face_checks"] == 1
    assert c.get("/api/bias/face-checks/u1").json()["checks"] == []


# ---- one analysis per diary entry, and a note when the entry is old ----

from datetime import datetime, timedelta, timezone


def _diary(store, doc_id="d1", user="u1", hours_ago=1.0):
    ended = datetime.now() - timedelta(hours=hours_ago)
    store.docs[("diaryEntries", doc_id)] = {
        "userId": user,
        "activityName": "Study",
        "activityCategory": "Self-study",
        "entryDate": ended.strftime("%Y-%m-%d"),
        "startTime": (ended - timedelta(hours=1)).strftime("%H:%M"),
        "endTime": ended.strftime("%H:%M"),
        "duration": "1h",
        "locationType": "Library",
        "moodBefore": "normal",
        "moodAfter": "normal",
        "createdAt": datetime.now(timezone.utc),
    }


_SENSORS = {"sensor_data": {
    "social_media_minutes": 5, "entertainment_minutes": 0,
    "verified_educational_minutes": 50, "app_switch_count": 4,
    "actual_location": "Library", "location_match": 1, "calendar_match": -1,
}}


def test_analysis_is_tied_to_the_diary_document(client):
    c, store = client
    _diary(store)
    r = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert r["status"] == "success" and r["source_doc_id"] == "d1"


def test_the_same_diary_entry_is_not_analysed_twice(client):
    c, store = client
    _diary(store)
    first = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    second = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert second["status"] == "already_analyzed"
    assert second["result"]["entry_id"] == first["entry_id"]
    assert len(c.get("/api/bias/history/u1").json()["history"]) == 1


def test_a_new_diary_entry_is_analysed_again(client):
    c, store = client
    _diary(store, "d1", hours_ago=3)
    c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS)
    _diary(store, "d2", hours_ago=1)
    # d2 is the newest entry now (createdAt is later), so it is analysed.
    store.docs[("diaryEntries", "d2")]["createdAt"] = datetime.now(timezone.utc) + timedelta(minutes=1)
    r = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert r["status"] == "success" and r["source_doc_id"] == "d2"
    assert len(c.get("/api/bias/history/u1").json()["history"]) == 2


def test_an_old_entry_is_not_analysed_it_counts_as_no_new_entry(client):
    c, store = client
    _diary(store, "old", hours_ago=30)
    r = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert r["status"] == "no_entry_found" and r["reason"] == "stale"
    assert r["entry_age_hours"] > 6
    # Nothing was stored for it.
    assert c.get("/api/bias/history/u1").json()["history"] == []


def test_a_fresh_entry_is_analysed_and_not_flagged(client):
    c, store = client
    _diary(store, "fresh", hours_ago=1)
    r = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert r["status"] == "success" and r["stale_entry"] is False


def test_the_edge_of_the_window(client):
    c, store = client
    _diary(store, "edge", hours_ago=5.5)
    assert c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()["status"] == "success"
    store.docs.clear()
    _diary(store, "late", hours_ago=6.5)
    assert c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()["status"] == "no_entry_found"


def test_no_entry_at_all_says_why(client):
    c, store = client
    r = c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS).json()
    assert r == {"status": "no_entry_found", "reason": "none"}


def test_entry_age_falls_back_to_when_it_was_saved():
    from app.components.self_bias_identification.services.diary_entry_mapper import entry_age_hours
    created = datetime.now(timezone.utc) - timedelta(hours=10)
    assert 9.9 <= entry_age_hours({"createdAt": created}) <= 10.1
    assert entry_age_hours({}) is None


# ---- the diary status the app asks for before it starts analysing ----

def test_diary_status_says_none_when_there_is_no_entry(client):
    c, store = client
    r = c.get("/api/bias/diary-status/u1").json()
    assert r["state"] == "none" and r["entry_age_hours"] is None


def test_diary_status_says_new_for_a_fresh_entry(client):
    c, store = client
    _diary(store, hours_ago=1)
    assert c.get("/api/bias/diary-status/u1").json()["state"] == "new"


def test_diary_status_says_stale_for_an_old_entry(client):
    c, store = client
    _diary(store, hours_ago=30)
    r = c.get("/api/bias/diary-status/u1").json()
    assert r["state"] == "stale" and r["entry_age_hours"] > 6


def test_diary_status_says_analyzed_once_it_was_analysed(client):
    c, store = client
    _diary(store, hours_ago=1)
    c.post("/api/bias/analyze-from-diary/u1", json=_SENSORS)
    assert c.get("/api/bias/diary-status/u1").json()["state"] == "analyzed"


def test_diary_status_does_not_analyse_or_store_anything(client):
    c, store = client
    _diary(store, hours_ago=1)
    for _ in range(3):
        c.get("/api/bias/diary-status/u1")
    assert c.get("/api/bias/history/u1").json()["history"] == []


def test_diary_status_only_looks_at_that_users_entries(client):
    c, store = client
    _diary(store, "mine", user="u1", hours_ago=1)
    assert c.get("/api/bias/diary-status/someone_else").json()["state"] == "none"
