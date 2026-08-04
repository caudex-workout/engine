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
  | { startWorkout: JsonObject }
  | { addExercise: JsonObject }
  | { removeExercise: JsonObject }
  | { reorderExercise: JsonObject }
  | { addSet: JsonObject }
  | { completeSet: JsonObject }
  | { skipSet: JsonObject }
  | { reopenSet: JsonObject }
  | { removeSet: JsonObject }
  | { reorderSet: JsonObject }
  | { completeWorkout: JsonObject };

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

export interface CreateCaudexOptions {
  wasm?: WebAssembly.Module | BufferSource;
  wasmUrl?: string | URL;
  fetch?: typeof globalThis.fetch;
}

export interface Caudex {
  recommendSession(request: RecommendationRequest): RecommendationResult;
  evaluatePerformance(request: EvaluationRequest): EvaluationResult;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
  dispose(): void;
}

interface WasmExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  caudex_abi_version(): number;
  caudex_runtime_execute(
    runtime: number,
    requestPointer: number,
    requestLength: number,
    outputPointer: number,
    outputCapacity: number,
    requiredPointer: number,
  ): number;
  caudex_wasm_alloc(length: number): number;
  caudex_wasm_free(pointer: number, length: number): void;
  caudex_wasm_runtime_create(): number;
  caudex_wasm_runtime_destroy(runtime: number): void;
}

const REQUIRED_EXPORTS = [
  "memory",
  "caudex_abi_version",
  "caudex_runtime_execute",
  "caudex_wasm_alloc",
  "caudex_wasm_free",
  "caudex_wasm_runtime_create",
  "caudex_wasm_runtime_destroy",
] as const;

const STATUS_INVALID_REQUEST = 3;
const STATUS_UNSUPPORTED_VERSION = 4;
const STATUS_UNSUPPORTED_METHODOLOGY = 5;
const STATUS_INSUFFICIENT_OUTPUT = 7;

export async function createCaudex(
  options: CreateCaudexOptions = {},
): Promise<Caudex> {
  const instance = await instantiate(options);
  const exports = requireExports(instance.exports);
  if (exports.caudex_abi_version() !== 2) {
    throw new CaudexInitializationError(
      "abi_mismatch",
      "The WebAssembly runtime does not implement Caudex ABI version 2.",
    );
  }
  const runtime = exports.caudex_wasm_runtime_create();
  if (runtime === 0) {
    throw new CaudexInitializationError(
      "runtime_create_failed",
      "The WebAssembly runtime could not be created.",
    );
  }
  return createFacade(exports, runtime);
}

async function instantiate(
  options: CreateCaudexOptions,
): Promise<WebAssembly.Instance> {
  if (options.wasm) {
    try {
      const module =
        options.wasm instanceof WebAssembly.Module
          ? options.wasm
          : await WebAssembly.compile(options.wasm);
      return await WebAssembly.instantiate(module, {});
    } catch (cause) {
      throw new CaudexInitializationError(
        "wasm_compile_failed",
        "The supplied Caudex WebAssembly module could not be instantiated.",
        cause,
      );
    }
  }

  const url = options.wasmUrl
    ? new URL(options.wasmUrl, import.meta.url)
    : new URL("../wasm/caudex.wasm", import.meta.url);
  if (url.protocol === "file:" && isNode()) {
    try {
      const dynamicImport = new Function(
        "specifier",
        "return import(specifier)",
      ) as (specifier: string) => Promise<{
        readFile(url: URL): Promise<Uint8Array>;
      }>;
      const { readFile } = await dynamicImport("node:fs/promises");
      const bytes = await readFile(url);
      const module = await WebAssembly.compile(bytes);
      return await WebAssembly.instantiate(module, {});
    } catch (cause) {
      throw new CaudexInitializationError(
        "wasm_load_failed",
        `The Caudex WebAssembly module could not be loaded from ${url}.`,
        cause,
      );
    }
  }

  const fetchImplementation = options.fetch ?? globalThis.fetch;
  if (!fetchImplementation) {
    throw new CaudexInitializationError(
      "wasm_load_failed",
      "No fetch implementation is available to load the Caudex WebAssembly module.",
    );
  }
  try {
    const response = await fetchImplementation(url);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        return (await WebAssembly.instantiateStreaming(response.clone(), {}))
          .instance;
      } catch {
        // Incorrect development-server MIME types use the ArrayBuffer fallback.
      }
    }
    const module = await WebAssembly.compile(await response.arrayBuffer());
    return await WebAssembly.instantiate(module, {});
  } catch (cause) {
    throw new CaudexInitializationError(
      "wasm_load_failed",
      `The Caudex WebAssembly module could not be loaded from ${url}.`,
      cause,
    );
  }
}

function requireExports(raw: WebAssembly.Exports): WasmExports {
  for (const name of REQUIRED_EXPORTS) {
    if (!(name in raw)) {
      throw new CaudexInitializationError(
        "missing_export",
        `The WebAssembly runtime is missing the required export "${name}".`,
      );
    }
  }
  return raw as WasmExports;
}

function createFacade(exports: WasmExports, runtime: number): Caudex {
  let disposed = false;
  const execute = <Request, Result>(
    request: Request,
    operation: "recommend" | "evaluate" | "applyTrackingCommand" | "applyTrackingBatch" | "instantiateRecommendation" | "instantiateTemplate" | "completeForEvaluation",
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
  return {
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
    dispose() {
      if (!disposed) {
        exports.caudex_wasm_runtime_destroy(runtime);
        disposed = true;
      }
    },
  };
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
  } as Result;
}

function isNode(): boolean {
  return Boolean(
    (globalThis as { process?: { versions?: { node?: string } } }).process
      ?.versions?.node,
  );
}
