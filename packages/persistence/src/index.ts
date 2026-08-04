import type {
  CompletedWorkout,
  Exercise,
  JsonValue,
  MethodologyState,
  RecommendationResult,
  TrackingSnapshot,
  WorkoutTemplateDocument,
} from "@caudex-workout/engine";

export const PERSISTENCE_CONTRACT_VERSION = 2;

export interface CatalogScope {
  hostScopeKey: string;
  asOf: string;
}

export interface HistoryQuery {
  hostScopeKey: string;
  through: string;
  exerciseIds?: readonly string[];
}

export interface HistorySnapshot {
  workouts: readonly CompletedWorkout[];
  summaries?: JsonValue;
}

export interface MethodologyStateKey {
  hostScopeKey: string;
  methodologyId: string;
}

export interface MethodologyStateRecord {
  key: MethodologyStateKey;
  methodologyVersion: string;
  state: MethodologyState;
  revision: string;
  updatedAt: string;
}

export interface CompareAndSetMethodologyState {
  key: MethodologyStateKey;
  expectedRevision: string | null;
  methodologyVersion: string;
  nextState: MethodologyState;
  updatedAt: string;
}

export interface CatalogSource {
  loadCatalog(scope: CatalogScope): Promise<readonly Exercise[]>;
}

export interface HistorySource {
  loadHistory(query: HistoryQuery): Promise<HistorySnapshot>;
}

export interface MethodologyStateStore {
  loadState(key: MethodologyStateKey): Promise<MethodologyStateRecord | null>;
  compareAndSetState(
    change: CompareAndSetMethodologyState,
  ): Promise<MethodologyStateRecord>;
}

export interface AcceptedRecommendationRecord {
  id: string;
  hostScopeKey: string;
  acceptedAt: string;
  result: RecommendationResult;
}

export interface RecommendationJournal {
  appendAcceptedRecommendation(
    record: AcceptedRecommendationRecord,
  ): Promise<void>;
}

export interface CompletedWorkoutSink {
  appendCompletedWorkout(
    hostScopeKey: string,
    workout: CompletedWorkout,
  ): Promise<void>;
}

export interface ActiveWorkoutRecord {
  hostScopeKey: string;
  workoutId: string;
  snapshot: TrackingSnapshot;
}

export interface ActiveWorkoutStore {
  loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null>;
  saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void>;
}

export interface WorkoutTemplateRecord {
  hostScopeKey: string;
  template: WorkoutTemplateDocument;
}

export interface WorkoutTemplateStore {
  loadTemplate(hostScopeKey: string, templateId: string): Promise<WorkoutTemplateRecord | null>;
  saveTemplate(record: WorkoutTemplateRecord, expectedRevision: number | null): Promise<void>;
}

export interface WorkflowRecoveryRecord {
  hostScopeKey: string;
  workflowId: string;
  kind: "recommendation_start" | "workout_completion" | "state_acceptance" | string;
  status: "pending" | "completed";
  idempotencyKey: string;
  payload: JsonValue;
  updatedAt: string;
}

export interface WorkflowRecoveryStore {
  loadWorkflowRecovery(hostScopeKey: string, workflowId: string): Promise<WorkflowRecoveryRecord | null>;
  saveWorkflowRecovery(record: WorkflowRecoveryRecord): Promise<void>;
}

export type PersistenceAdapterErrorCode =
  | "unavailable"
  | "invalid_data"
  | "unsupported_version"
  | "operation_failed";

export class PersistenceAdapterError extends Error {
  readonly code: PersistenceAdapterErrorCode;
  readonly operation: string;
  readonly cause?: unknown;

  constructor(
    code: PersistenceAdapterErrorCode,
    operation: string,
    message: string,
    cause?: unknown,
  ) {
    super(message);
    this.name = "PersistenceAdapterError";
    this.code = code;
    this.operation = operation;
    this.cause = cause;
  }
}

export class PersistenceConflictError extends Error {
  readonly key: MethodologyStateKey;
  readonly expectedRevision: string | null;
  readonly actualRevision: string | null;

  constructor(
    key: MethodologyStateKey,
    expectedRevision: string | null,
    actualRevision: string | null,
  ) {
    super("The methodology state changed after the snapshot was loaded.");
    this.name = "PersistenceConflictError";
    this.key = key;
    this.expectedRevision = expectedRevision;
    this.actualRevision = actualRevision;
  }
}

export class PersistenceRevisionConflictError extends Error {
  readonly resource: "active_workout" | "workout_template";
  readonly id: string;
  readonly expectedRevision: number | null;
  readonly actualRevision: number | null;

  constructor(resource: "active_workout" | "workout_template", id: string, expectedRevision: number | null, actualRevision: number | null) {
    super(`The ${resource.replace("_", " ")} revision changed after it was loaded.`);
    this.name = "PersistenceRevisionConflictError";
    this.resource = resource;
    this.id = id;
    this.expectedRevision = expectedRevision;
    this.actualRevision = actualRevision;
  }
}
