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
const recovery = @import("recovery.zig");
const volume = @import("volume.zig");

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

/// Program/session-owned interpretation of derived readiness. Required slots
/// remain required: a resulting conflict is returned by the ordinary planner
/// instead of being silently removed by this adapter.
pub const RecoveryCompositionPolicy = struct {
    prefer_ready_optional_targets: bool = true,
    minimum_preferred_readiness: u32 = 600_000,
    ready_target_weight: u16 = 1,
    reduce_session_when_systemic_below: ?u32 = null,
    maximum_exercises_when_reduced: ?u16 = null,
};

pub const VolumeConflict = struct {
    conflict: volume.CapConflict,
    policy_id: @import("primitives.zig").Id,
    policy_version: u32,
};

pub const VolumeAwareResult = union(enum) {
    composition: Result,
    volume_conflict: VolumeConflict,
    volume_policy_mismatch: struct {
        state_policy_id: @import("primitives.zig").Id,
        state_policy_version: u32,
        requested_policy_id: @import("primitives.zig").Id,
        requested_policy_version: u32,
    },

    pub fn deinit(self: *VolumeAwareResult) void {
        switch (self.*) {
            .composition => |*result| result.deinit(),
            .volume_conflict, .volume_policy_mismatch => {},
        }
        self.* = undefined;
    }
};

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

/// Applies an explicit composition policy to already-derived recovery state.
/// Recovery equations remain in `recovery`; this boundary only translates a
/// policy decision into existing typed planning priorities and constraints.
pub fn composeIntentWithRecovery(
    backing_allocator: std.mem.Allocator,
    intent: program_intent.PlannedSessionIntent,
    context: problem_builder.SessionContext,
    policy: ?hypertrophy.SessionPolicy,
    recovery_state: recovery.State,
    recovery_policy: RecoveryCompositionPolicy,
    options: planning.SolveOptions,
    history: training.HistorySnapshot,
) Error!Result {
    if (recovery_policy.minimum_preferred_readiness > recovery.readiness_units or
        recovery_policy.ready_target_weight == 0 or
        (recovery_policy.reduce_session_when_systemic_below != null and
            recovery_policy.reduce_session_when_systemic_below.? > recovery.readiness_units) or
        (recovery_policy.maximum_exercises_when_reduced == 0))
        return .{ .invalid = .{ .code = "InvalidRecoveryCompositionPolicy" } };

    const priority_storage = backing_allocator.alloc(
        hypertrophy.MusclePriority,
        context.muscle_priorities.len + recovery_state.muscles.len,
    ) catch return error.OutOfMemory;
    defer backing_allocator.free(priority_storage);
    @memcpy(priority_storage[0..context.muscle_priorities.len], context.muscle_priorities);
    var priority_count = context.muscle_priorities.len;
    if (recovery_policy.prefer_ready_optional_targets) {
        for (recovery_state.muscles) |muscle| {
            const readiness = muscle.readiness orelse continue;
            if (readiness < recovery_policy.minimum_preferred_readiness) continue;
            for (priority_storage[0..priority_count]) |existing| {
                if (existing.muscle_id.eql(muscle.muscle_id)) break;
            } else {
                priority_storage[priority_count] = .{
                    .muscle_id = muscle.muscle_id,
                    .weight = recovery_policy.ready_target_weight,
                };
                priority_count += 1;
            }
        }
    }
    var adjusted = context;
    adjusted.muscle_priorities = priority_storage[0..priority_count];
    if (recovery_policy.reduce_session_when_systemic_below) |threshold| {
        if (recovery_state.systemic.readiness) |readiness| {
            if (readiness < threshold) if (recovery_policy.maximum_exercises_when_reduced) |maximum| {
                adjusted.constraints.maximum_exercises = if (adjusted.constraints.maximum_exercises) |existing|
                    @min(existing, maximum)
                else
                    maximum;
            };
        }
    }
    return composeIntent(backing_allocator, intent, adjusted, policy, options, history);
}

