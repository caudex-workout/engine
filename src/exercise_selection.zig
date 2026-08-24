//! Deterministic, explainable exercise selection and substitution.
//!
//! This module owns eligibility and local ranking only.  It never mutates a
//! progression lane (a substitute therefore has independent progression
//! state), composes sessions, or infers medical restrictions.

const std = @import("std");
const training = @import("training.zig");
const knowledge = @import("exercise_knowledge.zig");

pub const Id = training.Id;
pub const max_reasons = 16;
pub const max_catalog_exercises: usize = 2048;
pub const max_alternatives: usize = 64;
pub const max_rejections: usize = 64;

pub const Role = struct {
    target_muscles: []const Id = &.{},
    movement_patterns: []const Id = &.{},
    exercise_families: []const Id = &.{},
    /// A fixed exercise is a hard requirement, unlike `preferred_exercises`.
    fixed_exercise_id: ?Id = null,
    progression_requirement: ?knowledge.ProgressionRequirement = null,
    required_laterality: ?bool = null,
    required_structural_type: ?[]const u8 = null,
};

pub const Continuity = enum { dynamic, sticky, fixed, novelty_biased };

pub const Policy = struct {
    preferred_exercises: []const Id = &.{},
    disliked_exercises: []const Id = &.{},
    excluded_exercises: []const Id = &.{},
    continuity: Continuity = .dynamic,
    preferred_family_ids: []const Id = &.{},
    /// A fixed program choice may be overridden only by an eligibility
    /// conflict; the conflict is retained in the result's rejected reasons.
    dislike_penalty: i32 = 12,
    preference_bonus: i32 = 24,
    continuity_bonus: i32 = 20,
    novelty_bonus: i32 = 8,
    overlap_penalty: i32 = 18,
};

pub const Context = struct {
    available_equipment_ids: ?[]const Id = null,
    excluded_restriction_ids: []const Id = &.{},
    excluded_exercise_ids: []const Id = &.{},
    recent_exercise_ids: []const Id = &.{},
    already_selected_exercise_ids: []const Id = &.{},
    already_selected_family_ids: []const Id = &.{},
    policy: Policy = .{},
};

pub const Reason = enum {
    target_match,
    movement_match,
    family_match,
    preference,
    dislike,
    continuity,
    novelty,
    overlap,
    equipment_convenience,
    substitution_similarity,
};

pub const EligibilityReason = enum {
    excluded,
    fixed_conflict,
    equipment_unavailable,
    restriction,
    progression_incompatible,
    movement_missing,
    muscle_missing,
    family_missing,
    laterality_mismatch,
    structural_type_mismatch,
};

pub const Score = struct {
    target_match: i32 = 0,
    movement_match: i32 = 0,
    family_match: i32 = 0,
    preference: i32 = 0,
    continuity: i32 = 0,
    novelty: i32 = 0,
    overlap: i32 = 0,
    equipment_convenience: i32 = 0,
    substitution_similarity: i32 = 0,

    pub fn total(self: Score) i64 {
        return @as(i64, self.target_match) + self.movement_match + self.family_match +
            self.preference + self.continuity + self.novelty + self.overlap +
            self.equipment_convenience + self.substitution_similarity;
    }
};

pub const Candidate = struct {
    exercise: *const training.Exercise,
    score: Score,
    reasons: [max_reasons]Reason = undefined,
    reason_count: u8 = 0,

    pub fn reasonSlice(self: *const Candidate) []const Reason {
        return self.reasons[0..self.reason_count];
    }
};

pub const Rejected = struct {
    exercise: *const training.Exercise,
    reason: EligibilityReason,
};

pub const Result = struct {
    selected: ?*const Candidate,
    alternatives: []const Candidate,
    rejected: []const Rejected,
    unsatisfiable: bool,
    /// Set when a required fixed exercise is absent from the catalog.
    conflict: ?Conflict = null,
    /// Substitution preserves the role, never an exercise-local progression
    /// history or load. Hosts may deliberately route shared state separately.
    progression_state_transfer: enum { not_applicable, independent } = .not_applicable,
};

pub const Conflict = enum { fixed_exercise_missing, source_exercise_missing };

pub const Request = struct {
    role: Role,
    catalog: training.ExerciseCatalog,
    context: Context = .{},
    /// Bounds result size; rejected candidates are bounded independently.
    alternative_limit: usize = 8,
    rejection_limit: usize = 32,
};

