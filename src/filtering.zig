const std = @import("std");
const canonical = @import("canonical.zig");
const primitives = @import("primitives.zig");
const training = @import("training.zig");

pub const MissingDurationPolicy = enum {
    allow,
    exclude,
};

pub const Candidate = struct {
    exercise: *const training.Exercise,
    /// A host- or methodology-supplied estimate. Duration derivation is CWE-023.
    estimated_duration_minutes: ?u32 = null,
};

pub const HostRestrictions = struct {
    excluded_exercise_ids: []const primitives.Id = &.{},
    excluded_movement_tags: []const primitives.Id = &.{},
    equipment_limitations: []const primitives.Id = &.{},
};

pub const Constraints = struct {
    available_equipment_ids: []const primitives.Id = &.{},
    excluded_exercise_ids: []const primitives.Id = &.{},
    required_exercise_ids: []const primitives.Id = &.{},
    available_minutes: ?u32 = null,
    host_restrictions: HostRestrictions = .{},
    methodology_required_tags: []const primitives.Id = &.{},
    missing_duration_policy: MissingDurationPolicy = .exclude,
};

/// All result memory is supplied by the caller.
pub const Buffers = struct {
    eligible_indices: []usize,
    explanations: []canonical.Explanation,
    issues: []canonical.ValidationIssue,
    explanation_ids: []u8,
};

pub const Result = struct {
    eligible_indices: []const usize,
    explanations: []const canonical.Explanation,
    issues: []const canonical.ValidationIssue,
};

pub const FilterError = error{OutputLimitReached};

const Exclusion = enum {
    equipment_unavailable,
    session_excluded,
    host_exercise_restriction,
    host_movement_restriction,
    host_equipment_restriction,
    methodology_tag_missing,
    time_budget,
    duration_unknown,
};

const equipment_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/availableEquipmentIds" },
};
const session_exclusion_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/excludedExerciseIds" },
};
const host_restriction_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/athlete/restrictions" },
};
const methodology_tag_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/methodology/config" },
};
const time_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/availableMinutes" },
};
const required_evidence = [_]canonical.EvidenceRef{
    .{ .path = "/session/requiredExerciseIds" },
};

/// Applies every hard rule to every candidate.
///
/// Eligible output preserves candidate order; CWE-022 owns stable candidate
/// ordering. Constraint-array order cannot affect membership or diagnostic
/// rule order. An exercise with no equipment IDs is explicitly bodyweight.
/// Empty movement tags fail any methodology-required tag.
pub fn filter(
    candidates: []const Candidate,
    constraints: Constraints,
    buffers: Buffers,
) FilterError!Result {
    var eligible_len: usize = 0;
    var explanation_len: usize = 0;
    var issue_len: usize = 0;
    var id_bytes_len: usize = 0;

    for (candidates, 0..) |candidate, candidate_index| {
        const exercise = candidate.exercise;
        const required = containsId(constraints.required_exercise_ids, exercise.id);
        var exclusion_count: usize = 0;
        var excluded_for_time = false;

        if (!allIdsPresent(exercise.equipment_ids, constraints.available_equipment_ids)) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .equipment_unavailable,
            );
            exclusion_count += 1;
        }
        if (containsId(constraints.excluded_exercise_ids, exercise.id)) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .session_excluded,
            );
            exclusion_count += 1;
        }
        if (containsId(
            constraints.host_restrictions.excluded_exercise_ids,
            exercise.id,
        )) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .host_exercise_restriction,
            );
            exclusion_count += 1;
        }
        if (anyIdPresent(
            exercise.movement_tags,
            constraints.host_restrictions.excluded_movement_tags,
        )) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .host_movement_restriction,
            );
            exclusion_count += 1;
        }
        if (anyIdPresent(
            exercise.equipment_ids,
            constraints.host_restrictions.equipment_limitations,
        )) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .host_equipment_restriction,
            );
            exclusion_count += 1;
        }
        if (!allIdsPresent(
            constraints.methodology_required_tags,
            exercise.movement_tags,
        )) {
            try appendExclusion(
                buffers,
                &explanation_len,
                &id_bytes_len,
                exercise.id,
                .methodology_tag_missing,
            );
            exclusion_count += 1;
        }
        if (constraints.available_minutes) |available_minutes| {
            if (candidate.estimated_duration_minutes) |duration| {
                if (duration > available_minutes) {
                    try appendExclusion(
                        buffers,
                        &explanation_len,
                        &id_bytes_len,
                        exercise.id,
                        .time_budget,
                    );
                    exclusion_count += 1;
                    excluded_for_time = true;
                }
            } else if (constraints.missing_duration_policy == .exclude) {
                try appendExclusion(
                    buffers,
                    &explanation_len,
                    &id_bytes_len,
                    exercise.id,
                    .duration_unknown,
                );
                exclusion_count += 1;
                excluded_for_time = true;
            }
        }

        if (exclusion_count == 0) {
            if (eligible_len == buffers.eligible_indices.len) {
                return error.OutputLimitReached;
            }
            buffers.eligible_indices[eligible_len] = candidate_index;
            eligible_len += 1;
            if (required) {
                try appendRequiredExplanation(
                    buffers,
                    &explanation_len,
                    &id_bytes_len,
                    exercise.id,
                );
            }
        } else if (required) {
            try appendIssue(
                buffers.issues,
                &issue_len,
                .{
                    .code = "session.required_exercise_unavailable",
                    .path = "/session/requiredExerciseIds",
                    .message = "A required exercise violates another hard constraint.",
                    .severity = .@"error",
                    .suggestion = "Remove the conflicting constraint or make the required exercise available.",
                },
            );
            if (excluded_for_time) {
                try appendIssue(
                    buffers.issues,
                    &issue_len,
                    .{
                        .code = "session.time_budget_unsatisfied",
                        .path = "/session/availableMinutes",
                        .message = "Required work cannot fit the explicit time budget.",
                        .severity = .@"error",
                        .suggestion = "Increase available minutes or remove the required exercise.",
                    },
                );
            }
        }
    }

    for (constraints.required_exercise_ids) |required_id| {
        if (!candidateExists(candidates, required_id)) {
            try appendIssue(
                buffers.issues,
                &issue_len,
                .{
                    .code = "catalog.exercise_reference_missing",
                    .path = "/session/requiredExerciseIds",
                    .message = "A required exercise is absent from the candidate catalog.",
                    .severity = .@"error",
                    .suggestion = "Include the required exercise in the catalog or remove the requirement.",
                },
            );
        }
    }

    return .{
        .eligible_indices = buffers.eligible_indices[0..eligible_len],
        .explanations = buffers.explanations[0..explanation_len],
        .issues = buffers.issues[0..issue_len],
    };
}

