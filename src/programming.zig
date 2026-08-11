//! Deterministic program/session composition above exercise progression.
//!
//! `fixed_session` is intentionally small: the host supplies stable ordered
//! slots and this module dispatches each slot to its assigned progression
//! method. Program state and progression state are separate values. A
//! progression `state_id` identifies a program slot/lane, not an exercise;
//! therefore one exercise may safely appear in multiple slots or blocks.

const std = @import("std");
const canonical = @import("canonical.zig");
const double_progression = @import("double_progression.zig");
const exercise_knowledge = @import("exercise_knowledge.zig");
const primitives = @import("primitives.zig");
const rpe = @import("rpe_top_set_backoff.zig");
const training = @import("training.zig");

pub const fixed_session_id = "caudex.fixed-session";
pub const fixed_session_version = "0.1.0";
pub const fixed_session_config_version: u32 = 1;
pub const max_exercises: usize = 16;

pub const Method = union(enum) {
    double_progression: struct {
        config: double_progression.Config,
        state: ?double_progression.State = null,
    },
    rpe_top_set_backoff: struct {
        config: rpe.Config,
        state: ?rpe.State = null,
    },

    pub fn id(self: Method) []const u8 {
        return switch (self) {
            .double_progression => double_progression.methodology_id,
            .rpe_top_set_backoff => rpe.methodology_id,
        };
    }
};

pub const ExerciseSlot = struct {
    slot_id: primitives.Id,
    exercise_id: primitives.Id,
    state_id: primitives.Id,
    progression: Method,
};

pub const ProgramState = struct {
    schema_version: u32,
    data: std.json.Value,
};

pub const RecommendationRequest = struct {
    as_of: primitives.Timestamp,
    catalog: training.ExerciseCatalog,
    history: training.HistorySnapshot = .{},
    available_equipment_ids: []const primitives.Id = &.{},
    slots: []const ExerciseSlot,
    program_state: ?ProgramState = null,
};

pub const ProgressionState = union(enum) {
    double_progression: double_progression.State,
    rpe_top_set_backoff: rpe.State,
};

pub const StateProposal = struct {
    state_id: primitives.Id,
    method_id: []const u8,
    method_version: []const u8 = "0.1.0",
    state: ProgressionState,
};

pub const Evaluation = struct {
    exercises: []const canonical.ExerciseEvaluation,
    state_proposals: []const StateProposal,
    explanations: []const canonical.Explanation,
    next_program_state: ?ProgramState = null,
};

pub const Error = error{
    EmptyProgram,
    ExerciseLimitReached,
    ExerciseNotFound,
    EquipmentUnavailable,
    IncompatibleProgression,
    DuplicateSlotId,
    DuplicateStateId,
    MissingProgressionAssignment,
    UnsupportedProgressionVersion,
    ProgressionStateMismatch,
    InvalidProgressionConfig,
    InvalidProgressionState,
    InvalidProgramState,
    RecommendationProvenanceMismatch,
    CompletedExerciseMissing,
    DuplicateCompletedExercise,
    OutputLimitReached,
    OutOfMemory,
};

