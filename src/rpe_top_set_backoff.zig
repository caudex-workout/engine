const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const primitives = @import("primitives.zig");

pub const methodology_id = "caudex.rpe-top-set-backoff";
pub const config_version: u32 = 1;
pub const state_schema_version: u32 = 1;

pub const EstimationFormula = enum {
    epley,
};

pub const BackoffCalculation = enum {
    percentage_of_top_set,
    percentage_of_estimated_one_rep_max,
};

pub const Backoff = struct {
    calculation: BackoffCalculation,
    percentage: []const u8,
    repetitions: u16,
    setCount: u16,
};

pub const RoundingMode = enum {
    nearest,
    up,
    down,
};

pub const Rounding = struct {
    mode: RoundingMode,
    quantum: canonical.Measurement,
};

pub const OvershootAction = enum {
    hold,
    decrease_estimate,
};

pub const UndershootAction = enum {
    hold,
    increase_estimate,
};

pub const ExertionPolicy = struct {
    tolerance: []const u8,
    onOvershoot: OvershootAction,
    onUndershoot: UndershootAction,
    estimateAdjustmentPercentage: []const u8,
};

/// Version 1 JSON-boundary configuration for RPE top-set/backoff.
pub const Config = struct {
    initialEstimatedOneRepMax: canonical.Measurement,
    topSetRepetitions: u16,
    targetRpe: []const u8,
    backoff: Backoff,
    rounding: Rounding,
    exertionPolicy: ExertionPolicy,
    estimationFormula: EstimationFormula,
};

pub const ExerciseState = struct {
    exerciseId: []const u8,
    estimatedOneRepMax: canonical.Measurement,
};

pub const StateData = struct {
    exercises: []const ExerciseState = &.{},
};

pub const State = struct {
    schemaVersion: u32,
    data: StateData,
};

pub fn validateConfig(
    config: Config,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    const initial = parseNonNegativeMeasurement(config.initialEstimatedOneRepMax) catch {
        try appendConfigInvalid(
            issues,
            "Initial estimated 1RM must be a non-negative mass measurement.",
        );
        return;
    };
    if (initial.unit.dimension() != .mass) {
        try appendConfigInvalid(issues, "Initial estimated 1RM must use a mass unit.");
    }
    if (config.topSetRepetitions == 0) {
        try appendConfigInvalid(issues, "Top-set repetitions must be greater than zero.");
    }
    if (!decimalInRange(config.targetRpe, "1", "10")) {
        try appendConfigInvalid(issues, "Target RPE must be an exact decimal from 1 through 10.");
    }
    if (!decimalPositiveAtMost(config.backoff.percentage, "100")) {
        try appendConfigInvalid(
            issues,
            "Backoff percentage must be greater than zero and at most 100.",
        );
    }
    if (config.backoff.repetitions == 0 or
        config.backoff.setCount == 0 or
        config.backoff.setCount > 64)
    {
        try appendConfigInvalid(
            issues,
            "Backoff repetitions must be positive and set count must be between 1 and 64.",
        );
    }
    const quantum = parsePositiveMeasurement(config.rounding.quantum) catch {
        try appendConfigInvalid(issues, "Rounding quantum must be a positive mass measurement.");
        return;
    };
    if (quantum.unit.dimension() != .mass or quantum.unit != initial.unit) {
        try appendConfigInvalid(
            issues,
            "Initial estimate and rounding quantum must use one mass unit.",
        );
    }
    if (!decimalInRange(config.exertionPolicy.tolerance, "0", "9")) {
        try appendConfigInvalid(
            issues,
            "RPE tolerance must be a non-negative exact decimal below 10.",
        );
    }
    if (!decimalPositiveAtMost(
        config.exertionPolicy.estimateAdjustmentPercentage,
        "100",
    )) {
        try appendConfigInvalid(
            issues,
            "Estimate adjustment percentage must be greater than zero and at most 100.",
        );
    }
}

pub fn validateState(
    config: Config,
    state: State,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (state.schemaVersion != state_schema_version) {
        try issues.append(.{
            .code = "methodology.state_unsupported_version",
            .path = "/methodologyState/schemaVersion",
            .message = "The RPE top-set/backoff state schema version is unsupported.",
            .severity = .@"error",
            .suggestion = "Provide RPE top-set/backoff state schema version 1.",
        });
    }
    const configured_unit = (parseNonNegativeMeasurement(
        config.initialEstimatedOneRepMax,
    ) catch return).unit;
    for (state.data.exercises, 0..) |exercise, exercise_index| {
        if (exercise.exerciseId.len == 0 or
            exercise.exerciseId.len > 200 or
            !std.unicode.utf8ValidateSlice(exercise.exerciseId))
        {
            try appendStateInvalid(issues, "A state exercise ID is invalid.");
        }
        for (state.data.exercises[0..exercise_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, exercise.exerciseId)) {
                try appendStateInvalid(issues, "State exercise IDs must be unique.");
                break;
            }
        }
        const estimate = parseNonNegativeMeasurement(exercise.estimatedOneRepMax) catch {
            try appendStateInvalid(
                issues,
                "Estimated 1RM state must be a non-negative mass measurement.",
            );
            continue;
        };
        if (estimate.unit.dimension() != .mass or estimate.unit != configured_unit) {
            try appendStateInvalid(
                issues,
                "Estimated 1RM state must use the configured mass unit.",
            );
        }
    }
}

