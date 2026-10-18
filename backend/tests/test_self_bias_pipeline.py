"""Tests for the self-bias component's comparator, PAS, rules, reflection and
photo-quality gates.

Modules are loaded straight from their files: importing through the `app`
package would open Firebase and Neo4j connections.
"""
import importlib.util
import pathlib

import numpy as np
import pytest
from PIL import Image

COMP = pathlib.Path(__file__).resolve().parents[1] / "app" / "components" / "self_bias_identification"


def _load(name: str, rel: str):
    spec = importlib.util.spec_from_file_location(name, COMP / rel)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


comparator_mod = _load("sb_comparator", "services/comparator.py")
pas_mod = _load("sb_pas", "services/pas_calculator.py")
reflection_mod = _load("sb_reflection", "services/reflection_bot.py")
quality = _load("sb_quality", "services/image_quality.py")

CALM = {"status": "success", "confidence": 0.8, "dominant_emotion": "neutral",
        "stress_indicator": 0.08, "emotion_scores": {"neutral": 0.8}}
STRESSED = {"status": "success", "confidence": 0.8, "dominant_emotion": "sad",
            "stress_indicator": 0.62, "emotion_scores": {"sad": 0.4}}


def entry(cat="Self-study", dur=60, loc="Home", mb="motivated", ma="motivated"):
    return {"activity_category": cat, "claimed_duration_minutes": dur,
            "claimed_location": loc, "mood_before": mb, "mood_after": ma}


def sensor(edu=55, social=5, sw=8, gps="Home", cal=1, face=CALM):
    return {"verified_educational_minutes": edu, "social_media_minutes": social,
            "app_switch_count": sw, "gps_location": gps, "calendar_match": cal,
            "facial_emotion": face}


def compare(d, s):
    return comparator_mod.MultiSignalComparator().compare(d, s)


# ---------------------------------------------------------------- comparator

@pytest.mark.parametrize("raw", [-1, None])
def test_calendar_not_checked_is_not_a_mismatch(raw):
    f = compare(entry(), sensor(cal=raw))["features"]
    assert f["calendar_checked"] is False
    assert f["calendar_match"] == 1


def test_calendar_missing_key_is_not_checked():
    s = sensor()
    del s["calendar_match"]
    assert compare(entry(), s)["features"]["calendar_checked"] is False


def test_calendar_checked_with_no_event_is_a_mismatch():
    f = compare(entry(), sensor(cal=0))["features"]
    assert f["calendar_checked"] is True and f["calendar_match"] == 0


@pytest.mark.parametrize("gps", ["Unknown", "unknown", "", None])
def test_unknown_gps_is_not_a_location_mismatch(gps):
    f = compare(entry(), sensor(gps=gps))["features"]
    assert f["location_checked"] is False
    assert f["location_match"] == 1


def test_location_comparison_ignores_case_and_whitespace():
    f = compare(entry(loc="home"), sensor(gps="Home "))["features"]
    assert f["location_checked"] is True and f["location_match"] == 1


def test_different_known_location_is_a_mismatch():
    f = compare(entry(loc="Library"), sensor(gps="Home"))["features"]
    assert f["location_checked"] is True and f["location_match"] == 0


def test_empty_claimed_location_is_not_checked():
    assert compare(entry(loc=""), sensor())["features"]["location_checked"] is False


def test_zero_minute_claim_is_not_scored():
    f = compare(entry(dur=0), sensor(edu=0))["features"]
    assert f["duration_checked"] is False
    assert f["duration_match_ratio"] == 1.0 and f["duration_gap"] == 0


def test_non_study_category_skips_duration_and_activity():
    f = compare(entry("Play", 90, "Playground"), sensor(0, 0, 5, "Playground"))["features"]
    assert f["duration_checked"] is False and f["activity_checked"] is False


def test_honest_tired_report_is_not_stress_underestimation():
    c = compare(entry(mb="normal", ma="tired"), sensor(face=STRESSED))
    assert c["features"]["stress_mismatch"] == 0
    assert c["comparison"]["mood_declined"] is True


