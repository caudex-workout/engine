import generated from "../../../catalog/generated/catalog.json" with { type: "json" };

export interface TaxonomyRef { sourceValue: string; id: string }
export interface CatalogSourceProvenance {
  dataset: string;
  upstreamRepository: string;
  upstreamCommit: string;
  upstreamId: string;
  license: string;
}
export interface ExerciseCatalogRecord {
  id: string;
  upstreamId: string;
  name: string;
  aliases: readonly string[];
  force: string | null;
  difficulty: string | null;
  mechanic: string | null;
  equipment: TaxonomyRef | null;
  primaryMuscles: readonly TaxonomyRef[];
  secondaryMuscles: readonly TaxonomyRef[];
  instructions: readonly string[];
  category: string | null;
  movementPatterns: readonly string[];
  source: CatalogSourceProvenance;
}
export interface ExerciseProjection {
  id: string;
  name: string;
  aliases: string[];
  equipmentIds: string[];
  movementTags: string[];
  muscleContributions: Array<{ muscleId: string; role: "primary" | "secondary" }>;
}
export interface CatalogDocument {
  schemaVersion: 1;
  catalogId: string;
  version: string;
  fingerprint: string;
  recordCount: number;
  mediaIncluded: false;
  records: readonly ExerciseCatalogRecord[];
}
export interface SearchQuery {
  text?: string;
  equipmentId?: string;
  muscleId?: string;
  difficulty?: string;
  category?: string;
  limit?: number;
}

export const catalog = generated as unknown as CatalogDocument;
export const records = catalog.records;
export const version = catalog.version;
export const fingerprint = catalog.fingerprint;

export function search(query: SearchQuery = {}): ExerciseCatalogRecord[] {
  const limit = query.limit ?? 50;
  if (!Number.isInteger(limit) || limit < 0 || limit > 256) throw new RangeError("Catalog search limit must be an integer from 0 through 256.");
  const text = query.text?.toLocaleLowerCase("en-US") ?? "";
  const output: ExerciseCatalogRecord[] = [];
  for (const record of records) {
    if (text && ![record.id, record.name, ...record.aliases].some((value) => value.toLocaleLowerCase("en-US").includes(text))) continue;
    if (query.equipmentId && record.equipment?.id !== query.equipmentId) continue;
    if (query.muscleId && ![...record.primaryMuscles, ...record.secondaryMuscles].some((value) => value.id === query.muscleId)) continue;
    if (query.difficulty && record.difficulty !== query.difficulty) continue;
    if (query.category && record.category !== query.category) continue;
    output.push(record);
    if (output.length === limit) break;
  }
  return output;
}

export function project(record: ExerciseCatalogRecord): ExerciseProjection {
  return {
    id: record.id,
    name: record.name,
    aliases: [...record.aliases],
    equipmentIds: record.equipment ? [record.equipment.id] : [],
    movementTags: [...record.movementPatterns],
    muscleContributions: [
      ...record.primaryMuscles.map((muscle) => ({ muscleId: muscle.id, role: "primary" as const })),
      ...record.secondaryMuscles.map((muscle) => ({ muscleId: muscle.id, role: "secondary" as const })),
    ],
  };
}

export function mergeCatalog(overrides: readonly ExerciseCatalogRecord[]): ExerciseCatalogRecord[] {
  const byId = new Map(records.map((record) => [record.id, record]));
  const seen = new Set<string>();
  for (const record of overrides) {
    if (seen.has(record.id)) throw new Error(`Duplicate catalog override ID: ${record.id}`);
    seen.add(record.id);
    byId.set(record.id, record);
  }
  return [...byId.values()].sort((left, right) => left.id.localeCompare(right.id, "en"));
}
