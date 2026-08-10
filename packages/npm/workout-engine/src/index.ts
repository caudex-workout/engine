export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface Measurement {
  amount: string;
  unit: string;
}

export {
  CaudexMeasurementError,
  kg,
  lb,
  load,
  metrics,
  minutes,
  reps,
  rir,
  rpe,
  seconds,
  type DecimalInput,
  type MassMeasurement,
} from "./measurements.ts";
import { type DecimalInput, type MassMeasurement } from "./measurements.ts";
import { createProgramFacade } from "./application.ts";
import { createActiveWorkout } from "./active-workout.ts";
import { initializeWasm, type WasmExports } from "./wasm-runtime.ts";

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

export {
  MethodologyConfigError,
  methodologies,
  type AdvancementCriteria,
  type BackoffCalculation,
  type DoubleProgressionConfig,
  type DoubleProgressionExerciseOverride,
  type DoubleProgressionHypertrophyOptions,
  type DoubleProgressionMethodology,
  type FailureAction,
  type FailurePolicy,
  type LoadRounding,
  type RepRange,
  type RpeTopSetBackoffConfig,
  type RpeTopSetBackoffMethodology,
  type RoundingMode,
} from "./methodologies.ts";

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
  history?: {
    workouts?: CompletedWorkout[];
    summaries?: JsonValue;
  };
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
  methodology: {
    id: string;
    version: string;
    configVersion: number;
  };
  inputFingerprint: string;
  resultFingerprint: string;
}

interface ProgrammingResultCommon {
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  metadata: ResultMetadata;
}

export type RecommendationResult = ProgrammingResultCommon & (
  | {
      ok: true;
      recommendation: SessionRecommendation;
      alternatives?: SessionRecommendation[];
      nextMethodologyState?: MethodologyState;
      issues?: never;
    }
  | {
      ok: false;
      recommendation?: never;
      alternatives?: never;
      nextMethodologyState?: never;
      issues: ValidationIssue[];
    }
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

export interface TrackingCommandRequest {
  schemaVersion: 1;
  snapshot: TrackingSnapshot;
  command: TrackingCommand;
}

export interface TrackingBatchRequest {
  schemaVersion: 1;
  snapshot: TrackingSnapshot;
  commands: TrackingCommand[];
}

export type TrackingCommandOutcome =
  | { accepted: { commandId: string; disposition: "applied" | "replayed"; workout: TrackedWorkout; warnings?: TrackingIssue[] } }
  | { rejected: { commandId: string; issues: TrackingIssue[] } };

export interface TrackingCommandResult {
  schemaVersion: 1;
  outcome: TrackingCommandOutcome;
  snapshot: TrackingSnapshot;
}

export interface TrackingBatchResult {
  schemaVersion: 1;
  applied: boolean;
  outcomes: TrackingCommandOutcome[];
  snapshot: TrackingSnapshot;
  issues?: TrackingIssue[];
}

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

export interface InstantiationIds {
  workoutId: string;
  membershipIds: string[];
  setIds: string[];
}

export interface RecommendationInstantiationRequest {
  schemaVersion: 1;
  recommendationResult: RecommendationResult;
  catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string };
  ids: InstantiationIds;
  createdAt: string;
  acceptedRecommendationId: string;
  methodologyStateRevision?: string;
  methodologyStateFingerprint?: string;
}

export interface TemplateInstantiationRequest {
  schemaVersion: 1;
  template: WorkoutTemplateDocument;
  catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string };
  ids: InstantiationIds;
  createdAt: string;
}

export interface CompletionConversionRequest {
  schemaVersion: 1;
  workout: TrackedWorkout;
  catalog: Exercise[];
}

export type InstantiationResult = { schemaVersion: 1; outcome: { accepted: TrackedWorkout } | { rejected: TrackingIssue[] } };
export type CompletionConversionResult = { schemaVersion: 1; outcome: { accepted: CompletedWorkout } | { rejected: TrackingIssue[] } };

