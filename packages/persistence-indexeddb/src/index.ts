import {
  PersistenceAdapterError,
  PersistenceConflictError,
  PersistenceRevisionConflictError,
  type ActiveWorkoutRecord,
  type ActiveWorkoutStore,
  type AthleteProfileKey,
  type AthleteProfileRecord,
  type AthleteProfileStore,
  type AcceptedRecommendationRecord,
  type CatalogScope,
  type CatalogSource,
  type CompareAndSetMethodologyState,
  type CompareAndSetAthleteProfile,
  type CompareAndSetProgramInstance,
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
  type PortableDataStore,
  type PortableExportQuery,
  type ProgramDefinitionKey,
  type ProgramDefinitionRecord,
  type ProgramDefinitionStore,
  type ProgramInstanceKey,
  type ProgramInstanceRecord,
  type ProgramInstanceStore,
  type ProgramOccurrenceKey,
  type ProgramOccurrenceRecord,
  type ProgramOccurrenceStore,
} from "@caudex-workout/persistence";
import type {
  CompletedWorkout,
  Exercise,
  PortableDocument,
  PortableImportPlan,
  PortableImportRequest,
  PortableIssue,
  ProgramDefinition,
  ProgramInstance,
  ProgramOccurrenceRecord as ProgramOccurrence,
  ProgramState,
} from "@caudex-workout/engine";

export const INDEXEDDB_SCHEMA_VERSION = 6;

