import type {
  Measurement,
  MethodologyRef,
  ValidationIssue,
} from "./index.ts";

export type RoundingMode = "nearest" | "up" | "down";
export type FailureAction = "hold" | "regress";

export interface RepRange {
  min: number;
  max: number;
}

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

export class MethodologyConfigError extends Error {
  readonly issues: ValidationIssue[];

  constructor(issues: ValidationIssue[]) {
    super("The methodology configuration is invalid.");
    this.name = "MethodologyConfigError";
    this.issues = issues;
  }
}

export const methodologies = {
  doubleProgression(
    config: DoubleProgressionConfig,
  ): DoubleProgressionMethodology {
    const normalized = canonicalClone(config);
    const issues = validateDoubleProgression(normalized);
    if (issues.length !== 0) throw new MethodologyConfigError(issues);
    return {
      id: "caudex.double-progression",
      versionRequirement: "^0.1.0",
      configVersion: 1,
      config: normalized,
    };
  },

  rpeTopSetBackoff(
    config: RpeTopSetBackoffConfig,
  ): RpeTopSetBackoffMethodology {
    const normalized = canonicalClone(config);
    const issues = validateRpeTopSetBackoff(normalized);
    if (issues.length !== 0) throw new MethodologyConfigError(issues);
    return {
      id: "caudex.rpe-top-set-backoff",
      versionRequirement: "^0.1.0",
      configVersion: 1,
      config: normalized,
    };
  },
} as const;

function validateDoubleProgression(
  config: DoubleProgressionConfig,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  requireKnownKeys(
    config,
    [
      "repRange",
      "workingSets",
      "advancementCriteria",
      "initialLoad",
      "loadIncrement",
      "failurePolicy",
      "rounding",
      "exerciseOverrides",
    ],
    "/methodology/config",
    issues,
  );
  validateResolvedDoubleProgression(
    config.repRange,
    config.workingSets,
    config.advancementCriteria,
    config.initialLoad,
    config.loadIncrement,
    config.failurePolicy,
    config.rounding,
    "/methodology/config",
    issues,
  );

  const seen = new Set<string>();
  for (const override of config.exerciseOverrides ?? []) {
    requireKnownKeys(
      override,
      [
        "exerciseId",
        "repRange",
        "workingSets",
        "advancementCriteria",
        "initialLoad",
        "loadIncrement",
        "failurePolicy",
        "rounding",
      ],
      "/methodology/config/exerciseOverrides",
      issues,
    );
    if (
      typeof override.exerciseId !== "string" ||
      override.exerciseId.length === 0 ||
      override.exerciseId.length > 200
    ) {
      appendInvalid(
        issues,
        "/methodology/config/exerciseOverrides",
        "An exercise override has an invalid exercise ID.",
      );
    }
    if (seen.has(override.exerciseId)) {
      appendInvalid(
        issues,
        "/methodology/config/exerciseOverrides",
        "Exercise override IDs must be unique.",
      );
    }
    seen.add(override.exerciseId);
    validateResolvedDoubleProgression(
      override.repRange ?? config.repRange,
      override.workingSets ?? config.workingSets,
      override.advancementCriteria ?? config.advancementCriteria,
      override.initialLoad ?? config.initialLoad,
      override.loadIncrement ?? config.loadIncrement,
      override.failurePolicy ?? config.failurePolicy,
      override.rounding ?? config.rounding,
      "/methodology/config/exerciseOverrides",
      issues,
    );
  }
  return issues;
}