pub const SubstitutionRequest = struct {
    exercise: Id,
    role: Role = .{},
    catalog: training.ExerciseCatalog,
    context: Context = .{},
    alternative_limit: usize = 8,
    rejection_limit: usize = 32,
};

pub const Error = error{ OutputTooSmall, LimitExceeded, InvalidPolicy };

pub fn rankExercises(
    request: Request,
    candidate_storage: []Candidate,
    rejected_storage: []Rejected,
) Error!Result {
    try validateLimits(request.catalog.exercises.len, request.alternative_limit, request.rejection_limit);
    try validatePolicy(request.context.policy);
    const requested_count = std.math.add(usize, request.alternative_limit, 1) catch std.math.maxInt(usize);
    const top_limit = @min(requested_count, candidate_storage.len);
    var count: usize = 0;
    var rejected_count: usize = 0;
    for (request.catalog.exercises) |*exercise| {
        if (eligibility(exercise.*, request.role, request.context)) |reason| {
            try insertRejected(rejected_storage, &rejected_count, request.rejection_limit, .{ .exercise = exercise, .reason = reason });
            continue;
        }
        if (top_limit == 0) return error.OutputTooSmall;
        if (count == top_limit and top_limit < requested_count) return error.OutputTooSmall;
        insertCandidate(candidate_storage[0..top_limit], &count, scoreCandidate(exercise, request.role, request.context));
    }
    const limit = @min(count, requested_count);
    const selected = if (count == 0) null else &candidate_storage[0];
    const alternatives = if (count == 0) candidate_storage[0..0] else candidate_storage[1..limit];
    const conflict = if (request.role.fixed_exercise_id != null and request.catalog.find(request.role.fixed_exercise_id.?) == null)
        Conflict.fixed_exercise_missing
    else
        null;
    return .{ .selected = selected, .alternatives = alternatives, .rejected = rejected_storage[0..rejected_count], .unsatisfiable = count == 0, .conflict = conflict };
}

pub fn findSubstitutes(
    request: SubstitutionRequest,
    candidate_storage: []Candidate,
    rejected_storage: []Rejected,
) Error!Result {
    try validateLimits(request.catalog.exercises.len, request.alternative_limit, request.rejection_limit);
    try validatePolicy(request.context.policy);
    const original = request.catalog.find(request.exercise) orelse {
        return .{
            .selected = null,
            .alternatives = candidate_storage[0..0],
            .rejected = rejected_storage[0..0],
            .unsatisfiable = true,
            .conflict = .source_exercise_missing,
            .progression_state_transfer = .independent,
        };
    };
    const requested_count = std.math.add(usize, request.alternative_limit, 1) catch std.math.maxInt(usize);
    const top_limit = @min(requested_count, candidate_storage.len);
    var kept: usize = 0;
    var rejected_count: usize = 0;
    for (request.catalog.exercises) |*exercise| {
        if (exercise.id.eql(original.id)) continue;
        if (eligibility(exercise.*, request.role, request.context)) |reason| {
            try insertRejected(rejected_storage, &rejected_count, request.rejection_limit, .{ .exercise = exercise, .reason = reason });
            continue;
        }
        if (top_limit == 0) return error.OutputTooSmall;
        if (kept == top_limit and top_limit < requested_count) return error.OutputTooSmall;
        var scored = scoreCandidate(exercise, request.role, request.context);
        const candidate = &scored;
        candidate.score.substitution_similarity = similarity(original.*, exercise.*, request.role);
        if (candidate.score.substitution_similarity != 0)
            addReason(candidate, .substitution_similarity) catch {};
        insertCandidate(candidate_storage[0..top_limit], &kept, scored);
    }
    const limit = @min(kept, requested_count);
    return .{
        .selected = if (kept == 0) null else &candidate_storage[0],
        .alternatives = if (kept == 0) candidate_storage[0..0] else candidate_storage[1..limit],
        .rejected = rejected_storage[0..rejected_count],
        .unsatisfiable = kept == 0,
        .progression_state_transfer = .independent,
    };
}

fn validateLimits(catalog_count: usize, alternative_limit: usize, rejection_limit: usize) Error!void {
    if (catalog_count > max_catalog_exercises or
        alternative_limit > max_alternatives or
        rejection_limit > max_rejections) return error.LimitExceeded;
}

