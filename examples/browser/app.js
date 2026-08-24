import {
  acceptProgramAdvancement,
  createCaudex,
  instantiateProgram,
  methodologies,
  programs,
  proposeProgramAdvancement,
  resolveNextSession,
} from "@caudex-workout/engine";

const elements = Object.fromEntries([
  "request-editor", "methodology", "run-request", "copy-fixture",
  "download-fixture", "action-status", "result-status", "result-summary",
  "explanations", "explanation-count", "output",
  "program-example", "program-start", "program-advance", "program-status",
  "program-summary", "program-output",
].map((id) => [id, document.querySelector(`#${id}`)]));

const methodologyReferences = {
  "double-progression": () => methodologies.doubleProgression({
    repRange: { min: 8, max: 12 },
    workingSets: 3,
    advancementCriteria: { minimumSuccessfulSets: 3, minimumRepetitions: 12 },
    initialLoad: { amount: "45", unit: "lb" },
    loadIncrement: { amount: "5", unit: "lb" },
    failurePolicy: {
      onPartial: "hold",
      onFailure: "regress",
      regressionAmount: { amount: "5", unit: "lb" },
    },
    rounding: { mode: "nearest", quantum: { amount: "2.5", unit: "lb" } },
  }),
  "rpe-top-set-backoff": () => methodologies.rpeTopSetBackoff({
    initialEstimatedOneRepMax: { amount: "225", unit: "lb" },
    topSetRepetitions: 5,
    targetRpe: "8.0",
    backoff: {
      calculation: "percentage_of_top_set",
      percentage: "90",
      repetitions: 8,
      setCount: 3,
    },
    rounding: { mode: "nearest", quantum: { amount: "2.5", unit: "lb" } },
    exertionPolicy: {
      tolerance: "0.5",
      onOvershoot: "decrease_estimate",
      onUndershoot: "increase_estimate",
      estimateAdjustmentPercentage: "2.5",
    },
    estimationFormula: "epley",
  }),
};

const initialRequest = {
  schemaVersion: 1,
  asOf: "2026-07-25T14:00:00Z",
  methodology: methodologyReferences["double-progression"](),
  methodologyState: {
    schemaVersion: 1,
    data: {
      exercises: {
        "incline-dumbbell-press": {
          load: { amount: "65", unit: "lb" },
        },
      },
    },
  },
  catalog: [{
    id: "incline-dumbbell-press",
    name: "Incline Dumbbell Press",
    equipmentIds: ["dumbbell", "adjustable-bench"],
    movementTags: ["horizontal-push"],
    muscleContributions: [
      { muscleId: "pectoralis-major", role: "primary" },
      { muscleId: "triceps", role: "secondary" },
    ],
  }],
  athleteProfile: {
    id: "athlete-1",
    goals: { primary: { id: "hypertrophy" } },
    schedule: { preferredSessionsPerWeek: 4 },
    duration: { preferredMinutes: 60, acceptableMinimumMinutes: 45, acceptableMaximumMinutes: 75 },
    musclePriorities: [{ muscleId: "pectoralis-major", priority: "emphasize" }],
    exercisePreferences: [{ targetKind: "exercise", targetId: "incline-dumbbell-press", level: "preferred" }],
    locations: [
      { id: "gym", equipment: [{ equipmentId: "dumbbell" }, { equipmentId: "barbell" }, { equipmentId: "cable-stack" }, { equipmentId: "adjustable-bench" }] },
      { id: "home", equipment: [{ equipmentId: "dumbbell" }, { equipmentId: "adjustable-bench" }, { equipmentId: "pull-up-bar" }] },
    ],
  },
  history: { workouts: [] },
  trainingContext: {
    locationId: "gym",
    availableMinutes: 35,
    equipment: { removals: ["cable-stack"] },
    restrictions: [{ id: "today-no-overhead", targetKind: "movement_pattern", targetId: "overhead-push" }],
    maxExercises: 4,
  },
  alternativeLimit: 1,
};