export type MethodologyOperation = "recommend" | "evaluate" | "validateConfig" | "validateState";
export type MethodologyFieldType = "integer" | "exactDecimal" | "measurement" | "enumeration" | "object" | "array" | "identifier";
export interface MethodologyFieldDescriptor {
  name: string;
  description: string;
  fieldType: MethodologyFieldType;
  required: boolean;
  defaultJson?: string;
  minimum?: string;
  maximum?: string;
  exactDecimal?: boolean;
  unitDimension?: string;
  enumChoices?: string[];
  deprecated?: boolean;
}
export interface MethodologyDescriptor {
  id: string;
  displayName: string;
  description: string;
  methodologyVersion: string;
  configurationSchemaVersion: number;
  stateSchemaVersion: number;
  supportedOperations: MethodologyOperation[];
  fields: MethodologyFieldDescriptor[];
  configurationSchemaRef: string;
  stateSchemaRef: string;
  deprecated?: boolean;
}
export interface DiscoveryRegistry {
  schemaVersion: 1;
  methodologies: MethodologyDescriptor[];
  supportedOperations: string[];
}
export type MethodologyValidationResult =
  | { schemaVersion: 1; valid: true; issues: [] }
  | { schemaVersion: 1; valid: false; issues: ValidationIssue[] };

export type InitializationErrorCode =
  | "wasm_load_failed"
  | "wasm_compile_failed"
  | "abi_mismatch"
  | "missing_export"
  | "runtime_create_failed";

export class CaudexInitializationError extends Error {
  readonly code: InitializationErrorCode;
  readonly cause?: unknown;

  constructor(code: InitializationErrorCode, message: string, cause?: unknown) {
    super(message);
    this.name = "CaudexInitializationError";
    this.code = code;
    this.cause = cause;
  }
}

export class CaudexRuntimeError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "CaudexRuntimeError";
    this.status = status;
  }
}

export class CaudexTrackingRejectedError extends Error {
  readonly issues: TrackingIssue[];
  constructor(issues: TrackingIssue[]) {
    super(issues[0]?.message ?? "The tracking command was rejected.");
    this.name = "CaudexTrackingRejectedError";
    this.issues = issues;
  }
}

export interface ClockProvider { now(): string }
export interface IdProvider { next(kind: "workout" | "membership" | "set" | "command" | "acceptedRecommendation"): string }
export interface ActiveWorkoutRecord { hostScopeKey: string; athleteId?: string; workoutId: string; snapshot: TrackingSnapshot }
export interface ActiveWorkoutPersistence {
  loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null>;
  saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void>;
}
export interface MethodologyStateAcceptancePersistence {
  compareAndSetState(change: {
    key: { hostScopeKey: string; methodologyId: string };
    expectedRevision: string | null;
    methodologyVersion: string;
    nextState: MethodologyState;
    updatedAt: string;
  }): Promise<unknown>;
}

