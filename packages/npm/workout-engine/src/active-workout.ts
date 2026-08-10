import type {
  ActiveWorkout,
  ClockProvider,
  CompletionConversionResult,
  Exercise,
  IdProvider,
  JsonValue,
  Metric,
  OrchestrationPersistence,
  SetResult,
  TrackingCommand,
  TrackingCommandResult,
  TrackingSnapshot,
  TrackedWorkout,
  WorkflowRecoveryRecord,
} from "./index.ts";
import { metrics as setMetrics } from "./measurements.ts";

export interface ActiveWorkoutDependencies {
  clock: ClockProvider;
  ids: IdProvider;
  persistence?: Partial<OrchestrationPersistence>;
  applyTracking(snapshot: TrackingSnapshot, command: TrackingCommand): TrackingCommandResult;
  convertCompletion(workout: TrackedWorkout, catalog: Exercise[]): CompletionConversionResult;
  persistSnapshot(hostScopeKey: string, workoutId: string, snapshot: TrackingSnapshot, expectedRevision: number | null): Promise<void>;
  runtimeError(message: string): Error;
  trackingRejected(issues: import("./index.ts").TrackingIssue[]): Error;
}

export function createActiveWorkout(
  initialSnapshot: TrackingSnapshot,
  workoutId: string,
  catalog: Exercise[],
  dependencies: ActiveWorkoutDependencies,
): ActiveWorkout {
  let current = initialSnapshot;
  const currentWorkout = (): TrackedWorkout => {
    const workout = current.workouts?.find((candidate) => candidate.id === workoutId);
    if (!workout) throw dependencies.runtimeError(`Active workout "${workoutId}" is absent from its snapshot.`);
    return workout;
  };
  const apply = async (command: TrackingCommand): Promise<TrackedWorkout> => {
    const before = currentWorkout();
    const result = dependencies.applyTracking(current, command);
    current = result.snapshot;
    if ("rejected" in result.outcome) throw dependencies.trackingRejected(result.outcome.rejected.issues);
    await dependencies.persistSnapshot(before.scope.hostScopeKey, workoutId, current, before.revision);
    return result.outcome.accepted.workout;
  };
  return {
    get snapshot() { return current; },
    get workout() { return currentWorkout(); },
    async completeSet(
      inputOrSetId: string | { membershipId: string; setId: string; actual: Metric[]; status?: "completed" | "partial" | "failed" },
      result?: SetResult,
    ) {
      const workout = currentWorkout();
      let membershipId: string;
      let setId: string;
      let actual: Metric[];
      let status: "completed" | "partial" | "failed";
      if (typeof inputOrSetId === "string") {
        setId = inputOrSetId;
        const memberships = (workout.exercises ?? []).filter((membership) => membership.sets?.some((set) => set.id === setId));
        if (memberships.length !== 1) throw dependencies.trackingRejected(setLookupError(workoutId, setId, memberships.length));
        membershipId = memberships[0].id;
        const trackedSet = memberships[0].sets?.find((set) => set.id === setId);
        if (trackedSet?.status !== "open") {
          throw dependencies.trackingRejected([{
            code: "tracking.set_not_open", category: "conflict", severity: "error",
            message: `Set "${setId}" cannot be completed because its status is "${trackedSet?.status}".`,
            relatedIds: [workoutId, membershipId, setId],
          }]);
        }
        actual = setMetrics(result ?? {});
        status = result?.status ?? "completed";
      } else {
        ({ membershipId, setId } = inputOrSetId);
        actual = inputOrSetId.actual;
        status = inputOrSetId.status ?? "completed";
      }
      return apply({ completeSet: {
        metadata: { commandId: dependencies.ids.next("command"), occurredAt: dependencies.clock.now() },
        scope: workout.scope, workoutId, expectedRevision: workout.revision, membershipId, setId,
        actualMetrics: actual, status, completedAt: dependencies.clock.now(),
      } });
    },
    async complete() {
      const workout = currentWorkout();
      if (workout.status !== "completed") {
        await apply({ completeWorkout: {
          metadata: { commandId: dependencies.ids.next("command"), occurredAt: dependencies.clock.now() },
          scope: workout.scope, workoutId, expectedRevision: workout.revision, completedAt: dependencies.clock.now(),
        } });
      }
      const converted = dependencies.convertCompletion(currentWorkout(), catalog);
      if ("rejected" in converted.outcome) throw dependencies.trackingRejected(converted.outcome.rejected);
      const completed = converted.outcome.accepted;
      if (dependencies.persistence?.appendCompletedWorkout || dependencies.persistence?.saveWorkflowRecovery) {
        const recovery: WorkflowRecoveryRecord = {
          hostScopeKey: workout.scope.hostScopeKey, workflowId: `completion:${workoutId}`,
          kind: "workout_completion", status: "pending", idempotencyKey: workoutId,
          payload: completed as unknown as JsonValue, updatedAt: dependencies.clock.now(),
        };
        await dependencies.persistence.saveWorkflowRecovery?.(recovery);
        await dependencies.persistence.appendCompletedWorkout?.(workout.scope.hostScopeKey, completed);
        await dependencies.persistence.saveWorkflowRecovery?.({ ...recovery, status: "completed", updatedAt: dependencies.clock.now() });
      }
      return completed;
    },
  };
}

function setLookupError(workoutId: string, setId: string, matches: number): import("./index.ts").TrackingIssue[] {
  return [{
    code: matches === 0 ? "tracking.set_not_found" : "tracking.set_ambiguous",
    category: matches === 0 ? "not_found" : "conflict", severity: "error",
    message: matches === 0
      ? `Set "${setId}" is not part of workout "${workoutId}".`
      : `Set "${setId}" occurs more than once in workout "${workoutId}".`,
    relatedIds: [workoutId, setId],
  }];
}
