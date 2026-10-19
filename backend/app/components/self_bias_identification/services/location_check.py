"""Checks the place a student claimed against where the phone was when the diary
entry was written, without the student saving any places by hand.

The app captures the phone's position (and the kinds of places around it) right
after the student writes an entry. This module turns that capture into one of
three results: the claim matches, the claim differs, or it cannot be checked.
It never turns "cannot check" into "differs": that is what keeps an honest
student from being flagged.

Kept free of Firestore and the web framework so it is cheap to test.
"""
import math

# The entry must be written close to when the activity ended, otherwise the
# phone's position at that time says nothing about where the activity was.
LOCATION_WINDOW_HOURS = 0.5

# Place types (Google Places) that fit each place a diary entry can claim.
_CAMPUS_TYPES = {"university", "school", "secondary_school", "primary_school"}
CLAIM_TYPES = {
    "library": {"library"} | _CAMPUS_TYPES,
    "lecture hall": set(_CAMPUS_TYPES),
    "lab": set(_CAMPUS_TYPES),
    "cafe": {"cafe", "restaurant", "bakery", "meal_takeaway", "food"},
}
# A claim of being at home is wrong if the phone was on a campus.
_NOT_HOME_TYPES = _CAMPUS_TYPES | {"library"}

# What the app shows for each reason code.
REASONS = {
    "saved_place": "matched a place the student saved",
    "nearby_places": "matched the kinds of places nearby",
    "late_entry": "the entry was written too long after the activity",
    "no_capture": "no location was captured for this entry",
    "no_claim": "the entry gives no place that can be checked",
    "no_place_data": "no named place was found near the phone",
    "cannot_verify_home": "a home claim cannot be checked from the map",
}


def _norm(text) -> str:
    return (text or "").strip().lower()


def distance_meters(lat1, lng1, lat2, lng2) -> float:
    """Haversine distance in metres."""
    radius = 6371000.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    a = (math.sin(d_lat / 2) ** 2
         + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2))
         * math.sin(d_lng / 2) ** 2)
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _result(checked, match, reason, source, evidence=None, label=""):
    evidence = evidence or {}
    return {
        "checked": checked,
        "match": match,
        "reason": reason,
        "source": source,
        "label": label,
        "lat": evidence.get("lat"),
        "lng": evidence.get("lng"),
        "place_name": evidence.get("place_name") or "",
        "place_types": list(evidence.get("place_types") or []),
        "captured_at": evidence.get("captured_at") or "",
        "accuracy_m": evidence.get("accuracy_m"),
        "age_at_capture_hours": evidence.get("age_at_capture_hours"),
    }


def saved_place_at(evidence, saved_places):
    """The saved place (by name) whose radius holds the captured position, the
    nearest one if several do. None when there is none."""
    if not saved_places or evidence.get("lat") is None or evidence.get("lng") is None:
        return None
    best, best_dist = None, float("inf")
    for name, spot in saved_places.items():
        try:
            dist = distance_meters(
                float(evidence["lat"]), float(evidence["lng"]),
                float(spot["lat"]), float(spot["lng"]),
            )
            radius = float(spot.get("radius_m", 80))
        except (KeyError, TypeError, ValueError):
            continue
        if dist <= radius and dist < best_dist:
            best, best_dist = name, dist
    return best


def evaluate(claimed, evidence, saved_places=None) -> dict:
    """Result of comparing [claimed] (the place type the student chose) with the
    captured [evidence] dict: lat, lng, accuracy_m, place_name, place_types,
    captured_at and age_at_capture_hours (how long after the activity ended the
    position was captured)."""
    claim = _norm(claimed)
    if not claim or claim == "other":
        return _result(False, False, "no_claim", "none", evidence)
    if not evidence:
        return _result(False, False, "no_capture", "none")

    age = evidence.get("age_at_capture_hours")
    if age is not None and age > LOCATION_WINDOW_HOURS:
        return _result(False, False, "late_entry", "none", evidence)

    # A place the student saved is the most precise answer there is.
    saved = saved_place_at(evidence, saved_places)
    if saved:
        return _result(True, _norm(saved) == claim, "saved_place",
                       "saved_place", evidence, label=saved)

    types = {_norm(t) for t in (evidence.get("place_types") or [])}
    name = evidence.get("place_name") or ""

    if claim == "home":
        if types & _NOT_HOME_TYPES:
            return _result(True, False, "nearby_places", "nearby_places",
                           evidence, label=name or "Campus")
        return _result(False, False, "cannot_verify_home", "none", evidence)

    wanted = CLAIM_TYPES.get(claim)
    if wanted is None:
        # A custom place name the map cannot reason about.
        return _result(False, False, "no_claim", "none", evidence)
    if not types:
        return _result(False, False, "no_place_data", "none", evidence)

    hit = types & wanted
    if hit:
        return _result(True, True, "nearby_places", "nearby_places",
                       evidence, label=name or sorted(hit)[0].title())
    # Places were found nearby but none fits the claim.
    other = name or sorted(types)[0].replace("_", " ").title()
    return _result(True, False, "nearby_places", "nearby_places",
                   evidence, label=other)
