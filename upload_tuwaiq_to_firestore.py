"""Import every Tuwaiq Excel row into a separate Firestore opportunities collection.

Usage:
  python upload_tuwaiq_to_firestore.py "path/to/original.xlsx" "path/to/service-account.json"

Safeguards:
- Only targets Firebase project masra-184b3 and collection opportunities.
- Never edits the Excel source, users, or certifications.
- Keeps all 15 original column values in originalFields.
- Deterministic document ID preserves duplicate source rows; reruns skip existing docs.
- Marks all new records inactive and in need of review, because the dataset does not
  contain trustworthy skill IDs or verified current application eligibility.
"""
import argparse
import hashlib
import json
from datetime import date, datetime
from pathlib import Path

from openpyxl import load_workbook
from firebase_admin import credentials, firestore, initialize_app

EXPECTED_PROJECT = 'masra-184b3'
EXPECTED_HEADERS = [
    'النوع', 'الاسم', 'الوصف', 'الأهداف', 'المميزات', 'المتطلبات',
    'المجال', 'الفئة العمرية', 'تاريخ البدء', 'تاريخ الانتهاء',
    'آخر موعد للتسجيل', 'الموقع', 'مجاني/مدفوع',
    'السعر (شامل الضريبة)', 'الرابط',
]

def preserve(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value

def main():
    parser = argparse.ArgumentParser(description='Safe Tuwaiq to Firestore importer')
    parser.add_argument('excel', type=Path, help='Original Tuwaiq XLSX file')
    parser.add_argument('credentials', type=Path, help='Firebase service account private JSON; never commit')
    args = parser.parse_args()
    if not args.excel.is_file() or not args.credentials.is_file():
        parser.error('Excel or credential file not found. Check the exact file paths.')

    with args.credentials.open('r', encoding='utf-8') as handle:
        key = json.load(handle)
    if key.get('project_id') != EXPECTED_PROJECT or key.get('type') != 'service_account':
        raise SystemExit('STOP: credential is not for the intended Firebase project ' + EXPECTED_PROJECT)

    workbook = load_workbook(args.excel, read_only=True, data_only=True)
    sheet = workbook['فعاليات طويق'] if 'فعاليات طويق' in workbook.sheetnames else workbook.active
    data = sheet.iter_rows(values_only=True)
    headers = list(next(data))[:15]
    if headers != EXPECTED_HEADERS:
        raise SystemExit('STOP: Excel headers do not match the expected 15 fields. Nothing uploaded.')

    docs = []
    for row_number, row in enumerate(data, start=2):
        fields = dict(zip(headers, [preserve(v) for v in row[:15]]))
        # Including the source row number ensures that even duplicate activities survive.
        doc_id = 'tuwaiq_' + hashlib.sha256(
            (str(row_number) + '\x1f' + str(fields.get('الرابط') or '')).encode('utf-8')
        ).hexdigest()[:24]
        docs.append((doc_id, {
            'source': 'tuwaiq',
            'sourceRow': row_number,
            'title': fields['الاسم'] or '',
            'type': fields['النوع'] or '',
            'provider': 'Tuwaiq Academy',
            'description': fields['الوصف'] or '',
            'objectives': fields['الأهداف'] or '',
            'requirementsText': fields['المتطلبات'] or '',
            'category': fields['المجال'] or '',
            'applicationUrl': fields['الرابط'] or '',
            'registrationDeadlineRaw': fields['آخر موعد للتسجيل'],
            'careerPathIds': [],
            'requiredSkillIds': [],
            'learningSkillIds': [],
            'level': '',
            'location': fields['الموقع'] or '',
            'deadline': None,
            'isActive': False,
            'reviewStatus': 'needs_review',
            'originalFields': fields,
        }))
    workbook.close()
    if len(docs) != 1052:
        raise SystemExit(f'STOP: expected 1052 rows, found {len(docs)}. Nothing uploaded.')

    initialize_app(credentials.Certificate(str(args.credentials)))
    db = firestore.client()
    collection = db.collection('opportunities')
    uploaded = 0
    skipped = 0
    for start in range(0, len(docs), 200):
        chunk = docs[start:start + 200]
        refs = [collection.document(doc_id) for doc_id, _ in chunk]
        existing = {snapshot.id for snapshot in db.get_all(refs) if snapshot.exists}
        batch = db.batch()
        new_count = 0
        for (doc_id, record), ref in zip(chunk, refs):
            if doc_id in existing:
                skipped += 1
                continue
            batch.create(ref, record)
            new_count += 1
        if new_count:
            batch.commit()
            uploaded += new_count
        print(f'Processed {min(start+200, len(docs))}/{len(docs)}: new {uploaded}, existing {skipped}')
    print(f'DONE. Excel records: {len(docs)}. Uploaded: {uploaded}. Existing skipped: {skipped}.')
    print('All uploaded records are inactive until skills, eligibility and deadlines are verified.')

if __name__ == '__main__':
    main()
