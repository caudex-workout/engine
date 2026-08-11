//! Pure bridges between programming results, templates, tracking, and evaluation.

const std = @import("std");
const caudex = @import("caudex");
const tracking = @import("caudex_tracking");
const tracking_protocol = @import("caudex_tracking_protocol");

pub const template_schema_version: u32 = 1;
pub const max_template_exercises: usize = 128;
pub const max_template_sets: usize = 256;
pub const max_tags: usize = 32;
pub const workflow_schema_version: u32 = 1;

pub const ScopeDocument = tracking_protocol.Scope;

pub const InstantiationIdsDocument = struct {
    workoutId: []const u8,
    membershipIds: []const []const u8,
    setIds: []const []const u8,
};

pub const RecommendationInstantiationDocument = struct {
    schemaVersion: u32,
    recommendationResult: caudex.canonical.RecommendationResult,
    catalog: []const caudex.canonical.Exercise,
    scope: ScopeDocument,
    ids: InstantiationIdsDocument,
    createdAt: []const u8,
    acceptedRecommendationId: []const u8,
    methodologyStateRevision: ?[]const u8 = null,
    methodologyStateFingerprint: ?[]const u8 = null,
};

pub const TemplateInstantiationDocument = struct {
    schemaVersion: u32,
    template: WorkoutTemplateDocument,
    catalog: []const caudex.canonical.Exercise,
    scope: ScopeDocument,
    ids: InstantiationIdsDocument,
    createdAt: []const u8,
};

pub const CompletionDocument = struct {
    schemaVersion: u32,
    workout: tracking_protocol.TrackedWorkout,
    catalog: []const caudex.canonical.Exercise,
};

pub const InstantiationDocumentResult = struct {
    schemaVersion: u32 = workflow_schema_version,
    outcome: union(enum) {
        accepted: tracking_protocol.TrackedWorkout,
        rejected: []const tracking_protocol.Issue,
    },
};

pub const CompletionDocumentResult = struct {
    schemaVersion: u32 = workflow_schema_version,
    outcome: union(enum) {
        accepted: caudex.canonical.CompletedWorkout,
        rejected: []const tracking_protocol.Issue,
    },
};

pub const CanonicalWorkflowError = caudex.canonical_json.DecodeError || error{InvalidWorkflowDocument};

pub fn decodeRecommendationInstantiationDocument(allocator: std.mem.Allocator, input: []const u8, limits: caudex.canonical_json.Limits) CanonicalWorkflowError!std.json.Parsed(RecommendationInstantiationDocument) {
    const parsed = try caudex.canonical_json.decodeValue(RecommendationInstantiationDocument, allocator, input, limits);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != workflow_schema_version) return error.UnsupportedVersion;
    try validateInstantiationDocument(parsed.value.ids);
    return parsed;
}

pub fn decodeTemplateInstantiationDocument(allocator: std.mem.Allocator, input: []const u8, limits: caudex.canonical_json.Limits) CanonicalWorkflowError!std.json.Parsed(TemplateInstantiationDocument) {
    const parsed = try caudex.canonical_json.decodeValue(TemplateInstantiationDocument, allocator, input, limits);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != workflow_schema_version or parsed.value.template.schemaVersion != template_schema_version)
        return error.UnsupportedVersion;
    try validateInstantiationDocument(parsed.value.ids);
    return parsed;
}

pub fn decodeCompletionDocument(allocator: std.mem.Allocator, input: []const u8, limits: caudex.canonical_json.Limits) CanonicalWorkflowError!std.json.Parsed(CompletionDocument) {
    const parsed = try caudex.canonical_json.decodeValue(CompletionDocument, allocator, input, limits);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != workflow_schema_version) return error.UnsupportedVersion;
    if (parsed.value.workout.exercises.len > max_template_exercises) return error.InvalidWorkflowDocument;
    return parsed;
}

fn validateInstantiationDocument(ids: InstantiationIdsDocument) error{InvalidWorkflowDocument}!void {
    if (ids.membershipIds.len > max_template_exercises or ids.setIds.len > max_template_sets)
        return error.InvalidWorkflowDocument;
}

pub const TemplateSet = struct {
    kind: ?tracking.Id = null,
    target_metrics: []const tracking.Metric = &.{},
};

pub const TemplateExercise = struct {
    exercise_id: tracking.Id,
    sets: []const TemplateSet = &.{},
    notes: ?[]const u8 = null,
    tags: []const tracking.Id = &.{},
};

pub const WorkoutTemplate = struct {
    schema_version: u32 = template_schema_version,
    id: tracking.Id,
    display_name: []const u8,
    description: ?[]const u8 = null,
    exercises: []const TemplateExercise,
    notes: ?[]const u8 = null,
    tags: []const tracking.Id = &.{},
    revision: u64,
};