fn validatePolicy(policy: Policy) Error!void {
    if (policy.dislike_penalty < 0 or policy.preference_bonus < 0 or
        policy.continuity_bonus < 0 or policy.novelty_bonus < 0 or
        policy.overlap_penalty < 0) return error.InvalidPolicy;
}

pub fn eligibility(exercise: training.Exercise, role: Role, context: Context) ?EligibilityReason {
    if (contains(context.policy.excluded_exercises, exercise.id) or contains(context.excluded_exercise_ids, exercise.id)) return .excluded;
    if (role.fixed_exercise_id) |fixed| if (!exercise.id.eql(fixed)) return .fixed_conflict;
    if (context.available_equipment_ids) |available| if (!knowledge.requiredEquipmentSatisfied(exercise, available)) return .equipment_unavailable;
    for (context.excluded_restriction_ids) |restriction| if (knowledge.hasRestriction(exercise, restriction.bytes)) return .restriction;
    if (role.progression_requirement) |requirement| if (knowledge.progressionCompatibility(exercise, requirement) == .incompatible) return .progression_incompatible;
    if (role.required_laterality) |unilateral| {
        const actual = exercise.unilateral orelse if (exercise.knowledge) |item|
            if (item.laterality) |laterality| switch (laterality) {
                .unilateral, .alternating => true,
                .bilateral, .independent_bilateral => false,
                else => return .laterality_mismatch,
            } else return .laterality_mismatch
        else
            return .laterality_mismatch;
        if (actual != unilateral) return .laterality_mismatch;
    }
    if (role.required_structural_type) |kind| {
        const actual = if (exercise.knowledge) |item| item.structuralType orelse
            return .structural_type_mismatch else return .structural_type_mismatch;
        if (!std.mem.eql(u8, @tagName(actual), kind)) return .structural_type_mismatch;
    }
    if (role.movement_patterns.len != 0 and !anyMovement(exercise, role.movement_patterns)) return .movement_missing;
    if (role.target_muscles.len != 0 and !anyMuscle(exercise, role.target_muscles)) return .muscle_missing;
    if (role.exercise_families.len != 0 and !anyFamily(exercise, role.exercise_families)) return .family_missing;
    return null;
}

fn scoreCandidate(exercise: *const training.Exercise, role: Role, context: Context) Candidate {
    var candidate = Candidate{ .exercise = exercise, .score = .{} };
    candidate.score.target_match = if (role.target_muscles.len == 0) 0 else if (anyMuscle(exercise.*, role.target_muscles)) 40 else 0;
    candidate.score.movement_match = if (role.movement_patterns.len == 0) 0 else if (anyMovement(exercise.*, role.movement_patterns)) 35 else 0;
    candidate.score.family_match = if (role.exercise_families.len == 0) 0 else if (anyFamily(exercise.*, role.exercise_families)) 25 else 0;
    if (contains(context.policy.preferred_exercises, exercise.id)) candidate.score.preference = context.policy.preference_bonus;
    if (anyFamily(exercise.*, context.policy.preferred_family_ids))
        candidate.score.preference +|= context.policy.preference_bonus;
    if (contains(context.policy.disliked_exercises, exercise.id)) candidate.score.preference -|= context.policy.dislike_penalty;
    if (contains(context.recent_exercise_ids, exercise.id)) {
        candidate.score.continuity = if (context.policy.continuity == .dynamic or context.policy.continuity == .novelty_biased) 0 else context.policy.continuity_bonus;
        if (context.policy.continuity == .novelty_biased) candidate.score.novelty = negate(context.policy.novelty_bonus);
    } else if (context.policy.continuity == .novelty_biased) candidate.score.novelty = context.policy.novelty_bonus;
    if (contains(context.already_selected_exercise_ids, exercise.id) or anyFamily(exercise.*, context.already_selected_family_ids)) candidate.score.overlap = negate(context.policy.overlap_penalty);
    if (exercise.knowledge) |item| {
        if (item.setupBurden) |burden| candidate.score.equipment_convenience = switch (burden) {
            .trivial => 4,
            .low => 2,
            .moderate, .high => 0,
            .unknown => 0,
        };
    }
    addReasons(&candidate);
    const preferred = contains(context.policy.preferred_exercises, exercise.id) or
        anyFamily(exercise.*, context.policy.preferred_family_ids);
    if (preferred and !hasReason(&candidate, .preference))
        addReason(&candidate, .preference) catch {};
    if (contains(context.policy.disliked_exercises, exercise.id) and
        !hasReason(&candidate, .dislike)) addReason(&candidate, .dislike) catch {};
    return candidate;
}