function validateResolvedDoubleProgression(
  repRange: RepRange,
  workingSets: number,
  advancement: AdvancementCriteria,
  initialLoad: Measurement,
  loadIncrement: Measurement,
  failurePolicy: FailurePolicy,
  rounding: LoadRounding,
  path: string,
  issues: ValidationIssue[],
): void {
  requireKnownKeys(repRange, ["min", "max"], path, issues);
  requireKnownKeys(
    advancement,
    ["minimumSuccessfulSets", "minimumRepetitions"],
    path,
    issues,
  );
  requireKnownKeys(initialLoad, ["amount", "unit"], path, issues);
  requireKnownKeys(loadIncrement, ["amount", "unit"], path, issues);
  requireKnownKeys(
    failurePolicy,
    ["onPartial", "onFailure", "regressionAmount"],
    path,
    issues,
  );
  requireKnownKeys(failurePolicy?.regressionAmount, ["amount", "unit"], path, issues);
  requireKnownKeys(rounding, ["mode", "quantum"], path, issues);
  requireKnownKeys(rounding?.quantum, ["amount", "unit"], path, issues);
  if (
    !isPositiveInteger(repRange?.min, 65_535) ||
    !isPositiveInteger(repRange?.max, 65_535) ||
    repRange.min > repRange.max
  ) {
    appendInvalid(issues, path, "The repetition range must be positive and ordered.");
  }
  if (!isPositiveInteger(workingSets, 64)) {
    appendInvalid(issues, path, "Working sets must be between 1 and 64.");
  }
  if (
    !isPositiveInteger(advancement?.minimumSuccessfulSets, 65_535) ||
    advancement.minimumSuccessfulSets > workingSets ||
    !isPositiveInteger(advancement?.minimumRepetitions, 65_535) ||
    advancement.minimumRepetitions < repRange.min ||
    advancement.minimumRepetitions > repRange.max
  ) {
    appendInvalid(
      issues,
      path,
      "Advancement criteria must fit the configured sets and repetition range.",
    );
  }

  const initial = parseMeasurement(initialLoad, false);
  const increment = parseMeasurement(loadIncrement, true);
  const regression = parseMeasurement(failurePolicy?.regressionAmount, true);
  const quantum = parseMeasurement(rounding?.quantum, true);
  if (!initial) appendInvalid(issues, path, "Initial load must be a non-negative mass measurement.");
  if (!increment) appendInvalid(issues, path, "Load increment must be a positive mass measurement.");
  if (!regression) appendInvalid(issues, path, "Regression amount must be a positive mass measurement.");
  if (!quantum) appendInvalid(issues, path, "Rounding quantum must be a positive mass measurement.");
  if (
    failurePolicy?.onPartial !== "hold" &&
    failurePolicy?.onPartial !== "regress"
  ) {
    appendInvalid(issues, path, "Partial-set policy must be hold or regress.");
  }
  if (
    failurePolicy?.onFailure !== "hold" &&
    failurePolicy?.onFailure !== "regress"
  ) {
    appendInvalid(issues, path, "Failure policy must be hold or regress.");
  }
  if (
    rounding?.mode !== "nearest" &&
    rounding?.mode !== "up" &&
    rounding?.mode !== "down"
  ) {
    appendInvalid(issues, path, "Rounding mode must be nearest, up, or down.");
  }
  if (!initial || !increment || !regression || !quantum) return;
  if (
    !isMassUnit(initial.unit) ||
    !isMassUnit(increment.unit) ||
    !isMassUnit(regression.unit) ||
    !isMassUnit(quantum.unit)
  ) {
    appendInvalid(issues, path, "Load values must use mass units.");
  }
  if (
    initial.unit !== increment.unit ||
    increment.unit !== regression.unit ||
    increment.unit !== quantum.unit
  ) {
    appendInvalid(
      issues,
      path,
      "Load increment, regression amount, and rounding quantum must use one unit.",
    );
  }
}

function validateRpeTopSetBackoff(
  config: RpeTopSetBackoffConfig,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];
  const path = "/methodology/config";
  requireKnownKeys(
    config,
    [
      "initialEstimatedOneRepMax",
      "topSetRepetitions",
      "targetRpe",
      "backoff",
      "rounding",
      "exertionPolicy",
      "estimationFormula",
    ],
    path,
    issues,
  );
  requireKnownKeys(
    config.initialEstimatedOneRepMax,
    ["amount", "unit"],
    path,
    issues,
  );
  requireKnownKeys(
    config.backoff,
    ["calculation", "percentage", "repetitions", "setCount"],
    path,
    issues,
  );
  requireKnownKeys(config.rounding, ["mode", "quantum"], path, issues);
  requireKnownKeys(config.rounding?.quantum, ["amount", "unit"], path, issues);
  requireKnownKeys(
    config.exertionPolicy,
    [
      "tolerance",
      "onOvershoot",
      "onUndershoot",
      "estimateAdjustmentPercentage",
    ],
    path,
    issues,
  );
  const initial = parseMeasurement(config.initialEstimatedOneRepMax, false);
  if (!initial || !isMassUnit(initial.unit)) {
    appendInvalid(
      issues,
      path,
      "Initial estimated 1RM must be a non-negative mass measurement.",
    );
  }
  if (!isPositiveInteger(config.topSetRepetitions, 65_535)) {
    appendInvalid(issues, path, "Top-set repetitions must be greater than zero.");
  }
  if (!decimalInRange(config.targetRpe, "1", "10")) {
    appendInvalid(issues, path, "Target RPE must be an exact decimal from 1 through 10.");
  }
  if (!decimalPositiveAtMost(config.backoff?.percentage, "100")) {
    appendInvalid(
      issues,
      path,
      "Backoff percentage must be greater than zero and at most 100.",
    );
  }
  if (
    config.backoff?.calculation !== "percentage_of_top_set" &&
    config.backoff?.calculation !== "percentage_of_estimated_one_rep_max"
  ) {
    appendInvalid(issues, path, "Backoff calculation is unsupported.");
  }
  if (
    !isPositiveInteger(config.backoff?.repetitions, 65_535) ||
    !isPositiveInteger(config.backoff?.setCount, 64)
  ) {
    appendInvalid(
      issues,
      path,
      "Backoff repetitions must be positive and set count must be between 1 and 64.",
    );
  }
  const quantum = parseMeasurement(config.rounding?.quantum, true);
  if (!quantum || !isMassUnit(quantum.unit)) {
    appendInvalid(issues, path, "Rounding quantum must be a positive mass measurement.");
  } else if (initial && quantum.unit !== initial.unit) {
    appendInvalid(
      issues,
      path,
      "Initial estimate and rounding quantum must use one mass unit.",
    );
  }
  if (
    config.rounding?.mode !== "nearest" &&
    config.rounding?.mode !== "up" &&
    config.rounding?.mode !== "down"
  ) {
    appendInvalid(issues, path, "Rounding mode must be nearest, up, or down.");
  }
  if (!decimalInRange(config.exertionPolicy?.tolerance, "0", "9")) {
    appendInvalid(
      issues,
      path,
      "RPE tolerance must be a non-negative exact decimal below 10.",
    );
  }
  if (
    !decimalPositiveAtMost(
      config.exertionPolicy?.estimateAdjustmentPercentage,
      "100",
    )
  ) {
    appendInvalid(
      issues,
      path,
      "Estimate adjustment percentage must be greater than zero and at most 100.",
    );
  }
  if (
    config.exertionPolicy?.onOvershoot !== "hold" &&
    config.exertionPolicy?.onOvershoot !== "decrease_estimate"
  ) {
    appendInvalid(issues, path, "Overshoot policy is unsupported.");
  }
  if (
    config.exertionPolicy?.onUndershoot !== "hold" &&
    config.exertionPolicy?.onUndershoot !== "increase_estimate"
  ) {
    appendInvalid(issues, path, "Undershoot policy is unsupported.");
  }
  if (config.estimationFormula !== "epley") {
    appendInvalid(issues, path, "Estimation formula is unsupported.");
  }
  return issues;
}