export interface OrchestrationPersistence {
  loadCatalog(input: { hostScopeKey: string; asOf: string }): Promise<readonly Exercise[]>;
  loadHistory(input: { hostScopeKey: string; through: string }): Promise<{
    workouts: readonly CompletedWorkout[];
    summaries?: JsonValue;
  }>;
  loadState(input: { hostScopeKey: string; methodologyId: string }): Promise<{
    state: MethodologyState;
    revision: string;
  } | null>;
  appendAcceptedRecommendation(record: {
    id: string;
    hostScopeKey: string;
    acceptedAt: string;
    result: RecommendationResult;
  }): Promise<void>;
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

export interface PortableCatalogReference {
  hostScopeKey: string;
  exerciseId: string;
  catalogId?: string;
  catalogVersion?: string;
}
export interface PortableCustomExerciseRecord { hostScopeKey: string; exercise: Exercise }
export interface PortableTemplateRecord { hostScopeKey: string; template: WorkoutTemplateDocument }
export interface PortableCompletedWorkoutRecord { hostScopeKey: string; workout: CompletedWorkout }
export interface PortableAcceptedRecommendationRecord {
  id: string;
  hostScopeKey: string;
  acceptedAt: string;
  result: RecommendationResult;
}
export interface PortableMethodologyStateRecord {
  hostScopeKey: string;
  methodologyId: string;
  methodologyVersion: string;
  state: MethodologyState;
  revision: string;
  updatedAt: string;
}
export interface PortableDocument {
  schemaVersion: 1;
  exportedAt: string;
  catalogReferences?: PortableCatalogReference[];
  customExercises?: PortableCustomExerciseRecord[];
  templates?: PortableTemplateRecord[];
  activeWorkouts?: ActiveWorkoutRecord[];
  completedWorkouts?: PortableCompletedWorkoutRecord[];
  acceptedRecommendations?: PortableAcceptedRecommendationRecord[];
  methodologyStates?: PortableMethodologyStateRecord[];
  workflowRecovery?: WorkflowRecoveryRecord[];
}
export type PortableImportMode = "merge" | "replace";
export type PortableConflictPolicy = "reject" | "keepExisting" | "overwrite";
export interface PortableImportRequest {
  schemaVersion: 1;
  mode: PortableImportMode;
  conflictPolicy: PortableConflictPolicy;
  dryRun?: boolean;
  document: PortableDocument;
}
export interface PortableIssue {
  code: string;
  path: string;
  message: string;
  severity: "warning" | "error";
}
export interface PortableCounts {
  catalogReferences: number;
  customExercises: number;
  templates: number;
  activeWorkouts: number;
  completedWorkouts: number;
  acceptedRecommendations: number;
  methodologyStates: number;
  workflowRecovery: number;
}
export interface PortableImportPlan {
  schemaVersion: 1;
  valid: boolean;
  dryRun: boolean;
  mode: PortableImportMode;
  conflictPolicy: PortableConflictPolicy;
  counts: PortableCounts;
  issues: PortableIssue[];
}
export type PortableExportResult = {
  schemaVersion: 1;
  outcome: { accepted: PortableDocument } | { rejected: PortableIssue[] };
};

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

export interface SetResult {
  reps?: number;
  load?: MassMeasurement;
  rpe?: DecimalInput;
  rir?: DecimalInput;
  metrics?: readonly Metric[];
  status?: "completed" | "partial" | "failed";
}

export interface ProgramOptions {
  catalog: readonly Exercise[];
  methodology: MethodologyRef<unknown>;
  hostScopeKey: string;
  athlete?: Athlete;
  history?: RecommendationRequest["history"];
  methodologyState?: MethodologyState;
  methodologyStateRevision?: string | null;
}

export interface RecommendationOptions {
  asOf?: string;
  session?: RecommendationRequest["session"];
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

export interface Program {
  recommend(options?: RecommendationOptions): RecommendationResult;
  startWorkout(result: RecommendationResult, options?: { acceptedRecommendationId?: string }): Promise<ActiveWorkout>;
  reloadWorkout(workoutId: string): Promise<ActiveWorkout | null>;
  /** Replaces the host-authoritative history used by subsequent calls. */
  replaceHistory(history: RecommendationRequest["history"]): void;
  /** Adds or replaces one completed workout in the retained history snapshot. */
  appendCompletedWorkout(workout: CompletedWorkout): void;
  evaluate(completedWorkout: CompletedWorkout, options?: { asOf?: string; history?: EvaluationRequest["history"] }): EvaluationResult;
  acceptState(evaluation: EvaluationResult): Promise<unknown>;
}

export interface RuntimeFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  evaluate(request: EvaluationRequest): EvaluationResult;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
}

export interface WorkflowFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  recommendFromPersistence(input: Omit<RecommendationRequest, "catalog" | "history" | "methodologyState"> & {
    hostScopeKey: string;
  }): Promise<RecommendationResult>;
  startRecommendation(result: RecommendationResult, input: {
    catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string };
    acceptedRecommendationId?: string; methodologyStateRevision?: string; methodologyStateFingerprint?: string;
  }): Promise<ActiveWorkout>;
  startTemplate(template: WorkoutTemplateDocument, input: {
    catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string };
  }): Promise<ActiveWorkout>;
  reloadActiveWorkout(input: { hostScopeKey: string; workoutId: string; catalog: Exercise[] }): Promise<ActiveWorkout | null>;
  evaluateCompletion(request: EvaluationRequest): EvaluationResult;
  evaluateCompletionFromPersistence(input: Omit<EvaluationRequest, "catalog" | "history" | "methodologyState"> & {
    hostScopeKey: string;
  }): Promise<EvaluationResult>;
  acceptProposedState(evaluation: EvaluationResult, input: { hostScopeKey: string; expectedRevision: string | null }): Promise<unknown>;
}