fn parsePositiveMeasurement(measurement: canonical.Measurement) !primitives.Measurement {
    const parsed = try parseNonNegativeMeasurement(measurement);
    if (parsed.value.mantissa <= 0) return error.NonPositive;
    return parsed;
}

fn parseNonNegativeMeasurement(measurement: canonical.Measurement) !primitives.Measurement {
    const value = try primitives.Decimal.parse(measurement.amount);
    if (value.mantissa < 0) return error.Negative;
    return .{
        .value = value,
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

fn decimalInRange(text: []const u8, minimum: []const u8, maximum: []const u8) bool {
    const value = primitives.Decimal.parse(text) catch return false;
    const min = primitives.Decimal.parse(minimum) catch unreachable;
    const max = primitives.Decimal.parse(maximum) catch unreachable;
    return compareDecimal(value, min) != .lt and compareDecimal(value, max) != .gt;
}

fn decimalPositiveAtMost(text: []const u8, maximum: []const u8) bool {
    const value = primitives.Decimal.parse(text) catch return false;
    const zero = primitives.Decimal{ .mantissa = 0, .scale = 0 };
    const max = primitives.Decimal.parse(maximum) catch unreachable;
    return compareDecimal(value, zero) == .gt and compareDecimal(value, max) != .gt;
}

fn compareDecimal(left: primitives.Decimal, right: primitives.Decimal) std.math.Order {
    const scale = @max(left.scale, right.scale);
    const left_value = scaledMantissa(left, scale);
    const right_value = scaledMantissa(right, scale);
    return std.math.order(left_value, right_value);
}

fn scaledMantissa(value: primitives.Decimal, scale: u8) i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) result *= 10;
    return result;
}

fn appendConfigInvalid(
    issues: *diagnostics.IssueWriter,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.config_invalid",
        .path = "/methodology/config",
        .message = message,
        .severity = .@"error",
        .suggestion = "Correct the RPE top-set/backoff configuration.",
    });
}

fn appendStateInvalid(
    issues: *diagnostics.IssueWriter,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.state_invalid",
        .path = "/methodologyState/data/exercises",
        .message = message,
        .severity = .@"error",
        .suggestion = "Rebuild state from valid accepted methodology output.",
    });
}

pub fn writeStateJson(
    state: State,
    out: []u8,
) std.Io.Writer.Error![]const u8 {
    var writer: std.Io.Writer = .fixed(out);
    try std.json.Stringify.value(
        state,
        .{ .emit_null_optional_fields = false },
        &writer,
    );
    return writer.buffered();
}

fn validConfig() Config {
    return .{
        .initialEstimatedOneRepMax = .{ .amount = "225", .unit = "lb" },
        .topSetRepetitions = 5,
        .targetRpe = "8.0",
        .backoff = .{
            .calculation = .percentage_of_top_set,
            .percentage = "90",
            .repetitions = 8,
            .setCount = 3,
        },
        .rounding = .{
            .mode = .nearest,
            .quantum = .{ .amount = "2.5", .unit = "lb" },
        },
        .exertionPolicy = .{
            .tolerance = "0.5",
            .onOvershoot = .decrease_estimate,
            .onUndershoot = .increase_estimate,
            .estimateAdjustmentPercentage = "2.5",
        },
        .estimationFormula = .epley,
    };
}

test "valid RPE config and state collect no issues" {
    const config = validConfig();
    const states = [_]ExerciseState{.{
        .exerciseId = "barbell-bench-press",
        .estimatedOneRepMax = .{ .amount = "225", .unit = "lb" },
    }};
    var storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&storage);
    try validateConfig(config, &issues);
    try validateState(
        config,
        .{ .schemaVersion = 1, .data = .{ .exercises = &states } },
        &issues,
    );
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);
}

test "RPE config validation collects range and unit failures" {
    var config = validConfig();
    config.targetRpe = "10.5";
    config.backoff.percentage = "0";
    config.backoff.setCount = 0;
    config.rounding.quantum = .{ .amount = "2.5", .unit = "kg" };
    var storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len >= 4);
    for (issues.items()) |issue| {
        try std.testing.expectEqualStrings("methodology.config_invalid", issue.code);
    }
}
