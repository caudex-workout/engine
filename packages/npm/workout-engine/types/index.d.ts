export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface Measurement {
  amount: string;
  unit: string;
}
export { CaudexMeasurementError, kg, lb, load, metrics, minutes, reps, rir, rpe, seconds, type DecimalInput, type MassMeasurement } from "./measurements.js";
import type { DecimalInput, MassMeasurement } from "./measurements.js";

export interface Metric {
  code: string;
  value: Measurement;
}

export interface MuscleContribution {
  muscleId: string;
  role: "primary" | "secondary" | "stabilizer" | "custom";
  weight?: string;
}

export type KnowledgeAuthority = "source_provided" | "caudex_curated" | "mechanically_derived" | "host_provided" | "unknown";
export type KnowledgeConfidence = "low" | "moderate" | "high" | "unknown";
export interface KnowledgeEvidence { authority: KnowledgeAuthority; sourceId?: string; version?: string; confidence?: KnowledgeConfidence }
export interface EquipmentRequirement { equipmentId: string; equipmentFamilyId?: string; requirement?: "required" | "optional" | "one_of"; role?: "load_bearing" | "support" | "setup" | "other"; alternativeGroup?: string }
export interface TrackingDimension { metricCode: string; requirement?: "required" | "optional"; scope?: "total" | "per_side" | "per_hand" | "left_right_independent" }
export interface ProgressionCapabilities { externalLoad?: boolean; repetitions?: boolean; percentageOneRepMax?: boolean; effortTarget?: boolean; amrap?: boolean; failureTraining?: boolean; duration?: boolean; distance?: boolean; assistanceReduction?: boolean }
export interface ExerciseRelationships { variantOf?: string; variantIds?: string[]; substituteIds?: string[]; similarExerciseIds?: string[]; sharedProgressionStateIds?: string[] }
export interface ExerciseVariantDimension { dimension: string; value: string }
export interface ExerciseFatigue { localMuscular?: "low" | "moderate" | "high" | "unknown"; axial?: "low" | "moderate" | "high" | "unknown"; systemic?: "low" | "moderate" | "high" | "unknown"; grip?: "low" | "moderate" | "high" | "unknown"; cardiorespiratory?: "low" | "moderate" | "high" | "unknown"; technical?: "low" | "moderate" | "high" | "unknown" }
export interface ExerciseKnowledge {
  schemaVersion?: 1; familyId?: string; variantDimensions?: ExerciseVariantDimension[]; movementPatterns?: string[];
  structuralType?: "compound" | "isolation" | "isometric" | "locomotor" | "conditioning" | "mobility" | "other";
  laterality?: "bilateral" | "unilateral" | "alternating" | "independent_bilateral" | "not_applicable" | "unknown";
  repetitionSemantics?: "total" | "per_side" | "alternating_total" | "left_right_independent" | "not_applicable" | "unknown";
  equipmentRequirements?: EquipmentRequirement[]; trackingDimensions?: TrackingDimension[];
  loadingMode?: "external_load" | "bodyweight" | "bodyweight_plus_load" | "assisted_bodyweight" | "repetitions_only" | "duration" | "distance" | "load_duration" | "distance_duration" | "machine_load" | "other";
  progressionCapabilities?: ProgressionCapabilities; restrictionTags?: string[]; relationships?: ExerciseRelationships;
  skillLevel?: "beginner_friendly" | "intermediate" | "advanced_technical" | "highly_technical" | "unknown";
  stabilityDemand?: "externally_stabilized" | "supported" | "free" | "highly_unstable" | "unknown";
  setupBurden?: "trivial" | "low" | "moderate" | "high" | "unknown"; fatigue?: ExerciseFatigue; evidence?: KnowledgeEvidence[];
}

export interface Exercise {
  id: string;
  name?: string;
  equipmentIds?: string[];
  movementTags?: string[];
  muscleContributions?: MuscleContribution[];
  unilateral?: boolean;
  aliases?: string[];
  attributes?: JsonValue;
  knowledge?: ExerciseKnowledge;
}

