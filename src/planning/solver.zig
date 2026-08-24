//! Deterministic candidate filtering, scoring, bounded global search, and
//! independent resolved-plan validation.

const std = @import("std");
const primitives = @import("../primitives.zig");
const training = @import("../training.zig");
const exercise_knowledge = @import("../exercise_knowledge.zig");
const exercise_selection = @import("../exercise_selection.zig");
const progression = @import("../progression/root.zig");
const volume = @import("../volume.zig");
const model = @import("problem.zig");

pub const max_slots: usize = 16;
pub const max_catalog_exercises: usize = 512;
pub const max_objectives: usize = 64;
pub const max_duration_estimates: usize = 1024;
pub const max_retained_candidates_per_slot: usize = 32;
pub const max_constraint_ids: usize = 64;
pub const max_tie_break_seed_bytes: usize = 64;

pub const SolveError = error{
    InvalidProblem,
    ProblemLimitExceeded,
    InvalidOptions,
    ScoreOverflow,
};

pub const ValidationError = error{
    InvalidOptions,
    InvalidProblem,
    InvalidResolvedPlan,
    ProblemLimitExceeded,
    ScoreOverflow,
};

const Candidate = struct {
    exercise_index: usize,
    local_score: model.ScoreVector,
    local_rank: u16 = 0,
};

const CandidateRange = struct {
    offset: usize,
    retained_count: usize = 0,
    eligible_count: u16 = 0,
};

/// Allocator-backed bounded workspace. `solve` performs no allocation and all
/// slices in its result remain valid until this workspace is reused or freed.
pub const Workspace = struct {
    allocator: std.mem.Allocator,
    owns_storage: bool,
    slot_order: []usize,
    ranges: []CandidateRange,
    candidates: []Candidate,
    digits: []usize,
    current: []?usize,
    best: []?usize,
    resolved_slots: []model.ResolvedSlot,
    alternatives: []model.CandidateAlternative,
    omitted_slots: []model.OmittedSlot,
    reasons: []model.DecisionReason,
    reason_refs: []u16,
    order_indices: []usize,
    in_degrees: []u8,
    violations: []model.InfeasibilityViolation,
    fingerprint_storage: [64]u8 = undefined,

    pub fn init(
        allocator: std.mem.Allocator,
        problem: model.PlanningProblem,
        options: model.SolveOptions,
    ) (SolveError || std.mem.Allocator.Error)!Workspace {
        try validateProblem(problem);
        try validateOptions(options);
        const candidate_capacity = std.math.mul(
            usize,
            problem.slots.len,
            options.candidate_limit_per_slot,
        ) catch return error.ProblemLimitExceeded;

        var result: Workspace = undefined;
        result.allocator = allocator;
        result.owns_storage = true;
        result.slot_order = try allocator.alloc(usize, problem.slots.len);
        errdefer allocator.free(result.slot_order);
        result.ranges = try allocator.alloc(CandidateRange, problem.slots.len);
        errdefer allocator.free(result.ranges);
        result.candidates = try allocator.alloc(Candidate, candidate_capacity);
        errdefer allocator.free(result.candidates);
        result.digits = try allocator.alloc(usize, problem.slots.len);
        errdefer allocator.free(result.digits);
        result.current = try allocator.alloc(?usize, problem.slots.len);
        errdefer allocator.free(result.current);
        result.best = try allocator.alloc(?usize, problem.slots.len);
        errdefer allocator.free(result.best);
        result.resolved_slots = try allocator.alloc(model.ResolvedSlot, problem.slots.len);
        errdefer allocator.free(result.resolved_slots);
        result.alternatives = try allocator.alloc(model.CandidateAlternative, candidate_capacity);
        errdefer allocator.free(result.alternatives);
        result.omitted_slots = try allocator.alloc(model.OmittedSlot, problem.slots.len);
        errdefer allocator.free(result.omitted_slots);
        result.reasons = try allocator.alloc(model.DecisionReason, problem.slots.len + 1);
        errdefer allocator.free(result.reasons);
        result.reason_refs = try allocator.alloc(u16, problem.slots.len);
        errdefer allocator.free(result.reason_refs);
        result.order_indices = try allocator.alloc(usize, problem.slots.len);
        errdefer allocator.free(result.order_indices);
        result.in_degrees = try allocator.alloc(u8, problem.slots.len);
        errdefer allocator.free(result.in_degrees);
        result.violations = try allocator.alloc(
            model.InfeasibilityViolation,
            problem.slots.len + max_constraint_ids + 4,
        );
        return result;
    }

    pub fn deinit(self: *Workspace) void {
        if (!self.owns_storage) {
            self.* = undefined;
            return;
        }
        self.allocator.free(self.slot_order);
        self.allocator.free(self.ranges);
        self.allocator.free(self.candidates);
        self.allocator.free(self.digits);
        self.allocator.free(self.current);
        self.allocator.free(self.best);
        self.allocator.free(self.resolved_slots);
        self.allocator.free(self.alternatives);
        self.allocator.free(self.omitted_slots);
        self.allocator.free(self.reasons);
        self.allocator.free(self.reason_refs);
        self.allocator.free(self.order_indices);
        self.allocator.free(self.in_degrees);
        self.allocator.free(self.violations);
        self.* = undefined;
    }
};

/// Fully caller-owned storage for the low-level solver. This is intentionally
/// large enough for every documented planner limit; callers that prefer exact
/// allocation can use `Workspace.init` as a convenience wrapper.
pub const FixedWorkspace = struct {
    slot_order: [max_slots]usize = undefined,
    ranges: [max_slots]CandidateRange = undefined,
    candidates: [max_slots * max_retained_candidates_per_slot]Candidate = undefined,
    digits: [max_slots]usize = undefined,
    current: [max_slots]?usize = undefined,
    best: [max_slots]?usize = undefined,
    resolved_slots: [max_slots]model.ResolvedSlot = undefined,
    alternatives: [max_slots * max_retained_candidates_per_slot]model.CandidateAlternative = undefined,
    omitted_slots: [max_slots]model.OmittedSlot = undefined,
    reasons: [max_slots + 1]model.DecisionReason = undefined,
    reason_refs: [max_slots]u16 = undefined,
    order_indices: [max_slots]usize = undefined,
    in_degrees: [max_slots]u8 = undefined,
    violations: [max_slots + max_constraint_ids + 4]model.InfeasibilityViolation = undefined,

    pub fn workspace(
        self: *FixedWorkspace,
        problem: model.PlanningProblem,
        options: model.SolveOptions,
    ) SolveError!Workspace {
        try validateProblem(problem);
        try validateOptions(options);
        const candidate_count = std.math.mul(
            usize,
            problem.slots.len,
            options.candidate_limit_per_slot,
        ) catch return error.ProblemLimitExceeded;
        return .{
            .allocator = undefined,
            .owns_storage = false,
            .slot_order = self.slot_order[0..problem.slots.len],
            .ranges = self.ranges[0..problem.slots.len],
            .candidates = self.candidates[0..candidate_count],
            .digits = self.digits[0..problem.slots.len],
            .current = self.current[0..problem.slots.len],
            .best = self.best[0..problem.slots.len],
            .resolved_slots = self.resolved_slots[0..problem.slots.len],
            .alternatives = self.alternatives[0..candidate_count],
            .omitted_slots = self.omitted_slots[0..problem.slots.len],
            .reasons = self.reasons[0 .. problem.slots.len + 1],
            .reason_refs = self.reason_refs[0..problem.slots.len],
            .order_indices = self.order_indices[0..problem.slots.len],
            .in_degrees = self.in_degrees[0..problem.slots.len],
            .violations = self.violations[0 .. problem.slots.len + max_constraint_ids + 4],
        };
    }
};

pub fn solve(
    problem: model.PlanningProblem,
    options: model.SolveOptions,
    workspace: *Workspace,
) SolveError!model.SolveResult {
    try validateProblem(problem);
    try validateOptions(options);
    if (!workspaceFits(workspace, problem, options)) return error.ProblemLimitExceeded;

    canonicalSlotOrder(problem.slots, workspace.slot_order);
    const retained_total = try generateCandidates(problem, options, workspace);
    _ = retained_total;
    fingerprintProblem(problem, &workspace.fingerprint_storage);

    var violation_count: usize = 0;
    try proveCheapContradictions(problem, workspace, &violation_count);
    if (violation_count != 0) {
        return .{ .infeasible = .{
            .planner = provenance(options, 0),
            .problem_fingerprint = &workspace.fingerprint_storage,
            .violations = workspace.violations[0..violation_count],
        } };
    }

    @memset(workspace.digits, 0);
    var explored: u32 = 0;
    var found = false;
    var best_score: model.ScoreVector = .{};
    var enumeration_complete = false;

    while (explored < options.beam_width) {
        mapDigitsToAssignment(problem, workspace);
        explored += 1;
        if (try assignmentScore(
            problem,
            workspace.candidates,
            workspace.current,
            workspace.order_indices,
            workspace.in_degrees,
        )) |score| {
            if (!found or model.ScoreVector.order(score, best_score) == .gt) {
                found = true;
                best_score = score;
                @memcpy(workspace.best, workspace.current);
            }
        }
        if (!incrementDigits(problem, workspace)) {
            enumeration_complete = true;
            break;
        }
    }

    if (!found) {
        const truncated = anyCandidateRangeTruncated(workspace.ranges);
        if (!enumeration_complete or truncated) return .{ .search_exhausted = .{
            .planner = provenance(options, explored),
            .problem_fingerprint = &workspace.fingerprint_storage,
            .explored_state_count = explored,
        } };
        workspace.violations[0] = .constraints_jointly_unsatisfiable;
        return .{ .infeasible = .{
            .planner = provenance(options, explored),
            .problem_fingerprint = &workspace.fingerprint_storage,
            .violations = workspace.violations[0..1],
        } };
    }

    return .{ .resolved = try buildResolvedPlan(
        problem,
        options,
        workspace,
        best_score,
        explored,
    ) };
}

