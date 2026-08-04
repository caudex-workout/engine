import {
  PersistenceAdapterError,
  PersistenceConflictError,
  PersistenceRevisionConflictError,
  type ActiveWorkoutRecord,
  type ActiveWorkoutStore,
  type AcceptedRecommendationRecord,
  type CatalogScope,
  type CatalogSource,
  type CompareAndSetMethodologyState,
  type CompletedWorkoutSink,
  type HistoryQuery,
  type HistorySnapshot,
  type HistorySource,
  type MethodologyStateKey,
  type MethodologyStateRecord,
  type MethodologyStateStore,
  type RecommendationJournal,
  type WorkoutTemplateRecord,
  type WorkoutTemplateStore,
  type WorkflowRecoveryRecord,
  type WorkflowRecoveryStore,
} from "@caudex/persistence";
import type {
  CompletedWorkout,
  Exercise,
} from "@caudex-workout/engine";

export const INDEXEDDB_SCHEMA_VERSION = 2;

const CATALOG_STORE = "catalog";
const HISTORY_STORE = "history";
const STATE_STORE = "methodology_state";
const JOURNAL_STORE = "recommendation_journal";
const ACTIVE_WORKOUT_STORE = "active_workouts";
const TEMPLATE_STORE = "workout_templates";
const RECOVERY_STORE = "workflow_recovery";

interface CatalogRow {
  hostScopeKey: string;
  exerciseId: string;
  exercise: Exercise;
}

interface HistoryRow {
  hostScopeKey: string;
  completedAt: string;
  workoutId: string;
  workout: CompletedWorkout;
}

interface StateRow extends MethodologyStateRecord {
  revisionNumber: number;
}

interface JournalRow extends AcceptedRecommendationRecord {}
interface ActiveWorkoutRow extends ActiveWorkoutRecord { revision: number }
interface TemplateRow extends WorkoutTemplateRecord { revision: number }
interface RecoveryRow extends WorkflowRecoveryRecord {}

export interface IndexedDbAdapterOptions {
  databaseName?: string;
  indexedDB?: IDBFactory;
}

