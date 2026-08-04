import {
  createCaudex,
  methodologies,
  type CompletedWorkout,
  type EvaluationRequest,
  type Exercise,
  type RecommendationRequest,
} from "@caudex-workout/engine";

const catalog: Exercise[] = [{
  id: "incline-dumbbell-press",
  equipmentIds: ["dumbbell", "adjustable-bench"],
}];
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
const recommendationRequest: RecommendationRequest = {
  schemaVersion: 1,
  asOf: "2026-07-25T14:00:00Z",
  methodology,
  catalog,
  history: { workouts: [] },
  session: {
    availableEquipmentIds: ["dumbbell", "adjustable-bench"],
  },
};
const completedWorkout: CompletedWorkout = {
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
const evaluationRequest: EvaluationRequest = {
  schemaVersion: 1,
  asOf: "2026-07-25T14:30:00Z",
  methodology,
  catalog,
  completedWorkout,
};

const caudex = await createCaudex();
try {
  const recommendation = caudex.recommendSession(recommendationRequest);
  const evaluation = caudex.evaluatePerformance(evaluationRequest);
  if (!recommendation.ok || !evaluation.ok) {
    throw new Error(JSON.stringify({
      recommendationIssues: recommendation.issues,
      evaluationIssues: evaluation.issues,
    }));
  }

  console.log(JSON.stringify({
    recommendation: {
      exerciseId: recommendation.recommendation?.exercises[0]?.exerciseId,
      explanationCode: recommendation.explanations?.[0]?.code,
    },
    evaluation: {
      outcome: evaluation.evaluation?.outcome,
      explanationCode: evaluation.explanations?.[0]?.code,
      nextMethodologyState: evaluation.nextMethodologyState,
    },
  }, null, 2));
} finally {
  caudex.dispose();
}

