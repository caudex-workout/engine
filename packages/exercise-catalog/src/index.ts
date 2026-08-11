import generated from "../../../catalog/generated/catalog.json" with { type: "json" };

export interface TaxonomyRef { sourceValue: string; sourceId: string; normalizedId: string }
export interface CatalogSourceProvenance { dataset: string; upstreamRepository: string; upstreamCommit: string; upstreamId: string; license: string }
export type KnowledgeAuthority = "source_provided" | "caudex_curated" | "mechanically_derived" | "host_provided" | "unknown";
export type KnowledgeConfidence = "low" | "moderate" | "high" | "unknown";
export interface KnowledgeEvidence { authority: KnowledgeAuthority; sourceId?: string | null; version?: string | null; confidence: KnowledgeConfidence }
export interface EquipmentRequirement { equipmentId: string; requirement: "required" | "optional" | "one_of"; role: "load_bearing" | "support" | "setup" | "other"; alternativeGroup?: string | null }
export interface TrackingDimension { metricCode: string; requirement: "required" | "optional"; scope: "total" | "per_side" | "per_hand" | "left_right_independent" }
export interface ProgressionCapabilities { externalLoad?: boolean | null; repetitions?: boolean | null; percentageOneRepMax?: boolean | null; effortTarget?: boolean | null; amrap?: boolean | null; failureTraining?: boolean | null; duration?: boolean | null; distance?: boolean | null; assistanceReduction?: boolean | null }
export interface ExerciseRelationships { variantOf?: string | null; variantIds: readonly string[]; substituteIds: readonly string[]; similarExerciseIds: readonly string[]; sharedProgressionStateIds: readonly string[] }
export interface ExerciseKnowledge {
  schemaVersion: 1;
  familyId?: string | null;
  variantDimensions: ReadonlyArray<{ dimension: string; value: string }>;
  movementPatterns: readonly string[];
  structuralType?: "compound" | "isolation" | "isometric" | "locomotor" | "conditioning" | "mobility" | "other" | null;
  laterality?: "bilateral" | "unilateral" | "alternating" | "independent_bilateral" | "not_applicable" | "unknown" | null;
  repetitionSemantics?: "total" | "per_side" | "alternating_total" | "left_right_independent" | "not_applicable" | "unknown" | null;
  equipmentRequirements: readonly EquipmentRequirement[];
  trackingDimensions: readonly TrackingDimension[];
  loadingMode?: "external_load" | "bodyweight" | "bodyweight_plus_load" | "assisted_bodyweight" | "repetitions_only" | "duration" | "distance" | "load_duration" | "distance_duration" | "machine_load" | "other" | null;
  progressionCapabilities: ProgressionCapabilities;
  restrictionTags: readonly string[];
  relationships: ExerciseRelationships;
  skillLevel?: "beginner_friendly" | "intermediate" | "advanced_technical" | "highly_technical" | "unknown" | null;
  stabilityDemand?: "externally_stabilized" | "supported" | "free" | "highly_unstable" | "unknown" | null;
  setupBurden?: "trivial" | "low" | "moderate" | "high" | "unknown" | null;
  fatigue: Partial<Record<"localMuscular" | "axial" | "systemic" | "grip" | "cardiorespiratory" | "technical", "low" | "moderate" | "high" | "unknown" | null>>;
  evidence: readonly KnowledgeEvidence[];
}
export interface ExerciseCatalogRecord {
  id: string; upstreamId: string; name: string; aliases: readonly string[];
  force: string | null; difficulty: string | null; mechanic: string | null;
  equipment: TaxonomyRef | null; primaryMuscles: readonly TaxonomyRef[]; secondaryMuscles: readonly TaxonomyRef[];
  instructions: readonly string[]; category: string | null; movementPatterns: readonly string[];
  knowledge: ExerciseKnowledge | null; source: CatalogSourceProvenance;
}
export interface ExerciseProjection {
  id: string; name: string; aliases: string[]; equipmentIds: string[]; movementTags: string[]; unilateral?: boolean;
  muscleContributions: Array<{ muscleId: string; role: "primary" | "secondary" }>;
  knowledge?: ExerciseKnowledge;
}
export interface CapabilityProjection { knowledge: ExerciseKnowledge; trackingDimensions: readonly TrackingDimension[]; progressionCapabilities: ProgressionCapabilities }
export interface CuratedRelationship { kind: "variant" | "substitute" | "similar" | "shared_progression_state"; exerciseId: string }
export interface CatalogDocument {
  schemaVersion: 2; catalogId: string; version: string; fingerprint: string; baseVersion: string; baseFingerprint: string;
  enrichmentVersion: string; enrichmentFingerprint: string; enrichmentRecordCount: number; recordCount: number; mediaIncluded: false;
  records: readonly ExerciseCatalogRecord[];
}
export interface SearchQuery {
  text?: string; equipmentId?: string; muscleId?: string; difficulty?: string; category?: string; force?: string; mechanic?: string;
  movementPattern?: string; familyId?: string; loadingMode?: NonNullable<ExerciseKnowledge["loadingMode"]>;
  structuralType?: NonNullable<ExerciseKnowledge["structuralType"]>; trackingMetric?: string;
  progressionCapability?: keyof ProgressionCapabilities; relationshipKind?: CuratedRelationship["kind"]; relatedExerciseId?: string; limit?: number;
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
    if (query.equipmentId && record.equipment?.normalizedId !== query.equipmentId) continue;
    if (query.muscleId && ![...record.primaryMuscles, ...record.secondaryMuscles].some((value) => value.normalizedId === query.muscleId)) continue;
    if (query.difficulty && record.difficulty !== query.difficulty) continue;
    if (query.category && record.category !== query.category) continue;
    if (query.force && record.force !== query.force) continue;
    if (query.mechanic && record.mechanic !== query.mechanic) continue;
    if (query.movementPattern && !record.movementPatterns.includes(query.movementPattern)) continue;
    const knowledge = record.knowledge;
    if ((query.familyId || query.loadingMode || query.structuralType || query.trackingMetric || query.progressionCapability || query.relationshipKind || query.relatedExerciseId) && !knowledge) continue;
    if (query.familyId && knowledge?.familyId !== query.familyId) continue;
    if (query.loadingMode && knowledge?.loadingMode !== query.loadingMode) continue;
    if (query.structuralType && knowledge?.structuralType !== query.structuralType) continue;
    if (query.trackingMetric && !knowledge?.trackingDimensions.some((dimension) => dimension.metricCode === query.trackingMetric)) continue;
    if (query.progressionCapability && !supportsProgressionCapability(record, query.progressionCapability)) continue;
    if ((query.relationshipKind || query.relatedExerciseId) && !relationships(record, query).length) continue;
    output.push(record);
    if (output.length === limit) break;
  }
  return output;
}