fn hasReason(candidate: *const Candidate, reason: Reason) bool {
    for (candidate.reasonSlice()) |existing| if (existing == reason) return true;
    return false;
}

fn addReasons(candidate: *Candidate) void {
    if (candidate.score.target_match != 0) addReason(candidate, .target_match) catch {};
    if (candidate.score.movement_match != 0) addReason(candidate, .movement_match) catch {};
    if (candidate.score.family_match != 0) addReason(candidate, .family_match) catch {};
    if (candidate.score.preference != 0) addReason(candidate, if (candidate.score.preference > 0) .preference else .dislike) catch {};
    if (candidate.score.continuity != 0) addReason(candidate, .continuity) catch {};
    if (candidate.score.novelty != 0) addReason(candidate, .novelty) catch {};
    if (candidate.score.overlap != 0) addReason(candidate, .overlap) catch {};
    if (candidate.score.equipment_convenience != 0)
        addReason(candidate, .equipment_convenience) catch {};
}
fn addReason(candidate: *Candidate, reason: Reason) error{Full}!void {
    if (candidate.reason_count == max_reasons) return error.Full;
    candidate.reasons[candidate.reason_count] = reason;
    candidate.reason_count += 1;
}
fn sortCandidates(candidates: []Candidate) void {
    std.sort.heap(Candidate, candidates, {}, compareCandidates);
}
/// Keep only the best bounded prefix. The catalog is never copied into a
/// second, catalog-sized allocation. Duplicate IDs already in the prefix are
/// replaced only when the later record is strictly better; ties retain the
/// first record, making malformed duplicate catalogs deterministic.
fn insertCandidate(storage: []Candidate, count: *usize, candidate: Candidate) void {
    for (storage[0..count.*]) |*existing| {
        if (existing.exercise.id.eql(candidate.exercise.id)) {
            if (compareCandidates({}, candidate, existing.*)) existing.* = candidate;
            sortCandidates(storage[0..count.*]);
            return;
        }
    }
    if (count.* < storage.len) {
        storage[count.*] = candidate;
        count.* += 1;
        sortCandidates(storage[0..count.*]);
    } else if (storage.len != 0 and compareCandidates({}, candidate, storage[storage.len - 1])) {
        storage[storage.len - 1] = candidate;
        sortCandidates(storage);
    }
}

fn rejectedLess(a: Rejected, b: Rejected) bool {
    if (a.reason != b.reason) return @intFromEnum(a.reason) < @intFromEnum(b.reason);
    return std.mem.order(u8, a.exercise.id.bytes, b.exercise.id.bytes) == .lt;
}

fn insertRejected(storage: []Rejected, count: *usize, limit: usize, rejected: Rejected) Error!void {
    if (limit == 0) return;
    if (storage.len == 0) return error.OutputTooSmall;
    for (storage[0..count.*]) |existing| if (existing.exercise.id.eql(rejected.exercise.id)) return;
    const bounded = @min(limit, storage.len);
    if (count.* < bounded) {
        storage[count.*] = rejected;
        count.* += 1;
    } else if (storage.len < limit) {
        return error.OutputTooSmall;
    } else if (rejectedLess(rejected, storage[count.* - 1])) {
        storage[count.* - 1] = rejected;
    } else return;
    std.sort.heap(Rejected, storage[0..count.*], {}, struct {
        fn less(_: void, a: Rejected, b: Rejected) bool {
            return rejectedLess(a, b);
        }
    }.less);
}

