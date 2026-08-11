import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const TOOL_VERSION = "caudex-exercise-catalog/1";
const EQUIPMENT_NORMALIZATION = new Map([
  ["medicine ball", "medicine-ball"], ["dumbbell", "dumbbell"], ["body only", "bodyweight"], ["bands", "bands"],
  ["kettlebells", "kettlebell"], ["foam roll", "foam-roller"], ["cable", "cable"], ["machine", "machine"],
  ["barbell", "barbell"], ["exercise ball", "stability-ball"], ["e-z curl bar", "ez-curl-bar"], ["other", "other"],
]);
const MUSCLE_NORMALIZATION = new Map([
  ["abdominals", "abdominals"], ["abductors", "abductors"], ["adductors", "adductors"], ["biceps", "biceps"], ["calves", "calves"], ["chest", "chest"], ["forearms", "forearms"], ["glutes", "glutes"], ["hamstrings", "hamstrings"], ["lats", "lats"], ["lower back", "lower-back"], ["middle back", "middle-back"], ["neck", "neck"], ["quadriceps", "quadriceps"], ["shoulders", "shoulders"], ["traps", "traps"], ["triceps", "triceps"],
]);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const sourcePath = resolve(valueArg("--source") ?? resolve(root, "catalog/upstream/exercises.json"));
const schemaPath = resolve(valueArg("--schema") ?? resolve(root, "catalog/upstream/schema.json"));
const manifestPath = resolve(valueArg("--manifest") ?? resolve(root, "catalog/source-manifest.json"));
const enrichmentPath = resolve(valueArg("--enrichment") ?? resolve(root, "catalog/enrichment.json"));
const outputPath = resolve(valueArg("--output") ?? resolve(root, "catalog/generated/catalog.json"));
const check = process.argv.includes("--check");
const coverage = process.argv.includes("--coverage");

const [sourceBytes, schemaBytes, manifestBytes, enrichmentBytes] = await Promise.all([
  readFile(sourcePath),
  readFile(schemaPath),
  readFile(manifestPath),
  readFile(enrichmentPath),
]);
const manifest = JSON.parse(manifestBytes);
assert(manifest.transformationToolVersion === TOOL_VERSION, "transformation tool version mismatch");
assert(manifest.upstreamDataSha256 === sha256(sourceBytes), "upstream data snapshot fingerprint mismatch");
assert(manifest.upstreamSchemaSha256 === sha256(schemaBytes), "upstream schema fingerprint mismatch");

const source = JSON.parse(sourceBytes);
assert(Array.isArray(source) && source.length <= 2000, "upstream exercise count exceeds the explicit limit");
const ids = new Set();
const normalizedIds = new Map();
const baseRecords = source.map(normalizeRecord).sort((left, right) => left.id.localeCompare(right.id, "en"));
const baseFingerprint = sha256(Buffer.from(JSON.stringify(baseRecords)));
const enrichment = normalizeEnrichment(JSON.parse(enrichmentBytes), baseRecords, baseFingerprint);
const enrichmentFingerprint = sha256(Buffer.from(JSON.stringify(enrichment.entries)));
const records = applyEnrichment(baseRecords, enrichment.entries);
const recordBytes = Buffer.from(JSON.stringify(records));
const fingerprint = sha256(recordBytes);
const document = {
  schemaVersion: 2,
  catalogId: "caudex.free-exercise-db",
  version: enrichment.version,
  fingerprint,
  baseVersion: manifest.upstreamCommit,
  baseFingerprint,
  enrichmentVersion: enrichment.version,
  enrichmentFingerprint,
  enrichmentRecordCount: enrichment.entries.length,
  recordCount: records.length,
  mediaIncluded: false,
  records,
};
const output = `${JSON.stringify(document, null, 2)}\n`;

