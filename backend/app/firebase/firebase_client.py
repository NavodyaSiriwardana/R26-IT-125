from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


_FIREBASE_APP = None


def initialize_firebase():
    global _FIREBASE_APP

    if _FIREBASE_APP is None:
        service_account_path = Path("app/firebase/firebase-service-account.json")

        if not service_account_path.exists():
            raise FileNotFoundError(
                f"Firebase service account file not found at {service_account_path}"
            )

        cred = credentials.Certificate(str(service_account_path))

        _FIREBASE_APP = firebase_admin.initialize_app(cred)

    return _FIREBASE_APP


def get_firestore_client():
    initialize_firebase()
    return firestore.client()