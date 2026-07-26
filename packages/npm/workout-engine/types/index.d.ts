export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

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

export interface CreateCaudexOptions {
  wasm?: WebAssembly.Module | BufferSource;
  wasmUrl?: string | URL;
  fetch?: typeof globalThis.fetch;
}

export interface Caudex {
  recommendSession(request: RecommendationRequest): RecommendationResult;
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