def test_stress_hidden_behind_positive_mood_is_underestimation():
    f = compare(entry(ma="motivated"), sensor(face=STRESSED))["features"]
    assert f["stress_checked"] is True and f["stress_mismatch"] == 1


def test_mood_decline_alone_is_not_a_mismatch_without_face_evidence():
    f = compare(entry(mb="normal", ma="tired"), sensor(face=CALM))["features"]
    assert f["stress_mismatch"] == 0


def test_no_usable_photo_means_stress_not_checked():
    f = compare(entry(), sensor(face={"status": "no_face_detected"}))["features"]
    assert f["stress_checked"] is False and f["stress_mismatch"] == 0 and f["facial_stress"] == 0


# ----------------------------------------------------------------------- PAS

def pas(d, s):
    out = compare(d, s)
    return pas_mod.PASCalculator().calculate(out["features"], d["claimed_duration_minutes"])


def test_weights_sum_to_one():
    assert sum(pas_mod.PASCalculator.WEIGHTS.values()) == pytest.approx(1.0)


def test_honest_session_scores_high():
    assert pas(entry(), sensor())["pas_score"] >= 85


def test_unchecked_calendar_does_not_change_the_score_of_a_clean_entry():
    with_cal = pas(entry(), sensor(cal=1))["pas_score"]
    without = pas(entry(), sensor(cal=-1))["pas_score"]
    assert abs(with_cal - without) <= 1


def test_unchecked_calendar_scores_better_than_a_failed_check():
    assert pas(entry(), sensor(cal=-1))["pas_score"] > pas(entry(), sensor(cal=0))["pas_score"]


def test_unknown_location_does_not_lower_pas():
    known = pas(entry(), sensor(gps="Home"))["pas_score"]
    unknown = pas(entry(), sensor(gps="Unknown"))["pas_score"]
    assert abs(known - unknown) <= 1
    assert "location" in pas(entry(), sensor(gps="Unknown"))["not_scored"]


def test_hidden_stress_lowers_pas():
    calm = pas(entry(), sensor(face=CALM))["pas_score"]
    hidden = pas(entry(), sensor(face=STRESSED))["pas_score"]
    assert hidden < calm


def test_honestly_reported_stress_does_not_lower_pas():
    calm = pas(entry(ma="motivated"), sensor(face=CALM))["pas_score"]
    honest = pas(entry(ma="stressed"), sensor(face=STRESSED))["pas_score"]
    assert abs(calm - honest) <= 1


def test_zero_minute_claim_is_excluded_not_penalised():
    result = pas(entry(dur=0), sensor(edu=0))
    assert "duration" in result["not_scored"]
    assert result["pas_score"] >= 85


def test_nothing_verifiable_still_gives_a_score():
    d = entry("Play", 0, "")
    result = pas(d, sensor(0, 0, 5, "", -1, {"status": "error"}))
    assert 0 <= result["pas_score"] <= 100


# ---------------------------------------------------------------- reflection

def reflect(bias, pas_score, **comparison):
    return reflection_mod.ReflectionBot().generate(bias, comparison, pas_score, [])["reflection_text"]


def test_praise_only_when_pas_is_high():
    assert "Excellent self-awareness" in reflect("accurate_perception", 92)
    low = reflect("accurate_perception", 52)
    assert "Excellent" not in low and "52/100" in low


def test_very_low_pas_text_does_not_praise():
    assert "Excellent" not in reflect("accurate_perception", 20)


def test_reflection_explains_unscored_signals():
    text = reflect("accurate_perception", 90, location_checked=False,
                   is_study_category=True, duration_checked=False)
    assert "location could not be verified" in text
    assert "no duration" in text


def test_reflection_has_no_note_when_everything_was_checked():
    assert "Note:" not in reflect("accurate_perception", 90, location_checked=True,
                                  is_study_category=True, duration_checked=True)