export class IndexedDbPersistenceAdapter
  implements
    CatalogSource,
    HistorySource,
    MethodologyStateStore,
    RecommendationJournal,
    CompletedWorkoutSink,
    ActiveWorkoutStore,
    WorkoutTemplateStore,
    WorkflowRecoveryStore
{
  readonly databaseName: string;
  readonly #factory: IDBFactory;
  #databasePromise: Promise<IDBDatabase> | undefined;
  #closed = false;

  constructor(options: IndexedDbAdapterOptions = {}) {
    this.databaseName = options.databaseName ?? "caudex";
    const factory = options.indexedDB ?? globalThis.indexedDB;
    if (!factory) {
      throw new PersistenceAdapterError(
        "unavailable",
        "open",
        "IndexedDB is not available in this environment.",
      );
    }
    this.#factory = factory;
  }

  async replaceCatalog(
    scope: CatalogScope,
    exercises: readonly Exercise[],
  ): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(CATALOG_STORE, "readwrite");
    const store = transaction.objectStore(CATALOG_STORE);
    const index = store.index("by_scope");
    for (const key of await request(index.getAllKeys(scope.hostScopeKey))) {
      store.delete(key);
    }
    for (const exercise of exercises) {
      store.put({
        hostScopeKey: scope.hostScopeKey,
        exerciseId: exercise.id,
        exercise,
      } satisfies CatalogRow);
    }
    await transactionDone(transaction, "replaceCatalog");
  }

  async loadCatalog(scope: CatalogScope): Promise<readonly Exercise[]> {
    const database = await this.#open();
    const transaction = database.transaction(CATALOG_STORE, "readonly");
    const rows = await request<CatalogRow[]>(
      transaction.objectStore(CATALOG_STORE).index("by_scope").getAll(
        scope.hostScopeKey,
      ),
    );
    await transactionDone(transaction, "loadCatalog");
    return rows
      .sort((left, right) => left.exerciseId.localeCompare(right.exerciseId))
      .map((row) => row.exercise);
  }

  async loadHistory(query: HistoryQuery): Promise<HistorySnapshot> {
    const database = await this.#open();
    const transaction = database.transaction(HISTORY_STORE, "readonly");
    const range = IDBKeyRange.bound(
      [query.hostScopeKey, ""],
      [query.hostScopeKey, query.through],
    );
    const rows = await request<HistoryRow[]>(
      transaction.objectStore(HISTORY_STORE).index("by_scope_completed").getAll(
        range,
      ),
    );
    await transactionDone(transaction, "loadHistory");
    const exerciseIds = query.exerciseIds
      ? new Set(query.exerciseIds)
      : undefined;
    return {
      workouts: rows
        .map((row) => row.workout)
        .filter((workout) =>
          exerciseIds === undefined ||
          workout.exercises.some((exercise) =>
            exerciseIds.has(exercise.exerciseId),
          ),
        ),
    };
  }

  async loadState(
    key: MethodologyStateKey,
  ): Promise<MethodologyStateRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(STATE_STORE, "readonly");
    const row = await request<StateRow | undefined>(
      transaction.objectStore(STATE_STORE).get(stateKey(key)),
    );
    await transactionDone(transaction, "loadState");
    return row ? publicStateRecord(row) : null;
  }

  async compareAndSetState(
    change: CompareAndSetMethodologyState,
  ): Promise<MethodologyStateRecord> {
    const database = await this.#open();
    const transaction = database.transaction(STATE_STORE, "readwrite");
    const store = transaction.objectStore(STATE_STORE);
    try {
      const existing = await request<StateRow | undefined>(
        store.get(stateKey(change.key)),
      );
      const actualRevision = existing?.revision ?? null;
      if (actualRevision !== change.expectedRevision) {
        transaction.abort();
        throw new PersistenceConflictError(
          change.key,
          change.expectedRevision,
          actualRevision,
        );
      }
      const revisionNumber = (existing?.revisionNumber ?? 0) + 1;
      const row: StateRow = {
        key: change.key,
        methodologyVersion: change.methodologyVersion,
        state: change.nextState,
        revision: String(revisionNumber),
        revisionNumber,
        updatedAt: change.updatedAt,
      };
      store.put(row);
      await transactionDone(transaction, "compareAndSetState");
      return publicStateRecord(row);
    } catch (error) {
      if (error instanceof PersistenceConflictError) throw error;
      throw adapterError("compareAndSetState", error);
    }
  }

  async appendAcceptedRecommendation(
    record: AcceptedRecommendationRecord,
  ): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(JOURNAL_STORE, "readwrite");
    transaction.objectStore(JOURNAL_STORE).add(record satisfies JournalRow);
    await transactionDone(transaction, "appendAcceptedRecommendation");
  }

  async appendCompletedWorkout(
    hostScopeKey: string,
    workout: CompletedWorkout,
  ): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(HISTORY_STORE, "readwrite");
    transaction.objectStore(HISTORY_STORE).put({
      hostScopeKey,
      completedAt: workout.completedAt,
      workoutId: workout.id,
      workout,
    } satisfies HistoryRow);
    await transactionDone(transaction, "appendCompletedWorkout");
  }

  async loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(ACTIVE_WORKOUT_STORE, "readonly");
    const row = await request<ActiveWorkoutRow | undefined>(transaction.objectStore(ACTIVE_WORKOUT_STORE).get([hostScopeKey, workoutId]));
    await transactionDone(transaction, "loadActiveWorkout");
    return row ? { hostScopeKey: row.hostScopeKey, workoutId: row.workoutId, snapshot: row.snapshot } : null;
  }

  async saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(ACTIVE_WORKOUT_STORE, "readwrite");
    const store = transaction.objectStore(ACTIVE_WORKOUT_STORE);
    try {
      const existing = await request<ActiveWorkoutRow | undefined>(store.get([record.hostScopeKey, record.workoutId]));
      const actualRevision = existing?.revision ?? null;
      if (actualRevision !== expectedRevision) {
        transaction.abort();
        throw new PersistenceRevisionConflictError("active_workout", record.workoutId, expectedRevision, actualRevision);
      }
      const workout = record.snapshot.workouts?.find((candidate) => candidate.id === record.workoutId);
      if (!workout) {
        transaction.abort();
        throw new PersistenceAdapterError("invalid_data", "saveActiveWorkout", "The active-workout snapshot does not contain its workout ID.");
      }
      store.put({ ...record, revision: workout.revision } satisfies ActiveWorkoutRow);
      await transactionDone(transaction, "saveActiveWorkout");
    } catch (error) {
      if (error instanceof PersistenceRevisionConflictError || error instanceof PersistenceAdapterError) throw error;
      throw adapterError("saveActiveWorkout", error);
    }
  }

  async loadTemplate(hostScopeKey: string, templateId: string): Promise<WorkoutTemplateRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(TEMPLATE_STORE, "readonly");
    const row = await request<TemplateRow | undefined>(transaction.objectStore(TEMPLATE_STORE).get([hostScopeKey, templateId]));
    await transactionDone(transaction, "loadTemplate");
    return row ? { hostScopeKey: row.hostScopeKey, template: row.template } : null;
  }

  async saveTemplate(record: WorkoutTemplateRecord, expectedRevision: number | null): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(TEMPLATE_STORE, "readwrite");
    const store = transaction.objectStore(TEMPLATE_STORE);
    try {
      const key = [record.hostScopeKey, record.template.id];
      const existing = await request<TemplateRow | undefined>(store.get(key));
      const actualRevision = existing?.revision ?? null;
      if (actualRevision !== expectedRevision) {
        transaction.abort();
        throw new PersistenceRevisionConflictError("workout_template", record.template.id, expectedRevision, actualRevision);
      }
      store.put({ ...record, revision: record.template.revision } satisfies TemplateRow);
      await transactionDone(transaction, "saveTemplate");
    } catch (error) {
      if (error instanceof PersistenceRevisionConflictError) throw error;
      throw adapterError("saveTemplate", error);
    }
  }

  async loadWorkflowRecovery(hostScopeKey: string, workflowId: string): Promise<WorkflowRecoveryRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(RECOVERY_STORE, "readonly");
    const row = await request<RecoveryRow | undefined>(transaction.objectStore(RECOVERY_STORE).get([hostScopeKey, workflowId]));
    await transactionDone(transaction, "loadWorkflowRecovery");
    return row ?? null;
  }

  async saveWorkflowRecovery(record: WorkflowRecoveryRecord): Promise<void> {
    const database = await this.#open();
    const transaction = database.transaction(RECOVERY_STORE, "readwrite");
    transaction.objectStore(RECOVERY_STORE).put(record satisfies RecoveryRow);
    await transactionDone(transaction, "saveWorkflowRecovery");
  }

  async close(): Promise<void> {
    this.#closed = true;
    if (this.#databasePromise) {
      (await this.#databasePromise).close();
      this.#databasePromise = undefined;
    }
  }

  async deleteDatabase(): Promise<void> {
    await this.close();
    await request(this.#factory.deleteDatabase(this.databaseName));
  }

  async #open(): Promise<IDBDatabase> {
    if (this.#closed) {
      throw new PersistenceAdapterError(
        "operation_failed",
        "open",
        "The IndexedDB adapter is closed.",
      );
    }
    this.#databasePromise ??= openDatabase(
      this.#factory,
      this.databaseName,
    );
    return this.#databasePromise;
  }
}

