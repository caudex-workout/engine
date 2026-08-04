import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const TOOL_VERSION = "caudex-exercise-catalog/1";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const sourcePath = resolve(valueArg("--source") ?? resolve(root, "catalog/upstream/exercises.json"));
const schemaPath = resolve(valueArg("--schema") ?? resolve(root, "catalog/upstream/schema.json"));
const manifestPath = resolve(valueArg("--manifest") ?? resolve(root, "catalog/source-manifest.json"));
const outputPath = resolve(valueArg("--output") ?? resolve(root, "catalog/generated/catalog.json"));
const check = process.argv.includes("--check");

const [sourceBytes, schemaBytes, manifestBytes] = await Promise.all([
  readFile(sourcePath),
  readFile(schemaPath),
  readFile(manifestPath),
]);
const manifest = JSON.parse(manifestBytes);
assert(manifest.transformationToolVersion === TOOL_VERSION, "transformation tool version mismatch");
assert(manifest.upstreamDataSha256 === sha256(sourceBytes), "upstream data snapshot fingerprint mismatch");
assert(manifest.upstreamSchemaSha256 === sha256(schemaBytes), "upstream schema fingerprint mismatch");

const source = JSON.parse(sourceBytes);
assert(Array.isArray(source) && source.length <= 2000, "upstream exercise count exceeds the explicit limit");
const ids = new Set();
const normalizedIds = new Map();
const records = source.map(normalizeRecord).sort((left, right) => left.id.localeCompare(right.id, "en"));
const recordBytes = Buffer.from(JSON.stringify(records));
const fingerprint = sha256(recordBytes);
const document = {
  schemaVersion: 1,
  catalogId: "caudex.free-exercise-db",
  version: manifest.upstreamCommit,
  fingerprint,
  recordCount: records.length,
  mediaIncluded: false,
  records,
};
const output = `${JSON.stringify(document, null, 2)}\n`;

if (check) {
  const checked = await readFile(outputPath, "utf8");
  assert(checked === output, "generated catalog drift detected; run the generator without --check");
  assert(manifest.normalizedOutputFingerprint === fingerprint, "source manifest output fingerprint is stale");
  console.log(`caudex exercise catalog verified: ${records.length} records, ${fingerprint}`);
} else {
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, output);
  manifest.normalizedOutputFingerprint = fingerprint;
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`caudex exercise catalog generated: ${records.length} records, ${fingerprint}`);
}

function normalizeRecord(input, index) {
  assertObject(input, `record ${index}`);
  assertString(input.id, `record ${index} id`, 200);
  assertString(input.name, `record ${index} name`, 500);
  assert(!ids.has(input.id), `duplicate upstream ID: ${input.id}`);
  ids.add(input.id);
  const normalizedId = normalizeTaxonomy(input.id);
  const collision = normalizedIds.get(normalizedId);
  assert(collision === undefined, `normalized upstream ID collision: ${collision} and ${input.id}`);
  normalizedIds.set(normalizedId, input.id);
  const primaryMuscles = normalizeTaxonomyList(input.primaryMuscles, "primaryMuscles", input.id);
  const secondaryMuscles = normalizeTaxonomyList(input.secondaryMuscles, "secondaryMuscles", input.id);
  const instructions = normalizeStrings(input.instructions, "instructions", input.id, 128, 10000, true);
  const force = nullableEnum(input.force, ["pull", "push", "static"], "force", input.id);
  const level = nullableEnum(input.level, ["beginner", "intermediate", "expert"], "level", input.id);
  const mechanic = nullableEnum(input.mechanic, ["compound", "isolation"], "mechanic", input.id);
  const equipment = nullableString(input.equipment, "equipment", input.id);
  const category = nullableString(input.category, "category", input.id);
  return {
    id: `free-exercise-db:${input.id}`,
    upstreamId: input.id,
    name: input.name,
    aliases: [input.id],
    force,
    difficulty: level,
    mechanic,
    equipment: equipment === null ? null : { sourceValue: equipment, id: `free-exercise-db.equipment:${normalizeTaxonomy(equipment)}` },
    primaryMuscles: primaryMuscles.map((value) => ({ sourceValue: value, id: `free-exercise-db.muscle:${normalizeTaxonomy(value)}` })),
    secondaryMuscles: secondaryMuscles.map((value) => ({ sourceValue: value, id: `free-exercise-db.muscle:${normalizeTaxonomy(value)}` })),
    instructions,
    category,
    movementPatterns: [],
    source: {
      dataset: "free-exercise-db",
      upstreamRepository: manifest.upstreamRepository,
      upstreamCommit: manifest.upstreamCommit,
      upstreamId: input.id,
      license: manifest.license,
    },
  };
}

function normalizeTaxonomyList(value, field, id) {
  return normalizeStrings(value, field, id, 128, 200);
}

function normalizeStrings(value, field, id, maxItems, maxLength, allowEmpty = false) {
  assert(Array.isArray(value) && value.length <= maxItems, `${id} ${field} exceeds its collection limit`);
  return value.map((item, index) => {
    if (allowEmpty) assert(typeof item === "string" && item.length <= maxLength, `${id} ${field}[${index}] is invalid`);
    else assertString(item, `${id} ${field}[${index}]`, maxLength);
    return item;
  });
}

function nullableEnum(value, choices, field, id) {
  if (value === null) return null;
  assertString(value, `${id} ${field}`, 200);
  assert(choices.includes(value), `${id} has unknown ${field}: ${value}`);
  return value;
}

function nullableString(value, field, id) {
  if (value === null) return null;
  assertString(value, `${id} ${field}`, 200);
  return value;
}

function normalizeTaxonomy(value) {
  return value.normalize("NFKD").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function assertString(value, label, maxLength) {
  assert(typeof value === "string" && value.length > 0 && value.length <= maxLength, `${label} is invalid`);
}

function assertObject(value, label) {
  assert(value !== null && typeof value === "object" && !Array.isArray(value), `${label} is not an object`);
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function valueArg(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return null;
  const value = process.argv[index + 1];
  if (!value || value.startsWith("--")) throw new Error(`${name} requires a path`);
  return value;
}