export function project(record: ExerciseCatalogRecord): ExerciseProjection {
  const knowledge = projectKnowledge(record);
  const unilateral = knowledge?.laterality === "unilateral" ? true : knowledge?.laterality === "bilateral" ? false : undefined;
  return {
    id: record.id, name: record.name, aliases: [...record.aliases], equipmentIds: record.equipment ? [record.equipment.normalizedId] : [],
    movementTags: [...record.movementPatterns], ...(unilateral === undefined ? {} : { unilateral }),
    muscleContributions: [...record.primaryMuscles.map((muscle) => ({ muscleId: muscle.normalizedId, role: "primary" as const })), ...record.secondaryMuscles.map((muscle) => ({ muscleId: muscle.normalizedId, role: "secondary" as const }))],
    ...(knowledge ? { knowledge } : {}),
  };
}

/** Returns the fully typed canonical exercise-knowledge projection, if curated. */
export function projectKnowledge(record: ExerciseCatalogRecord): ExerciseKnowledge | undefined { return record.knowledge ?? undefined; }

export function projectCapabilities(record: ExerciseCatalogRecord): CapabilityProjection | undefined {
  const knowledge = projectKnowledge(record);
  return knowledge ? { knowledge, trackingDimensions: knowledge.trackingDimensions, progressionCapabilities: knowledge.progressionCapabilities } : undefined;
}

export function supportsProgressionCapability(record: ExerciseCatalogRecord, capability: keyof ProgressionCapabilities): boolean {
  return record.knowledge?.progressionCapabilities[capability] === true;
}

/** Returns curated relationships while keeping substitutes distinct from progression-state sharing. */
export function relationships(record: ExerciseCatalogRecord, query: Pick<SearchQuery, "relationshipKind" | "relatedExerciseId"> = {}): CuratedRelationship[] {
  const relation = record.knowledge?.relationships;
  if (!relation) return [];
  const output: CuratedRelationship[] = [
    ...(relation.variantOf ? [{ kind: "variant" as const, exerciseId: relation.variantOf }] : []),
    ...relation.variantIds.map((exerciseId) => ({ kind: "variant" as const, exerciseId })),
    ...relation.substituteIds.map((exerciseId) => ({ kind: "substitute" as const, exerciseId })),
    ...relation.similarExerciseIds.map((exerciseId) => ({ kind: "similar" as const, exerciseId })),
    ...relation.sharedProgressionStateIds.map((exerciseId) => ({ kind: "shared_progression_state" as const, exerciseId })),
  ];
  return output.filter((item) => (!query.relationshipKind || item.kind === query.relationshipKind) && (!query.relatedExerciseId || item.exerciseId === query.relatedExerciseId));
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