/// Re-evaluates the resolved assignments and every hard constraint without
/// trusting optimizer bookkeeping, scores, metrics, or candidate ranks.
pub fn validateResolvedPlan(
    problem: model.PlanningProblem,
    plan: model.ResolvedSessionPlan,
) ValidationError!void {
    try validateProblem(problem);
    if (plan.schema_version != model.schema_version or
        !sameOrigin(problem.origin, plan.origin) or
        plan.slots.len + plan.omitted_slots.len != problem.slots.len)
        return error.InvalidResolvedPlan;

    for (problem.slots) |slot| {
        const resolved = findResolved(plan.slots, slot.id);
        const omitted = findOmitted(plan.omitted_slots, slot.id);
        if ((resolved == null) == (omitted == null)) return error.InvalidResolvedPlan;
        if (slot.presence == .required and omitted != null) return error.InvalidResolvedPlan;
        if (resolved) |placed| {
            const exercise = problem.catalog.find(placed.exercise_id) orelse
                return error.InvalidResolvedPlan;
            if (!slot.progression.state_id.eql(placed.progression.state_id) or
                !std.mem.eql(u8, slot.progression.method.id(), placed.progression.method.id()) or
                !candidateEligible(problem, slot, exercise.*))
                return error.InvalidResolvedPlan;
        }
    }
    for (plan.slots, 0..) |slot, index| {
        if (slot.position != index) return error.InvalidResolvedPlan;
        for (plan.slots[0..index]) |prior| if (prior.slot_id.eql(slot.slot_id))
            return error.InvalidResolvedPlan;
    }
    if (!resolvedPlanHardConstraints(problem, plan.slots)) return error.InvalidResolvedPlan;
}

fn validateProblem(problem: model.PlanningProblem) SolveError!void {
    if (problem.schema_version != model.schema_version or problem.origin.definition_version == 0 or
        problem.origin.definition_fingerprint.len == 0 or problem.slots.len == 0)
        return error.InvalidProblem;
    if (problem.slots.len > max_slots or problem.catalog.exercises.len > max_catalog_exercises or
        problem.objectives.len > max_objectives or problem.duration_estimates.len > max_duration_estimates)
        return error.ProblemLimitExceeded;
    if (problem.volume_context) |context| {
        volume.validatePolicy(context.policy) catch return error.InvalidProblem;
        if (!context.state.policy_id.eql(context.policy.id) or
            context.state.policy_version != context.policy.version) return error.InvalidProblem;
        if (context.state.muscles.len > volume.max_muscles) return error.ProblemLimitExceeded;
    }
    if (problem.constraints.minimum_exercises) |minimum| {
        if (problem.constraints.maximum_exercises) |maximum| if (minimum > maximum)
            return error.InvalidProblem;
    }
    for (problem.catalog.exercises, 0..) |exercise, index| {
        if (exercise.family_ids.len > max_constraint_ids or
            exercise.equipment_ids.len > max_constraint_ids or
            exercise.movement_tags.len > max_constraint_ids or
            exercise.muscle_contributions.len > max_constraint_ids)
            return error.ProblemLimitExceeded;
        if (exercise.knowledge) |knowledge| {
            if (knowledge.movementPatterns.len > max_constraint_ids or
                knowledge.restrictionTags.len > max_constraint_ids or
                knowledge.equipmentRequirements.len > max_constraint_ids)
                return error.ProblemLimitExceeded;
        }
        for (problem.catalog.exercises[0..index]) |prior| if (prior.id.eql(exercise.id))
            return error.InvalidProblem;
    }
    var required_slot_count: usize = 0;
    for (problem.slots, 0..) |slot, index| {
        if (slot.presence == .required) required_slot_count += 1;
        for (problem.slots[0..index]) |prior| {
            if (prior.id.eql(slot.id) or
                prior.progression.state_id.eql(slot.progression.state_id))
                return error.InvalidProblem;
        }
        try validateIdSet(slot.ordering.before_slot_ids);
        try validateIdSet(slot.ordering.after_slot_ids);
        switch (slot.selection) {
            .fixed => {},
            .adaptive => |adaptive| {
                try validateExerciseSet(adaptive.preferred);
                switch (adaptive.universe) {
                    .catalog => {},
                    .allowlist => |set| try validateExerciseSet(set),
                }
                try validateIdSet(adaptive.requirements.muscles.ids);
                try validateIdSet(adaptive.requirements.movement_patterns.ids);
                try validateIdSet(adaptive.requirements.exercise_families.ids);
                try validateIdSet(adaptive.requirements.equipment.ids);
                try validateIdSet(adaptive.requirements.excluded_exercise_ids);
            },
        }
        for (slot.ordering.before_slot_ids) |id| if (findSlotIndex(problem.slots, id) == null)
            return error.InvalidProblem;
        for (slot.ordering.after_slot_ids) |id| if (findSlotIndex(problem.slots, id) == null)
            return error.InvalidProblem;
    }
    if (required_slot_count == 0) return error.InvalidProblem;
    try validateIdSet(problem.constraints.available_equipment_ids);
    try validateIdSet(problem.constraints.required_exercise_ids);
    try validateIdSet(problem.constraints.excluded_exercise_ids);
    try validateIdSet(problem.constraints.excluded_family_ids);
    try validateIdSet(problem.constraints.excluded_movement_pattern_ids);
    try validateIdSet(problem.constraints.excluded_restriction_tag_ids);
    try validateIdSet(problem.constraints.excluded_equipment_ids);
    for (problem.duration_estimates, 0..) |estimate, index| {
        if (findSlotIndex(problem.slots, estimate.slot_id) == null) return error.InvalidProblem;
        for (problem.duration_estimates[0..index]) |prior| {
            if (prior.slot_id.eql(estimate.slot_id) and prior.exercise_id.eql(estimate.exercise_id))
                return error.InvalidProblem;
        }
    }
}

fn validateOptions(options: model.SolveOptions) SolveError!void {
    if (options.candidate_limit_per_slot == 0 or
        options.candidate_limit_per_slot > max_retained_candidates_per_slot or
        options.beam_width == 0)
        return error.InvalidOptions;
    switch (options.tie_break) {
        .stable_id => {},
        .seeded => |seed| if (seed.len > max_tie_break_seed_bytes) return error.InvalidOptions,
    }
}

fn validateExerciseSet(set: model.ExerciseSet) SolveError!void {
    try validateIdSet(set.exercise_ids);
    try validateIdSet(set.family_ids);
}

fn validateIdSet(ids: []const primitives.Id) SolveError!void {
    if (ids.len > max_constraint_ids) return error.ProblemLimitExceeded;
    for (ids, 0..) |id, index| for (ids[0..index]) |prior| if (prior.eql(id))
        return error.InvalidProblem;
}

fn workspaceFits(workspace: *Workspace, problem: model.PlanningProblem, options: model.SolveOptions) bool {
    const slots = problem.slots.len;
    const candidates = std.math.mul(usize, slots, options.candidate_limit_per_slot) catch return false;
    return workspace.slot_order.len >= slots and workspace.ranges.len >= slots and
        workspace.candidates.len >= candidates and workspace.digits.len >= slots and
        workspace.current.len >= slots and workspace.best.len >= slots and
        workspace.resolved_slots.len >= slots and workspace.omitted_slots.len >= slots and
        workspace.alternatives.len >= candidates and
        workspace.reasons.len >= slots + 1 and workspace.reason_refs.len >= slots and
        workspace.order_indices.len >= slots and workspace.in_degrees.len >= slots and
        workspace.violations.len >= slots + max_constraint_ids + 4;
}

fn provenance(options: model.SolveOptions, explored: u32) model.PlannerProvenance {
    return .{
        .candidate_limit_per_slot = options.candidate_limit_per_slot,
        .search_bound = options.beam_width,
        .tie_break = options.tie_break,
        .explored_state_count = explored,
    };
}

fn canonicalSlotOrder(slots: []const model.Slot, out: []usize) void {
    for (slots, 0..) |_, index| {
        var insertion = index;
        while (insertion > 0 and std.mem.order(
            u8,
            slots[index].id.bytes,
            slots[out[insertion - 1]].id.bytes,
        ) == .lt) : (insertion -= 1) out[insertion] = out[insertion - 1];
        out[insertion] = index;
    }
}