/// Arena-owned recommendation. All returned canonical slices and JSON values
/// remain valid until `deinit`; no ownership is hidden from direct Zig hosts.
pub const OwnedRecommendation = struct {
    arena: std.heap.ArenaAllocator,
    recommendation: canonical.SessionRecommendation,
    explanations: []const canonical.Explanation,

    pub fn deinit(self: *OwnedRecommendation) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub const OwnedEvaluation = struct {
    arena: std.heap.ArenaAllocator,
    evaluation: Evaluation,

    pub fn deinit(self: *OwnedEvaluation) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn recommendFixedSession(
    backing_allocator: std.mem.Allocator,
    request: RecommendationRequest,
) Error!OwnedRecommendation {
    try validateRequest(request);
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const exercises = allocator.alloc(canonical.ExerciseRecommendation, request.slots.len) catch return error.OutOfMemory;
    const explanations = allocator.alloc(canonical.Explanation, request.slots.len + 1) catch return error.OutOfMemory;
    explanations[0] = .{
        .id = "program-strategy",
        .code = "program.strategy.fixed_session",
        .category = "program",
        .summary = "The fixed-session strategy preserved the supplied exercise-slot order.",
        .ruleId = "fixed-session.ordered-slots",
        .severity = .info,
    };
    for (request.slots, 0..) |slot, index| {
        const exercise = findExercise(request.catalog, slot.exercise_id) orelse return error.ExerciseNotFound;
        if (!exercise_knowledge.requiredEquipmentSatisfied(exercise.*, request.available_equipment_ids))
            return error.EquipmentUnavailable;
        if (exercise_knowledge.progressionCompatibility(
            exercise.*,
            .externally_loadable_repetitions,
        ) == .incompatible) return error.IncompatibleProgression;
        exercises[index] = switch (slot.progression) {
            .double_progression => |value| try recommendDouble(allocator, request, slot, value, index, &explanations[index + 1]),
            .rpe_top_set_backoff => |value| try recommendRpe(allocator, request, slot, value, index, &explanations[index + 1]),
        };
    }
    return .{
        .arena = arena,
        .recommendation = .{
            .exercises = exercises,
            .programming = .{
                .strategy = resolved(fixed_session_id),
                .config = try jsonValue(allocator, struct {}{}),
                .inputState = if (request.program_state) |state| .{ .schemaVersion = state.schema_version, .data = state.data } else null,
            },
        },
        .explanations = explanations,
    };
}

pub fn evaluateFixedSession(
    backing_allocator: std.mem.Allocator,
    recommendation: canonical.SessionRecommendation,
    completed: training.CompletedWorkout,
) Error!OwnedEvaluation {
    const session_provenance = recommendation.programming orelse return error.RecommendationProvenanceMismatch;
    if (!std.mem.eql(u8, session_provenance.strategy.id, fixed_session_id) or
        !std.mem.eql(u8, session_provenance.strategy.version, fixed_session_version))
        return error.RecommendationProvenanceMismatch;
    if (recommendation.exercises.len > max_exercises) return error.ExerciseLimitReached;
    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const evaluations = allocator.alloc(canonical.ExerciseEvaluation, completed.exercises.len) catch return error.OutOfMemory;
    const proposals = allocator.alloc(StateProposal, completed.exercises.len) catch return error.OutOfMemory;
    const explanations = allocator.alloc(canonical.Explanation, completed.exercises.len) catch return error.OutOfMemory;
    for (completed.exercises, 0..) |completed_exercise, completed_index| {
        var occurrence: usize = 0;
        for (completed.exercises[0..completed_index]) |prior| {
            if (prior.exercise_id.eql(completed_exercise.exercise_id)) occurrence += 1;
        }
        const prescription = findPrescriptionOccurrence(recommendation, completed_exercise.exercise_id, occurrence) orelse return error.CompletedExerciseMissing;
        const provenance = prescription.programming orelse return error.RecommendationProvenanceMismatch;
        const one_exercise = training.CompletedWorkout{
            .id = completed.id,
            .started_at = completed.started_at,
            .completed_at = completed.completed_at,
            .exercises = completed.exercises[completed_index .. completed_index + 1],
        };
        if (std.mem.eql(u8, provenance.progression.id, double_progression.methodology_id)) {
            try evaluateDouble(allocator, provenance, one_exercise, completed_index, &evaluations[completed_index], &proposals[completed_index], &explanations[completed_index]);
        } else if (std.mem.eql(u8, provenance.progression.id, rpe.methodology_id)) {
            try evaluateRpe(allocator, provenance, one_exercise, completed_index, &evaluations[completed_index], &proposals[completed_index], &explanations[completed_index]);
        } else return error.RecommendationProvenanceMismatch;
    }
    return .{
        .arena = arena,
        .evaluation = .{
            .exercises = evaluations,
            .state_proposals = proposals,
            .explanations = explanations,
            .next_program_state = if (session_provenance.inputState) |state| .{ .schema_version = state.schemaVersion, .data = state.data } else null,
        },
    };
}

fn validateRequest(request: RecommendationRequest) Error!void {
    if (request.slots.len == 0) return error.EmptyProgram;
    if (request.slots.len > max_exercises) return error.ExerciseLimitReached;
    if (request.program_state) |state| if (state.schema_version != 1) return error.InvalidProgramState;
    var issue_storage: [64]training.ValidationIssue = undefined;
    const issues = training.validate(request.catalog, request.history, &issue_storage) catch return error.OutputLimitReached;
    if (issues.len != 0) return error.InvalidProgressionConfig;
    for (request.history.workouts) |workout| {
        if (workout.completed_at.unixSeconds() > request.as_of.unixSeconds()) return error.InvalidProgressionConfig;
    }
    for (request.slots, 0..) |slot, index| {
        for (request.slots[0..index]) |prior| {
            if (prior.slot_id.eql(slot.slot_id)) return error.DuplicateSlotId;
            if (prior.state_id.eql(slot.state_id)) return error.DuplicateStateId;
        }
        if (findExercise(request.catalog, slot.exercise_id) == null) return error.ExerciseNotFound;
    }
}

fn recommendDouble(allocator: std.mem.Allocator, request: RecommendationRequest, slot: ExerciseSlot, value: anytype, index: usize, explanation: *canonical.Explanation) Error!canonical.ExerciseRecommendation {
    const prescription = double_progression.recommendExercise(value.config, value.state, request.history, slot.exercise_id) catch return error.InvalidProgressionConfig;
    const sets = allocator.alloc(canonical.SetRecommendation, prescription.working_sets) catch return error.OutOfMemory;
    const metrics = allocator.alloc(canonical.Metric, prescription.working_sets * 2) catch return error.OutOfMemory;
    const refs = try refsFor(allocator, index);
    const load_amount = try formatDecimal(allocator, prescription.load.value);
    const repetitions = std.fmt.allocPrint(allocator, "{d}", .{prescription.repetitions}) catch return error.OutOfMemory;
    for (sets, 0..) |*set, set_index| {
        metrics[set_index * 2] = .{ .code = "load", .value = .{ .amount = load_amount, .unit = prescription.load.unit.code() } };
        metrics[set_index * 2 + 1] = .{ .code = "repetitions", .value = .{ .amount = repetitions, .unit = "count" } };
        set.* = .{ .kind = "working", .targetMetrics = metrics[set_index * 2 .. set_index * 2 + 2], .explanationRefs = refs };
    }
    explanation.* = progressionExplanation(index, slot.exercise_id.bytes, prescription.explanation.code, prescription.explanation.summary, prescription.explanation.rule_id);
    return .{
        .exerciseId = slot.exercise_id.bytes,
        .sets = sets,
        .explanationRefs = refs,
        .programming = .{
            .slotId = slot.slot_id.bytes,
            .stateId = slot.state_id.bytes,
            .progression = resolved(double_progression.methodology_id),
            .config = try jsonValue(allocator, value.config),
            .inputState = if (value.state) |state| .{ .schemaVersion = state.schemaVersion, .data = try jsonValue(allocator, state.data) } else null,
        },
    };
}

fn recommendRpe(allocator: std.mem.Allocator, request: RecommendationRequest, slot: ExerciseSlot, value: anytype, index: usize, explanation: *canonical.Explanation) Error!canonical.ExerciseRecommendation {
    const top = rpe.recommendTopSet(value.config, value.state, request.history, slot.exercise_id) catch return error.InvalidProgressionConfig;
    const backoff = rpe.recommendBackoffs(value.config, top) catch return error.InvalidProgressionConfig;
    const sets = allocator.alloc(canonical.SetRecommendation, @as(usize, backoff.set_count) + 1) catch return error.OutOfMemory;
    const metrics = allocator.alloc(canonical.Metric, 3 + @as(usize, backoff.set_count) * 2) catch return error.OutOfMemory;
    const refs = try refsFor(allocator, index);
    metrics[0] = .{ .code = "load", .value = .{ .amount = try formatDecimal(allocator, top.load.value), .unit = top.load.unit.code() } };
    metrics[1] = .{ .code = "repetitions", .value = .{ .amount = std.fmt.allocPrint(allocator, "{d}", .{top.repetitions}) catch return error.OutOfMemory, .unit = "count" } };
    metrics[2] = .{ .code = "rpe", .value = .{ .amount = try formatDecimal(allocator, top.target_rpe), .unit = "rpe" } };
    sets[0] = .{ .kind = "top", .targetMetrics = metrics[0..3], .explanationRefs = refs };
    var metric_index: usize = 3;
    for (sets[1..]) |*set| {
        metrics[metric_index] = .{ .code = "load", .value = .{ .amount = try formatDecimal(allocator, backoff.load.value), .unit = backoff.load.unit.code() } };
        metrics[metric_index + 1] = .{ .code = "repetitions", .value = .{ .amount = std.fmt.allocPrint(allocator, "{d}", .{backoff.repetitions}) catch return error.OutOfMemory, .unit = "count" } };
        set.* = .{ .kind = "backoff", .targetMetrics = metrics[metric_index .. metric_index + 2], .explanationRefs = refs };
        metric_index += 2;
    }
    explanation.* = progressionExplanation(index, slot.exercise_id.bytes, top.explanation.code, top.explanation.summary, top.explanation.rule_id);
    return .{
        .exerciseId = slot.exercise_id.bytes,
        .sets = sets,
        .explanationRefs = refs,
        .programming = .{
            .slotId = slot.slot_id.bytes,
            .stateId = slot.state_id.bytes,
            .progression = resolved(rpe.methodology_id),
            .config = try jsonValue(allocator, value.config),
            .inputState = if (value.state) |state| .{ .schemaVersion = state.schemaVersion, .data = try jsonValue(allocator, state.data) } else null,
        },
    };
}

fn evaluateDouble(allocator: std.mem.Allocator, provenance: canonical.ExerciseProgrammingProvenance, workout: training.CompletedWorkout, index: usize, evaluation: *canonical.ExerciseEvaluation, proposal: *StateProposal, explanation: *canonical.Explanation) Error!void {
    if (provenance.progression.configVersion != double_progression.config_version or !std.mem.eql(u8, provenance.progression.version, "0.1.0")) return error.UnsupportedProgressionVersion;
    const config = std.json.parseFromValueLeaky(double_progression.Config, allocator, provenance.config, .{ .ignore_unknown_fields = false }) catch return error.InvalidProgressionConfig;
    const state: ?double_progression.State = if (provenance.inputState) |input| .{ .schemaVersion = input.schemaVersion, .data = std.json.parseFromValueLeaky(double_progression.StateData, allocator, input.data, .{ .ignore_unknown_fields = false }) catch return error.ProgressionStateMismatch } else null;
    const state_storage = allocator.alloc(double_progression.ExerciseState, 64) catch return error.OutOfMemory;
    const evaluation_storage = allocator.alloc(double_progression.ExerciseEvaluation, 1) catch return error.OutOfMemory;
    const amount_storage = allocator.alloc(u8, 2048) catch return error.OutOfMemory;
    const result = double_progression.evaluatePerformance(config, state, &workout, .{ .state_exercises = state_storage, .exercise_evaluations = evaluation_storage, .load_amounts = amount_storage }) catch return error.InvalidProgressionState;
    const refs = try evaluationRefsFor(allocator, index);
    evaluation.* = .{ .exerciseId = workout.exercises[0].exercise_id.bytes, .outcome = result.exercises[0].outcome, .explanationRefs = refs, .stateId = provenance.stateId, .progression = provenance.progression };
    proposal.* = .{ .state_id = primitives.Id.parse(provenance.stateId) catch return error.RecommendationProvenanceMismatch, .method_id = double_progression.methodology_id, .state = .{ .double_progression = result.next_state } };
    explanation.* = .{ .id = refs[0], .code = result.exercises[0].explanation.code, .category = "progression", .summary = result.exercises[0].explanation.summary, .subject = .{ .exerciseId = workout.exercises[0].exercise_id.bytes }, .ruleId = result.exercises[0].explanation.rule_id, .severity = .info };
}

fn evaluateRpe(allocator: std.mem.Allocator, provenance: canonical.ExerciseProgrammingProvenance, workout: training.CompletedWorkout, index: usize, evaluation: *canonical.ExerciseEvaluation, proposal: *StateProposal, explanation: *canonical.Explanation) Error!void {
    if (provenance.progression.configVersion != rpe.config_version or !std.mem.eql(u8, provenance.progression.version, "0.1.0")) return error.UnsupportedProgressionVersion;
    const config = std.json.parseFromValueLeaky(rpe.Config, allocator, provenance.config, .{ .ignore_unknown_fields = false }) catch return error.InvalidProgressionConfig;
    const state: ?rpe.State = if (provenance.inputState) |input| .{ .schemaVersion = input.schemaVersion, .data = std.json.parseFromValueLeaky(rpe.StateData, allocator, input.data, .{ .ignore_unknown_fields = false }) catch return error.ProgressionStateMismatch } else null;
    const state_storage = allocator.alloc(rpe.ExerciseState, 64) catch return error.OutOfMemory;
    const evaluation_storage = allocator.alloc(rpe.ExerciseEvaluation, 1) catch return error.OutOfMemory;
    const amount_storage = allocator.alloc(u8, 2048) catch return error.OutOfMemory;
    const result = rpe.evaluatePerformance(config, state, &workout, .{ .state_exercises = state_storage, .exercise_evaluations = evaluation_storage, .estimate_amounts = amount_storage }) catch return error.InvalidProgressionState;
    const refs = try evaluationRefsFor(allocator, index);
    evaluation.* = .{ .exerciseId = workout.exercises[0].exercise_id.bytes, .outcome = @tagName(result.exercises[0].outcome), .explanationRefs = refs, .stateId = provenance.stateId, .progression = provenance.progression };
    proposal.* = .{ .state_id = primitives.Id.parse(provenance.stateId) catch return error.RecommendationProvenanceMismatch, .method_id = rpe.methodology_id, .state = .{ .rpe_top_set_backoff = result.next_state } };
    explanation.* = .{ .id = refs[0], .code = result.exercises[0].policy_explanation.code, .category = "progression", .summary = result.exercises[0].policy_explanation.summary, .subject = .{ .exerciseId = workout.exercises[0].exercise_id.bytes }, .ruleId = result.exercises[0].policy_explanation.rule_id, .severity = .info };
}

fn findExercise(catalog: training.ExerciseCatalog, id: primitives.Id) ?*const training.Exercise {
    for (catalog.exercises) |*exercise| if (exercise.id.eql(id)) return exercise;
    return null;
}

fn findPrescriptionOccurrence(recommendation: canonical.SessionRecommendation, id: primitives.Id, target_occurrence: usize) ?canonical.ExerciseRecommendation {
    var occurrence: usize = 0;
    for (recommendation.exercises) |exercise| {
        if (!std.mem.eql(u8, exercise.exerciseId, id.bytes)) continue;
        if (occurrence == target_occurrence) return exercise;
        occurrence += 1;
    }
    return null;
}

fn equipmentAvailable(required: []const primitives.Id, available: []const primitives.Id) bool {
    for (required) |required_id| {
        for (available) |available_id| if (required_id.eql(available_id)) break else {} else return false;
    }
    return true;
}

fn resolved(id: []const u8) canonical.ResolvedComponent {
    return .{ .id = id, .version = "0.1.0", .configVersion = 1 };
}

fn refsFor(allocator: std.mem.Allocator, index: usize) Error![]const []const u8 {
    const refs = allocator.alloc([]const u8, 1) catch return error.OutOfMemory;
    refs[0] = std.fmt.allocPrint(allocator, "progression-{d}", .{index + 1}) catch return error.OutOfMemory;
    return refs;
}

fn evaluationRefsFor(allocator: std.mem.Allocator, index: usize) Error![]const []const u8 {
    const refs = allocator.alloc([]const u8, 1) catch return error.OutOfMemory;
    refs[0] = std.fmt.allocPrint(allocator, "evaluation-progression-{d}", .{index + 1}) catch return error.OutOfMemory;
    return refs;
}

fn progressionExplanation(index: usize, exercise_id: []const u8, code: []const u8, summary: []const u8, rule_id: []const u8) canonical.Explanation {
    const ids = [_][]const u8{ "progression-1", "progression-2", "progression-3", "progression-4", "progression-5", "progression-6", "progression-7", "progression-8", "progression-9", "progression-10", "progression-11", "progression-12", "progression-13", "progression-14", "progression-15", "progression-16" };
    return .{ .id = ids[index], .code = code, .category = "progression", .summary = summary, .subject = .{ .exerciseId = exercise_id }, .ruleId = rule_id, .severity = .info };
}

fn formatDecimal(allocator: std.mem.Allocator, value: primitives.Decimal) Error![]const u8 {
    const storage = allocator.alloc(u8, 64) catch return error.OutOfMemory;
    return value.format(storage) catch return error.OutputLimitReached;
}

fn jsonValue(allocator: std.mem.Allocator, value: anytype) Error!std.json.Value {
    const bytes = std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    return std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{}) catch return error.OutOfMemory;
}

fn testDoubleConfig() double_progression.Config {
    return .{
        .repRange = .{ .min = 8, .max = 12 },
        .workingSets = 1,
        .advancementCriteria = .{ .minimumSuccessfulSets = 1, .minimumRepetitions = 12 },
        .initialLoad = .{ .amount = "45", .unit = "lb" },
        .loadIncrement = .{ .amount = "5", .unit = "lb" },
        .failurePolicy = .{ .onPartial = .hold, .onFailure = .regress, .regressionAmount = .{ .amount = "5", .unit = "lb" } },
        .rounding = .{ .mode = .nearest, .quantum = .{ .amount = "2.5", .unit = "lb" } },
    };
}

fn testRpeConfig() rpe.Config {
    return .{
        .initialEstimatedOneRepMax = .{ .amount = "225", .unit = "lb" },
        .topSetRepetitions = 5,
        .targetRpe = "8.0",
        .backoff = .{ .calculation = .percentage_of_top_set, .percentage = "90", .repetitions = 8, .setCount = 1 },
        .rounding = .{ .mode = .nearest, .quantum = .{ .amount = "2.5", .unit = "lb" } },
        .exertionPolicy = .{ .tolerance = "0.5", .onOvershoot = .decrease_estimate, .onUndershoot = .increase_estimate, .estimateAdjustmentPercentage = "2.5" },
        .estimationFormula = .epley,
    };
}

test "fixed session composes and evaluates two progression methods with isolated state" {
    const catalog_exercises = [_]training.Exercise{
        .{ .id = try .parse("leg-extension") },
        .{ .id = try .parse("barbell-bench-press") },
    };
    const slots = [_]ExerciseSlot{
        .{ .slot_id = try .parse("accessory-slot"), .exercise_id = catalog_exercises[0].id, .state_id = try .parse("block-1-accessory"), .progression = .{ .double_progression = .{ .config = testDoubleConfig() } } },
        .{ .slot_id = try .parse("primary-slot"), .exercise_id = catalog_exercises[1].id, .state_id = try .parse("block-1-primary"), .progression = .{ .rpe_top_set_backoff = .{ .config = testRpeConfig() } } },
    };
    var recommendation = try recommendFixedSession(std.testing.allocator, .{
        .as_of = try .parse("2026-08-10T12:00:00Z"),
        .catalog = .{ .exercises = &catalog_exercises },
        .slots = &slots,
    });
    defer recommendation.deinit();
    try std.testing.expectEqual(@as(usize, 2), recommendation.recommendation.exercises.len);
    try std.testing.expectEqualStrings(double_progression.methodology_id, recommendation.recommendation.exercises[0].programming.?.progression.id);
    try std.testing.expectEqualStrings(rpe.methodology_id, recommendation.recommendation.exercises[1].programming.?.progression.id);

    const load = try primitives.Id.parse("load");
    const repetitions = try primitives.Id.parse("repetitions");
    const exertion = try primitives.Id.parse("rpe");
    const dp_metrics = [_]training.Metric{
        .{ .code = load, .value = .{ .value = try .parse("45"), .unit = .lb } },
        .{ .code = repetitions, .value = .{ .value = try .parse("12"), .unit = .count } },
    };
    const rpe_metrics = [_]training.Metric{
        .{ .code = load, .value = .{ .value = try .parse("190"), .unit = .lb } },
        .{ .code = repetitions, .value = .{ .value = try .parse("5"), .unit = .count } },
        .{ .code = exertion, .value = .{ .value = try .parse("9"), .unit = .rpe } },
    };
    const dp_sets = [_]training.CompletedSet{.{ .kind = try .parse("working"), .actual_metrics = &dp_metrics, .status = .completed }};
    const rpe_sets = [_]training.CompletedSet{.{ .kind = try .parse("top"), .actual_metrics = &rpe_metrics, .status = .completed }};
    const completed_exercises = [_]training.CompletedExercise{
        .{ .exercise_id = catalog_exercises[0].id, .sets = &dp_sets },
        .{ .exercise_id = catalog_exercises[1].id, .sets = &rpe_sets },
    };
    var evaluation = try evaluateFixedSession(std.testing.allocator, recommendation.recommendation, .{
        .id = try .parse("mixed-workout"),
        .started_at = try .parse("2026-08-10T12:00:00Z"),
        .completed_at = try .parse("2026-08-10T13:00:00Z"),
        .exercises = &completed_exercises,
    });
    defer evaluation.deinit();
    try std.testing.expectEqual(@as(usize, 2), evaluation.evaluation.state_proposals.len);
    try std.testing.expectEqualStrings("block-1-accessory", evaluation.evaluation.state_proposals[0].state_id.bytes);
    try std.testing.expectEqualStrings(double_progression.methodology_id, evaluation.evaluation.state_proposals[0].method_id);
    try std.testing.expectEqualStrings("block-1-primary", evaluation.evaluation.state_proposals[1].state_id.bytes);
    try std.testing.expectEqualStrings(rpe.methodology_id, evaluation.evaluation.state_proposals[1].method_id);
    try std.testing.expect(evaluation.evaluation.next_program_state == null);
}

test "fixed session rejects duplicate progression state identity" {
    const exercises = [_]training.Exercise{ .{ .id = try .parse("a") }, .{ .id = try .parse("b") } };
    const duplicate = try primitives.Id.parse("same-lane");
    const slots = [_]ExerciseSlot{
        .{ .slot_id = try .parse("slot-a"), .exercise_id = exercises[0].id, .state_id = duplicate, .progression = .{ .double_progression = .{ .config = testDoubleConfig() } } },
        .{ .slot_id = try .parse("slot-b"), .exercise_id = exercises[1].id, .state_id = duplicate, .progression = .{ .rpe_top_set_backoff = .{ .config = testRpeConfig() } } },
    };
    try std.testing.expectError(error.DuplicateStateId, recommendFixedSession(std.testing.allocator, .{ .as_of = try .parse("2026-08-10T12:00:00Z"), .catalog = .{ .exercises = &exercises }, .slots = &slots }));
}

test "fixed session rejects explicit duration-only progression mismatch" {
    const exercise = training.Exercise{
        .id = try .parse("plank"),
        .knowledge = .{
            .loadingMode = .duration,
            .trackingDimensions = &.{.{ .metricCode = "duration" }},
            .progressionCapabilities = .{
                .externalLoad = false,
                .repetitions = false,
                .duration = true,
            },
        },
    };
    const slots = [_]ExerciseSlot{.{
        .slot_id = try .parse("plank-slot"),
        .exercise_id = exercise.id,
        .state_id = try .parse("plank-lane"),
        .progression = .{ .double_progression = .{ .config = testDoubleConfig() } },
    }};
    try std.testing.expectError(
        error.IncompatibleProgression,
        recommendFixedSession(std.testing.allocator, .{
            .as_of = try .parse("2026-08-10T12:00:00Z"),
            .catalog = .{ .exercises = &.{exercise} },
            .slots = &slots,
        }),
    );
}