fn appendExclusion(
    buffers: Buffers,
    explanation_len: *usize,
    id_bytes_len: *usize,
    exercise_id: primitives.Id,
    exclusion: Exclusion,
) FilterError!void {
    const details = exclusionDetails(exclusion);
    try appendExplanation(
        buffers,
        explanation_len,
        id_bytes_len,
        .{
            .code = details.code,
            .summary = details.summary,
            .exercise_id = exercise_id.bytes,
            .evidence = details.evidence,
        },
    );
}

fn appendRequiredExplanation(
    buffers: Buffers,
    explanation_len: *usize,
    id_bytes_len: *usize,
    exercise_id: primitives.Id,
) FilterError!void {
    try appendExplanation(
        buffers,
        explanation_len,
        id_bytes_len,
        .{
            .code = "exercise.selected.required",
            .summary = "A session constraint required the exercise.",
            .exercise_id = exercise_id.bytes,
            .evidence = &required_evidence,
        },
    );
}

const ExplanationInput = struct {
    code: []const u8,
    summary: []const u8,
    exercise_id: []const u8,
    evidence: []const canonical.EvidenceRef,
};

fn appendExplanation(
    buffers: Buffers,
    explanation_len: *usize,
    id_bytes_len: *usize,
    input: ExplanationInput,
) FilterError!void {
    if (explanation_len.* == buffers.explanations.len) {
        return error.OutputLimitReached;
    }
    const id = std.fmt.bufPrint(
        buffers.explanation_ids[id_bytes_len.*..],
        "constraint-{d}",
        .{explanation_len.* + 1},
    ) catch return error.OutputLimitReached;
    id_bytes_len.* += id.len;
    buffers.explanations[explanation_len.*] = .{
        .id = id,
        .code = input.code,
        .category = "constraint",
        .summary = input.summary,
        .subject = .{ .exerciseId = input.exercise_id },
        .evidence = input.evidence,
        .severity = .info,
    };
    explanation_len.* += 1;
}

const ExclusionDetails = struct {
    code: []const u8,
    summary: []const u8,
    evidence: []const canonical.EvidenceRef,
};

