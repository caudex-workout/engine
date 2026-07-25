const std = @import("std");
const canonical = @import("canonical.zig");
const primitives = @import("primitives.zig");

pub const Assumptions = struct {
    set_seconds: u64,
    rest_between_sets_seconds: u64,
    setup_per_exercise_seconds: u64,
    transition_between_exercises_seconds: u64,
};

pub const MethodologyOverride = struct {
    /// Replaces active-set and between-set rest time for one exercise.
    active_and_rest_seconds: u64,
    rule_id: primitives.Id,
};

pub const ExerciseWork = struct {
    exercise_id: primitives.Id,
    set_count: u16,
    required: bool = false,
    methodology_override: ?MethodologyOverride = null,
};

pub const Component = enum {
    active_sets,
    rest_between_sets,
    setup,
    transition,
    methodology_override,
};

/// A typed, structured explanation of one duration component.
pub const Explanation = struct {
    code: []const u8,
    component: Component,
    seconds_per_occurrence: u64,
    occurrences: u64,
    total_seconds: u64,
    subject_exercise_id: ?[]const u8 = null,
    methodology_rule_id: ?[]const u8 = null,
};

pub const Result = struct {
    estimated_duration: primitives.Measurement,
    required_work_duration: primitives.Measurement,
    explanations: []const Explanation,
    budget_issue: ?canonical.ValidationIssue,
};

pub const EstimateError = error{
    InvalidWork,
    OutputLimitReached,
    Overflow,
};

const ComponentTotals = struct {
    set_occurrences: u64 = 0,
    set_seconds: u64 = 0,
    rest_occurrences: u64 = 0,
    rest_seconds: u64 = 0,
    setup_occurrences: u64 = 0,
    setup_seconds: u64 = 0,
    transition_occurrences: u64 = 0,
    transition_seconds: u64 = 0,
    override_seconds: u64 = 0,

    fn total(self: ComponentTotals) EstimateError!u64 {
        var result: u64 = 0;
        inline for (.{
            self.set_seconds,
            self.rest_seconds,
            self.setup_seconds,
            self.transition_seconds,
            self.override_seconds,
        }) |component| {
            result = checkedAdd(result, component) catch return error.Overflow;
        }
        return result;
    }
};

/// Estimates a session without adding, removing, or mutating prescribed work.
///
/// `available_seconds` is an explicit host budget. If required work exceeds it,
/// the unchanged estimate is returned with an actionable canonical issue.
pub fn estimateSession(
    work: []const ExerciseWork,
    assumptions: Assumptions,
    available_seconds: ?u64,
    explanation_storage: []Explanation,
) EstimateError!Result {
    const totals = try calculateTotals(work, assumptions, false);
    const required_totals = try calculateTotals(work, assumptions, true);
    const total_seconds = try totals.total();
    const required_seconds = try required_totals.total();
    if (total_seconds > std.math.maxInt(i64) or
        required_seconds > std.math.maxInt(i64))
    {
        return error.Overflow;
    }

    var explanation_len: usize = 0;
    try appendExplanation(explanation_storage, &explanation_len, .{
        .code = "session.duration.assumption.active_sets",
        .component = .active_sets,
        .seconds_per_occurrence = assumptions.set_seconds,
        .occurrences = totals.set_occurrences,
        .total_seconds = totals.set_seconds,
    });
    try appendExplanation(explanation_storage, &explanation_len, .{
        .code = "session.duration.assumption.rest_between_sets",
        .component = .rest_between_sets,
        .seconds_per_occurrence = assumptions.rest_between_sets_seconds,
        .occurrences = totals.rest_occurrences,
        .total_seconds = totals.rest_seconds,
    });
    try appendExplanation(explanation_storage, &explanation_len, .{
        .code = "session.duration.assumption.setup",
        .component = .setup,
        .seconds_per_occurrence = assumptions.setup_per_exercise_seconds,
        .occurrences = totals.setup_occurrences,
        .total_seconds = totals.setup_seconds,
    });
    try appendExplanation(explanation_storage, &explanation_len, .{
        .code = "session.duration.assumption.transition",
        .component = .transition,
        .seconds_per_occurrence = assumptions.transition_between_exercises_seconds,
        .occurrences = totals.transition_occurrences,
        .total_seconds = totals.transition_seconds,
    });
    for (work) |exercise| {
        if (exercise.methodology_override) |override| {
            try appendExplanation(explanation_storage, &explanation_len, .{
                .code = "session.duration.methodology_override",
                .component = .methodology_override,
                .seconds_per_occurrence = override.active_and_rest_seconds,
                .occurrences = 1,
                .total_seconds = override.active_and_rest_seconds,
                .subject_exercise_id = exercise.exercise_id.bytes,
                .methodology_rule_id = override.rule_id.bytes,
            });
        }
    }

    const issue: ?canonical.ValidationIssue = if (available_seconds) |available|
        if (required_seconds > available)
            .{
                .code = "session.time_budget_unsatisfied",
                .path = "/session/availableMinutes",
                .message = "Required work cannot fit the explicit time budget.",
                .severity = .@"error",
                .suggestion = "Increase the time budget or explicitly revise required work.",
            }
        else
            null
    else
        null;

    return .{
        .estimated_duration = secondsMeasurement(@intCast(total_seconds)),
        .required_work_duration = secondsMeasurement(@intCast(required_seconds)),
        .explanations = explanation_storage[0..explanation_len],
        .budget_issue = issue,
    };
}

