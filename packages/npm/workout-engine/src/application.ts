import type {
  ActiveWorkout,
  ClockProvider,
  CompletedWorkout,
  EvaluationResult,
  Program,
  ProgramOptions,
  RecommendationResult,
  RuntimeFacade,
  WorkflowFacade,
} from "./index.ts";

export interface ProgramDependencies {
  clock: ClockProvider;
  runtime: RuntimeFacade;
  workflows: WorkflowFacade;
  hasStatePersistence: boolean;
  runtimeError(message: string): Error;
}

/** Constructs the application facade without owning engine or host state. */
export function createProgramFacade(
  options: ProgramOptions,
  dependencies: ProgramDependencies,
): Program {
  const catalog = [...options.catalog];
  const scope = { hostScopeKey: options.hostScopeKey, athleteId: options.athleteProfile?.id };
  let history = structuredClone(options.history);
  let state = options.methodologyState;
  let stateRevision = options.methodologyStateRevision ?? null;

  return {
    recommend(recommendationOptions = {}) {
      return dependencies.runtime.recommend({
        schemaVersion: 1,
        asOf: recommendationOptions.asOf ?? dependencies.clock.now(),
        methodology: options.methodology,
        methodologyState: state,
        catalog,
        athleteProfile: options.athleteProfile,
        history,
        trainingContext: recommendationOptions.trainingContext,
        alternativeLimit: recommendationOptions.alternativeLimit,
        tieBreakSeed: recommendationOptions.tieBreakSeed,
      });
    },
    startWorkout(result, startOptions = {}): Promise<ActiveWorkout> {
      return dependencies.workflows.startRecommendation(result, {
        catalog,
        scope,
        acceptedRecommendationId: startOptions.acceptedRecommendationId,
        methodologyStateRevision: stateRevision ?? undefined,
      });
    },
    reloadWorkout(workoutId): Promise<ActiveWorkout | null> {
      return dependencies.workflows.reloadActiveWorkout({
        hostScopeKey: scope.hostScopeKey,
        workoutId,
        catalog,
      });
    },
    replaceHistory(nextHistory) {
      history = structuredClone(nextHistory);
    },
    appendCompletedWorkout(workout) {
      const workouts = [...(history?.workouts ?? [])];
      const existing = workouts.findIndex((candidate) => candidate.id === workout.id);
      if (existing === -1) workouts.push(structuredClone(workout));
      else workouts[existing] = structuredClone(workout);
      history = { ...history, workouts };
    },
    evaluate(completedWorkout, evaluationOptions = {}): EvaluationResult {
      return dependencies.runtime.evaluate({
        schemaVersion: 1,
        asOf: evaluationOptions.asOf ?? dependencies.clock.now(),
        methodology: options.methodology,
        methodologyState: state,
        catalog,
        athleteProfile: options.athleteProfile,
        history: evaluationOptions.history ?? history,
        completedWorkout,
      });
    },
    async acceptState(evaluation: EvaluationResult): Promise<unknown> {
      if (!evaluation.ok || !evaluation.nextMethodologyState) {
        throw dependencies.runtimeError("A successful evaluation with a methodology-state proposal is required.");
      }
      const accepted = dependencies.hasStatePersistence
        ? await dependencies.workflows.acceptProposedState(evaluation, {
            hostScopeKey: scope.hostScopeKey,
            expectedRevision: stateRevision,
          })
        : { state: structuredClone(evaluation.nextMethodologyState), revision: stateRevision };
      state = structuredClone(evaluation.nextMethodologyState);
      const revision = (accepted as { revision?: unknown } | null)?.revision;
      if (typeof revision === "string") stateRevision = revision;
      return accepted;
    },
  };
}