const CATALOG_STORE = "catalog";
const HISTORY_STORE = "history";
const STATE_STORE = "methodology_state";
const JOURNAL_STORE = "recommendation_journal";
const ACTIVE_WORKOUT_STORE = "active_workouts";
const TEMPLATE_STORE = "workout_templates";
const RECOVERY_STORE = "workflow_recovery";
const CATALOG_REFERENCE_STORE = "portable_catalog_references";
const ATHLETE_PROFILE_STORE = "athlete_profiles";
const PROGRAM_DEFINITION_STORE = "program_definitions";
const PROGRAM_INSTANCE_STORE = "program_instances";
const PROGRAM_OCCURRENCE_STORE = "program_occurrences";

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
interface CatalogReferenceRow { hostScopeKey: string; exerciseId: string; catalogId?: string; catalogVersion?: string }
interface AthleteProfileRow extends AthleteProfileRecord { hostScopeKey: string; athleteProfileId: string; revision: number }
interface ProgramDefinitionRow extends ProgramDefinitionRecord {}
interface ProgramInstanceRow extends ProgramInstanceRecord {}
interface ProgramOccurrenceRow extends ProgramOccurrenceRecord {}

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
    WorkflowRecoveryStore,
    AthleteProfileStore,
    ProgramDefinitionStore,
    ProgramInstanceStore,
    ProgramOccurrenceStore,
    PortableDataStore
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

  async loadAthleteProfile(key: AthleteProfileKey): Promise<AthleteProfileRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(ATHLETE_PROFILE_STORE, "readonly");
    const row = await request<AthleteProfileRow | undefined>(transaction.objectStore(ATHLETE_PROFILE_STORE).get([key.hostScopeKey, key.athleteProfileId]));
    await transactionDone(transaction, "loadAthleteProfile");
    return row ? structuredClone(row) : null;
  }

  async compareAndSetAthleteProfile(change: CompareAndSetAthleteProfile): Promise<AthleteProfileRecord> {
    const database = await this.#open();
    const transaction = database.transaction(ATHLETE_PROFILE_STORE, "readwrite");
    const store = transaction.objectStore(ATHLETE_PROFILE_STORE);
    try {
      const existing = await request<AthleteProfileRow | undefined>(store.get([change.key.hostScopeKey, change.key.athleteProfileId]));
      const currentRevision = existing?.profile.revision ?? null;
      if (currentRevision !== change.expectedRevision) {
        transaction.abort();
        throw new PersistenceRevisionConflictError("athlete_profile", change.key.athleteProfileId, change.expectedRevision, currentRevision);
      }
      if (change.nextProfile.id !== change.key.athleteProfileId) throw new PersistenceAdapterError("invalid_data", "compareAndSetAthleteProfile", "Profile ID must match the scoped profile key.");
      const nextRevision = (currentRevision ?? 0) + 1;
      const row: AthleteProfileRow = { key: structuredClone(change.key), profile: structuredClone({ ...change.nextProfile, revision: nextRevision }), revision: nextRevision, hostScopeKey: change.key.hostScopeKey, athleteProfileId: change.key.athleteProfileId };
      store.put(row);
      await transactionDone(transaction, "compareAndSetAthleteProfile");
      return row;
    } catch (error) {
      if (error instanceof PersistenceRevisionConflictError) throw error;
      throw adapterError("compareAndSetAthleteProfile", error);
    }
  }

  async loadProgramDefinition(key: ProgramDefinitionKey): Promise<ProgramDefinitionRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(PROGRAM_DEFINITION_STORE, "readonly");
    const row = await request<ProgramDefinitionRow | undefined>(transaction.objectStore(PROGRAM_DEFINITION_STORE).get(programDefinitionKey(key)));
    await transactionDone(transaction, "loadProgramDefinition");
    return row ? structuredClone(row) : null;
  }

  async putProgramDefinition(record: ProgramDefinitionRecord): Promise<ProgramDefinitionRecord> {
    if (!validProgramDefinitionRecord(record)) throw invalidData("putProgramDefinition", "The program definition does not match its scoped immutable key.");
    const database = await this.#open();
    const transaction = database.transaction(PROGRAM_DEFINITION_STORE, "readwrite");
    const store = transaction.objectStore(PROGRAM_DEFINITION_STORE);
    try {
      const existing = await request<ProgramDefinitionRow | undefined>(store.get(programDefinitionKey(record.key)));
      if (existing) {
        transaction.abort();
        throw immutableConflict("program definition", record.key.definitionId);
      }
      store.add(structuredClone(record) satisfies ProgramDefinitionRow);
      await transactionDone(transaction, "putProgramDefinition");
      return structuredClone(record);
    } catch (error) {
      if (error instanceof PersistenceAdapterError) throw error;
      throw adapterError("putProgramDefinition", error);
    }
  }

  async loadProgramInstance(key: ProgramInstanceKey): Promise<ProgramInstanceRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(PROGRAM_INSTANCE_STORE, "readonly");
    const row = await request<ProgramInstanceRow | undefined>(transaction.objectStore(PROGRAM_INSTANCE_STORE).get(programInstanceKey(key)));
    await transactionDone(transaction, "loadProgramInstance");
    return row ? structuredClone(row) : null;
  }

  async compareAndSetProgramInstance(change: CompareAndSetProgramInstance): Promise<ProgramInstanceRecord> {
    if (!validProgramInstanceRecord(change.record)) throw invalidData("compareAndSetProgramInstance", "The program instance and planning state are inconsistent.");
    const database = await this.#open();
    const transaction = database.transaction([PROGRAM_DEFINITION_STORE, PROGRAM_INSTANCE_STORE], "readwrite");
    const definitionStore = transaction.objectStore(PROGRAM_DEFINITION_STORE);
    const instanceStore = transaction.objectStore(PROGRAM_INSTANCE_STORE);
    try {
      const definition = await request<ProgramDefinitionRow | undefined>(definitionStore.get([
        change.record.key.hostScopeKey,
        change.record.instance.definition.id,
        change.record.instance.definition.version,
      ]));
      if (!definition || definition.definition.configurationFingerprint !== change.record.instance.definition.configurationFingerprint) {
        transaction.abort();
        throw invalidData("compareAndSetProgramInstance", "The program instance must reference a stored definition with the matching fingerprint.");
      }
      const existing = await request<ProgramInstanceRow | undefined>(instanceStore.get(programInstanceKey(change.record.key)));
      if (existing !== undefined &&
          (existing.instance.definition.id !== change.record.instance.definition.id ||
           existing.instance.definition.version !== change.record.instance.definition.version ||
           existing.instance.definition.configurationFingerprint !== change.record.instance.definition.configurationFingerprint)) {
        transaction.abort();
        throw invalidData("compareAndSetProgramInstance", "An existing program instance cannot be rebound to another definition.");
      }
      const actualRevision = existing?.planningState?.revision ?? null;
      if ((existing === undefined && change.expectedRevision !== null) ||
          (existing !== undefined && (change.expectedRevision === null || change.expectedRevision !== actualRevision))) {
        transaction.abort();
        throw new PersistenceRevisionConflictError("program_instance", change.record.key.instanceId, change.expectedRevision, actualRevision);
      }
      instanceStore.put(structuredClone(change.record) satisfies ProgramInstanceRow);
      await transactionDone(transaction, "compareAndSetProgramInstance");
      return structuredClone(change.record);
    } catch (error) {
      if (error instanceof PersistenceAdapterError || error instanceof PersistenceRevisionConflictError) throw error;
      throw adapterError("compareAndSetProgramInstance", error);
    }
  }

  async loadProgramOccurrence(key: ProgramOccurrenceKey): Promise<ProgramOccurrenceRecord | null> {
    const database = await this.#open();
    const transaction = database.transaction(PROGRAM_OCCURRENCE_STORE, "readonly");
    const row = await request<ProgramOccurrenceRow | undefined>(transaction.objectStore(PROGRAM_OCCURRENCE_STORE).get(programOccurrenceKey(key)));
    await transactionDone(transaction, "loadProgramOccurrence");
    return row ? structuredClone(row) : null;
  }

  async appendProgramOccurrence(record: ProgramOccurrenceRecord): Promise<ProgramOccurrenceRecord> {
    if (!validProgramOccurrenceRecord(record)) throw invalidData("appendProgramOccurrence", "The program occurrence does not match its scoped immutable key or revision transition.");
    const database = await this.#open();
    const transaction = database.transaction([PROGRAM_INSTANCE_STORE, PROGRAM_OCCURRENCE_STORE], "readwrite");
    const instanceStore = transaction.objectStore(PROGRAM_INSTANCE_STORE);
    const occurrenceStore = transaction.objectStore(PROGRAM_OCCURRENCE_STORE);
    try {
      const instance = await request<ProgramInstanceRow | undefined>(instanceStore.get([
        record.key.hostScopeKey,
        record.key.instanceId,
      ]));
      if (!instance || !sameProgramDefinitionReference(instance.instance.definition, record.occurrence.definition)) {
        transaction.abort();
        throw invalidData("appendProgramOccurrence", "A program occurrence must reference its stored instance and exact definition.");
      }
      const existing = await request<ProgramOccurrenceRow | undefined>(occurrenceStore.get(programOccurrenceKey(record.key)));
      if (existing) {
        transaction.abort();
        throw immutableConflict("program occurrence", record.key.occurrenceId);
      }
      occurrenceStore.add(structuredClone(record) satisfies ProgramOccurrenceRow);
      await transactionDone(transaction, "appendProgramOccurrence");
      return structuredClone(record);
    } catch (error) {
      if (error instanceof PersistenceAdapterError) throw error;
      throw adapterError("appendProgramOccurrence", error);
    }
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
      if (existing && !Number.isSafeInteger(existing.revisionNumber)) {
        transaction.abort();
        throw new PersistenceAdapterError(
          "invalid_data",
          "compareAndSetState",
          "The persisted methodology-state revision is outside JavaScript's exact integer range.",
        );
      }
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
    const store = transaction.objectStore(JOURNAL_STORE);
    const existing = await request<JournalRow | undefined>(
      store.index("by_scope_id").get([record.hostScopeKey, record.id]),
    );
    if (existing) {
      if (!sameAcceptedRecommendation(existing, record)) {
        transaction.abort();
        throw new PersistenceAdapterError(
          "invalid_data",
          "appendAcceptedRecommendation",
          "An accepted-recommendation ID was reused with a different payload.",
        );
      }
      await transactionDone(transaction, "appendAcceptedRecommendation");
      return;
    }
    store.add(record satisfies JournalRow);
    try {
      await transactionDone(transaction, "appendAcceptedRecommendation");
    } catch (error) {
      // Two tabs can both observe a missing ID before the unique index is
      // enforced. Re-read after the losing transaction aborts so a concurrent
      // exact retry still has idempotent semantics.
      if (!isConstraintError(error)) throw error;
      const retryTransaction = database.transaction(JOURNAL_STORE, "readonly");
      const winner = await request<JournalRow | undefined>(
        retryTransaction.objectStore(JOURNAL_STORE).index("by_scope_id").get([record.hostScopeKey, record.id]),
      );
      await transactionDone(retryTransaction, "appendAcceptedRecommendation");
      if (winner && sameAcceptedRecommendation(winner, record)) return;
      if (winner) {
        throw new PersistenceAdapterError(
          "invalid_data",
          "appendAcceptedRecommendation",
          "An accepted-recommendation ID was reused with a different payload.",
        );
      }
      throw error;
    }
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
      if (!isSafeRevision(workout.revision)) {
        transaction.abort();
        throw new PersistenceAdapterError("invalid_data", "saveActiveWorkout", "The active-workout revision is outside JavaScript's exact integer range.");
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
      if (!isSafeRevision(record.template.revision)) {
        transaction.abort();
        throw new PersistenceAdapterError("invalid_data", "saveTemplate", "The workout-template revision is outside JavaScript's exact integer range.");
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

  async exportPortable(query: PortableExportQuery): Promise<PortableDocument> {
    const database = await this.#open();
    const stores = [CATALOG_STORE, HISTORY_STORE, STATE_STORE, JOURNAL_STORE, ACTIVE_WORKOUT_STORE, TEMPLATE_STORE, RECOVERY_STORE, CATALOG_REFERENCE_STORE, ATHLETE_PROFILE_STORE, PROGRAM_DEFINITION_STORE, PROGRAM_INSTANCE_STORE, PROGRAM_OCCURRENCE_STORE];
    const transaction = database.transaction(stores, "readonly");
    const scope = query.hostScopeKey;
    const catalogPromise = request<CatalogRow[]>(transaction.objectStore(CATALOG_STORE).index("by_scope").getAll(scope));
    const historyPromise = request<HistoryRow[]>(transaction.objectStore(HISTORY_STORE).getAll());
    const statePromise = request<StateRow[]>(transaction.objectStore(STATE_STORE).getAll());
    const journalPromise = request<JournalRow[]>(transaction.objectStore(JOURNAL_STORE).getAll());
    const activePromise = request<ActiveWorkoutRow[]>(transaction.objectStore(ACTIVE_WORKOUT_STORE).getAll());
    const templatePromise = request<TemplateRow[]>(transaction.objectStore(TEMPLATE_STORE).getAll());
    const recoveryPromise = request<RecoveryRow[]>(transaction.objectStore(RECOVERY_STORE).getAll());
    const referencesPromise = request<CatalogReferenceRow[]>(transaction.objectStore(CATALOG_REFERENCE_STORE).getAll());
    const profilesPromise = request<Array<AthleteProfileRow & { hostScopeKey: string; athleteProfileId: string }>>(transaction.objectStore(ATHLETE_PROFILE_STORE).getAll());
    const programDefinitionsPromise = request<ProgramDefinitionRow[]>(transaction.objectStore(PROGRAM_DEFINITION_STORE).getAll());
    const programInstancesPromise = request<ProgramInstanceRow[]>(transaction.objectStore(PROGRAM_INSTANCE_STORE).getAll());
    const programOccurrencesPromise = request<ProgramOccurrenceRow[]>(transaction.objectStore(PROGRAM_OCCURRENCE_STORE).getAll());
    const [catalog, history, states, journal, active, templates, recovery, references, profiles, programDefinitions, programInstances, programOccurrences] = await Promise.all([
      catalogPromise, historyPromise, statePromise, journalPromise, activePromise, templatePromise, recoveryPromise, referencesPromise, profilesPromise, programDefinitionsPromise, programInstancesPromise, programOccurrencesPromise,
    ]);
    await transactionDone(transaction, "exportPortable");
    const document: PortableDocument = {
      schemaVersion: 1,
      exportedAt: query.exportedAt,
      catalogReferences: references.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.exerciseId, right.exerciseId))
        .map((row) => structuredClone(row)),
      customExercises: catalog
        .sort((left, right) => portableCompare(left.exerciseId, right.exerciseId))
        .map((row) => ({ hostScopeKey: scope, exercise: structuredClone(row.exercise) })),
      templates: templates.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.template.id, right.template.id))
        .map((row) => ({ hostScopeKey: scope, template: structuredClone(row.template) })),
      athleteProfiles: profiles.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.athleteProfileId, right.athleteProfileId))
        .map((row) => ({ hostScopeKey: scope, profile: structuredClone(row.profile) })),
      programDefinitions: programDefinitions.filter((row) => row.key.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.key.definitionId, right.key.definitionId) || portableCompare(left.key.definitionVersion, right.key.definitionVersion))
        .map((row) => ({ hostScopeKey: scope, definition: structuredClone(row.definition) })),
      programInstances: programInstances.filter((row) => row.key.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.key.instanceId, right.key.instanceId))
        .map((row) => ({ hostScopeKey: scope, instance: structuredClone(row.instance), ...(row.planningState === null ? {} : { planningState: structuredClone(row.planningState) }) })),
      programOccurrences: programOccurrences.filter((row) => row.key.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.key.instanceId, right.key.instanceId) || portableCompare(left.key.occurrenceId, right.key.occurrenceId))
        .map((row) => ({ hostScopeKey: scope, occurrence: structuredClone(row.occurrence) })),
      activeWorkouts: active.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => {
          const athlete = portableCompare(left.athleteId ?? left.snapshot.workouts?.find((workout) => workout.id === left.workoutId)?.scope.athleteId ?? "", right.athleteId ?? right.snapshot.workouts?.find((workout) => workout.id === right.workoutId)?.scope.athleteId ?? "");
          return athlete || portableCompare(left.workoutId, right.workoutId);
        })
        .map((row) => {
          const athleteId = row.athleteId ?? row.snapshot.workouts?.find((workout) => workout.id === row.workoutId)?.scope.athleteId;
          return { hostScopeKey: scope, ...(athleteId === undefined ? {} : { athleteId }), workoutId: row.workoutId, snapshot: structuredClone(row.snapshot) };
        }),
      completedWorkouts: history.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.workoutId, right.workoutId))
        .map((row) => ({ hostScopeKey: scope, workout: structuredClone(row.workout) })),
      acceptedRecommendations: journal.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.id, right.id))
        .map((row) => structuredClone(row)),
      methodologyStates: states.filter((row) => row.key.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.key.methodologyId, right.key.methodologyId))
        .map((row) => ({ hostScopeKey: scope, methodologyId: row.key.methodologyId, methodologyVersion: row.methodologyVersion, state: structuredClone(row.state), revision: row.revision, updatedAt: row.updatedAt })),
      workflowRecovery: recovery.filter((row) => row.hostScopeKey === scope)
        .sort((left, right) => portableCompare(left.workflowId, right.workflowId))
        .map((row) => structuredClone(row)),
    };
    if (new TextEncoder().encode(JSON.stringify(document)).byteLength > 4 * 1024 * 1024) {
      throw new PersistenceAdapterError("invalid_data", "exportPortable", "The portable export exceeds the 4 MiB encoded limit.");
    }
    return document;
  }

  async importPortable(input: PortableImportRequest): Promise<PortableImportPlan> {
    const plan = validatePortableRequest(input);
    if (!plan.valid || input.dryRun !== false) return plan;
    const database = await this.#open();
    const storeNames = [CATALOG_STORE, HISTORY_STORE, STATE_STORE, JOURNAL_STORE, ACTIVE_WORKOUT_STORE, TEMPLATE_STORE, RECOVERY_STORE, CATALOG_REFERENCE_STORE, ATHLETE_PROFILE_STORE, PROGRAM_DEFINITION_STORE, PROGRAM_INSTANCE_STORE, PROGRAM_OCCURRENCE_STORE];
    const transaction = database.transaction(storeNames, "readwrite");
    try {
      if (input.mode === "replace") {
        const scopes = portableScopes(input.document);
        const keyPromises = storeNames.map((name) => request<IDBValidKey[]>(transaction.objectStore(name).getAllKeys()));
        const allKeys = await Promise.all(keyPromises);
        for (const [index, name] of storeNames.entries()) {
          const store = transaction.objectStore(name);
          for (const key of allKeys[index] ?? []) {
            const scope = Array.isArray(key) ? String(key[0]) : "";
            if (scopes.has(scope)) store.delete(key);
          }
        }
      }
      const conflicts = input.mode === "merge" ? await portableConflicts(transaction, input.document) : new Set<string>();
      if (input.conflictPolicy === "reject" && conflicts.size !== 0) {
        transaction.abort();
        return withConflictIssues(plan, conflicts);
      }
      const shouldWrite = (key: string): boolean => input.conflictPolicy !== "keepExisting" || !conflicts.has(key);
      for (const record of input.document.catalogReferences ?? []) if (shouldWrite(`reference:${record.hostScopeKey}:${record.exerciseId}`))
        transaction.objectStore(CATALOG_REFERENCE_STORE).put(record satisfies CatalogReferenceRow);
      for (const record of input.document.customExercises ?? []) if (shouldWrite(`catalog:${record.hostScopeKey}:${record.exercise.id}`))
        transaction.objectStore(CATALOG_STORE).put({ hostScopeKey: record.hostScopeKey, exerciseId: record.exercise.id, exercise: record.exercise } satisfies CatalogRow);
      for (const record of input.document.templates ?? []) if (shouldWrite(`template:${record.hostScopeKey}:${record.template.id}`))
        transaction.objectStore(TEMPLATE_STORE).put({ hostScopeKey: record.hostScopeKey, template: record.template, revision: record.template.revision } satisfies TemplateRow);
      for (const record of input.document.athleteProfiles ?? []) if (shouldWrite(`profile:${record.hostScopeKey}:${record.profile.id}`))
        transaction.objectStore(ATHLETE_PROFILE_STORE).put({ hostScopeKey: record.hostScopeKey, athleteProfileId: record.profile.id, key: { hostScopeKey: record.hostScopeKey, athleteProfileId: record.profile.id }, profile: record.profile, revision: record.profile.revision ?? 0 });
      for (const record of input.document.programDefinitions ?? []) if (shouldWrite(`program_definition:${record.hostScopeKey}:${record.definition.id}:${record.definition.version}`)) {
        const definitionStore = transaction.objectStore(PROGRAM_DEFINITION_STORE);
        const definitionKey: [string, string, string] = [record.hostScopeKey, record.definition.id, record.definition.version];
        const existing = await request<ProgramDefinitionRow | undefined>(definitionStore.get(definitionKey));
        if (existing) {
          if (existing.definition.configurationFingerprint !== record.definition.configurationFingerprint ||
              JSON.stringify(existing.definition) !== JSON.stringify(record.definition)) {
            transaction.abort();
            throw invalidData("importPortable", "A versioned program definition is immutable and cannot be overwritten.");
          }
        } else {
          definitionStore.add({ key: { hostScopeKey: record.hostScopeKey, definitionId: record.definition.id, definitionVersion: record.definition.version }, definition: record.definition } satisfies ProgramDefinitionRow);
        }
      }
      for (const record of input.document.programInstances ?? []) if (shouldWrite(`program_instance:${record.hostScopeKey}:${record.instance.id}`))
        transaction.objectStore(PROGRAM_INSTANCE_STORE).put({ key: { hostScopeKey: record.hostScopeKey, instanceId: record.instance.id }, instance: record.instance, planningState: record.planningState ?? null } satisfies ProgramInstanceRow);
      for (const record of input.document.programOccurrences ?? []) if (shouldWrite(`program_occurrence:${record.hostScopeKey}:${record.occurrence.instanceId}:${record.occurrence.occurrenceId}`))
        transaction.objectStore(PROGRAM_OCCURRENCE_STORE).put({ key: { hostScopeKey: record.hostScopeKey, instanceId: record.occurrence.instanceId, occurrenceId: record.occurrence.occurrenceId }, occurrence: record.occurrence } satisfies ProgramOccurrenceRow);
      for (const record of input.document.activeWorkouts ?? []) if (shouldWrite(`active:${record.hostScopeKey}:${record.workoutId}`)) {
        const workout = record.snapshot.workouts?.find((candidate) => candidate.id === record.workoutId);
        if (!workout) throw new PersistenceAdapterError("invalid_data", "importPortable", "An active-workout record does not contain its workout.");
        transaction.objectStore(ACTIVE_WORKOUT_STORE).put({ ...record, revision: workout.revision } satisfies ActiveWorkoutRow);
      }
      for (const record of input.document.completedWorkouts ?? []) if (shouldWrite(`history:${record.hostScopeKey}:${record.workout.id}`))
        transaction.objectStore(HISTORY_STORE).put({ hostScopeKey: record.hostScopeKey, completedAt: record.workout.completedAt, workoutId: record.workout.id, workout: record.workout } satisfies HistoryRow);
      for (const record of input.document.acceptedRecommendations ?? []) if (shouldWrite(`journal:${record.hostScopeKey}:${record.id}`))
        transaction.objectStore(JOURNAL_STORE).put(record satisfies JournalRow);
      for (const record of input.document.methodologyStates ?? []) if (shouldWrite(`state:${record.hostScopeKey}:${record.methodologyId}`))
        transaction.objectStore(STATE_STORE).put({ key: { hostScopeKey: record.hostScopeKey, methodologyId: record.methodologyId }, methodologyVersion: record.methodologyVersion, state: record.state, revision: record.revision, revisionNumber: parseRevision(record.revision), updatedAt: record.updatedAt } satisfies StateRow);
      for (const record of input.document.workflowRecovery ?? []) if (shouldWrite(`recovery:${record.hostScopeKey}:${record.workflowId}`))
        transaction.objectStore(RECOVERY_STORE).put(record satisfies RecoveryRow);
      await transactionDone(transaction, "importPortable");
      return plan;
    } catch (error) {
      try { transaction.abort(); } catch { /* already inactive */ }
      if (error instanceof PersistenceAdapterError) throw error;
      throw adapterError("importPortable", error);
    }
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

function validatePortableRequest(input: PortableImportRequest): PortableImportPlan {
  const document = input.document;
  const issues: PortableIssue[] = [];
  const add = (code: string, path: string, message: string) => {
    if (issues.length < 256) issues.push({ code, path, message, severity: "error" });
  };
  try {
    if (new TextEncoder().encode(JSON.stringify(document)).byteLength > 4 * 1024 * 1024) add("portable.byte_limit_exceeded", "/document", "The portable document exceeds the 4 MiB encoded limit.");
  } catch {
    add("portable.invalid_data", "/document", "The portable document is not JSON serializable.");
  }
  if (input.schemaVersion !== 1 || document.schemaVersion !== 1) add("portable.unsupported_version", "/schemaVersion", "Only portable schema version 1 is supported.");
  if (!validTimestamp(document.exportedAt)) add("portable.timestamp_invalid", "/document/exportedAt", "The export timestamp is not valid RFC 3339.");
  const collections = {
    catalogReferences: document.catalogReferences ?? [], customExercises: document.customExercises ?? [], templates: document.templates ?? [], athleteProfiles: document.athleteProfiles ?? [],
    programDefinitions: document.programDefinitions ?? [], programInstances: document.programInstances ?? [], programOccurrences: document.programOccurrences ?? [],
    activeWorkouts: document.activeWorkouts ?? [], completedWorkouts: document.completedWorkouts ?? [], acceptedRecommendations: document.acceptedRecommendations ?? [],
    methodologyStates: document.methodologyStates ?? [], workflowRecovery: document.workflowRecovery ?? [],
  };
  for (const [name, values] of Object.entries(collections)) if (values.length > 10_000)
    add("portable.record_limit_exceeded", `/document/${name}`, "Portable record collections are limited to 10,000 entries.");
  const keyed: Array<[string, string[]]> = [
    ["catalogReferences", collections.catalogReferences.map((value) => `${value.hostScopeKey}\0${value.exerciseId}`)],
    ["customExercises", collections.customExercises.map((value) => `${value.hostScopeKey}\0${value.exercise.id}`)],
    ["templates", collections.templates.map((value) => `${value.hostScopeKey}\0${value.template.id}`)],
    ["athleteProfiles", collections.athleteProfiles.map((value) => `${value.hostScopeKey}\0${value.profile.id}`)],
    ["programDefinitions", collections.programDefinitions.map((value) => `${value.hostScopeKey}\0${value.definition.id}\0${value.definition.version}`)],
    ["programInstances", collections.programInstances.map((value) => `${value.hostScopeKey}\0${value.instance.id}`)],
    ["programOccurrences", collections.programOccurrences.map((value) => `${value.hostScopeKey}\0${value.occurrence.instanceId}\0${value.occurrence.occurrenceId}`)],
    ["activeWorkouts", collections.activeWorkouts.map((value) => `${value.hostScopeKey}\0${value.athleteId ?? ""}\0${value.workoutId}`)],
    ["completedWorkouts", collections.completedWorkouts.map((value) => `${value.hostScopeKey}\0${value.workout.id}`)],
    ["acceptedRecommendations", collections.acceptedRecommendations.map((value) => `${value.hostScopeKey}\0${value.id}`)],
    ["methodologyStates", collections.methodologyStates.map((value) => `${value.hostScopeKey}\0${value.methodologyId}`)],
    ["workflowRecovery", collections.workflowRecovery.map((value) => `${value.hostScopeKey}\0${value.workflowId}`)],
  ];
  const indexedDbActiveKeys = new Set<string>();
  for (const record of collections.athleteProfiles) {
    if (!record.profile.id) add("portable.profile_id_invalid", "/document/athleteProfiles", "An athlete profile must have a stable non-empty ID.");
    if ((record.profile.schemaVersion ?? 1) !== 1) add("portable.profile_version_unsupported", "/document/athleteProfiles", "An athlete profile uses an unsupported schema version.");
  }
  const portableDefinitions = new Map<string, ProgramDefinition>();
  for (const record of collections.programDefinitions) {
    const definition = record.definition;
    if (!validPortableProgramDefinition(record.hostScopeKey, definition))
      add("portable.program_definition_identity_invalid", "/document/programDefinitions", "A program definition must match a complete host-scoped immutable identity.");
    portableDefinitions.set(`${record.hostScopeKey}\0${definition.id}\0${definition.version}`, definition);
  }
  const portableInstances = new Map<string, { instance: ProgramInstance; planningState?: ProgramState }>();
  for (const record of collections.programInstances) {
    const instance = record.instance;
    const definition = portableDefinitions.get(`${record.hostScopeKey}\0${instance.definition.id}\0${instance.definition.version}`);
    if (!validPortableProgramInstance(record.hostScopeKey, instance, record.planningState))
      add("portable.program_instance_identity_invalid", "/document/programInstances", "A program instance and its planning state must share complete matching identities.");
    if (!definition)
      add("portable.program_definition_missing", "/document/programInstances", "A program instance must reference an embedded definition in the same scope.");
    else if (definition.configurationFingerprint !== instance.definition.configurationFingerprint)
      add("portable.program_definition_fingerprint_mismatch", "/document/programInstances", "A program instance definition fingerprint does not match its embedded definition.");
    portableInstances.set(`${record.hostScopeKey}\0${instance.id}`, { instance, ...(record.planningState === undefined ? {} : { planningState: record.planningState }) });
  }
  for (const record of collections.programOccurrences) {
    const occurrence = record.occurrence;
    const instance = portableInstances.get(`${record.hostScopeKey}\0${occurrence.instanceId}`);
    if (!validPortableProgramOccurrence(record.hostScopeKey, occurrence))
      add("portable.program_occurrence_revision_invalid", "/document/programOccurrences", "A program occurrence must match its immutable identity and accepted revision transition.");
    if (!instance)
      add("portable.program_instance_missing", "/document/programOccurrences", "A program occurrence must reference an embedded instance in the same scope.");
    else if (!sameProgramDefinitionReference(instance.instance.definition, occurrence.definition))
      add("portable.program_occurrence_definition_mismatch", "/document/programOccurrences", "A program occurrence must reference the same definition as its instance.");
    else if (occurrence.afterRevision > (instance.planningState?.revision ?? 0))
      add("portable.program_occurrence_revision_ahead", "/document/programOccurrences", "A program occurrence cannot be ahead of the persisted planning-state revision.");
  }
  for (const record of collections.activeWorkouts) {
    const key = `${record.hostScopeKey}\0${record.workoutId}`;
    if (indexedDbActiveKeys.has(key)) add("portable.adapter_key_conflict", "/document/activeWorkouts", "IndexedDB requires workout IDs to be unique within a host scope.");
    indexedDbActiveKeys.add(key);
  }
  for (const [name, keys] of keyed) for (let index = 1; index < keys.length; index += 1) {
    if (keys[index] === keys[index - 1]) add("portable.duplicate_id", `/document/${name}`, "Portable record IDs must be unique within each record kind.");
    else if ((keys[index] ?? "") < (keys[index - 1] ?? "")) add("portable.order_invalid", `/document/${name}`, "Portable records must be sorted by their stable key.");
  }
  const exerciseKeys = new Set([
    ...collections.catalogReferences.map((value) => `${value.hostScopeKey}\0${value.exerciseId}`),
    ...collections.customExercises.map((value) => `${value.hostScopeKey}\0${value.exercise.id}`),
  ]);
  const customExerciseKeys = new Set(collections.customExercises.map((value) => `${value.hostScopeKey}\0${value.exercise.id}`));
  for (const reference of collections.catalogReferences) if (customExerciseKeys.has(`${reference.hostScopeKey}\0${reference.exerciseId}`))
    add("portable.catalog_source_conflict", "/document/catalogReferences", "An exercise cannot be both an external catalog reference and an embedded custom exercise in one scope.");
  for (const record of collections.activeWorkouts) {
    const workouts = record.snapshot.workouts ?? [];
    const workout = workouts[0];
    if (workouts.length !== 1 || workout?.id !== record.workoutId || workout.scope.hostScopeKey !== record.hostScopeKey ||
        (workout.scope.athleteId ?? undefined) !== (record.athleteId ?? undefined) || workout.status !== "active")
      add("portable.active_workout_inconsistent", "/document/activeWorkouts", "An active-workout record must contain exactly its matching active workout and scope.");
    for (const candidate of workouts) for (const exercise of candidate.exercises ?? [])
      if (!exerciseKeys.has(`${record.hostScopeKey}\0${exercise.exerciseId}`)) add("portable.catalog_reference_missing", "/document/activeWorkouts", "An active workout exercise has no catalog reference or embedded custom exercise.");
    for (const candidate of workouts) if (!isSafeRevision(candidate.revision)) add("portable.revision_invalid", "/document/activeWorkouts", "An active-workout revision must be a non-negative safe integer.");
  }
  for (const record of collections.completedWorkouts) for (const exercise of record.workout.exercises)
    if (!exerciseKeys.has(`${record.hostScopeKey}\0${exercise.exerciseId}`)) add("portable.catalog_reference_missing", "/document/completedWorkouts", "A completed workout exercise has no catalog reference or embedded custom exercise.");
  const validateMetrics = (metrics: readonly { value: { amount: string; unit: string } }[] | undefined, path: string) => {
    for (const metric of metrics ?? []) {
      if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(metric.value.amount)) add("portable.decimal_invalid", path, "A metric amount is not an exact canonical decimal.");
      if (!PORTABLE_UNITS.has(metric.value.unit)) add("portable.unit_unknown", path, "A metric unit is not supported by this protocol version.");
    }
  };
  for (const record of collections.activeWorkouts) for (const workout of record.snapshot.workouts ?? []) for (const exercise of workout.exercises ?? []) for (const set of exercise.sets ?? []) {
    validateMetrics(set.targetMetrics, "/document/activeWorkouts"); validateMetrics(set.actualMetrics, "/document/activeWorkouts");
  }
  for (const record of collections.completedWorkouts) {
    if (!validTimestamp(record.workout.startedAt) || !validTimestamp(record.workout.completedAt)) add("portable.timestamp_invalid", "/document/completedWorkouts", "A completed workout timestamp is invalid.");
    for (const exercise of record.workout.exercises) for (const set of exercise.sets) {
      validateMetrics(set.targetMetrics, "/document/completedWorkouts"); validateMetrics(set.actualMetrics, "/document/completedWorkouts");
    }
  }
  for (const record of collections.templates) for (const exercise of record.template.exercises) for (const set of exercise.sets ?? []) validateMetrics(set.targetMetrics, "/document/templates");
  for (const record of collections.acceptedRecommendations) {
    if (!validTimestamp(record.acceptedAt)) add("portable.timestamp_invalid", "/document/acceptedRecommendations", "An accepted-recommendation timestamp is invalid.");
    for (const exercise of record.result.recommendation?.exercises ?? []) for (const set of exercise.sets) validateMetrics(set.targetMetrics, "/document/acceptedRecommendations");
  }
  for (const record of collections.templates) if (!isSafeRevision(record.template.revision)) add("portable.revision_invalid", "/document/templates", "A workout-template revision must be a non-negative safe integer.");
  for (const record of collections.methodologyStates) {
    if (!validTimestamp(record.updatedAt)) add("portable.timestamp_invalid", "/document/methodologyStates", "A methodology-state timestamp is invalid.");
    if (!validRevision(record.revision)) add("portable.revision_invalid", "/document/methodologyStates", "A methodology-state revision must be a non-negative safe integer string.");
  }
  for (const record of collections.workflowRecovery) if (!validTimestamp(record.updatedAt)) add("portable.timestamp_invalid", "/document/workflowRecovery", "A workflow-recovery timestamp is invalid.");
  return {
    schemaVersion: 1,
    valid: issues.length === 0,
    dryRun: input.dryRun ?? true,
    mode: input.mode,
    conflictPolicy: input.conflictPolicy,
    counts: Object.fromEntries(Object.entries(collections).map(([name, values]) => [name, values.length])) as unknown as PortableImportPlan["counts"],
    issues,
  };
}