fn exclusionDetails(exclusion: Exclusion) ExclusionDetails {
    return switch (exclusion) {
        .equipment_unavailable => .{
            .code = "exercise.excluded.equipment_unavailable",
            .summary = "Required exercise equipment is unavailable.",
            .evidence = &equipment_evidence,
        },
        .session_excluded => .{
            .code = "exercise.excluded.host_restriction",
            .summary = "The session explicitly excluded the exercise.",
            .evidence = &session_exclusion_evidence,
        },
        .host_exercise_restriction => .{
            .code = "exercise.excluded.host_restriction",
            .summary = "A host restriction excluded the exercise.",
            .evidence = &host_restriction_evidence,
        },
        .host_movement_restriction => .{
            .code = "exercise.excluded.host_restriction",
            .summary = "A host movement restriction excluded the exercise.",
            .evidence = &host_restriction_evidence,
        },
        .host_equipment_restriction => .{
            .code = "exercise.excluded.host_restriction",
            .summary = "A host equipment restriction excluded the exercise.",
            .evidence = &host_restriction_evidence,
        },
        .methodology_tag_missing => .{
            .code = "exercise.excluded.methodology_required_tag_missing",
            .summary = "The exercise lacks a tag required by the methodology.",
            .evidence = &methodology_tag_evidence,
        },
        .time_budget => .{
            .code = "exercise.excluded.available_time",
            .summary = "The exercise cannot fit the available time.",
            .evidence = &time_evidence,
        },
        .duration_unknown => .{
            .code = "exercise.excluded.duration_unknown",
            .summary = "The exercise duration is unknown under the configured policy.",
            .evidence = &time_evidence,
        },
    };
}

fn appendIssue(
    storage: []canonical.ValidationIssue,
    len: *usize,
    issue: canonical.ValidationIssue,
) FilterError!void {
    if (len.* == storage.len) return error.OutputLimitReached;
    storage[len.*] = issue;
    len.* += 1;
}

fn containsId(ids: []const primitives.Id, needle: primitives.Id) bool {
    for (ids) |id| {
        if (id.eql(needle)) return true;
    }
    return false;
}

fn allIdsPresent(required: []const primitives.Id, available: []const primitives.Id) bool {
    for (required) |id| {
        if (!containsId(available, id)) return false;
    }
    return true;
}

fn anyIdPresent(left: []const primitives.Id, right: []const primitives.Id) bool {
    for (left) |id| {
        if (containsId(right, id)) return true;
    }
    return false;
}

fn candidateExists(candidates: []const Candidate, exercise_id: primitives.Id) bool {
    for (candidates) |candidate| {
        if (candidate.exercise.id.eql(exercise_id)) return true;
    }
    return false;
}

const TestOutput = struct {
    eligible: [8]usize = undefined,
    explanations: [24]canonical.Explanation = undefined,
    issues: [8]canonical.ValidationIssue = undefined,
    ids: [512]u8 = undefined,

    fn buffers(self: *TestOutput) Buffers {
        return .{
            .eligible_indices = &self.eligible,
            .explanations = &self.explanations,
            .issues = &self.issues,
            .explanation_ids = &self.ids,
        };
    }
};

test "hard constraints exclude candidates with structured explanations" {
    const dumbbell = try primitives.Id.parse("dumbbell");
    const bench = try primitives.Id.parse("bench");
    const hypertrophy = try primitives.Id.parse("hypertrophy");
    const restricted_tag = try primitives.Id.parse("restricted");
    const ids = [_]primitives.Id{
        try .parse("eligible"),
        try .parse("equipment"),
        try .parse("session-excluded"),
        try .parse("host-restricted"),
        try .parse("tag-missing"),
        try .parse("too-long"),
    };
    const exercises = [_]training.Exercise{
        .{ .id = ids[0], .equipment_ids = &.{dumbbell}, .movement_tags = &.{hypertrophy} },
        .{ .id = ids[1], .equipment_ids = &.{bench}, .movement_tags = &.{hypertrophy} },
        .{ .id = ids[2], .equipment_ids = &.{dumbbell}, .movement_tags = &.{hypertrophy} },
        .{ .id = ids[3], .equipment_ids = &.{dumbbell}, .movement_tags = &.{ restricted_tag, hypertrophy } },
        .{ .id = ids[4], .equipment_ids = &.{dumbbell} },
        .{ .id = ids[5], .equipment_ids = &.{dumbbell}, .movement_tags = &.{hypertrophy} },
    };
    const candidates = [_]Candidate{
        .{ .exercise = &exercises[0], .estimated_duration_minutes = 10 },
        .{ .exercise = &exercises[1], .estimated_duration_minutes = 10 },
        .{ .exercise = &exercises[2], .estimated_duration_minutes = 10 },
        .{ .exercise = &exercises[3], .estimated_duration_minutes = 10 },
        .{ .exercise = &exercises[4], .estimated_duration_minutes = 10 },
        .{ .exercise = &exercises[5], .estimated_duration_minutes = 40 },
    };
    var output: TestOutput = .{};
    const result = try filter(
        &candidates,
        .{
            .available_equipment_ids = &.{dumbbell},
            .excluded_exercise_ids = &.{ids[2]},
            .available_minutes = 30,
            .host_restrictions = .{ .excluded_movement_tags = &.{restricted_tag} },
            .methodology_required_tags = &.{hypertrophy},
        },
        output.buffers(),
    );

    try std.testing.expectEqualSlices(usize, &.{0}, result.eligible_indices);
    const expected_codes = [_][]const u8{
        "exercise.excluded.equipment_unavailable",
        "exercise.excluded.host_restriction",
        "exercise.excluded.host_restriction",
        "exercise.excluded.methodology_required_tag_missing",
        "exercise.excluded.available_time",
    };
    try std.testing.expectEqual(expected_codes.len, result.explanations.len);
    for (expected_codes, result.explanations) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual.code);
        try std.testing.expect(actual.subject.?.exerciseId != null);
        try std.testing.expectEqual(@as(usize, 1), actual.evidence.len);
    }
}

