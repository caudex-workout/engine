import "../packages/persistence-indexeddb/node_modules/fake-indexeddb/auto/index.mjs";
import { PersistenceConflictError } from "../packages/persistence-indexeddb/node_modules/@caudex/persistence/dist/index.js";
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

  console.log("caudex IndexedDB adapter integration passed");
} finally {
  await adapter.deleteDatabase();
}