const PORTABLE_UNITS = new Set(["count", "g", "kg", "lb", "s", "min", "m", "km", "mi", "rpe", "rir", "level", "percent"]);
function isSafeRevision(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}
function validRevision(value: string): boolean {
  return /^(0|[1-9][0-9]*)$/.test(value) && isSafeRevision(Number(value));
}
function portableCompare(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}
function validTimestamp(value: string): boolean {
  if (value.length > 64) return false;
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-](\d{2}):(\d{2}))$/.exec(value);
  if (!match) return false;
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return false;
  const daysInMonth = month === 2
    ? (year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0) ? 29 : 28)
    : [4, 6, 9, 11].includes(month) ? 30 : 31;
  if (day < 1 || day > daysInMonth) return false;
  if (match[7] !== "Z" && (Number(match[8]) > 23 || Number(match[9]) > 59)) return false;
  return true;
}

function sameAcceptedRecommendation(
  left: AcceptedRecommendationRecord,
  right: AcceptedRecommendationRecord,
): boolean {
  return left.id === right.id &&
    left.hostScopeKey === right.hostScopeKey &&
    left.acceptedAt === right.acceptedAt &&
    JSON.stringify(left.result) === JSON.stringify(right.result);
}

function isConstraintError(error: unknown): boolean {
  return error instanceof PersistenceAdapterError &&
    error.cause instanceof DOMException &&
    error.cause.name === "ConstraintError";
}