fn generateCandidates(
    problem: model.PlanningProblem,
    options: model.SolveOptions,
    workspace: *Workspace,
) SolveError!usize {
    var total: usize = 0;
    for (workspace.slot_order[0..problem.slots.len]) |slot_index| {
        const slot = problem.slots[slot_index];
        const range = &workspace.ranges[slot_index];
        range.* = .{ .offset = total };
        for (problem.catalog.exercises, 0..) |exercise, exercise_index| {
            if (!candidateEligible(problem, slot, exercise)) continue;
            range.eligible_count = std.math.add(u16, range.eligible_count, 1) catch
                return error.ProblemLimitExceeded;
            const candidate = Candidate{
                .exercise_index = exercise_index,
                .local_score = try localScore(problem, slot, exercise),
            };
            insertCandidate(
                problem,
                options.tie_break,
                workspace.candidates[range.offset .. range.offset + options.candidate_limit_per_slot],
                &range.retained_count,
                candidate,
            );
        }
        for (workspace.candidates[range.offset .. range.offset + range.retained_count], 0..) |*candidate, rank|
            candidate.local_rank = @intCast(rank);
        total += range.retained_count;
    }
    return total;
}

fn insertCandidate(
    problem: model.PlanningProblem,
    tie_break: model.TieBreakPolicy,
    storage: []Candidate,
    count: *usize,
    candidate: Candidate,
) void {
    var insertion: usize = 0;
    while (insertion < count.* and !candidateBefore(problem, tie_break, candidate, storage[insertion]))
        insertion += 1;
    if (insertion >= storage.len) return;
    const new_count = @min(storage.len, count.* + 1);
    var move = new_count - 1;
    while (move > insertion) : (move -= 1) storage[move] = storage[move - 1];
    storage[insertion] = candidate;
    count.* = new_count;
}

fn candidateBefore(
    problem: model.PlanningProblem,
    tie_break: model.TieBreakPolicy,
    left: Candidate,
    right: Candidate,
) bool {
    const score_order = model.ScoreVector.order(left.local_score, right.local_score);
    if (score_order != .eq) return score_order == .gt;
    const left_id = problem.catalog.exercises[left.exercise_index].id.bytes;
    const right_id = problem.catalog.exercises[right.exercise_index].id.bytes;
    return tieOrder(tie_break, left_id, right_id) == .lt;
}

fn tieOrder(policy: model.TieBreakPolicy, left: []const u8, right: []const u8) std.math.Order {
    return switch (policy) {
        .stable_id => std.mem.order(u8, left, right),
        .seeded => |seed| blk: {
            const seed_hash = std.hash.Wyhash.hash(0, seed);
            const left_hash = std.hash.Wyhash.hash(seed_hash, left);
            const right_hash = std.hash.Wyhash.hash(seed_hash, right);
            const order = std.math.order(left_hash, right_hash);
            break :blk if (order == .eq) std.mem.order(u8, left, right) else order;
        },
    };
}

fn candidateEligible(problem: model.PlanningProblem, slot: model.Slot, exercise: training.Exercise) bool {
    if (!candidateEligibleWithoutVolume(problem, slot, exercise)) return false;
    if (candidateVolumeConflict(problem, slot, exercise) != null) return false;
    return true;
}

fn candidateEligibleWithoutVolume(
    problem: model.PlanningProblem,
    slot: model.Slot,
    exercise: training.Exercise,
) bool {
    switch (slot.selection) {
        .fixed => |id| if (!id.eql(exercise.id)) return false,
        .adaptive => |adaptive| {
            switch (adaptive.universe) {
                .catalog => {},
                .allowlist => |allowlist| if (!exerciseSetContains(exercise, allowlist)) return false,
            }
            if (!matchesPlannerOnlyRequirements(exercise, adaptive.requirements)) return false;
        },
    }
    const constraints = problem.constraints;
    if (containsId(constraints.excluded_exercise_ids, exercise.id) or
        hasAnyFamily(exercise, constraints.excluded_family_ids) or
        hasAnyMovement(exercise, constraints.excluded_movement_pattern_ids) or
        hasAnyEquipment(exercise, constraints.excluded_equipment_ids))
        return false;
    // The standalone selector owns shared exercise-local hard eligibility;
    // the planner adds slot-universe and whole-session constraints around it.
    const selection_role: exercise_selection.Role = switch (slot.selection) {
        .fixed => |id| .{ .fixed_exercise_id = id, .progression_requirement = slot.progression.method.requirement() },
        .adaptive => |adaptive| .{
            .target_muscles = if (adaptive.requirements.muscles.mode == .any) adaptive.requirements.muscles.ids else &.{},
            .movement_patterns = if (adaptive.requirements.movement_patterns.mode == .any) adaptive.requirements.movement_patterns.ids else &.{},
            .exercise_families = if (adaptive.requirements.exercise_families.mode == .any) adaptive.requirements.exercise_families.ids else &.{},
            .progression_requirement = slot.progression.method.requirement(),
        },
    };
    if (exercise_selection.eligibility(exercise, selection_role, .{
        .available_equipment_ids = constraints.available_equipment_ids,
        .excluded_restriction_ids = constraints.excluded_restriction_tag_ids,
    }) != null) return false;
    if (durationFor(problem, slot.id, exercise.id) == null and
        constraints.unknown_duration_policy == .reject) return false;
    return true;
}

fn candidateVolumeConflict(
    problem: model.PlanningProblem,
    slot: model.Slot,
    exercise: training.Exercise,
) ?volume.CapConflict {
    if (problem.volume_context) |context| {
        const sets = expectedQualifyingSetCount(
            slot.progression,
            exercise.id,
            context.policy,
        ) orelse return null;
        if (volume.capConflictForExercise(context.state, exercise, sets, context.policy) catch
            return null) |conflict| return conflict;
    }
    return null;
}

fn expectedQualifyingSetCount(
    lane: progression.Lane,
    exercise_id: primitives.Id,
    policy: volume.CreditPolicy,
) ?u16 {
    return switch (lane.method) {
        .double_progression => |method| blk: {
            var count = method.config.workingSets;
            for (method.config.exerciseOverrides) |override| {
                if (!std.mem.eql(u8, override.exerciseId, exercise_id.bytes)) continue;
                count = override.workingSets orelse count;
                break;
            }
            break :blk if (count == 0 or !policyCountsKind(policy, "working")) 0 else count;
        },
        .rpe_top_set_backoff => |method| blk: {
            const top: u16 = @intFromBool(policyCountsKind(policy, "top"));
            const backoff = if (policyCountsKind(policy, "backoff"))
                method.config.backoff.setCount
            else
                0;
            break :blk std.math.add(u16, top, backoff) catch null;
        },
    };
}

fn policyCountsKind(policy: volume.CreditPolicy, kind: []const u8) bool {
    for (policy.qualifying_set_kinds) |candidate| {
        if (std.mem.eql(u8, candidate.bytes, kind)) return true;
    }
    return false;
}

fn matchesPlannerOnlyRequirements(exercise: training.Exercise, requirements: model.SlotRequirements) bool {
    if (containsId(requirements.excluded_exercise_ids, exercise.id)) return false;
    return matchAllRequirement(exercise, requirements.muscles, .muscle) and
        matchAllRequirement(exercise, requirements.movement_patterns, .movement) and
        matchAllRequirement(exercise, requirements.exercise_families, .family) and
        matchRequirement(exercise, requirements.equipment, .equipment);
}

fn matchAllRequirement(exercise: training.Exercise, requirement: model.IdRequirement, taxonomy: Taxonomy) bool {
    return requirement.mode == .any or matchRequirement(exercise, requirement, taxonomy);
}

const Taxonomy = enum { muscle, movement, family, equipment };

fn matchRequirement(exercise: training.Exercise, requirement: model.IdRequirement, taxonomy: Taxonomy) bool {
    if (requirement.ids.len == 0) return true;
    return switch (requirement.mode) {
        .any => for (requirement.ids) |id| {
            if (exerciseHas(exercise, id, taxonomy)) break true;
        } else false,
        .all => for (requirement.ids) |id| {
            if (!exerciseHas(exercise, id, taxonomy)) break false;
        } else true,
    };
}

fn exerciseHas(exercise: training.Exercise, id: primitives.Id, taxonomy: Taxonomy) bool {
    return switch (taxonomy) {
        .muscle => for (exercise.muscle_contributions) |entry| {
            if (entry.muscle_id.eql(id)) break true;
        } else false,
        .movement => exercise_knowledge.hasMovementPattern(exercise, id.bytes),
        .family => hasFamily(exercise, id),
        .equipment => hasEquipment(exercise, id),
    };
}

fn hasFamily(exercise: training.Exercise, id: primitives.Id) bool {
    if (containsId(exercise.family_ids, id)) return true;
    if (exercise.knowledge) |knowledge| if (knowledge.familyId) |family|
        return std.mem.eql(u8, family, id.bytes);
    return false;
}

fn hasEquipment(exercise: training.Exercise, id: primitives.Id) bool {
    if (containsId(exercise.equipment_ids, id)) return true;
    if (exercise.knowledge) |knowledge| for (knowledge.equipmentRequirements) |requirement| {
        if (std.mem.eql(u8, requirement.equipmentId, id.bytes) or
            (requirement.equipmentFamilyId != null and
                std.mem.eql(u8, requirement.equipmentFamilyId.?, id.bytes))) return true;
    };
    return false;
}

fn exerciseSetContains(exercise: training.Exercise, set: model.ExerciseSet) bool {
    return containsId(set.exercise_ids, exercise.id) or hasAnyFamily(exercise, set.family_ids);
}

