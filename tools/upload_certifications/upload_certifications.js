#!/usr/bin/env node
/**
 * Uploads the Masra IT certifications CSV to Firestore.
 *
 *   node upload_certifications.js --dry-run            # parse + show summary, no upload
 *   node upload_certifications.js --key <service.json> # upload (or set GOOGLE_APPLICATION_CREDENTIALS)
 *   node upload_certifications.js --key <...> --prune  # also delete docs no longer in the CSV
 *
 * Each CSV row becomes one document in `certifications/{id}`.
 * List columns (career_paths, skills) are stored as arrays so the app can
 * query them with `arrayContains`.
 */
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "masra-184b3"; // from .firebaserc
const COLLECTION = "certifications";
const DEFAULT_CSV = path.join(
  __dirname, "..", "..", "lib", "assets", "data", "Masra_IT_Certifications.csv",
);
const BATCH_SIZE = 400; // Firestore allows up to 500 writes per batch.

// ---------------------------------------------------------
// ARGS
// ---------------------------------------------------------

function parseArgs(argv) {
  const args = { dryRun: false, prune: false, key: null, csv: DEFAULT_CSV };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") args.dryRun = true;
    else if (a === "--prune") args.prune = true;
    else if (a === "--key") args.key = argv[++i];
    else if (a === "--csv") args.csv = argv[++i];
    else throw new Error(`Unknown argument: ${a}`);
  }
  return args;
}

// ---------------------------------------------------------
// CSV (RFC 4180: quoted fields, "" escapes, newlines inside quotes)
// ---------------------------------------------------------

function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1); // strip BOM
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
    } else if (c === '"') {
      inQuotes = true;
    } else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += c;
    }
  }
  if (field !== "" || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((v) => v.trim() !== ""));
}

const splitList = (value) =>
  (value || "").split(";").map((s) => s.trim()).filter(Boolean);

function rowToDoc(header, values) {
  const r = Object.fromEntries(header.map((h, i) => [h, (values[i] ?? "").trim()]));
  return {
    id: r.id,
    data: {
      name: r.name,
      shortName: r.short_name,
      issuer: r.issuer,
      examCode: r.exam_code,
      level: r.level,
      category: r.category,
      description: r.description,
      descriptionAr: r.description_ar,
      careerPaths: splitList(r.career_paths),
      skills: splitList(r.skills),
      officialUrl: r.official_url,
      verified: r.verified.toLowerCase() === "yes",
      statusNote: r.status_note,
    },
  };
}

function loadDocs(csvPath) {
  const rows = parseCsv(fs.readFileSync(csvPath, "utf8"));
  const [header, ...body] = rows;
  const required = ["id", "name", "issuer", "level", "category", "career_paths"];
  const missing = required.filter((h) => !header.includes(h));
  if (missing.length) throw new Error(`CSV is missing columns: ${missing.join(", ")}`);

  const docs = [];
  const seen = new Set();
  body.forEach((values, n) => {
    if (values.length !== header.length) {
      throw new Error(`Row ${n + 2} has ${values.length} fields, expected ${header.length}`);
    }
    const doc = rowToDoc(header, values);
    if (!doc.id) throw new Error(`Row ${n + 2} has no id`);
    if (seen.has(doc.id)) throw new Error(`Duplicate id: ${doc.id}`);
    seen.add(doc.id);
    docs.push(doc);
  });
  return docs;
}

// ---------------------------------------------------------
// MAIN
// ---------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const docs = loadDocs(args.csv);

  const byCategory = {};
  docs.forEach((d) => (byCategory[d.data.category] = (byCategory[d.data.category] || 0) + 1));
  console.log(`Parsed ${docs.length} certifications from ${path.basename(args.csv)}`);
  console.log(`Verified: ${docs.filter((d) => d.data.verified).length}`);
  console.log("By category:", byCategory);

  if (args.dryRun) {
    console.log("\nExample document:", JSON.stringify(docs[0], null, 2));
    console.log("\nDry run only - nothing was uploaded.");
    return;
  }

  // Loaded only for real uploads, so --dry-run works without `npm install`.
  const admin = require("firebase-admin");
  if (args.key) {
    const keyPath = path.resolve(args.key);
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(fs.readFileSync(keyPath, "utf8"))),
      projectId: PROJECT_ID,
    });
  } else {
    // Uses GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`.
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  const db = admin.firestore();
  const col = db.collection(COLLECTION);
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_SIZE).forEach((d) => {
      batch.set(col.doc(d.id), { ...d.data, updatedAt: now });
    });
    await batch.commit();
    console.log(`Uploaded ${Math.min(i + BATCH_SIZE, docs.length)} / ${docs.length}`);
  }

  if (args.prune) {
    const keep = new Set(docs.map((d) => d.id));
    const existing = await col.listDocuments();
    const stale = existing.filter((ref) => !keep.has(ref.id));
    for (let i = 0; i < stale.length; i += BATCH_SIZE) {
      const batch = db.batch();
      stale.slice(i, i + BATCH_SIZE).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
    console.log(`Pruned ${stale.length} documents that are no longer in the CSV.`);
  }

  console.log(`\nDone: ${docs.length} documents in '${COLLECTION}' (project ${PROJECT_ID}).`);
}

main().catch((err) => {
  console.error("Upload failed:", err.message);
  process.exit(1);
});