function portableScopes(document: PortableDocument): Set<string> {
  return new Set([
    ...(document.catalogReferences ?? []).map((value) => value.hostScopeKey),
    ...(document.customExercises ?? []).map((value) => value.hostScopeKey),
    ...(document.templates ?? []).map((value) => value.hostScopeKey),
    ...(document.athleteProfiles ?? []).map((value) => value.hostScopeKey),
    ...(document.programDefinitions ?? []).map((value) => value.hostScopeKey),
    ...(document.programInstances ?? []).map((value) => value.hostScopeKey),
    ...(document.programOccurrences ?? []).map((value) => value.hostScopeKey),
    ...(document.activeWorkouts ?? []).map((value) => value.hostScopeKey),
    ...(document.completedWorkouts ?? []).map((value) => value.hostScopeKey),
    ...(document.acceptedRecommendations ?? []).map((value) => value.hostScopeKey),
    ...(document.methodologyStates ?? []).map((value) => value.hostScopeKey),
    ...(document.workflowRecovery ?? []).map((value) => value.hostScopeKey),
  ]);
}

async function portableConflicts(transaction: IDBTransaction, document: PortableDocument): Promise<Set<string>> {
  const stores = [CATALOG_STORE, HISTORY_STORE, STATE_STORE, JOURNAL_STORE, ACTIVE_WORKOUT_STORE, TEMPLATE_STORE, RECOVERY_STORE, CATALOG_REFERENCE_STORE, ATHLETE_PROFILE_STORE, PROGRAM_DEFINITION_STORE, PROGRAM_INSTANCE_STORE, PROGRAM_OCCURRENCE_STORE];
  const requests = stores.map((name) => request<unknown[]>(transaction.objectStore(name).getAll()));
  const [catalog, history, states, journal, active, templates, recovery, references, profiles, programDefinitions, programInstances, programOccurrences] = await Promise.all(requests) as [CatalogRow[], HistoryRow[], StateRow[], JournalRow[], ActiveWorkoutRow[], TemplateRow[], RecoveryRow[], CatalogReferenceRow[], Array<AthleteProfileRow & { hostScopeKey: string; athleteProfileId: string }>, ProgramDefinitionRow[], ProgramInstanceRow[], ProgramOccurrenceRow[]];
  const existing = new Set<string>([
    ...catalog.map((row) => `catalog:${row.hostScopeKey}:${row.exerciseId}`),
    ...history.map((row) => `history:${row.hostScopeKey}:${row.workoutId}`),
    ...states.map((row) => `state:${row.key.hostScopeKey}:${row.key.methodologyId}`),
    ...journal.map((row) => `journal:${row.hostScopeKey}:${row.id}`),
    ...active.map((row) => `active:${row.hostScopeKey}:${row.workoutId}`),
    ...templates.map((row) => `template:${row.hostScopeKey}:${row.template.id}`),
    ...recovery.map((row) => `recovery:${row.hostScopeKey}:${row.workflowId}`),
    ...references.map((row) => `reference:${row.hostScopeKey}:${row.exerciseId}`),
    ...profiles.map((row) => `profile:${row.hostScopeKey}:${row.athleteProfileId}`),
    ...programDefinitions.map((row) => `program_definition:${row.key.hostScopeKey}:${row.key.definitionId}:${row.key.definitionVersion}`),
    ...programInstances.map((row) => `program_instance:${row.key.hostScopeKey}:${row.key.instanceId}`),
    ...programOccurrences.map((row) => `program_occurrence:${row.key.hostScopeKey}:${row.key.instanceId}:${row.key.occurrenceId}`),
  ]);
  const incoming = [
    ...(document.catalogReferences ?? []).map((row) => `reference:${row.hostScopeKey}:${row.exerciseId}`),
    ...(document.customExercises ?? []).map((row) => `catalog:${row.hostScopeKey}:${row.exercise.id}`),
    ...(document.completedWorkouts ?? []).map((row) => `history:${row.hostScopeKey}:${row.workout.id}`),
    ...(document.methodologyStates ?? []).map((row) => `state:${row.hostScopeKey}:${row.methodologyId}`),
    ...(document.acceptedRecommendations ?? []).map((row) => `journal:${row.hostScopeKey}:${row.id}`),
    ...(document.activeWorkouts ?? []).map((row) => `active:${row.hostScopeKey}:${row.workoutId}`),
    ...(document.templates ?? []).map((row) => `template:${row.hostScopeKey}:${row.template.id}`),
    ...(document.athleteProfiles ?? []).map((row) => `profile:${row.hostScopeKey}:${row.profile.id}`),
    ...(document.programDefinitions ?? []).map((row) => `program_definition:${row.hostScopeKey}:${row.definition.id}:${row.definition.version}`),
    ...(document.programInstances ?? []).map((row) => `program_instance:${row.hostScopeKey}:${row.instance.id}`),
    ...(document.programOccurrences ?? []).map((row) => `program_occurrence:${row.hostScopeKey}:${row.occurrence.instanceId}:${row.occurrence.occurrenceId}`),
    ...(document.workflowRecovery ?? []).map((row) => `recovery:${row.hostScopeKey}:${row.workflowId}`),
  ];
  return new Set(incoming.filter((key) => existing.has(key)));
}

