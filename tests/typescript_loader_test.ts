import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  CaudexInitializationError,
  CaudexRuntimeError,
  createCaudex,
  type RecommendationRequest,
  type TrackingBatchRequest,
  type TrackingCommandRequest,
  type TemplateInstantiationRequest,
  type ActiveWorkoutRecord,
  type WorkflowRecoveryRecord,
  type JsonValue,
} from "../packages/npm/workout-engine/src/index.ts";

const [wasmPath, fixturePath] = process.argv.slice(2);
if (!wasmPath || !fixturePath) throw new Error("missing test artifact paths");

const wasm = await readFile(wasmPath);
const request = JSON.parse(
  await readFile(fixturePath, "utf8"),
) as RecommendationRequest;

let idSequence = 0;
const activeRecords = new Map<string, ActiveWorkoutRecord>();
const recoveryRecords = new Map<string, WorkflowRecoveryRecord>();
const acceptedRecommendationIds: string[] = [];
const completedWorkoutIds: string[] = [];
const caudex = await createCaudex({
  wasm,
  clock: { now: () => "2026-08-04T12:00:00Z" },
  ids: { next: (kind) => `${kind}-${++idSequence}` },
  persistence: {
    async loadActiveWorkout(hostScopeKey, workoutId) {
      return activeRecords.get(`${hostScopeKey}/${workoutId}`) ?? null;
    },
    async saveActiveWorkout(record, expectedRevision) {
      const key = `${record.hostScopeKey}/${record.workoutId}`;
      const existing = activeRecords.get(key);
      const actual = existing?.snapshot.workouts?.find((workout) => workout.id === record.workoutId)?.revision ?? null;
      if (actual !== expectedRevision) throw new Error(`revision conflict: expected ${expectedRevision}, actual ${actual}`);
      activeRecords.set(key, structuredClone(record));
    },
    async loadCatalog() { return structuredClone(request.catalog); },
    async loadHistory() { return structuredClone(request.history ?? {}); },
    async loadState() {
      return request.methodologyState ? { state: structuredClone(request.methodologyState), revision: "state-1" } : null;
    },
    async appendAcceptedRecommendation(record) {
      if (!acceptedRecommendationIds.includes(record.id)) acceptedRecommendationIds.push(record.id);
    },
    async appendCompletedWorkout(_hostScopeKey, workout) {
      if (!completedWorkoutIds.includes(workout.id)) completedWorkoutIds.push(workout.id);
    },
    async loadWorkflowRecovery(hostScopeKey, workflowId) {
      return recoveryRecords.get(`${hostScopeKey}/${workflowId}`) ?? null;
    },
    async saveWorkflowRecovery(record) {
      recoveryRecords.set(`${record.hostScopeKey}/${record.workflowId}`, structuredClone(record));
    },
  },
});
const result = caudex.recommendSession(request);
if (!result.ok || !result.recommendation) {
  throw new Error("ordinary object request did not produce a recommendation");
}
if (
  result.metadata.resultFingerprint !==
  "83481330a812bb41384d958c104038d230bf93ceee163fd47b7c62a41361fd6f"
) {
  throw new Error("TypeScript facade fingerprint differs from core fixtures");
}
const registry = caudex.listMethodologies();
if (registry.methodologies.length !== 2 || !registry.supportedOperations.includes("applyTrackingCommand")) {
  throw new Error("methodology discovery did not expose registry capabilities");
}
const descriptor = caudex.describeMethodology("caudex.double-progression");
if (!descriptor.fields.some((field) => field.name === "initialLoad" && field.exactDecimal)) {
  throw new Error("methodology discovery omitted exact-decimal field metadata");
}
const validConfig = caudex.validateMethodologyConfiguration({
  methodologyId: request.methodology.id,
  configurationSchemaVersion: request.methodology.configVersion,
  config: request.methodology.config as JsonValue,
});
if (!validConfig.valid) throw new Error("valid methodology configuration was rejected by discovery validation");
const invalidConfig = caudex.validateMethodologyConfiguration({
  methodologyId: request.methodology.id,
  configurationSchemaVersion: request.methodology.configVersion,
  config: {},
});
if (invalidConfig.valid || invalidConfig.issues[0]?.code !== "methodology.config_invalid") {
  throw new Error("invalid methodology configuration did not return structured issues");
}
const validState = caudex.validateMethodologyState({
  methodologyId: request.methodology.id,
  configurationSchemaVersion: request.methodology.configVersion,
  config: request.methodology.config as JsonValue,
  state: { schemaVersion: 1, data: { exercises: [] } },
});
if (!validState.valid) throw new Error("valid methodology state was rejected by discovery validation");
const {
  catalog: ignoredCatalog,
  history: ignoredHistory,
  methodologyState: ignoredState,
  ...requestWithoutSources
} = request;
void ignoredCatalog;
void ignoredHistory;
void ignoredState;
const assembled = await caudex.workflows.recommendFromPersistence({
  ...requestWithoutSources,
  hostScopeKey: "scope-high-level",
});
if (assembled.metadata.resultFingerprint !== result.metadata.resultFingerprint) {
  throw new Error("persistence orchestration assembled a different recommendation request");
}