pub const TemplateSetDocument = caudex.canonical.TemplateSet;
pub const TemplateExerciseDocument = caudex.canonical.TemplateExercise;
pub const WorkoutTemplateDocument = caudex.canonical.WorkoutTemplate;

pub const TemplateDocumentStorage = struct {
    exercises: []TemplateExercise,
    sets: []TemplateSet,
    metrics: []tracking.Metric,
    tags: []tracking.Id,
};

pub const TemplateWireStorage = struct {
    exercises: []TemplateExerciseDocument,
    sets: []TemplateSetDocument,
    metrics: []caudex.canonical.Metric,
    amount_bytes: [][64]u8,
    tags: [][]const u8,
};

pub const TemplateDocumentError = caudex.canonical_json.DecodeError || error{
    InvalidTemplate,
    ExerciseBufferTooSmall,
    SetBufferTooSmall,
    MetricBufferTooSmall,
    TagBufferTooSmall,
};

pub fn decodeTemplateDocument(allocator: std.mem.Allocator, input: []const u8, limits: caudex.canonical_json.Limits) TemplateDocumentError!std.json.Parsed(WorkoutTemplateDocument) {
    const parsed = try caudex.canonical_json.decodeValue(WorkoutTemplateDocument, allocator, input, limits);
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != template_schema_version) return error.UnsupportedVersion;
    if (parsed.value.exercises.len > max_template_exercises or templateDocumentSetCount(parsed.value.exercises) == null)
        return error.InvalidTemplate;
    return parsed;
}

pub fn encodeTemplateDocument(value: WorkoutTemplateDocument, output: []u8) caudex.canonical_json.EncodeError![]const u8 {
    return caudex.canonical_json.encode(value, output);
}

pub fn templateToDomain(value: WorkoutTemplateDocument, storage: TemplateDocumentStorage) TemplateDocumentError!WorkoutTemplate {
    if (value.schemaVersion != template_schema_version or value.exercises.len > max_template_exercises or storage.exercises.len < value.exercises.len)
        return error.InvalidTemplate;
    const total_sets = templateDocumentSetCount(value.exercises) orelse return error.InvalidTemplate;
    if (storage.sets.len < total_sets) return error.SetBufferTooSmall;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    var tag_offset: usize = 0;
    for (value.exercises, 0..) |exercise, index| {
        const set_start = set_offset;
        for (exercise.sets) |set| {
            storage.sets[set_offset] = .{
                .kind = if (set.kind) |kind| tracking.Id.parse(kind) catch return error.InvalidTemplate else null,
                .target_metrics = convertMetrics(set.targetMetrics, storage.metrics, &metric_offset) catch return error.InvalidTemplate,
            };
            set_offset += 1;
        }
        const tag_end = std.math.add(usize, tag_offset, exercise.tags.len) catch return error.TagBufferTooSmall;
        if (tag_end > storage.tags.len) return error.TagBufferTooSmall;
        for (exercise.tags, tag_offset..) |tag, tag_index| storage.tags[tag_index] = tracking.Id.parse(tag) catch return error.InvalidTemplate;
        storage.exercises[index] = .{
            .exercise_id = tracking.Id.parse(exercise.exerciseId) catch return error.InvalidTemplate,
            .sets = storage.sets[set_start..set_offset],
            .notes = exercise.notes,
            .tags = storage.tags[tag_offset..tag_end],
        };
        tag_offset = tag_end;
    }
    const template_tag_end = std.math.add(usize, tag_offset, value.tags.len) catch return error.TagBufferTooSmall;
    if (template_tag_end > storage.tags.len) return error.TagBufferTooSmall;
    for (value.tags, tag_offset..) |tag, tag_index| storage.tags[tag_index] = tracking.Id.parse(tag) catch return error.InvalidTemplate;
    return .{
        .id = tracking.Id.parse(value.id) catch return error.InvalidTemplate,
        .display_name = value.displayName,
        .description = value.description,
        .exercises = storage.exercises[0..value.exercises.len],
        .notes = value.notes,
        .tags = storage.tags[tag_offset..template_tag_end],
        .revision = value.revision,
    };
}