if (coverage) {
  console.log(JSON.stringify(coverageReport(records, enrichment.entries), null, 2));
} else if (check) {
  const checked = await readFile(outputPath, "utf8");
  assert(checked === output, "generated catalog drift detected; run the generator without --check");
  assert(manifest.normalizedOutputFingerprint === fingerprint, "source manifest output fingerprint is stale");
  console.log(`caudex exercise catalog verified: ${records.length} records, ${fingerprint}; ${enrichment.entries.length} enriched`);
} else {
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, output);
  manifest.normalizedOutputFingerprint = fingerprint;
  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`caudex exercise catalog generated: ${records.length} records, ${fingerprint}; ${enrichment.entries.length} enriched`);
}

function normalizeEnrichment(input, baseRecords, baseFingerprint) {
  assertObject(input, "enrichment");
  assert(input.schemaVersion === 1, "unsupported enrichment schema version");
  assert(input.catalogId === "caudex.free-exercise-db", "enrichment catalog ID mismatch");
  assert(input.baseVersion === manifest.upstreamCommit, "enrichment base version is stale");
  assert(input.baseFingerprint === baseFingerprint, `enrichment base fingerprint is stale; expected ${baseFingerprint}`);
  assertString(input.version, "enrichment version", 200);
  assertObject(input.source, "enrichment source");
  assertString(input.source.dataset, "enrichment source dataset", 200);
  assertString(input.source.license, "enrichment source license", 200);
  assert(Array.isArray(input.entries) && input.entries.length <= baseRecords.length, "enrichment entries exceed catalog size");
  const baseIds = new Set(baseRecords.map((record) => record.id));
  const entryIds = new Set();
  const entries = input.entries.map((entry, index) => {
    assertObject(entry, `enrichment entry ${index}`);
    assertString(entry.exerciseId, `enrichment entry ${index} exerciseId`, 500);
    assert(baseIds.has(entry.exerciseId), `enrichment references missing exercise ID: ${entry.exerciseId}`);
    assert(!entryIds.has(entry.exerciseId), `duplicate enrichment exercise ID: ${entry.exerciseId}`);
    entryIds.add(entry.exerciseId);
    return { exerciseId: entry.exerciseId, knowledge: normalizeKnowledge(entry.knowledge, entry.exerciseId, baseIds, input.version) };
  }).sort((left, right) => left.exerciseId.localeCompare(right.exerciseId, "en"));
  return { version: input.version, entries };
}

function normalizeKnowledge(input, id, baseIds, version) {
  assertObject(input, `${id} knowledge`);
  const familyId = nullableIdentifier(input.familyId, "familyId", id);
  const variantDimensions = normalizeVariantDimensions(input.variantDimensions ?? [], id);
  const movementPatterns = normalizeIdentifiers(input.movementPatterns, "movementPatterns", id);
  const structuralType = nullableEnum(input.structuralType, ["compound", "isolation", "isometric", "locomotor", "conditioning", "mobility", "other"], "structuralType", id);
  const laterality = nullableEnum(input.laterality, ["bilateral", "unilateral", "alternating", "independent_bilateral", "not_applicable", "unknown"], "laterality", id);
  const repetitionSemantics = nullableEnum(input.repetitionSemantics, ["total", "per_side", "alternating_total", "left_right_independent", "not_applicable", "unknown"], "repetitionSemantics", id);
  const equipmentRequirements = normalizeEquipmentRequirements(input.equipmentRequirements ?? [], id);
  const trackingDimensions = normalizeTrackingDimensions(input.trackingDimensions ?? [], id);
  const loadingMode = nullableEnum(input.loadingMode, ["external_load", "bodyweight", "bodyweight_plus_load", "assisted_bodyweight", "repetitions_only", "duration", "distance", "load_duration", "distance_duration", "machine_load", "other"], "loadingMode", id);
  const progressionCapabilities = normalizeProgressionCapabilities(input.progressionCapabilities, id);
  const restrictionTags = normalizeIdentifiers(input.restrictionTags ?? [], "restrictionTags", id);
  const relationships = normalizeRelationships(input.relationships ?? {}, id, baseIds);
  const skillLevel = nullableEnum(input.skillLevel, ["beginner_friendly", "intermediate", "advanced_technical", "highly_technical", "unknown"], "skillLevel", id);
  const stabilityDemand = nullableEnum(input.stabilityDemand, ["externally_stabilized", "supported", "free", "highly_unstable", "unknown"], "stabilityDemand", id);
  const setupBurden = nullableEnum(input.setupBurden, ["trivial", "low", "moderate", "high", "unknown"], "setupBurden", id);
  const fatigue = normalizeFatigue(input.fatigue, id);
  return {
    schemaVersion: 1, familyId, variantDimensions, movementPatterns, structuralType, laterality, repetitionSemantics,
    equipmentRequirements, trackingDimensions, loadingMode, progressionCapabilities, restrictionTags, relationships,
    skillLevel, stabilityDemand, setupBurden, fatigue,
    evidence: [{ authority: "caudex_curated", sourceId: `catalog/enrichment.json#${id}`, version, confidence: "high" }],
  };
}

