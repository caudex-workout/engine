import {
  catalog,
  fingerprint,
  mergeCatalog,
  project,
  projectCapabilities,
  projectKnowledge,
  records,
  search,
  version,
} from "../packages/exercise-catalog/src/index.ts";

if (records.length !== 873 || catalog.recordCount !== records.length) throw new Error("catalog record count changed unexpectedly");
if (fingerprint !== "1489c44273ece313784ef6322a9953bc695d368ef0415743ab988396cb195c8c") throw new Error("catalog fingerprint mismatch");
if (version !== "2026.08.10.2" || catalog.baseVersion !== "b0eed061e1c832b3ed815fbaa4b45b3cdc14df49" || catalog.mediaIncluded !== false) throw new Error("catalog provenance or media policy mismatch");
const [record] = search({ text: "alternate incline dumbbell curl", limit: 1 });
if (!record || record.upstreamId !== "Alternate_Incline_Dumbbell_Curl") throw new Error("catalog text search failed");
if ("images" in record || JSON.stringify(record).includes(".jpg")) throw new Error("catalog record exposed excluded media");
const projected = project(record);
if (projected.id !== record.id || projected.muscleContributions.length === 0) throw new Error("canonical projection failed");
if (record.equipment?.normalizedId !== "caudex.equipment:dumbbell" || !record.primaryMuscles.every((muscle) => muscle.normalizedId.startsWith("caudex.muscle:"))) throw new Error("catalog taxonomy mapping failed");
const [incline] = search({ familyId: "horizontal-press", loadingMode: "external_load", trackingMetric: "load", limit: 1 });
if (!incline || !projectKnowledge(incline)?.evidence.some((evidence) => evidence.authority === "caudex_curated" && evidence.version === catalog.enrichmentVersion) || !projectCapabilities(incline)?.progressionCapabilities.repetitions) throw new Error("catalog knowledge projection failed");
if (!search({ relatedExerciseId: "free-exercise-db:Dumbbell_Bench_Press", relationshipKind: "substitute", limit: 1 }).length) throw new Error("catalog relationship search failed");
if (records.some((candidate, index) => index > 0 && records[index - 1]!.id.localeCompare(candidate.id, "en") > 0)) throw new Error("catalog output ordering is unstable");
const replacement = { ...record, name: "Host replacement", source: { ...record.source, dataset: "host" } };
const merged = mergeCatalog([replacement]);
if (merged.find((candidate) => candidate.id === record.id)?.name !== "Host replacement") throw new Error("host override did not replace by stable ID");
try {
  mergeCatalog([replacement, replacement]);
  throw new Error("duplicate host overrides were accepted");
} catch (error) {
  if (!(error instanceof Error) || !error.message.includes("Duplicate catalog override ID")) throw error;
}
console.log(`caudex exercise catalog runtime passed: ${records.length} records, ${fingerprint}`);
