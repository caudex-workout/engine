import {
  methodologies,
  type CompletedWorkout,
  type Exercise,
  type MethodologyState,
  type RecommendationRequest,
} from "@caudex-workout/engine";
import {
  PersistenceConflictError,
  type CatalogSource,
  type CompareAndSetMethodologyState,
  type HistoryQuery,
  type HistorySource,
  type MethodologyStateKey,
  type MethodologyStateRecord,
  type MethodologyStateStore,
} from "@caudex/persistence";

interface LegacyExerciseRow {
  exercise_pk: number;
  label: string;
  gear: string;
  retired: 0 | 1;
}

interface LegacySetRow {
  set_pk: number;
  workout_pk: number;
  exercise_pk: number;
  sequence: number;
  pounds: string;
  reps: number;
}

interface LegacyWorkoutRow {
  workout_pk: number;
  member_pk: number;
  started_at: string;
  finished_at: string;
}

interface LegacyStateRow {
  member_pk: number;
  methodology: string;
  methodology_version: string;
  schema_version: number;
  payload: MethodologyState["data"];
  row_version: number;
  updated_at: string;
}

class LegacyFitnessRepository {
  readonly exercises: LegacyExerciseRow[] = [{
    exercise_pk: 42,
    label: "Incline Dumbbell Press",
    gear: "dumbbell,adjustable-bench",
    retired: 0,
  }];
  readonly workouts: LegacyWorkoutRow[] = [
    {
      workout_pk: 902,
      member_pk: 7,
      started_at: "2026-07-20T14:00:00Z",
      finished_at: "2026-07-20T14:40:00Z",
    },
    {
      workout_pk: 901,
      member_pk: 7,
      started_at: "2026-07-18T14:00:00Z",
      finished_at: "2026-07-18T14:35:00Z",
    },
  ];
  readonly sets: LegacySetRow[] = [
    {
      set_pk: 2,
      workout_pk: 902,
      exercise_pk: 42,
      sequence: 1,
      pounds: "50",
      reps: 10,
    },
    {
      set_pk: 1,
      workout_pk: 901,
      exercise_pk: 42,
      sequence: 1,
      pounds: "45",
      reps: 12,
    },
  ];
  states: LegacyStateRow[] = [{
    member_pk: 7,
    methodology: "caudex.double-progression",
    methodology_version: "0.1.0",
    schema_version: 1,
    payload: { exercises: [] },
    row_version: 3,
    updated_at: "2026-07-20T14:45:00Z",
  }];

  workoutWrites = 0;
  exerciseWrites = 0;
  stateWrites = 0;

  findMemberWorkouts(memberPk: number, through: string): LegacyWorkoutRow[] {
    return this.workouts.filter((row) =>
      row.member_pk === memberPk && row.finished_at <= through
    );
  }

  findSets(workoutPk: number): LegacySetRow[] {
    return this.sets.filter((row) => row.workout_pk === workoutPk);
  }

  findState(memberPk: number, methodology: string): LegacyStateRow | null {
    return this.states.find((row) =>
      row.member_pk === memberPk && row.methodology === methodology
    ) ?? null;
  }

  replaceState(expectedVersion: number | null, next: LegacyStateRow): boolean {
    const index = this.states.findIndex((row) =>
      row.member_pk === next.member_pk &&
      row.methodology === next.methodology
    );
    const actualVersion = index === -1 ? null : this.states[index]!.row_version;
    if (actualVersion !== expectedVersion) return false;
    if (index === -1) this.states.push(next);
    else this.states[index] = next;
    this.stateWrites += 1;
    return true;
  }
}

function memberPk(hostScopeKey: string): number {
  const match = /^member:(\d+)$/.exec(hostScopeKey);
  if (!match) throw new Error(`Unsupported host scope: ${hostScopeKey}`);
  return Number(match[1]);
}

function exerciseId(primaryKey: number): string {
  return `legacy-exercise:${primaryKey}`;
}

function mapExercise(row: LegacyExerciseRow): Exercise {
  return {
    id: exerciseId(row.exercise_pk),
    name: row.label,
    equipmentIds: row.gear.split(","),
  };
}

function mapWorkout(
  repository: LegacyFitnessRepository,
  row: LegacyWorkoutRow,
): CompletedWorkout {
  const sets = repository.findSets(row.workout_pk)
    .sort((left, right) => left.sequence - right.sequence);
  return {
    id: `legacy-workout:${row.workout_pk}`,
    startedAt: row.started_at,
    completedAt: row.finished_at,
    exercises: [{
      exerciseId: exerciseId(sets[0]!.exercise_pk),
      sets: sets.map((set) => ({
        id: `legacy-set:${set.set_pk}`,
        kind: "working",
        status: "completed",
        actualMetrics: [
          { code: "load", value: { amount: set.pounds, unit: "lb" } },
          {
            code: "repetitions",
            value: { amount: String(set.reps), unit: "count" },
          },
        ],
      })),
    }],
  };
}

function mapState(row: LegacyStateRow): MethodologyStateRecord {
  return {
    key: {
      hostScopeKey: `member:${row.member_pk}`,
      methodologyId: row.methodology,
    },
    methodologyVersion: row.methodology_version,
    state: { schemaVersion: row.schema_version, data: row.payload },
    revision: String(row.row_version),
    updatedAt: row.updated_at,
  };
}