fn containsId(ids: []const primitives.Id, target: primitives.Id) bool {
    for (ids) |id| if (id.eql(target)) return true;
    return false;
}

fn hasAnyFamily(exercise: training.Exercise, ids: []const primitives.Id) bool {
    for (ids) |id| if (hasFamily(exercise, id)) return true;
    return false;
}

fn hasAnyMovement(exercise: training.Exercise, ids: []const primitives.Id) bool {
    for (ids) |id| if (exercise_knowledge.hasMovementPattern(exercise, id.bytes)) return true;
    return false;
}

fn hasAnyRestriction(exercise: training.Exercise, ids: []const primitives.Id) bool {
    for (ids) |id| if (exercise_knowledge.hasRestriction(exercise, id.bytes)) return true;
    return false;
}

fn hasAnyEquipment(exercise: training.Exercise, ids: []const primitives.Id) bool {
    for (ids) |id| if (hasEquipment(exercise, id)) return true;
    return false;
}

fn localScore(problem: model.PlanningProblem, slot: model.Slot, exercise: training.Exercise) SolveError!model.ScoreVector {
    var score: model.ScoreVector = .{};
    if (slot.selection == .adaptive and exerciseSetContains(exercise, slot.selection.adaptive.preferred))
        score.preference = 1;
    for (problem.objectives) |objective| switch (objective) {
        .muscle_priority => |value| if (exerciseHas(exercise, value.muscle_id, .muscle))
            try addScore(&score.training, value.weight),
        .exercise_preference => |value| {
            const matches = switch (value.target) {
                .exercise => |id| exercise.id.eql(id),
                .family => |id| hasFamily(exercise, id),
            };
            if (matches) try addSignedScore(
                &score.preference,
                value.weight,
                value.direction == .prefer,
            );
        },
        else => {},
    };
    return score;
}

fn addScore(target: *i64, value: anytype) SolveError!void {
    target.* = std.math.add(i64, target.*, @intCast(value)) catch return error.ScoreOverflow;
}

fn addSignedScore(target: *i64, value: anytype, positive: bool) SolveError!void {
    const signed: i64 = @intCast(value);
    target.* = if (positive)
        std.math.add(i64, target.*, signed) catch return error.ScoreOverflow
    else
        std.math.sub(i64, target.*, signed) catch return error.ScoreOverflow;
}

fn durationFor(problem: model.PlanningProblem, slot_id: primitives.Id, exercise_id: primitives.Id) ?u16 {
    for (problem.duration_estimates) |estimate| {
        if (estimate.slot_id.eql(slot_id) and estimate.exercise_id.eql(exercise_id))
            return estimate.minutes;
    }
    return null;
}

fn proveCheapContradictions(
    problem: model.PlanningProblem,
    workspace: *Workspace,
    violation_count: *usize,
) SolveError!void {
    var required_slot_count: usize = 0;
    var possible_slot_count: usize = 0;
    var minimum_known_minutes: u32 = 0;
    for (problem.slots, 0..) |slot, slot_index| {
        const range = workspace.ranges[slot_index];
        if (range.eligible_count != 0) possible_slot_count += 1;
        if (slot.presence == .optional) continue;
        required_slot_count += 1;
        if (range.eligible_count == 0) {
            if (firstSlotVolumeConflict(problem, slot)) |conflict| {
                appendViolation(workspace, violation_count, .{ .volume_cap_prevents_required_slot = .{
                    .slot_id = slot.id,
                    .muscle_id = conflict.muscle_id,
                    .current = conflict.current,
                    .proposed = conflict.proposed,
                    .hard_cap = conflict.hard_cap,
                } });
            } else appendViolation(workspace, violation_count, .{
                .required_slot_has_no_eligible_candidate = slot.id,
            });
        }
        // A retained top-K is not a proof over the full candidate universe.
        // Only derive a duration lower bound when no eligible candidate was
        // truncated for this slot.
        if (problem.constraints.hard_maximum_minutes != null and
            range.retained_count != 0 and range.eligible_count == range.retained_count)
        {
            var minimum: ?u16 = null;
            for (workspace.candidates[range.offset .. range.offset + range.retained_count]) |candidate| {
                const exercise = problem.catalog.exercises[candidate.exercise_index];
                const duration = durationFor(problem, slot.id, exercise.id) orelse 0;
                if (minimum == null or duration < minimum.?) minimum = duration;
            }
            minimum_known_minutes = std.math.add(u32, minimum_known_minutes, minimum orelse 0) catch
                return error.ScoreOverflow;
        }
    }
    if (problem.constraints.maximum_exercises) |maximum| if (required_slot_count > maximum)
        appendViolation(workspace, violation_count, .maximum_exercise_count_below_required);
    if (problem.constraints.minimum_exercises) |minimum| if (possible_slot_count < minimum)
        appendViolation(workspace, violation_count, .minimum_exercise_count_unreachable);
    if (problem.constraints.hard_maximum_minutes) |maximum| if (minimum_known_minutes > maximum)
        appendViolation(workspace, violation_count, .known_minimum_duration_exceeds_maximum);

    for (problem.constraints.required_exercise_ids) |required| {
        var assignable = false;
        const exercise = problem.catalog.find(required);
        if (exercise) |candidate| for (problem.slots) |slot| {
            if (candidateEligible(problem, slot, candidate.*)) assignable = true;
            if (assignable) break;
        };
        if (!assignable) appendViolation(workspace, violation_count, .{ .required_exercise_cannot_be_assigned = required });
    }

    for (problem.slots, 0..) |slot, index| workspace.current[index] = if (slot.presence == .required and
        workspace.ranges[index].retained_count != 0) workspace.ranges[index].offset else null;
    if (!orderingFeasible(problem, workspace.current, workspace.order_indices, workspace.in_degrees))
        appendViolation(workspace, violation_count, .ordering_cycle);
}

fn firstSlotVolumeConflict(
    problem: model.PlanningProblem,
    slot: model.Slot,
) ?volume.CapConflict {
    for (problem.catalog.exercises) |exercise| {
        if (!candidateEligibleWithoutVolume(problem, slot, exercise)) continue;
        if (candidateVolumeConflict(problem, slot, exercise)) |conflict| return conflict;
    }
    return null;
}

fn appendViolation(workspace: *Workspace, count: *usize, value: model.InfeasibilityViolation) void {
    std.debug.assert(count.* < workspace.violations.len);
    workspace.violations[count.*] = value;
    count.* += 1;
}

fn anyCandidateRangeTruncated(ranges: []const CandidateRange) bool {
    for (ranges) |range| if (range.eligible_count > range.retained_count) return true;
    return false;
}

fn mapDigitsToAssignment(problem: model.PlanningProblem, workspace: *Workspace) void {
    for (workspace.slot_order[0..problem.slots.len], 0..) |slot_index, canonical_index| {
        const range = workspace.ranges[slot_index];
        const digit = workspace.digits[canonical_index];
        workspace.current[slot_index] = if (digit < range.retained_count)
            range.offset + digit
        else
            null;
    }
}

fn incrementDigits(problem: model.PlanningProblem, workspace: *Workspace) bool {
    var position = problem.slots.len;
    while (position > 0) {
        position -= 1;
        const slot_index = workspace.slot_order[position];
        const range = workspace.ranges[slot_index];
        const choices = range.retained_count + @intFromBool(problem.slots[slot_index].presence == .optional);
        workspace.digits[position] += 1;
        if (workspace.digits[position] < choices) return true;
        workspace.digits[position] = 0;
    }
    return false;
}

fn assignmentScore(
    problem: model.PlanningProblem,
    candidates: []const Candidate,
    assignment: []const ?usize,
    order_storage: []usize,
    degree_storage: []u8,
) SolveError!?model.ScoreVector {
    var count: usize = 0;
    var duration: u32 = 0;
    var any_unknown_duration = false;
    var score: model.ScoreVector = .{};
    for (problem.slots, 0..) |slot, slot_index| {
        const candidate_index = assignment[slot_index] orelse {
            if (slot.presence == .required) return null;
            continue;
        };
        const candidate = candidates[candidate_index];
        count += 1;
        try addVector(&score, candidate.local_score);
        if (slot.presence == .optional) {
            // Lower tiers order earlier and represent higher program priority.
            // Rewarding retained optional slots in the program score ensures
            // hard-budget reductions keep the most important coherent work.
            try addScore(&score.program, @as(u64, 256) - slot.ordering.priority_tier);
        }
        const exercise = problem.catalog.exercises[candidate.exercise_index];
        if (durationFor(problem, slot.id, exercise.id)) |minutes|
            duration = std.math.add(u32, duration, minutes) catch return error.ScoreOverflow
        else
            any_unknown_duration = true;
    }
    if (problem.constraints.minimum_exercises) |minimum| if (count < minimum) return null;
    if (problem.constraints.maximum_exercises) |maximum| if (count > maximum) return null;
    if (problem.constraints.hard_maximum_minutes) |maximum| {
        if (duration > maximum or
            (any_unknown_duration and problem.constraints.unknown_duration_policy == .reject)) return null;
    }
    for (problem.constraints.required_exercise_ids) |required| {
        for (assignment) |candidate_index| {
            const absolute = candidate_index orelse continue;
            const candidate = candidates[absolute];
            if (problem.catalog.exercises[candidate.exercise_index].id.eql(required)) break;
        } else return null;
    }
    if (!orderingFeasible(problem, assignment, order_storage, degree_storage)) return null;

    for (problem.objectives) |objective| switch (objective) {
        .avoid_exercise_reuse => |value| {
            var duplicates: u32 = 0;
            for (assignment, 0..) |left_absolute, left_index| {
                const left = left_absolute orelse continue;
                const left_candidate = candidates[left];
                for (assignment[0..left_index]) |right_absolute| {
                    const right = right_absolute orelse continue;
                    const right_candidate = candidates[right];
                    if (problem.catalog.exercises[left_candidate.exercise_index].id.eql(
                        problem.catalog.exercises[right_candidate.exercise_index].id,
                    )) duplicates += 1;
                }
            }
            try addSignedScore(&score.training, @as(u64, duplicates) * value.weight, false);
        },
        .movement_variety => |value| {
            const unique = uniqueMovementCount(problem, candidates, assignment);
            try addScore(&score.training, @as(u64, unique) * value.weight);
        },
        .minimize_equipment_transitions => |value| {
            const transitions = equipmentTransitions(problem, candidates, assignment, order_storage[0..count]);
            try addSignedScore(&score.preference, @as(u64, transitions) * value.weight, false);
        },
        .target_duration => |value| if (!any_unknown_duration) {
            const difference = if (duration > value.minutes) duration - value.minutes else value.minutes - duration;
            try addSignedScore(&score.training, @as(u64, difference) * value.weight, false);
        },
        else => {},
    };
    return score;
}