function normalizeIdentifiers(value, field, id) {
  assert(Array.isArray(value) && value.length <= 32, `${id} ${field} exceeds its collection limit`);
  const seen = new Set();
  return value.map((item, index) => {
    assertString(item, `${id} ${field}[${index}]`, 64);
    assert(/^[a-z][a-z0-9-]*$/.test(item), `${id} ${field}[${index}] is not a stable identifier`);
    assert(!seen.has(item), `${id} has duplicate ${field} value: ${item}`);
    seen.add(item);
    return item;
  }).sort((left, right) => left.localeCompare(right, "en"));
}

function nullableIdentifier(value, field, id) {
  if (value === undefined || value === null) return null;
  return normalizeIdentifiers([value], field, id)[0];
}

function normalizeVariantDimensions(value, id) {
  assert(Array.isArray(value) && value.length <= 16, `${id} variantDimensions exceeds its collection limit`);
  const seen = new Set();
  return value.map((item, index) => {
    assertObject(item, `${id} variantDimensions[${index}]`);
    const dimension = normalizeIdentifiers([item.dimension], "variant dimension", id)[0];
    const itemValue = normalizeIdentifiers([item.value], "variant value", id)[0];
    assert(!seen.has(dimension), `${id} has duplicate variant dimension: ${dimension}`);
    seen.add(dimension);
    return { dimension, value: itemValue };
  }).sort((left, right) => left.dimension.localeCompare(right.dimension, "en"));
}

function normalizeEquipmentRequirements(value, id) {
  assert(Array.isArray(value) && value.length <= 16, `${id} equipmentRequirements exceeds its collection limit`);
  const seen = new Set();
  return value.map((item, index) => {
    assertObject(item, `${id} equipmentRequirements[${index}]`);
    assertString(item.equipmentId, `${id} equipmentRequirements[${index}] equipmentId`, 200);
    assert(/^[a-z][a-z0-9.-]*:[a-z][a-z0-9-]*$/.test(item.equipmentId), `${id} equipment requirement has invalid ID: ${item.equipmentId}`);
    const requirement = nullableEnum(item.requirement ?? "required", ["required", "optional", "one_of"], "equipment requirement", id);
    const role = nullableEnum(item.role ?? "other", ["load_bearing", "support", "setup", "other"], "equipment role", id);
    const alternativeGroup = nullableIdentifier(item.alternativeGroup, "alternativeGroup", id);
    const key = `${item.equipmentId}\u0000${requirement}\u0000${role}\u0000${alternativeGroup ?? ""}`;
    assert(!seen.has(key), `${id} has duplicate equipment requirement: ${item.equipmentId}`);
    seen.add(key);
    return { equipmentId: item.equipmentId, requirement, role, alternativeGroup };
  }).sort((left, right) => left.equipmentId.localeCompare(right.equipmentId, "en"));
}

function normalizeTrackingDimensions(value, id) {
  assert(Array.isArray(value) && value.length <= 16, `${id} trackingDimensions exceeds its collection limit`);
  const seen = new Set();
  return value.map((item, index) => {
    assertObject(item, `${id} trackingDimensions[${index}]`);
    const metricCode = normalizeIdentifiers([item.metricCode], "tracking metric", id)[0];
    const requirement = nullableEnum(item.requirement ?? "required", ["required", "optional"], "tracking requirement", id);
    const scope = nullableEnum(item.scope ?? "total", ["total", "per_side", "per_hand", "left_right_independent"], "tracking scope", id);
    assert(!seen.has(metricCode), `${id} has duplicate tracking metric: ${metricCode}`);
    seen.add(metricCode);
    return { metricCode, requirement, scope };
  }).sort((left, right) => left.metricCode.localeCompare(right.metricCode, "en"));
}

