"""Photo quality gates for the facial analysis, kept free of any model so they
are cheap to import and test."""
import cv2
import numpy as np
from PIL import Image, ImageOps

# Mean grey level (0-255) below which a photo is too dark to analyse. A dim
# indoor webcam frame is typically 60-130; below ~45 the face loses detail.
LOW_LIGHT_THRESHOLD = 45.0
# Variance of the Laplacian below which a photo is too blurry.
BLUR_THRESHOLD = 15.0


def _gray(image: Image.Image) -> np.ndarray:
    return cv2.cvtColor(np.array(image.convert("RGB")), cv2.COLOR_RGB2GRAY)


def mean_brightness(image: Image.Image) -> float:
    return float(_gray(image).mean())


def is_too_dark(image: Image.Image, threshold: float = LOW_LIGHT_THRESHOLD) -> bool:
    return mean_brightness(image) < threshold


def is_image_blurry(image: Image.Image, threshold: float = BLUR_THRESHOLD) -> bool:
    # A dark frame also has low Laplacian variance, so callers must check
    # is_too_dark first or a lighting problem is reported as blur.
    return cv2.Laplacian(_gray(image), cv2.CV_64F).var() < threshold


def apply_exif_orientation(image: Image.Image) -> Image.Image:
    """Turns a phone photo the right way up. Phones store the picture as the
    sensor saw it and add a tag saying how to rotate it; PIL ignores the tag
    unless told to, so without this a portrait selfie arrives on its side."""
    return ImageOps.exif_transpose(image)


def choose_orientation(image: Image.Image, face_score) -> Image.Image:
    """Returns the image turned so that a face looks most like an upright
    face. [face_score] is any function giving how confident a face detector
    is about an image (0 when it sees no face). The image as it is wins
    unless a turned copy is clearly better, so a photo that is already the
    right way up is never changed. This is the fallback for photos that carry
    no rotation tag."""
    best, best_score = image, face_score(image)
    for angle in (90, 270, 180):
        turned = image.rotate(angle, expand=True)
        score = face_score(turned)
        if score > best_score + 0.05:
            best, best_score = turned, score
    return best