export interface CompletedSet {
  id?: string;
  kind: string;
  actualMetrics: Metric[];
  targetMetrics?: Metric[];
  completedAt?: string;
  status: "completed" | "partial" | "skipped" | "failed";
}

export interface CompletedExercise {
  exerciseId: string;
  sets: CompletedSet[];
  tags?: string[];
  notes?: string;
}

export interface CompletedWorkout {
  id: string;
  startedAt: string;
  completedAt: string;
  exercises: CompletedExercise[];
}

export interface MethodologyRef<TConfig = JsonValue> {
  id: string;
  versionRequirement?: string;
  configVersion: number;
  config: TConfig;
}

export interface MethodologyState {
  schemaVersion: number;
  data: JsonValue;
}
export interface ProgramState { schemaVersion: number; data: JsonValue }
export interface ProgramStrategyRef<TConfig = JsonValue> { id: string; versionRequirement?: string; configVersion: number; config: TConfig }
export interface ProgressionAssignment<TConfig = JsonValue> { stateId: string; methodology: MethodologyRef<TConfig>; state?: MethodologyState }
export interface ProgramExerciseSlot<TConfig = JsonValue> { slotId: string; exerciseId: string; progression: ProgressionAssignment<TConfig> }
export interface ProgramRecommendationRequest {
  schemaVersion: 1; asOf: string;
  program: { strategy: ProgramStrategyRef; state?: ProgramState; exercises: ProgramExerciseSlot[]; trainingContext?: ProgramTrainingContext };
  catalog: Exercise[]; athleteProfile?: AthleteProfile; history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue }; trainingContext?: TrainingContext;
}