// A complete-session request exercises the canonical composer independently
// from the single-methodology editor above. Temporary time/equipment changes
// stay in constraints and do not mutate the program intent.
const compositionRequest = {
  schemaVersion: 1,
  asOf: initialRequest.asOf,
  intent: {
    definitionId: "browser:upper",
    definitionVersion: 1,
    definitionFingerprint: "browser-fixture",
    instanceId: "browser:instance",
    occurrenceId: "browser:occurrence",
    blockId: "browser:block",
    roleId: "upper",
    planningStateRevision: 1,
    strategy: "fixed",
    slots: [
      ["press-focus", ["bench-press"], "rpe-top-set-backoff", "required", 0, true],
      ["press-accessory", ["flat-dumbbell-press", "incline-dumbbell-press", "machine-chest-press"], "double-progression", "required", 1],
      ["row", ["chest-supported-row", "one-arm-dumbbell-row", "seated-cable-row"], "double-progression", "required", 1],
      ["lateral-raise", ["cable-lateral-raise", "dumbbell-lateral-raise"], "double-progression", "optional", 2],
    ].map(([slotId, exerciseIds, method, presence, priorityTier, fixed], index) => ({
      id: `slot-${index + 1}:${slotId}`,
      presence,
      selection: fixed
        ? { fixed: { exerciseId: exerciseIds[0] } }
        : { dynamic: { exerciseIds } },
      progression: {
        stateId: `browser:${slotId}:state`,
        methodology: method === "rpe-top-set-backoff"
          ? methodologyReferences["rpe-top-set-backoff"]()
          : methodologyReferences["double-progression"](),
      },
      priorityTier,
    })),
  },
  catalog: [
    { id: "bench-press", name: "Bench Press", equipmentIds: ["barbell", "adjustable-bench"], movementTags: ["horizontal-push"] },
    { id: "incline-dumbbell-press", name: "Incline Dumbbell Press", equipmentIds: ["dumbbell", "adjustable-bench"], movementTags: ["horizontal-push"] },
    { id: "flat-dumbbell-press", name: "Flat Dumbbell Press", equipmentIds: ["dumbbell", "adjustable-bench"], movementTags: ["horizontal-push"] },
    { id: "machine-chest-press", name: "Machine Chest Press", equipmentIds: ["chest-press-machine"], movementTags: ["horizontal-push"] },
    { id: "chest-supported-row", name: "Chest-Supported Row", equipmentIds: ["dumbbell", "adjustable-bench"], movementTags: ["horizontal-pull"] },
    { id: "one-arm-dumbbell-row", name: "One-Arm Dumbbell Row", equipmentIds: ["dumbbell", "adjustable-bench"], movementTags: ["horizontal-pull"] },
    { id: "seated-cable-row", name: "Seated Cable Row", equipmentIds: ["cable-stack"], movementTags: ["horizontal-pull"] },
    { id: "cable-lateral-raise", name: "Cable Lateral Raise", equipmentIds: ["cable-stack"] },
    { id: "dumbbell-lateral-raise", name: "Dumbbell Lateral Raise", equipmentIds: ["dumbbell"] },
  ],
  constraints: {
    availableEquipmentIds: ["barbell", "dumbbell", "adjustable-bench", "cable-stack", "chest-press-machine"],
    hardMaximumMinutes: 45,
    targetDurationMinutes: 43,
    maximumExercises: 4,
  },
  durationEstimates: [
    { slotId: "slot-1:press-focus", exerciseId: "bench-press", minutes: 14 },
    { slotId: "slot-2:press-accessory", exerciseId: "incline-dumbbell-press", minutes: 10 },
    { slotId: "slot-2:press-accessory", exerciseId: "flat-dumbbell-press", minutes: 10 },
    { slotId: "slot-2:press-accessory", exerciseId: "machine-chest-press", minutes: 9 },
    { slotId: "slot-3:row", exerciseId: "chest-supported-row", minutes: 10 },
    { slotId: "slot-3:row", exerciseId: "one-arm-dumbbell-row", minutes: 10 },
    { slotId: "slot-3:row", exerciseId: "seated-cable-row", minutes: 10 },
    { slotId: "slot-4:lateral-raise", exerciseId: "cable-lateral-raise", minutes: 7 },
    { slotId: "slot-4:lateral-raise", exerciseId: "dumbbell-lateral-raise", minutes: 6 },
  ],
};