const highLevel = await caudex.workflows.startRecommendation(result, {
  catalog: request.catalog,
  scope: { hostScopeKey: "scope-high-level" },
  acceptedRecommendationId: "accepted-high-level",
});
const retriedHighLevel = await caudex.workflows.startRecommendation(result, {
  catalog: request.catalog,
  scope: { hostScopeKey: "scope-high-level" },
  acceptedRecommendationId: "accepted-high-level",
});
if (retriedHighLevel.workout.id !== highLevel.workout.id || acceptedRecommendationIds.length !== 1) {
  throw new Error("recommendation instantiation recovery was not idempotent");
}
if (recoveryRecords.get("scope-high-level/recommendation:accepted-high-level")?.status !== "completed") {
  throw new Error("recommendation instantiation did not complete its recovery record");
}
const firstMembership = highLevel.workout.exercises?.[0];
const firstSet = firstMembership?.sets?.[0];
if (!firstMembership || !firstSet) throw new Error("high-level workflow did not instantiate prescribed IDs");
await highLevel.completeSet({
  membershipId: firstMembership.id,
  setId: firstSet.id,
  actual: firstSet.targetMetrics ?? [],
});
const reloaded = await caudex.workflows.reloadActiveWorkout({
  hostScopeKey: "scope-high-level",
  workoutId: highLevel.workout.id,
  catalog: request.catalog,
});
if (!reloaded || reloaded.workout.revision !== 2) {
  throw new Error("high-level active workout did not persist and reload with its revision");
}
for (const membership of reloaded.workout.exercises ?? []) {
  for (const set of membership.sets ?? []) {
    if (set.status !== "open") continue;
    await reloaded.completeSet({
      membershipId: membership.id,
      setId: set.id,
      actual: set.targetMetrics ?? [],
    });
  }
}
const completion = await reloaded.complete();
const retriedCompletion = await reloaded.complete();
if (retriedCompletion.id !== completion.id || completedWorkoutIds.length !== 1) {
  throw new Error("completed-workout persistence was not idempotently resumable");
}
if (recoveryRecords.get(`scope-high-level/completion:${completion.id}`)?.status !== "completed") {
  throw new Error("workout completion did not complete its recovery record");
}
const evaluatedCompletion = await caudex.workflows.evaluateCompletionFromPersistence({
  schemaVersion: 1,
  hostScopeKey: "scope-high-level",
  asOf: request.asOf,
  methodology: request.methodology,
  athlete: request.athlete,
  completedWorkout: completion,
});
if (evaluatedCompletion.metadata.methodology.id !== request.methodology.id) {
  throw new Error("persistence orchestration did not evaluate the completion");
}
if ("memory" in caudex || "alloc" in caudex || "execute" in caudex) {
  throw new Error("the public facade exposes raw WebAssembly ownership");
}

