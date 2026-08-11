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
  schemaVersion: 1; familyId?: string | null; variantDimensions: ReadonlyArray<{ dimension: string; value: string }>; movementPatterns: readonly string[];
  structuralType?: "compound" | "isolation" | "isometric" | "locomotor" | "conditioning" | "mobility" | "other" | null;
  laterality?: "bilateral" | "unilateral" | "alternating" | "independent_bilateral" | "not_applicable" | "unknown" | null;
  repetitionSemantics?: "total" | "per_side" | "alternating_total" | "left_right_independent" | "not_applicable" | "unknown" | null;
  equipmentRequirements: readonly EquipmentRequirement[]; trackingDimensions: readonly TrackingDimension[];
  loadingMode?: "external_load" | "bodyweight" | "bodyweight_plus_load" | "assisted_bodyweight" | "repetitions_only" | "duration" | "distance" | "load_duration" | "distance_duration" | "machine_load" | "other" | null;
  progressionCapabilities: ProgressionCapabilities; restrictionTags: readonly string[]; relationships: ExerciseRelationships;
  skillLevel?: "beginner_friendly" | "intermediate" | "advanced_technical" | "highly_technical" | "unknown" | null;
  stabilityDemand?: "externally_stabilized" | "supported" | "free" | "highly_unstable" | "unknown" | null; setupBurden?: "trivial" | "low" | "moderate" | "high" | "unknown" | null;
  fatigue: Partial<Record<"localMuscular" | "axial" | "systemic" | "grip" | "cardiorespiratory" | "technical", "low" | "moderate" | "high" | "unknown" | null>>; evidence: readonly KnowledgeEvidence[];
}
export interface ExerciseCatalogRecord { id: string; upstreamId: string; name: string; aliases: readonly string[]; force: string | null; difficulty: string | null; mechanic: string | null; equipment: TaxonomyRef | null; primaryMuscles: readonly TaxonomyRef[]; secondaryMuscles: readonly TaxonomyRef[]; instructions: readonly string[]; category: string | null; movementPatterns: readonly string[]; knowledge: ExerciseKnowledge | null; source: CatalogSourceProvenance }
export interface ExerciseProjection { id: string; name: string; aliases: string[]; equipmentIds: string[]; movementTags: string[]; unilateral?: boolean; muscleContributions: Array<{ muscleId: string; role: "primary" | "secondary" }>; knowledge?: ExerciseKnowledge }
export interface CapabilityProjection { knowledge: ExerciseKnowledge; trackingDimensions: readonly TrackingDimension[]; progressionCapabilities: ProgressionCapabilities }
export interface CuratedRelationship { kind: "variant" | "substitute" | "similar" | "shared_progression_state"; exerciseId: string }
export interface CatalogDocument { schemaVersion: 2; catalogId: string; version: string; fingerprint: string; baseVersion: string; baseFingerprint: string; enrichmentVersion: string; enrichmentFingerprint: string; enrichmentRecordCount: number; recordCount: number; mediaIncluded: false; records: readonly ExerciseCatalogRecord[] }
export interface SearchQuery { text?: string; equipmentId?: string; muscleId?: string; difficulty?: string; category?: string; force?: string; mechanic?: string; movementPattern?: string; familyId?: string; loadingMode?: NonNullable<ExerciseKnowledge["loadingMode"]>; structuralType?: NonNullable<ExerciseKnowledge["structuralType"]>; trackingMetric?: string; progressionCapability?: keyof ProgressionCapabilities; relationshipKind?: CuratedRelationship["kind"]; relatedExerciseId?: string; limit?: number }
export declare const catalog: CatalogDocument;
export declare const records: readonly ExerciseCatalogRecord[];
export declare const version: string;
export declare const fingerprint: string;
export declare function search(query?: SearchQuery): ExerciseCatalogRecord[];
export declare function project(record: ExerciseCatalogRecord): ExerciseProjection;
export declare function projectKnowledge(record: ExerciseCatalogRecord): ExerciseKnowledge | undefined;
export declare function projectCapabilities(record: ExerciseCatalogRecord): CapabilityProjection | undefined;
export declare function supportsProgressionCapability(record: ExerciseCatalogRecord, capability: keyof ProgressionCapabilities): boolean;
export declare function relationships(record: ExerciseCatalogRecord, query?: Pick<SearchQuery, "relationshipKind" | "relatedExerciseId">): CuratedRelationship[];
export declare function mergeCatalog(overrides: readonly ExerciseCatalogRecord[]): ExerciseCatalogRecord[];