function withConflictIssues(plan: PortableImportPlan, conflicts: Set<string>): PortableImportPlan {
  return { ...plan, valid: false, issues: [...plan.issues, ...[...conflicts].slice(0, 256 - plan.issues.length).map((key) => ({
    code: "portable.conflict", path: "/document", message: `A persisted record already exists for ${key}.`, severity: "error" as const,
  }))] };
}

function parseRevision(value: string): number {
  if (!validRevision(value)) {
    throw new PersistenceAdapterError(
      "invalid_data",
      "importPortable",
      "A methodology-state revision is not representable exactly by IndexedDB's JavaScript adapter.",
    );
  }
  return Number(value);
}

function programDefinitionKey(key: ProgramDefinitionKey): [string, string, string] {
  return [key.hostScopeKey, key.definitionId, key.definitionVersion];
}

function programInstanceKey(key: ProgramInstanceKey): [string, string] {
  return [key.hostScopeKey, key.instanceId];
}

function programOccurrenceKey(key: ProgramOccurrenceKey): [string, string, string] {
  return [key.hostScopeKey, key.instanceId, key.occurrenceId];
}

function sameProgramDefinitionReference(
  left: ProgramInstance["definition"] | ProgramState["definition"],
  right: ProgramInstance["definition"] | ProgramState["definition"],
): boolean {
  return left.id === right.id && left.version === right.version &&
    left.configurationFingerprint === right.configurationFingerprint;
}

