import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  CaudexInitializationError,
  CaudexRuntimeError,
  CaudexMeasurementError,
  createCaudex,
  lb,
  reps,
  type RecommendationRequest,
  type TrackingBatchRequest,
  type TrackingCommandRequest,
  type TemplateInstantiationRequest,
  type ActiveWorkoutRecord,
  type WorkflowRecoveryRecord,
  type PortableDocument,
  type JsonValue,
  type Exercise,
  type ProgramRecommendationRequest,
} from "../packages/npm/workout-engine/src/index.ts";

const [wasmPath, fixturePath, portableFixturePath] = process.argv.slice(2);
if (!wasmPath || !fixturePath || !portableFixturePath) throw new Error("missing test artifact paths");

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
const program = caudex.createProgram({
  catalog: request.catalog,
  methodology: request.methodology,
  hostScopeKey: "scope-program",
  athlete: request.athlete,
  history: request.history,
  methodologyState: request.methodologyState,
});
const programResult = program.recommend({ asOf: request.asOf, session: request.session, alternativeLimit: request.alternativeLimit });
if (!programResult.ok || programResult.metadata.resultFingerprint !== result.metadata.resultFingerprint) {
  throw new Error("bound program and canonical runtime did not produce equivalent behavior");
}
program.replaceHistory({ workouts: [] });
const refreshedHistoryResult = program.recommend({ asOf: request.asOf, session: request.session, alternativeLimit: request.alternativeLimit });
if (refreshedHistoryResult.metadata.inputFingerprint === programResult.metadata.inputFingerprint) {
  throw new Error("replacing program history did not affect the next complete canonical request");
}
program.replaceHistory(request.history);
if (caudex.runtime.recommend(request).metadata.resultFingerprint !== result.metadata.resultFingerprint) {
  throw new Error("runtime namespace is not equivalent to the v0.1 alias");
}
if (lb("185.00").amount !== "185.00" || reps(8).value.amount !== "8") {
  throw new Error("measurement helpers did not preserve exact canonical values");
}
try {
  lb(Number.NaN);
  throw new Error("invalid measurement was accepted");
} catch (error) {
  if (!(error instanceof CaudexMeasurementError)) throw error;
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
const programWorkout = await program.startWorkout(programResult, { acceptedRecommendationId: "accepted-program" });
const programSet = programWorkout.workout.exercises?.[0]?.sets?.[0];
if (!programSet) throw new Error("program did not instantiate its recommendation");
await programWorkout.completeSet(programSet.id, { reps: 8, load: lb(65) });
if (programWorkout.workout.exercises?.[0]?.sets?.[0]?.actualMetrics?.length !== 2) {
  throw new Error("ergonomic set completion did not resolve membership and metrics");
}
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
program.appendCompletedWorkout(completion);
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

const portableDocument = JSON.parse(await readFile(portableFixturePath, "utf8")) as PortableDocument;
const portableExport = caudex.exportPortable(portableDocument);
if (!("accepted" in portableExport.outcome) || portableExport.outcome.accepted.completedWorkouts?.[0]?.workout.exercises[0]?.sets[0]?.actualMetrics[0]?.value.amount !== "185.00") {
  throw new Error("portable export did not preserve an exact decimal through WASM");
}
const portablePlan = caudex.validatePortableImport({
  schemaVersion: 1,
  mode: "merge",
  conflictPolicy: "reject",
  dryRun: true,
  document: portableDocument,
});
if (!portablePlan.valid || !portablePlan.dryRun || portablePlan.counts.completedWorkouts !== 1) {
  throw new Error("portable dry-run validation did not cross the WASM boundary");
}

const doubleConfig = request.methodology.config as JsonValue;
const rpeConfig = {
  initialEstimatedOneRepMax: { amount: "225", unit: "lb" },
  topSetRepetitions: 5,
  targetRpe: "8.0",
  backoff: { calculation: "percentage_of_top_set", percentage: "90", repetitions: 8, setCount: 1 },
  rounding: { mode: "nearest", quantum: { amount: "2.5", unit: "lb" } },
  exertionPolicy: { tolerance: "0.5", onOvershoot: "decrease_estimate", onUndershoot: "increase_estimate", estimateAdjustmentPercentage: "2.5" },
  estimationFormula: "epley",
} satisfies JsonValue;
const mixedRequest: ProgramRecommendationRequest = {
  schemaVersion: 1,
  asOf: request.asOf,
  program: {
    strategy: { id: "caudex.fixed-session", versionRequirement: "0.1.0", configVersion: 1, config: {} },
    exercises: [
      { slotId: "accessory", exerciseId: "leg-extension", progression: { stateId: "block-1-accessory", methodology: { id: "caudex.double-progression", versionRequirement: "0.1.0", configVersion: 1, config: doubleConfig } } },
      { slotId: "primary", exerciseId: "bench-press", progression: { stateId: "block-1-primary", methodology: { id: "caudex.rpe-top-set-backoff", versionRequirement: "0.1.0", configVersion: 1, config: rpeConfig } } },
    ],
  },
  catalog: [{ id: "leg-extension" }, { id: "bench-press" }],
};
const richExercise = {
  id: "rich-squat",
  knowledge: {
    schemaVersion: 1,
    familyId: "squat",
    variantDimensions: [{ dimension: "bar-position", value: "high-bar" }],
    movementPatterns: ["squat"],
    structuralType: "compound",
    laterality: "bilateral",
    repetitionSemantics: "total",
    equipmentRequirements: [{ equipmentId: "barbell", role: "load_bearing" }],
    trackingDimensions: [{ metricCode: "repetitions" }],
    loadingMode: "external_load",
    progressionCapabilities: { externalLoad: true, repetitions: true },
    restrictionTags: ["requires-rack"],
    relationships: { substituteIds: ["front-squat"] },
    skillLevel: "intermediate",
    stabilityDemand: "free",
    setupBurden: "moderate",
    fatigue: { axial: "high", technical: "moderate" },
    evidence: [{ authority: "caudex_curated", confidence: "high" }],
  },
} satisfies Exercise;
if (richExercise.knowledge?.relationships?.substituteIds?.[0] !== "front-squat") {
  throw new Error("exercise knowledge types did not preserve rich relationships");
}
const mixed = caudex.recommendProgram(mixedRequest);
if (!mixed.ok || mixed.recommendation.exercises.length !== 2 || mixed.recommendation.exercises[0]?.programming?.progression.id !== "caudex.double-progression" || mixed.recommendation.exercises[1]?.programming?.progression.id !== "caudex.rpe-top-set-backoff") {
  throw new Error("mixed program recommendation did not retain per-exercise progression provenance");
}
const replayedMixed = caudex.runtime.recommendProgram(structuredClone(mixedRequest));
if (!replayedMixed.ok || replayedMixed.metadata.resultFingerprint !== mixed.metadata.resultFingerprint) {
  throw new Error("mixed program recommendation was not deterministic");
}
const mixedEvaluation = caudex.evaluateProgram({
  schemaVersion: 1,
  asOf: "2026-08-04T14:00:00Z",
  recommendation: mixed.recommendation,
  catalog: mixedRequest.catalog,
  completedWorkout: {
    id: "mixed-workout", startedAt: "2026-08-04T12:00:00Z", completedAt: "2026-08-04T13:00:00Z",
    exercises: [
      { exerciseId: "leg-extension", sets: [{ kind: "working", actualMetrics: [{ code: "load", value: { amount: "45", unit: "lb" } }, { code: "repetitions", value: { amount: "12", unit: "count" } }], status: "completed" }] },
      { exerciseId: "bench-press", sets: [{ kind: "top", actualMetrics: [{ code: "load", value: { amount: "190", unit: "lb" } }, { code: "repetitions", value: { amount: "5", unit: "count" } }, { code: "rpe", value: { amount: "9", unit: "rpe" } }], status: "completed" }] },
    ],
  },
});
if (!mixedEvaluation.ok || mixedEvaluation.progressionStateProposals[0]?.stateId !== "block-1-accessory" || mixedEvaluation.progressionStateProposals[1]?.stateId !== "block-1-primary") {
  throw new Error("mixed evaluation did not route independent progression-state proposals");
}
const activeMixed = await caudex.startProgramWorkout(mixed, { catalog: mixedRequest.catalog, scope: { hostScopeKey: "scope-mixed" }, acceptedRecommendationId: "accepted-mixed" });
for (const exercise of activeMixed.workout.exercises ?? []) {
  for (const set of exercise.sets ?? []) {
    await activeMixed.completeSet({ membershipId: exercise.id, setId: set.id, actual: set.targetMetrics ?? [] });
  }
}
const completedMixed = await activeMixed.complete();
const activeMixedEvaluation = caudex.evaluateProgram({ schemaVersion: 1, asOf: "2026-08-04T14:00:00Z", recommendation: mixed.recommendation, catalog: mixedRequest.catalog, completedWorkout: completedMixed });
if (!activeMixedEvaluation.ok || activeMixedEvaluation.progressionStateProposals.length !== 2) {
  throw new Error("mixed recommendation did not survive active-workout completion and evaluation");
}
if (registry.progressionMethods.length !== 2 || registry.programStrategies[0]?.id !== "caudex.fixed-session") {
  throw new Error("capability discovery did not distinguish strategies from progression methods");
}
const invalidMixed = caudex.recommendProgram({
  ...mixedRequest,
  program: { ...mixedRequest.program, exercises: [
    mixedRequest.program.exercises[0]!,
    { ...mixedRequest.program.exercises[1]!, progression: { ...mixedRequest.program.exercises[1]!.progression, stateId: "block-1-accessory" } },
  ] },
});
if (invalidMixed.ok || invalidMixed.issues[0]?.code !== "progression.duplicate_state_id") {
  throw new Error("duplicate progression state identity did not return a structured issue");
}
const wrongVersion = caudex.recommendProgram({
  ...mixedRequest,
  program: { ...mixedRequest.program, exercises: [{ ...mixedRequest.program.exercises[0]!, progression: { ...mixedRequest.program.exercises[0]!.progression, methodology: { ...mixedRequest.program.exercises[0]!.progression.methodology, versionRequirement: "2.0.0" } } }] },
});
if (wrongVersion.ok || wrongVersion.issues[0]?.code !== "progression.unsupported_version") {
  throw new Error("progression version mismatch did not return a structured issue");
}
const incompatibleProgression = caudex.recommendProgram({
  ...mixedRequest,
  catalog: [{
    ...mixedRequest.catalog[0]!,
    knowledge: { progressionCapabilities: { externalLoad: false } },
  }, mixedRequest.catalog[1]!],
});
if (incompatibleProgression.ok || incompatibleProgression.issues[0]?.code !== "exercise.rejected.incompatible_progression" || incompatibleProgression.issues[0]?.path !== "/program/exercises/0") {
  throw new Error("explicitly incompatible exercise knowledge did not reject the progression slot");
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