# ------------------------------------------------------------ photo quality

def _img(array) -> Image.Image:
    return Image.fromarray(np.asarray(array, dtype=np.uint8)).convert("RGB")


def test_dark_photo_is_too_dark_not_blurry_first():
    dark = _img(np.random.default_rng(0).integers(0, 40, (200, 200)))
    assert quality.is_too_dark(dark)


def test_normally_lit_detailed_photo_passes_both_gates():
    lit = _img(np.random.default_rng(1).integers(60, 200, (200, 200)))
    assert not quality.is_too_dark(lit)
    assert not quality.is_image_blurry(lit)


def test_bright_but_flat_photo_is_blurry_not_dark():
    flat = _img(np.full((200, 200), 150))
    assert not quality.is_too_dark(flat)
    assert quality.is_image_blurry(flat)


# ------------------------------------------------- classifier rule indicators

@pytest.fixture(scope="module")
def classifier():
    return _load("sb_classifier", "services/classifier.py").BiasClassifier()


def rules(classifier, d, s):
    out = compare(d, s)
    return classifier.classify_with_rules(
        out["features"], facial_emotion=s["facial_emotion"], mood_after=d["mood_after"]
    )["additional_indicators"]


def types_of(indicators):
    return [i["type"] for i in indicators]


def test_no_schedule_warning_when_calendar_not_checked(classifier):
    assert "schedule_mismatch" not in types_of(rules(classifier, entry(), sensor(cal=-1)))


def test_schedule_warning_when_checked_and_no_event(classifier):
    assert "schedule_mismatch" in types_of(rules(classifier, entry(), sensor(cal=0)))


def test_no_location_warning_when_gps_unknown(classifier):
    assert "context_mismatch" not in types_of(rules(classifier, entry(), sensor(gps="Unknown")))


def test_location_warning_when_known_and_different(classifier):
    assert "context_mismatch" in types_of(rules(classifier, entry(loc="Library"), sensor(gps="Home")))


def test_honest_tired_report_gets_no_stress_warning(classifier):
    found = types_of(rules(classifier, entry(mb="normal", ma="tired"), sensor(face=STRESSED)))
    assert "facial_stress_mismatch" not in found and "stress_underestimation" not in found


def test_hidden_stress_warning_names_the_reported_mood(classifier):
    found = rules(classifier, entry(ma="motivated"), sensor(face=STRESSED))
    warning = next(i for i in found if i["type"] == "facial_stress_mismatch")
    assert "62%" in warning["reason"] and "motivated" in warning["reason"]


# ---- phone photos must be turned the right way up before the face is read ----

def _photo_with_orientation(tag: int, size=(60, 100)) -> Image.Image:
    """A photo as a phone saves it: pixels as the sensor saw them, plus an
    EXIF orientation tag (6 = 'rotate 90 degrees clockwise to view')."""
    import io

    img = Image.new("RGB", size, (200, 200, 200))
    img.paste((255, 0, 0), (0, 0, 10, 10))  # a marker in the top-left corner
    exif = Image.Exif()
    exif[0x0112] = tag
    buffer = io.BytesIO()
    img.save(buffer, format="JPEG", exif=exif)
    return Image.open(io.BytesIO(buffer.getvalue()))


def test_exif_orientation_turns_a_sideways_phone_photo_upright():
    sideways = _photo_with_orientation(6, size=(100, 60))  # landscape pixels
    upright = quality.apply_exif_orientation(sideways)
    assert upright.size == (60, 100)  # now portrait


def test_a_photo_with_no_orientation_tag_is_left_alone():
    plain = Image.new("RGB", (80, 50), (120, 120, 120))
    assert quality.apply_exif_orientation(plain).size == (80, 50)


def test_an_upright_photo_with_tag_one_is_unchanged():
    photo = _photo_with_orientation(1, size=(60, 100))
    assert quality.apply_exif_orientation(photo).size == (60, 100)


