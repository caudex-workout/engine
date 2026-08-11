import {
  createCaudex,
  lb,
  methodologies,
} from "@caudex-workout/engine";

const sampleCatalog = [{
  id: "incline-dumbbell-press",
  name: "Incline Dumbbell Press",
  equipmentIds: ["dumbbell", "adjustable-bench"],
  movementTags: ["horizontal-push"],
  muscleContributions: [
    { muscleId: "pectoralis-major", role: "primary" as const },
    { muscleId: "triceps", role: "secondary" as const },
  ],
}];

const caudex = await createCaudex();
try {
  const methodology = methodologies.presets.hypertrophy({
    initialLoad: lb(45),
    loadIncrement: lb(5),
    rounding: { mode: "nearest", quantum: lb("2.5") },
  });
  const program = caudex.createProgram({
    hostScopeKey: "quickstart-profile",
    methodology,
    catalog: sampleCatalog,
    history: { workouts: [] },
  });
  const result = program.recommend({
    asOf: "2026-07-25T14:00:00Z",
    trainingContext: {
      availableMinutes: 35,
      equipment: { override: ["dumbbell", "adjustable-bench"] },
    },
  });
  if (!result.ok) {
    throw new Error(`Request rejected: ${JSON.stringify(result.issues)}`);
  }

  const exercise = result.recommendation.exercises[0];
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