export type GoalId = "hypertrophy" | "strength" | "general-fitness" | "muscular-endurance" | "powerlifting-practice" | "limited-equipment" | "maintenance" | (string & {});
export interface Goal { id: GoalId; weight?: number }
export interface GoalSet { primary?: Goal; secondary?: Goal[]; bodyCompositionObjective?: string }
export type Familiarity = "unfamiliar" | "learning" | "familiar" | "proficient";
export interface Experience { resistanceTraining?: "novice" | "intermediate" | "advanced"; consistentMonths?: number; technicalLiftFamiliarity?: Familiarity; exercises?: Array<{ exerciseId: string; familiarity: Familiarity }> }
export interface SchedulePreference { preferredSessionsPerWeek?: number; minimumSessionsPerWeek?: number; maximumSessionsPerWeek?: number; preferredDays?: Array<"monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday">; cadence?: "unspecified" | "fixed_weekdays" | "rolling"; preferRestBetweenSessions?: boolean }
export interface DurationPreference { preferredMinutes?: number; acceptableMinimumMinutes?: number; acceptableMaximumMinutes?: number; hardMaximumMinutes?: number }
export interface UnitPreferences { load?: "kilograms" | "pounds"; bodyweight?: "kilograms" | "pounds"; distance?: "meters" | "kilometers" | "feet" | "miles" }
export type PreferenceTargetKind = "exercise" | "exercise_family" | "movement_pattern" | "equipment_category";
export type PreferenceLevel = "preferred" | "deprioritized" | "excluded" | "required";
export interface ExercisePreference { targetKind: PreferenceTargetKind; targetId: string; level: PreferenceLevel }
export interface MusclePriority { muscleId: string; priority: "emphasize" | "balanced" | "maintain" | "deprioritize"; weight?: number }
export interface TrainingRestriction { id: string; targetKind: "exercise" | "exercise_family" | "movement_pattern" | "restriction_tag" | "equipment"; targetId: string }
export interface EquipmentItem { equipmentId: string; minimumLoadIncrement?: Measurement }
export interface TrainingLocation { id: string; name?: string; equipment?: EquipmentItem[]; metadata?: JsonValue }
export interface CapabilityObservation { id: string; kind: "recent_performance" | "estimated_one_rep_max" | "assistance_capacity" | "exercise_familiarity" | "benchmark" | "custom"; exerciseId?: string; value?: Measurement; observedAt: string; provenance?: "athlete_reported" | "host_observed" | "device_supplied" | "imported" | "unknown"; customKindId?: string }
export interface AthleteProfile { schemaVersion?: 1; id: string; revision?: number; displayName?: string; goals?: GoalSet; experience?: Experience; schedule?: SchedulePreference; duration?: DurationPreference; units?: UnitPreferences; exercisePreferences?: ExercisePreference[]; musclePriorities?: MusclePriority[]; restrictions?: TrainingRestriction[]; locations?: TrainingLocation[]; capabilityObservations?: CapabilityObservation[]; metadata?: JsonValue }
export interface ReadinessObservation { id: string; dimension: "overall" | "fatigue" | "sleep_quality" | "pain" | "soreness"; subjectId?: string; value: number; scaleMaximum: number; observedAt: string; provenance?: "athlete_reported" | "host_observed" | "device_supplied" | "imported" | "unknown" }
export interface EquipmentDelta { override?: string[]; additions?: string[]; removals?: string[] }
export interface TrainingContext { locationId?: string; equipment?: EquipmentDelta; availableMinutes?: number; hardMaximumMinutes?: number; goals?: GoalSet; preferences?: ExercisePreference[]; restrictions?: TrainingRestriction[]; minExercises?: number; maxExercises?: number; maxSets?: number; excludedExerciseIds?: string[]; requiredExerciseIds?: string[]; readiness?: ReadinessObservation[] }
export interface ProgramTrainingContext { goals?: GoalSet; exercisePreferences?: ExercisePreference[]; musclePriorities?: MusclePriority[]; restrictions?: TrainingRestriction[]; requiredExerciseIds?: string[]; excludedExerciseIds?: string[] }
export type ContextSource = "engine_default" | "athlete_profile" | "program" | "location_profile" | "session" | "explicit_request";
export interface ResolvedTrainingContext { schemaVersion: 1; athleteProfileId: string; athleteProfileRevision: number; athleteProfileFingerprint: string; goals: GoalSet; experience: Experience; schedule: SchedulePreference; preferredDuration: DurationPreference; availableMinutes?: number; hardMaximumMinutes?: number; units: UnitPreferences; locationId?: string; availableEquipmentIds: string[]; preferences: Array<{ value: ExercisePreference; source: ContextSource }>; restrictions: Array<{ value: TrainingRestriction; source: ContextSource }>; musclePriorities: Array<{ value: MusclePriority; source: ContextSource }>; requiredExercises: Array<{ exerciseId: string; source: ContextSource }>; excludedExercises: Array<{ exerciseId: string; source: ContextSource }>; readiness: ReadinessObservation[]; capabilityObservations: CapabilityObservation[] }
export declare function defineAthleteProfile(profile: AthleteProfile): AthleteProfile;
export interface AthleteProfileDiff { fromRevision: number; toRevision: number; changedFields: string[] }
export declare function diffAthleteProfiles(before: AthleteProfile, after: AthleteProfile): AthleteProfileDiff;
export declare function resolveTrainingContext(profile: AthleteProfile, session?: TrainingContext, program?: ProgramTrainingContext, request?: TrainingContext): ResolvedTrainingContext;

export interface RecommendationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  trainingContext?: TrainingContext;
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

export interface EvaluationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  completedWorkout: CompletedWorkout;
}

export type Severity = "info" | "warning" | "error";

export interface ValidationIssue {
  code: string;
  path: string;
  message: string;
  severity: Severity;
  parameters?: JsonValue;
  suggestion?: string;
}

export interface Explanation {
  id: string;
  code: string;
  category: string;
  summary: string;
  subject?: { exerciseId?: string; setIndex?: number };
  evidence?: Array<{ path: string }>;
  parameters?: JsonValue;
  ruleId?: string;
  severity: Severity;
}

export interface SetRecommendation {
  kind: string;
  targetMetrics: Metric[];
  restDuration?: Measurement;
  explanationRefs?: string[];
}