fn addVector(target: *model.ScoreVector, contribution: model.ScoreVector) SolveError!void {
    target.program = std.math.add(i64, target.program, contribution.program) catch return error.ScoreOverflow;
    target.training = std.math.add(i64, target.training, contribution.training) catch return error.ScoreOverflow;
    target.preference = std.math.add(i64, target.preference, contribution.preference) catch return error.ScoreOverflow;
}

fn orderingFeasible(
    problem: model.PlanningProblem,
    assignment: []const ?usize,
    order_storage: []usize,
    degree_storage: []u8,
) bool {
    @memset(degree_storage[0..problem.slots.len], 0);
    var selected_count: usize = 0;
    for (assignment, 0..) |candidate, index| if (candidate != null) {
        order_storage[selected_count] = index;
        selected_count += 1;
    };
    for (problem.slots, 0..) |slot, from| {
        if (assignment[from] == null) continue;
        for (slot.ordering.before_slot_ids) |target_id| {
            const target = findSlotIndex(problem.slots, target_id).?;
            if (assignment[target] != null) degree_storage[target] += 1;
        }
        for (slot.ordering.after_slot_ids) |source_id| {
            const source = findSlotIndex(problem.slots, source_id).?;
            if (assignment[source] != null) degree_storage[from] += 1;
        }
    }
    var output_count: usize = 0;
    while (output_count < selected_count) {
        var best: ?usize = null;
        for (problem.slots, 0..) |slot, index| {
            if (assignment[index] == null or degree_storage[index] != 0) continue;
            var already_output = false;
            for (order_storage[0..output_count]) |done| if (done == index) {
                already_output = true;
                break;
            };
            if (already_output) continue;
            if (best == null or slotComesFirst(slot, problem.slots[best.?])) best = index;
        }
        const next = best orelse return false;
        order_storage[output_count] = next;
        output_count += 1;
        const slot = problem.slots[next];
        for (slot.ordering.before_slot_ids) |target_id| {
            const target = findSlotIndex(problem.slots, target_id).?;
            if (assignment[target] != null) degree_storage[target] -= 1;
        }
        for (problem.slots, 0..) |other, other_index| {
            if (assignment[other_index] == null) continue;
            for (other.ordering.after_slot_ids) |source_id| if (source_id.eql(slot.id)) {
                degree_storage[other_index] -= 1;
                break;
            };
        }
    }
    return true;
}

fn slotComesFirst(left: model.Slot, right: model.Slot) bool {
    if (left.ordering.priority_tier != right.ordering.priority_tier)
        return left.ordering.priority_tier < right.ordering.priority_tier;
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}

fn uniqueMovementCount(
    problem: model.PlanningProblem,
    candidates: []const Candidate,
    assignment: []const ?usize,
) usize {
    var count: usize = 0;
    for (assignment, 0..) |absolute, slot_index| {
        const candidate = candidates[absolute orelse continue];
        const exercise = problem.catalog.exercises[candidate.exercise_index];
        const patterns = if (exercise.knowledge) |knowledge| knowledge.movementPatterns else blk: {
            break :blk &.{};
        };
        for (patterns) |pattern| {
            var seen = false;
            for (assignment[0..slot_index], 0..) |prior_absolute, prior_slot_index| {
                _ = prior_slot_index;
                const prior = candidates[prior_absolute orelse continue];
                if (exercise_knowledge.hasMovementPattern(
                    problem.catalog.exercises[prior.exercise_index],
                    pattern,
                )) {
                    seen = true;
                    break;
                }
            }
            if (!seen) count += 1;
        }
        if (patterns.len == 0) for (exercise.movement_tags) |pattern| {
            var seen = false;
            for (assignment[0..slot_index], 0..) |prior_absolute, prior_slot_index| {
                _ = prior_slot_index;
                const prior = candidates[prior_absolute orelse continue];
                if (exercise_knowledge.hasMovementPattern(
                    problem.catalog.exercises[prior.exercise_index],
                    pattern.bytes,
                )) {
                    seen = true;
                    break;
                }
            }
            if (!seen) count += 1;
        };
    }
    return count;
}

fn equipmentTransitions(
    problem: model.PlanningProblem,
    candidates: []const Candidate,
    assignment: []const ?usize,
    order: []const usize,
) usize {
    var transitions: usize = 0;
    if (order.len < 2) return 0;
    for (order[1..], 1..) |slot_index, position| {
        const prior_slot = order[position - 1];
        const left = candidates[assignment[prior_slot].?];
        const right = candidates[assignment[slot_index].?];
        if (!sameEquipment(
            problem.catalog.exercises[left.exercise_index],
            problem.catalog.exercises[right.exercise_index],
        )) transitions += 1;
    }
    return transitions;
}

fn sameEquipment(left: training.Exercise, right: training.Exercise) bool {
    return equipmentSubset(left, right) and equipmentSubset(right, left);
}

fn equipmentSubset(left: training.Exercise, right: training.Exercise) bool {
    var has_structured_required = false;
    if (left.knowledge) |knowledge| for (knowledge.equipmentRequirements) |requirement| {
        if (requirement.requirement != .required) continue;
        has_structured_required = true;
        const id = primitives.Id.parse(requirement.equipmentId) catch return false;
        if (!hasRequiredEquipment(right, id)) return false;
    };
    if (!has_structured_required)
        for (left.equipment_ids) |id| if (!hasRequiredEquipment(right, id)) return false;
    return true;
}

fn hasRequiredEquipment(exercise: training.Exercise, id: primitives.Id) bool {
    var has_structured_required = false;
    if (exercise.knowledge) |knowledge| for (knowledge.equipmentRequirements) |requirement| {
        if (requirement.requirement != .required) continue;
        has_structured_required = true;
        if (std.mem.eql(u8, requirement.equipmentId, id.bytes)) return true;
    };
    return !has_structured_required and containsId(exercise.equipment_ids, id);
}