fn calculateTotals(
    work: []const ExerciseWork,
    assumptions: Assumptions,
    required_only: bool,
) EstimateError!ComponentTotals {
    var totals = ComponentTotals{};
    var included_exercises: u64 = 0;
    for (work) |exercise| {
        if (exercise.set_count == 0) return error.InvalidWork;
        if (required_only and !exercise.required) continue;
        included_exercises = try checkedAdd(included_exercises, 1);
        totals.setup_occurrences = try checkedAdd(totals.setup_occurrences, 1);
        totals.setup_seconds = try checkedAdd(
            totals.setup_seconds,
            try checkedMultiply(assumptions.setup_per_exercise_seconds, 1),
        );

        if (exercise.methodology_override) |override| {
            totals.override_seconds = try checkedAdd(
                totals.override_seconds,
                override.active_and_rest_seconds,
            );
        } else {
            const set_count: u64 = exercise.set_count;
            const rest_count = set_count - 1;
            totals.set_occurrences = try checkedAdd(totals.set_occurrences, set_count);
            totals.set_seconds = try checkedAdd(
                totals.set_seconds,
                try checkedMultiply(assumptions.set_seconds, set_count),
            );
            totals.rest_occurrences = try checkedAdd(totals.rest_occurrences, rest_count);
            totals.rest_seconds = try checkedAdd(
                totals.rest_seconds,
                try checkedMultiply(
                    assumptions.rest_between_sets_seconds,
                    rest_count,
                ),
            );
        }
    }
    totals.transition_occurrences = if (included_exercises == 0)
        0
    else
        included_exercises - 1;
    totals.transition_seconds = try checkedMultiply(
        assumptions.transition_between_exercises_seconds,
        totals.transition_occurrences,
    );
    return totals;
}

fn appendExplanation(
    storage: []Explanation,
    len: *usize,
    explanation: Explanation,
) EstimateError!void {
    if (len.* == storage.len) return error.OutputLimitReached;
    storage[len.*] = explanation;
    len.* += 1;
}

fn checkedAdd(left: u64, right: u64) EstimateError!u64 {
    const result, const overflow = @addWithOverflow(left, right);
    if (overflow != 0) return error.Overflow;
    return result;
}

fn checkedMultiply(left: u64, right: u64) EstimateError!u64 {
    const result, const overflow = @mulWithOverflow(left, right);
    if (overflow != 0) return error.Overflow;
    return result;
}