class LegacyCatalogSource implements CatalogSource {
  constructor(private readonly repository: LegacyFitnessRepository) {}

  async loadCatalog(
    _scope: Parameters<CatalogSource["loadCatalog"]>[0],
  ): Promise<readonly Exercise[]> {
    return this.repository.exercises
      .filter((row) => row.retired === 0)
      .map(mapExercise);
  }
}

class LegacyHistorySource implements HistorySource {
  constructor(private readonly repository: LegacyFitnessRepository) {}

  async loadHistory(query: HistoryQuery) {
    const requestedIds = query.exerciseIds === undefined
      ? null
      : new Set(query.exerciseIds);
    const workouts = this.repository
      .findMemberWorkouts(memberPk(query.hostScopeKey), query.through)
      .map((row) => mapWorkout(this.repository, row))
      .filter((workout) =>
        requestedIds === null ||
        workout.exercises.some((exercise) =>
          requestedIds.has(exercise.exerciseId)
        )
      )
      .sort((left, right) =>
        left.completedAt.localeCompare(right.completedAt) ||
        left.id.localeCompare(right.id)
      );
    return { workouts };
  }
}

class LegacyMethodologyStateStore implements MethodologyStateStore {
  constructor(private readonly repository: LegacyFitnessRepository) {}

  async loadState(
    key: MethodologyStateKey,
  ): Promise<MethodologyStateRecord | null> {
    const row = this.repository.findState(
      memberPk(key.hostScopeKey),
      key.methodologyId,
    );
    return row === null ? null : mapState(row);
  }

  async compareAndSetState(
    change: CompareAndSetMethodologyState,
  ): Promise<MethodologyStateRecord> {
    const nextVersion = change.expectedRevision === null
      ? 1
      : Number(change.expectedRevision) + 1;
    const next: LegacyStateRow = {
      member_pk: memberPk(change.key.hostScopeKey),
      methodology: change.key.methodologyId,
      methodology_version: change.methodologyVersion,
      schema_version: change.nextState.schemaVersion,
      payload: change.nextState.data,
      row_version: nextVersion,
      updated_at: change.updatedAt,
    };
    if (
      !this.repository.replaceState(
        change.expectedRevision === null
          ? null
          : Number(change.expectedRevision),
        next,
      )
    ) {
      const actual = this.repository.findState(
        next.member_pk,
        next.methodology,
      );
      throw new PersistenceConflictError(
        change.key,
        change.expectedRevision,
        actual === null ? null : String(actual.row_version),
      );
    }
    return mapState(next);
  }
}

const repository = new LegacyFitnessRepository();
const catalogSource = new LegacyCatalogSource(repository);
const historySource = new LegacyHistorySource(repository);
const stateStore = new LegacyMethodologyStateStore(repository);
const scope = "member:7";
const methodologyId = "caudex.double-progression";
const asOf = "2026-07-21T12:00:00Z";

const [catalog, history, storedState] = await Promise.all([
  catalogSource.loadCatalog({ hostScopeKey: scope, asOf }),
  historySource.loadHistory({ hostScopeKey: scope, through: asOf }),
  stateStore.loadState({ hostScopeKey: scope, methodologyId }),
]);

const request: RecommendationRequest = {
  schemaVersion: 1,
  asOf,
  methodology: methodologies.doubleProgression({
    repRange: { min: 8, max: 12 },
    workingSets: 3,
    advancementCriteria: {
      minimumSuccessfulSets: 3,
      minimumRepetitions: 12,
    },
    initialLoad: { amount: "45", unit: "lb" },
    loadIncrement: { amount: "5", unit: "lb" },
    failurePolicy: {
      onPartial: "hold",
      onFailure: "regress",
      regressionAmount: { amount: "5", unit: "lb" },
    },
    rounding: {
      mode: "nearest",
      quantum: { amount: "2.5", unit: "lb" },
    },
  }),
  catalog: [...catalog],
  history,
  ...(storedState === null ? {} : { methodologyState: storedState.state }),
};

// Calculation is still a direct snapshot call:
// const result = caudex.recommendSession(request);
// Only an explicitly accepted result's proposed state is persisted.
const savedState = await stateStore.compareAndSetState({
  key: { hostScopeKey: scope, methodologyId },
  expectedRevision: storedState?.revision ?? null,
  methodologyVersion: "0.1.0",
  nextState: {
    schemaVersion: 1,
    data: { exercises: [{ exerciseId: "legacy-exercise:42", load: "55" }] },
  },
  updatedAt: "2026-07-21T12:01:00Z",
});

console.log(JSON.stringify({
  request: {
    catalogId: request.catalog[0]?.id,
    historyIds: request.history?.workouts?.map((workout) => workout.id),
    historyLoads: request.history?.workouts?.map((workout) =>
      workout.exercises[0]?.sets[0]?.actualMetrics[0]?.value.amount
    ),
    loadedStateRevision: storedState?.revision,
  },
  writes: {
    exercises: repository.exerciseWrites,
    workouts: repository.workoutWrites,
    methodologyStates: repository.stateWrites,
  },
  hostRecordsRetained: {
    exercises: repository.exercises.length,
    workouts: repository.workouts.length,
  },
  savedStateRevision: savedState.revision,
}));
