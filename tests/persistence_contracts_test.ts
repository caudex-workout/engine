import {
  PERSISTENCE_CONTRACT_VERSION,
  PersistenceAdapterError,
  PersistenceConflictError,
  PersistenceRevisionConflictError,
  type ActiveWorkoutStore,
  type CatalogSource,
  type CompletedWorkoutSink,
  type HistorySource,
  type MethodologyStateStore,
  type RecommendationJournal,
  type WorkoutTemplateStore,
  type WorkflowRecoveryStore,
} from "../packages/persistence/src/index.ts";

const catalog: CatalogSource = {
  async loadCatalog() {
    return [];
  },
};
const history: HistorySource = {
  async loadHistory() {
    return { workouts: [] };
  },
};
const states: MethodologyStateStore = {
  async loadState() {
    return null;
  },
  async compareAndSetState(change) {
    return {
      key: change.key,
      methodologyVersion: change.methodologyVersion,
      state: change.nextState,
      revision: "1",
      updatedAt: change.updatedAt,
    };
  },
};
const journal: RecommendationJournal = {
  async appendAcceptedRecommendation() {},
};
const workouts: CompletedWorkoutSink = {
  async appendCompletedWorkout() {},
};
const active: ActiveWorkoutStore = {
  async loadActiveWorkout() { return null; },
  async saveActiveWorkout() {},
};
const templates: WorkoutTemplateStore = {
  async loadTemplate() { return null; },
  async saveTemplate() {},
};
const recovery: WorkflowRecoveryStore = {
  async loadWorkflowRecovery() { return null; },
  async saveWorkflowRecovery() {},
};

void catalog;
void history;
void states;
void journal;
void workouts;
void active;
void templates;
void recovery;

if (PERSISTENCE_CONTRACT_VERSION !== 2) {
  throw new Error("unexpected persistence contract version");
}

const revisionConflict = new PersistenceRevisionConflictError("active_workout", "workout-1", 4, 5);
if (revisionConflict.resource !== "active_workout" || revisionConflict.expectedRevision !== 4 || revisionConflict.actualRevision !== 5) {
  throw new Error("resource revision conflict details were not preserved");
}

const key = { hostScopeKey: "athlete-1", methodologyId: "methodology-1" };
const conflict = new PersistenceConflictError(key, "4", "5");
if (
  conflict.name !== "PersistenceConflictError" ||
  conflict.expectedRevision !== "4" ||
  conflict.actualRevision !== "5"
) {
  throw new Error("persistence conflict details were not preserved");
}

const adapterError = new PersistenceAdapterError(
  "unavailable",
  "loadCatalog",
  "repository unavailable",
);
if (
  adapterError.name !== "PersistenceAdapterError" ||
  adapterError.code !== "unavailable" ||
  adapterError.operation !== "loadCatalog"
) {
  throw new Error("adapter error details were not preserved");
}

console.log("caudex persistence capability contracts passed");