pub fn templateFromDomain(value: WorkoutTemplate, storage: TemplateWireStorage) TemplateDocumentError!WorkoutTemplateDocument {
    if (storage.exercises.len < value.exercises.len) return error.ExerciseBufferTooSmall;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    var tag_offset: usize = 0;
    for (value.exercises, 0..) |exercise, index| {
        const set_end = std.math.add(usize, set_offset, exercise.sets.len) catch return error.SetBufferTooSmall;
        if (set_end > storage.sets.len) return error.SetBufferTooSmall;
        for (exercise.sets, set_offset..) |set, set_index| {
            storage.sets[set_index] = .{
                .kind = if (set.kind) |kind| kind.bytes else null,
                .targetMetrics = try formatTemplateMetrics(set.target_metrics, storage, &metric_offset),
            };
        }
        const tag_end = std.math.add(usize, tag_offset, exercise.tags.len) catch return error.TagBufferTooSmall;
        if (tag_end > storage.tags.len) return error.TagBufferTooSmall;
        for (exercise.tags, tag_offset..) |tag, tag_index| storage.tags[tag_index] = tag.bytes;
        storage.exercises[index] = .{
            .exerciseId = exercise.exercise_id.bytes,
            .sets = storage.sets[set_offset..set_end],
            .notes = exercise.notes,
            .tags = storage.tags[tag_offset..tag_end],
        };
        set_offset = set_end;
        tag_offset = tag_end;
    }
    const template_tag_end = std.math.add(usize, tag_offset, value.tags.len) catch return error.TagBufferTooSmall;
    if (template_tag_end > storage.tags.len) return error.TagBufferTooSmall;
    for (value.tags, tag_offset..) |tag, tag_index| storage.tags[tag_index] = tag.bytes;
    return .{
        .schemaVersion = template_schema_version,
        .id = value.id.bytes,
        .displayName = value.display_name,
        .description = value.description,
        .exercises = storage.exercises[0..value.exercises.len],
        .notes = value.notes,
        .tags = storage.tags[tag_offset..template_tag_end],
        .revision = value.revision,
    };
}

fn formatTemplateMetrics(values: []const tracking.Metric, storage: TemplateWireStorage, offset: *usize) TemplateDocumentError![]const caudex.canonical.Metric {
    const end = std.math.add(usize, offset.*, values.len) catch return error.MetricBufferTooSmall;
    if (end > storage.metrics.len or end > storage.amount_bytes.len) return error.MetricBufferTooSmall;
    const start = offset.*;
    for (values, start..) |metric, index| {
        const amount = metric.value.value.format(&storage.amount_bytes[index]) catch return error.MetricBufferTooSmall;
        storage.metrics[index] = .{ .code = metric.code.bytes, .value = .{ .amount = amount, .unit = metric.value.unit.code() } };
    }
    offset.* = end;
    return storage.metrics[start..end];
}

fn templateDocumentSetCount(exercises: []const TemplateExerciseDocument) ?usize {
    var count: usize = 0;
    for (exercises) |exercise| {
        count = std.math.add(usize, count, exercise.sets.len) catch return null;
        if (count > max_template_sets or exercise.tags.len > max_tags) return null;
    }
    return count;
}

pub const InstantiationIds = struct {
    workout_id: tracking.Id,
    membership_ids: []const tracking.Id,
    set_ids: []const tracking.Id,
};

pub const RecommendationInstantiation = struct {
    scope: tracking.Scope,
    ids: InstantiationIds,
    created_at: tracking.Timestamp,
    accepted_recommendation_id: tracking.Id,
    methodology_state_revision: ?[]const u8 = null,
    methodology_state_fingerprint: ?[]const u8 = null,
    athlete_profile_id: ?[]const u8 = null,
    athlete_profile_revision: ?u64 = null,
    athlete_profile_fingerprint: ?[]const u8 = null,
    training_location_id: ?[]const u8 = null,
    effective_equipment_ids: []const []const u8 = &.{},
    available_minutes: ?u16 = null,
    hard_maximum_minutes: ?u16 = null,
    session_goal_id: ?[]const u8 = null,
    active_restriction_ids: []const []const u8 = &.{},
};

pub const TemplateInstantiation = struct {
    scope: tracking.Scope,
    ids: InstantiationIds,
    created_at: tracking.Timestamp,
};

pub const InstantiationStorage = struct {
    exercises: []tracking.ExerciseMembership,
    sets: []tracking.TrackedSet,
    prescription_exercises: []tracking.PrescribedExercise,
    prescription_sets: []tracking.PrescribedSet,
    metrics: []tracking.Metric,
};

pub const WorkflowError = error{
    ExerciseBufferTooSmall,
    SetBufferTooSmall,
    MetricBufferTooSmall,
    IssueBufferTooSmall,
};

pub const InstantiationResult = union(enum) {
    accepted: tracking.Workout,
    rejected: []const tracking.Issue,
};

pub const issue_codes = struct {
    pub const invalid_recommendation = "workflow.invalid_recommendation";
    pub const invalid_evaluation = "workflow.invalid_evaluation";
    pub const invalid_template = "workflow.invalid_template";
    pub const invalid_identifier = "workflow.invalid_identifier";
    pub const catalog_reference_missing = "workflow.catalog_reference_missing";
    pub const duplicate_identifier = "workflow.duplicate_identifier";
    pub const invalid_metric = "workflow.invalid_metric";
    pub const workout_not_completed = "workflow.workout_not_completed";
    pub const actual_value_required = "workflow.actual_value_required";
    pub const provenance_inconsistent = "workflow.provenance_inconsistent";
};

