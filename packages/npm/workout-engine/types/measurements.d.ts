import type { Measurement, Metric } from "./index.js";
export type DecimalInput = string | number;
export type MassMeasurement = Measurement & { readonly unit: "lb" | "kg" };
export declare class CaudexMeasurementError extends RangeError {
  readonly code: "measurement.invalid";
  readonly value: unknown;
  readonly unit: string;
}
export declare function lb(value: DecimalInput): MassMeasurement;
export declare function kg(value: DecimalInput): MassMeasurement;
export declare function reps(value: number): Metric;
export declare function rpe(value: DecimalInput): Metric;
export declare function rir(value: DecimalInput): Metric;
export declare function seconds(value: DecimalInput): Measurement;
export declare function minutes(value: DecimalInput): Measurement;
export declare function load(value: MassMeasurement): Metric;
export declare function metrics(input: { reps?: number; load?: MassMeasurement; rpe?: DecimalInput; rir?: DecimalInput; metrics?: readonly Metric[] }): Metric[];
