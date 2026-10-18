"""Privacy helpers: face images are analysed in memory and must never be stored.

`facial_service.analyze_facial_expression` returns a `cropped_face_base64`
field so the app can show the user their own face while scanning. That field
must not travel any further than the device that took the photo.
"""

FACE_IMAGE_FIELDS = ("cropped_face_base64",)


def strip_face_images(facial: dict | None) -> dict | None:
    """Return a copy of a facial-analysis result without any image data."""
    if not isinstance(facial, dict):
        return facial
    return {k: v for k, v in facial.items() if k not in FACE_IMAGE_FIELDS}
