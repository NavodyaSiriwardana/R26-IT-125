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


def is_image_blurry(image: Image.Image, threshold: float = 15.0) -> bool:
    img_array = np.array(image.convert("RGB"))
    gray = cv2.cvtColor(img_array, cv2.COLOR_RGB2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < threshold


def detect_and_crop_face(image: Image.Image):
    img_array = np.array(image.convert("RGB"))
    h, w, _ = img_array.shape
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=img_array)

    results = _face_detector.detect(mp_image)
    if not results.detections:
        return None, False

    # BoundingBox fields are already absolute pixel coordinates in the
    # Tasks API (unlike the old relative_bounding_box, which was 0-1).
    detection = max(
        results.detections,
        key=lambda d: d.bounding_box.width * d.bounding_box.height
    )
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
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")

        if is_image_blurry(image):
            return {
                "status": "blurry_image",
                "message": "The image is too blurry for reliable analysis. Please hold the camera steady and retake the photo."
            }

        face_image, landmarks_visible = detect_and_crop_face(image)

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