fn buildResolvedPlan(
    problem: model.PlanningProblem,
    options: model.SolveOptions,
    workspace: *Workspace,
    score: model.ScoreVector,
    explored: u32,
) SolveError!model.ResolvedSessionPlan {
    if (!orderingFeasible(problem, workspace.best, workspace.order_indices, workspace.in_degrees))
        unreachable;
    var selected_count: usize = 0;
    for (workspace.best) |candidate| {
        if (candidate != null) selected_count += 1;
    }
    var reason_count: usize = 0;
    var reason_ref_count: usize = 0;
    var alternative_count: usize = 0;
    for (workspace.order_indices[0..selected_count], 0..) |slot_index, position| {
        const slot = problem.slots[slot_index];
        const selected_candidate_index = workspace.best[slot_index].?;
        const candidate = workspace.candidates[selected_candidate_index];
        const exercise = problem.catalog.exercises[candidate.exercise_index];
        workspace.reasons[reason_count] = .{
            .code = if (slot.selection == .fixed) .fixed_exercise_selected else .optimized_exercise_selected,
            .subject = .{ .selection = .{ .slot_id = slot.id, .exercise_id = exercise.id } },
            .contribution = candidate.local_score,
        };
        workspace.reason_refs[reason_ref_count] = @intCast(reason_count);
        const alternatives_start = alternative_count;
        const range = workspace.ranges[slot_index];
        for (workspace.candidates[range.offset .. range.offset + range.retained_count], range.offset..) |alternative, candidate_index| {
            if (candidate_index == selected_candidate_index) continue;
            const alternative_exercise = problem.catalog.exercises[alternative.exercise_index];
            workspace.alternatives[alternative_count] = .{
                .exercise_id = alternative_exercise.id,
                .local_rank = alternative.local_rank,
                .estimated_duration_minutes = durationFor(problem, slot.id, alternative_exercise.id),
                .score = alternative.local_score,
                .ranked_lower_because = switch (model.ScoreVector.order(
                    alternative.local_score,
                    candidate.local_score,
                )) {
                    .lt => .lower_score,
                    .eq => .deterministic_tie_break,
                    .gt => .global_assignment_tradeoff,
                },
            };
            alternative_count += 1;
        }
        workspace.resolved_slots[position] = .{
            .slot_id = slot.id,
            .exercise_id = exercise.id,
            .progression = slot.progression,
            .position = @intCast(position),
            .selection_source = switch (slot.selection) {
                .fixed => .fixed,
                .adaptive => .{ .optimized = .{
                    .eligible_candidate_count = workspace.ranges[slot_index].eligible_count,
                    .local_rank = candidate.local_rank,
                } },
            },
            .estimated_duration_minutes = durationFor(problem, slot.id, exercise.id),
            .score = candidate.local_score,
            .reason_refs = workspace.reason_refs[reason_ref_count .. reason_ref_count + 1],
            .alternatives = workspace.alternatives[alternatives_start..alternative_count],
        };
        reason_count += 1;
        reason_ref_count += 1;
    }
    var omitted_count: usize = 0;
    for (workspace.slot_order[0..problem.slots.len]) |slot_index| {
        if (workspace.best[slot_index] != null) continue;
        const slot = problem.slots[slot_index];
        workspace.reasons[reason_count] = .{
            .code = .optional_slot_omitted,
            .subject = .{ .slot = slot.id },
        };
        workspace.reason_refs[reason_ref_count] = @intCast(reason_count);
        workspace.omitted_slots[omitted_count] = .{
            .slot_id = slot.id,
            .reason = if (workspace.ranges[slot_index].eligible_count == 0)
                .no_eligible_candidate
            else
                .optimizer_tradeoff,
            .reason_refs = workspace.reason_refs[reason_ref_count .. reason_ref_count + 1],
        };
        reason_count += 1;
        reason_ref_count += 1;
        omitted_count += 1;
    }
    workspace.reasons[reason_count] = .{ .code = .session_constraints_satisfied, .subject = .session };
    reason_count += 1;
    const metrics = planMetrics(
        problem,
        workspace.candidates,
        workspace.best,
        workspace.order_indices[0..selected_count],
    );
    var required_slot_count: usize = 0;
    for (problem.slots) |slot| if (slot.presence == .required) {
        required_slot_count += 1;
    };
    return .{
        .origin = problem.origin,
        .planner = provenance(options, explored),
        .problem_fingerprint = &workspace.fingerprint_storage,
        .slots = workspace.resolved_slots[0..selected_count],
        .omitted_slots = workspace.omitted_slots[0..omitted_count],
        .score = score,
        .metrics = metrics,
        .workload = .{
            .required_slot_count = @intCast(required_slot_count),
            .target_slot_count = @intCast(problem.slots.len),
            .optional_slot_count = @intCast(problem.slots.len - required_slot_count),
            .composed_slot_count = @intCast(selected_count),
            .omitted_optional_slot_count = @intCast(omitted_count),
        },
        .reasons = workspace.reasons[0..reason_count],
    };
}

fn planMetrics(
    problem: model.PlanningProblem,
    candidates: []const Candidate,
    assignment: []const ?usize,
    order: []const usize,
) model.PlanMetrics {
    var duration: u32 = 0;
    var known = true;
    for (assignment, 0..) |absolute, slot_index| {
        const candidate = candidates[absolute orelse continue];
        const exercise = problem.catalog.exercises[candidate.exercise_index];
        if (durationFor(problem, problem.slots[slot_index].id, exercise.id)) |minutes|
            duration += minutes
        else
            known = false;
    }
    return .{
        .exercise_count = @intCast(order.len),
        .estimated_duration_minutes = if (known) @intCast(duration) else null,
        .equipment_transition_count = @intCast(equipmentTransitions(problem, candidates, assignment, order)),
    };
}

fn resolvedPlanHardConstraints(problem: model.PlanningProblem, slots: []const model.ResolvedSlot) bool {
    if (problem.constraints.minimum_exercises) |minimum| if (slots.len < minimum) return false;
    if (problem.constraints.maximum_exercises) |maximum| if (slots.len > maximum) return false;
    var duration: u32 = 0;
    for (slots) |slot| {
        if (durationFor(problem, slot.slot_id, slot.exercise_id)) |minutes|
            duration += minutes
        else if (problem.constraints.unknown_duration_policy == .reject)
            return false;
    }
    if (problem.constraints.hard_maximum_minutes) |maximum| if (duration > maximum) return false;
    for (problem.constraints.required_exercise_ids) |required| {
        for (slots) |slot| if (slot.exercise_id.eql(required)) break else {} else return false;
    }
    for (problem.slots) |slot| {
        const from_position = resolvedPosition(slots, slot.id) orelse continue;
        for (slot.ordering.before_slot_ids) |target| {
            if (resolvedPosition(slots, target)) |target_position| if (from_position >= target_position) return false;
        }
        for (slot.ordering.after_slot_ids) |source| {
            if (resolvedPosition(slots, source)) |source_position| if (from_position <= source_position) return false;
        }
    }
    return true;
}

fn findResolved(slots: []const model.ResolvedSlot, id: primitives.Id) ?model.ResolvedSlot {
    for (slots) |slot| if (slot.slot_id.eql(id)) return slot;
    return null;
}

fn findOmitted(slots: []const model.OmittedSlot, id: primitives.Id) ?model.OmittedSlot {
    for (slots) |slot| if (slot.slot_id.eql(id)) return slot;
    return null;
}

fn resolvedPosition(slots: []const model.ResolvedSlot, id: primitives.Id) ?usize {
    for (slots, 0..) |slot, index| if (slot.slot_id.eql(id)) return index;
    return null;
}

fn findSlotIndex(slots: []const model.Slot, id: primitives.Id) ?usize {
    for (slots, 0..) |slot, index| if (slot.id.eql(id)) return index;
    return null;
}

fn sameOrigin(left: model.Origin, right: model.Origin) bool {
    return left.definition_id.eql(right.definition_id) and
        left.definition_version == right.definition_version and
        std.mem.eql(u8, left.definition_fingerprint, right.definition_fingerprint) and
        left.instance_id.eql(right.instance_id) and left.occurrence_id.eql(right.occurrence_id) and
        left.block_id.eql(right.block_id) and left.role_id.eql(right.role_id) and
        left.planning_state_revision == right.planning_state_revision and left.strategy == right.strategy;
}

fn fingerprintProblem(problem: model.PlanningProblem, out: *[64]u8) void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("caudex:planning-problem:v1\x00");
    updateBytes(&hash, problem.origin.definition_id.bytes);
    updateU64(&hash, problem.origin.definition_version);
    updateBytes(&hash, problem.origin.definition_fingerprint);
    updateBytes(&hash, problem.origin.instance_id.bytes);
    updateBytes(&hash, problem.origin.occurrence_id.bytes);
    updateBytes(&hash, problem.origin.block_id.bytes);
    updateBytes(&hash, problem.origin.role_id.bytes);
    updateU64(&hash, problem.origin.planning_state_revision);
    updateBytes(&hash, @tagName(problem.origin.strategy));
    updateBytes(&hash, problem.as_of.bytes);
    aggregateEntities(&hash, problem.catalog.exercises, fingerprintExercise);
    aggregateEntities(&hash, problem.slots, fingerprintSlot);
    fingerprintConstraints(&hash, problem.constraints);
    aggregateEntities(&hash, problem.objectives, fingerprintObjective);
    aggregateEntities(&hash, problem.duration_estimates, fingerprintDuration);
    if (problem.volume_context) |context| fingerprintVolumeContext(&hash, context) else hash.update("no-volume-context");
    finishHex(&hash, out);
}

fn fingerprintVolumeContext(
    hash: *std.crypto.hash.sha2.Sha256,
    context: model.VolumeContext,
) void {
    updateBytes(hash, context.policy.id.bytes);
    updateU64(hash, context.policy.version);
    updateBytes(hash, @tagName(context.policy.mode));
    updateU64(hash, context.policy.primary_credit);
    updateU64(hash, context.policy.secondary_credit);
    updateU64(hash, context.policy.stabilizer_credit);
    updateU64(hash, context.policy.custom_credit);
    updateU64(hash, @intFromBool(context.policy.count_partial));
    updateU64(hash, @intFromBool(context.policy.count_failed));
    aggregateIds(hash, context.policy.qualifying_set_kinds);
    updateU64(hash, context.policy.maximum_credit_per_muscle_per_set);
    switch (context.state.scope) {
        .all_history => hash.update("all-history"),
        .interval => |interval| {
            hash.update("interval");
            updateBytes(hash, interval.from.bytes);
            updateBytes(hash, interval.through.bytes);
        },
        .program_window => |window| {
            hash.update("program-window");
            updateBytes(hash, window.instance_id.bytes);
            updateBytes(hash, window.block_id.bytes);
            updateU64(hash, window.microcycle_index);
        },
    }
    aggregateEntities(hash, context.state.muscles, fingerprintVolumeObservation);
}

