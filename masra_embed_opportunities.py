"""One-time semantic vector preparation for existing Masra/Tuwaiq Firestore records.

Run locally on a trusted computer with a NEW Firebase service-account JSON:
  X:\\.venv\\Scripts\\python.exe masra_embed_opportunities.py "C:\\path\\to\\new-service-account.json"

Only writes the fields semanticEmbedding, semanticEmbeddingModel and
semanticEmbeddingTextVersion in existing opportunities documents. Does NOT
change isActive, reviewStatus, dates, eligibility, or originalFields.
"""
import argparse
import json
from pathlib import Path

from firebase_admin import credentials, firestore, initialize_app
from sentence_transformers import SentenceTransformer

EXPECTED_PROJECT = 'masra-184b3'
MODEL_ID = 'sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2'
VERSION = 1


def semantic_text(record):
    # Keep this definition aligned with Flutter opportunity_model.semanticText.
    fields = ('title', 'category', 'description', 'objectives')
    return ' '.join(str(record.get(key) or '').strip() for key in fields if str(record.get(key) or '').strip())


def main():
    parser = argparse.ArgumentParser(description='Add semantic embeddings to existing Masra opportunity records')
    parser.add_argument('credentials', type=Path, help='Path to a NEW Firebase Admin service-account JSON; do not upload or commit it')
    args = parser.parse_args()
    if not args.credentials.is_file():
        parser.error('Service-account JSON file not found')
    with args.credentials.open('r', encoding='utf-8') as file:
        key = json.load(file)
    if key.get('type') != 'service_account' or key.get('project_id') != EXPECTED_PROJECT:
        raise SystemExit('STOP: Wrong Firebase project. No writes performed.')

    print('Loading local multilingual model...')
    model = SentenceTransformer(MODEL_ID, device='cpu')
    initialize_app(credentials.Certificate(str(args.credentials)), {'projectId': EXPECTED_PROJECT})
    db = firestore.client()
    docs = list(db.collection('opportunities').stream())
    if not docs:
        raise SystemExit('STOP: No opportunities documents found. No writes performed.')
    # Limit to rows from the uploaded Tuwaiq dataset; do not modify another provider's records.
    selected = []
    skipped = 0
    for doc in docs:
        record = doc.to_dict() or {}
        if record.get('source') != 'tuwaiq':
            continue
        if record.get('semanticEmbeddingModel') == MODEL_ID and record.get('semanticEmbeddingTextVersion') == VERSION and isinstance(record.get('semanticEmbedding'), list) and len(record['semanticEmbedding']) == 384:
            skipped += 1
            continue
        content = semantic_text(record)
        if content:
            selected.append((doc.reference, content))
    print('Tuwaiq opportunities to process: {} | already done: {}'.format(len(selected), skipped))
    if not selected:
        print('DONE. Nothing needs updating.')
        return

    written = 0
    for start in range(0, len(selected), 32):
        group = selected[start:start + 32]
        vectors = model.encode([content for _, content in group], batch_size=16, normalize_embeddings=True, show_progress_bar=False)
        batch = db.batch()
        for (ref, _), vector in zip(group, vectors):
            batch.update(ref, {
                'semanticEmbedding': [float(value) for value in vector],
                'semanticEmbeddingModel': MODEL_ID,
                'semanticEmbeddingTextVersion': VERSION,
            })
        batch.commit()
        written += len(group)
        print('Processed {}/{} (new vectors only)'.format(written, len(selected)))
    print('DONE. Added {} embeddings, left {} existing embeddings unchanged.'.format(written, skipped))
    print('No opportunity was activated; old or unverified opportunities remain unavailable for recommendations.')


if __name__ == '__main__':
    main()
