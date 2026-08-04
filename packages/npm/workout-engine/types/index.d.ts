export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface Measurement {
  amount: string;
  unit: string;
}

export interface Metric {
  code: string;
  value: Measurement;
}

export interface MuscleContribution {
  muscleId: string;
  role: "primary" | "secondary" | "stabilizer" | "custom";
  weight?: string;
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

export interface AthletePreferences {
  preferredExerciseIds?: string[];
  dislikedExerciseIds?: string[];
  avoidedEquipmentIds?: string[];
  muscleEmphasis?: Array<{ muscleId: string; weight: string }>;
}

export interface AthleteRestrictions {
  excludedExerciseIds?: string[];
  excludedMovementTags?: string[];
  equipmentLimitations?: string[];
  constraints?: Array<{
    code: string;
    subjectId?: string;
    details?: JsonValue;
  }>;
}

export interface Athlete {
  id?: string;
  preferences?: AthletePreferences;
  restrictions?: AthleteRestrictions;
  capabilities?: JsonValue;
  readiness?: JsonValue;
}

export interface RecommendationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athlete?: Athlete;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  session?: {
    availableMinutes?: number;
    availableEquipmentIds?: string[];
    goals?: string[];
    minExercises?: number;
    maxExercises?: number;
    maxSets?: number;
    excludedExerciseIds?: string[];
    requiredExerciseIds?: string[];
    locationTags?: string[];
    readiness?: JsonValue;
  };
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

export interface EvaluationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athlete?: Athlete;
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
  }>;
}

export interface ResultMetadata {
  engineVersion: string;
  schemaVersion: number;
  methodology: { id: string; version: string; configVersion: number };
  inputFingerprint: string;
  resultFingerprint: string;
}

export interface RecommendationResult {
  ok: boolean;
  recommendation?: SessionRecommendation;
  alternatives?: SessionRecommendation[];
  nextMethodologyState?: MethodologyState;
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  issues?: ValidationIssue[];
  metadata: ResultMetadata;
}

export interface ExerciseEvaluation {
  exerciseId: string;
  outcome: string;
  explanationRefs?: string[];
}

export interface PerformanceEvaluation {
  outcome: string;
  exercises: ExerciseEvaluation[];
}

export interface EvaluationResult {
  ok: boolean;
  evaluation?: PerformanceEvaluation;
  nextMethodologyState?: MethodologyState;
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  issues?: ValidationIssue[];
  metadata: ResultMetadata;
}

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
export interface ActiveWorkoutRecord { hostScopeKey: string; workoutId: string; snapshot: TrackingSnapshot }
export interface ActiveWorkoutPersistence {
  loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null>;
  saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void>;
}
export interface MethodologyStateAcceptancePersistence {
  compareAndSetState(change: { key: { hostScopeKey: string; methodologyId: string }; expectedRevision: string | null; methodologyVersion: string; nextState: MethodologyState; updatedAt: string }): Promise<unknown>;
}

export interface CreateCaudexOptions {
  wasm?: WebAssembly.Module | BufferSource;
  wasmUrl?: string | URL;
  fetch?: typeof globalThis.fetch;
  clock?: ClockProvider;
  ids?: IdProvider;
  persistence?: Partial<ActiveWorkoutPersistence & MethodologyStateAcceptancePersistence>;
}
export interface ActiveWorkout {
  readonly snapshot: TrackingSnapshot;
  readonly workout: TrackedWorkout;
  completeSet(input: { membershipId: string; setId: string; actual: Metric[]; status?: "completed" | "partial" | "failed" }): Promise<TrackedWorkout>;
  complete(): Promise<CompletedWorkout>;
}
export interface WorkflowFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  startRecommendation(result: RecommendationResult, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string }; acceptedRecommendationId?: string; methodologyStateRevision?: string; methodologyStateFingerprint?: string }): Promise<ActiveWorkout>;
  startTemplate(template: WorkoutTemplateDocument, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string } }): Promise<ActiveWorkout>;
  reloadActiveWorkout(input: { hostScopeKey: string; workoutId: string; catalog: Exercise[] }): Promise<ActiveWorkout | null>;
  evaluateCompletion(request: EvaluationRequest): EvaluationResult;
  acceptProposedState(evaluation: EvaluationResult, input: { hostScopeKey: string; expectedRevision: string | null }): Promise<unknown>;
}

export interface Caudex {
  recommendSession(request: RecommendationRequest): RecommendationResult;
  evaluatePerformance(request: EvaluationRequest): EvaluationResult;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
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
  type FailureAction,
  type FailurePolicy,
  type LoadRounding,
  type RepRange,
  type RpeTopSetBackoffConfig,
  type RpeTopSetBackoffMethodology,
  type RoundingMode,
} from "./methodologies.js";