elements["request-editor"].value = formatJson(initialRequest);
let caudex;
let planning;

elements["run-request"].addEventListener("click", runRecommendation);
elements["program-start"].addEventListener("click", startProgramDemo);
elements["program-advance"].addEventListener("click", advanceProgramDemo);
elements["program-example"].addEventListener("change", startProgramDemo);
elements.methodology.addEventListener("change", () => {
  try {
    const request = JSON.parse(elements["request-editor"].value);
    request.methodology = methodologyReferences[elements.methodology.value]();
    delete request.methodologyState;
    elements["request-editor"].value = formatJson(request);
    setActionStatus("Methodology updated. Run to calculate a new result.");
  } catch (error) {
    setActionStatus(`Fix the request JSON before switching: ${error.message}`, true);
  }
});
elements["copy-fixture"].addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(elements["request-editor"].value);
    setActionStatus("Request JSON copied to the clipboard.");
  } catch {
    setActionStatus("Clipboard access is unavailable in this browser.", true);
  }
});
elements["download-fixture"].addEventListener("click", () => {
  const blob = new Blob(
    [elements["request-editor"].value],
    { type: "application/json" },
  );
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `caudex-${elements.methodology.value}-request.json`;
  anchor.click();
  URL.revokeObjectURL(url);
  setActionStatus(`Downloaded ${anchor.download}.`);
});

const planningStrategy = {
  id: "caudex.fixed-session",
  versionRequirement: "^0.1.0",
  configVersion: 1,
  config: {},
};

const programExamples = {
  rotation: () => programs.presets.asynchronousUpperLower({
    id: "browser:upper-lower",
    version: "1",
    strategy: planningStrategy,
  }),
  weekdays: () => programs.presets.fixedWeekdayUpperLower({
    id: "browser:weekday-upper-lower",
    version: "1",
    strategy: planningStrategy,
  }),
  block: () => programs.presets.structuredHypertrophyBlock({
    id: "browser:hypertrophy-block",
    version: "1",
    strategy: planningStrategy,
  }),
};

try {
  caudex = await createCaudex();
  runRecommendation();
  startProgramDemo();
} catch (error) {
  renderFailure(error);
}

function startProgramDemo() {
  const definition = programExamples[elements["program-example"].value]();
  const instantiated = instantiateProgram(definition, {
    instanceId: `browser:${elements["program-example"].value}:instance`,
    athleteId: "athlete-1",
    startedOn: "2026-08-10",
    lifecycle: "active",
  });
  planning = { definition, ...instantiated };
  renderProgramDemo("Program instance started. Previewing does not advance state.");
}

function advanceProgramDemo() {
  if (!planning || planning.state.completed) return;
  const intent = nextProgramIntent();
  const proposal = proposeProgramAdvancement({
    ...planning,
    intent,
    status: "completed",
  });
  planning.state = acceptProgramAdvancement(planning.state, proposal);
  renderProgramDemo("Host explicitly accepted one completed occurrence.", proposal);
}

function nextProgramIntent() {
  const block = planning.definition.blocks[planning.state.blockIndex];
  const schedule = block.schedule;
  const occurrence = { id: `browser:occurrence:${planning.state.revision + 1}` };
  if (schedule.kind === "fixed_weekdays") {
    occurrence.weekday = schedule.sessions[planning.state.sessionCursor].weekday;
  }
  return resolveNextSession({ ...planning, occurrence });
}