pub const CompletionStorage = struct {
    exercises: []caudex.canonical.CompletedExercise,
    sets: []caudex.canonical.CompletedSet,
    metrics: []caudex.canonical.Metric,
    amount_bytes: [][64]u8,
    tags: [][]const u8,
};

pub const CompletionResult = union(enum) {
    accepted: caudex.canonical.CompletedWorkout,
    rejected: []const tracking.Issue,
};

pub const CompletionError = error{
    ExerciseBufferTooSmall,
    SetBufferTooSmall,
    MetricBufferTooSmall,
    TagBufferTooSmall,
    IssueBufferTooSmall,
};

pub const ModificationKind = enum {
    exercise_added,
    exercise_removed,
    exercise_reordered,
    set_added,
    set_removed,
    set_reordered,
};

pub const Modification = struct {
    kind: ModificationKind,
    membership_id: tracking.Id,
    set_id: ?tracking.Id = null,
    prescribed_index: ?u16 = null,
    current_index: ?u16 = null,
};

pub fn collectModifications(workout: tracking.Workout, output: []Modification) error{OutputBufferTooSmall}![]const Modification {
    var written: usize = 0;
    for (workout.prescription, 0..) |prescribed, prescribed_index| {
        const current_index = findMembershipIndex(workout.exercises, prescribed.membership_id);
        if (current_index == null) {
            try appendModification(output, &written, .{ .kind = .exercise_removed, .membership_id = prescribed.membership_id, .prescribed_index = @intCast(prescribed_index) });
            continue;
        }
        if (current_index.? != prescribed_index)
            try appendModification(output, &written, .{ .kind = .exercise_reordered, .membership_id = prescribed.membership_id, .prescribed_index = @intCast(prescribed_index), .current_index = @intCast(current_index.?) });
        const current = workout.exercises[current_index.?];
        for (prescribed.sets, 0..) |prescribed_set, prescribed_set_index| {
            const current_set_index = findSetIndex(current.sets, prescribed_set.set_id);
            if (current_set_index == null) {
                try appendModification(output, &written, .{ .kind = .set_removed, .membership_id = prescribed.membership_id, .set_id = prescribed_set.set_id, .prescribed_index = @intCast(prescribed_set_index) });
            } else if (current_set_index.? != prescribed_set_index) {
                try appendModification(output, &written, .{ .kind = .set_reordered, .membership_id = prescribed.membership_id, .set_id = prescribed_set.set_id, .prescribed_index = @intCast(prescribed_set_index), .current_index = @intCast(current_set_index.?) });
            }
        }
        for (current.sets, 0..) |set, current_set_index| {
            if (findPrescribedSetIndex(prescribed.sets, set.id) == null)
                try appendModification(output, &written, .{ .kind = .set_added, .membership_id = current.id, .set_id = set.id, .current_index = @intCast(current_set_index) });
        }
    }
    for (workout.exercises, 0..) |exercise, current_index| {
        if (findPrescriptionIndex(workout.prescription, exercise.id) == null)
            try appendModification(output, &written, .{ .kind = .exercise_added, .membership_id = exercise.id, .current_index = @intCast(current_index) });
    }
    return output[0..written];
}

pub const StateWriteProposal = struct {
    methodology_id: tracking.Id,
    methodology_version: []const u8,
    expected_revision: ?[]const u8,
    next_state: caudex.canonical.MethodologyState,
    accepted_at: tracking.Timestamp,
    evaluation_fingerprint: []const u8,
};

pub const StateAcceptanceResult = union(enum) {
    accepted: StateWriteProposal,
    rejected: []const tracking.Issue,
};

pub fn proposeStateAcceptance(evaluation: caudex.canonical.EvaluationResult, expected_revision: ?[]const u8, accepted_at: tracking.Timestamp, issues: []tracking.Issue) WorkflowError!StateAcceptanceResult {
    if (!evaluation.ok or evaluation.nextMethodologyState == null) {
        if (issues.len == 0) return error.IssueBufferTooSmall;
        issues[0] = .{ .code = issue_codes.invalid_evaluation, .category = .validation, .severity = .@"error", .message = "The evaluation has no methodology-state proposal to accept." };
        return .{ .rejected = issues[0..1] };
    }
    const methodology_id = tracking.Id.parse(evaluation.metadata.methodology.id) catch {
        if (issues.len == 0) return error.IssueBufferTooSmall;
        issues[0] = .{ .code = issue_codes.invalid_identifier, .category = .validation, .severity = .@"error", .message = "The evaluation methodology ID is invalid." };
        return .{ .rejected = issues[0..1] };
    };
    return .{ .accepted = .{
        .methodology_id = methodology_id,
        .methodology_version = evaluation.metadata.methodology.version,
        .expected_revision = expected_revision,
        .next_state = evaluation.nextMethodologyState.?,
        .accepted_at = accepted_at,
        .evaluation_fingerprint = evaluation.metadata.resultFingerprint,
    } };
}