export interface SessionRecommendation {
  title?: string;
  estimatedDuration?: Measurement;
  exercises: Array<{
    exerciseId: string;
    sets: SetRecommendation[];
    substitutionGroup?: string;
    explanationRefs?: string[];
    programming?: ExerciseProgrammingProvenance;
  }>;
  programming?: { strategy: ResolvedComponent; config: JsonValue; inputState?: ProgramState; resolvedTrainingContext?: ResolvedTrainingContext };
  resolvedTrainingContext?: ResolvedTrainingContext;
}
export interface ResolvedComponent { id: string; version: string; configVersion: number }
export interface ExerciseProgrammingProvenance { slotId: string; stateId: string; progression: ResolvedComponent; config: JsonValue; inputState?: MethodologyState }

export interface ResultMetadata {
  engineVersion: string;
  schemaVersion: number;
  methodology: { id: string; version: string; configVersion: number };
  inputFingerprint: string;
  resultFingerprint: string;
}

interface ProgrammingResultCommon {
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  metadata: ResultMetadata;
}
export type RecommendationResult = ProgrammingResultCommon & (
  | { ok: true; recommendation: SessionRecommendation; alternatives?: SessionRecommendation[]; nextMethodologyState?: MethodologyState; issues?: never }
  | { ok: false; recommendation?: never; alternatives?: never; nextMethodologyState?: never; issues: ValidationIssue[] }
);

export interface ExerciseEvaluation {
  exerciseId: string;
  outcome: string;
  explanationRefs?: string[];
}

export interface PerformanceEvaluation {
  outcome: string;
  exercises: ExerciseEvaluation[];
}

export type EvaluationResult = ProgrammingResultCommon & (
  | { ok: true; evaluation: PerformanceEvaluation; nextMethodologyState?: MethodologyState; issues?: never }
  | { ok: false; evaluation?: never; nextMethodologyState?: never; issues: ValidationIssue[] }
);
export interface ProgramEvaluationRequest { schemaVersion: 1; asOf: string; recommendation: SessionRecommendation; catalog: Exercise[]; athleteProfile?: AthleteProfile; history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue }; completedWorkout: CompletedWorkout }
export interface ProgramResultMetadata { engineVersion: string; schemaVersion: number; programStrategy: ResolvedComponent; inputFingerprint: string; resultFingerprint: string }
export type ProgramRecommendationResult =
  | { ok: true; recommendation: SessionRecommendation; explanations?: Explanation[]; warnings?: ValidationIssue[]; metadata: ProgramResultMetadata; issues?: never }
  | { ok: false; recommendation?: never; explanations?: Explanation[]; warnings?: ValidationIssue[]; issues: ValidationIssue[]; metadata: ProgramResultMetadata };
export interface ProgressionStateProposal { stateId: string; progression: ResolvedComponent; state: MethodologyState }
export type ProgramEvaluationResult =
  | { ok: true; evaluation: PerformanceEvaluation; nextProgramState?: ProgramState; progressionStateProposals: ProgressionStateProposal[]; explanations?: Explanation[]; warnings?: ValidationIssue[]; metadata: ProgramResultMetadata; issues?: never }
  | { ok: false; evaluation?: never; nextProgramState?: never; progressionStateProposals?: never; explanations?: Explanation[]; warnings?: ValidationIssue[]; issues: ValidationIssue[]; metadata: ProgramResultMetadata };