function normalizeProgressionCapabilities(value, id) {
  assertObject(value, `${id} progressionCapabilities`);
  const allowed = ["externalLoad", "repetitions", "percentageOneRepMax", "effortTarget", "amrap", "failureTraining", "duration", "distance", "assistanceReduction"];
  for (const key of Object.keys(value)) assert(allowed.includes(key), `${id} has unknown progression capability: ${key}`);
  const output = {};
  for (const key of allowed) if (value[key] !== undefined) {
    assert(typeof value[key] === "boolean", `${id} progression capability ${key} must be boolean`);
    output[key] = value[key];
  }
  return output;
}

function normalizeRelationships(value, id, baseIds) {
  assertObject(value, `${id} relationships`);
  const allowed = ["variantOf", "variantIds", "substituteIds", "similarExerciseIds", "sharedProgressionStateIds"];
  for (const key of Object.keys(value)) assert(allowed.includes(key), `${id} has unknown relationship field: ${key}`);
  const variantOf = value.variantOf === undefined ? null : normalizeRelationshipId(value.variantOf, "variantOf", id, baseIds);
  const normalizeList = (field) => {
    const values = value[field] ?? [];
    assert(Array.isArray(values) && values.length <= 32, `${id} ${field} exceeds its collection limit`);
    const seen = new Set();
    return values.map((target, index) => {
      const normalized = normalizeRelationshipId(target, `${field}[${index}]`, id, baseIds);
      assert(!seen.has(normalized), `${id} has duplicate ${field} relationship: ${normalized}`);
      seen.add(normalized);
      return normalized;
    }).sort((left, right) => left.localeCompare(right, "en"));
  };
  return { variantOf, variantIds: normalizeList("variantIds"), substituteIds: normalizeList("substituteIds"), similarExerciseIds: normalizeList("similarExerciseIds"), sharedProgressionStateIds: normalizeList("sharedProgressionStateIds") };
}

function normalizeRelationshipId(value, field, id, baseIds) {
  assertString(value, `${id} ${field}`, 500);
  assert(value !== id, `${id} ${field} cannot target itself`);
  assert(baseIds.has(value), `${id} ${field} references missing exercise ID: ${value}`);
  return value;
}

function normalizeFatigue(value, id) {
  assertObject(value, `${id} fatigue`);
  const allowed = ["localMuscular", "axial", "systemic", "grip", "cardiorespiratory", "technical"];
  const output = {};
  for (const key of Object.keys(value)) assert(allowed.includes(key), `${id} has unknown fatigue dimension: ${key}`);
  for (const key of allowed) if (value[key] !== undefined) output[key] = nullableEnum(value[key], ["low", "moderate", "high", "unknown"], `fatigue ${key}`, id);
  return output;
}

function applyEnrichment(baseRecords, entries) {
  const byId = new Map(entries.map((entry) => [entry.exerciseId, entry]));
  return baseRecords.map((record) => {
    const entry = byId.get(record.id);
    if (!entry) return { ...record, knowledge: null };
    return { ...record, movementPatterns: entry.knowledge.movementPatterns, knowledge: entry.knowledge };
  });
}

