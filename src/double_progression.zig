const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const primitives = @import("primitives.zig");

pub const methodology_id = "caudex.double-progression";
pub const config_version: u32 = 1;
pub const state_schema_version: u32 = 1;

pub const RepRange = struct {
    min: u16,
    max: u16,
};

pub const AdvancementCriteria = struct {
    minimumSuccessfulSets: u16,
    minimumRepetitions: u16,
};

pub const FailureAction = enum {
    hold,
    regress,
};

pub const FailurePolicy = struct {
    onPartial: FailureAction,
    onFailure: FailureAction,
    regressionAmount: canonical.Measurement,
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

pub const ExerciseOverride = struct {
    exerciseId: []const u8,
    repRange: ?RepRange = null,
    workingSets: ?u16 = null,
    advancementCriteria: ?AdvancementCriteria = null,
    loadIncrement: ?canonical.Measurement = null,
    failurePolicy: ?FailurePolicy = null,
    rounding: ?Rounding = null,
};

/// Version 1 JSON-boundary configuration for double progression.
pub const Config = struct {
    repRange: RepRange,
    workingSets: u16,
    advancementCriteria: AdvancementCriteria,
    loadIncrement: canonical.Measurement,
    failurePolicy: FailurePolicy,
    rounding: Rounding,
    exerciseOverrides: []const ExerciseOverride = &.{},
};

pub const ExerciseState = struct {
    exerciseId: []const u8,
    load: canonical.Measurement,
    targetRepetitions: u16,
};

pub const StateData = struct {
    exercises: []const ExerciseState = &.{},
};

/// Versioned methodology state envelope returned as a proposal to the host.
pub const State = struct {
    schemaVersion: u32,
    data: StateData,
};

/// Collects every independently detectable configuration issue.
pub fn validateConfig(
    config: Config,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    try validateResolvedConfig(
        config.repRange,
        config.workingSets,
        config.advancementCriteria,
        config.loadIncrement,
        config.failurePolicy,
        config.rounding,
        "/methodology/config",
        issues,
    );

    for (config.exerciseOverrides, 0..) |override, override_index| {
        if (override.exerciseId.len == 0 or
            override.exerciseId.len > 200 or
            !std.unicode.utf8ValidateSlice(override.exerciseId))
        {
            try appendInvalid(
                issues,
                "/methodology/config/exerciseOverrides",
                "An exercise override has an invalid exercise ID.",
            );
        }
        for (config.exerciseOverrides[0..override_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, override.exerciseId)) {
                try appendInvalid(
                    issues,
                    "/methodology/config/exerciseOverrides",
                    "Exercise override IDs must be unique.",
                );
                break;
            }
        }

        try validateResolvedConfig(
            override.repRange orelse config.repRange,
            override.workingSets orelse config.workingSets,
            override.advancementCriteria orelse config.advancementCriteria,
            override.loadIncrement orelse config.loadIncrement,
            override.failurePolicy orelse config.failurePolicy,
            override.rounding orelse config.rounding,
            "/methodology/config/exerciseOverrides",
            issues,
        );
    }
}

/// Validates a decoded state against its schema version and resolved config.
pub fn validateState(
    config: Config,
    state: State,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (state.schemaVersion != state_schema_version) {
        try issues.append(.{
            .code = "methodology.state_unsupported_version",
            .path = "/methodologyState/schemaVersion",
            .message = "The double-progression state schema version is unsupported.",
            .severity = .@"error",
            .suggestion = "Provide double-progression state schema version 1.",
        });
    }
    for (state.data.exercises, 0..) |exercise, exercise_index| {
        for (state.data.exercises[0..exercise_index]) |prior| {
            if (std.mem.eql(u8, prior.exerciseId, exercise.exerciseId)) {
                try appendStateInvalid(
                    issues,
                    "Double-progression state exercise IDs must be unique.",
                );
                break;
            }
        }
        const resolved = resolvedForExercise(config, exercise.exerciseId);
        if (exercise.targetRepetitions < resolved.repRange.min or
            exercise.targetRepetitions > resolved.repRange.max)
        {
            try appendStateInvalid(
                issues,
                "A state target repetition value is outside its resolved rep range.",
            );
        }
        const load_value = primitives.Decimal.parse(exercise.load.amount) catch {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
            continue;
        };
        const load_unit = primitives.Unit.parse(exercise.load.unit) catch {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
            continue;
        };
        if (load_value.mantissa < 0 or load_unit.dimension() != .mass) {
            try appendStateInvalid(
                issues,
                "A state load must be a non-negative mass measurement.",
            );
        }
    }
}

pub const ResolvedConfig = struct {
    repRange: RepRange,
    workingSets: u16,
    advancementCriteria: AdvancementCriteria,
    loadIncrement: canonical.Measurement,
    failurePolicy: FailurePolicy,
    rounding: Rounding,
};

pub fn resolvedForExercise(config: Config, exercise_id: []const u8) ResolvedConfig {
    for (config.exerciseOverrides) |override| {
        if (!std.mem.eql(u8, override.exerciseId, exercise_id)) continue;
        return .{
            .repRange = override.repRange orelse config.repRange,
            .workingSets = override.workingSets orelse config.workingSets,
            .advancementCriteria = override.advancementCriteria orelse
                config.advancementCriteria,
            .loadIncrement = override.loadIncrement orelse config.loadIncrement,
            .failurePolicy = override.failurePolicy orelse config.failurePolicy,
            .rounding = override.rounding orelse config.rounding,
        };
    }
    return .{
        .repRange = config.repRange,
        .workingSets = config.workingSets,
        .advancementCriteria = config.advancementCriteria,
        .loadIncrement = config.loadIncrement,
        .failurePolicy = config.failurePolicy,
        .rounding = config.rounding,
    };
}

