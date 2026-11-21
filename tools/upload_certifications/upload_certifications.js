#!/usr/bin/env node
/**
 * Uploads the Masra IT certifications CSV to Firestore.
 *
 *   node upload_certifications.js --dry-run            # parse + show summary, no upload
 *   node upload_certifications.js --key <service.json> # upload (or set GOOGLE_APPLICATION_CREDENTIALS)
 *   node upload_certifications.js --key <...> --prune  # also delete docs no longer in the CSV
 *   node upload_certifications.js --dry-run --prune --baseline <old.csv>  # what an upload would add, change and delete, compared with an old copy
 *   node upload_certifications.js --dry-run --prune --key <service.json>  # the same, compared with Firestore (read only)
 *
 * A dry run reads Firestore only when --key is given, and then only reads.
 * A --baseline dry run compares the CSV with an old copy of it (for example
 * the file as it was at the last upload) and needs no key. Its list equals
 * what an upload would do only if Firestore still holds that old copy; the
 * --key dry run gives the exact list.
 *
 * A CSV with no rows is refused. With --prune, the stored ids are read before
 * the upload, and the run stops with nothing written if none of them is in
 * the CSV (that would delete the whole collection, so the file is wrong).
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
  const args = { dryRun: false, prune: false, key: null, csv: DEFAULT_CSV, baseline: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--dry-run") args.dryRun = true;
    else if (a === "--prune") args.prune = true;
    else if (a === "--key") args.key = argv[++i];
    else if (a === "--csv") args.csv = argv[++i];
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

// Stops a --prune that would delete every stored document. That only happens
// with the wrong file (for example one with other ids), so the run stops
// before anything is written. An empty collection is fine: nothing to delete.
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
  const docs = loadDocs(args.csv);
  // An empty file is always a mistake: the upload would write nothing, and
  // --prune would then delete the whole collection.
  if (!docs.length) {
    throw new Error(
      `${path.basename(args.csv)} has no certifications. Nothing was uploaded or deleted.`,
    );
  }

  const byCategory = {};
  docs.forEach((d) => (byCategory[d.data.category] = (byCategory[d.data.category] || 0) + 1));
  console.log(`Parsed ${docs.length} certifications from ${path.basename(args.csv)}`);
  console.log(`Verified: ${docs.filter((d) => d.data.verified).length}`);
  console.log("By category:", byCategory);

  if (args.dryRun) {
    console.log("\nExample document:", JSON.stringify(docs[0], null, 2));
    if (args.baseline) {
      // An old copy of the CSV, checked the same way as the main file.
      const old = loadDocs(args.baseline);
      // The same check the real run makes, so a wrong file stops here too.
      if (args.prune) checkPrune(old.map((d) => d.id), docs);
      const before = new Map(old.map((d) => [d.id, d.data]));
      const stale = notInFile(old.map((d) => d.id), docs);
      printComparison(path.basename(args.baseline), compareDocs(docs, before), stale, args.prune);
    } else if (args.key) {
      // Read only: get() and listDocuments() never write.
      const col = openFirestore(args.key).firestore().collection(COLLECTION);
      const snapshot = await col.get();
      const before = new Map(snapshot.docs.map((doc) => [doc.id, doc.data()]));
      // The same list the real --prune uses, so the delete list matches it.
      const existing = await col.listDocuments();
      if (args.prune) checkPrune(existing.map((ref) => ref.id), docs);
      const stale = notInFile(existing.map((ref) => ref.id), docs);
      const label = `Firestore '${COLLECTION}' (project ${PROJECT_ID})`;
      printComparison(label, compareDocs(docs, before), stale, args.prune);
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

  // With --prune, the stored ids are read and checked before anything is
  // written, so a wrong file stops the run with Firestore unchanged.
  let existing = [];
  if (args.prune) {
    existing = await col.listDocuments();
    checkPrune(existing.map((ref) => ref.id), docs);
  }

  for (let i = 0; i < docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    docs.slice(i, i + BATCH_SIZE).forEach((d) => {
      batch.set(col.doc(d.id), { ...d.data, updatedAt: now });
    });
    await batch.commit();
    console.log(`Uploaded ${Math.min(i + BATCH_SIZE, docs.length)} / ${docs.length}`);
  }

  if (args.prune) {
    // The ids read before the upload. The upload only writes ids that are in
    // the CSV, so reading again afterwards would give the same delete list.
    const keep = new Set(docs.map((d) => d.id));
    const stale = existing.filter((ref) => !keep.has(ref.id));
    for (let i = 0; i < stale.length; i += BATCH_SIZE) {
      const batch = db.batch();
      stale.slice(i, i + BATCH_SIZE).forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
    console.log(`Pruned ${stale.length} documents that are no longer in the CSV.`);
    stale.map((ref) => ref.id).sort().forEach((id) => console.log(`  ${id}`));
  }

  console.log(`\nDone: ${docs.length} documents in '${COLLECTION}' (project ${PROJECT_ID}).`);
}

main().catch((err) => {
  console.error("Stopped:", err.message);
  process.exit(1);
});