/// Composes with the ordinary planner, then uses the authoritative prospective
/// volume policy to reject a plan whose direct or indirect credit would exceed
/// a configured hard cap. The conflict is structured rather than silently
/// weakening required program intent.
pub fn composeIntentWithVolume(
    backing_allocator: std.mem.Allocator,
    intent: program_intent.PlannedSessionIntent,
    context: problem_builder.SessionContext,
    policy: hypertrophy.SessionPolicy,
    options: planning.SolveOptions,
    history: training.HistorySnapshot,
    catalog: training.ExerciseCatalog,
    current_volume: volume.State,
) Error!VolumeAwareResult {
    if (!current_volume.policy_id.eql(policy.volume_policy.id) or
        current_volume.policy_version != policy.volume_policy.version)
    {
        return .{ .volume_policy_mismatch = .{
            .state_policy_id = current_volume.policy_id,
            .state_policy_version = current_volume.policy_version,
            .requested_policy_id = policy.volume_policy.id,
            .requested_policy_version = policy.volume_policy.version,
        } };
    }
    var volume_aware_context = context;
    volume_aware_context.volume_context = .{
        .state = current_volume,
        .policy = policy.volume_policy,
    };
    var composed = try composeIntent(
        backing_allocator,
        intent,
        volume_aware_context,
        policy,
        options,
        history,
    );
    errdefer composed.deinit();
    const session = switch (composed) {
        .successful, .constrained => |*value| value,
        else => return .{ .composition = composed },
    };
    const exercises = session.prescription.recommendation.exercises;
    var proposed_count: usize = 0;
    for (exercises) |exercise| proposed_count = std.math.add(usize, proposed_count, exercise.sets.len) catch
        return .{ .composition = composed };
    const proposed = backing_allocator.alloc(volume.ProposedWork, proposed_count) catch
        return error.OutOfMemory;
    defer backing_allocator.free(proposed);
    var proposed_index: usize = 0;
    for (exercises) |exercise| {
        const exercise_id = @import("primitives.zig").Id.parse(exercise.exerciseId) catch
            return .{ .composition = composed };
        for (exercise.sets) |set| {
            proposed[proposed_index] = .{
                .exercise_id = exercise_id,
                .set_count = 1,
                .kind = @import("primitives.zig").Id.parse(set.kind) catch
                    return .{ .composition = composed },
            };
            proposed_index += 1;
        }
    }
    var impact = volume.estimate(backing_allocator, catalog, proposed, policy.volume_policy) catch
        return .{ .composition = composed };
    defer impact.deinit();
    if (volume.firstCapConflict(current_volume, impact.muscles)) |conflict| {
        composed.deinit();
        return .{ .volume_conflict = .{
            .conflict = conflict,
            .policy_id = policy.volume_policy.id,
            .policy_version = policy.volume_policy.version,
        } };
    }
    return .{ .composition = composed };
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

test "volume-aware planner avoids indirect caps and prioritizes remaining targets" {
    const chest = try @import("primitives.zig").Id.parse("chest");
    const triceps = try @import("primitives.zig").Id.parse("triceps");
    const bench = training.Exercise{ .id = try .parse("bench"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary },
        .{ .muscle_id = triceps, .role = .secondary },
    } };
    const fly = training.Exercise{ .id = try .parse("fly"), .muscle_contributions = &.{
        .{ .muscle_id = chest, .role = .primary },
    } };
    const row = training.Exercise{ .id = try .parse("row"), .muscle_contributions = &.{} };
    const targets = [_]volume.Target{
        .{ .muscle_id = chest, .minimum = 3 * volume.units_per_set, .source = .{ .kind = .program_strategy, .id = try .parse("strategy") } },
        .{ .muscle_id = triceps, .hard_cap = 0, .source = .{ .kind = .program_strategy, .id = try .parse("strategy") } },
    };
    var current = try volume.calculate(std.testing.allocator, .{
        .catalog = .{ .exercises = &.{ bench, fly, row } },
        .targets = &targets,
    });
    defer current.deinit();
    const slots = [_]model.Slot{.{
        .id = try .parse("adaptive"),
        .selection = .{ .adaptive = .{} },
        .progression = testLane("lane"),
    }};
    const problem: model.PlanningProblem = .{
        .origin = testOrigin(),
        .as_of = try .parse("2026-08-10T12:00:00Z"),
        .catalog = .{ .exercises = &.{ bench, fly, row } },
        .slots = &slots,
        .objectives = &.{.{ .muscle_priority = .{ .muscle_id = chest, .weight = 2 } }},
        .volume_context = .{ .state = current.state, .policy = .firstParty() },
    };
    var workspace = try planning.Workspace.init(std.testing.allocator, problem, .{});
    defer workspace.deinit();
    const solved = try planning.solve(problem, .{}, &workspace);
    const resolved = switch (solved) {
        .resolved => |value| value,
        else => return error.TestUnexpectedResult,
    };
    try std.testing.expectEqualStrings("fly", resolved.slots[0].exercise_id.bytes);
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
