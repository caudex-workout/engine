//! Versioned, adapter-independent portable data protocol.

const std = @import("std");
const caudex = @import("caudex");
const tracking_protocol = @import("caudex_tracking_protocol");
const tracking = @import("caudex_tracking");

pub const schema_version: u32 = 1;
pub const max_input_bytes: usize = 4 * 1024 * 1024;
pub const max_records_per_kind: usize = 10_000;
pub const max_issues: usize = 256;
pub const max_program_blocks: usize = 128;
pub const max_program_session_roles_per_block: usize = 64;
pub const max_program_exercises_per_role: usize = 128;
pub const max_program_schedule_entries_per_block: usize = 366;

pub const CatalogReference = struct {
    hostScopeKey: []const u8,
    exerciseId: []const u8,
    catalogId: ?[]const u8 = null,
    catalogVersion: ?[]const u8 = null,
};

pub const CustomExerciseRecord = struct {
    hostScopeKey: []const u8,
    exercise: caudex.canonical.Exercise,
};

pub const TemplateRecord = struct {
    hostScopeKey: []const u8,
    template: caudex.canonical.WorkoutTemplate,
};

/// Host-neutral persistent athlete intent. Account credentials and host-only
/// presentation data are deliberately outside the portable contract.
pub const AthleteProfileRecord = struct {
    hostScopeKey: []const u8,
    profile: caudex.canonical.AthleteProfile,
};

/// A complete embedded definition, including host-custom definitions. A
/// portable import never requires the originating preset builder to exist.
pub const ProgramDefinitionRecord = struct {
    hostScopeKey: []const u8,
    definition: caudex.canonical.ProgramDefinitionDocument,
};

/// Athlete-specific program identity and its current explicit planning state.
pub const ProgramInstanceRecord = struct {
    hostScopeKey: []const u8,
    instance: caudex.canonical.ProgramInstanceDocument,
    planningState: ?caudex.canonical.ProgramPlanningState = null,
};

pub const ProgramOccurrenceRecord = struct {
    hostScopeKey: []const u8,
    occurrence: caudex.canonical.ProgramOccurrenceRecord,
};

pub const ActiveWorkoutRecord = struct {
    hostScopeKey: []const u8,
    athleteId: ?[]const u8 = null,
    workoutId: []const u8,
    snapshot: tracking_protocol.TrackingSnapshot,
};

pub const CompletedWorkoutRecord = struct {
    hostScopeKey: []const u8,
    workout: caudex.canonical.CompletedWorkout,
};

pub const AcceptedRecommendationRecord = struct {
    id: []const u8,
    hostScopeKey: []const u8,
    acceptedAt: []const u8,
    result: caudex.canonical.RecommendationResult,
};

pub const AcceptedProgramRecommendationRecord = struct {
    id: []const u8,
    hostScopeKey: []const u8,
    acceptedAt: []const u8,
    result: caudex.canonical.ProgramRecommendationResult,
};

