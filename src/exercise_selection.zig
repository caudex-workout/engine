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
    dislike_penalty: i16 = 12,
    preference_bonus: i16 = 24,
    continuity_bonus: i16 = 20,
    novelty_bonus: i16 = 8,
    overlap_penalty: i16 = 18,
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
    not_in_catalog,
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
    target_match: i16 = 0,
    movement_match: i16 = 0,
    family_match: i16 = 0,
    preference: i16 = 0,
    continuity: i16 = 0,
    novelty: i16 = 0,
    overlap: i16 = 0,
    equipment_convenience: i16 = 0,
    substitution_similarity: i16 = 0,

    pub fn total(self: Score) i32 {
        return @as(i32, self.target_match) + self.movement_match + self.family_match +
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
    /// Substitution preserves the role, never an exercise-local progression
    /// history or load. Hosts may deliberately route shared state separately.
    progression_state_transfer: enum { not_applicable, independent } = .not_applicable,
};

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

pub const Error = error{OutputTooSmall};

pub fn rankExercises(
    request: Request,
    candidate_storage: []Candidate,
    rejected_storage: []Rejected,
) Error!Result {
    var count: usize = 0;
    var rejected_count: usize = 0;
    for (request.catalog.exercises) |*exercise| {
        if (count >= candidate_storage.len and rejected_count >= rejected_storage.len)
            return error.OutputTooSmall;
        if (eligibility(exercise.*, request.role, request.context)) |reason| {
            if (rejected_count < @min(request.rejection_limit, rejected_storage.len)) {
                rejected_storage[rejected_count] = .{ .exercise = exercise, .reason = reason };
                rejected_count += 1;
            }
            continue;
        }
        if (count == candidate_storage.len) return error.OutputTooSmall;
        candidate_storage[count] = scoreCandidate(exercise, request.role, request.context);
        count += 1;
    }
    sortCandidates(candidate_storage[0..count]);
    const requested_count = std.math.add(usize, request.alternative_limit, 1) catch
        std.math.maxInt(usize);
    const limit = @min(count, requested_count);
    const selected = if (count == 0) null else &candidate_storage[0];
    const alternatives = if (count == 0) candidate_storage[0..0] else candidate_storage[1..limit];
    return .{ .selected = selected, .alternatives = alternatives, .rejected = rejected_storage[0..rejected_count], .unsatisfiable = count == 0 };
}

pub fn findSubstitutes(
    request: SubstitutionRequest,
    candidate_storage: []Candidate,
    rejected_storage: []Rejected,
) Error!Result {
    const original = request.catalog.find(request.exercise) orelse {
        return .{
            .selected = null,
            .alternatives = candidate_storage[0..0],
            .rejected = rejected_storage[0..0],
            .unsatisfiable = true,
            .progression_state_transfer = .independent,
        };
    };
    var kept: usize = 0;
    var rejected_count: usize = 0;
    for (request.catalog.exercises) |*exercise| {
        if (exercise.id.eql(original.id)) continue;
        if (eligibility(exercise.*, request.role, request.context)) |reason| {
            if (rejected_count < @min(request.rejection_limit, rejected_storage.len)) {
                rejected_storage[rejected_count] = .{ .exercise = exercise, .reason = reason };
                rejected_count += 1;
            }
            continue;
        }
        if (kept == candidate_storage.len) return error.OutputTooSmall;
        candidate_storage[kept] = scoreCandidate(exercise, request.role, request.context);
        const candidate = &candidate_storage[kept];
        candidate.score.substitution_similarity = similarity(original.*, exercise.*, request.role);
        if (candidate.score.substitution_similarity != 0)
            addReason(candidate, .substitution_similarity) catch {};
        kept += 1;
    }
    sortCandidates(candidate_storage[0..kept]);
    const requested_count = std.math.add(usize, request.alternative_limit, 1) catch
        std.math.maxInt(usize);
    const limit = @min(kept, requested_count);
    return .{
        .selected = if (kept == 0) null else &candidate_storage[0],
        .alternatives = if (kept == 0) candidate_storage[0..0] else candidate_storage[1..limit],
        .rejected = rejected_storage[0..rejected_count],
        .unsatisfiable = kept == 0,
        .progression_state_transfer = .independent,
    };
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
        candidate.score.preference += context.policy.preference_bonus;
    if (contains(context.policy.disliked_exercises, exercise.id)) candidate.score.preference -= context.policy.dislike_penalty;
    if (contains(context.recent_exercise_ids, exercise.id)) {
        candidate.score.continuity = if (context.policy.continuity == .dynamic or context.policy.continuity == .novelty_biased) 0 else context.policy.continuity_bonus;
        if (context.policy.continuity == .novelty_biased) candidate.score.novelty = -context.policy.novelty_bonus;
    } else if (context.policy.continuity == .novelty_biased) candidate.score.novelty = context.policy.novelty_bonus;
    if (contains(context.already_selected_exercise_ids, exercise.id) or anyFamily(exercise.*, context.already_selected_family_ids)) candidate.score.overlap = -context.policy.overlap_penalty;
    if (exercise.knowledge) |item| {
        if (item.setupBurden) |burden| candidate.score.equipment_convenience = switch (burden) {
            .trivial => 4,
            .low => 2,
            .moderate, .high => 0,
            .unknown => 0,
        };
    }
    addReasons(&candidate);
    return candidate;
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
fn compareCandidates(_: void, a: Candidate, b: Candidate) bool {
    const as = a.score.total();
    const bs = b.score.total();
    if (as != bs) return as > bs;
    return std.mem.order(u8, a.exercise.id.bytes, b.exercise.id.bytes) == .lt;
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
fn similarity(original: training.Exercise, candidate: training.Exercise, role: Role) i16 {
    var score: i16 = 0;
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
    try std.testing.expectEqual(EligibilityReason.equipment_unavailable, result.rejected[0].reason);
    try std.testing.expectEqual(EligibilityReason.fixed_conflict, result.rejected[1].reason);
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