function validProgramDefinitionRecord(record: ProgramDefinitionRecord): boolean {
  const { key, definition } = record;
  return validPortableProgramDefinition(key.hostScopeKey, definition) &&
    key.definitionId === definition.id && key.definitionVersion === definition.version;
}

function validProgramInstanceRecord(record: ProgramInstanceRecord): boolean {
  return validPortableProgramInstance(record.key.hostScopeKey, record.instance, record.planningState) &&
    record.key.instanceId === record.instance.id;
}

function validProgramOccurrenceRecord(record: ProgramOccurrenceRecord): boolean {
  const { key, occurrence } = record;
  return validPortableProgramOccurrence(key.hostScopeKey, occurrence) &&
    key.instanceId === occurrence.instanceId && key.occurrenceId === occurrence.occurrenceId;
}

function validPortableProgramDefinition(scope: string, definition: ProgramDefinition): boolean {
  return scope.length > 0 && definition.schemaVersion === 1 && definition.id.length > 0 &&
    definition.version.length > 0 && definition.displayName.length > 0 &&
    definition.configurationFingerprint.length > 0 && definition.blocks.length > 0;
}

function validPortableProgramInstance(
  scope: string,
  instance: ProgramInstance,
  planningState: ProgramState | null | undefined,
): boolean {
  if (scope.length === 0 || instance.schemaVersion !== 1 || instance.id.length === 0 ||
      instance.athleteId.length === 0 || !validProgramDefinitionReference(instance.definition) ||
      (instance.lifecycle === "active" && planningState == null)) return false;
  return planningState == null ||
    planningState.schemaVersion === 1 && isSafeRevision(planningState.revision) &&
    planningState.instanceId === instance.id &&
    sameProgramDefinitionReference(planningState.definition, instance.definition);
}

