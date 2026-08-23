//! First-class whole-session composition.
//!
//! Composition intentionally delegates exercise selection to `planning` and
//! exercise prescriptions to `programming`.  It owns the returned structural
//! plan and progression recommendation, while preserving the program intent
//! and planner provenance supplied by the caller.

const std = @import("std");
const planning = @import("planning/root.zig");
const model = @import("planning/problem.zig");
const programming = @import("programming.zig");
const problem_builder = @import("planning/build.zig");
const program_intent = @import("programs/intent.zig");
const hypertrophy = @import("programs/hypertrophy.zig");
const training = @import("training.zig");
const double_progression = @import("double_progression.zig");
const rpe = @import("rpe_top_set_backoff.zig");

pub const InvalidInput = struct {
    code: []const u8,
};

pub const OwnedSession = struct {
    arena: std.heap.ArenaAllocator,
    plan: model.ResolvedSessionPlan,
    prescription: programming.OwnedRecommendation,

    pub fn deinit(self: *OwnedSession) void {
        self.prescription.deinit();
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const OwnedUnsatisfiable = struct {
    arena: std.heap.ArenaAllocator,
    failure: model.InfeasiblePlan,

    pub fn deinit(self: *OwnedUnsatisfiable) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const OwnedSearchExhausted = struct {
    arena: std.heap.ArenaAllocator,
    failure: model.SearchExhausted,

    pub fn deinit(self: *OwnedSearchExhausted) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// `constrained` means a valid session was retained but optional intent was
/// omitted. `unsatisfiable` and `search_exhausted` retain the planner's
/// structured evidence so hosts can explain or retry the request.
pub const Result = union(enum) {
    successful: OwnedSession,
    constrained: OwnedSession,
    unsatisfiable: OwnedUnsatisfiable,
    invalid: InvalidInput,
    search_exhausted: OwnedSearchExhausted,

    pub fn deinit(self: *Result) void {
        switch (self.*) {
            .successful, .constrained => |*session| session.deinit(),
            .unsatisfiable => |*failure| failure.deinit(),
            .search_exhausted => |*failure| failure.deinit(),
            .invalid => {},
        }
        self.* = undefined;
    }
};

pub const Error = error{OutOfMemory};

pub fn compose(
    backing_allocator: std.mem.Allocator,
    problem: model.PlanningProblem,
    options: planning.SolveOptions,
    workspace: *planning.Workspace,
    history: training.HistorySnapshot,
) Error!Result {
    const planned = programming.recommendPlannedSession(
        backing_allocator,
        problem,
        options,
        workspace,
        history,
    ) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .invalid = .{ .code = @errorName(err) } },
    };

    return switch (planned) {
        .infeasible => |failure| .{ .unsatisfiable = try ownInfeasible(backing_allocator, failure) },
        .search_exhausted => |failure| .{ .search_exhausted = try ownSearchExhausted(backing_allocator, failure) },
        .resolved => |resolved| {
            const owned = try ownPlan(backing_allocator, resolved.plan, resolved.prescription);
            const constrained = owned.plan.workload.omitted_optional_slot_count != 0;
            return if (constrained) .{ .constrained = owned } else .{ .successful = owned };
        },
    };
}

/// Convenience boundary from immutable program intent and today's temporary
/// context. The intent remains unchanged; only the returned plan records any
/// optional work omitted for this composition.
pub fn composeIntent(
    backing_allocator: std.mem.Allocator,
    intent: program_intent.PlannedSessionIntent,
    context: problem_builder.SessionContext,
    policy: ?hypertrophy.SessionPolicy,
    options: planning.SolveOptions,
    history: training.HistorySnapshot,
) Error!Result {
    const objectives = backing_allocator.alloc(model.Objective, planning.solver.max_objectives) catch
        return error.OutOfMemory;
    defer backing_allocator.free(objectives);
    const durations = backing_allocator.alloc(
        model.DurationEstimate,
        planning.solver.max_duration_estimates,
    ) catch return error.OutOfMemory;
    defer backing_allocator.free(durations);
    const problem = problem_builder.build(intent, context, policy, .{
        .objectives = objectives,
        .duration_estimates = durations,
    }) catch |err| return .{ .invalid = .{ .code = @errorName(err) } };
    var workspace = planning.Workspace.init(backing_allocator, problem, options) catch |err| {
        return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => .{ .invalid = .{ .code = @errorName(err) } },
        };
    };
    defer workspace.deinit();
    return compose(backing_allocator, problem, options, &workspace, history);
}

fn ownInfeasible(
    backing_allocator: std.mem.Allocator,
    source: model.InfeasiblePlan,
) Error!OwnedUnsatisfiable {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    var failure = source;
    failure.problem_fingerprint = allocator.dupe(u8, source.problem_fingerprint) catch
        return error.OutOfMemory;
    failure.violations = allocator.dupe(model.InfeasibilityViolation, source.violations) catch
        return error.OutOfMemory;
    return .{ .arena = arena, .failure = failure };
}

fn ownSearchExhausted(
    backing_allocator: std.mem.Allocator,
    source: model.SearchExhausted,
) Error!OwnedSearchExhausted {
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    var failure = source;
    failure.problem_fingerprint = arena.allocator().dupe(u8, source.problem_fingerprint) catch
        return error.OutOfMemory;
    return .{ .arena = arena, .failure = failure };
}

fn ownPlan(
    backing_allocator: std.mem.Allocator,
    source: model.ResolvedSessionPlan,
    prescription: programming.OwnedRecommendation,
) Error!OwnedSession {
    var owned_prescription = prescription;
    errdefer owned_prescription.deinit();
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const slots = allocator.alloc(model.ResolvedSlot, source.slots.len) catch return error.OutOfMemory;
    const omitted = allocator.alloc(model.OmittedSlot, source.omitted_slots.len) catch return error.OutOfMemory;
    const reasons = allocator.alloc(model.DecisionReason, source.reasons.len) catch return error.OutOfMemory;
    for (source.reasons, reasons) |reason, *copy| copy.* = reason;
    for (source.slots, slots) |slot, *copy| {
        copy.* = slot;
        copy.reason_refs = allocator.dupe(u16, slot.reason_refs) catch return error.OutOfMemory;
        copy.alternatives = allocator.dupe(model.CandidateAlternative, slot.alternatives) catch return error.OutOfMemory;
    }
    for (source.omitted_slots, omitted) |item, *copy| {
        copy.* = item;
        copy.reason_refs = allocator.dupe(u16, item.reason_refs) catch return error.OutOfMemory;
    }
    const owned_plan = source;
    var plan = owned_plan;
    plan.slots = slots;
    plan.omitted_slots = omitted;
    plan.reasons = reasons;
    plan.problem_fingerprint = allocator.dupe(u8, source.problem_fingerprint) catch return error.OutOfMemory;
    return .{ .arena = arena, .plan = plan, .prescription = owned_prescription };
}

test "composer preserves mixed progression and returns a complete session" {
    const first = training.Exercise{ .id = try .parse("press") };
    const second = training.Exercise{ .id = try .parse("row") };
    const slots = [_]model.Slot{
        .{ .id = try .parse("press-slot"), .selection = .{ .fixed = first.id }, .progression = .{ .state_id = try .parse("press-lane"), .method = .{ .double_progression = .{ .config = testDoubleConfig() } } } },
        .{ .id = try .parse("row-slot"), .selection = .{ .fixed = second.id }, .progression = .{ .state_id = try .parse("row-lane"), .method = .{ .rpe_top_set_backoff = .{ .config = testRpeConfig() } } } },
    };
    const problem: model.PlanningProblem = .{ .origin = testOrigin(), .as_of = try .parse("2026-08-10T12:00:00Z"), .catalog = .{ .exercises = &.{ first, second } }, .slots = &slots };
    var workspace = try planning.Workspace.init(std.testing.allocator, problem, .{});
    defer workspace.deinit();
    var result = try compose(std.testing.allocator, problem, .{}, &workspace, .{});
    switch (result) {
        .successful => |*session| {
            defer session.deinit();
            try std.testing.expectEqual(@as(usize, 2), session.plan.slots.len);
            try std.testing.expectEqual(@as(usize, 2), session.prescription.recommendation.exercises.len);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "composer constrains optional work without rewriting requested workload" {
    const main = training.Exercise{ .id = try .parse("main") };
    const accessory = training.Exercise{ .id = try .parse("accessory") };
    const slots = [_]model.Slot{
        .{ .id = try .parse("main-slot"), .selection = .{ .fixed = main.id }, .progression = testLane("main-lane") },
        .{ .id = try .parse("accessory-slot"), .presence = .optional, .selection = .{ .fixed = accessory.id }, .progression = testLane("accessory-lane") },
    };
    const durations = [_]model.DurationEstimate{
        .{ .slot_id = slots[0].id, .exercise_id = main.id, .minutes = 20 },
        .{ .slot_id = slots[1].id, .exercise_id = accessory.id, .minutes = 15 },
    };
    const problem: model.PlanningProblem = .{
        .origin = testOrigin(),
        .as_of = try .parse("2026-08-10T12:00:00Z"),
        .catalog = .{ .exercises = &.{ main, accessory } },
        .slots = &slots,
        .constraints = .{ .hard_maximum_minutes = 20 },
        .duration_estimates = &durations,
    };
    var workspace = try planning.Workspace.init(std.testing.allocator, problem, .{});
    defer workspace.deinit();
    var result = try compose(std.testing.allocator, problem, .{}, &workspace, .{});
    defer result.deinit();
    const session = switch (result) {
        .constrained => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqual(@as(u8, 2), session.plan.workload.target_slot_count);
    try std.testing.expectEqual(@as(u8, 1), session.plan.workload.composed_slot_count);
    try std.testing.expectEqualStrings("accessory-slot", session.plan.omitted_slots[0].slot_id.bytes);
}

test "composer reports an unavailable required exercise as unsatisfiable" {
    const available = training.Exercise{ .id = try .parse("available") };
    const slots = [_]model.Slot{.{
        .id = try .parse("required-slot"),
        .selection = .{ .fixed = try .parse("required-unavailable") },
        .progression = testLane("required-lane"),
    }};
    const problem: model.PlanningProblem = .{
        .origin = testOrigin(),
        .as_of = try .parse("2026-08-10T12:00:00Z"),
        .catalog = .{ .exercises = &.{available} },
        .slots = &slots,
    };
    var workspace = try planning.Workspace.init(std.testing.allocator, problem, .{});
    defer workspace.deinit();
    var result = try compose(std.testing.allocator, problem, .{}, &workspace, .{});
    defer result.deinit();
    const failure = switch (result) {
        .unsatisfiable => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expect(failure.failure.violations[0] == .required_slot_has_no_eligible_candidate);
}

fn testLane(state_id: []const u8) @import("progression/root.zig").Lane {
    return .{
        .state_id = .{ .bytes = state_id },
        .method = .{ .double_progression = .{ .config = testDoubleConfig() } },
    };
}

fn testDoubleConfig() double_progression.Config {
    return .{ .repRange = .{ .min = 8, .max = 12 }, .workingSets = 1, .advancementCriteria = .{ .minimumSuccessfulSets = 1, .minimumRepetitions = 12 }, .initialLoad = .{ .amount = "45", .unit = "lb" }, .loadIncrement = .{ .amount = "5", .unit = "lb" }, .failurePolicy = .{ .onPartial = .hold, .onFailure = .regress, .regressionAmount = .{ .amount = "5", .unit = "lb" } }, .rounding = .{ .mode = .nearest, .quantum = .{ .amount = "2.5", .unit = "lb" } } };
}

fn testRpeConfig() rpe.Config {
    return .{ .initialEstimatedOneRepMax = .{ .amount = "225", .unit = "lb" }, .topSetRepetitions = 5, .targetRpe = "8.0", .backoff = .{ .calculation = .percentage_of_top_set, .percentage = "90", .repetitions = 8, .setCount = 1 }, .rounding = .{ .mode = .nearest, .quantum = .{ .amount = "2.5", .unit = "lb" } }, .exertionPolicy = .{ .tolerance = "0.5", .onOvershoot = .decrease_estimate, .onUndershoot = .increase_estimate, .estimateAdjustmentPercentage = "2.5" }, .estimationFormula = .epley };
}

fn testOrigin() model.Origin {
    return .{ .definition_id = .{ .bytes = "program" }, .definition_version = 1, .definition_fingerprint = "fingerprint", .instance_id = .{ .bytes = "instance" }, .occurrence_id = .{ .bytes = "occurrence" }, .block_id = .{ .bytes = "block" }, .role_id = .{ .bytes = "role" }, .planning_state_revision = 1, .strategy = .fixed };
}