fn appendModification(output: []Modification, written: *usize, value: Modification) error{OutputBufferTooSmall}!void {
    if (written.* >= output.len) return error.OutputBufferTooSmall;
    output[written.*] = value;
    written.* += 1;
}

fn findMembershipIndex(values: []const tracking.ExerciseMembership, id: tracking.Id) ?usize {
    for (values, 0..) |value, index| if (value.id.eql(id)) return index;
    return null;
}

fn findSetIndex(values: []const tracking.TrackedSet, id: tracking.Id) ?usize {
    for (values, 0..) |value, index| if (value.id.eql(id)) return index;
    return null;
}

fn findPrescriptionIndex(values: []const tracking.PrescribedExercise, id: tracking.Id) ?usize {
    for (values, 0..) |value, index| if (value.membership_id.eql(id)) return index;
    return null;
}

fn findPrescribedSetIndex(values: []const tracking.PrescribedSet, id: tracking.Id) ?usize {
    for (values, 0..) |value, index| if (value.set_id.eql(id)) return index;
    return null;
}

pub fn completeForEvaluation(workout: tracking.Workout, catalog: []const caudex.canonical.Exercise, storage: CompletionStorage, issues: []tracking.Issue) CompletionError!CompletionResult {
    if (workout.status != .completed or workout.completed_at == null)
        return completionReject(issues, issue_codes.workout_not_completed, "Only a completed tracked workout can be converted for evaluation.");
    if (!provenanceConsistent(workout))
        return completionReject(issues, issue_codes.provenance_inconsistent, "Workout origin and provenance are inconsistent.");
    if (storage.exercises.len < workout.exercises.len) return error.ExerciseBufferTooSmall;
    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    var tag_offset: usize = 0;
    for (workout.exercises, 0..) |exercise, exercise_index| {
        if (!catalogContains(catalog, exercise.exercise_id.bytes))
            return completionReject(issues, issue_codes.catalog_reference_missing, "A tracked exercise is absent from the supplied catalog.");
        for (workout.exercises[0..exercise_index]) |prior| {
            if (prior.id.eql(exercise.id))
                return completionReject(issues, issue_codes.duplicate_identifier, "Exercise membership IDs must be unique.");
        }
        const set_end = std.math.add(usize, set_offset, exercise.sets.len) catch return error.SetBufferTooSmall;
        if (set_end > storage.sets.len) return error.SetBufferTooSmall;
        for (exercise.sets, set_offset..) |set, output_index| {
            if (setIdSeenBefore(workout.exercises, exercise_index, output_index - set_offset, set.id))
                return completionReject(issues, issue_codes.duplicate_identifier, "Set IDs must be unique within a workout.");
            if (set.status == .open or
                (set.status != .skipped and set.actual_metrics.len == 0))
                return completionReject(issues, issue_codes.actual_value_required, "Every executed set requires actual performance values.");
            const actual = try formatMetrics(set.actual_metrics, storage, &metric_offset);
            const targets = try formatMetrics(set.target_metrics, storage, &metric_offset);
            storage.sets[output_index] = .{
                .id = set.id.bytes,
                .kind = set.kind.bytes,
                .actualMetrics = actual,
                .targetMetrics = targets,
                .completedAt = if (set.recorded_at) |at| at.bytes else null,
                .status = switch (set.status) {
                    .completed => .completed,
                    .partial => .partial,
                    .failed => .failed,
                    .skipped => .skipped,
                    .open => unreachable,
                },
            };
        }
        const prescribed = findPrescription(workout.prescription, exercise.id);
        const tags = if (prescribed) |value| blk: {
            const tag_end = std.math.add(usize, tag_offset, value.tags.len) catch return error.TagBufferTooSmall;
            if (tag_end > storage.tags.len) return error.TagBufferTooSmall;
            for (value.tags, tag_offset..) |tag, index| storage.tags[index] = tag.bytes;
            const result = storage.tags[tag_offset..tag_end];
            tag_offset = tag_end;
            break :blk result;
        } else &.{};
        storage.exercises[exercise_index] = .{
            .exerciseId = exercise.exercise_id.bytes,
            .sets = storage.sets[set_offset..set_end],
            .tags = tags,
            .notes = if (prescribed) |value| value.notes else null,
        };
        set_offset = set_end;
    }
    return .{ .accepted = .{
        .id = workout.id.bytes,
        .startedAt = workout.started_at.bytes,
        .completedAt = workout.completed_at.?.bytes,
        .exercises = storage.exercises[0..workout.exercises.len],
    } };
}

