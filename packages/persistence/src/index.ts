import type {
  CompletedWorkout,
  Exercise,
  JsonValue,
  MethodologyState,
  RecommendationResult,
} from "@caudex-workout/engine";

export const PERSISTENCE_CONTRACT_VERSION = 1;

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