fn compareCandidates(_: void, a: Candidate, b: Candidate) bool {
    const as = a.score.total();
    const bs = b.score.total();
    if (as != bs) return as > bs;
    return std.mem.order(u8, a.exercise.id.bytes, b.exercise.id.bytes) == .lt;
}
fn negate(value: i32) i32 {
    return if (value == std.math.minInt(i32)) std.math.maxInt(i32) else -value;
}
fn contains(ids: []const Id, id: Id) bool {
    for (ids) |candidate| if (candidate.eql(id)) return true;
    return false;
}
fn containsBytes(ids: []const []const u8, id: []const u8) bool {
    for (ids) |candidate| if (std.mem.eql(u8, candidate, id)) return true;
    return false;
}
fn anyMuscle(exercise: training.Exercise, ids: []const Id) bool {
    for (exercise.muscle_contributions) |m| for (ids) |id| if (m.muscle_id.eql(id)) return true;
    return false;
}
fn anyMovement(exercise: training.Exercise, ids: []const Id) bool {
    for (ids) |id| if (knowledge.hasMovementPattern(exercise, id.bytes)) return true;
    return false;
}
fn anyFamily(exercise: training.Exercise, ids: []const Id) bool {
    for (exercise.family_ids) |f| for (ids) |id| if (f.eql(id)) return true;
    if (exercise.knowledge) |k| if (k.familyId) |f| for (ids) |id| if (std.mem.eql(u8, f, id.bytes)) return true;
    return false;
}
fn similarity(original: training.Exercise, candidate: training.Exercise, role: Role) i32 {
    var score: i32 = 0;
    if (role.movement_patterns.len != 0) {
        if (anyMovement(candidate, role.movement_patterns)) score += 35;
    } else if (sameMovement(original, candidate)) score += 35;
    if (role.target_muscles.len != 0) {
        if (anyMuscle(candidate, role.target_muscles)) score += 35;
    } else if (sameMuscle(original, candidate)) score += 35;
    if (original.knowledge != null and candidate.knowledge != null) {
        if (original.knowledge.?.structuralType == candidate.knowledge.?.structuralType) score += 15;
        if (original.knowledge.?.loadingMode == candidate.knowledge.?.loadingMode) score += 15;
    }
    if (sharedFamily(original, candidate)) score += 20;
    if (containsBytes(knowledge.relationshipIds(original, .substitutes), candidate.id.bytes)) score += 20;
    return score;
}

fn sharedFamily(left: training.Exercise, right: training.Exercise) bool {
    for (left.family_ids) |family| if (anyFamily(right, &.{family})) return true;
    if (left.knowledge) |item| if (item.familyId) |family| {
        if (right.knowledge) |other| if (other.familyId) |candidate|
            return std.mem.eql(u8, family, candidate);
        for (right.family_ids) |candidate| if (std.mem.eql(u8, family, candidate.bytes)) return true;
    };
    return false;
}

fn sameMovement(a: training.Exercise, b: training.Exercise) bool {
    const patterns = knowledge.movementPatterns(a);
    for (patterns) |pattern| if (knowledge.hasMovementPattern(b, pattern)) return true;
    return false;
}

fn sameMuscle(a: training.Exercise, b: training.Exercise) bool {
    for (a.muscle_contributions) |left| for (b.muscle_contributions) |right| if (left.muscle_id.eql(right.muscle_id)) return true;
    return false;
}

test "hard equipment exclusion and stable tie" {
    const a = training.Exercise{ .id = try .parse("a"), .equipment_ids = &.{try .parse("rack")} };
    const b = training.Exercise{ .id = try .parse("b") };
    var candidates: [2]Candidate = undefined;
    var rejected: [2]Rejected = undefined;
    const result = try rankExercises(.{ .role = .{}, .catalog = .{ .exercises = &.{ a, b } }, .context = .{ .available_equipment_ids = &.{} } }, &candidates, &rejected);
    try std.testing.expect(result.selected.?.exercise.id.eql(try .parse("b")));
    try std.testing.expectEqual(EligibilityReason.equipment_unavailable, result.rejected[0].reason);
}

test "excluded and preferred semantics" {
    const a = training.Exercise{ .id = try .parse("a") };
    const b = training.Exercise{ .id = try .parse("b") };
    var c: [2]Candidate = undefined;
    var r: [2]Rejected = undefined;
    const x = try rankExercises(.{ .role = .{}, .catalog = .{ .exercises = &.{ a, b } }, .context = .{ .policy = .{ .preferred_exercises = &.{try .parse("b")}, .excluded_exercises = &.{try .parse("a")} } } }, &c, &r);
    try std.testing.expect(x.selected.?.exercise.id.eql(try .parse("b")));
    try std.testing.expectEqual(@as(usize, 1), x.rejected.len);
}