fn fingerprintVolumeObservation(
    hash: *std.crypto.hash.sha2.Sha256,
    observation: volume.Observation,
) void {
    updateBytes(hash, observation.muscle_id.bytes);
    updateU64(hash, observation.completed_credit);
    updateOptionalU64(hash, observation.remaining.required);
    updateOptionalU64(hash, observation.remaining.preferred);
    updateOptionalU64(hash, observation.remaining.maximum_additional);
    if (observation.target) |target| {
        updateOptionalU64(hash, target.hard_cap);
        updateOptionalU64(hash, target.priority_weight);
    } else hash.update("no-target");
}

fn aggregateEntities(hash: *std.crypto.hash.sha2.Sha256, values: anytype, comptime fingerprint: anytype) void {
    var xor: [32]u8 = @splat(0);
    var sum: [32]u8 = @splat(0);
    for (values) |value| {
        var item_hash = std.crypto.hash.sha2.Sha256.init(.{});
        fingerprint(&item_hash, value);
        var digest: [32]u8 = undefined;
        item_hash.final(&digest);
        var carry: u16 = 0;
        var index: usize = 32;
        while (index > 0) {
            index -= 1;
            xor[index] ^= digest[index];
            const total: u16 = @as(u16, sum[index]) + digest[index] + carry;
            sum[index] = @truncate(total);
            carry = total >> 8;
        }
    }
    updateU64(hash, values.len);
    hash.update(&xor);
    hash.update(&sum);
}

fn fingerprintExercise(hash: *std.crypto.hash.sha2.Sha256, exercise: training.Exercise) void {
    updateBytes(hash, exercise.id.bytes);
    aggregateIds(hash, exercise.family_ids);
    aggregateIds(hash, exercise.equipment_ids);
    aggregateIds(hash, exercise.movement_tags);
    if (exercise.knowledge) |knowledge| {
        updateOptionalBytes(hash, knowledge.familyId);
        aggregateStrings(hash, knowledge.movementPatterns);
        aggregateStrings(hash, knowledge.restrictionTags);
        aggregateEntities(hash, knowledge.equipmentRequirements, fingerprintEquipmentRequirement);
        if (knowledge.progressionCapabilities) |capabilities| {
            const values = [_]?bool{ capabilities.externalLoad, capabilities.repetitions, capabilities.duration, capabilities.distance };
            for (values) |value| hash.update(if (value == null) "?" else if (value.?) "1" else "0");
        }
    }
    aggregateEntities(hash, exercise.muscle_contributions, fingerprintMuscleContribution);
}

fn fingerprintEquipmentRequirement(
    hash: *std.crypto.hash.sha2.Sha256,
    requirement: @import("../canonical.zig").EquipmentRequirement,
) void {
    updateBytes(hash, requirement.equipmentId);
    updateOptionalBytes(hash, requirement.equipmentFamilyId);
    updateBytes(hash, @tagName(requirement.requirement));
    updateOptionalBytes(hash, requirement.alternativeGroup);
}

fn fingerprintMuscleContribution(
    hash: *std.crypto.hash.sha2.Sha256,
    contribution: training.MuscleContribution,
) void {
    updateBytes(hash, contribution.muscle_id.bytes);
    updateBytes(hash, @tagName(contribution.role));
    if (contribution.weight) |weight| {
        updateU64(hash, @as(u64, @bitCast(weight.mantissa)));
        updateU64(hash, weight.scale);
    } else hash.update("no-weight");
}

fn fingerprintSlot(hash: *std.crypto.hash.sha2.Sha256, slot: model.Slot) void {
    updateBytes(hash, slot.id.bytes);
    updateBytes(hash, @tagName(slot.presence));
    switch (slot.selection) {
        .fixed => |id| updateBytes(hash, id.bytes),
        .adaptive => |adaptive| {
            switch (adaptive.universe) {
                .catalog => hash.update("catalog"),
                .allowlist => |set| fingerprintExerciseSet(hash, set),
            }
            fingerprintExerciseSet(hash, adaptive.preferred);
            fingerprintRequirement(hash, adaptive.requirements.muscles);
            fingerprintRequirement(hash, adaptive.requirements.movement_patterns);
            fingerprintRequirement(hash, adaptive.requirements.exercise_families);
            fingerprintRequirement(hash, adaptive.requirements.equipment);
            aggregateIds(hash, adaptive.requirements.excluded_exercise_ids);
        },
    }
    updateBytes(hash, slot.progression.state_id.bytes);
    updateBytes(hash, slot.progression.method.id());
    updateU64(hash, slot.ordering.priority_tier);
    aggregateIds(hash, slot.ordering.before_slot_ids);
    aggregateIds(hash, slot.ordering.after_slot_ids);
}

fn fingerprintExerciseSet(hash: *std.crypto.hash.sha2.Sha256, set: model.ExerciseSet) void {
    aggregateIds(hash, set.exercise_ids);
    aggregateIds(hash, set.family_ids);
}

fn fingerprintRequirement(hash: *std.crypto.hash.sha2.Sha256, requirement: model.IdRequirement) void {
    updateBytes(hash, @tagName(requirement.mode));
    aggregateIds(hash, requirement.ids);
}

fn fingerprintConstraints(hash: *std.crypto.hash.sha2.Sha256, constraints: model.SessionConstraints) void {
    aggregateIds(hash, constraints.available_equipment_ids);
    aggregateIds(hash, constraints.required_exercise_ids);
    aggregateIds(hash, constraints.excluded_exercise_ids);
    aggregateIds(hash, constraints.excluded_family_ids);
    aggregateIds(hash, constraints.excluded_movement_pattern_ids);
    aggregateIds(hash, constraints.excluded_restriction_tag_ids);
    aggregateIds(hash, constraints.excluded_equipment_ids);
    updateOptionalU64(hash, constraints.minimum_exercises);
    updateOptionalU64(hash, constraints.maximum_exercises);
    updateOptionalU64(hash, constraints.hard_maximum_minutes);
    updateBytes(hash, @tagName(constraints.unknown_duration_policy));
}

fn fingerprintObjective(hash: *std.crypto.hash.sha2.Sha256, objective: model.Objective) void {
    updateBytes(hash, @tagName(objective));
    switch (objective) {
        .muscle_priority => |value| {
            updateBytes(hash, value.muscle_id.bytes);
            updateU64(hash, value.weight);
        },
        .exercise_preference => |value| {
            updateBytes(hash, @tagName(value.target));
            switch (value.target) {
                inline else => |id| updateBytes(hash, id.bytes),
            }
            updateBytes(hash, @tagName(value.direction));
            updateU64(hash, value.weight);
        },
        .target_duration => |value| {
            updateU64(hash, value.minutes);
            updateU64(hash, value.weight);
        },
        inline else => |value| updateU64(hash, value.weight),
    }
}

fn fingerprintDuration(hash: *std.crypto.hash.sha2.Sha256, estimate: model.DurationEstimate) void {
    updateBytes(hash, estimate.slot_id.bytes);
    updateBytes(hash, estimate.exercise_id.bytes);
    updateU64(hash, estimate.minutes);
}

fn aggregateIds(hash: *std.crypto.hash.sha2.Sha256, ids: []const primitives.Id) void {
    var xor: [32]u8 = @splat(0);
    var sum: [32]u8 = @splat(0);
    for (ids) |id| {
        var item_hash = std.crypto.hash.sha2.Sha256.init(.{});
        updateBytes(&item_hash, id.bytes);
        var digest: [32]u8 = undefined;
        item_hash.final(&digest);
        addDigest(&xor, &sum, digest);
    }
    updateU64(hash, ids.len);
    hash.update(&xor);
    hash.update(&sum);
}

fn aggregateStrings(hash: *std.crypto.hash.sha2.Sha256, values: []const []const u8) void {
    var xor: [32]u8 = @splat(0);
    var sum: [32]u8 = @splat(0);
    for (values) |value| {
        var item_hash = std.crypto.hash.sha2.Sha256.init(.{});
        updateBytes(&item_hash, value);
        var digest: [32]u8 = undefined;
        item_hash.final(&digest);
        addDigest(&xor, &sum, digest);
    }
    updateU64(hash, values.len);
    hash.update(&xor);
    hash.update(&sum);
}

fn addDigest(xor: *[32]u8, sum: *[32]u8, digest: [32]u8) void {
    var carry: u16 = 0;
    var index: usize = 32;
    while (index > 0) {
        index -= 1;
        xor[index] ^= digest[index];
        const total: u16 = @as(u16, sum[index]) + digest[index] + carry;
        sum[index] = @truncate(total);
        carry = total >> 8;
    }
}

fn updateBytes(hash: *std.crypto.hash.sha2.Sha256, value: []const u8) void {
    updateU64(hash, value.len);
    hash.update(value);
}

fn updateOptionalBytes(hash: *std.crypto.hash.sha2.Sha256, value: ?[]const u8) void {
    if (value) |present| {
        hash.update("1");
        updateBytes(hash, present);
    } else hash.update("0");
}

fn updateOptionalU64(hash: *std.crypto.hash.sha2.Sha256, value: anytype) void {
    if (value) |present| {
        hash.update("1");
        updateU64(hash, present);
    } else hash.update("0");
}

fn updateU64(hash: *std.crypto.hash.sha2.Sha256, value: anytype) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, @intCast(value), .big);
    hash.update(&bytes);
}

fn finishHex(hash: *std.crypto.hash.sha2.Sha256, out: *[64]u8) void {
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const alphabet = "0123456789abcdef";
    for (digest, 0..) |byte, index| {
        out[index * 2] = alphabet[byte >> 4];
        out[index * 2 + 1] = alphabet[byte & 0x0f];
    }
}