fn formatMetrics(values: []const tracking.Metric, storage: CompletionStorage, offset: *usize) CompletionError![]const caudex.canonical.Metric {
    const end = std.math.add(usize, offset.*, values.len) catch return error.MetricBufferTooSmall;
    if (end > storage.metrics.len or end > storage.amount_bytes.len) return error.MetricBufferTooSmall;
    const start = offset.*;
    for (values, start..) |metric, index| {
        const amount = metric.value.value.format(&storage.amount_bytes[index]) catch return error.MetricBufferTooSmall;
        storage.metrics[index] = .{ .code = metric.code.bytes, .value = .{ .amount = amount, .unit = metric.value.unit.code() } };
    }
    offset.* = end;
    return storage.metrics[start..end];
}

fn provenanceConsistent(workout: tracking.Workout) bool {
    return switch (workout.origin) {
        .manual => workout.provenance == null and workout.prescription.len == 0,
        .template => workout.provenance != null and std.meta.activeTag(workout.provenance.?) == .template and workout.prescription.len > 0,
        .recommendation => blk: {
            if (workout.provenance == null or std.meta.activeTag(workout.provenance.?) != .recommendation or workout.prescription.len == 0)
                break :blk false;
            const value = workout.provenance.?.recommendation;
            break :blk value.input_fingerprint.len > 0 and value.result_fingerprint.len > 0 and value.methodology_version.len > 0;
        },
    };
}

fn setIdSeenBefore(exercises: []const tracking.ExerciseMembership, exercise_index: usize, set_index: usize, id: tracking.Id) bool {
    for (exercises[0..exercise_index]) |exercise| {
        for (exercise.sets) |set| if (set.id.eql(id)) return true;
    }
    for (exercises[exercise_index].sets[0..set_index]) |set| if (set.id.eql(id)) return true;
    return false;
}

fn findPrescription(values: []const tracking.PrescribedExercise, membership_id: tracking.Id) ?tracking.PrescribedExercise {
    for (values) |value| if (value.membership_id.eql(membership_id)) return value;
    return null;
}

fn completionReject(storage: []tracking.Issue, code: []const u8, message: []const u8) CompletionError!CompletionResult {
    if (storage.len == 0) return error.IssueBufferTooSmall;
    storage[0] = .{ .code = code, .category = .validation, .severity = .@"error", .message = message };
    return .{ .rejected = storage[0..1] };
}