class _Marked:
    """Tells the 'detector' which way up a picture is by where a red mark sits."""

    @staticmethod
    def image(top_left_marker: bool) -> Image.Image:
        img = Image.new("RGB", (60, 100), (200, 200, 200))
        img.paste((255, 0, 0), (0, 0, 10, 10))
        return img


def _score_marker_top_left(image: Image.Image) -> float:
    """Pretend detector: 0.9 when the red marker is at the top-left (upright)."""
    arr = np.array(image.convert("RGB"))
    return 0.9 if tuple(arr[2, 2]) == (255, 0, 0) else 0.3


def test_choose_orientation_keeps_an_already_upright_picture():
    img = _Marked.image(True)
    assert quality.choose_orientation(img, _score_marker_top_left) is img


def test_choose_orientation_turns_a_sideways_picture_upright():
    sideways = _Marked.image(True).rotate(270, expand=True)
    fixed = quality.choose_orientation(sideways, _score_marker_top_left)
    assert _score_marker_top_left(fixed) == 0.9
    assert fixed.size == (60, 100)


def test_choose_orientation_handles_upside_down():
    upside = _Marked.image(True).rotate(180, expand=True)
    fixed = quality.choose_orientation(upside, _score_marker_top_left)
    assert _score_marker_top_left(fixed) == 0.9


def test_a_picture_with_no_face_anywhere_is_not_turned():
    img = Image.new("RGB", (60, 100), (90, 90, 90))
    assert quality.choose_orientation(img, lambda i: 0.0) is img


def test_a_tiny_gain_does_not_turn_the_picture():
    img = Image.new("RGB", (60, 100), (90, 90, 90))
    scores = {id(img): 0.80}
    # Any turned copy scores 0.83: better, but not clearly.
    assert quality.choose_orientation(img, lambda i: scores.get(id(i), 0.83)) is img


# ---- an honest "I'm stressed" is not stress underestimation ----

def _bias(classifier, d, s):
    out = compare(d, s)
    return classifier.classify_with_rules(
        out["features"], facial_emotion=s["facial_emotion"], mood_after=d["mood_after"]
    )["primary_bias"]


def test_stressed_face_and_honest_stressed_report_is_not_stress_underestimation(classifier):
    for mood in ("stressed", "tired", "bored"):
        bias = _bias(classifier, entry(mb="normal", ma=mood), sensor(face=STRESSED))
        assert bias["bias_type"] != "stress_underestimation", mood
        assert "adjusted" in bias


def test_stressed_face_and_calm_report_is_still_stress_underestimation(classifier):
    for mood in ("normal", "motivated", "happy"):
        bias = _bias(classifier, entry(mb="normal", ma=mood), sensor(face=STRESSED))
        assert bias["bias_type"] == "stress_underestimation", mood
        assert "adjusted" not in bias


def test_the_adjusted_confidence_is_a_real_share_not_a_tiny_leftover(classifier):
    bias = _bias(classifier, entry(mb="normal", ma="stressed"), sensor(face=STRESSED))
    assert 0.2 <= bias["confidence"] <= 1.0


def test_the_adjusted_answer_is_the_best_of_the_rest(classifier):
    bias = _bias(classifier, entry(mb="normal", ma="stressed"), sensor(face=STRESSED))
    probs = bias["all_probabilities"]
    rest = {k: v for k, v in probs.items() if k != "stress_underestimation"}
    assert bias["bias_type"] == max(rest, key=rest.get)


def test_honest_stress_with_otherwise_clean_session_reads_as_accurate(classifier):
    bias = _bias(classifier, entry(mb="normal", ma="stressed"), sensor(face=STRESSED))
    assert bias["bias_type"] == "accurate_perception"


def test_no_face_scan_never_gives_stress_underestimation(classifier):
    out = compare(entry(ma="normal"), sensor(face=None))
    primary = classifier.classify_with_rules(
        out["features"], facial_emotion=None, mood_after="normal"
    )["primary_bias"]
    assert primary["bias_type"] != "stress_underestimation"
