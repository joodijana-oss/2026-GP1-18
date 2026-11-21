#!/usr/bin/env node
/**
 * Uploads the Masra opportunities JSON to Firestore.
 *
 *   node upload_opportunities.js --dry-run                 # check + show summary, no upload
 *   node upload_opportunities.js --key <service.json>      # upload (or set GOOGLE_APPLICATION_CREDENTIALS)
 *   node upload_opportunities.js --key <...> --delete-old  # also delete the old Arabic docs
 *   node upload_opportunities.js --key <...> --prune       # also delete English docs no longer in the JSON
 *   node upload_opportunities.js --dry-run --prune --baseline <old.json>  # what an upload would add, change and delete, compared with an old copy
 *   node upload_opportunities.js --dry-run --prune --key <service.json>  # the same, compared with Firestore (read only)
 *
 * Each JSON record becomes one document in `opportunities/{id}`, with
 * language: 'en', isActive: true and updatedAt added. The app only reads
 * documents where language == 'en'.
 *
 * The old Arabic documents in the same collection have no `language` field.
 * They are kept unless --delete-old is given; then every document without a
 * `language` field is deleted (after the upload). English documents are
 * deleted only with --prune, and only when their id is no longer in the JSON.
 *
 * A JSON with no records is refused. With --prune, the stored English ids are
 * read before the upload, and the run stops with nothing written if none of
 * them is in the JSON (that would delete every English document, so the file
 * is wrong).
 *
 * A dry run reads Firestore only when --key is given, and then only reads.
 * A --baseline dry run compares the JSON with an old copy of it (for example
 * the file as it was at the last upload) and needs no key. Its list equals
 * what an upload would do only if Firestore still holds that old copy; the
 * --key dry run gives the exact list.
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
  const args = {
    dryRun: false, deleteOld: false, prune: false, key: null, json: DEFAULT_JSON, baseline: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") args.dryRun = true;
    else if (a === "--delete-old") args.deleteOld = true;
    else if (a === "--prune") args.prune = true;
    else if (a === "--key") args.key = argv[++i];
    else if (a === "--json") args.json = argv[++i];
    else if (a === "--baseline") {
      args.baseline = argv[++i];
      if (!args.baseline) throw new Error("--baseline needs a file");
    } else throw new Error(`Unknown argument: ${a}`);
  }
  // Checked here, before any file or key is read.
  if (args.baseline && !args.dryRun) throw new Error("--baseline is only for --dry-run");
  if (args.baseline && args.key) {
    throw new Error("Use --baseline or --key for a dry run, not both");
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

// The fields an upload writes for one record (updatedAt is added on top).
const uploadData = (d) => ({ ...d.data, language: "en", isActive: true });

// ---------------------------------------------------------
// DRY-RUN COMPARISON
// ---------------------------------------------------------

// Compares the documents an upload would write with the ones already there
// (an old copy of the file, or Firestore). `before` maps id -> stored fields.
// updatedAt is ignored. A field on one side only counts as changed, because
// the upload uses set(), which replaces the whole document.
function compareDocs(docs, before) {
  const result = { added: [], changed: [], unchanged: 0 };
  for (const d of docs) {
    const old = before.get(d.id);
    if (!old) {
      result.added.push(d.id);
      continue;
    }
    const fields = [...new Set([...Object.keys(d.data), ...Object.keys(old)])].filter(
      (f) => f !== "updatedAt" && JSON.stringify(d.data[f]) !== JSON.stringify(old[f]),
    );
    if (fields.length) result.changed.push({ id: d.id, fields });
    else result.unchanged++;
  }
  result.added.sort();
  result.changed.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  return result;
}

// The ids that are stored but no longer in the file.
function notInFile(storedIds, docs) {
  const keep = new Set(docs.map((d) => d.id));
  return storedIds.filter((id) => !keep.has(id)).sort();
}

// Stops a --prune that would delete every stored English document. That only
// happens with the wrong file (for example one with other ids), so the run
// stops before anything is written. No stored ids is fine: nothing to delete.
function checkPrune(storedIds, docs) {
  const keep = new Set(docs.map((d) => d.id));
  if (storedIds.length && !storedIds.some((id) => keep.has(id))) {
    throw new Error(
      `None of the ${storedIds.length} stored ids is in the file, so --prune would delete them all. ` +
        "Check the file. Nothing was uploaded or deleted.",
    );
  }
}

function printComparison(label, result, stale, prune) {
  console.log(`\nCompared with: ${label}`);
  console.log(`Would add (${result.added.length}):`);
  result.added.forEach((id) => console.log(`  ${id}`));
  console.log(`Would change (${result.changed.length}):`);
  result.changed.forEach((c) => console.log(`  ${c.id}: ${c.fields.join(", ")}`));
  console.log(
    prune
      ? `Would delete with --prune (${stale.length}):`
      : `Not in the file, kept (add --prune to delete them) (${stale.length}):`,
  );
  stale.forEach((id) => console.log(`  ${id}`));
  console.log(`Unchanged: ${result.unchanged}`);
}

// ---------------------------------------------------------
// FIRESTORE
// ---------------------------------------------------------

// Loaded only when Firestore is used, so a dry run without --key works
// without `npm install` and never loads any credentials.
function openFirestore(key) {
  const admin = require("firebase-admin");
  if (key) {
    const keyPath = path.resolve(key);
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(fs.readFileSync(keyPath, "utf8"))),
      projectId: PROJECT_ID,
    });
  } else {
    // Uses GOOGLE_APPLICATION_CREDENTIALS or `gcloud auth application-default login`.
    admin.initializeApp({ projectId: PROJECT_ID });
  }
  return admin;
}

// ---------------------------------------------------------
// MAIN
// ---------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const docs = loadDocs(args.json);
  // An empty file is always a mistake: the upload would write nothing, and
  // --prune would then delete every English document.
  if (!docs.length) {
    throw new Error(
      `${path.basename(args.json)} has no opportunities. Nothing was uploaded or deleted.`,
    );
  }

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
    const toWrite = docs.map((d) => ({ id: d.id, data: uploadData(d) }));
    if (args.baseline) {
      // An old copy of the JSON, checked the same way as the main file.
      const old = loadDocs(args.baseline);
      // The same check the real run makes, so a wrong file stops here too.
      if (args.prune) checkPrune(old.map((d) => d.id), docs);
      const before = new Map(old.map((d) => [d.id, uploadData(d)]));
      const stale = notInFile(old.map((d) => d.id), docs);
      printComparison(path.basename(args.baseline), compareDocs(toWrite, before), stale, args.prune);
      console.log(
        "Old documents without a 'language' field: not counted here (this needs Firestore: pass --key instead of --baseline)",
      );
    } else if (args.key) {
      // Read only: these queries never write. The English list is the same
      // query the real --prune uses, so the delete list matches it.
      const col = openFirestore(args.key).firestore().collection(COLLECTION);
      const snapshot = await col.where("language", "==", "en").get();
      const before = new Map(snapshot.docs.map((doc) => [doc.id, doc.data()]));
      if (args.prune) checkPrune([...before.keys()], docs);
      const stale = notInFile([...before.keys()], docs);
      const label = `Firestore '${COLLECTION}' (project ${PROJECT_ID})`;
      printComparison(label, compareDocs(toWrite, before), stale, args.prune);
      // The upload runs first and gives a document in the JSON a language
      // field, so --delete-old would only delete the ones not in the JSON.
      const keep = new Set(docs.map((d) => d.id));
      const oldDocs = (await col.select("language").get()).docs.filter(
        (doc) => doc.get("language") === undefined && !keep.has(doc.id),
      );
      console.log(
        `Old documents without a 'language' field: ${oldDocs.length} (deleted only with --delete-old)`,
      );
    } else {
      console.log(
        "\nTo list what an upload would add, change and delete, pass --baseline <old file> or --key <service.json> (read only).",
      );
    }
    console.log("\nDry run only - nothing was uploaded or deleted.");
    return;
  }

  const admin = openFirestore(args.key);
  const db = admin.firestore();
  const col = db.collection(COLLECTION);
  const now = admin.firestore.FieldValue.serverTimestamp();

  // With --prune, the stored English ids are read and checked before anything
  // is written, so a wrong file stops the run with Firestore unchanged.
  let english = [];
  if (args.prune) {
    english = (await col.where("language", "==", "en").select().get()).docs;
    checkPrune(english.map((doc) => doc.id), docs);
  }

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_SIZE).forEach((d) => {
      batch.set(col.doc(d.id), { ...uploadData(d), updatedAt: now });
    });
    await batch.commit();
    console.log(`Uploaded ${Math.min(i + BATCH_SIZE, docs.length)} / ${docs.length}`);
  }

  if (args.prune) {
    // Only English documents whose id is no longer in the JSON. The old
    // Arabic documents (no `language` field) are left to --delete-old. The
    // list was read before the upload; the upload only writes ids that are
    // in the JSON, so reading again afterwards would give the same list.
    const keep = new Set(docs.map((d) => d.id));
    const stale = english.filter((doc) => !keep.has(doc.id));
    for (let i = 0; i < stale.length; i += BATCH_SIZE) {
      const batch = db.batch();
      stale.slice(i, i + BATCH_SIZE).forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
    console.log(`Pruned ${stale.length} English documents that are no longer in the JSON.`);
    stale.map((doc) => doc.id).sort().forEach((id) => console.log(`  ${id}`));
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
  console.error("Stopped:", err.message);
  process.exit(1);
});
