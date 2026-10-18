"""Export Mood Reset study data to CSV with pseudonymised participant IDs.

Run from the backend folder:
    python -m app.components.self_bias_identification.evaluation.export_study_data \
        --out study_resets.csv --salt "<a secret string you keep>"

Only participants who gave consent AND turned study mode on are exported.
User IDs are replaced by a salted hash, so the CSV can be shared with a
supervisor or kept in the report appendix without exposing identities.
No face images are involved: they are never stored.
"""
import argparse
import csv
import hashlib

from app.database import db

COLUMNS = [
    "participant", "condition", "before_stress", "after_stress",
    "self_before", "self_after", "outcome", "delta_points",
    "duration_seconds", "rounds_completed", "created_at",
]


def pseudonym(user_id: str, salt: str) -> str:
    return "P" + hashlib.sha256((salt + user_id).encode()).hexdigest()[:8]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="study_resets.csv")
    ap.add_argument("--salt", required=True, help="secret string used to pseudonymise IDs")
    args = ap.parse_args()

    consenting = {
        doc.id for doc in db.collection("consents").stream()
        if doc.to_dict().get("agreed") and doc.to_dict().get("study_mode")
    }

    rows = []
    for doc in db.collection("mood_resets").stream():
        d = doc.to_dict()
        if d.get("user_id") not in consenting or not d.get("study_mode"):
            continue
        row = {c: d.get(c) for c in COLUMNS}
        row["participant"] = pseudonym(d["user_id"], args.salt)
        rows.append(row)

    rows.sort(key=lambda r: (r["participant"], r["created_at"] or ""))
    with open(args.out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=COLUMNS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"Exported {len(rows)} resets from {len({r['participant'] for r in rows})} "
          f"participants to {args.out}")


if __name__ == "__main__":
    main()