test "fixed exercise conflict is explicit when equipment makes it impossible" {
    const fixed = training.Exercise{
        .id = try .parse("fixed-press"),
        .equipment_ids = &.{try .parse("barbell")},
    };
    const fallback = training.Exercise{ .id = try .parse("fallback-press") };
    var candidates: [2]Candidate = undefined;
    var rejected: [2]Rejected = undefined;
    const result = try rankExercises(.{
        .role = .{ .fixed_exercise_id = fixed.id },
        .catalog = .{ .exercises = &.{ fixed, fallback } },
        .context = .{ .available_equipment_ids = &.{} },
    }, &candidates, &rejected);
    try std.testing.expect(result.unsatisfiable);
    try std.testing.expectEqual(EligibilityReason.fixed_conflict, result.rejected[0].reason);
    try std.testing.expectEqual(EligibilityReason.equipment_unavailable, result.rejected[1].reason);
}

test "progression incompatibility is a hard rejection" {
    const hold = training.Exercise{
        .id = try .parse("hold"),
        .knowledge = .{
            .progressionCapabilities = .{
                .externalLoad = false,
                .repetitions = false,
                .duration = true,
            },
        },
    };
    var candidates: [1]Candidate = undefined;
    var rejected: [1]Rejected = undefined;
    const result = try rankExercises(.{
        .role = .{ .progression_requirement = .externally_loadable_repetitions },
        .catalog = .{ .exercises = &.{hold} },
    }, &candidates, &rejected);
    try std.testing.expect(result.unsatisfiable);
    try std.testing.expectEqual(EligibilityReason.progression_incompatible, result.rejected[0].reason);
}

test "substitution ranking changes with role intent and never transfers state" {
    const horizontal = try Id.parse("horizontal-push");
    const chest = try Id.parse("chest");
    const source = training.Exercise{
        .id = try .parse("barbell-bench"),
        .movement_tags = &.{horizontal},
        .muscle_contributions = &.{.{ .muscle_id = chest, .role = .primary }},
        .knowledge = .{ .structuralType = .compound, .loadingMode = .external_load },
    };
    const dumbbell = training.Exercise{
        .id = try .parse("dumbbell-bench"),
        .movement_tags = &.{horizontal},
        .muscle_contributions = &.{.{ .muscle_id = chest, .role = .primary }},
        .knowledge = .{ .structuralType = .compound, .loadingMode = .external_load },
    };
    const fly = training.Exercise{
        .id = try .parse("cable-fly"),
        .muscle_contributions = &.{.{ .muscle_id = chest, .role = .primary }},
        .knowledge = .{ .structuralType = .isolation, .loadingMode = .machine_load },
    };
    var candidates: [3]Candidate = undefined;
    var rejected: [3]Rejected = undefined;
    const press = try findSubstitutes(.{
        .exercise = source.id,
        .role = .{ .movement_patterns = &.{horizontal} },
        .catalog = .{ .exercises = &.{ source, fly, dumbbell } },
    }, &candidates, &rejected);
    try std.testing.expect(press.selected.?.exercise.id.eql(dumbbell.id));
    try std.testing.expectEqual(.independent, press.progression_state_transfer);

    const isolation = try findSubstitutes(.{
        .exercise = source.id,
        .role = .{ .target_muscles = &.{chest}, .required_structural_type = "isolation" },
        .catalog = .{ .exercises = &.{ source, fly, dumbbell } },
    }, &candidates, &rejected);
    try std.testing.expect(isolation.selected.?.exercise.id.eql(fly.id));
}

test "family overlap influences equivalent candidates" {
    const family = try Id.parse("press-family");
    const a = training.Exercise{ .id = try .parse("a"), .family_ids = &.{family} };
    const b = training.Exercise{ .id = try .parse("b") };
    var candidates: [2]Candidate = undefined;
    var rejected: [2]Rejected = undefined;
    const result = try rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &.{ a, b } },
        .context = .{
            .already_selected_family_ids = &.{family},
        },
    }, &candidates, &rejected);
    try std.testing.expect(result.selected.?.exercise.id.eql(b.id));
}

test "substitution alternative limits are safe and exact" {
    const source = training.Exercise{ .id = try .parse("source") };
    const a = training.Exercise{ .id = try .parse("a") };
    const b = training.Exercise{ .id = try .parse("b") };
    var candidates: [3]Candidate = undefined;
    var rejected: [3]Rejected = undefined;
    const none = try findSubstitutes(.{
        .exercise = source.id,
        .catalog = .{ .exercises = &.{ source, a, b } },
        .alternative_limit = 0,
    }, &candidates, &rejected);
    try std.testing.expectEqual(@as(usize, 0), none.alternatives.len);
    const one = try findSubstitutes(.{
        .exercise = source.id,
        .catalog = .{ .exercises = &.{ source, a, b } },
        .alternative_limit = 1,
    }, &candidates, &rejected);
    try std.testing.expectEqual(@as(usize, 1), one.alternatives.len);
}

