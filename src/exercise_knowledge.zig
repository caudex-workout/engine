//! Deterministic queries over host-supplied exercise knowledge.

const std = @import("std");
const canonical = @import("canonical.zig");
const training = @import("training.zig");

pub const ProgressionRequirement = enum {
    externally_loadable_repetitions,
    repetitions,
    duration,
    distance,
};

pub const Compatibility = enum { compatible, incompatible, unknown };

pub const Query = struct {
    muscle_id: ?training.Id = null,
    movement_pattern_id: ?training.Id = null,
    available_equipment_ids: ?[]const training.Id = null,
    progression_requirement: ?ProgressionRequirement = null,
    excluded_restriction_ids: []const training.Id = &.{},
};

pub const Mismatch = enum {
    muscle_not_targeted,
    movement_pattern_missing,
    required_equipment_unavailable,
    progression_incompatible,
    movement_restriction,
};

pub const MatchResult = struct {
    matches: bool,
    mismatches: []const Mismatch,
};

/// Evaluates composable exercise constraints in stable rule order. Unknown
/// optional knowledge is permissive except for positive taxonomy filters,
/// which cannot be proven without the requested classification.
pub fn match(
    exercise: training.Exercise,
    query: Query,
    mismatch_storage: []Mismatch,
) error{OutputTooSmall}!MatchResult {
    var count: usize = 0;
    if (query.muscle_id) |muscle| {
        for (exercise.muscle_contributions) |contribution| {
            if (contribution.muscle_id.eql(muscle)) break;
        } else try appendMismatch(mismatch_storage, &count, .muscle_not_targeted);
    }
    if (query.movement_pattern_id) |pattern| {
        if (!hasMovementPattern(exercise, pattern.bytes))
            try appendMismatch(mismatch_storage, &count, .movement_pattern_missing);
    }
    if (query.available_equipment_ids) |available| {
        if (!requiredEquipmentSatisfied(exercise, available))
            try appendMismatch(mismatch_storage, &count, .required_equipment_unavailable);
    }
    if (query.progression_requirement) |requirement| {
        if (progressionCompatibility(exercise, requirement) == .incompatible)
            try appendMismatch(mismatch_storage, &count, .progression_incompatible);
    }
    for (query.excluded_restriction_ids) |restriction| {
        if (hasRestriction(exercise, restriction.bytes)) {
            try appendMismatch(mismatch_storage, &count, .movement_restriction);
            break;
        }
    }
    return .{ .matches = count == 0, .mismatches = mismatch_storage[0..count] };
}

pub fn progressionCompatibility(
    exercise: training.Exercise,
    requirement: ProgressionRequirement,
) Compatibility {
    const knowledge = exercise.knowledge orelse return .unknown;
    const capabilities = knowledge.progressionCapabilities orelse return .unknown;
    return switch (requirement) {
        .externally_loadable_repetitions => combine(
            capabilities.externalLoad,
            capabilities.repetitions,
        ),
        .repetitions => fromOptional(capabilities.repetitions),
        .duration => fromOptional(capabilities.duration),
        .distance => fromOptional(capabilities.distance),
    };
}

pub fn requiredEquipmentSatisfied(
    exercise: training.Exercise,
    available: []const training.Id,
) bool {
    if (exercise.knowledge) |knowledge| {
        var has_structured_requirements = false;
        for (knowledge.equipmentRequirements, 0..) |requirement, index| {
            if (requirement.requirement == .one_of) {
                const group = requirement.alternativeGroup orelse continue;
                for (knowledge.equipmentRequirements[0..index]) |prior| {
                    if (prior.requirement == .one_of and
                        std.mem.eql(u8, prior.alternativeGroup orelse "", group)) break;
                } else {
                    has_structured_requirements = true;
                    for (knowledge.equipmentRequirements) |alternative| {
                        if (alternative.requirement != .one_of or
                            !std.mem.eql(u8, alternative.alternativeGroup orelse "", group)) continue;
                        for (available) |candidate| {
                            if (std.mem.eql(u8, candidate.bytes, alternative.equipmentId)) break;
                        } else continue;
                        break;
                    } else return false;
                }
                continue;
            }
            if (requirement.requirement != .required) continue;
            has_structured_requirements = true;
            for (available) |candidate| {
                if (std.mem.eql(u8, candidate.bytes, requirement.equipmentId)) break;
            } else return false;
        }
        if (has_structured_requirements) return true;
    }
    for (exercise.equipment_ids) |required| {
        for (available) |candidate| if (required.eql(candidate)) break else {} else return false;
    }
    return true;
}

