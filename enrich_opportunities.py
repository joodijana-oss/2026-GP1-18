#!/usr/bin/env python3
"""Prepare conservative skillsTaught metadata for Masra opportunities.

Dry-run by default:
  python enrich_opportunities.py --credentials path/to/serviceAccount.json
Write only after reviewing the preview:
  python enrich_opportunities.py --credentials path/to/serviceAccount.json --apply

Adds only skillsTaught and skillExtraction. Never marks old opportunities active,
never changes deadlines, and never changes user/certification documents.
New records are handled automatically on the next run. Requires firebase-admin.
"""
import argparse
import re
import unicodedata
from collections import Counter

SKILLS = {
    "Power BI": [r"\bpower\s*bi\b", r"باور\s*بي\s*اي"],
    "Tableau": [r"\btableau\b", r"تابلو"],
    "SQL": [r"\bsql\b", r"اس\s*كيو\s*ال"],
    "Python": [r"\bpython\b", r"بايثون"],
    "Excel": [r"\bexcel\b", r"اكسل"],
    "R": [r"(?<![a-z])r(?![a-z])", r"لغه\s*r\b"],
    "Machine Learning": [r"\bmachine\s+learning\b", r"تعلم\s+الاله", r"التعلم\s+الالي"],
    "Data Visualization": [r"\bdata\s+visualization\b", r"تصور\s+البيانات", r"تصوير\s+البيانات"],
    "Dashboard Development": [r"\bdashboard(s)?\b", r"لوحات\s+(المعلومات|البيانات|تفاعليه)"],
    "Data Governance": [r"\bdata\s+governance\b", r"حوكمه\s+البيانات"],
    "BigQuery": [r"\bbigquery\b", r"بيج\s*كويري"],
    "Pandas": [r"\bpandas\b", r"بانداز"],
}
# R is too ambiguous in natural-language titles; demand explicit "R language"
SKILLS["R"] = [r"لغه\s+r\b", r"باستخدام\s+r\b", r"\br\s+(programming|language)\b"]

def norm(value):
    value = str(value or "").lower()
    value = "".join(c for c in unicodedata.normalize("NFKD", value)
                    if not unicodedata.combining(c))
    value = value.translate(str.maketrans({"أ":"ا", "إ":"ا", "آ":"ا", "ى":"ي", "ة":"ه"}))
    value = re.sub(r"[^a-z0-9\u0621-\u064a]+", " ", value)
    return " ".join(value.split())

def title_skills(title):
    title = norm(title)
    return [skill for skill, patterns in SKILLS.items()
            if any(re.search(p, title) for p in patterns)]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--credentials", required=True)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--force", action="store_true",
                        help="Reprocess previously extracted records, except manually verified")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()
    from firebase_admin import credentials, firestore, initialize_app
    initialize_app(credentials.Certificate(args.credentials))
    db = firestore.client()
    count = Counter()
    batch = db.batch()
    pending = 0
    scanned = 0

    for doc in db.collection("opportunities").order_by("__name__").stream():
        scanned += 1
        if args.limit and scanned > args.limit:
            break
        data = doc.to_dict() or {}
        prior = data.get("skillExtraction") or {}
        if prior.get("status") == "manual_verified":
            count["manual_skipped"] += 1
            continue
        if not args.force and prior.get("status") in ("auto_high", "review_needed"):
            count["previously_processed"] += 1
            continue

        skills = title_skills(data.get("title"))
        status = "auto_high" if skills else "review_needed"
        count[status] += 1
        if scanned <= 15:
            print(doc.id, "=>", skills or "[needs review]")
        if args.apply:
            batch.update(doc.reference, {
                "skillsTaught": skills,
                "skillExtraction": {
                    "status": status,
                    "method": "exact_title_v1",
                    "evidence": "title" if skills else "insufficient",
                }
            })
            pending += 1
            if pending == 200:
                batch.commit()
                batch = db.batch()
                pending = 0

    if args.apply and pending:
        batch.commit()
    print(f"Scanned {scanned}; counts={dict(count)}")
    print("Applied updates." if args.apply else "DRY RUN only; nothing was written.")
    print("Opportunity availability and deadlines were NOT modified.")

if __name__ == "__main__":
    main()