pub fn instantiateRecommendation(result: caudex.canonical.RecommendationResult, catalog: []const caudex.canonical.Exercise, input: RecommendationInstantiation, storage: InstantiationStorage, issues: []tracking.Issue) WorkflowError!InstantiationResult {
    const recommendation = if (result.ok) result.recommendation else null;
    if (recommendation == null) return reject(issues, issue_codes.invalid_recommendation, "The recommendation result has no accepted recommendation.");
    if (result.metadata.inputFingerprint.len == 0 or result.metadata.resultFingerprint.len == 0 or
        tracking.Timestamp.parse(input.created_at.bytes) catch null == null or
        tracking.Id.parse(input.accepted_recommendation_id.bytes) catch null == null)
        return reject(issues, issue_codes.invalid_recommendation, "Recommendation provenance or host-supplied time is invalid.");
    if (!validInstantiationIds(input.ids, recommendation.?.exercises))
        return reject(issues, issue_codes.invalid_identifier, "Instantiation IDs are missing, invalid, or duplicated.");
    const set_count = recommendationSetCount(recommendation.?.exercises) orelse
        return reject(issues, issue_codes.invalid_recommendation, "The recommendation exceeds supported set bounds.");
    if (storage.exercises.len < recommendation.?.exercises.len or storage.prescription_exercises.len < recommendation.?.exercises.len)
        return error.ExerciseBufferTooSmall;
    if (storage.sets.len < set_count or storage.prescription_sets.len < set_count)
        return error.SetBufferTooSmall;

    var set_offset: usize = 0;
    var metric_offset: usize = 0;
    for (recommendation.?.exercises, 0..) |exercise, exercise_index| {
        if (!catalogContains(catalog, exercise.exerciseId))
            return reject(issues, issue_codes.catalog_reference_missing, "A prescribed exercise is absent from the supplied catalog.");
        const set_start = set_offset;
        for (exercise.sets) |set| {
            const metrics = convertMetrics(set.targetMetrics, storage.metrics, &metric_offset) catch
                return reject(issues, issue_codes.invalid_metric, "A prescribed target metric is invalid.");
            const set_id = input.ids.set_ids[set_offset];
            const kind = tracking.Id.parse(set.kind) catch
                return reject(issues, issue_codes.invalid_identifier, "A prescribed set kind is invalid.");
            storage.sets[set_offset] = .{ .id = set_id, .kind = kind, .target_metrics = metrics };
            storage.prescription_sets[set_offset] = .{ .set_id = set_id, .kind = kind, .target_metrics = metrics };
            set_offset += 1;
        }
        const membership_id = input.ids.membership_ids[exercise_index];
        const exercise_id = tracking.Id.parse(exercise.exerciseId) catch
            return reject(issues, issue_codes.invalid_identifier, "A prescribed exercise ID is invalid.");
        storage.exercises[exercise_index] = .{
            .id = membership_id,
            .exercise_id = exercise_id,
            .sets = storage.sets[set_start..set_offset],
        };
        storage.prescription_exercises[exercise_index] = .{
            .membership_id = membership_id,
            .exercise_id = exercise_id,
            .sets = storage.prescription_sets[set_start..set_offset],
        };
    }
    return .{ .accepted = .{
        .id = input.ids.workout_id,
        .scope = input.scope,
        .revision = 1,
        .status = .active,
        .started_at = input.created_at,
        .exercises = storage.exercises[0..recommendation.?.exercises.len],
        .origin = .recommendation,
        .provenance = .{ .recommendation = .{
            .accepted_recommendation_id = input.accepted_recommendation_id,
            .input_fingerprint = result.metadata.inputFingerprint,
            .result_fingerprint = result.metadata.resultFingerprint,
            .methodology_id = tracking.Id.parse(result.metadata.methodology.id) catch
                return reject(issues, issue_codes.invalid_identifier, "The methodology ID is invalid."),
            .methodology_version = result.metadata.methodology.version,
            .methodology_config_version = result.metadata.methodology.configVersion,
            .methodology_state_revision = input.methodology_state_revision,
            .methodology_state_fingerprint = input.methodology_state_fingerprint,
            .athlete_profile_id = input.athlete_profile_id,
            .athlete_profile_revision = input.athlete_profile_revision,
            .athlete_profile_fingerprint = input.athlete_profile_fingerprint,
            .training_location_id = input.training_location_id,
            .effective_equipment_ids = input.effective_equipment_ids,
            .available_minutes = input.available_minutes,
            .hard_maximum_minutes = input.hard_maximum_minutes,
            .session_goal_id = input.session_goal_id,
            .active_restriction_ids = input.active_restriction_ids,
        } },
        .prescription = storage.prescription_exercises[0..recommendation.?.exercises.len],
    } };
}

pub fn instantiateTemplate(template: WorkoutTemplate, catalog: []const caudex.canonical.Exercise, input: TemplateInstantiation, storage: InstantiationStorage, issues: []tracking.Issue) WorkflowError!InstantiationResult {
    if (!validTemplate(template) or tracking.Timestamp.parse(input.created_at.bytes) catch null == null)
        return reject(issues, issue_codes.invalid_template, "The template version or bounds are invalid.");
    const set_count = templateSetCount(template.exercises) orelse
        return reject(issues, issue_codes.invalid_template, "The template exceeds supported set bounds.");
    if (input.ids.membership_ids.len != template.exercises.len or input.ids.set_ids.len != set_count or !uniqueIds(input.ids.membership_ids) or !uniqueIds(input.ids.set_ids))
        return reject(issues, issue_codes.invalid_identifier, "Instantiation IDs are missing, invalid, or duplicated.");
    if (storage.exercises.len < template.exercises.len or storage.prescription_exercises.len < template.exercises.len)
        return error.ExerciseBufferTooSmall;
    if (storage.sets.len < set_count or storage.prescription_sets.len < set_count)
        return error.SetBufferTooSmall;
    var set_offset: usize = 0;
    for (template.exercises, 0..) |exercise, exercise_index| {
        if (!catalogContains(catalog, exercise.exercise_id.bytes))
            return reject(issues, issue_codes.catalog_reference_missing, "A template exercise is absent from the supplied catalog.");
        const set_start = set_offset;
        for (exercise.sets) |set| {
            const kind = set.kind orelse tracking.Id{ .bytes = "working" };
            const set_id = input.ids.set_ids[set_offset];
            storage.sets[set_offset] = .{ .id = set_id, .kind = kind, .target_metrics = set.target_metrics };
            storage.prescription_sets[set_offset] = .{ .set_id = set_id, .kind = kind, .target_metrics = set.target_metrics };
            set_offset += 1;
        }
        storage.exercises[exercise_index] = .{ .id = input.ids.membership_ids[exercise_index], .exercise_id = exercise.exercise_id, .sets = storage.sets[set_start..set_offset] };
        storage.prescription_exercises[exercise_index] = .{ .membership_id = input.ids.membership_ids[exercise_index], .exercise_id = exercise.exercise_id, .sets = storage.prescription_sets[set_start..set_offset], .notes = exercise.notes, .tags = exercise.tags };
    }
    return .{ .accepted = .{
        .id = input.ids.workout_id,
        .scope = input.scope,
        .revision = 1,
        .status = .active,
        .started_at = input.created_at,
        .exercises = storage.exercises[0..template.exercises.len],
        .origin = .template,
        .provenance = .{ .template = .{ .template_id = template.id, .template_revision = template.revision } },
        .prescription = storage.prescription_exercises[0..template.exercises.len],
    } };
}