function openDatabase(
  factory: IDBFactory,
  databaseName: string,
): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const open = factory.open(databaseName, INDEXEDDB_SCHEMA_VERSION);
    open.onupgradeneeded = () => {
      const database = open.result;
      if (!database.objectStoreNames.contains(CATALOG_STORE)) {
        const catalog = database.createObjectStore(CATALOG_STORE, {
          keyPath: ["hostScopeKey", "exerciseId"],
        });
        catalog.createIndex("by_scope", "hostScopeKey");
      }
      if (!database.objectStoreNames.contains(HISTORY_STORE)) {
        const history = database.createObjectStore(HISTORY_STORE, {
          keyPath: ["hostScopeKey", "completedAt", "workoutId"],
        });
        history.createIndex(
          "by_scope_completed",
          ["hostScopeKey", "completedAt"],
        );
      }
      if (!database.objectStoreNames.contains(STATE_STORE)) {
        database.createObjectStore(STATE_STORE, {
          keyPath: ["key.hostScopeKey", "key.methodologyId"],
        });
      }
      if (!database.objectStoreNames.contains(JOURNAL_STORE)) {
        const journal = database.createObjectStore(JOURNAL_STORE, {
          keyPath: ["hostScopeKey", "acceptedAt", "id"],
        });
        journal.createIndex(
          "by_scope_accepted",
          ["hostScopeKey", "acceptedAt"],
        );
      }
      if (!database.objectStoreNames.contains(ACTIVE_WORKOUT_STORE)) {
        database.createObjectStore(ACTIVE_WORKOUT_STORE, { keyPath: ["hostScopeKey", "workoutId"] });
      }
      if (!database.objectStoreNames.contains(TEMPLATE_STORE)) {
        database.createObjectStore(TEMPLATE_STORE, { keyPath: ["hostScopeKey", "template.id"] });
      }
      if (!database.objectStoreNames.contains(RECOVERY_STORE)) {
        database.createObjectStore(RECOVERY_STORE, { keyPath: ["hostScopeKey", "workflowId"] });
      }
    };
    open.onerror = () => reject(adapterError("open", open.error));
    open.onblocked = () =>
      reject(
        new PersistenceAdapterError(
          "unavailable",
          "open",
          "The IndexedDB upgrade is blocked by another open connection.",
        ),
      );
    open.onsuccess = () => {
      open.result.onversionchange = () => open.result.close();
      resolve(open.result);
    };
  });
}

function stateKey(key: MethodologyStateKey): [string, string] {
  return [key.hostScopeKey, key.methodologyId];
}

function publicStateRecord(row: StateRow): MethodologyStateRecord {
  return {
    key: row.key,
    methodologyVersion: row.methodologyVersion,
    state: row.state,
    revision: row.revision,
    updatedAt: row.updatedAt,
  };
}

function request<T>(value: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    value.onsuccess = () => resolve(value.result);
    value.onerror = () => reject(value.error);
  });
}

function transactionDone(
  transaction: IDBTransaction,
  operation: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () =>
      reject(adapterError(operation, transaction.error));
    transaction.onabort = () =>
      reject(adapterError(operation, transaction.error));
  });
}

function adapterError(
  operation: string,
  cause: unknown,
): PersistenceAdapterError {
  if (cause instanceof PersistenceAdapterError) return cause;
  const code =
    cause instanceof DOMException && cause.name === "QuotaExceededError"
      ? "unavailable"
      : "operation_failed";
  return new PersistenceAdapterError(
    code,
    operation,
    `IndexedDB operation "${operation}" failed.`,
    cause,
  );
}