const startRequest: TrackingCommandRequest = {
  schemaVersion: 1,
  snapshot: { workouts: [], startReceipts: [], exerciseCatalog: [] },
  command: { startWorkout: {
    metadata: { commandId: "start-1", occurredAt: "2026-08-04T12:00:00Z" },
    scope: { hostScopeKey: "scope-1" },
    workoutId: "workout-1",
    startedAt: "2026-08-04T12:00:00Z",
  } },
};
const started = caudex.applyTrackingCommand(startRequest);
if (!("accepted" in started.outcome) || started.outcome.accepted.workout.revision !== 1 || started.snapshot.startReceipts?.length !== 1) {
  throw new Error("tracking command did not return its resulting replay-bearing snapshot");
}
const replayed = caudex.applyTrackingCommand({ ...startRequest, snapshot: started.snapshot });
if (!("accepted" in replayed.outcome) || replayed.outcome.accepted.disposition !== "replayed") {
  throw new Error("tracking command retry was not idempotent");
}

const batchRequest: TrackingBatchRequest = {
  schemaVersion: 1,
  snapshot: { workouts: [], startReceipts: [], exerciseCatalog: [{ exerciseId: "squat", availability: "active" }] },
  commands: [
    startRequest.command,
    { addExercise: {
      metadata: { commandId: "add-exercise-1", occurredAt: "2026-08-04T12:01:00Z" },
      scope: { hostScopeKey: "scope-1" },
      workoutId: "workout-1",
      expectedRevision: 1,
      membershipId: "membership-1",
      exerciseId: "squat",
      anchor: { end: {} },
    } },
  ],
};
const batch = caudex.applyTrackingBatch(batchRequest);
if (!batch.applied || batch.snapshot.workouts?.[0]?.revision !== 2) {
  throw new Error("atomic tracking batch did not return the final snapshot");
}

const templateInstantiation: TemplateInstantiationRequest = {
  schemaVersion: 1,
  template: {
    schemaVersion: 1,
    id: "template-1",
    displayName: "Squat day",
    exercises: [{ exerciseId: "squat", sets: [{ kind: "working", targetMetrics: [{ code: "repetitions", value: { amount: "8", unit: "count" } }] }] }],
    revision: 7,
  },
  catalog: [{ id: "squat" }],
  scope: { hostScopeKey: "scope-1" },
  ids: { workoutId: "template-workout-1", membershipIds: ["template-membership-1"], setIds: ["template-set-1"] },
  createdAt: "2026-08-04T12:00:00Z",
};
const instantiatedTemplate = caudex.instantiateTemplate(templateInstantiation);
if (!("accepted" in instantiatedTemplate.outcome) || instantiatedTemplate.outcome.accepted.origin !== "template") {
  throw new Error("template workflow did not cross the WASM boundary");
}

const invalid = caudex.recommendSession({
  ...request,
  schemaVersion: 2,
} as unknown as RecommendationRequest);
if (invalid.ok || invalid.issues?.[0]?.code !== "protocol.unsupported_version") {
  throw new Error("validation failure was not returned as an issue value");
}
caudex.dispose();
caudex.dispose();
try {
  caudex.recommendSession(request);
  throw new Error("disposed runtime remained callable");
} catch (error) {
  if (!(error instanceof CaudexRuntimeError)) throw error;
}

const dataUrl = `data:application/wasm;base64,${wasm.toString("base64")}`;
const browserStyle = await createCaudex({ wasmUrl: dataUrl });
const browserResult = browserStyle.recommendSession(request);
browserStyle.dispose();
if (
  browserResult.metadata.resultFingerprint !== result.metadata.resultFingerprint
) {
  throw new Error("fetch loader and byte loader produced different results");
}

const nodeStyle = await createCaudex({ wasmUrl: pathToFileURL(wasmPath) });
const nodeResult = nodeStyle.recommendSession(request);
nodeStyle.dispose();
if (nodeResult.metadata.resultFingerprint !== result.metadata.resultFingerprint) {
  throw new Error("Node file loader and byte loader produced different results");
}

try {
  await createCaudex({ wasm: new Uint8Array([0, 1, 2, 3]) });
  throw new Error("invalid WASM unexpectedly initialized");
} catch (error) {
  if (
    !(error instanceof CaudexInitializationError) ||
    error.code !== "wasm_compile_failed"
  ) {
    throw error;
  }
}

console.log(
  `caudex TypeScript facade fingerprint: ${result.metadata.resultFingerprint}`,
);