fn validTemplate(template: WorkoutTemplate) bool {
    if (template.schema_version != template_schema_version or template.exercises.len > max_template_exercises or
        template.display_name.len == 0 or template.display_name.len > 200 or template.tags.len > max_tags or
        tracking.Id.parse(template.id.bytes) catch null == null)
        return false;
    for (template.tags) |tag| if (tracking.Id.parse(tag.bytes) catch null == null) return false;
    for (template.exercises) |exercise| {
        if (tracking.Id.parse(exercise.exercise_id.bytes) catch null == null or exercise.tags.len > max_tags) return false;
        for (exercise.tags) |tag| if (tracking.Id.parse(tag.bytes) catch null == null) return false;
        for (exercise.sets) |set| {
            if (set.kind) |kind| if (tracking.Id.parse(kind.bytes) catch null == null) return false;
            for (set.target_metrics) |metric| {
                if (tracking.Id.parse(metric.code.bytes) catch null == null or metric.value.value.scale > tracking.Decimal.max_scale)
                    return false;
            }
        }
    }
    return templateSetCount(template.exercises) != null;
}

fn convertMetrics(values: []const caudex.canonical.Metric, storage: []tracking.Metric, offset: *usize) error{InvalidMetric}![]const tracking.Metric {
    const end = std.math.add(usize, offset.*, values.len) catch return error.InvalidMetric;
    if (end > storage.len) return error.InvalidMetric;
    const start = offset.*;
    for (values, start..) |metric, index| {
        storage[index] = .{
            .code = tracking.Id.parse(metric.code) catch return error.InvalidMetric,
            .value = .{
                .value = tracking.Decimal.parse(metric.value.amount) catch return error.InvalidMetric,
                .unit = caudex.primitives.Unit.parse(metric.value.unit) catch return error.InvalidMetric,
            },
        };
    }
    offset.* = end;
    return storage[start..end];
}

fn validInstantiationIds(ids: InstantiationIds, exercises: []const caudex.canonical.ExerciseRecommendation) bool {
    const set_count = recommendationSetCount(exercises) orelse return false;
    return tracking.Id.parse(ids.workout_id.bytes) catch null != null and
        ids.membership_ids.len == exercises.len and ids.set_ids.len == set_count and
        uniqueIds(ids.membership_ids) and uniqueIds(ids.set_ids);
}

fn uniqueIds(ids: []const tracking.Id) bool {
    for (ids, 0..) |id, index| {
        if (tracking.Id.parse(id.bytes) catch null == null) return false;
        for (ids[0..index]) |prior| if (prior.eql(id)) return false;
    }
    return true;
}

fn catalogContains(catalog: []const caudex.canonical.Exercise, id: []const u8) bool {
    for (catalog) |exercise| if (std.mem.eql(u8, exercise.id, id)) return true;
    return false;
}

fn recommendationSetCount(exercises: []const caudex.canonical.ExerciseRecommendation) ?usize {
    var count: usize = 0;
    if (exercises.len > max_template_exercises) return null;
    for (exercises) |exercise| {
        count = std.math.add(usize, count, exercise.sets.len) catch return null;
        if (count > max_template_sets) return null;
    }
    return count;
}

fn templateSetCount(exercises: []const TemplateExercise) ?usize {
    var count: usize = 0;
    for (exercises) |exercise| {
        if (exercise.tags.len > max_tags) return null;
        count = std.math.add(usize, count, exercise.sets.len) catch return null;
        if (count > max_template_sets) return null;
    }
    return count;
}

fn reject(storage: []tracking.Issue, code: []const u8, message: []const u8) WorkflowError!InstantiationResult {
    if (storage.len == 0) return error.IssueBufferTooSmall;
    storage[0] = .{ .code = code, .category = .validation, .severity = .@"error", .message = message };
    return .{ .rejected = storage[0..1] };
}