export type TrackingWorkoutStatus = "active" | "completed" | "cancelled";
export type TrackingSetStatus = "open" | "completed" | "partial" | "failed" | "skipped";
export type TrackingAvailability = "active" | "archived";
export interface TrackingIssue {
  code: string;
  category: "validation" | "not_found" | "conflict";
  severity: "warning" | "error";
  path?: string;
  message: string;
  relatedIds?: string[];
}
export interface TrackedSet {
  id: string;
  kind: string;
  targetMetrics?: Metric[];
  actualMetrics?: Metric[];
  status: TrackingSetStatus;
  recordedAt?: string;
}
export interface ExerciseMembership {
  id: string;
  exerciseId: string;
  sets?: TrackedSet[];
}
export interface TrackedWorkout {
  id: string;
  scope: { hostScopeKey: string; athleteId?: string };
  revision: number;
  status: TrackingWorkoutStatus;
  startedAt: string;
  completedAt?: string;
  exercises?: ExerciseMembership[];
  origin?: "manual" | "template" | "recommendation";
  provenance?: JsonValue;
  prescription?: JsonValue[];
}
export interface TrackingSnapshot {
  workouts?: TrackedWorkout[];
  startReceipts?: JsonValue[];
  exerciseCatalog?: Array<{ exerciseId: string; availability: TrackingAvailability }>;
}
export type TrackingCommand =
  | { startWorkout: Record<string, unknown> }
  | { addExercise: Record<string, unknown> }
  | { removeExercise: Record<string, unknown> }
  | { reorderExercise: Record<string, unknown> }
  | { addSet: Record<string, unknown> }
  | { completeSet: Record<string, unknown> }
  | { skipSet: Record<string, unknown> }
  | { reopenSet: Record<string, unknown> }
  | { removeSet: Record<string, unknown> }
  | { reorderSet: Record<string, unknown> }
  | { completeWorkout: Record<string, unknown> };
export interface TrackingCommandRequest { schemaVersion: 1; snapshot: TrackingSnapshot; command: TrackingCommand }
export interface TrackingBatchRequest { schemaVersion: 1; snapshot: TrackingSnapshot; commands: TrackingCommand[] }
export type TrackingCommandOutcome =
  | { accepted: { commandId: string; disposition: "applied" | "replayed"; workout: TrackedWorkout; warnings?: TrackingIssue[] } }
  | { rejected: { commandId: string; issues: TrackingIssue[] } };
export interface TrackingCommandResult { schemaVersion: 1; outcome: TrackingCommandOutcome; snapshot: TrackingSnapshot }
export interface TrackingBatchResult { schemaVersion: 1; applied: boolean; outcomes: TrackingCommandOutcome[]; snapshot: TrackingSnapshot; issues?: TrackingIssue[] }
export interface WorkoutTemplateDocument {
  schemaVersion: 1;
  id: string;
  displayName: string;
  description?: string;
  exercises: Array<{ exerciseId: string; sets?: Array<{ kind?: string; targetMetrics?: Metric[] }>; notes?: string; tags?: string[] }>;
  notes?: string;
  tags?: string[];
  revision: number;
}
export interface InstantiationIds { workoutId: string; membershipIds: string[]; setIds: string[] }
export interface RecommendationInstantiationRequest {
  schemaVersion: 1; recommendationResult: RecommendationResult; catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string }; ids: InstantiationIds; createdAt: string;
  acceptedRecommendationId: string; methodologyStateRevision?: string; methodologyStateFingerprint?: string;
}
export interface TemplateInstantiationRequest {
  schemaVersion: 1; template: WorkoutTemplateDocument; catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string }; ids: InstantiationIds; createdAt: string;
}
export interface CompletionConversionRequest { schemaVersion: 1; workout: TrackedWorkout; catalog: Exercise[] }
export type InstantiationResult = { schemaVersion: 1; outcome: { accepted: TrackedWorkout } | { rejected: TrackingIssue[] } };
export type CompletionConversionResult = { schemaVersion: 1; outcome: { accepted: CompletedWorkout } | { rejected: TrackingIssue[] } };
export type MethodologyOperation = "recommend" | "evaluate" | "validateConfig" | "validateState";
export type MethodologyFieldType = "integer" | "exactDecimal" | "measurement" | "enumeration" | "object" | "array" | "identifier";
export interface MethodologyFieldDescriptor {
  name: string; description: string; fieldType: MethodologyFieldType; required: boolean;
  defaultJson?: string; minimum?: string; maximum?: string; exactDecimal?: boolean;
  unitDimension?: string; enumChoices?: string[]; deprecated?: boolean;
}
export interface MethodologyDescriptor {
  id: string; displayName: string; description: string; methodologyVersion: string;
  configurationSchemaVersion: number; stateSchemaVersion: number;
  supportedOperations: MethodologyOperation[]; fields: MethodologyFieldDescriptor[];
  configurationSchemaRef: string; stateSchemaRef: string; deprecated?: boolean;
}
export interface ProgramStrategyDescriptor { id: string; displayName: string; description: string; strategyVersion: string; configurationSchemaVersion: number; stateSchemaVersion: number; supportedOperations: MethodologyOperation[]; configurationSchemaRef: string; stateSchemaRef?: string }
export interface DiscoveryRegistry { schemaVersion: 1; methodologies: MethodologyDescriptor[]; progressionMethods: MethodologyDescriptor[]; programStrategies: ProgramStrategyDescriptor[]; supportedOperations: string[] }
export type MethodologyValidationResult = { schemaVersion: 1; valid: true; issues: [] } | { schemaVersion: 1; valid: false; issues: ValidationIssue[] };