function coverageReport(records, entries) {
  const count = (predicate) => records.filter(predicate).length;
  const countsBy = (values) => Object.fromEntries([...values.reduce((counts, value) => {
    counts.set(value, (counts.get(value) ?? 0) + 1);
    return counts;
  }, new Map()).entries()].sort(([left], [right]) => left.localeCompare(right, "en")));
  return {
    schemaVersion: 1,
    catalogId: "caudex.free-exercise-db",
    baseRecordCount: records.length,
    enrichedRecordCount: entries.length,
    enrichedPercent: Number((entries.length * 100 / records.length).toFixed(2)),
    recordsByCategory: countsBy(records.map((record) => record.category ?? "unknown")),
    recordsByMovementPattern: countsBy(records.flatMap((record) => record.movementPatterns)),
    recordsByMuscle: countsBy(records.flatMap((record) => [...record.primaryMuscles, ...record.secondaryMuscles].map((muscle) => muscle.normalizedId))),
    recordsByEquipment: countsBy(records.map((record) => record.equipment?.normalizedId ?? "unknown")),
    movementPatternRecordCount: count((record) => record.movementPatterns.length !== 0),
    familyRecordCount: count((record) => record.knowledge?.familyId != null),
    missingFamilyRecordCount: count((record) => record.knowledge?.familyId == null),
    missingMovementClassificationRecordCount: count((record) => record.movementPatterns.length === 0),
    missingUsefulMuscleClassificationRecordCount: count((record) => record.primaryMuscles.length === 0 && record.secondaryMuscles.length === 0),
    unknownEquipmentRecordCount: count((record) => record.equipment == null),
    multiEquipmentRecordCount: count((record) => (record.knowledge?.equipmentRequirements.length ?? 0) > 1),
    trackingRecordCount: count((record) => (record.knowledge?.trackingDimensions.length ?? 0) !== 0),
    missingTrackingCapabilityRecordCount: count((record) => (record.knowledge?.trackingDimensions.length ?? 0) === 0),
    progressionCapabilityRecordCount: count((record) => record.knowledge?.progressionCapabilities != null && Object.values(record.knowledge.progressionCapabilities).some((value) => value === true)),
    missingProgressionCapabilityRecordCount: count((record) => record.knowledge?.progressionCapabilities == null || !Object.values(record.knowledge.progressionCapabilities).some((value) => value === true)),
    durationOnlyRecordCount: count((record) => record.knowledge?.loadingMode === "duration" && record.knowledge.trackingDimensions.every((dimension) => dimension.metricCode === "duration")),
    assistedBodyweightRecordCount: count((record) => record.knowledge?.loadingMode === "assisted_bodyweight"),
    machineLoadRecordCount: count((record) => record.knowledge?.loadingMode === "machine_load"),
    unilateralRecordCount: count((record) => record.knowledge?.laterality === "unilateral"),
    conditioningRecordCount: count((record) => record.knowledge?.structuralType === "conditioning"),
    technicalRecordCount: count((record) => ["advanced_technical", "highly_technical"].includes(record.knowledge?.skillLevel)),
    substituteRelationshipCount: records.reduce((total, record) => total + (record.knowledge?.relationships.substituteIds.length ?? 0), 0),
    recordsWithSubstitutesCount: count((record) => (record.knowledge?.relationships.substituteIds.length ?? 0) !== 0),
    recordsWithFatigueAnnotationsCount: count((record) => record.knowledge?.fatigue != null && Object.keys(record.knowledge.fatigue).length !== 0),
    recordsWithStabilityAnnotationsCount: count((record) => record.knowledge?.stabilityDemand != null),
    suspiciousRecordCount: 0,
    sharedProgressionStateRelationshipCount: records.reduce((total, record) => total + (record.knowledge?.relationships.sharedProgressionStateIds.length ?? 0), 0),
  };
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
    equipment: equipment === null ? null : normalizeTaxonomyRef(equipment, "equipment", EQUIPMENT_NORMALIZATION, input.id),
    primaryMuscles: primaryMuscles.map((value) => normalizeTaxonomyRef(value, "muscle", MUSCLE_NORMALIZATION, input.id)),
    secondaryMuscles: secondaryMuscles.map((value) => normalizeTaxonomyRef(value, "muscle", MUSCLE_NORMALIZATION, input.id)),
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

function normalizeTaxonomyRef(sourceValue, kind, knownValues, recordId) {
  const normalized = knownValues.get(sourceValue);
  assert(normalized !== undefined, `${recordId} has unknown ${kind} taxonomy value: ${sourceValue}`);
  return { sourceValue, sourceId: `free-exercise-db.${kind}:${normalizeTaxonomy(sourceValue)}`, normalizedId: `caudex.${kind}:${normalized}` };
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