pub fn movementPatterns(exercise: training.Exercise) []const []const u8 {
    if (exercise.knowledge) |knowledge| if (knowledge.movementPatterns.len != 0)
        return knowledge.movementPatterns;
    return &.{};
}

pub fn hasMovementPattern(exercise: training.Exercise, pattern_id: []const u8) bool {
    if (exercise.knowledge) |knowledge| if (knowledge.movementPatterns.len != 0) {
        for (knowledge.movementPatterns) |candidate| {
            if (std.mem.eql(u8, candidate, pattern_id)) return true;
        }
        return false;
    };
    for (exercise.movement_tags) |candidate| {
        if (std.mem.eql(u8, candidate.bytes, pattern_id)) return true;
    }
    return false;
}

pub fn hasRestriction(exercise: training.Exercise, restriction_id: []const u8) bool {
    const knowledge = exercise.knowledge orelse return false;
    for (knowledge.restrictionTags) |candidate| {
        if (std.mem.eql(u8, candidate, restriction_id)) return true;
    }
    return false;
}

pub fn relationshipIds(
    exercise: training.Exercise,
    kind: enum { variants, substitutes, similar, shared_progression_state },
) []const []const u8 {
    const knowledge = exercise.knowledge orelse return &.{};
    return switch (kind) {
        .variants => knowledge.relationships.variantIds,
        .substitutes => knowledge.relationships.substituteIds,
        .similar => knowledge.relationships.similarExerciseIds,
        .shared_progression_state => knowledge.relationships.sharedProgressionStateIds,
    };
}

fn combine(left: ?bool, right: ?bool) Compatibility {
    if (left == false or right == false) return .incompatible;
    if (left == true and right == true) return .compatible;
    return .unknown;
}

fn fromOptional(value: ?bool) Compatibility {
    if (value) |known| return if (known) .compatible else .incompatible;
    return .unknown;
}

fn appendMismatch(storage: []Mismatch, count: *usize, mismatch: Mismatch) error{OutputTooSmall}!void {
    if (count.* == storage.len) return error.OutputTooSmall;
    storage[count.*] = mismatch;
    count.* += 1;
}

test "explicit duration-only capability rejects load and repetition progression" {
    const exercise = training.Exercise{
        .id = try .parse("plank"),
        .knowledge = canonical.ExerciseKnowledge{
            .progressionCapabilities = .{ .externalLoad = false, .repetitions = false, .duration = true },
        },
    };
    try std.testing.expectEqual(
        Compatibility.incompatible,
        progressionCompatibility(exercise, .externally_loadable_repetitions),
    );
}

test "structured multi-equipment requirements are authoritative" {
    const requirements = [_]canonical.EquipmentRequirement{
        .{ .equipmentId = "dumbbell", .role = .load_bearing },
        .{ .equipmentId = "adjustable-bench", .role = .support },
    };
    const exercise = training.Exercise{
        .id = try .parse("incline-dumbbell-press"),
        .knowledge = .{ .equipmentRequirements = &requirements },
    };
    const dumbbell = [_]training.Id{try .parse("dumbbell")};
    const complete = [_]training.Id{ try .parse("adjustable-bench"), try .parse("dumbbell") };
    try std.testing.expect(!requiredEquipmentSatisfied(exercise, &dumbbell));
    try std.testing.expect(requiredEquipmentSatisfied(exercise, &complete));
}

test "query reports deterministic reasons" {
    const exercise = training.Exercise{
        .id = try .parse("plank"),
        .knowledge = .{
            .movementPatterns = &.{"trunk-anti-extension"},
            .restrictionTags = &.{"floor-access"},
            .progressionCapabilities = .{ .externalLoad = false, .repetitions = false, .duration = true },
        },
    };
    var mismatches: [5]Mismatch = undefined;
    const result = try match(exercise, .{
        .movement_pattern_id = try .parse("horizontal-push"),
        .progression_requirement = .externally_loadable_repetitions,
        .excluded_restriction_ids = &.{try .parse("floor-access")},
    }, &mismatches);
    try std.testing.expectEqualDeep(
        &[_]Mismatch{ .movement_pattern_missing, .progression_incompatible, .movement_restriction },
        result.mismatches,
    );
}
