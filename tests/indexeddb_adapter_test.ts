import "../packages/persistence-indexeddb/node_modules/fake-indexeddb/auto/index.mjs";
import { readFile } from "node:fs/promises";
import { PersistenceConflictError, PersistenceRevisionConflictError } from "../packages/persistence-indexeddb/node_modules/@caudex-workout/persistence/dist/index.js";
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

  const acceptedRecommendation = {
    id: "accepted-1",
    hostScopeKey: "athlete-1",
    acceptedAt: "2026-07-26T12:02:30Z",
    result: {
      ok: false,
      metadata: {
        engineVersion: "test",
        schemaVersion: 1,
        methodology: { id: "caudex.double-progression", version: "1", configVersion: 1 },
        inputFingerprint: "input",
        resultFingerprint: "result",
      },
    },
  };
  await adapter.appendAcceptedRecommendation(acceptedRecommendation);
  await adapter.appendAcceptedRecommendation(structuredClone(acceptedRecommendation));
  let journalConflict: unknown;
  try {
    await adapter.appendAcceptedRecommendation({
      ...acceptedRecommendation,
      acceptedAt: "2026-07-26T12:02:31Z",
    });
  } catch (error) {
    journalConflict = error;
  }
  if (!(journalConflict instanceof Error) || !journalConflict.message.includes("reused")) {
    throw new Error("accepted-recommendation ID reuse was not rejected");
  }
  const journalExport = await adapter.exportPortable({ hostScopeKey: "athlete-1", exportedAt: "2026-08-04T12:00:00Z" });
  if (journalExport.acceptedRecommendations?.length !== 1) {
    throw new Error("accepted-recommendation retry created a duplicate journal row");
  }

  const invalidDatePlan = await adapter.importPortable({
    schemaVersion: 1,
    mode: "merge",
    conflictPolicy: "reject",
    dryRun: true,
    document: {
      schemaVersion: 1,
      exportedAt: "2026-02-31T12:00:00Z",
    },
  });
  if (invalidDatePlan.valid || !invalidDatePlan.issues.some((issue) => issue.code === "portable.timestamp_invalid")) {
    throw new Error("portable import accepted an impossible calendar date");
  }

  const invalidRevisionPlan = await adapter.importPortable({
    schemaVersion: 1,
    mode: "merge",
    conflictPolicy: "reject",
    dryRun: true,
    document: {
      schemaVersion: 1,
      exportedAt: "2026-08-04T12:00:00Z",
      methodologyStates: [{
        hostScopeKey: "athlete-1",
        methodologyId: "caudex.double-progression",
        methodologyVersion: "0.1.0",
        state: { schemaVersion: 1, data: {} },
        revision: "9007199254740992",
        updatedAt: "2026-08-04T12:00:00Z",
      }],
    },
  });
  if (invalidRevisionPlan.valid || !invalidRevisionPlan.issues.some((issue) => issue.code === "portable.revision_invalid")) {
    throw new Error("portable import accepted an unsafe revision number");
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

  const exported = await adapter.exportPortable({ hostScopeKey: "athlete-1", exportedAt: "2026-08-04T12:00:00Z" });
  if (exported.schemaVersion !== 1 || exported.customExercises?.map((record) => record.exercise.id).join(",") !== "bench-press,squat" ||
      exported.activeWorkouts?.[0]?.snapshot.workouts?.[0]?.revision !== 2 ||
      exported.activeWorkouts?.[0]?.snapshot.workouts?.[0]?.exercises?.[0]?.sets?.[0]?.targetMetrics?.[0]?.value.amount !== "185.00") {
    throw new Error("portable export did not preserve deterministic scoped adapter data");
  }
  const importedAdapter = new IndexedDbPersistenceAdapter({ databaseName: `caudex-import-${crypto.randomUUID()}` });
  try {
    const dryRun = await importedAdapter.importPortable({ schemaVersion: 1, mode: "merge", conflictPolicy: "reject", dryRun: true, document: exported });
    if (!dryRun.valid || (await importedAdapter.loadActiveWorkout("athlete-1", "active-1")) !== null) {
      throw new Error("portable dry run mutated IndexedDB");
    }
    const applied = await importedAdapter.importPortable({ schemaVersion: 1, mode: "merge", conflictPolicy: "reject", dryRun: false, document: exported });
    if (!applied.valid || (await importedAdapter.loadTemplate("athlete-1", "template-1"))?.template.displayName !== "Squat day" ||
        (await importedAdapter.loadActiveWorkout("athlete-1", "active-1"))?.snapshot.workouts?.[0]?.exercises?.[0]?.sets?.[0]?.targetMetrics?.[0]?.value.amount !== "185.00") {
      throw new Error("portable import did not round trip exact IndexedDB records");
    }
    const rejectedConflict = await importedAdapter.importPortable({ schemaVersion: 1, mode: "merge", conflictPolicy: "reject", dryRun: false, document: exported });
    if (rejectedConflict.valid || rejectedConflict.issues[0]?.code !== "portable.conflict") {
      throw new Error("portable merge did not report existing-record conflicts");
    }
    const kept = await importedAdapter.importPortable({ schemaVersion: 1, mode: "merge", conflictPolicy: "keepExisting", dryRun: false, document: exported });
    if (!kept.valid) throw new Error("portable keep-existing merge was rejected");
    await importedAdapter.close();
    const reopened = new IndexedDbPersistenceAdapter({ databaseName: importedAdapter.databaseName });
    if ((await reopened.loadState(key))?.revision !== "2") throw new Error("portable import was not durable after reopen");
    await reopened.deleteDatabase();

    const fixtureAdapter = new IndexedDbPersistenceAdapter({ databaseName: `caudex-fixture-${crypto.randomUUID()}` });
    const fixture = JSON.parse(await readFile("fixtures/portable/export-v1.json", "utf8"));
    const fixturePlan = await fixtureAdapter.importPortable({ schemaVersion: 1, mode: "replace", conflictPolicy: "overwrite", dryRun: false, document: fixture });
    const fixtureRoundTrip = await fixtureAdapter.exportPortable({ hostScopeKey: "scope-1", exportedAt: "2026-08-04T12:00:00Z" });
    if (!fixturePlan.valid || fixtureRoundTrip.catalogReferences?.[0]?.catalogId !== "host.catalog" ||
        fixtureRoundTrip.completedWorkouts?.[0]?.workout.exercises[0]?.sets[0]?.actualMetrics[0]?.value.amount !== "185.00") {
      throw new Error("shared portable fixture did not preserve canonical meaning in IndexedDB");
    }
    await fixtureAdapter.deleteDatabase();
  } finally {
    try { await importedAdapter.deleteDatabase(); } catch { /* already deleted */ }
  }
  await secondConnection.close();

  console.log("caudex IndexedDB adapter integration passed");
} finally {
  await adapter.deleteDatabase();
}