fn secondsMeasurement(seconds: i64) primitives.Measurement {
    return .{
        .value = .{ .mantissa = seconds, .scale = 0 },
        .unit = .s,
    };
}

const test_assumptions = Assumptions{
    .set_seconds = 30,
    .rest_between_sets_seconds = 90,
    .setup_per_exercise_seconds = 60,
    .transition_between_exercises_seconds = 45,
};

test "explicit assumptions produce exact component totals" {
    const work = [_]ExerciseWork{
        .{ .exercise_id = try .parse("squat"), .set_count = 3, .required = true },
        .{ .exercise_id = try .parse("row"), .set_count = 2 },
    };
    var explanations: [4]Explanation = undefined;
    const result = try estimateSession(&work, test_assumptions, null, &explanations);

    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 585, .scale = 0 },
        result.estimated_duration.value,
    );
    try std.testing.expectEqual(@as(usize, 4), result.explanations.len);
    try std.testing.expectEqual(@as(u64, 150), result.explanations[0].total_seconds);
    try std.testing.expectEqual(@as(u64, 270), result.explanations[1].total_seconds);
    try std.testing.expectEqual(@as(u64, 120), result.explanations[2].total_seconds);
    try std.testing.expectEqual(@as(u64, 45), result.explanations[3].total_seconds);
}

test "methodology override replaces active and rest estimate" {
    const work = [_]ExerciseWork{
        .{
            .exercise_id = try .parse("squat"),
            .set_count = 3,
            .methodology_override = .{
                .active_and_rest_seconds = 200,
                .rule_id = try .parse("method.duration.squat"),
            },
        },
    };
    var explanations: [5]Explanation = undefined;
    const result = try estimateSession(&work, test_assumptions, null, &explanations);

    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 260, .scale = 0 },
        result.estimated_duration.value,
    );
    const override = result.explanations[4];
    try std.testing.expectEqual(.methodology_override, override.component);
    try std.testing.expectEqualStrings(
        "method.duration.squat",
        override.methodology_rule_id.?,
    );
}

test "time budget reports required work without removing it" {
    const work = [_]ExerciseWork{
        .{ .exercise_id = try .parse("required"), .set_count = 3, .required = true },
        .{ .exercise_id = try .parse("optional"), .set_count = 2 },
    };
    var explanations: [4]Explanation = undefined;
    const result = try estimateSession(&work, test_assumptions, 300, &explanations);

    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 330, .scale = 0 },
        result.required_work_duration.value,
    );
    try std.testing.expectEqual(
        primitives.Decimal{ .mantissa = 585, .scale = 0 },
        result.estimated_duration.value,
    );
    try std.testing.expectEqualStrings(
        "session.time_budget_unsatisfied",
        result.budget_issue.?.code,
    );
    try std.testing.expect(result.budget_issue.?.suggestion != null);
}

test "invalid work storage limits and arithmetic overflow are explicit" {
    const empty_work = [_]ExerciseWork{
        .{ .exercise_id = try .parse("invalid"), .set_count = 0 },
    };
    var explanations: [4]Explanation = undefined;
    try std.testing.expectError(
        error.InvalidWork,
        estimateSession(&empty_work, test_assumptions, null, &explanations),
    );

    const valid_work = [_]ExerciseWork{
        .{ .exercise_id = try .parse("valid"), .set_count = 1 },
    };
    try std.testing.expectError(
        error.OutputLimitReached,
        estimateSession(&valid_work, test_assumptions, null, explanations[0..3]),
    );
    try std.testing.expectError(
        error.Overflow,
        estimateSession(
            &valid_work,
            .{
                .set_seconds = std.math.maxInt(u64),
                .rest_between_sets_seconds = 0,
                .setup_per_exercise_seconds = 1,
                .transition_between_exercises_seconds = 0,
            },
            null,
            &explanations,
        ),
    );
}