test "bounded ranking handles large duplicate catalogs and zero rejection limit" {
    const exercise = training.Exercise{ .id = try .parse("repeated") };
    var catalog: [1024]training.Exercise = undefined;
    for (&catalog) |*item| item.* = exercise;
    var candidates: [1]Candidate = undefined;
    var rejected: [0]Rejected = .{};
    const result = try rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &catalog },
        .rejection_limit = 0,
        .alternative_limit = 0,
    }, &candidates, &rejected);
    try std.testing.expectEqual(@as(usize, 0), result.alternatives.len);
    try std.testing.expectEqual(@as(usize, 1), @as(usize, if (result.selected != null) 1 else 0));
    try std.testing.expectEqual(@as(usize, 0), result.rejected.len);
}

test "selection limits reject above-bound requests and substitution reports missing source" {
    var catalog: [max_catalog_exercises + 1]training.Exercise = undefined;
    for (&catalog, 0..) |*exercise, index| {
        exercise.* = .{ .id = .{ .bytes = try std.fmt.allocPrint(std.testing.allocator, "exercise-{d}", .{index}) } };
    }
    defer for (&catalog) |exercise| std.testing.allocator.free(exercise.id.bytes);
    var candidate: [1]Candidate = undefined;
    var rejected: [1]Rejected = undefined;
    try std.testing.expectError(error.LimitExceeded, rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &catalog },
        .alternative_limit = 0,
        .rejection_limit = 0,
    }, &candidate, &rejected));

    const available = training.Exercise{ .id = try .parse("available") };
    const missing = try findSubstitutes(.{
        .exercise = try .parse("missing"),
        .catalog = .{ .exercises = &.{available} },
        .alternative_limit = 0,
        .rejection_limit = 0,
    }, &candidate, &rejected);
    try std.testing.expectEqual(Conflict.source_exercise_missing, missing.conflict.?);
}

test "empty candidate storage is valid when every exercise is rejected" {
    const exercise = training.Exercise{ .id = try .parse("excluded") };
    var candidates: [0]Candidate = .{};
    var rejected: [1]Rejected = undefined;
    const result = try rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &.{exercise} },
        .context = .{ .policy = .{ .excluded_exercises = &.{exercise.id} } },
    }, &candidates, &rejected);
    try std.testing.expect(result.unsatisfiable);
    try std.testing.expectEqual(@as(usize, 1), result.rejected.len);
}

test "extreme policy weights remain bounded and deterministic" {
    const a = training.Exercise{ .id = try .parse("a") };
    const b = training.Exercise{ .id = try .parse("b") };
    var candidates: [2]Candidate = undefined;
    var rejected: [1]Rejected = undefined;
    const result = try rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &.{ a, b } },
        .context = .{ .policy = .{
            .preferred_exercises = &.{a.id},
            .preference_bonus = std.math.maxInt(i32),
            .dislike_penalty = std.math.maxInt(i32),
        } },
    }, &candidates, &rejected);
    try std.testing.expect(result.selected.?.exercise.id.eql(a.id));
    try std.testing.expect(result.selected.?.score.total() <= std.math.maxInt(i64));
}

test "undersized output storage and negative policy weights are rejected" {
    const a = training.Exercise{ .id = try .parse("a") };
    const b = training.Exercise{ .id = try .parse("b") };
    var one_candidate: [1]Candidate = undefined;
    var one_rejected: [1]Rejected = undefined;
    try std.testing.expectError(error.OutputTooSmall, rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &.{ a, b } },
        .alternative_limit = 1,
        .rejection_limit = 0,
    }, &one_candidate, &one_rejected));
    try std.testing.expectError(error.InvalidPolicy, rankExercises(.{
        .role = .{},
        .catalog = .{ .exercises = &.{a} },
        .context = .{ .policy = .{ .preference_bonus = -1 } },
        .alternative_limit = 0,
        .rejection_limit = 0,
    }, &one_candidate, &one_rejected));
}
