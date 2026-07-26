import type {
  Measurement,
  MethodologyRef,
  ValidationIssue,
} from "./index.js";

export type RoundingMode = "nearest" | "up" | "down";
export type FailureAction = "hold" | "regress";
export interface RepRange { min: number; max: number }
export interface AdvancementCriteria {
  minimumSuccessfulSets: number;
  minimumRepetitions: number;
}
export interface FailurePolicy {
  onPartial: FailureAction;
  onFailure: FailureAction;
  regressionAmount: Measurement;
}
export interface LoadRounding {
  mode: RoundingMode;
  quantum: Measurement;
}
export interface DoubleProgressionExerciseOverride {
  exerciseId: string;
  repRange?: RepRange;
  workingSets?: number;
  advancementCriteria?: AdvancementCriteria;
  initialLoad?: Measurement;
  loadIncrement?: Measurement;
  failurePolicy?: FailurePolicy;
  rounding?: LoadRounding;
}
export interface DoubleProgressionConfig {
  repRange: RepRange;
  workingSets: number;
  advancementCriteria: AdvancementCriteria;
  initialLoad: Measurement;
  loadIncrement: Measurement;
  failurePolicy: FailurePolicy;
  rounding: LoadRounding;
  exerciseOverrides?: DoubleProgressionExerciseOverride[];
}
export interface DoubleProgressionMethodology
  extends MethodologyRef<DoubleProgressionConfig> {
  id: "caudex.double-progression";
  versionRequirement: "^0.1.0";
  configVersion: 1;
}
export type BackoffCalculation =
  | "percentage_of_top_set"
  | "percentage_of_estimated_one_rep_max";
export interface RpeTopSetBackoffConfig {
  initialEstimatedOneRepMax: Measurement;
  topSetRepetitions: number;
  targetRpe: string;
  backoff: {
    calculation: BackoffCalculation;
    percentage: string;
    repetitions: number;
    setCount: number;
  };
  rounding: LoadRounding;
  exertionPolicy: {
    tolerance: string;
    onOvershoot: "hold" | "decrease_estimate";
    onUndershoot: "hold" | "increase_estimate";
    estimateAdjustmentPercentage: string;
  };
  estimationFormula: "epley";
}
export interface RpeTopSetBackoffMethodology
  extends MethodologyRef<RpeTopSetBackoffConfig> {
  id: "caudex.rpe-top-set-backoff";
  versionRequirement: "^0.1.0";
  configVersion: 1;
}
export declare class MethodologyConfigError extends Error {
  readonly issues: ValidationIssue[];
  constructor(issues: ValidationIssue[]);
}
export declare const methodologies: {
  readonly doubleProgression: (
    config: DoubleProgressionConfig,
  ) => DoubleProgressionMethodology;
  readonly rpeTopSetBackoff: (
    config: RpeTopSetBackoffConfig,
  ) => RpeTopSetBackoffMethodology;
};