function validPortableProgramOccurrence(scope: string, occurrence: ProgramOccurrence): boolean {
  if (scope.length === 0 || occurrence.schemaVersion !== 1 || occurrence.instanceId.length === 0 ||
      occurrence.occurrenceId.length === 0 || occurrence.blockId.length === 0 ||
      occurrence.roleId.length === 0 || !validProgramDefinitionReference(occurrence.definition) ||
      !isSafeRevision(occurrence.beforeRevision) || !isSafeRevision(occurrence.afterRevision)) return false;
  return occurrence.afterRevision === occurrence.beforeRevision + 1;
}

function validProgramDefinitionReference(reference: ProgramInstance["definition"]): boolean {
  return reference.id.length > 0 && reference.version.length > 0 &&
    reference.configurationFingerprint.length > 0;
}

function invalidData(operation: string, message: string): PersistenceAdapterError {
  return new PersistenceAdapterError("invalid_data", operation, message);
}

function immutableConflict(resource: string, id: string): PersistenceAdapterError {
  return new PersistenceAdapterError(
    "invalid_data",
    resource,
    `A ${resource} with ID "${id}" already exists and is immutable.`,
  );
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
        journal.createIndex("by_scope_id", ["hostScopeKey", "id"], {
          unique: true,
        });
      } else {
        const journal = open.transaction?.objectStore(JOURNAL_STORE);
        if (journal && !journal.indexNames.contains("by_scope_id")) {
          // An old database with duplicate IDs must fail the upgrade instead
          // of silently choosing which persisted record wins.
          journal.createIndex("by_scope_id", ["hostScopeKey", "id"], {
            unique: true,
          });
        }
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
      if (!database.objectStoreNames.contains(CATALOG_REFERENCE_STORE)) {
        database.createObjectStore(CATALOG_REFERENCE_STORE, { keyPath: ["hostScopeKey", "exerciseId"] });
      }
      if (!database.objectStoreNames.contains(ATHLETE_PROFILE_STORE)) {
        database.createObjectStore(ATHLETE_PROFILE_STORE, { keyPath: ["hostScopeKey", "athleteProfileId"] });
      }
      if (!database.objectStoreNames.contains(PROGRAM_DEFINITION_STORE)) {
        database.createObjectStore(PROGRAM_DEFINITION_STORE, { keyPath: ["key.hostScopeKey", "key.definitionId", "key.definitionVersion"] });
      }
      if (!database.objectStoreNames.contains(PROGRAM_INSTANCE_STORE)) {
        database.createObjectStore(PROGRAM_INSTANCE_STORE, { keyPath: ["key.hostScopeKey", "key.instanceId"] });
      }
      if (!database.objectStoreNames.contains(PROGRAM_OCCURRENCE_STORE)) {
        database.createObjectStore(PROGRAM_OCCURRENCE_STORE, { keyPath: ["key.hostScopeKey", "key.instanceId", "key.occurrenceId"] });
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
