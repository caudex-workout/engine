import type { Measurement, Metric } from "./index.ts";

export type DecimalInput = string | number;
export type MassMeasurement = Measurement & { readonly unit: "lb" | "kg" };

export class CaudexMeasurementError extends RangeError {
  readonly code = "measurement.invalid" as const;
  readonly value: unknown;
  readonly unit: string;

  constructor(value: unknown, unit: string, reason: string) {
    super(`Invalid ${unit} measurement: ${reason}`);
    this.name = "CaudexMeasurementError";
    this.value = value;
    this.unit = unit;
  }
}

export function lb(value: DecimalInput): MassMeasurement {
  return measurement(value, "lb", { minimum: "0" }) as MassMeasurement;
}

export function kg(value: DecimalInput): MassMeasurement {
  return measurement(value, "kg", { minimum: "0" }) as MassMeasurement;
}

export function reps(value: number): Metric {
  return integerMetric("repetitions", value, "count", 0, 65_535);
}

export function rpe(value: DecimalInput): Metric {
  return { code: "rpe", value: measurement(value, "rpe", { minimum: "0", maximum: "10" }) };
}

export function rir(value: DecimalInput): Metric {
  return { code: "rir", value: measurement(value, "rir", { minimum: "0" }) };
}

export function seconds(value: DecimalInput): Measurement {
  return measurement(value, "s", { minimum: "0" });
}

export function minutes(value: DecimalInput): Measurement {
  return measurement(value, "min", { minimum: "0" });
}

export function load(value: MassMeasurement): Metric {
  return { code: "load", value };
}

export function metrics(input: {
  reps?: number;
  load?: MassMeasurement;
  rpe?: DecimalInput;
  rir?: DecimalInput;
  metrics?: readonly Metric[];
}): Metric[] {
  const result = input.metrics ? input.metrics.map((metric) => structuredClone(metric)) : [];
  if (input.load) result.push(load(input.load));
  if (input.reps !== undefined) result.push(reps(input.reps));
  if (input.rpe !== undefined) result.push(rpe(input.rpe));
  if (input.rir !== undefined) result.push(rir(input.rir));
  if (result.length === 0) {
    throw new CaudexMeasurementError(input, "set", "at least one result metric is required");
  }
  return result;
}

function integerMetric(
  code: string,
  value: number,
  unit: string,
  minimum: number,
  maximum: number,
): Metric {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new CaudexMeasurementError(value, unit, `expected a safe integer from ${minimum} through ${maximum}`);
  }
  return { code, value: { amount: String(value), unit } };
}

function measurement(
  value: DecimalInput,
  unit: string,
  limits: { minimum?: string; maximum?: string },
): Measurement {
  const amount = decimal(value, unit);
  if (limits.minimum !== undefined && compare(amount, limits.minimum) < 0) {
    throw new CaudexMeasurementError(value, unit, `value must be at least ${limits.minimum}`);
  }
  if (limits.maximum !== undefined && compare(amount, limits.maximum) > 0) {
    throw new CaudexMeasurementError(value, unit, `value must be at most ${limits.maximum}`);
  }
  return { amount, unit };
}

function decimal(value: DecimalInput, unit: string): string {
  if (typeof value === "number") {
    if (!Number.isFinite(value) || (Number.isInteger(value) && !Number.isSafeInteger(value))) {
      throw new CaudexMeasurementError(value, unit, "expected a finite number or exact decimal string");
    }
    const rendered = String(value);
    if (rendered.includes("e")) {
      throw new CaudexMeasurementError(value, unit, "use an exact decimal string for exponential values");
    }
    value = rendered;
  }
  if (!/^-?(0|[1-9][0-9]*)(\.[0-9]+)?$/.test(value)) {
    throw new CaudexMeasurementError(value, unit, "expected canonical decimal notation");
  }
  const [whole, fraction = ""] = value.replace("-", "").split(".");
  if (fraction.length > 18 || BigInt(whole + fraction) > 9_223_372_036_854_775_807n) {
    throw new CaudexMeasurementError(value, unit, "value exceeds the canonical exact-decimal bound");
  }
  return value === "-0" ? "0" : value;
}

function compare(left: string, right: string): number {
  const scaled = (value: string, scale: number): bigint => {
    const negative = value.startsWith("-");
    const [whole, fraction = ""] = (negative ? value.slice(1) : value).split(".");
    const magnitude = BigInt(whole + fraction.padEnd(scale, "0"));
    return negative ? -magnitude : magnitude;
  };
  const scale = Math.max(left.split(".")[1]?.length ?? 0, right.split(".")[1]?.length ?? 0);
  const a = scaled(left, scale);
  const b = scaled(right, scale);
  return a < b ? -1 : a > b ? 1 : 0;
}
