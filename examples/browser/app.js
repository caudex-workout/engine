import { createCaudex, methodologies } from "@caudex/workout-engine";

const elements = Object.fromEntries([
  "request-editor", "methodology", "run-request", "copy-fixture",
  "download-fixture", "action-status", "result-status", "result-summary",
  "explanations", "explanation-count", "output",
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
  athlete: {
    preferences: { preferredExerciseIds: ["incline-dumbbell-press"] },
  },
  history: { workouts: [] },
  session: {
    availableMinutes: 35,
    availableEquipmentIds: ["dumbbell", "adjustable-bench"],
    goals: ["hypertrophy"],
    maxExercises: 4,
  },
  alternativeLimit: 1,
};

elements["request-editor"].value = formatJson(initialRequest);
let caudex;

elements["run-request"].addEventListener("click", runRecommendation);
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

try {
  caudex = await createCaudex();
  runRecommendation();
} catch (error) {
  renderFailure(error);
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
    document.body.dataset.status = "passed";
    setActionStatus("Recommendation calculated locally.");
  } catch (error) {
    renderFailure(error);
  }
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