export type InitializationErrorCode =
  | "wasm_load_failed"
  | "wasm_compile_failed"
  | "abi_mismatch"
  | "missing_export"
  | "runtime_create_failed";

export declare class CaudexInitializationError extends Error {
  readonly code: InitializationErrorCode;
  readonly cause?: unknown;
  constructor(code: InitializationErrorCode, message: string, cause?: unknown);
}

export declare class CaudexRuntimeError extends Error {
  readonly status?: number;
  constructor(message: string, status?: number);
}
export declare class CaudexTrackingRejectedError extends Error {
  readonly issues: TrackingIssue[];
  constructor(issues: TrackingIssue[]);
}
export interface ClockProvider { now(): string }
export interface IdProvider { next(kind: "workout" | "membership" | "set" | "command" | "acceptedRecommendation"): string }
export interface ActiveWorkoutRecord { hostScopeKey: string; athleteId?: string; workoutId: string; snapshot: TrackingSnapshot }
export interface ActiveWorkoutPersistence {
  loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null>;
  saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void>;
}
export interface MethodologyStateAcceptancePersistence {
  compareAndSetState(change: { key: { hostScopeKey: string; methodologyId: string }; expectedRevision: string | null; methodologyVersion: string; nextState: MethodologyState; updatedAt: string }): Promise<unknown>;
}
export interface OrchestrationPersistence {
  loadAthleteProfile?(key: { hostScopeKey: string; athleteProfileId: string }): Promise<{ profile: AthleteProfile } | null>;
  loadCatalog(input: { hostScopeKey: string; asOf: string }): Promise<readonly Exercise[]>;
  loadHistory(input: { hostScopeKey: string; through: string }): Promise<{ workouts: readonly CompletedWorkout[]; summaries?: JsonValue }>;
  loadState(input: { hostScopeKey: string; methodologyId: string }): Promise<{ state: MethodologyState; revision: string } | null>;
  appendAcceptedRecommendation(record: { id: string; hostScopeKey: string; acceptedAt: string; result: RecommendationResult | ProgramRecommendationResult }): Promise<void>;
  appendCompletedWorkout(hostScopeKey: string, workout: CompletedWorkout): Promise<void>;
  loadWorkflowRecovery(hostScopeKey: string, workflowId: string): Promise<WorkflowRecoveryRecord | null>;
  saveWorkflowRecovery(record: WorkflowRecoveryRecord): Promise<void>;
}
export interface WorkflowRecoveryRecord {
  hostScopeKey: string;
  workflowId: string;
  kind: string;
  status: "pending" | "completed";
  idempotencyKey: string;
  payload: JsonValue;
  updatedAt: string;
}
export interface PortableCatalogReference { hostScopeKey: string; exerciseId: string; catalogId?: string; catalogVersion?: string }
export interface PortableCustomExerciseRecord { hostScopeKey: string; exercise: Exercise }
export interface PortableTemplateRecord { hostScopeKey: string; template: WorkoutTemplateDocument }
export interface PortableAthleteProfileRecord { hostScopeKey: string; profile: AthleteProfile }
export interface PortableCompletedWorkoutRecord { hostScopeKey: string; workout: CompletedWorkout }
export interface PortableAcceptedRecommendationRecord { id: string; hostScopeKey: string; acceptedAt: string; result: RecommendationResult }
export interface PortableMethodologyStateRecord { hostScopeKey: string; methodologyId: string; methodologyVersion: string; state: MethodologyState; revision: string; updatedAt: string }
export interface PortableAcceptedProgramRecommendationRecord { id: string; hostScopeKey: string; acceptedAt: string; result: ProgramRecommendationResult }
export interface PortableProgressionStateRecord { hostScopeKey: string; stateId: string; progressionId: string; progressionVersion: string; state: MethodologyState; revision: string; updatedAt: string }
export interface PortableProgramStateRecord { hostScopeKey: string; programId: string; strategyId: string; strategyVersion: string; state: ProgramState; revision: string; updatedAt: string }
export interface PortableDocument {
  schemaVersion: 1;
  exportedAt: string;
  catalogReferences?: PortableCatalogReference[];
  customExercises?: PortableCustomExerciseRecord[];
  templates?: PortableTemplateRecord[];
  athleteProfiles?: PortableAthleteProfileRecord[];
  activeWorkouts?: ActiveWorkoutRecord[];
  completedWorkouts?: PortableCompletedWorkoutRecord[];
  acceptedRecommendations?: PortableAcceptedRecommendationRecord[];
  acceptedProgramRecommendations?: PortableAcceptedProgramRecommendationRecord[];
  methodologyStates?: PortableMethodologyStateRecord[];
  progressionStates?: PortableProgressionStateRecord[];
  programStates?: PortableProgramStateRecord[];
  workflowRecovery?: WorkflowRecoveryRecord[];
}
export type PortableImportMode = "merge" | "replace";
export type PortableConflictPolicy = "reject" | "keepExisting" | "overwrite";
export interface PortableImportRequest { schemaVersion: 1; mode: PortableImportMode; conflictPolicy: PortableConflictPolicy; dryRun?: boolean; document: PortableDocument }
export interface PortableIssue { code: string; path: string; message: string; severity: "warning" | "error" }
export interface PortableCounts { catalogReferences: number; customExercises: number; templates: number; athleteProfiles: number; activeWorkouts: number; completedWorkouts: number; acceptedRecommendations: number; acceptedProgramRecommendations: number; methodologyStates: number; progressionStates: number; programStates: number; workflowRecovery: number }
export interface PortableImportPlan { schemaVersion: 1; valid: boolean; dryRun: boolean; mode: PortableImportMode; conflictPolicy: PortableConflictPolicy; counts: PortableCounts; issues: PortableIssue[] }
export type PortableExportResult = { schemaVersion: 1; outcome: { accepted: PortableDocument } | { rejected: PortableIssue[] } };