pub const ProgressionStateRecord = struct {
    hostScopeKey: []const u8,
    stateId: []const u8,
    progressionId: []const u8,
    progressionVersion: []const u8,
    state: caudex.canonical.MethodologyState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const ProgramStateRecord = struct {
    hostScopeKey: []const u8,
    programId: []const u8,
    strategyId: []const u8,
    strategyVersion: []const u8,
    state: caudex.canonical.ProgramState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const MethodologyStateRecord = struct {
    hostScopeKey: []const u8,
    methodologyId: []const u8,
    methodologyVersion: []const u8,
    state: caudex.canonical.MethodologyState,
    revision: []const u8,
    updatedAt: []const u8,
};

pub const WorkflowRecoveryRecord = struct {
    hostScopeKey: []const u8,
    workflowId: []const u8,
    kind: []const u8,
    status: enum { pending, completed },
    idempotencyKey: []const u8,
    payload: std.json.Value,
    updatedAt: []const u8,
};

pub const Document = struct {
    schemaVersion: u32,
    exportedAt: []const u8,
    catalogReferences: []const CatalogReference = &.{},
    customExercises: []const CustomExerciseRecord = &.{},
    templates: []const TemplateRecord = &.{},
    athleteProfiles: []const AthleteProfileRecord = &.{},
    programDefinitions: []const ProgramDefinitionRecord = &.{},
    programInstances: []const ProgramInstanceRecord = &.{},
    programOccurrences: []const ProgramOccurrenceRecord = &.{},
    activeWorkouts: []const ActiveWorkoutRecord = &.{},
    completedWorkouts: []const CompletedWorkoutRecord = &.{},
    acceptedRecommendations: []const AcceptedRecommendationRecord = &.{},
    acceptedProgramRecommendations: []const AcceptedProgramRecommendationRecord = &.{},
    methodologyStates: []const MethodologyStateRecord = &.{},
    progressionStates: []const ProgressionStateRecord = &.{},
    programStates: []const ProgramStateRecord = &.{},
    workflowRecovery: []const WorkflowRecoveryRecord = &.{},
};

pub const ImportMode = enum { merge, replace };
pub const ConflictPolicy = enum { reject, keepExisting, overwrite };

pub const ImportRequest = struct {
    schemaVersion: u32,
    mode: ImportMode,
    conflictPolicy: ConflictPolicy,
    dryRun: bool = true,
    document: Document,
};

pub const Severity = enum { warning, @"error" };
pub const Issue = struct {
    code: []const u8,
    path: []const u8,
    message: []const u8,
    severity: Severity,
};

pub const Counts = struct {
    catalogReferences: usize = 0,
    customExercises: usize = 0,
    templates: usize = 0,
    athleteProfiles: usize = 0,
    programDefinitions: usize = 0,
    programInstances: usize = 0,
    programOccurrences: usize = 0,
    activeWorkouts: usize = 0,
    completedWorkouts: usize = 0,
    acceptedRecommendations: usize = 0,
    acceptedProgramRecommendations: usize = 0,
    methodologyStates: usize = 0,
    progressionStates: usize = 0,
    programStates: usize = 0,
    workflowRecovery: usize = 0,
};

pub const ImportPlan = struct {
    schemaVersion: u32 = schema_version,
    valid: bool,
    dryRun: bool,
    mode: ImportMode,
    conflictPolicy: ConflictPolicy,
    counts: Counts,
    issues: []const Issue,
};

pub const ExportOutcome = union(enum) {
    accepted: Document,
    rejected: []const Issue,
};

pub const ExportResult = struct {
    schemaVersion: u32 = schema_version,
    outcome: ExportOutcome,
};

pub const DecodeError = caudex.canonical_json.DecodeError || error{RecordLimitExceeded};

pub fn decodeDocument(allocator: std.mem.Allocator, input: []const u8) DecodeError!std.json.Parsed(Document) {
    const parsed = try caudex.canonical_json.decodeValue(Document, allocator, input, limits());
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateDocumentBounds(parsed.value);
    return parsed;
}

pub fn decodeImportRequest(allocator: std.mem.Allocator, input: []const u8) DecodeError!std.json.Parsed(ImportRequest) {
    const parsed = try caudex.canonical_json.decodeValue(ImportRequest, allocator, input, limits());
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version or parsed.value.document.schemaVersion != schema_version) return error.UnsupportedVersion;
    try validateDocumentBounds(parsed.value.document);
    return parsed;
}

pub fn encode(value: anytype, output: []u8) caudex.canonical_json.EncodeError![]const u8 {
    return caudex.canonical_json.encode(value, output);
}

pub fn planImport(request: ImportRequest, issue_storage: []Issue) error{IssueBufferTooSmall}!ImportPlan {
    var issue_count: usize = 0;
    if (request.schemaVersion != schema_version) try appendIssue(issue_storage, &issue_count, "portable.unsupported_version", "/schemaVersion", "Only portable schema version 1 is supported.");
    validateDocument(request.document, issue_storage, &issue_count) catch return error.IssueBufferTooSmall;
    return .{
        .valid = issue_count == 0,
        .dryRun = request.dryRun,
        .mode = request.mode,
        .conflictPolicy = request.conflictPolicy,
        .counts = counts(request.document),
        .issues = issue_storage[0..issue_count],
    };
}

pub fn validateExport(document: Document, issue_storage: []Issue) error{IssueBufferTooSmall}!ExportResult {
    var issue_count: usize = 0;
    validateDocument(document, issue_storage, &issue_count) catch return error.IssueBufferTooSmall;
    return .{ .outcome = if (issue_count == 0)
        .{ .accepted = document }
    else
        .{ .rejected = issue_storage[0..issue_count] } };
}

pub fn validateDocumentBounds(document: Document) error{RecordLimitExceeded}!void {
    inline for (.{
        document.catalogReferences.len,
        document.customExercises.len,
        document.templates.len,
        document.athleteProfiles.len,
        document.programDefinitions.len,
        document.programInstances.len,
        document.programOccurrences.len,
        document.activeWorkouts.len,
        document.completedWorkouts.len,
        document.acceptedRecommendations.len,
        document.acceptedProgramRecommendations.len,
        document.methodologyStates.len,
        document.progressionStates.len,
        document.programStates.len,
        document.workflowRecovery.len,
    }) |count| if (count > max_records_per_kind) return error.RecordLimitExceeded;
    for (document.activeWorkouts) |record| tracking_protocol.validateSnapshot(record.snapshot) catch return error.RecordLimitExceeded;
    for (document.programDefinitions) |record| {
        if (record.definition.blocks.len > max_program_blocks) return error.RecordLimitExceeded;
        for (record.definition.blocks) |block| {
            if (block.sessionRoles.len > max_program_session_roles_per_block) return error.RecordLimitExceeded;
            if (programScheduleLength(block.schedule) > max_program_schedule_entries_per_block) return error.RecordLimitExceeded;
            for (block.sessionRoles) |role| if (role.items.len > max_program_exercises_per_role) return error.RecordLimitExceeded;
        }
    }
}

fn validateDocument(document: Document, storage: []Issue, count: *usize) error{IssueBufferTooSmall}!void {
    validateDocumentBounds(document) catch try appendIssue(storage, count, "portable.record_limit_exceeded", "/", "The portable document exceeds a record or nested tracking limit.");
    if (document.schemaVersion != schema_version) try appendIssue(storage, count, "portable.unsupported_version", "/schemaVersion", "Only portable schema version 1 is supported.");
    if (tracking.Timestamp.parse(document.exportedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/exportedAt", "The export timestamp is not valid RFC 3339.");
    try validateUniqueAndSorted(CatalogReference, document.catalogReferences, storage, count, "/catalogReferences", catalogOrder);
    try validateUniqueAndSorted(CustomExerciseRecord, document.customExercises, storage, count, "/customExercises", exerciseOrder);
    try validateUniqueAndSorted(TemplateRecord, document.templates, storage, count, "/templates", templateOrder);
    try validateUniqueAndSorted(AthleteProfileRecord, document.athleteProfiles, storage, count, "/athleteProfiles", athleteProfileOrder);
    try validateUniqueAndSorted(ProgramDefinitionRecord, document.programDefinitions, storage, count, "/programDefinitions", programDefinitionOrder);
    try validateUniqueAndSorted(ProgramInstanceRecord, document.programInstances, storage, count, "/programInstances", programInstanceOrder);
    try validateUniqueAndSorted(ProgramOccurrenceRecord, document.programOccurrences, storage, count, "/programOccurrences", programOccurrenceOrder);
    try validateUniqueAndSorted(ActiveWorkoutRecord, document.activeWorkouts, storage, count, "/activeWorkouts", activeOrder);
    try validateUniqueAndSorted(CompletedWorkoutRecord, document.completedWorkouts, storage, count, "/completedWorkouts", completedOrder);
    try validateUniqueAndSorted(AcceptedRecommendationRecord, document.acceptedRecommendations, storage, count, "/acceptedRecommendations", acceptedOrder);
    try validateUniqueAndSorted(AcceptedProgramRecommendationRecord, document.acceptedProgramRecommendations, storage, count, "/acceptedProgramRecommendations", acceptedProgramOrder);
    try validateUniqueAndSorted(MethodologyStateRecord, document.methodologyStates, storage, count, "/methodologyStates", stateOrder);
    try validateUniqueAndSorted(ProgressionStateRecord, document.progressionStates, storage, count, "/progressionStates", progressionStateOrder);
    try validateUniqueAndSorted(ProgramStateRecord, document.programStates, storage, count, "/programStates", programStateOrder);
    try validateUniqueAndSorted(WorkflowRecoveryRecord, document.workflowRecovery, storage, count, "/workflowRecovery", recoveryOrder);
    var reference_index: usize = 0;
    var custom_index: usize = 0;
    while (reference_index < document.catalogReferences.len and custom_index < document.customExercises.len) {
        const reference = document.catalogReferences[reference_index];
        const custom = document.customExercises[custom_index];
        const order = scopedOrder(reference.hostScopeKey, reference.exerciseId, custom.hostScopeKey, custom.exercise.id);
        switch (order) {
            .lt => reference_index += 1,
            .gt => custom_index += 1,
            .eq => {
                try appendIssue(storage, count, "portable.catalog_source_conflict", "/catalogReferences", "An exercise cannot be both an external catalog reference and an embedded custom exercise in one scope.");
                reference_index += 1;
                custom_index += 1;
            },
        }
    }
    for (document.activeWorkouts) |record| {
        if (record.snapshot.workouts.len != 1 or
            !std.mem.eql(u8, record.snapshot.workouts[0].id, record.workoutId) or
            !std.mem.eql(u8, record.snapshot.workouts[0].scope.hostScopeKey, record.hostScopeKey) or
            !optionalStringsEqual(record.snapshot.workouts[0].scope.athleteId, record.athleteId) or
            record.snapshot.workouts[0].status != .active)
            try appendIssue(storage, count, "portable.active_workout_inconsistent", "/activeWorkouts", "An active-workout record must contain exactly its matching active workout and scope.");
        for (record.snapshot.workouts) |workout| {
            for (workout.exercises) |exercise| {
                if (!hasExercise(document, record.hostScopeKey, exercise.exerciseId)) try appendIssue(storage, count, "portable.catalog_reference_missing", "/activeWorkouts", "An active workout exercise has no catalog reference or embedded custom exercise.");
                for (exercise.sets) |set| {
                    try validateMetrics(set.targetMetrics, storage, count, "/activeWorkouts");
                    try validateMetrics(set.actualMetrics, storage, count, "/activeWorkouts");
                }
            }
        }
    }
    for (document.completedWorkouts) |record| {
        if (tracking.Timestamp.parse(record.workout.startedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/completedWorkouts", "A completed workout start timestamp is invalid.");
        if (tracking.Timestamp.parse(record.workout.completedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/completedWorkouts", "A completed workout completion timestamp is invalid.");
        for (record.workout.exercises) |exercise| {
            if (!hasExercise(document, record.hostScopeKey, exercise.exerciseId)) try appendIssue(storage, count, "portable.catalog_reference_missing", "/completedWorkouts", "A completed workout exercise has no catalog reference or embedded custom exercise.");
            for (exercise.sets) |set| {
                try validateMetrics(set.targetMetrics, storage, count, "/completedWorkouts");
                try validateMetrics(set.actualMetrics, storage, count, "/completedWorkouts");
            }
        }
    }
    for (document.templates) |record| for (record.template.exercises) |exercise| for (exercise.sets) |set| try validateMetrics(set.targetMetrics, storage, count, "/templates");
    for (document.acceptedRecommendations) |record| {
        if (tracking.Timestamp.parse(record.acceptedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/acceptedRecommendations", "An accepted-recommendation timestamp is invalid.");
        if (record.result.recommendation) |recommendation| try validateSessionMetrics(recommendation, storage, count);
        for (record.result.alternatives) |alternative| try validateSessionMetrics(alternative, storage, count);
    }
    for (document.acceptedProgramRecommendations) |record| {
        if (tracking.Timestamp.parse(record.acceptedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/acceptedProgramRecommendations", "An accepted program recommendation timestamp is invalid.");
        if (record.result.recommendation) |recommendation| try validateSessionMetrics(recommendation, storage, count);
    }
    for (document.methodologyStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/methodologyStates", "A methodology-state timestamp is invalid.");
    for (document.progressionStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/progressionStates", "A progression-state timestamp is invalid.");
    for (document.programStates) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/programStates", "A program-state timestamp is invalid.");
    for (document.workflowRecovery) |record| if (tracking.Timestamp.parse(record.updatedAt)) |_| {} else |_| try appendIssue(storage, count, "portable.timestamp_invalid", "/workflowRecovery", "A workflow-recovery timestamp is invalid.");
    for (document.athleteProfiles) |record| {
        if (record.profile.schemaVersion != 1)
            try appendIssue(storage, count, "portable.profile_version_unsupported", "/athleteProfiles", "An athlete profile uses an unsupported schema version.");
        if (record.profile.id.len == 0)
            try appendIssue(storage, count, "portable.profile_id_invalid", "/athleteProfiles", "An athlete profile must have a stable non-empty ID.");
    }
    try validatePrograms(document, storage, count);
}

fn validatePrograms(document: Document, storage: []Issue, count: *usize) error{IssueBufferTooSmall}!void {
    for (document.programDefinitions) |record| {
        const definition = record.definition;
        if (definition.schemaVersion != 1)
            try appendIssue(storage, count, "portable.program_definition_version_unsupported", "/programDefinitions", "A program definition uses an unsupported schema version.");
        if (record.hostScopeKey.len == 0 or definition.id.len == 0 or definition.version.len == 0 or definition.displayName.len == 0 or definition.configurationFingerprint.len == 0)
            try appendIssue(storage, count, "portable.program_definition_identity_invalid", "/programDefinitions", "A program definition must have a scope, ID, version, display name, and configuration fingerprint.");
        if (definition.blocks.len == 0)
            try appendIssue(storage, count, "portable.program_definition_empty", "/programDefinitions", "A program definition must contain at least one block.");
        if (definition.source) |source| switch (source.kind) {
            .built_in_preset => if (source.id == null or source.id.?.len == 0 or source.version == null or source.version.?.len == 0)
                try appendIssue(storage, count, "portable.program_definition_source_invalid", "/programDefinitions", "A built-in preset source must identify its preset and version."),
            .host_custom, .imported => {},
        };
        for (definition.blocks, 0..) |block, block_index| {
            if (block.id.len == 0 or block.microcycleCount == 0 or block.sessionRoles.len == 0)
                try appendIssue(storage, count, "portable.program_block_invalid", "/programDefinitions", "Every program block needs an ID, at least one microcycle, and at least one session role.");
            for (definition.blocks[0..block_index]) |previous| if (std.mem.eql(u8, previous.id, block.id))
                try appendIssue(storage, count, "portable.program_block_duplicate", "/programDefinitions", "Program block IDs must be unique within a definition.");
            try validateProgramSchedule(block, storage, count);
            for (block.sessionRoles, 0..) |role, role_index| {
                if (role.id.len == 0 or role.items.len == 0)
                    try appendIssue(storage, count, "portable.program_role_invalid", "/programDefinitions", "Every program session role needs an ID and at least one session item.");
                for (block.sessionRoles[0..role_index]) |previous| if (std.mem.eql(u8, previous.id, role.id))
                    try appendIssue(storage, count, "portable.program_role_duplicate", "/programDefinitions", "Session-role IDs must be unique within a program block.");
                for (role.items, 0..) |item, item_index| {
                    const item_id = programItemId(item);
                    if (item_id.len == 0)
                        try appendIssue(storage, count, "portable.program_item_identity_invalid", "/programDefinitions", "Every program session item needs a stable item ID.");
                    for (role.items[0..item_index]) |previous| if (std.mem.eql(u8, programItemId(previous), item_id))
                        try appendIssue(storage, count, "portable.program_item_duplicate", "/programDefinitions", "Session item IDs must be unique within a session role.");
                    const progression = programItemProgression(item) orelse role.defaultProgression orelse block.defaultProgression;
                    if (progression == null or progression.?.stateId.len == 0)
                        try appendIssue(storage, count, "portable.program_progression_assignment_missing", "/programDefinitions", "Every program session item must resolve a stable progression-state assignment.");
                    switch (item) {
                        .fixed => |fixed| if (fixed.exerciseId.len == 0)
                            try appendIssue(storage, count, "portable.program_fixed_exercise_missing", "/programDefinitions", "A fixed program item must reference an exercise."),
                        .dynamic => {},
                    }
                }
            }
        }
    }

    for (document.programInstances) |record| {
        const instance = record.instance;
        if (instance.schemaVersion != 1)
            try appendIssue(storage, count, "portable.program_instance_version_unsupported", "/programInstances", "A program instance uses an unsupported schema version.");
        if (record.hostScopeKey.len == 0 or instance.id.len == 0 or instance.athleteId.len == 0 or !validDefinitionReference(instance.definition))
            try appendIssue(storage, count, "portable.program_instance_identity_invalid", "/programInstances", "A program instance must have a scope, instance ID, athlete ID, and complete definition reference.");
        if (instance.startedOn) |started_on| if (!isValidDate(started_on))
            try appendIssue(storage, count, "portable.program_started_on_invalid", "/programInstances", "A program start date must use a valid YYYY-MM-DD calendar date.");
        const definition_record = findProgramDefinition(document, record.hostScopeKey, instance.definition);
        if (definition_record == null)
            try appendIssue(storage, count, "portable.program_definition_missing", "/programInstances", "A program instance must reference an embedded definition in the same scope.")
        else if (!std.mem.eql(u8, definition_record.?.definition.configurationFingerprint, instance.definition.configurationFingerprint))
            try appendIssue(storage, count, "portable.program_definition_fingerprint_mismatch", "/programInstances", "A program instance definition fingerprint does not match the embedded definition.");
        if (instance.lifecycle == .active and record.planningState == null)
            try appendIssue(storage, count, "portable.program_active_state_missing", "/programInstances", "An active program instance must carry its current planning state.");
        if (record.planningState) |state| try validatePlanningState(record, state, definition_record, storage, count);
    }

    for (document.programOccurrences) |record| {
        const occurrence = record.occurrence;
        if (occurrence.schemaVersion != 1)
            try appendIssue(storage, count, "portable.program_occurrence_version_unsupported", "/programOccurrences", "A program occurrence uses an unsupported schema version.");
        if (record.hostScopeKey.len == 0 or occurrence.instanceId.len == 0 or occurrence.blockId.len == 0 or occurrence.roleId.len == 0 or occurrence.occurrenceId.len == 0 or !validDefinitionReference(occurrence.definition))
            try appendIssue(storage, count, "portable.program_occurrence_identity_invalid", "/programOccurrences", "A program occurrence must carry complete scope, instance, definition, block, role, and occurrence identities.");
        const expected_after = switch (occurrence.status) {
            .completed, .skipped => std.math.add(u64, occurrence.beforeRevision, 1) catch null,
            .upcoming, .due, .overdue, .partial, .abandoned => occurrence.beforeRevision,
        };
        if (expected_after == null or occurrence.afterRevision != expected_after.?)
            try appendIssue(storage, count, "portable.program_occurrence_revision_invalid", "/programOccurrences", "A program occurrence revision must match its accepted status transition.");
        const instance_record = findProgramInstance(document, record.hostScopeKey, occurrence.instanceId);
        if (instance_record == null) {
            try appendIssue(storage, count, "portable.program_instance_missing", "/programOccurrences", "A program occurrence must reference an embedded instance in the same scope.");
            continue;
        }
        if (!definitionReferencesEqual(instance_record.?.instance.definition, occurrence.definition))
            try appendIssue(storage, count, "portable.program_occurrence_definition_mismatch", "/programOccurrences", "A program occurrence must reference the same definition as its instance.");
        if (instance_record.?.planningState) |state| if (occurrence.afterRevision > state.revision)
            try appendIssue(storage, count, "portable.program_occurrence_revision_ahead", "/programOccurrences", "A program occurrence cannot be ahead of the persisted planning-state revision.");
        const definition_record = findProgramDefinition(document, record.hostScopeKey, occurrence.definition);
        if (definition_record) |definition| {
            if (!definitionContainsRole(definition.definition, occurrence.blockId, occurrence.roleId))
                try appendIssue(storage, count, "portable.program_occurrence_role_missing", "/programOccurrences", "A program occurrence block and role must exist in its embedded definition.");
        }
    }
}

fn validatePlanningState(
    record: ProgramInstanceRecord,
    state: caudex.canonical.ProgramPlanningState,
    definition_record: ?ProgramDefinitionRecord,
    storage: []Issue,
    count: *usize,
) error{IssueBufferTooSmall}!void {
    if (state.schemaVersion != 1)
        try appendIssue(storage, count, "portable.program_state_version_unsupported", "/programInstances", "A program planning state uses an unsupported schema version.");
    if (!std.mem.eql(u8, state.instanceId, record.instance.id) or !definitionReferencesEqual(state.definition, record.instance.definition))
        try appendIssue(storage, count, "portable.program_state_inconsistent", "/programInstances", "A planning state must reference its containing instance and exact definition.");
    if (definition_record) |definition| {
        if (state.completed) {
            if (definition.definition.blocks.len == 0 or
                state.blockIndex != definition.definition.blocks.len - 1 or
                state.microcycleIndex != definition.definition.blocks[state.blockIndex].microcycleCount or
                state.sessionCursor != 0)
                try appendIssue(storage, count, "portable.program_state_cursor_invalid", "/programInstances", "A completed planning state must identify the exhausted final block with a reset session cursor.");
            return;
        }
        if (state.blockIndex >= definition.definition.blocks.len) {
            try appendIssue(storage, count, "portable.program_state_cursor_invalid", "/programInstances", "A planning-state block index is outside its definition.");
            return;
        }
        const block = definition.definition.blocks[state.blockIndex];
        if (state.microcycleIndex >= block.microcycleCount or state.sessionCursor >= block.sessionRoles.len)
            try appendIssue(storage, count, "portable.program_state_cursor_invalid", "/programInstances", "A planning-state microcycle or session cursor is outside its current block.");
    }
}

fn validateProgramSchedule(
    block: caudex.canonical.ProgramBlockDefinition,
    storage: []Issue,
    count: *usize,
) error{IssueBufferTooSmall}!void {
    if (programScheduleLength(block.schedule) == 0) {
        try appendIssue(storage, count, "portable.program_schedule_empty", "/programDefinitions", "Every program block needs a non-empty schedule.");
        return;
    }
    switch (block.schedule) {
        .rotation => |schedule| {
            for (schedule.roleIds) |role_id| try validateScheduledRole(block, role_id, storage, count);
            if (schedule.frequency) |frequency| try validateProgramFrequency(frequency, storage, count);
        },
        .fixedWeekdays => |schedule| for (schedule.entries, 0..) |entry, index| {
            try validateScheduledRole(block, entry.roleId, storage, count);
            for (schedule.entries[0..index]) |previous| if (previous.weekday == entry.weekday)
                try appendIssue(storage, count, "portable.program_schedule_weekday_duplicate", "/programDefinitions", "A fixed-weekday schedule cannot assign one weekday more than once.");
        },
        .frequencyTargeted => |schedule| {
            for (schedule.roleIds) |role_id| try validateScheduledRole(block, role_id, storage, count);
            try validateProgramFrequency(schedule.target, storage, count);
        },
        .explicitDates => |schedule| for (schedule.entries, 0..) |entry, index| {
            try validateScheduledRole(block, entry.roleId, storage, count);
            if (!isValidDate(entry.localDate))
                try appendIssue(storage, count, "portable.program_schedule_date_invalid", "/programDefinitions", "An explicit program schedule date must use a valid YYYY-MM-DD calendar date.");
            for (schedule.entries[0..index]) |previous| if (std.mem.eql(u8, previous.localDate, entry.localDate))
                try appendIssue(storage, count, "portable.program_schedule_date_duplicate", "/programDefinitions", "An explicit-date schedule cannot assign one date more than once.");
        },
        .hybrid => |schedule| {
            for (schedule.roleIds) |role_id| try validateScheduledRole(block, role_id, storage, count);
            try validateProgramFrequency(schedule.target, storage, count);
        },
    }
}

fn validateScheduledRole(
    block: caudex.canonical.ProgramBlockDefinition,
    role_id: []const u8,
    storage: []Issue,
    count: *usize,
) error{IssueBufferTooSmall}!void {
    for (block.sessionRoles) |role| if (std.mem.eql(u8, role.id, role_id)) return;
    try appendIssue(storage, count, "portable.program_schedule_role_missing", "/programDefinitions", "A program schedule references a role outside its block.");
}

fn validateProgramFrequency(
    frequency: caudex.canonical.ProgramFrequencyTarget,
    storage: []Issue,
    count: *usize,
) error{IssueBufferTooSmall}!void {
    if (frequency.sessions == 0 or frequency.days == 0)
        try appendIssue(storage, count, "portable.program_schedule_frequency_invalid", "/programDefinitions", "Program frequency sessions and days must both be positive.");
}

fn programScheduleLength(schedule: caudex.canonical.ProgramSchedule) usize {
    return switch (schedule) {
        .rotation => |value| value.roleIds.len,
        .fixedWeekdays => |value| value.entries.len,
        .frequencyTargeted => |value| value.roleIds.len,
        .explicitDates => |value| value.entries.len,
        .hybrid => |value| value.roleIds.len,
    };
}

fn programItemId(item: caudex.canonical.ProgramSessionItem) []const u8 {
    return switch (item) {
        inline else => |value| value.id,
    };
}

fn programItemProgression(item: caudex.canonical.ProgramSessionItem) ?caudex.canonical.ProgressionAssignment {
    return switch (item) {
        inline else => |value| value.progression,
    };
}

fn validateSessionMetrics(session: caudex.canonical.SessionRecommendation, storage: []Issue, count: *usize) error{IssueBufferTooSmall}!void {
    for (session.exercises) |exercise| for (exercise.sets) |set| try validateMetrics(set.targetMetrics, storage, count, "/acceptedRecommendations");
}

fn validateMetrics(metrics: []const caudex.canonical.Metric, storage: []Issue, count: *usize, path: []const u8) error{IssueBufferTooSmall}!void {
    for (metrics) |metric| {
        if (caudex.primitives.Decimal.parse(metric.value.amount)) |_| {} else |_| try appendIssue(storage, count, "portable.decimal_invalid", path, "A metric amount is not an exact canonical decimal.");
        _ = caudex.primitives.Unit.parse(metric.value.unit) catch try appendIssue(storage, count, "portable.unit_unknown", path, "A metric unit is not supported by this protocol version.");
    }
}

fn optionalStringsEqual(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

fn validateUniqueAndSorted(comptime T: type, values: []const T, storage: []Issue, count: *usize, path: []const u8, orderFn: fn (T, T) std.math.Order) error{IssueBufferTooSmall}!void {
    if (values.len < 2) return;
    for (values[1..], values[0..if (values.len == 0) 0 else values.len - 1]) |current, previous| {
        const order = orderFn(previous, current);
        if (order == .eq) try appendIssue(storage, count, "portable.duplicate_id", path, "Portable record IDs must be unique within each record kind.");
        if (order == .gt) try appendIssue(storage, count, "portable.order_invalid", path, "Portable records must be sorted by their stable key.");
    }
}

fn catalogOrder(left: CatalogReference, right: CatalogReference) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.exerciseId, right.hostScopeKey, right.exerciseId);
}
fn exerciseOrder(left: CustomExerciseRecord, right: CustomExerciseRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.exercise.id, right.hostScopeKey, right.exercise.id);
}
fn templateOrder(left: TemplateRecord, right: TemplateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.template.id, right.hostScopeKey, right.template.id);
}
fn athleteProfileOrder(left: AthleteProfileRecord, right: AthleteProfileRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.profile.id, right.hostScopeKey, right.profile.id);
}
fn programDefinitionOrder(left: ProgramDefinitionRecord, right: ProgramDefinitionRecord) std.math.Order {
    const scope_order = std.mem.order(u8, left.hostScopeKey, right.hostScopeKey);
    if (scope_order != .eq) return scope_order;
    const id_order = std.mem.order(u8, left.definition.id, right.definition.id);
    return if (id_order == .eq) std.mem.order(u8, left.definition.version, right.definition.version) else id_order;
}
fn programInstanceOrder(left: ProgramInstanceRecord, right: ProgramInstanceRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.instance.id, right.hostScopeKey, right.instance.id);
}
fn programOccurrenceOrder(left: ProgramOccurrenceRecord, right: ProgramOccurrenceRecord) std.math.Order {
    const scope_order = std.mem.order(u8, left.hostScopeKey, right.hostScopeKey);
    if (scope_order != .eq) return scope_order;
    const instance_order = std.mem.order(u8, left.occurrence.instanceId, right.occurrence.instanceId);
    return if (instance_order == .eq) std.mem.order(u8, left.occurrence.occurrenceId, right.occurrence.occurrenceId) else instance_order;
}
fn activeOrder(left: ActiveWorkoutRecord, right: ActiveWorkoutRecord) std.math.Order {
    const scope_order = std.mem.order(u8, left.hostScopeKey, right.hostScopeKey);
    if (scope_order != .eq) return scope_order;
    const athlete_order = std.mem.order(u8, left.athleteId orelse "", right.athleteId orelse "");
    return if (athlete_order == .eq) std.mem.order(u8, left.workoutId, right.workoutId) else athlete_order;
}
fn completedOrder(left: CompletedWorkoutRecord, right: CompletedWorkoutRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.workout.id, right.hostScopeKey, right.workout.id);
}
fn acceptedOrder(left: AcceptedRecommendationRecord, right: AcceptedRecommendationRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.id, right.hostScopeKey, right.id);
}
fn acceptedProgramOrder(left: AcceptedProgramRecommendationRecord, right: AcceptedProgramRecommendationRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.id, right.hostScopeKey, right.id);
}
fn stateOrder(left: MethodologyStateRecord, right: MethodologyStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.methodologyId, right.hostScopeKey, right.methodologyId);
}
fn progressionStateOrder(left: ProgressionStateRecord, right: ProgressionStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.stateId, right.hostScopeKey, right.stateId);
}
fn programStateOrder(left: ProgramStateRecord, right: ProgramStateRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.programId, right.hostScopeKey, right.programId);
}
fn recoveryOrder(left: WorkflowRecoveryRecord, right: WorkflowRecoveryRecord) std.math.Order {
    return scopedOrder(left.hostScopeKey, left.workflowId, right.hostScopeKey, right.workflowId);
}

fn scopedOrder(left_scope: []const u8, left_id: []const u8, right_scope: []const u8, right_id: []const u8) std.math.Order {
    const scope_order = std.mem.order(u8, left_scope, right_scope);
    return if (scope_order == .eq) std.mem.order(u8, left_id, right_id) else scope_order;
}

fn hasExercise(document: Document, scope: []const u8, id: []const u8) bool {
    for (document.catalogReferences) |reference| if (std.mem.eql(u8, reference.hostScopeKey, scope) and std.mem.eql(u8, reference.exerciseId, id)) return true;
    for (document.customExercises) |record| if (std.mem.eql(u8, record.hostScopeKey, scope) and std.mem.eql(u8, record.exercise.id, id)) return true;
    return false;
}

fn findProgramDefinition(document: Document, scope: []const u8, reference: caudex.canonical.ProgramDefinitionReference) ?ProgramDefinitionRecord {
    var lower: usize = 0;
    var upper = document.programDefinitions.len;
    while (lower < upper) {
        const middle = lower + (upper - lower) / 2;
        const record = document.programDefinitions[middle];
        const scope_order = std.mem.order(u8, record.hostScopeKey, scope);
        const id_order = if (scope_order == .eq) std.mem.order(u8, record.definition.id, reference.id) else scope_order;
        const order = if (id_order == .eq) std.mem.order(u8, record.definition.version, reference.version) else id_order;
        switch (order) {
            .lt => lower = middle + 1,
            .gt => upper = middle,
            .eq => return record,
        }
    }
    return null;
}

fn findProgramInstance(document: Document, scope: []const u8, instance_id: []const u8) ?ProgramInstanceRecord {
    var lower: usize = 0;
    var upper = document.programInstances.len;
    while (lower < upper) {
        const middle = lower + (upper - lower) / 2;
        const record = document.programInstances[middle];
        const order = scopedOrder(record.hostScopeKey, record.instance.id, scope, instance_id);
        switch (order) {
            .lt => lower = middle + 1,
            .gt => upper = middle,
            .eq => return record,
        }
    }
    return null;
}

fn validDefinitionReference(reference: caudex.canonical.ProgramDefinitionReference) bool {
    return reference.id.len != 0 and reference.version.len != 0 and reference.configurationFingerprint.len != 0;
}

fn definitionReferencesEqual(left: caudex.canonical.ProgramDefinitionReference, right: caudex.canonical.ProgramDefinitionReference) bool {
    return std.mem.eql(u8, left.id, right.id) and
        std.mem.eql(u8, left.version, right.version) and
        std.mem.eql(u8, left.configurationFingerprint, right.configurationFingerprint);
}

fn definitionContainsRole(definition: caudex.canonical.ProgramDefinitionDocument, block_id: []const u8, role_id: []const u8) bool {
    for (definition.blocks) |block| {
        if (!std.mem.eql(u8, block.id, block_id)) continue;
        for (block.sessionRoles) |role| if (std.mem.eql(u8, role.id, role_id)) return true;
        return false;
    }
    return false;
}

fn isValidDate(value: []const u8) bool {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') return false;
    inline for (.{ 0, 1, 2, 3, 5, 6, 8, 9 }) |index| if (!std.ascii.isDigit(value[index])) return false;
    const year = std.fmt.parseUnsigned(u16, value[0..4], 10) catch return false;
    const month = std.fmt.parseUnsigned(u8, value[5..7], 10) catch return false;
    const day = std.fmt.parseUnsigned(u8, value[8..10], 10) catch return false;
    if (year == 0 or month == 0 or month > 12 or day == 0) return false;
    const leap_year = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
    const maximum_day: u8 = switch (month) {
        2 => if (leap_year) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
    return day <= maximum_day;
}

fn appendIssue(storage: []Issue, count: *usize, code: []const u8, path: []const u8, message: []const u8) error{IssueBufferTooSmall}!void {
    if (count.* >= storage.len or count.* >= max_issues) return error.IssueBufferTooSmall;
    storage[count.*] = .{ .code = code, .path = path, .message = message, .severity = .@"error" };
    count.* += 1;
}

fn counts(document: Document) Counts {
    return .{
        .catalogReferences = document.catalogReferences.len,
        .customExercises = document.customExercises.len,
        .templates = document.templates.len,
        .athleteProfiles = document.athleteProfiles.len,
        .programDefinitions = document.programDefinitions.len,
        .programInstances = document.programInstances.len,
        .programOccurrences = document.programOccurrences.len,
        .activeWorkouts = document.activeWorkouts.len,
        .completedWorkouts = document.completedWorkouts.len,
        .acceptedRecommendations = document.acceptedRecommendations.len,
        .acceptedProgramRecommendations = document.acceptedProgramRecommendations.len,
        .methodologyStates = document.methodologyStates.len,
        .progressionStates = document.progressionStates.len,
        .programStates = document.programStates.len,
        .workflowRecovery = document.workflowRecovery.len,
    };
}

fn limits() caudex.canonical_json.Limits {
    return .{ .max_input_bytes = max_input_bytes, .max_nesting = 32, .max_collection_items = 100_000, .max_string_bytes = 64 * 1024 };
}
