import {
  createCaudex,
  methodologies,
} from "@caudex/workout-engine";

const output = document.querySelector("#output");
const methodology = methodologies.doubleProgression({
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
});
const catalog = [{
  id: "incline-dumbbell-press",
  equipmentIds: ["dumbbell", "adjustable-bench"],
}];
const completedWorkout = {
  id: "workout-1",
  startedAt: "2026-07-25T14:00:00Z",
  completedAt: "2026-07-25T14:30:00Z",
  exercises: [{
    exerciseId: "incline-dumbbell-press",
    sets: Array.from({ length: 3 }, (_, index) => ({
      id: `set-${index + 1}`,
      kind: "working",
      actualMetrics: [
        { code: "load", value: { amount: "45", unit: "lb" } },
        { code: "repetitions", value: { amount: "12", unit: "count" } },
      ],
      status: "completed",
    })),
  }],
};

try {
  const caudex = await createCaudex();
  try {
    const recommendation = caudex.recommendSession({
      schemaVersion: 1,
      asOf: "2026-07-25T14:00:00Z",
      methodology,
      catalog,
      history: { workouts: [] },
      session: {
        availableEquipmentIds: ["dumbbell", "adjustable-bench"],
      },
    });
    const evaluation = caudex.evaluatePerformance({
      schemaVersion: 1,
      asOf: "2026-07-25T14:30:00Z",
      methodology,
      catalog,
      completedWorkout,
    });
    if (!recommendation.ok || !evaluation.ok) {
      throw new Error("Caudex rejected the example request");
    }
    output.textContent = JSON.stringify({
      recommendation: {
        exerciseId: recommendation.recommendation?.exercises[0]?.exerciseId,
        explanationCode: recommendation.explanations?.[0]?.code,
      },
      evaluation: {
        outcome: evaluation.evaluation?.outcome,
        explanationCode: evaluation.explanations?.[0]?.code,
      },
    }, null, 2);
    document.body.dataset.status = "passed";
  } finally {
    caudex.dispose();
  }
} catch (error) {
  output.textContent = String(error?.stack ?? error);
  document.body.dataset.status = "failed";
}