export interface CreateCaudexOptions {
  wasm?: WebAssembly.Module | BufferSource;
  wasmUrl?: string | URL;
  fetch?: typeof globalThis.fetch;
  clock?: ClockProvider;
  ids?: IdProvider;
  persistence?: Partial<ActiveWorkoutPersistence & MethodologyStateAcceptancePersistence & OrchestrationPersistence>;
}
export interface ActiveWorkout {
  readonly snapshot: TrackingSnapshot;
  readonly workout: TrackedWorkout;
  completeSet(setId: string, result: SetResult): Promise<TrackedWorkout>;
  completeSet(input: { membershipId: string; setId: string; actual: Metric[]; status?: "completed" | "partial" | "failed" }): Promise<TrackedWorkout>;
  complete(): Promise<CompletedWorkout>;
}
export interface SetResult { reps?: number; load?: MassMeasurement; rpe?: DecimalInput; rir?: DecimalInput; metrics?: readonly Metric[]; status?: "completed" | "partial" | "failed" }
export interface ProgramOptions { catalog: readonly Exercise[]; methodology: MethodologyRef<unknown>; hostScopeKey: string; athleteProfile?: AthleteProfile; history?: RecommendationRequest["history"]; methodologyState?: MethodologyState; methodologyStateRevision?: string | null }
export interface RecommendationOptions { asOf?: string; trainingContext?: TrainingContext; alternativeLimit?: number; tieBreakSeed?: string }
export interface Program {
  recommend(options?: RecommendationOptions): RecommendationResult;
  startWorkout(result: RecommendationResult, options?: { acceptedRecommendationId?: string }): Promise<ActiveWorkout>;
  reloadWorkout(workoutId: string): Promise<ActiveWorkout | null>;
  replaceHistory(history: RecommendationRequest["history"]): void;
  appendCompletedWorkout(workout: CompletedWorkout): void;
  evaluate(completedWorkout: CompletedWorkout, options?: { asOf?: string; history?: EvaluationRequest["history"] }): EvaluationResult;
  acceptState(evaluation: EvaluationResult): Promise<unknown>;
}
export interface RuntimeFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  evaluate(request: EvaluationRequest): EvaluationResult;
  recommendProgram(request: ProgramRecommendationRequest): ProgramRecommendationResult;
  evaluateProgram(request: ProgramEvaluationRequest): ProgramEvaluationResult;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
}
export interface WorkflowFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  recommendFromPersistence(input: Omit<RecommendationRequest, "catalog" | "history" | "methodologyState" | "athleteProfile"> & { hostScopeKey: string; athleteProfileId?: string }): Promise<RecommendationResult>;
  startRecommendation(result: RecommendationResult, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string }; acceptedRecommendationId?: string; methodologyStateRevision?: string; methodologyStateFingerprint?: string }): Promise<ActiveWorkout>;
  startTemplate(template: WorkoutTemplateDocument, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string } }): Promise<ActiveWorkout>;
  reloadActiveWorkout(input: { hostScopeKey: string; workoutId: string; catalog: Exercise[] }): Promise<ActiveWorkout | null>;
  evaluateCompletion(request: EvaluationRequest): EvaluationResult;
  evaluateCompletionFromPersistence(input: Omit<EvaluationRequest, "catalog" | "history" | "methodologyState"> & { hostScopeKey: string }): Promise<EvaluationResult>;
  acceptProposedState(evaluation: EvaluationResult, input: { hostScopeKey: string; expectedRevision: string | null }): Promise<unknown>;
}

