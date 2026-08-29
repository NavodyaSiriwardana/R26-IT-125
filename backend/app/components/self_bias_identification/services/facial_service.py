from transformers import pipeline
from PIL import Image
import mediapipe as mp
import numpy as np
import io
import base64
import cv2

emotion_classifier = pipeline(
    "image-classification",
    model="dima806/facial_emotions_image_detection"
)

mp_face_detection = mp.solutions.face_detection
face_detector = mp_face_detection.FaceDetection(
    model_selection=0, min_detection_confidence=0.6
)

mp_face_mesh = mp.solutions.face_mesh
face_mesh = mp_face_mesh.FaceMesh(
    static_image_mode=True, max_num_faces=1, min_detection_confidence=0.6
)


def is_image_blurry(image: Image.Image, threshold: float = 15.0) -> bool:
    img_array = np.array(image.convert("RGB"))
    gray = cv2.cvtColor(img_array, cv2.COLOR_RGB2GRAY)
    return cv2.Laplacian(gray, cv2.CV_64F).var() < threshold


def detect_and_crop_face(image: Image.Image):
    img_array = np.array(image.convert("RGB"))
    h, w, _ = img_array.shape

    results = face_detector.process(img_array)
    if not results.detections:
        return None, False

    detection = max(
    results.detections,
    key=lambda d: d.location_data.relative_bounding_box.width
    * d.location_data.relative_bounding_box.height
)
    bbox = detection.location_data.relative_bounding_box

    x = max(0, int(bbox.xmin * w))
    y = max(0, int(bbox.ymin * h))
    bw = int(bbox.width * w)
    bh = int(bbox.height * h)

    margin_x = int(0.25 * bw)
    margin_y = int(0.25 * bh)
    x1 = max(0, x - margin_x)
    y1 = max(0, y - margin_y)
    x2 = min(w, x + bw + margin_x)
    y2 = min(h, y + bh + margin_y)

    cropped = img_array[y1:y2, x1:x2]

    mesh_results = face_mesh.process(img_array)
    landmarks_visible = mesh_results.multi_face_landmarks is not None

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