// Browser-only workflow example. Install the optional packages before bundling:
// npm install @caudex-workout/engine @caudex-workout/persistence-indexeddb @caudex-workout/exercise-catalog
import { createCaudex } from "@caudex-workout/engine";
import { IndexedDbPersistenceAdapter } from "@caudex-workout/persistence-indexeddb";
import { records, project } from "@caudex-workout/exercise-catalog";

export async function runPersistedWorkout(request) {
  const scope = { hostScopeKey: "browser-profile" };
  const catalog = records.map(project);
  const persistence = new IndexedDbPersistenceAdapter({ databaseName: "caudex-browser-example" });
  await persistence.replaceCatalog(scope, catalog);
  const caudex = await createCaudex({ persistence });
  const recommendation = caudex.workflows.recommend({ ...request, catalog });
  if (!recommendation.ok) throw new Error(JSON.stringify(recommendation.issues));
  const workout = await caudex.workflows.startRecommendation(recommendation, {
    catalog, scope, acceptedRecommendationId: "accepted-browser-example-1",
  });
  const firstExercise = workout.workout.exercises[0];
  const firstSet = firstExercise.sets[0];
  await workout.completeSet({
    membershipId: firstExercise.id,
    setId: firstSet.id,
    actual: [{ code: "repetitions", value: { amount: "8", unit: "count" } }],
  });

  // A later page load can reconstruct the active workout from IndexedDB.
  const resumed = await caudex.workflows.reloadActiveWorkout({ ...scope, workoutId: workout.workout.id, catalog });
  if (!resumed) throw new Error("active workout was not durable");
  const completion = await resumed.complete();
  const evaluation = caudex.workflows.evaluateCompletion({
    ...request, catalog, history: { workouts: [completion] }, completedWorkout: completion,
  });
  if (evaluation.ok && evaluation.nextMethodologyState) {
    await caudex.workflows.acceptProposedState(evaluation, { hostScopeKey: scope.hostScopeKey, expectedRevision: null });
  }
  caudex.dispose();
  persistence.close();
  return { completion, evaluation };
}
