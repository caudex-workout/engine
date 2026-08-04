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
} from "../packages/npm/workout-engine/src/index.ts";

const [wasmPath, fixturePath] = process.argv.slice(2);
if (!wasmPath || !fixturePath) throw new Error("missing test artifact paths");

const wasm = await readFile(wasmPath);
const request = JSON.parse(
  await readFile(fixturePath, "utf8"),
) as RecommendationRequest;

const caudex = await createCaudex({ wasm });
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