export interface Caudex {
  readonly runtime: RuntimeFacade;
  createProgram(options: ProgramOptions): Program;
  recommendSession(request: RecommendationRequest): RecommendationResult;
  evaluatePerformance(request: EvaluationRequest): EvaluationResult;
  recommendProgram(request: ProgramRecommendationRequest): ProgramRecommendationResult;
  evaluateProgram(request: ProgramEvaluationRequest): ProgramEvaluationResult;
  startProgramWorkout(result: ProgramRecommendationResult, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string }; acceptedRecommendationId?: string }): Promise<ActiveWorkout>;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
  listMethodologies(): DiscoveryRegistry;
  describeMethodology(id: string): MethodologyDescriptor;
  listCapabilities(): DiscoveryRegistry;
  validateMethodologyConfiguration(input: { methodologyId: string; configurationSchemaVersion: number; config: JsonValue }): MethodologyValidationResult;
  validateMethodologyState(input: { methodologyId: string; configurationSchemaVersion: number; config: JsonValue; state: MethodologyState }): MethodologyValidationResult;
  exportPortable(document: PortableDocument): PortableExportResult;
  validatePortableImport(request: PortableImportRequest): PortableImportPlan;
  readonly workflows: WorkflowFacade;
  dispose(): void;
}

export declare function createCaudex(options?: CreateCaudexOptions): Promise<Caudex>;

export {
  MethodologyConfigError,
  methodologies,
  type AdvancementCriteria,
  type BackoffCalculation,
  type DoubleProgressionConfig,
  type DoubleProgressionExerciseOverride,
  type DoubleProgressionMethodology,
  type DoubleProgressionHypertrophyOptions,
  type FailureAction,
  type FailurePolicy,
  type LoadRounding,
  type RepRange,
  type RpeTopSetBackoffConfig,
  type RpeTopSetBackoffMethodology,
  type RoundingMode,
} from "./methodologies.js";