test "required conflicts produce actionable issues and selection explanation" {
    const bodyweight = training.Exercise{ .id = try .parse("bodyweight-squat") };
    const long = training.Exercise{ .id = try .parse("long-session") };
    const candidates = [_]Candidate{
        .{ .exercise = &bodyweight, .estimated_duration_minutes = 5 },
        .{ .exercise = &long, .estimated_duration_minutes = 60 },
    };
    const missing = try primitives.Id.parse("missing");
    const required = [_]primitives.Id{ bodyweight.id, long.id, missing };
    var output: TestOutput = .{};
    const result = try filter(
        &candidates,
        .{
            .required_exercise_ids = &required,
            .available_minutes = 30,
        },
        output.buffers(),
    );

    try std.testing.expectEqualSlices(usize, &.{0}, result.eligible_indices);
    try std.testing.expectEqualStrings(
        "exercise.selected.required",
        result.explanations[0].code,
    );
    const expected_issues = [_][]const u8{
        "session.required_exercise_unavailable",
        "session.time_budget_unsatisfied",
        "catalog.exercise_reference_missing",
    };
    for (expected_issues, result.issues) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual.code);
        try std.testing.expect(actual.suggestion != null);
    }
}

test "constraint array order does not change eligibility" {
    const first = training.Exercise{ .id = try .parse("first") };
    const second = training.Exercise{ .id = try .parse("second") };
    const third = training.Exercise{ .id = try .parse("third") };
    const candidates = [_]Candidate{
        .{ .exercise = &first },
        .{ .exercise = &second },
        .{ .exercise = &third },
    };
    var forward_output: TestOutput = .{};
    const forward = try filter(
        &candidates,
        .{
            .excluded_exercise_ids = &.{ first.id, third.id },
            .missing_duration_policy = .allow,
        },
        forward_output.buffers(),
    );
    var reverse_output: TestOutput = .{};
    const reverse = try filter(
        &candidates,
        .{
            .excluded_exercise_ids = &.{ third.id, first.id },
            .missing_duration_policy = .allow,
        },
        reverse_output.buffers(),
    );
    try std.testing.expectEqualSlices(
        usize,
        forward.eligible_indices,
        reverse.eligible_indices,
    );
}

test "missing duration behavior is explicit and configurable" {
    const exercise = training.Exercise{ .id = try .parse("unknown-duration") };
    const candidates = [_]Candidate{.{ .exercise = &exercise }};

    var exclude_output: TestOutput = .{};
    const excluded = try filter(
        &candidates,
        .{ .available_minutes = 30, .missing_duration_policy = .exclude },
        exclude_output.buffers(),
    );
    try std.testing.expectEqual(@as(usize, 0), excluded.eligible_indices.len);
    try std.testing.expectEqualStrings(
        "exercise.excluded.duration_unknown",
        excluded.explanations[0].code,
    );

    var allow_output: TestOutput = .{};
    const allowed = try filter(
        &candidates,
        .{ .available_minutes = 30, .missing_duration_policy = .allow },
        allow_output.buffers(),
    );
    try std.testing.expectEqualSlices(usize, &.{0}, allowed.eligible_indices);
}