fn validateResolvedConfig(
    rep_range: RepRange,
    working_sets: u16,
    advancement: AdvancementCriteria,
    load_increment: canonical.Measurement,
    failure_policy: FailurePolicy,
    rounding: Rounding,
    path: []const u8,
    issues: *diagnostics.IssueWriter,
) diagnostics.IssueWriter.AppendError!void {
    if (rep_range.min == 0 or rep_range.min > rep_range.max) {
        try appendInvalid(issues, path, "The repetition range must be positive and ordered.");
    }
    if (working_sets == 0) {
        try appendInvalid(issues, path, "Working sets must be greater than zero.");
    }
    if (advancement.minimumSuccessfulSets == 0 or
        advancement.minimumSuccessfulSets > working_sets or
        advancement.minimumRepetitions < rep_range.min or
        advancement.minimumRepetitions > rep_range.max)
    {
        try appendInvalid(
            issues,
            path,
            "Advancement criteria must fit the configured sets and repetition range.",
        );
    }

    const increment = parsePositiveMeasurement(load_increment) catch {
        try appendInvalid(issues, path, "Load increment must be a positive mass measurement.");
        return;
    };
    const regression = parsePositiveMeasurement(failure_policy.regressionAmount) catch {
        try appendInvalid(issues, path, "Regression amount must be a positive mass measurement.");
        return;
    };
    const quantum = parsePositiveMeasurement(rounding.quantum) catch {
        try appendInvalid(issues, path, "Rounding quantum must be a positive mass measurement.");
        return;
    };
    if (increment.unit.dimension() != .mass or
        regression.unit.dimension() != .mass or
        quantum.unit.dimension() != .mass)
    {
        try appendInvalid(issues, path, "Load values must use mass units.");
    }
    if (increment.unit != regression.unit or increment.unit != quantum.unit) {
        try appendInvalid(
            issues,
            path,
            "Load increment, regression amount, and rounding quantum must use one unit.",
        );
    }
}

fn parsePositiveMeasurement(
    measurement: canonical.Measurement,
) !primitives.Measurement {
    const value = try primitives.Decimal.parse(measurement.amount);
    if (value.mantissa <= 0) return error.NonPositive;
    return .{
        .value = value,
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

fn appendInvalid(
    issues: *diagnostics.IssueWriter,
    path: []const u8,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.state_invalid",
        .path = path,
        .message = message,
        .severity = .@"error",
        .suggestion = "Correct the double-progression configuration.",
    });
}

fn appendStateInvalid(
    issues: *diagnostics.IssueWriter,
    message: []const u8,
) diagnostics.IssueWriter.AppendError!void {
    try issues.append(.{
        .code = "methodology.config_invalid",
        .path = "/methodologyState/data/exercises",
        .message = message,
        .severity = .@"error",
        .suggestion = "Rebuild the state from valid accepted methodology output.",
    });
}

fn validConfig(overrides: []const ExerciseOverride) Config {
    return .{
        .repRange = .{ .min = 8, .max = 12 },
        .workingSets = 3,
        .advancementCriteria = .{
            .minimumSuccessfulSets = 3,
            .minimumRepetitions = 12,
        },
        .loadIncrement = .{ .amount = "5", .unit = "lb" },
        .failurePolicy = .{
            .onPartial = .hold,
            .onFailure = .regress,
            .regressionAmount = .{ .amount = "5", .unit = "lb" },
        },
        .rounding = .{
            .mode = .nearest,
            .quantum = .{ .amount = "2.5", .unit = "lb" },
        },
        .exerciseOverrides = overrides,
    };
}

test "valid config and state collect no issues" {
    const overrides = [_]ExerciseOverride{.{
        .exerciseId = "squat",
        .workingSets = 4,
        .advancementCriteria = .{
            .minimumSuccessfulSets = 4,
            .minimumRepetitions = 12,
        },
    }};
    const config = validConfig(&overrides);
    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);

    const states = [_]ExerciseState{.{
        .exerciseId = "squat",
        .load = .{ .amount = "225", .unit = "lb" },
        .targetRepetitions = 10,
    }};
    try validateState(
        config,
        .{ .schemaVersion = 1, .data = .{ .exercises = &states } },
        &issues,
    );
    try std.testing.expectEqual(@as(usize, 0), issues.items().len);
}

test "config validation collects independent failures" {
    var config = validConfig(&.{});
    config.repRange = .{ .min = 12, .max = 8 };
    config.workingSets = 0;
    config.loadIncrement = .{ .amount = "0", .unit = "lb" };
    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len >= 3);
    for (issues.items()) |issue| {
        try std.testing.expectEqualStrings("methodology.config_invalid", issue.code);
    }
}

test "exercise overrides resolve deterministically and reject duplicates" {
    const overrides = [_]ExerciseOverride{
        .{ .exerciseId = "squat", .repRange = .{ .min = 5, .max = 8 } },
        .{ .exerciseId = "squat" },
    };
    const config = validConfig(&overrides);
    const resolved = resolvedForExercise(config, "squat");
    try std.testing.expectEqual(@as(u16, 5), resolved.repRange.min);

    var issue_storage: [8]canonical.ValidationIssue = undefined;
    var issues: diagnostics.IssueWriter = .init(&issue_storage);
    try validateConfig(config, &issues);
    try std.testing.expect(issues.items().len > 0);
}