export interface Caudex {
  /** Direct deterministic operations over complete canonical request snapshots. */
  readonly runtime: RuntimeFacade;
  /** Binds stable host context while constructing complete requests for every engine call. */
  createProgram(options: ProgramOptions): Program;
  recommendSession(request: RecommendationRequest): RecommendationResult;
  evaluatePerformance(request: EvaluationRequest): EvaluationResult;
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

const STATUS_INVALID_REQUEST = 3;
const STATUS_UNSUPPORTED_VERSION = 4;
const STATUS_UNSUPPORTED_METHODOLOGY = 5;
const STATUS_INSUFFICIENT_OUTPUT = 7;

export async function createCaudex(
  options: CreateCaudexOptions = {},
): Promise<Caudex> {
  const { exports, runtime } = await initializeWasm(
    options,
    (code, message, cause) => new CaudexInitializationError(code, message, cause),
  );
  return createFacade(exports, runtime, options);
}

function createFacade(exports: WasmExports, runtime: number, options: CreateCaudexOptions): Caudex {
  let disposed = false;
  const clock = options.clock ?? { now: () => new Date().toISOString() };
  const ids = options.ids ?? { next: (kind: string) => `${kind}-${secureRandomId()}` };
  const persistence = options.persistence;
  const volatileActiveWorkouts = new Map<string, ActiveWorkoutRecord>();
  const execute = <Request, Result>(
    request: Request,
    operation: "recommend" | "evaluate" | "applyTrackingCommand" | "applyTrackingBatch" | "instantiateRecommendation" | "instantiateTemplate" | "completeForEvaluation" | "listMethodologies" | "describeMethodology" | "validateMethodologyConfig" | "validateMethodologyState" | "listCapabilities" | "exportPortable" | "validatePortableImport",
    programmingResult: boolean,
  ): Result => {
    if (disposed) {
      throw new CaudexRuntimeError("The Caudex runtime has been disposed.");
    }
    let requestBytes: Uint8Array;
    try {
      requestBytes = new TextEncoder().encode(JSON.stringify({ schemaVersion: 1, operation, payload: request }));
    } catch {
      if (programmingResult) return invalidResult(
        request as RecommendationRequest | EvaluationRequest,
        "protocol.invalid_request",
        "The request is not JSON serializable.",
      ) as Result;
      throw new CaudexRuntimeError("The tracking request is not JSON serializable.", STATUS_INVALID_REQUEST);
    }

    const requestPointer = exports.caudex_wasm_alloc(requestBytes.length);
    const requiredPointer = exports.caudex_wasm_alloc(4);
    if (requestPointer === 0 || requiredPointer === 0) {
      if (requiredPointer !== 0) exports.caudex_wasm_free(requiredPointer, 4);
      if (requestPointer !== 0) {
        exports.caudex_wasm_free(requestPointer, requestBytes.length);
      }
      throw new CaudexRuntimeError("WebAssembly request allocation failed.");
    }
    try {
      new Uint8Array(
        exports.memory.buffer,
        requestPointer,
        requestBytes.length,
      ).set(requestBytes);
      new Uint8Array(exports.memory.buffer, requiredPointer, 4).fill(0);
      const sizingStatus = exports.caudex_runtime_execute(
        runtime,
        requestPointer,
        requestBytes.length,
        0,
        0,
        requiredPointer,
      );
      if (sizingStatus !== STATUS_INSUFFICIENT_OUTPUT) {
        if (programmingResult) return statusResult(
          request as RecommendationRequest | EvaluationRequest,
          sizingStatus,
        ) as Result;
        throw new CaudexRuntimeError("The canonical tracking request was rejected by the runtime boundary.", sizingStatus);
      }
      const resultLength = new DataView(exports.memory.buffer).getUint32(requiredPointer, true);
      const resultPointer = exports.caudex_wasm_alloc(resultLength);
      if (resultPointer === 0) throw new CaudexRuntimeError("WebAssembly result allocation failed.");
      const status = exports.caudex_runtime_execute(runtime, requestPointer, requestBytes.length, resultPointer, resultLength, requiredPointer);
      if (status !== 0) {
        exports.caudex_wasm_free(resultPointer, resultLength);
        if (programmingResult) return statusResult(
          request as RecommendationRequest | EvaluationRequest,
          status,
        ) as Result;
        throw new CaudexRuntimeError("The canonical tracking request was rejected by the runtime boundary.", status);
      }
      const resultBytes = new Uint8Array(
        exports.memory.buffer,
        resultPointer,
        resultLength,
      );
      try {
        return JSON.parse(new TextDecoder().decode(resultBytes)) as Result;
      } finally {
        exports.caudex_wasm_free(resultPointer, resultLength);
      }
    } catch (cause) {
      if (cause instanceof CaudexRuntimeError) throw cause;
      throw new CaudexRuntimeError(
        "The WebAssembly runtime returned an unreadable result.",
      );
    } finally {
      exports.caudex_wasm_free(requiredPointer, 4);
      exports.caudex_wasm_free(requestPointer, requestBytes.length);
    }
  };
  const persistSnapshot = async (hostScopeKey: string, workoutId: string, snapshot: TrackingSnapshot, expectedRevision: number | null): Promise<void> => {
    const record = { hostScopeKey, workoutId, snapshot };
    if (persistence?.saveActiveWorkout) {
      await persistence.saveActiveWorkout(record, expectedRevision);
    }
    volatileActiveWorkouts.set(`${hostScopeKey}/${workoutId}`, structuredClone(record));
  };
  const activeWorkout = (snapshot: TrackingSnapshot, workoutId: string, catalog: Exercise[]): ActiveWorkout =>
    createActiveWorkout(snapshot, workoutId, catalog, {
      clock,
      ids,
      persistence,
      applyTracking: (current, command) => execute(
        { schemaVersion: 1, snapshot: current, command },
        "applyTrackingCommand",
        false,
      ),
      convertCompletion: (workout, workoutCatalog) => execute(
        { schemaVersion: 1, workout, catalog: workoutCatalog },
        "completeForEvaluation",
        false,
      ),
      persistSnapshot,
      runtimeError: (message) => new CaudexRuntimeError(message),
      trackingRejected: (issues) => new CaudexTrackingRejectedError(issues),
    });
  const runtimeFacade: RuntimeFacade = {
    recommend: (request) => execute(request, "recommend", true),
    evaluate: (request) => execute(request, "evaluate", true),
    applyTrackingCommand: (request) => execute(request, "applyTrackingCommand", false),
    applyTrackingBatch: (request) => execute(request, "applyTrackingBatch", false),
    instantiateRecommendation: (request) => execute(request, "instantiateRecommendation", false),
    instantiateTemplate: (request) => execute(request, "instantiateTemplate", false),
    completeForEvaluation: (request) => execute(request, "completeForEvaluation", false),
  };
  const facade: Caudex = {
    runtime: runtimeFacade,
    createProgram(programOptions) {
      return createProgramFacade(programOptions, {
        clock,
        runtime: runtimeFacade,
        workflows: facade.workflows,
        hasStatePersistence: Boolean(persistence?.compareAndSetState),
        runtimeError: (message) => new CaudexRuntimeError(message),
      });
    },
    recommendSession(request) {
      return execute<RecommendationRequest, RecommendationResult>(
        request,
        "recommend",
        true,
      );
    },
    evaluatePerformance(request) {
      return execute<EvaluationRequest, EvaluationResult>(
        request,
        "evaluate",
        true,
      );
    },
    applyTrackingCommand(request) {
      return execute<TrackingCommandRequest, TrackingCommandResult>(request, "applyTrackingCommand", false);
    },
    applyTrackingBatch(request) {
      return execute<TrackingBatchRequest, TrackingBatchResult>(request, "applyTrackingBatch", false);
    },
    instantiateRecommendation(request) {
      return execute<RecommendationInstantiationRequest, InstantiationResult>(request, "instantiateRecommendation", false);
    },
    instantiateTemplate(request) {
      return execute<TemplateInstantiationRequest, InstantiationResult>(request, "instantiateTemplate", false);
    },
    completeForEvaluation(request) {
      return execute<CompletionConversionRequest, CompletionConversionResult>(request, "completeForEvaluation", false);
    },
    listMethodologies() {
      return execute<{ schemaVersion: 1 }, DiscoveryRegistry>({ schemaVersion: 1 }, "listMethodologies", false);
    },
    describeMethodology(id) {
      const result = execute<{ schemaVersion: 1; id: string }, { schemaVersion: 1; methodology: MethodologyDescriptor }>({ schemaVersion: 1, id }, "describeMethodology", false);
      return result.methodology;
    },
    listCapabilities() {
      return execute<{ schemaVersion: 1 }, DiscoveryRegistry>({ schemaVersion: 1 }, "listCapabilities", false);
    },
    validateMethodologyConfiguration(input) {
      return execute<typeof input & { schemaVersion: 1 }, MethodologyValidationResult>({ schemaVersion: 1, ...input }, "validateMethodologyConfig", false);
    },
    validateMethodologyState(input) {
      return execute<typeof input & { schemaVersion: 1 }, MethodologyValidationResult>({ schemaVersion: 1, ...input }, "validateMethodologyState", false);
    },
    exportPortable(document) {
      return execute<PortableDocument, PortableExportResult>(document, "exportPortable", false);
    },
    validatePortableImport(request) {
      return execute<PortableImportRequest, PortableImportPlan>(request, "validatePortableImport", false);
    },
    workflows: {
      recommend(request) {
        return execute<RecommendationRequest, RecommendationResult>(request, "recommend", true);
      },
      async recommendFromPersistence(input) {
        if (!persistence?.loadCatalog || !persistence.loadHistory) {
          throw new CaudexRuntimeError("Catalog and history persistence capabilities are required.");
        }
        const [catalog, history, stateRecord] = await Promise.all([
          persistence.loadCatalog({ hostScopeKey: input.hostScopeKey, asOf: input.asOf }),
          persistence.loadHistory({ hostScopeKey: input.hostScopeKey, through: input.asOf }),
          persistence.loadState?.({
            hostScopeKey: input.hostScopeKey,
            methodologyId: input.methodology.id,
          }) ?? Promise.resolve(null),
        ]);
        const { hostScopeKey: _, ...request } = input;
        return execute<RecommendationRequest, RecommendationResult>({
          ...request,
          catalog: [...catalog],
          history: { ...history, workouts: [...history.workouts] },
          methodologyState: stateRecord?.state,
        }, "recommend", true);
      },
      async startRecommendation(result, input) {
        const acceptedRecommendationId = input.acceptedRecommendationId ?? ids.next("acceptedRecommendation");
        const workflowId = `recommendation:${acceptedRecommendationId}`;
        const existing = await persistence?.loadWorkflowRecovery?.(input.scope.hostScopeKey, workflowId);
        if (existing) {
          const recovered = parseInstantiationRecovery(existing);
          if (existing.status === "pending") {
            await persistence?.appendAcceptedRecommendation?.({
              id: acceptedRecommendationId,
              hostScopeKey: input.scope.hostScopeKey,
              acceptedAt: recovered.workout.startedAt,
              result,
            });
            await persistSnapshot(input.scope.hostScopeKey, recovered.workout.id, recovered.snapshot, null);
            await persistence?.saveWorkflowRecovery?.({ ...existing, status: "completed", updatedAt: clock.now() });
          }
          return activeWorkout(recovered.snapshot, recovered.workout.id, input.catalog);
        }
        const recommendation = result.recommendation;
        const membershipIds = recommendation?.exercises.map(() => ids.next("membership")) ?? [];
        const setIds = recommendation?.exercises.flatMap((exercise) => exercise.sets.map(() => ids.next("set"))) ?? [];
        const instantiated = execute<RecommendationInstantiationRequest, InstantiationResult>({
          schemaVersion: 1,
          recommendationResult: result,
          catalog: input.catalog,
          scope: input.scope,
          ids: { workoutId: ids.next("workout"), membershipIds, setIds },
          createdAt: clock.now(),
          acceptedRecommendationId,
          methodologyStateRevision: input.methodologyStateRevision,
          methodologyStateFingerprint: input.methodologyStateFingerprint,
        }, "instantiateRecommendation", false);
        if ("rejected" in instantiated.outcome) throw new CaudexTrackingRejectedError(instantiated.outcome.rejected);
        const snapshot: TrackingSnapshot = {
          workouts: [instantiated.outcome.accepted],
          startReceipts: [],
          exerciseCatalog: input.catalog.map((exercise) => ({ exerciseId: exercise.id, availability: "active" })),
        };
        const recovery: WorkflowRecoveryRecord = {
          hostScopeKey: input.scope.hostScopeKey,
          workflowId,
          kind: "recommendation_instantiation",
          status: "pending",
          idempotencyKey: acceptedRecommendationId,
          payload: { workout: instantiated.outcome.accepted, snapshot } as unknown as JsonValue,
          updatedAt: clock.now(),
        };
        await persistence?.saveWorkflowRecovery?.(recovery);
        await persistence?.appendAcceptedRecommendation?.({
          id: acceptedRecommendationId,
          hostScopeKey: input.scope.hostScopeKey,
          acceptedAt: instantiated.outcome.accepted.startedAt,
          result,
        });
        await persistSnapshot(input.scope.hostScopeKey, instantiated.outcome.accepted.id, snapshot, null);
        await persistence?.saveWorkflowRecovery?.({ ...recovery, status: "completed", updatedAt: clock.now() });
        return activeWorkout(snapshot, instantiated.outcome.accepted.id, input.catalog);
      },
      async startTemplate(template, input) {
        const membershipIds = template.exercises.map(() => ids.next("membership"));
        const setIds = template.exercises.flatMap((exercise) => (exercise.sets ?? []).map(() => ids.next("set")));
        const instantiated = execute<TemplateInstantiationRequest, InstantiationResult>({
          schemaVersion: 1,
          template,
          catalog: input.catalog,
          scope: input.scope,
          ids: { workoutId: ids.next("workout"), membershipIds, setIds },
          createdAt: clock.now(),
        }, "instantiateTemplate", false);
        if ("rejected" in instantiated.outcome) throw new CaudexTrackingRejectedError(instantiated.outcome.rejected);
        const snapshot: TrackingSnapshot = {
          workouts: [instantiated.outcome.accepted],
          startReceipts: [],
          exerciseCatalog: input.catalog.map((exercise) => ({ exerciseId: exercise.id, availability: "active" })),
        };
        await persistSnapshot(input.scope.hostScopeKey, instantiated.outcome.accepted.id, snapshot, null);
        return activeWorkout(snapshot, instantiated.outcome.accepted.id, input.catalog);
      },
      async reloadActiveWorkout(input) {
        const record = persistence?.loadActiveWorkout
          ? await persistence.loadActiveWorkout(input.hostScopeKey, input.workoutId)
          : volatileActiveWorkouts.get(`${input.hostScopeKey}/${input.workoutId}`) ?? null;
        return record ? activeWorkout(record.snapshot, record.workoutId, input.catalog) : null;
      },
      evaluateCompletion(request) {
        return execute<EvaluationRequest, EvaluationResult>(request, "evaluate", true);
      },
      async evaluateCompletionFromPersistence(input) {
        if (!persistence?.loadCatalog || !persistence.loadHistory) {
          throw new CaudexRuntimeError("Catalog and history persistence capabilities are required.");
        }
        const [catalog, history, stateRecord] = await Promise.all([
          persistence.loadCatalog({ hostScopeKey: input.hostScopeKey, asOf: input.asOf }),
          persistence.loadHistory({ hostScopeKey: input.hostScopeKey, through: input.asOf }),
          persistence.loadState?.({
            hostScopeKey: input.hostScopeKey,
            methodologyId: input.methodology.id,
          }) ?? Promise.resolve(null),
        ]);
        const { hostScopeKey: _, ...request } = input;
        return execute<EvaluationRequest, EvaluationResult>({
          ...request,
          catalog: [...catalog],
          history: { ...history, workouts: [...history.workouts] },
          methodologyState: stateRecord?.state,
        }, "evaluate", true);
      },
      async acceptProposedState(evaluation, input) {
        if (!evaluation.ok || !evaluation.nextMethodologyState) {
          throw new CaudexRuntimeError("The evaluation has no methodology-state proposal to accept.");
        }
        if (!persistence?.compareAndSetState) {
          throw new CaudexRuntimeError("No methodology-state persistence capability was supplied.");
        }
        return persistence.compareAndSetState({
          key: { hostScopeKey: input.hostScopeKey, methodologyId: evaluation.metadata.methodology.id },
          expectedRevision: input.expectedRevision,
          methodologyVersion: evaluation.metadata.methodology.version,
          nextState: evaluation.nextMethodologyState,
          updatedAt: clock.now(),
        });
      },
    },
    dispose() {
      if (!disposed) {
        exports.caudex_wasm_runtime_destroy(runtime);
        disposed = true;
      }
    },
  };
  return facade;
}

function secureRandomId(): string {
  const crypto = globalThis.crypto;
  if (!crypto?.randomUUID) throw new CaudexRuntimeError("Secure platform randomness is unavailable; inject an ID provider.");
  return crypto.randomUUID();
}

function parseInstantiationRecovery(record: WorkflowRecoveryRecord): {
  workout: TrackedWorkout;
  snapshot: TrackingSnapshot;
} {
  if (record.kind !== "recommendation_instantiation") {
    throw new CaudexRuntimeError("The workflow recovery record has an unexpected kind.");
  }
  try {
    const value = record.payload as {
      workout?: TrackedWorkout;
      snapshot?: TrackingSnapshot;
    };
    if (!value.workout?.id || !Array.isArray(value.snapshot?.workouts)) {
      throw new Error("missing workout snapshot");
    }
    return { workout: value.workout, snapshot: value.snapshot };
  } catch {
    throw new CaudexRuntimeError("The workflow recovery record is malformed.");
  }
}

function statusResult<Result extends RecommendationResult | EvaluationResult>(
  request: RecommendationRequest | EvaluationRequest,
  status: number,
): Result {
  if (status === STATUS_INVALID_REQUEST) {
    return invalidResult<Result>(
      request,
      "protocol.invalid_request",
      "The canonical request is invalid.",
    );
  }
  if (status === STATUS_UNSUPPORTED_VERSION) {
    return invalidResult<Result>(
      request,
      "protocol.unsupported_version",
      "A requested protocol or methodology version is unsupported.",
    );
  }
  if (status === STATUS_UNSUPPORTED_METHODOLOGY) {
    return invalidResult<Result>(
      request,
      "methodology.unsupported",
      "The requested methodology is not compiled into this runtime.",
    );
  }
  throw new CaudexRuntimeError(
    `The WebAssembly runtime could not complete the request (status ${status}).`,
    status,
  );
}

function invalidResult<
  Result extends RecommendationResult | EvaluationResult,
>(
  request: RecommendationRequest | EvaluationRequest,
  code: string,
  message: string,
): Result {
  return {
    ok: false,
    explanations: [],
    warnings: [],
    issues: [
      {
        code,
        path: "/",
        message,
        severity: "error",
      },
    ],
    metadata: {
      engineVersion: "unresolved",
      schemaVersion: 1,
      methodology: {
        id: request?.methodology?.id ?? "unresolved",
        version: "unresolved",
        configVersion: request?.methodology?.configVersion ?? 0,
      },
      inputFingerprint: "",
      resultFingerprint: "",
    },
  } as unknown as Result;
}
