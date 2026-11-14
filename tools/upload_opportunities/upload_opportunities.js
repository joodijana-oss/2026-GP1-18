#!/usr/bin/env node
/**
 * Uploads the Masra opportunities JSON to Firestore.
 *
 *   node upload_opportunities.js --dry-run                 # check + show summary, no upload
 *   node upload_opportunities.js --key <service.json>      # upload (or set GOOGLE_APPLICATION_CREDENTIALS)
 *   node upload_opportunities.js --key <...> --delete-old  # also delete the old Arabic docs
 *
 * Each JSON record becomes one document in `opportunities/{id}`, with
 * language: 'en', isActive: true and updatedAt added. The app only reads
 * documents where language == 'en'.
 *
 * The old Arabic documents in the same collection have no `language` field.
 * They are kept unless --delete-old is given; then every document without a
 * `language` field is deleted (after the upload). English documents are
 * never deleted by this script.
 */
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "masra-184b3"; // from .firebaserc
const COLLECTION = "opportunities";
const DATA_DIR = path.join(__dirname, "..", "..", "lib", "assets", "data");
const DEFAULT_JSON = path.join(DATA_DIR, "Masra_Opportunities.json");
const CAREER_PATHS_JSON = path.join(DATA_DIR, "careerPaths.json");
const BATCH_SIZE = 400; // Firestore allows up to 500 writes per batch.

const SOURCES = ["tuwaiq", "doroob", "coursera"];
const TYPES = ["Training Program", "Bootcamp", "Meetup", "Webinar", "Course", "Hackathon"];
const TEXT_FIELDS = [
  "source", "provider", "type", "title", "description", "field", "location",
  "price", "startDate", "endDate", "registrationDeadline", "duration", "url",
];
const LIST_FIELDS = ["objectives", "requirements", "skills", "careerPathIds"];
const DATE_FIELDS = ["startDate", "endDate", "registrationDeadline"];

// ---------------------------------------------------------
// ARGS
// ---------------------------------------------------------

function parseArgs(argv) {
  const args = { dryRun: false, deleteOld: false, key: null, json: DEFAULT_JSON };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") args.dryRun = true;
    else if (a === "--delete-old") args.deleteOld = true;
    else if (a === "--key") args.key = argv[++i];
    else if (a === "--json") args.json = argv[++i];
    else throw new Error(`Unknown argument: ${a}`);
  }
  return args;
}

// ---------------------------------------------------------
// JSON CHECKS (same rules as test/opportunity_data_test.dart)
// ---------------------------------------------------------

function readJson(file) {
  let text = fs.readFileSync(file, "utf8");
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1); // strip BOM
  return JSON.parse(text);
}

function knownCareerPaths() {
  return new Set(readJson(CAREER_PATHS_JSON).map((p) => p.id));
}

// 'YYYY-MM-DD' that is a real calendar day.
function isDay(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

// Firestore document ids cannot contain '/', be '.' or '..', or look like __x__.
function isValidDocId(id) {
  return (
    id !== "." && id !== ".." && !id.includes("/") &&
    !/^__.*__$/.test(id) && Buffer.byteLength(id, "utf8") <= 1500
  );
}

function recordToDoc(record, n, careerPaths) {
  const where = `Record ${n + 1}${record && record.id ? ` (${record.id})` : ""}`;
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    throw new Error(`${where} is not an object`);
  }

  const id = typeof record.id === "string" ? record.id.trim() : "";
  if (!id) throw new Error(`${where} has no id`);
  if (!isValidDocId(id)) throw new Error(`${where} has an id Firestore cannot use`);

  const data = { id };
  for (const f of TEXT_FIELDS) {
    const v = record[f] ?? "";
    if (typeof v !== "string") throw new Error(`${where}: '${f}' must be text`);
    data[f] = v.trim();
  }
  for (const f of LIST_FIELDS) {
    const v = record[f] ?? [];
    if (!Array.isArray(v) || v.some((s) => typeof s !== "string")) {
      throw new Error(`${where}: '${f}' must be a list of text`);
    }
    data[f] = v.map((s) => s.trim()).filter(Boolean);
  }
  const isFree = record.isFree ?? null;
  if (isFree !== true && isFree !== false && isFree !== null) {
    throw new Error(`${where}: 'isFree' must be true, false or null`);
  }
  data.isFree = isFree;

  for (const f of ["title", "url", "type"]) {
    if (!data[f]) throw new Error(`${where} has no ${f}`);
  }
  if (!SOURCES.includes(data.source)) {
    throw new Error(`${where}: source must be one of ${SOURCES.join(", ")}`);
  }
  for (const f of DATE_FIELDS) {
    if (data[f] && !isDay(data[f])) {
      throw new Error(`${where}: '${f}' must be YYYY-MM-DD or empty`);
    }
  }
  const unknown = data.careerPathIds.filter((p) => !careerPaths.has(p));
  if (unknown.length) {
    throw new Error(`${where}: unknown careerPathIds: ${unknown.join(", ")}`);
  }

  return { id, data };
}

function loadDocs(jsonPath) {
  const records = readJson(jsonPath);
  if (!Array.isArray(records)) throw new Error("The JSON file must be a list of records");
  const careerPaths = knownCareerPaths();

  const docs = [];
  const seen = new Set();
  records.forEach((record, n) => {
    const doc = recordToDoc(record, n, careerPaths);
    if (seen.has(doc.id)) throw new Error(`Duplicate id: ${doc.id}`);
    seen.add(doc.id);
    docs.push(doc);
  });
  return docs;
}

function countBy(docs, field) {
  const counts = {};
  docs.forEach((d) => (counts[d.data[field]] = (counts[d.data[field]] || 0) + 1));
  return counts;
}

// ---------------------------------------------------------
// MAIN
// ---------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const docs = loadDocs(args.json);

  console.log(`Parsed ${docs.length} opportunities from ${path.basename(args.json)}`);
  console.log("By source:", countBy(docs, "source"));
  console.log("By type:", countBy(docs, "type"));
  console.log(`With dates: ${docs.filter((d) => DATE_FIELDS.some((f) => d.data[f])).length}`);
  const otherTypes = docs.filter((d) => !TYPES.includes(d.data.type));
  if (otherTypes.length) {
    console.log(`Warning: ${otherTypes.length} records have a type outside: ${TYPES.join(", ")}`);
  }

  if (args.dryRun) {
    console.log("\nExample document:", JSON.stringify(docs[0], null, 2));
    if (args.deleteOld) {
      console.log("\n--delete-old would delete every document without a 'language' field.");
    }
    console.log("\nDry run only - nothing was uploaded or deleted.");
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
      batch.set(col.doc(d.id), { ...d.data, language: "en", isActive: true, updatedAt: now });
    });
    await batch.commit();
    console.log(`Uploaded ${Math.min(i + BATCH_SIZE, docs.length)} / ${docs.length}`);
  }

  if (args.deleteOld) {
    // Only the old Arabic documents: the ones with no `language` field.
    const snapshot = await col.select("language").get();
    const old = snapshot.docs.filter((doc) => doc.get("language") === undefined);
    for (let i = 0; i < old.length; i += BATCH_SIZE) {
      const batch = db.batch();
      old.slice(i, i + BATCH_SIZE).forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
    console.log(`Deleted ${old.length} old documents without a 'language' field.`);
  }

  console.log(`\nDone: ${docs.length} documents in '${COLLECTION}' (project ${PROJECT_ID}).`);
}

main().catch((err) => {
  console.error("Upload failed:", err.message);
  process.exit(1);
});
