import {
  createCaudex,
  methodologies,
  type RecommendationRequest,
} from "@caudex/workout-engine";
import { sampleCatalog } from "./sample-catalog.js";

const caudex = await createCaudex();
try {
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

  const request: RecommendationRequest = {
    schemaVersion: 1,
    asOf: "2026-07-25T14:00:00Z",
    methodology,
    catalog: sampleCatalog,
    history: { workouts: [] },
    session: {
      availableMinutes: 35,
      availableEquipmentIds: ["dumbbell", "adjustable-bench"],
    },
  };

  const result = caudex.recommendSession(request);
  if (!result.ok) {
    throw new Error(`Request rejected: ${JSON.stringify(result.issues)}`);
  }

  const exercise = result.recommendation?.exercises[0];
  const explanation = result.explanations?.[0];
  if (!exercise || !explanation) {
    throw new Error("Expected a recommendation with an explanation");
  }

  console.log(JSON.stringify({
    exerciseId: exercise.exerciseId,
    sets: exercise.sets.length,
    explanation: {
      code: explanation.code,
      summary: explanation.summary,
    },
    fingerprint: result.metadata.resultFingerprint,
  }, null, 2));
} finally {
  caudex.dispose();
}
