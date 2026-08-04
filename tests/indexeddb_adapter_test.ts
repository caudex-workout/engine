import "../packages/persistence-indexeddb/node_modules/fake-indexeddb/auto/index.mjs";
import { PersistenceConflictError, PersistenceRevisionConflictError } from "../packages/persistence-indexeddb/node_modules/@caudex/persistence/dist/index.js";
import { IndexedDbPersistenceAdapter } from "../packages/persistence-indexeddb/src/index.ts";

const adapter = new IndexedDbPersistenceAdapter({
  databaseName: `caudex-test-${crypto.randomUUID()}`,
});
const scope = {
  hostScopeKey: "athlete-1",
  asOf: "2026-07-26T12:00:00Z",
};

try {
  await adapter.replaceCatalog(scope, [
    { id: "squat" },
    { id: "bench-press" },
  ]);
  const catalog = await adapter.loadCatalog(scope);
  if (catalog.map((exercise) => exercise.id).join(",") !==
    "bench-press,squat") {
    throw new Error("catalog loading was not deterministic");
  }

  await adapter.appendCompletedWorkout("athlete-1", {
    id: "later",
    startedAt: "2026-07-25T12:00:00Z",
    completedAt: "2026-07-25T13:00:00Z",
    exercises: [],
  });
  await adapter.appendCompletedWorkout("athlete-1", {
    id: "earlier",
    startedAt: "2026-07-24T12:00:00Z",
    completedAt: "2026-07-24T13:00:00Z",
    exercises: [],
  });
  const history = await adapter.loadHistory({
    hostScopeKey: "athlete-1",
    through: "2026-07-26T12:00:00Z",
  });
  if (history.workouts.map((workout) => workout.id).join(",") !==
    "earlier,later") {
    throw new Error("history was not chronologically ordered");
  }

  const key = {
    hostScopeKey: "athlete-1",
    methodologyId: "caudex.double-progression",
  };
  const first = await adapter.compareAndSetState({
    key,
    expectedRevision: null,
    methodologyVersion: "0.1.0",
    nextState: { schemaVersion: 1, data: { exercises: [] } },
    updatedAt: "2026-07-26T12:00:00Z",
  });
  if (first.revision !== "1") {
    throw new Error("initial state revision was not one");
  }
  let conflict: unknown;
  try {
    await adapter.compareAndSetState({
      key,
      expectedRevision: null,
      methodologyVersion: "0.1.0",
      nextState: first.state,
      updatedAt: "2026-07-26T12:01:00Z",
    });
  } catch (error) {
    conflict = error;
  }
  if (!(conflict instanceof PersistenceConflictError)) {
    throw new Error("stale compare-and-set did not report a conflict");
  }
  const second = await adapter.compareAndSetState({
    key,
    expectedRevision: first.revision,
    methodologyVersion: "0.1.0",
    nextState: first.state,
    updatedAt: "2026-07-26T12:02:00Z",
  });
  if (second.revision !== "2" ||
      (await adapter.loadState(key))?.revision !== "2") {
    throw new Error("state compare-and-set did not round trip");
  }

  const active = {
    hostScopeKey: "athlete-1",
    workoutId: "active-1",
    snapshot: {
      workouts: [{
        id: "active-1",
        scope: { hostScopeKey: "athlete-1" },
        revision: 1,
        status: "active" as const,
        startedAt: "2026-07-26T12:00:00Z",
        exercises: [{ id: "membership-1", exerciseId: "squat", sets: [{
          id: "set-1", kind: "working", status: "open" as const,
          targetMetrics: [{ code: "load", value: { amount: "185.00", unit: "lb" } }],
        }] }],
      }],
      startReceipts: [],
      exerciseCatalog: [{ exerciseId: "squat", availability: "active" as const }],
    },
  };
  await adapter.saveActiveWorkout(active, null);
  const secondConnection = new IndexedDbPersistenceAdapter({ databaseName: adapter.databaseName });
  const loadedActive = await secondConnection.loadActiveWorkout("athlete-1", "active-1");
  if (loadedActive?.snapshot.workouts?.[0]?.exercises?.[0]?.sets?.[0]?.targetMetrics?.[0]?.value.amount !== "185.00") {
    throw new Error("active workout did not round trip exact canonical decimals across connections");
  }
  let workoutConflict: unknown;
  try { await adapter.saveActiveWorkout(active, null); } catch (error) { workoutConflict = error; }
  if (!(workoutConflict instanceof PersistenceRevisionConflictError)) {
    throw new Error("stale active-workout revision did not report a conflict");
  }
  const revised = structuredClone(active);
  revised.snapshot.workouts[0].revision = 2;
  await adapter.saveActiveWorkout(revised, 1);

  const template = {
    hostScopeKey: "athlete-1",
    template: { schemaVersion: 1 as const, id: "template-1", displayName: "Squat day", exercises: [{ exerciseId: "squat" }], revision: 1 },
  };
  await adapter.saveTemplate(template, null);
  if ((await adapter.loadTemplate("athlete-1", "template-1"))?.template.displayName !== "Squat day") {
    throw new Error("workout template did not round trip");
  }
  await adapter.saveWorkflowRecovery({
    hostScopeKey: "athlete-1", workflowId: "workflow-1", kind: "workout_completion",
    status: "pending", idempotencyKey: "completion-1", payload: { workoutId: "active-1" },
    updatedAt: "2026-07-26T12:03:00Z",
  });
  if ((await adapter.loadWorkflowRecovery("athlete-1", "workflow-1"))?.idempotencyKey !== "completion-1") {
    throw new Error("workflow recovery record did not round trip");
  }
  await secondConnection.close();

  console.log("caudex IndexedDB adapter integration passed");
} finally {
  await adapter.deleteDatabase();
}