function renderProgramDemo(message, proposal) {
  const intent = planning.state.completed ? null : nextProgramIntent();
  const block = planning.definition.blocks[planning.state.blockIndex];
  elements["program-status"].textContent = planning.state.completed ? "Completed" : "Active";
  elements["program-status"].className = `result-status ${planning.state.completed ? "" : "success"}`;
  elements["program-advance"].disabled = planning.state.completed;
  elements["program-summary"].replaceChildren(
    element("p", message),
    element("div", intent ? displayName(intent.roleId) : "Program complete", "exercise-name"),
    element("p", `Block: ${block.displayName ?? block.id} · Phase: ${intent?.phase ?? block.phase ?? "base"} · Accepted revision: ${planning.state.revision}`),
  );
  elements["program-output"].textContent = formatJson({
    definition: planning.definition,
    instance: planning.instance,
    acceptedState: planning.state,
    nextIntent: intent,
    lastProposal: proposal,
  });
}

function runRecommendation() {
  if (!caudex) return;
  try {
    const request = JSON.parse(elements["request-editor"].value);
    const result = caudex.recommendSession(request);
    elements.output.textContent = formatJson(result);
    if (!result.ok) {
      renderIssues(result.issues ?? []);
      document.body.dataset.status = "rejected";
      return;
    }
    renderRecommendation(result);
    renderCompositionDemo();
    document.body.dataset.status = "passed";
    setActionStatus("Recommendation calculated locally.");
  } catch (error) {
    renderFailure(error);
  }
}

function renderCompositionDemo() {
  const edited = JSON.parse(elements["request-editor"].value);
  const today = edited.trainingContext ?? {};
  const location = edited.athleteProfile?.locations?.find((item) => item.id === today.locationId);
  const equipment = new Set(today.equipment?.override ?? location?.equipment?.map((item) => item.equipmentId) ?? []);
  for (const id of today.equipment?.additions ?? []) equipment.add(id);
  for (const id of today.equipment?.removals ?? []) equipment.delete(id);
  const result = caudex.composeSession({
    ...compositionRequest,
    constraints: {
      ...compositionRequest.constraints,
      availableMinutes: today.availableMinutes,
      availableEquipmentIds: [...equipment],
      excludedExerciseIds: today.excludedExerciseIds,
      maximumExercises: today.maxExercises,
    },
    preferences: today.preferences,
  });
  const recommendation = JSON.parse(elements.output.textContent);
  const outcome = result.successful ?? result.constrained;
  if (!outcome) {
    elements.output.textContent = formatJson({ ...recommendation, composition: result });
    setActionStatus(`Session composition returned ${Object.keys(result)[0]}.`, true);
    return;
  }
  const exercises = outcome.recommendation.exercises ?? [];
  const swaps = exercises[0] ? caudex.findSubstitutes({
    exerciseId: exercises[0].exerciseId,
    role: { movementPatterns: ["horizontal-push"] },
    catalog: compositionRequest.catalog,
    context: {
      availableEquipmentIds: [...equipment],
      excludedExerciseIds: today.excludedExerciseIds,
      alreadySelectedExerciseIds: exercises.slice(1).map((item) => item.exerciseId),
    },
    alternativeLimit: 3,
  }) : null;
  elements.output.textContent = formatJson({ ...recommendation, composition: result, swaps });
  const alternativeCount = (outcome.plan.selectionMetadata ?? [])
    .reduce((count, slot) => count + (slot.alternatives?.length ?? 0), 0);
  const omitted = (outcome.plan.omittedReasons ?? [])
    .map((item) => `${item.slotId}: ${item.reason}`);
  const exerciseNodes = exercises.map((exercise) =>
    element("div", displayName(exercise.exerciseId), "exercise-name"));
  const swapButton = element("button", "Swap primary exercise", "secondary");
  swapButton.addEventListener("click", () => {
    const choices = [swaps?.selected, ...(swaps?.alternatives ?? [])].filter(Boolean);
    if (choices.length === 0) {
      setActionStatus("No eligible substitute under today's constraints.");
      return;
    }
    exerciseNodes[0].textContent = displayName(choices[0].exerciseId);
    swapButton.textContent = `Applied ${displayName(choices[0].exerciseId)}`;
    elements.output.textContent = formatJson({
      ...recommendation,
      composition: result,
      swaps,
      acceptedSwap: { fromExerciseId: exercises[0].exerciseId, toExerciseId: choices[0].exerciseId },
    });
    setActionStatus(`Applied swap: ${displayName(choices[0].exerciseId)} · ${choices[0].reasons.join(", ")}`);
  });
  elements["result-summary"].replaceChildren(
    element("p", `${Object.hasOwn(result, "constrained") ? "Constrained" : "Complete"} session · ${outcome.plan.estimatedDurationMinutes ?? "unknown"} min estimate`),
    ...exerciseNodes,
    element("p", `${alternativeCount} viable slot alternatives · ${outcome.plan.decisionReasons?.length ?? 0} structured planning reasons`),
    element("p", `${swaps?.selected ? 1 + swaps.alternatives.length : 0} role-preserving primary swaps under today's equipment`),
    swapButton,
    ...omitted.map((reason) => element("p", `Omitted ${reason}`)),
    metricList(exercises.flatMap((exercise) => exercise.sets.flatMap((set) => set.targetMetrics ?? []))),
  );
  renderExplanations(outcome.explanations ?? []);
  setActionStatus("Complete multi-exercise session composed locally.");
}