function appendInvalid(
  issues: ValidationIssue[],
  path: string,
  message: string,
): void {
  issues.push({
    code: "methodology.config_invalid",
    path,
    message,
    severity: "error",
    suggestion: "Correct the methodology configuration.",
  });
}

function requireKnownKeys(
  value: unknown,
  allowed: string[],
  path: string,
  issues: ValidationIssue[],
): void {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return;
  const allowedSet = new Set(allowed);
  if (Object.keys(value).some((key) => !allowedSet.has(key))) {
    appendInvalid(issues, path, "The configuration contains an unknown field.");
  }
}

function canonicalClone<T>(value: T): T {
  try {
    const encoded = JSON.stringify(value);
    if (encoded === undefined) throw new Error("not JSON serializable");
    return JSON.parse(encoded) as T;
  } catch {
    throw new MethodologyConfigError([
      {
        code: "methodology.config_invalid",
        path: "/methodology/config",
        message: "The configuration must be an ordinary JSON value.",
        severity: "error",
        suggestion: "Remove cycles and non-JSON values from the configuration.",
      },
    ]);
  }
}

interface ParsedMeasurement {
  amount: DecimalParts;
  unit: string;
}

function parseMeasurement(
  measurement: Measurement | undefined,
  positive: boolean,
): ParsedMeasurement | undefined {
  if (!measurement || typeof measurement.unit !== "string") return undefined;
  const amount = parseDecimal(measurement.amount);
  if (!amount || amount.negative || (positive && amount.magnitude === 0n)) {
    return undefined;
  }
  return { amount, unit: measurement.unit };
}

interface DecimalParts {
  negative: boolean;
  magnitude: bigint;
  scale: number;
}

function parseDecimal(value: unknown): DecimalParts | undefined {
  if (
    typeof value !== "string" ||
    !/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(value)
  ) {
    return undefined;
  }
  const negative = value.startsWith("-");
  const unsigned = negative ? value.slice(1) : value;
  const [whole, fraction = ""] = unsigned.split(".");
  if (fraction.length > 18) return undefined;
  const magnitude = BigInt(whole + fraction);
  const limit = negative ? 9_223_372_036_854_775_808n : 9_223_372_036_854_775_807n;
  if (magnitude > limit) return undefined;
  return { negative: negative && magnitude !== 0n, magnitude, scale: fraction.length };
}

function decimalInRange(value: unknown, minimum: string, maximum: string): boolean {
  const parsed = parseDecimal(value);
  const min = parseDecimal(minimum);
  const max = parseDecimal(maximum);
  return Boolean(
    parsed &&
      min &&
      max &&
      compareDecimal(parsed, min) >= 0 &&
      compareDecimal(parsed, max) <= 0,
  );
}

function decimalPositiveAtMost(value: unknown, maximum: string): boolean {
  const parsed = parseDecimal(value);
  const max = parseDecimal(maximum);
  return Boolean(
    parsed &&
      max &&
      !parsed.negative &&
      parsed.magnitude !== 0n &&
      compareDecimal(parsed, max) <= 0,
  );
}

function compareDecimal(left: DecimalParts, right: DecimalParts): number {
  const scale = Math.max(left.scale, right.scale);
  const leftValue =
    (left.negative ? -left.magnitude : left.magnitude) *
    10n ** BigInt(scale - left.scale);
  const rightValue =
    (right.negative ? -right.magnitude : right.magnitude) *
    10n ** BigInt(scale - right.scale);
  return leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : 0;
}

function isPositiveInteger(value: unknown, maximum: number): value is number {
  return Number.isInteger(value) && Number(value) >= 1 && Number(value) <= maximum;
}

function isMassUnit(unit: string): boolean {
  return unit === "g" || unit === "kg" || unit === "lb";
}