fn testId(bytes: []const u8) primitives.Id {
    return primitives.Id.parse(bytes) catch unreachable;
}

fn testLane(state_id: []const u8) progression.Lane {
    return .{
        .state_id = testId(state_id),
        .method = .{ .double_progression = .{ .config = .{
            .repRange = .{ .min = 8, .max = 12 },
            .workingSets = 3,
            .advancementCriteria = .{ .minimumSuccessfulSets = 3, .minimumRepetitions = 12 },
            .initialLoad = .{ .amount = "45", .unit = "lb" },
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
        } } },
    };
}

fn testOrigin() model.Origin {
    return .{
        .definition_id = testId("definition"),
        .definition_version = 1,
        .definition_fingerprint = "definition-fingerprint",
        .instance_id = testId("instance"),
        .occurrence_id = testId("occurrence"),
        .block_id = testId("block"),
        .role_id = testId("role"),
        .planning_state_revision = 4,
        .strategy = .adaptive_hypertrophy,
    };
}

fn testProblem(exercises: []const training.Exercise, slots: []const model.Slot) model.PlanningProblem {
    return .{
        .origin = testOrigin(),
        .as_of = primitives.Timestamp.parse("2026-08-17T12:00:00Z") catch unreachable,
        .catalog = .{ .exercises = exercises },
        .slots = slots,
    };
}

test "fixed and adaptive slots share the planner and preserve lanes" {
    const squat_family = [_]primitives.Id{testId("squat")};
    const exercises = [_]training.Exercise{
        .{ .id = testId("back-squat"), .family_ids = &squat_family },
        .{ .id = testId("goblet-squat"), .family_ids = &squat_family },
    };
    const family_requirement = [_]primitives.Id{testId("squat")};
    const slots = [_]model.Slot{
        .{ .id = testId("primary"), .selection = .{ .fixed = testId("back-squat") }, .progression = testLane("primary-lane") },
        .{ .id = testId("secondary"), .selection = .{ .adaptive = .{ .requirements = .{
            .exercise_families = .{ .ids = &family_requirement, .mode = .all },
        } } }, .progression = testLane("secondary-lane") },
    };
    const problem = testProblem(&exercises, &slots);
    var storage: FixedWorkspace = .{};
    var workspace = try storage.workspace(problem, .{});

    const result = try solve(problem, .{}, &workspace);
    const plan = result.resolved;
    try std.testing.expectEqual(@as(usize, 2), plan.slots.len);
    try std.testing.expectEqual(model.SelectionSource.fixed, plan.slots[0].selection_source);
    try std.testing.expectEqualStrings("primary-lane", plan.slots[0].progression.state_id.bytes);
    try std.testing.expectEqual(@as(u8, 2), plan.workload.required_slot_count);
    try std.testing.expectEqual(@as(u8, 2), plan.workload.target_slot_count);
    try std.testing.expectEqual(@as(u8, 2), plan.workload.composed_slot_count);
    try std.testing.expectEqual(@as(usize, 1), plan.slots[1].alternatives.len);
    try std.testing.expectEqualStrings("goblet-squat", plan.slots[1].alternatives[0].exercise_id.bytes);
    try validateResolvedPlan(problem, plan);
}

test "global search avoids the locally preferred greedy dead end" {
    const exercises = [_]training.Exercise{
        .{ .id = testId("a") },
        .{ .id = testId("b") },
    };
    const preferred = model.ExerciseSet{ .exercise_ids = &.{testId("a")} };
    const slots = [_]model.Slot{
        .{ .id = testId("flex"), .selection = .{ .adaptive = .{ .preferred = preferred } }, .progression = testLane("flex-lane") },
        .{ .id = testId("fixed"), .selection = .{ .fixed = testId("a") }, .progression = testLane("fixed-lane") },
    };
    var problem = testProblem(&exercises, &slots);
    problem.constraints.required_exercise_ids = &.{testId("b")};
    var workspace = try Workspace.init(std.testing.allocator, problem, .{ .beam_width = 16 });
    defer workspace.deinit();

    const plan = (try solve(problem, .{ .beam_width = 16 }, &workspace)).resolved;
    try std.testing.expectEqualStrings("b", findResolved(plan.slots, testId("flex")).?.exercise_id.bytes);
    try std.testing.expectEqualStrings("a", findResolved(plan.slots, testId("fixed")).?.exercise_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), findResolved(plan.slots, testId("flex")).?.alternatives.len);
}

test "optional work is explicitly omitted to satisfy hard duration" {
    const exercises = [_]training.Exercise{ .{ .id = testId("main") }, .{ .id = testId("accessory") } };
    const slots = [_]model.Slot{
        .{ .id = testId("main-slot"), .selection = .{ .fixed = testId("main") }, .progression = testLane("main-lane") },
        .{ .id = testId("accessory-slot"), .presence = .optional, .selection = .{ .fixed = testId("accessory") }, .progression = testLane("accessory-lane") },
    };
    var problem = testProblem(&exercises, &slots);
    problem.constraints.hard_maximum_minutes = 20;
    problem.duration_estimates = &.{
        .{ .slot_id = testId("main-slot"), .exercise_id = testId("main"), .minutes = 20 },
        .{ .slot_id = testId("accessory-slot"), .exercise_id = testId("accessory"), .minutes = 10 },
    };
    var workspace = try Workspace.init(std.testing.allocator, problem, .{});
    defer workspace.deinit();

    const plan = (try solve(problem, .{}, &workspace)).resolved;
    try std.testing.expectEqual(@as(usize, 1), plan.slots.len);
    try std.testing.expectEqualStrings("accessory-slot", plan.omitted_slots[0].slot_id.bytes);
    try std.testing.expectEqual(@as(u8, 1), plan.workload.required_slot_count);
    try std.testing.expectEqual(@as(u8, 2), plan.workload.target_slot_count);
    try std.testing.expectEqual(@as(u8, 1), plan.workload.omitted_optional_slot_count);
    try validateResolvedPlan(problem, plan);
}

test "proved infeasibility is distinct from bounded search exhaustion" {
    const exercises = [_]training.Exercise{ .{ .id = testId("a") }, .{ .id = testId("b") } };
    const slots = [_]model.Slot{
        .{ .id = testId("one"), .selection = .{ .adaptive = .{} }, .progression = testLane("one-lane") },
        .{ .id = testId("two"), .selection = .{ .adaptive = .{} }, .progression = testLane("two-lane") },
    };
    var exhausted_problem = testProblem(&exercises, &slots);
    exhausted_problem.constraints.required_exercise_ids = &.{ testId("a"), testId("b") };
    const tight = model.SolveOptions{ .candidate_limit_per_slot = 2, .beam_width = 1 };
    var tight_workspace = try Workspace.init(std.testing.allocator, exhausted_problem, tight);
    defer tight_workspace.deinit();
    try std.testing.expect((try solve(exhausted_problem, tight, &tight_workspace)) == .search_exhausted);

    var infeasible_problem = testProblem(&exercises, &slots);
    infeasible_problem.constraints.required_exercise_ids = &.{testId("missing")};
    var proof_workspace = try Workspace.init(std.testing.allocator, infeasible_problem, .{});
    defer proof_workspace.deinit();
    try std.testing.expect((try solve(infeasible_problem, .{}, &proof_workspace)) == .infeasible);
}

test "higher semantic score tier cannot be overpowered by a lower tier" {
    const higher = model.ScoreVector{ .program = 1, .preference = 0 };
    const lower = model.ScoreVector{ .program = 0, .preference = std.math.maxInt(i64) };
    try std.testing.expectEqual(std.math.Order.gt, model.ScoreVector.order(higher, lower));
}

test "catalog and slot permutations preserve result and fingerprint" {
    const exercises_a = [_]training.Exercise{ .{ .id = testId("b") }, .{ .id = testId("a") } };
    const exercises_b = [_]training.Exercise{ .{ .id = testId("a") }, .{ .id = testId("b") } };
    const slot_a = model.Slot{ .id = testId("a-slot"), .selection = .{ .adaptive = .{} }, .progression = testLane("a-lane") };
    const slot_b = model.Slot{ .id = testId("b-slot"), .selection = .{ .adaptive = .{} }, .progression = testLane("b-lane") };
    const slots_a = [_]model.Slot{ slot_b, slot_a };
    const slots_b = [_]model.Slot{ slot_a, slot_b };
    const first_problem = testProblem(&exercises_a, &slots_a);
    const second_problem = testProblem(&exercises_b, &slots_b);
    var first_workspace = try Workspace.init(std.testing.allocator, first_problem, .{});
    defer first_workspace.deinit();
    var second_workspace = try Workspace.init(std.testing.allocator, second_problem, .{});
    defer second_workspace.deinit();

    const first = (try solve(first_problem, .{}, &first_workspace)).resolved;
    const second = (try solve(second_problem, .{}, &second_workspace)).resolved;
    try std.testing.expectEqualStrings(first.problem_fingerprint, second.problem_fingerprint);
    try std.testing.expectEqualStrings(first.slots[0].slot_id.bytes, second.slots[0].slot_id.bytes);
    try std.testing.expectEqualStrings(first.slots[0].exercise_id.bytes, second.slots[0].exercise_id.bytes);
}
