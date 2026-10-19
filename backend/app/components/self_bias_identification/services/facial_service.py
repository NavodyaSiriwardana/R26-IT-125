import os
from transformers import pipeline
from PIL import Image
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
import numpy as np
import io
import base64
import cv2
from app.components.self_bias_identification.services.image_quality import (
    apply_exif_orientation,
    choose_orientation,
    is_image_blurry,
    is_too_dark,
)

emotion_classifier = pipeline(
    "image-classification",
    model="dima806/facial_emotions_image_detection"
)

# Tasks API replaces the legacy mp.solutions.* API removed in mediapipe>=0.10.30
# (see STUDY_CATEGORIES-style comment in comparator.py history — this swap was
# required to unblock numpy>=2, which shap/ortools in this shared backend need
# and the old mp.solutions.* build could never support).
_MODELS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "ml_models", "mediapipe_models",
)

_face_detector = mp_vision.FaceDetector.create_from_options(
    mp_vision.FaceDetectorOptions(
        base_options=mp_python.BaseOptions(
            model_asset_path=os.path.join(_MODELS_DIR, "blaze_face_short_range.tflite")
        ),
        min_detection_confidence=0.6,
    )
)

_face_landmarker = mp_vision.FaceLandmarker.create_from_options(
    mp_vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(
            model_asset_path=os.path.join(_MODELS_DIR, "face_landmarker.task")
        ),
        num_faces=1,
    )
)


# Sentinel returned by detect_and_crop_face when more than one prominent
# face is found, distinguishing it from the "no face at all" (None) case.
MULTIPLE_FACES = "MULTIPLE_FACES_DETECTED"


def face_confidence(image: Image.Image) -> float:
    """How sure the face detector is that this picture holds a face (0 if none)."""
    mp_image = mp.Image(
        image_format=mp.ImageFormat.SRGB,
        data=np.array(image.convert("RGB")),
    )
    results = _face_detector.detect(mp_image)
    if not results.detections:
        return 0.0
    return max(d.categories[0].score for d in results.detections)


def detect_and_crop_face(image: Image.Image):
    img_array = np.array(image.convert("RGB"))
    h, w, _ = img_array.shape
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=img_array)

    results = _face_detector.detect(mp_image)
    if not results.detections:
        return None, False

    # BoundingBox fields are already absolute pixel coordinates in the
    # Tasks API (unlike the old relative_bounding_box, which was 0-1).
    areas = [d.bounding_box.width * d.bounding_box.height for d in results.detections]
    largest_area = max(areas)

    # A second face only counts as a real "someone else is in frame" case
    # if it's a comparable size to the main face — a small face far in the
    # background (a photo on the wall, someone walking past) shouldn't
    # reject an otherwise valid selfie.
    significant_faces = sum(1 for a in areas if a >= 0.35 * largest_area)
    if significant_faces > 1:
        return MULTIPLE_FACES, False

    detection = results.detections[areas.index(largest_area)]
    bbox = detection.bounding_box

    x = max(0, bbox.origin_x)
    y = max(0, bbox.origin_y)
    bw = bbox.width
    bh = bbox.height

    margin_x = int(0.25 * bw)
    margin_y = int(0.25 * bh)
    x1 = max(0, x - margin_x)
    y1 = max(0, y - margin_y)
    x2 = min(w, x + bw + margin_x)
    y2 = min(h, y + bh + margin_y)

    cropped = img_array[y1:y2, x1:x2]

    landmark_results = _face_landmarker.detect(mp_image)
    landmarks_visible = len(landmark_results.face_landmarks) > 0

    return Image.fromarray(cropped), landmarks_visible


def image_to_base64(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG")
    return base64.b64encode(buffer.getvalue()).decode("utf-8")


def analyze_facial_expression(image_base64: str):
    try:
        image_bytes = base64.b64decode(image_base64)
        # Phone photos carry a rotation tag; apply it so the face is upright.
        image = apply_exif_orientation(Image.open(io.BytesIO(image_bytes))).convert("RGB")

        # Check lighting first: a dark frame also fails the blur test, and
        # telling the user "blurry" would send them chasing the wrong fix.
        if is_too_dark(image):
            return {
                "status": "low_light",
                "message": "It is too dark for reliable analysis. Move to a brighter spot or face a light, then retake the photo."
            }

        if is_image_blurry(image):
            return {
                "status": "blurry_image",
                "message": "The image is too blurry for reliable analysis. Please hold the camera steady and retake the photo."
            }

        # Fallback for photos without a rotation tag: use the turn in which the
        # face looks most upright.
        image = choose_orientation(image, face_confidence)

        face_image, landmarks_visible = detect_and_crop_face(image)

        if face_image == MULTIPLE_FACES:
            return {
                "status": "multiple_faces_detected",
                "message": "More than one face was detected in the frame. Please make sure only you are visible, then retake the photo."
            }

        if face_image is None:
            return {
                "status": "no_face_detected",
                "message": "No face detected in the image. Please try again with better lighting and a clear view of your face."
            }

        if not landmarks_visible:
            return {
                "status": "partial_face",
                "message": "Your face is not fully visible. Please make sure your full face is clearly visible, then retake the photo.",
                "cropped_face_base64": image_to_base64(face_image),
            }

        results = emotion_classifier(face_image)
        dominant = results[0]
        emotion_scores = {r['label']: round(r['score'], 4) for r in results}

        stress_emotions = ['sad', 'angry', 'fear', 'disgust']
        stress_score = sum(emotion_scores.get(e, 0) for e in stress_emotions)

        return {
            "status": "success",
            "dominant_emotion": dominant['label'],
            "confidence": round(dominant['score'], 4),
            "emotion_scores": emotion_scores,
            "stress_indicator": round(stress_score, 4),
            "cropped_face_base64": image_to_base64(face_image),
        }

    except Exception as e:
        return {
            "status": "error",
            "message": f"Facial analysis failed: {str(e)}"
        }