function renderRecommendation(result) {
  const exercise = result.recommendation?.exercises?.[0];
  const metrics = exercise?.sets?.flatMap((set) => set.targetMetrics ?? []) ?? [];
  elements["result-status"].textContent = "Recommended";
  elements["result-status"].className = "result-status success";
  elements["result-summary"].replaceChildren(
    element("p", "Primary exercise"),
    element("div", displayName(exercise?.exerciseId), "exercise-name"),
    metricList(metrics),
  );
  renderExplanations(result.explanations ?? []);
}

function renderIssues(issues) {
  elements["result-status"].textContent = "Rejected";
  elements["result-status"].className = "result-status error";
  elements["result-summary"].replaceChildren(
    element("p", "The request was safely rejected."),
    ...issues.map((issue) =>
      element("div", `${issue.code}: ${issue.message}`, "explanation")
    ),
  );
  renderExplanations([]);
}

function renderExplanations(explanations) {
  elements.explanations.replaceChildren(
    ...explanations.map((explanation) => {
      const item = document.createElement("li");
      item.className = "explanation";
      item.append(
        element("code", explanation.code),
        element("p", explanation.summary),
      );
      return item;
    }),
  );
  const suffix = explanations.length === 1 ? "record" : "records";
  elements["explanation-count"].textContent =
    `${explanations.length} ${suffix}`;
}

function renderFailure(error) {
  elements.output.textContent = String(error?.stack ?? error);
  elements["result-status"].textContent = "Error";
  elements["result-status"].className = "result-status error";
  elements["result-summary"].replaceChildren(
    element("p", error?.message ?? String(error)),
  );
  renderExplanations([]);
  setActionStatus("The playground could not calculate this request.", true);
  document.body.dataset.status = "failed";
}

function metricList(metrics) {
  const container = document.createElement("div");
  container.className = "prescription";
  for (const metric of metrics) {
    container.append(element(
      "span",
      `${metric.code}: ${metric.value.amount} ${metric.value.unit}`,
      "metric",
    ));
  }
  return container;
}

function element(tagName, text, className) {
  const node = document.createElement(tagName);
  node.textContent = text ?? "No exercise returned";
  if (className) node.className = className;
  return node;
}

function setActionStatus(message, isError = false) {
  elements["action-status"].textContent = message;
  elements["action-status"].className = isError
    ? "action-status error"
    : "action-status";
}

function displayName(identifier) {
  return identifier
    ? identifier.split("-").map((word) =>
      word.charAt(0).toUpperCase() + word.slice(1)
    ).join(" ")
    : undefined;
}

function formatJson(value) {
  return JSON.stringify(value, null, 2);
}
