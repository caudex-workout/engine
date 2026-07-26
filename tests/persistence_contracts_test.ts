import {
  PERSISTENCE_CONTRACT_VERSION,
  PersistenceAdapterError,
  PersistenceConflictError,
  type CatalogSource,
  type CompletedWorkoutSink,
  type HistorySource,
  type MethodologyStateStore,
  type RecommendationJournal,
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

void catalog;
void history;
void states;
void journal;
void workouts;

if (PERSISTENCE_CONTRACT_VERSION !== 1) {
  throw new Error("unexpected persistence contract version");
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
