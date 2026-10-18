"""Remove face images that earlier versions of the app stored in Firestore.

Before the privacy fix, the whole facial-analysis result, including
`cropped_face_base64` (a photo of the user's face), was saved inside
`bias_results.comparison.facial_emotion` and `auto_sensor_data.facial_emotion`.

Run from the backend folder. Default is a DRY RUN that only counts:
    python -m app.components.self_bias_identification.evaluation.scrub_stored_face_images
Then, once you are happy with the counts:
    python -m app.components.self_bias_identification.evaluation.scrub_stored_face_images --apply
"""
import argparse

from firebase_admin import firestore

from app.database import db

# (collection, path to the facial dict inside each document)
TARGETS = [
    ("bias_results", ("comparison", "facial_emotion")),
    ("auto_sensor_data", ("facial_emotion",)),
]
FIELD = "cropped_face_base64"


def holds_image(doc: dict, path: tuple) -> bool:
    node = doc
    for key in path:
        node = node.get(key) if isinstance(node, dict) else None
    return isinstance(node, dict) and FIELD in node


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="actually delete the images")
    args = ap.parse_args()

    for collection, path in TARGETS:
        found = 0
        for doc in db.collection(collection).stream():
            if holds_image(doc.to_dict(), path):
                found += 1
                if args.apply:
                    dotted = ".".join(path + (FIELD,))
                    doc.reference.update({dotted: firestore.DELETE_FIELD})
        verb = "scrubbed" if args.apply else "would scrub"
        print(f"{collection}: {verb} {found} document(s)")
    if not args.apply:
        print("Dry run only. Re-run with --apply to delete the images.")


if __name__ == "__main__":
    main()
