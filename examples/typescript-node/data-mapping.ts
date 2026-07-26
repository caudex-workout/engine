import type {
  CompletedWorkout,
  Exercise,
  MethodologyState,
  RecommendationResult,
} from "@caudex/workout-engine";

interface HostExercise {
  key: number;
  displayName: string;
  equipmentCodes?: string[] | null;
  archived: boolean;
}

interface HostWorkout {
  key: number;
  startedAt: string;
  completedAt: string;
  exercises: Array<{
    exerciseKey: number;
    sets: Array<{
      key: number;
      loadPounds: string | null;
      repetitions: number | null;
      outcome: "done" | "partial" | "skipped" | "failed";
    }>;
  }>;
}

interface StoredMethodologyState {
  methodologyId: string;
  methodologyVersion: string;
  state: MethodologyState;
  revision: number;
}

interface MethodologyStateStore {
  compareAndSet(
    scope: string,
    expectedRevision: number,
    next: StoredMethodologyState,
  ): Promise<void>;
}

type RecommendationDecision =
  | { kind: "accept" }
  | { kind: "reject"; reason?: string };

export function exerciseId(key: number): string {
  return `host-exercise:${key}`;
}

export function mapCatalog(records: HostExercise[]): Exercise[] {
  return records
    .filter((record) => !record.archived)
    .map((record) => ({
      id: exerciseId(record.key),
      name: record.displayName,
      ...(record.equipmentCodes
        ? { equipmentIds: record.equipmentCodes }
        : {}),
    }));
}

export function mapWorkout(record: HostWorkout): CompletedWorkout {
  return {
    id: `host-workout:${record.key}`,
    startedAt: record.startedAt,
    completedAt: record.completedAt,
    exercises: record.exercises.map((exercise) => ({
      exerciseId: exerciseId(exercise.exerciseKey),
      sets: exercise.sets.map((set) => {
        const actualMetrics: CompletedWorkout["exercises"][number]["sets"][number]["actualMetrics"] = [];
        if (set.loadPounds !== null) {
          actualMetrics.push({
            code: "load",
            value: { amount: set.loadPounds, unit: "lb" },
          });
        }
        if (set.repetitions !== null) {
          actualMetrics.push({
            code: "repetitions",
            value: { amount: String(set.repetitions), unit: "count" },
          });
        }
        return {
          id: `host-set:${set.key}`,
          kind: "working",
          actualMetrics,
          status: {
            done: "completed",
            partial: "partial",
            skipped: "skipped",
            failed: "failed",
          }[set.outcome] as "completed" | "partial" | "skipped" | "failed",
        };
      }),
    })),
  };
}

export async function applyRecommendationDecision(
  store: MethodologyStateStore,
  scope: string,
  current: StoredMethodologyState | undefined,
  result: RecommendationResult,
  decision: RecommendationDecision,
): Promise<"unchanged" | "saved"> {
  if (
    decision.kind === "reject" ||
    !result.ok ||
    !result.nextMethodologyState
  ) {
    return "unchanged";
  }

  await store.compareAndSet(scope, current?.revision ?? 0, {
    methodologyId: result.metadata.methodology.id,
    methodologyVersion: result.metadata.methodology.version,
    state: result.nextMethodologyState,
    revision: (current?.revision ?? 0) + 1,
  });
  return "saved";
}

const catalog = mapCatalog([{
  key: 42,
  displayName: "Incline Dumbbell Press",
  equipmentCodes: ["dumbbell", "adjustable-bench"],
  archived: false,
}]);
const workout = mapWorkout({
  key: 103,
  startedAt: "2026-07-22T13:00:00Z",
  completedAt: "2026-07-22T13:40:00Z",
  exercises: [{
    exerciseKey: 42,
    sets: [{
      key: 1,
      loadPounds: "65",
      repetitions: 12,
      outcome: "done",
    }],
  }],
});

let savedState: StoredMethodologyState | undefined;
const stateStore: MethodologyStateStore = {
  async compareAndSet(_scope, expectedRevision, next) {
    if (expectedRevision !== 0) throw new Error("unexpected revision");
    savedState = next;
  },
};
const proposedResult: RecommendationResult = {
  ok: true,
  nextMethodologyState: {
    schemaVersion: 1,
    data: { exercises: [] },
  },
  metadata: {
    engineVersion: "0.1.0",
    schemaVersion: 1,
    methodology: {
      id: "caudex.double-progression",
      version: "0.1.0",
      configVersion: 1,
    },
    inputFingerprint: "example-input",
    resultFingerprint: "example-result",
  },
};
const rejected = await applyRecommendationDecision(
  stateStore,
  "athlete:7",
  undefined,
  proposedResult,
  { kind: "reject", reason: "Preview only" },
);
const accepted = await applyRecommendationDecision(
  stateStore,
  "athlete:7",
  undefined,
  proposedResult,
  { kind: "accept" },
);

console.log(JSON.stringify({
  catalogExerciseId: catalog[0]?.id,
  historyExerciseId: workout.exercises[0]?.exerciseId,
  load: workout.exercises[0]?.sets[0]?.actualMetrics[0]?.value,
  decisions: { rejected, accepted },
  savedMethodologyId: savedState?.methodologyId,
}));
