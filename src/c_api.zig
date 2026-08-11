const std = @import("std");
const caudex = @import("caudex");
const canonical = caudex.canonical;
const canonical_json = caudex.canonical_json;
const athlete_profile = caudex.athlete_profile;
const double_progression = caudex.double_progression;
const discovery = caudex.discovery;
const engine = caudex.engine;
const methodology = caudex.methodology;
const primitives = caudex.primitives;
const programming = caudex.programming;
const program_planning = caudex.program_planning;
const rpe_top_set_backoff = caudex.rpe_top_set_backoff;
const training = caudex.training;
const tracking = @import("caudex_tracking");
const tracking_protocol = @import("caudex_tracking_protocol");
const workflows = @import("caudex_workflows");
const portable = @import("caudex_portable");

pub const abi_version: u32 = 2;
// The C contract intentionally exposes a smaller result bound than the
// portable request envelope. Keep this separate from the input limit so a
// caller can never infer an unbounded output allocation from a valid request.
const max_result_bytes: usize = 1 * 1024 * 1024;
const max_execution_request_bytes: usize = portable.max_input_bytes + 1024;
const tracking_workspace_items: usize = 4096;

pub const Status = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    out_of_memory = 2,
    invalid_request = 3,
    unsupported_version = 4,
    unsupported_methodology = 5,
    output_limit_reached = 6,
    insufficient_output = 7,
    internal_error = 255,
};

const OwnedBuffer = struct {
    data: ?[*]u8 = null,
    len: usize = 0,
    capacity: usize = 0,
};

const RuntimeAllocator = std.heap.DebugAllocator(.{});

pub const Runtime = struct {
    debug_allocator: RuntimeAllocator,

    fn allocator(self: *Runtime) std.mem.Allocator {
        return self.debug_allocator.allocator();
    }
};

pub export fn caudex_abi_version() callconv(.c) u32 {
    return abi_version;
}

pub export fn caudex_runtime_create(
    out_runtime: ?*?*Runtime,
) callconv(.c) Status {
    const destination = out_runtime orelse return .invalid_argument;
    const runtime = std.heap.page_allocator.create(Runtime) catch
        return .out_of_memory;
    runtime.* = .{ .debug_allocator = .init };
    destination.* = runtime;
    return .ok;
}

pub export fn caudex_runtime_destroy(runtime: ?*Runtime) callconv(.c) void {
    if (runtime) |value| {
        _ = value.debug_allocator.deinit();
        std.heap.page_allocator.destroy(value);
    }
}

pub export fn caudex_runtime_execute(
    runtime: ?*Runtime,
    request_data: ?[*]const u8,
    request_len: usize,
    output_data: ?[*]u8,
    output_capacity: usize,
    out_required: ?*usize,
) callconv(.c) Status {
    const active = runtime orelse return .invalid_argument;
    const required = out_required orelse return .invalid_argument;
    required.* = 0;
    if (request_data == null and request_len != 0) return .invalid_argument;
    if (output_data == null and output_capacity != 0) return .invalid_argument;
    const input = if (request_len == 0)
        @as([]const u8, &.{})
    else
        request_data.?[0..request_len];

    var result: OwnedBuffer = .{};
    executeDispatch(active, input, &result) catch |err| return statusForError(err);
    defer if (result.data) |data| active.allocator().free(data[0..result.capacity]);
    required.* = result.len;
    if (output_capacity < result.len) return .insufficient_output;
    if (result.len != 0) @memcpy(output_data.?[0..result.len], result.data.?[0..result.len]);
    return .ok;
}

const ExecuteError = canonical_json.DecodeError || engine.RecommendError ||
    error{InvalidRequest};

const Operation = enum {
    recommend,
    evaluate,
    recommendProgram,
    evaluateProgram,
    applyTrackingCommand,
    applyTrackingBatch,
    instantiateRecommendation,
    instantiateTemplate,
    completeForEvaluation,
    listMethodologies,
    describeMethodology,
    validateMethodologyConfig,
    validateMethodologyState,
    listCapabilities,
    exportPortable,
    validatePortableImport,
    validateProgramDefinition,
    instantiateProgram,
    resolvePlannedSession,
    proposeProgramAdvancement,
};

const ExecutionRequest = struct {
    schemaVersion: u32,
    operation: Operation,
    payload: std.json.Value,
};

fn executeDispatch(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = try canonical_json.decodeValue(ExecutionRequest, runtime.allocator(), input, .{ .max_input_bytes = max_execution_request_bytes, .max_collection_items = 100_000 });
    defer document.deinit();
    if (document.value.schemaVersion != 1) return error.UnsupportedVersion;
    const payload = runtime.allocator().alloc(u8, portable.max_input_bytes) catch return error.OutOfMemory;
    defer runtime.allocator().free(payload);
    var writer: std.Io.Writer = .fixed(payload);
    std.json.Stringify.value(document.value.payload, .{}, &writer) catch return error.InvalidRequest;
    return switch (document.value.operation) {
        .recommend => executeRecommendation(runtime, writer.buffered(), out),
        .evaluate => executeEvaluation(runtime, writer.buffered(), out),
        .recommendProgram => executeProgramRecommendation(runtime, writer.buffered(), out),
        .evaluateProgram => executeProgramEvaluation(runtime, writer.buffered(), out),
        .applyTrackingCommand => executeTrackingCommand(runtime, writer.buffered(), out),
        .applyTrackingBatch => executeTrackingBatch(runtime, writer.buffered(), out),
        .instantiateRecommendation => executeRecommendationInstantiation(runtime, writer.buffered(), out),
        .instantiateTemplate => executeTemplateInstantiation(runtime, writer.buffered(), out),
        .completeForEvaluation => executeCompletionConversion(runtime, writer.buffered(), out),
        .listMethodologies => executeListMethodologies(runtime, writer.buffered(), out),
        .describeMethodology => executeDescribeMethodology(runtime, writer.buffered(), out),
        .validateMethodologyConfig => executeMethodologyValidation(runtime, writer.buffered(), false, out),
        .validateMethodologyState => executeMethodologyValidation(runtime, writer.buffered(), true, out),
        .listCapabilities => executeListCapabilities(runtime, writer.buffered(), out),
        .exportPortable => executePortableExport(runtime, writer.buffered(), out),
        .validatePortableImport => executePortableImportValidation(runtime, writer.buffered(), out),
        .validateProgramDefinition => executeProgramDefinitionValidation(runtime, writer.buffered(), out),
        .instantiateProgram => executeProgramInstantiation(runtime, writer.buffered(), out),
        .resolvePlannedSession => executePlannedSessionResolution(runtime, writer.buffered(), out),
        .proposeProgramAdvancement => executeProgramAdvancement(runtime, writer.buffered(), out),
    };
}

fn executeProgramDefinitionValidation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const request = try canonical_json.decodeValue(
        canonical.ProgramDefinitionValidationRequest,
        runtime.allocator(),
        input,
        .{},
    );
    defer request.deinit();
    if (request.value.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const definition = try translateProgramDefinition(allocator, request.value.definition);
    const domain_issues = allocator.alloc(program_planning.Issue, 128) catch
        return error.OutOfMemory;
    const issues = program_planning.validateDefinition(definition, domain_issues) catch
        return error.OutputLimitReached;
    const wire_issues = try programPlanningIssuesToCanonical(allocator, issues);
    return encodeOwned(runtime, canonical.ProgramDefinitionValidationResult{
        .valid = wire_issues.len == 0,
        .issues = wire_issues,
    }, out);
}

fn executeProgramInstantiation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const request = try canonical_json.decodeValue(
        canonical.ProgramInstantiationRequest,
        runtime.allocator(),
        input,
        .{},
    );
    defer request.deinit();
    if (request.value.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const definition = try translateProgramDefinition(allocator, request.value.definition);
    var issue_storage: [128]program_planning.Issue = undefined;
    const issues = program_planning.validateDefinition(definition, &issue_storage) catch
        return error.OutputLimitReached;
    if (issues.len != 0) return error.InvalidRequest;
    _ = primitives.Id.parse(request.value.instanceId) catch return error.InvalidRequest;
    _ = primitives.Id.parse(request.value.athleteId) catch return error.InvalidRequest;
    if (request.value.startedOn) |date| try validateLocalDateText(date);

    const reference = canonicalDefinitionReference(request.value.definition);
    const instance = canonical.ProgramInstanceDocument{
        .id = request.value.instanceId,
        .athleteId = request.value.athleteId,
        .definition = reference,
        .startedOn = request.value.startedOn,
        .lifecycle = request.value.lifecycle,
        .configuration = request.value.configuration,
    };
    return encodeOwned(runtime, canonical.ProgramInstantiationResult{
        .instance = instance,
        .state = .{
            .instanceId = instance.id,
            .definition = reference,
            .revision = 0,
            .blockIndex = 0,
            .microcycleIndex = 0,
            .sessionCursor = 0,
            .completedOccurrenceCount = 0,
            .strategyState = request.value.strategyState,
        },
    }, out);
}

fn executePlannedSessionResolution(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const request = try canonical_json.decodeValue(
        canonical.ProgramResolutionRequest,
        runtime.allocator(),
        input,
        .{ .max_collection_items = 100_000 },
    );
    defer request.deinit();
    if (request.value.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    try validateProgramSnapshotReferences(
        request.value.definition,
        request.value.instance,
        request.value.state,
    );
    const definition = try translateProgramDefinition(allocator, request.value.definition);
    const instance = try translateProgramInstance(request.value.instance);
    const state = try translateProgramPlanningState(request.value.state);
    const local_date: ?program_planning.LocalDate = if (request.value.localDate) |date| blk: {
        try validateLocalDateText(date.isoDate);
        break :blk .{
            .iso_date = date.isoDate,
            .weekday = @enumFromInt(@intFromEnum(date.weekday)),
        };
    } else null;
    const occurrence_storage = allocator.alloc(u8, 1024) catch return error.OutOfMemory;
    const planned = program_planning.resolvePlannedSession(
        occurrence_storage,
        definition,
        instance,
        state,
        local_date,
    ) catch return error.InvalidRequest;
    const block_index: usize = request.value.state.blockIndex;
    if (block_index >= request.value.definition.blocks.len) return error.InvalidRequest;
    const source_block = request.value.definition.blocks[block_index];
    const source_role = findCanonicalProgramRole(source_block, planned.role.id) orelse
        return error.InvalidRequest;
    const catalog = try translateCatalog(allocator, request.value.catalog);
    const exercises = allocator.alloc(
        canonical.ProgramExerciseSlot,
        planned.role.items.len,
    ) catch return error.OutOfMemory;
    for (planned.role.items, source_role.items, exercises) |item, source_item, *exercise| {
        const exercise_id = switch (item) {
            .fixed => |fixed| fixed.exercise_id,
            .slot => program_planning.resolveSlotBasic(item, catalog) orelse
                return error.InvalidRequest,
        };
        if (catalog.find(primitives.Id.parse(exercise_id) catch return error.InvalidRequest) == null) {
            return error.InvalidRequest;
        }
        exercise.* = .{
            .slotId = item.id(),
            .exerciseId = exercise_id,
            .progression = resolveCanonicalProgression(
                source_block,
                source_role,
                source_item,
            ) orelse return error.InvalidRequest,
        };
    }
    const training_context = try plannedTrainingContext(allocator, source_block, source_role);
    return encodeOwned(runtime, canonical.PlannedSessionIntentDocument{
        .instanceId = request.value.instance.id,
        .definition = request.value.instance.definition,
        .blockId = source_block.id,
        .roleId = source_role.id,
        .occurrenceId = planned.occurrence.id,
        .scheduledDate = planned.occurrence.scheduled_date,
        .scheduleStatus = @enumFromInt(@intFromEnum(planned.occurrence.status)),
        .planningStateRevision = request.value.state.revision,
        .program = .{
            .strategy = request.value.definition.strategy,
            .state = request.value.state.strategyState,
            .exercises = exercises,
            .trainingContext = training_context,
        },
    }, out);
}

fn executeProgramAdvancement(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const request = try canonical_json.decodeValue(
        canonical.ProgramAdvancementRequest,
        runtime.allocator(),
        input,
        .{ .max_collection_items = 100_000 },
    );
    defer request.deinit();
    if (request.value.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    try validateProgramSnapshotReferences(
        request.value.definition,
        request.value.instance,
        request.value.state,
    );
    if (request.value.intent.planningStateRevision != request.value.state.revision or
        !std.mem.eql(u8, request.value.intent.instanceId, request.value.instance.id) or
        !canonicalDefinitionReferencesEqual(
            request.value.intent.definition,
            request.value.state.definition,
        )) return error.InvalidRequest;
    const definition = try translateProgramDefinition(allocator, request.value.definition);
    const state = try translateProgramPlanningState(request.value.state);
    if (request.value.state.blockIndex >= request.value.definition.blocks.len) {
        return error.InvalidRequest;
    }
    const block = definition.blocks[request.value.state.blockIndex];
    if (!std.mem.eql(u8, request.value.intent.blockId, block.id)) return error.InvalidRequest;
    const role = findProgramRole(block, request.value.intent.roleId) orelse
        return error.InvalidRequest;
    const planned = program_planning.PlannedSessionIntent{
        .definition = state.definition,
        .instance_id = request.value.instance.id,
        .block_id = block.id,
        .block_phase = block.phase,
        .occurrence = .{
            .id = request.value.intent.occurrenceId,
            .instance_id = request.value.instance.id,
            .block_id = block.id,
            .microcycle_index = state.microcycle_index,
            .role_id = role.id,
            .sequence_index = state.session_cursor,
            .scheduled_date = request.value.intent.scheduledDate,
            .status = @enumFromInt(@intFromEnum(request.value.intent.scheduleStatus)),
        },
        .role = role,
        .block_default_progression = block.default_progression,
        .program_muscle_priorities = block.muscle_priorities,
        .scheduling_provenance = .rotation_next,
    };
    const proposal = program_planning.proposeAdvancement(
        definition,
        state,
        planned,
        switch (request.value.status) {
            .completed => .completed,
            .skipped => .skipped,
        },
    ) catch return error.InvalidRequest;
    const next = switch (proposal.outcome) {
        .advance => |value| value,
        .require_host_policy, .no_change => return error.InvalidRequest,
    };
    var next_state = programPlanningStateToCanonical(
        next,
        request.value.state.definition,
        request.value.nextStrategyState orelse request.value.state.strategyState,
    );
    next_state.completedOccurrenceCount = if (request.value.status == .completed)
        std.math.add(u64, request.value.state.completedOccurrenceCount, 1) catch
            return error.InvalidRequest
    else
        request.value.state.completedOccurrenceCount;
    return encodeOwned(runtime, canonical.ProgramStateProposalDocument{
        .instanceId = request.value.instance.id,
        .definition = request.value.state.definition,
        .expectedRevision = request.value.state.revision,
        .nextState = next_state,
        .occurrence = .{
            .instanceId = request.value.instance.id,
            .definition = request.value.state.definition,
            .blockId = request.value.intent.blockId,
            .roleId = request.value.intent.roleId,
            .occurrenceId = request.value.intent.occurrenceId,
            .status = switch (request.value.status) {
                .completed => .completed,
                .skipped => .skipped,
            },
            .beforeRevision = request.value.state.revision,
            .afterRevision = next.revision,
        },
    }, out);
}

fn translateProgramDefinition(
    allocator: std.mem.Allocator,
    source: canonical.ProgramDefinitionDocument,
) ExecuteError!program_planning.ProgramDefinition {
    if (source.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    _ = primitives.Id.parse(source.id) catch return error.InvalidRequest;
    if (source.displayName.len == 0 or source.configurationFingerprint.len == 0) {
        return error.InvalidRequest;
    }
    if (!std.mem.eql(u8, source.strategy.id, programming.fixed_session_id)) {
        return error.UnsupportedMethodology;
    }
    if (source.strategy.configVersion != programming.fixed_session_config_version) {
        return error.UnsupportedVersion;
    }
    _ = try resolvedVersion(source.strategy.versionRequirement);
    const blocks = allocator.alloc(program_planning.Block, source.blocks.len) catch
        return error.OutOfMemory;
    for (source.blocks, blocks) |block, *translated| {
        translated.* = .{
            .id = block.id,
            .name = block.displayName orelse block.id,
            .phase = @enumFromInt(@intFromEnum(block.phase)),
            .phase_semantic = block.phaseSemantic,
            .length = .{ .completed_microcycles = block.microcycleCount },
            .schedule = try translateProgramSchedule(allocator, block.schedule),
            .roles = try translateProgramRoles(allocator, block.sessionRoles),
            .muscle_priorities = try translateProgramMusclePriorities(
                allocator,
                block.musclePriorities,
            ),
            .default_progression = try translateOptionalProgression(
                allocator,
                block.defaultProgression,
            ),
            .next_block_id = block.nextBlockId,
        };
    }
    return .{
        .id = source.id,
        .version = try parseProgramDefinitionVersion(source.version),
        .display_name = source.displayName,
        .description = source.description,
        .strategy_id = source.strategy.id,
        .strategy_version = source.strategy.configVersion,
        .configuration_fingerprint = source.configurationFingerprint,
        .source = if (source.source) |value| value.id else null,
        .blocks = blocks,
    };
}

fn translateProgramSchedule(
    allocator: std.mem.Allocator,
    source: canonical.ProgramSchedule,
) ExecuteError!program_planning.Schedule {
    return switch (source) {
        .rotation => |value| .{ .rotation = .{
            .role_ids = value.roleIds,
            .frequency = if (value.frequency) |frequency| .{
                .sessions = frequency.sessions,
                .days = frequency.days,
            } else null,
        } },
        .frequencyTargeted => |value| .{ .frequency_targeted = .{
            .role_ids = value.roleIds,
            .target = .{ .sessions = value.target.sessions, .days = value.target.days },
        } },
        .hybrid => |value| blk: {
            const weekdays = allocator.alloc(
                program_planning.Weekday,
                value.preferredWeekdays.len,
            ) catch return error.OutOfMemory;
            for (value.preferredWeekdays, weekdays) |weekday, *translated| {
                translated.* = @enumFromInt(@intFromEnum(weekday));
            }
            break :blk .{ .hybrid = .{
                .role_ids = value.roleIds,
                .target = .{ .sessions = value.target.sessions, .days = value.target.days },
                .preferred_weekdays = weekdays,
            } };
        },
        .fixedWeekdays => |value| blk: {
            const entries = allocator.alloc(
                program_planning.WeekdayEntry,
                value.entries.len,
            ) catch return error.OutOfMemory;
            for (value.entries, entries) |entry, *translated| translated.* = .{
                .weekday = @enumFromInt(@intFromEnum(entry.weekday)),
                .role_id = entry.roleId,
            };
            break :blk .{ .fixed_weekdays = .{ .entries = entries } };
        },
        .explicitDates => |value| blk: {
            const entries = allocator.alloc(
                program_planning.DatedEntry,
                value.entries.len,
            ) catch return error.OutOfMemory;
            for (value.entries, entries) |entry, *translated| {
                try validateLocalDateText(entry.localDate);
                translated.* = .{ .local_date = entry.localDate, .role_id = entry.roleId };
            }
            break :blk .{ .explicit_dates = .{ .entries = entries } };
        },
    };
}

fn translateProgramRoles(
    allocator: std.mem.Allocator,
    source: []const canonical.ProgramSessionRoleDefinition,
) ExecuteError![]const program_planning.SessionRole {
    const roles = allocator.alloc(program_planning.SessionRole, source.len) catch
        return error.OutOfMemory;
    for (source, roles) |role, *translated| translated.* = .{
        .id = role.id,
        .name = role.displayName orelse role.id,
        .purpose = role.description,
        .muscle_priorities = try translateProgramMusclePriorities(
            allocator,
            role.musclePriorities,
        ),
        .items = try translateProgramItems(allocator, role.items),
        .default_progression = try translateOptionalProgression(
            allocator,
            role.defaultProgression,
        ),
        .expected_duration_minutes = role.expectedDurationMinutes,
    };
    return roles;
}

fn translateProgramItems(
    allocator: std.mem.Allocator,
    source: []const canonical.ProgramSessionItem,
) ExecuteError![]const program_planning.SessionItem {
    const items = allocator.alloc(program_planning.SessionItem, source.len) catch
        return error.OutOfMemory;
    for (source, items) |item, *translated| translated.* = switch (item) {
        .fixed => |value| .{ .fixed = .{
            .id = value.id,
            .exercise_id = value.exerciseId,
            .anchor = @enumFromInt(@intFromEnum(value.anchor)),
            .progression = try translateOptionalProgression(allocator, value.progression),
            .ordering = .{
                .priority_tier = value.ordering.priorityTier,
                .before_item_ids = value.ordering.beforeItemIds,
                .after_item_ids = value.ordering.afterItemIds,
            },
        } },
        .dynamic => |value| .{ .slot = .{
            .id = value.id,
            .requirements = .{
                .target_muscle_ids = value.requirements.targetMuscleIds,
                .movement_pattern_ids = value.requirements.movementPatternIds,
                .exercise_family_ids = value.requirements.exerciseFamilyIds,
                .required_exercise_ids = value.requirements.requiredExerciseIds,
                .excluded_exercise_ids = value.requirements.excludedExerciseIds,
                .required_equipment_ids = value.requirements.requiredEquipmentIds,
                .progression_requirement = if (value.requirements.progressionRequirement) |requirement|
                    @enumFromInt(@intFromEnum(requirement))
                else
                    null,
            },
            .pool = .{
                .exercise_ids = value.pool.exerciseIds,
                .exercise_family_ids = value.pool.exerciseFamilyIds,
            },
            .progression = try translateOptionalProgression(allocator, value.progression),
            .ordering = .{
                .priority_tier = value.ordering.priorityTier,
                .before_item_ids = value.ordering.beforeItemIds,
                .after_item_ids = value.ordering.afterItemIds,
            },
        } },
    };
    return items;
}

fn translateOptionalProgression(
    allocator: std.mem.Allocator,
    source: ?canonical.ProgressionAssignment,
) ExecuteError!?program_planning.ProgressionAssignment {
    const value = source orelse return null;
    _ = primitives.Id.parse(value.stateId) catch return error.InvalidRequest;
    return .{ .state_id = value.stateId, .method = try translateProgression(allocator, value) };
}

fn translateProgramMusclePriorities(
    allocator: std.mem.Allocator,
    source: []const canonical.MusclePriority,
) ExecuteError![]const program_planning.MusclePriority {
    const priorities = allocator.alloc(program_planning.MusclePriority, source.len) catch
        return error.OutOfMemory;
    for (source, priorities) |priority, *translated| translated.* = .{
        .muscle_id = priority.muscleId,
        .priority = @enumFromInt(@intFromEnum(priority.priority)),
        .weight = priority.weight,
    };
    return priorities;
}

fn translateProgramInstance(
    source: canonical.ProgramInstanceDocument,
) ExecuteError!program_planning.ProgramInstance {
    if (source.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    return .{
        .id = source.id,
        .athlete_id = source.athleteId,
        .definition = try translateProgramDefinitionReference(source.definition),
        .lifecycle = switch (source.lifecycle) {
            .planned => .created,
            .active => .active,
            .paused => .paused,
            .completed => .completed,
            .abandoned => .ended,
        },
        .started_on = source.startedOn,
    };
}

fn translateProgramPlanningState(
    source: canonical.ProgramPlanningState,
) ExecuteError!program_planning.ProgramState {
    if (source.schemaVersion != program_planning.schema_version) {
        return error.UnsupportedVersion;
    }
    return .{
        .instance_id = source.instanceId,
        .definition = try translateProgramDefinitionReference(source.definition),
        .revision = source.revision,
        .block_index = std.math.cast(u16, source.blockIndex) orelse
            return error.InvalidRequest,
        .microcycle_index = source.microcycleIndex,
        .session_cursor = std.math.cast(u16, source.sessionCursor) orelse
            return error.InvalidRequest,
        .completed_occurrences = source.completedOccurrenceCount,
        .complete = source.completed,
    };
}

fn programPlanningStateToCanonical(
    source: program_planning.ProgramState,
    definition: canonical.ProgramDefinitionReference,
    strategy_state: ?canonical.ProgramState,
) canonical.ProgramPlanningState {
    return .{
        .instanceId = source.instance_id,
        .definition = definition,
        .revision = source.revision,
        .blockIndex = source.block_index,
        .microcycleIndex = source.microcycle_index,
        .sessionCursor = source.session_cursor,
        .completedOccurrenceCount = source.completed_occurrences,
        .completed = source.complete,
        .strategyState = strategy_state,
    };
}

fn translateProgramDefinitionReference(
    source: canonical.ProgramDefinitionReference,
) ExecuteError!program_planning.DefinitionRef {
    return .{
        .id = source.id,
        .version = try parseProgramDefinitionVersion(source.version),
        .configuration_fingerprint = source.configurationFingerprint,
    };
}

fn canonicalDefinitionReference(
    definition: canonical.ProgramDefinitionDocument,
) canonical.ProgramDefinitionReference {
    return .{
        .id = definition.id,
        .version = definition.version,
        .configurationFingerprint = definition.configurationFingerprint,
    };
}

fn validateProgramSnapshotReferences(
    definition: canonical.ProgramDefinitionDocument,
    instance: canonical.ProgramInstanceDocument,
    state: canonical.ProgramPlanningState,
) ExecuteError!void {
    const reference = canonicalDefinitionReference(definition);
    if (!canonicalDefinitionReferencesEqual(reference, instance.definition) or
        !canonicalDefinitionReferencesEqual(reference, state.definition) or
        !std.mem.eql(u8, instance.id, state.instanceId)) return error.InvalidRequest;
}

fn canonicalDefinitionReferencesEqual(
    left: canonical.ProgramDefinitionReference,
    right: canonical.ProgramDefinitionReference,
) bool {
    return std.mem.eql(u8, left.id, right.id) and
        std.mem.eql(u8, left.version, right.version) and
        std.mem.eql(
            u8,
            left.configurationFingerprint,
            right.configurationFingerprint,
        );
}

fn parseProgramDefinitionVersion(value: []const u8) ExecuteError!u32 {
    const end = std.mem.indexOfScalar(u8, value, '.') orelse value.len;
    if (end == 0) return error.InvalidRequest;
    const version = std.fmt.parseInt(u32, value[0..end], 10) catch
        return error.InvalidRequest;
    if (version == 0) return error.InvalidRequest;
    return version;
}

fn programPlanningIssuesToCanonical(
    allocator: std.mem.Allocator,
    source: []const program_planning.Issue,
) ExecuteError![]const canonical.ValidationIssue {
    const issues = allocator.alloc(canonical.ValidationIssue, source.len) catch
        return error.OutOfMemory;
    for (source, issues) |issue, *translated| translated.* = .{
        .code = issue.code,
        .path = issue.path,
        .message = issue.message,
        .severity = .@"error",
    };
    return issues;
}

fn findCanonicalProgramRole(
    block: canonical.ProgramBlockDefinition,
    role_id: []const u8,
) ?canonical.ProgramSessionRoleDefinition {
    for (block.sessionRoles) |role| {
        if (std.mem.eql(u8, role.id, role_id)) return role;
    }
    return null;
}

fn findProgramRole(
    block: program_planning.Block,
    role_id: []const u8,
) ?program_planning.SessionRole {
    for (block.roles) |role| {
        if (std.mem.eql(u8, role.id, role_id)) return role;
    }
    return null;
}

fn resolveCanonicalProgression(
    block: canonical.ProgramBlockDefinition,
    role: canonical.ProgramSessionRoleDefinition,
    item: canonical.ProgramSessionItem,
) ?canonical.ProgressionAssignment {
    return switch (item) {
        inline else => |value| value.progression orelse
            role.defaultProgression orelse
            block.defaultProgression,
    };
}

fn plannedTrainingContext(
    allocator: std.mem.Allocator,
    block: canonical.ProgramBlockDefinition,
    role: canonical.ProgramSessionRoleDefinition,
) ExecuteError!canonical.ProgramTrainingContext {
    if (block.musclePriorities.len == 0) return role.trainingContext;
    const count = std.math.add(
        usize,
        block.musclePriorities.len,
        role.trainingContext.musclePriorities.len,
    ) catch return error.InvalidRequest;
    const priorities = allocator.alloc(canonical.MusclePriority, count) catch
        return error.OutOfMemory;
    @memcpy(priorities[0..block.musclePriorities.len], block.musclePriorities);
    @memcpy(
        priorities[block.musclePriorities.len..],
        role.trainingContext.musclePriorities,
    );
    var result = role.trainingContext;
    result.musclePriorities = priorities;
    return result;
}

fn validateLocalDateText(value: []const u8) ExecuteError!void {
    if (value.len != 10 or value[4] != '-' or value[7] != '-') {
        return error.InvalidRequest;
    }
    for (value, 0..) |byte, index| {
        if (index == 4 or index == 7) continue;
        if (!std.ascii.isDigit(byte)) return error.InvalidRequest;
    }
    const year = std.fmt.parseInt(u16, value[0..4], 10) catch
        return error.InvalidRequest;
    const month = std.fmt.parseInt(u8, value[5..7], 10) catch
        return error.InvalidRequest;
    const day = std.fmt.parseInt(u8, value[8..10], 10) catch
        return error.InvalidRequest;
    if (year == 0 or month == 0 or month > 12 or day == 0) {
        return error.InvalidRequest;
    }
    const leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
    const days = [_]u8{ 31, if (leap) 29 else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (day > days[month - 1]) return error.InvalidRequest;
}

fn executePortableExport(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = portable.decodeDocument(runtime.allocator(), input) catch |err| return mapTrackingError(err);
    defer document.deinit();
    const issues = runtime.allocator().alloc(portable.Issue, portable.max_issues) catch return error.OutOfMemory;
    defer runtime.allocator().free(issues);
    return encodeOwned(runtime, portable.validateExport(document.value, issues) catch return error.InvalidRequest, out);
}

fn executePortableImportValidation(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const request = portable.decodeImportRequest(runtime.allocator(), input) catch |err| return mapTrackingError(err);
    defer request.deinit();
    const issues = runtime.allocator().alloc(portable.Issue, portable.max_issues) catch return error.OutOfMemory;
    defer runtime.allocator().free(issues);
    return encodeOwned(runtime, portable.planImport(request.value, issues) catch return error.InvalidRequest, out);
}

const DiscoveryRequest = struct { schemaVersion: u32 };
const DescribeMethodologyRequest = struct { schemaVersion: u32, id: []const u8 };
const ValidationRequest = struct {
    schemaVersion: u32,
    methodologyId: []const u8,
    configurationSchemaVersion: u32,
    config: std.json.Value,
    state: ?canonical.MethodologyState = null,
};
const DescribeMethodologyResult = struct {
    schemaVersion: u32 = discovery.schema_version,
    methodology: discovery.MethodologyDescriptor,
};
const ValidationResult = struct {
    schemaVersion: u32 = discovery.schema_version,
    valid: bool,
    issues: []const canonical.ValidationIssue,
};

fn executeListMethodologies(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const request = try canonical_json.decodeValue(DiscoveryRequest, runtime.allocator(), input, .{});
    defer request.deinit();
    if (request.value.schemaVersion != discovery.schema_version) return error.UnsupportedVersion;
    return encodeOwned(runtime, discovery.registry(), out);
}

fn executeListCapabilities(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    return executeListMethodologies(runtime, input, out);
}

fn executeDescribeMethodology(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const request = try canonical_json.decodeValue(DescribeMethodologyRequest, runtime.allocator(), input, .{});
    defer request.deinit();
    if (request.value.schemaVersion != discovery.schema_version) return error.UnsupportedVersion;
    const descriptor = discovery.find(request.value.id) orelse return error.UnsupportedMethodology;
    return encodeOwned(runtime, DescribeMethodologyResult{ .methodology = descriptor.* }, out);
}

fn executeMethodologyValidation(runtime: *Runtime, input: []const u8, include_state: bool, out: *OwnedBuffer) ExecuteError!void {
    const request = try canonical_json.decodeValue(ValidationRequest, runtime.allocator(), input, .{});
    defer request.deinit();
    if (request.value.schemaVersion != discovery.schema_version) return error.UnsupportedVersion;
    const descriptor = discovery.find(request.value.methodologyId) orelse return error.UnsupportedMethodology;
    if (request.value.configurationSchemaVersion != descriptor.configurationSchemaVersion) return error.UnsupportedVersion;
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const issue_storage = allocator.alloc(canonical.ValidationIssue, discovery.max_validation_issues) catch return error.OutOfMemory;
    const issues = if (std.mem.eql(u8, request.value.methodologyId, double_progression.methodology_id)) blk: {
        const config = std.json.parseFromValueLeaky(double_progression.Config, allocator, request.value.config, .{ .ignore_unknown_fields = false }) catch
            break :blk invalidDiscoveryValue(issue_storage, "methodology.config_invalid", "/config", "The double-progression configuration is malformed.");
        if (!include_state) break :blk discovery.validateConfig(.{ .doubleProgression = config }, issue_storage) catch return error.OutputLimitReached;
        const state = request.value.state orelse break :blk invalidDiscoveryValue(issue_storage, "methodology.state_invalid", "/state", "Methodology state is required.");
        const data = std.json.parseFromValueLeaky(double_progression.StateData, allocator, state.data, .{ .ignore_unknown_fields = false }) catch
            break :blk invalidDiscoveryValue(issue_storage, "methodology.state_invalid", "/state/data", "The double-progression state is malformed.");
        break :blk discovery.validateState(.{ .doubleProgression = .{ .config = config, .state = .{ .schemaVersion = state.schemaVersion, .data = data } } }, issue_storage) catch return error.OutputLimitReached;
    } else if (std.mem.eql(u8, request.value.methodologyId, rpe_top_set_backoff.methodology_id)) blk: {
        const config = std.json.parseFromValueLeaky(rpe_top_set_backoff.Config, allocator, request.value.config, .{ .ignore_unknown_fields = false }) catch
            break :blk invalidDiscoveryValue(issue_storage, "methodology.config_invalid", "/config", "The RPE top-set/backoff configuration is malformed.");
        if (!include_state) break :blk discovery.validateConfig(.{ .rpeTopSetBackoff = config }, issue_storage) catch return error.OutputLimitReached;
        const state = request.value.state orelse break :blk invalidDiscoveryValue(issue_storage, "methodology.state_invalid", "/state", "Methodology state is required.");
        const data = std.json.parseFromValueLeaky(rpe_top_set_backoff.StateData, allocator, state.data, .{ .ignore_unknown_fields = false }) catch
            break :blk invalidDiscoveryValue(issue_storage, "methodology.state_invalid", "/state/data", "The RPE top-set/backoff state is malformed.");
        break :blk discovery.validateState(.{ .rpeTopSetBackoff = .{ .config = config, .state = .{ .schemaVersion = state.schemaVersion, .data = data } } }, issue_storage) catch return error.OutputLimitReached;
    } else return error.UnsupportedMethodology;
    return encodeOwned(runtime, ValidationResult{ .valid = issues.len == 0, .issues = issues }, out);
}

fn invalidDiscoveryValue(storage: []canonical.ValidationIssue, code: []const u8, path: []const u8, message: []const u8) []const canonical.ValidationIssue {
    std.debug.assert(storage.len != 0);
    storage[0] = .{
        .code = code,
        .path = path,
        .message = message,
        .severity = .@"error",
    };
    return storage[0..1];
}

fn parseInstantiationIds(allocator: std.mem.Allocator, value: workflows.InstantiationIdsDocument) error{ InvalidRequest, OutOfMemory }!workflows.InstantiationIds {
    const memberships = allocator.alloc(tracking.Id, value.membershipIds.len) catch return error.OutOfMemory;
    const sets = allocator.alloc(tracking.Id, value.setIds.len) catch return error.OutOfMemory;
    for (value.membershipIds, 0..) |id, index| memberships[index] = tracking.Id.parse(id) catch return error.InvalidRequest;
    for (value.setIds, 0..) |id, index| sets[index] = tracking.Id.parse(id) catch return error.InvalidRequest;
    return .{
        .workout_id = tracking.Id.parse(value.workoutId) catch return error.InvalidRequest,
        .membership_ids = memberships,
        .set_ids = sets,
    };
}

fn instantiationStorage(allocator: std.mem.Allocator) error{OutOfMemory}!workflows.InstantiationStorage {
    return .{
        .exercises = allocator.alloc(tracking.ExerciseMembership, workflows.max_template_exercises) catch return error.OutOfMemory,
        .sets = allocator.alloc(tracking.TrackedSet, workflows.max_template_sets) catch return error.OutOfMemory,
        .prescription_exercises = allocator.alloc(tracking.PrescribedExercise, workflows.max_template_exercises) catch return error.OutOfMemory,
        .prescription_sets = allocator.alloc(tracking.PrescribedSet, workflows.max_template_sets) catch return error.OutOfMemory,
        .metrics = allocator.alloc(tracking.Metric, tracking_workspace_items) catch return error.OutOfMemory,
    };
}

fn workflowIssuesToWire(allocator: std.mem.Allocator, values: []const tracking.Issue) error{OutOfMemory}![]const tracking_protocol.Issue {
    const output = allocator.alloc(tracking_protocol.Issue, values.len) catch return error.OutOfMemory;
    for (values, 0..) |issue, index| {
        const related = allocator.alloc([]const u8, issue.related_ids.len) catch return error.OutOfMemory;
        for (issue.related_ids, 0..) |id, related_index| related[related_index] = id.bytes;
        output[index] = .{
            .code = issue.code,
            .category = tracking_protocol.issueCategoryFromDomain(issue.category),
            .severity = tracking_protocol.issueSeverityFromDomain(issue.severity),
            .path = issue.path,
            .message = issue.message,
            .relatedIds = related,
        };
    }
    return output;
}

fn workflowWorkoutToWire(allocator: std.mem.Allocator, workout: tracking.Workout) error{ InvalidRequest, OutOfMemory }!tracking_protocol.TrackedWorkout {
    const wire = tracking_protocol.snapshotFromDomain(
        .{ .workouts = &.{workout} },
        (try wireResultStorage(allocator)).snapshot,
    ) catch return error.InvalidRequest;
    return wire.workouts[0];
}

fn executeRecommendationInstantiation(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = workflows.decodeRecommendationInstantiationDocument(runtime.allocator(), input, .{}) catch |err| return mapTrackingError(err);
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const value = document.value;
    const resolved_context = if (value.recommendationResult.recommendation) |recommendation| recommendation.resolvedTrainingContext else null;
    const result = workflows.instantiateRecommendation(value.recommendationResult, value.catalog, .{
        .scope = .{
            .host_scope_key = tracking.Id.parse(value.scope.hostScopeKey) catch return error.InvalidRequest,
            .athlete_id = if (value.scope.athleteId) |id| tracking.Id.parse(id) catch return error.InvalidRequest else null,
        },
        .ids = try parseInstantiationIds(allocator, value.ids),
        .created_at = tracking.Timestamp.parse(value.createdAt) catch return error.InvalidRequest,
        .accepted_recommendation_id = tracking.Id.parse(value.acceptedRecommendationId) catch return error.InvalidRequest,
        .methodology_state_revision = value.methodologyStateRevision,
        .methodology_state_fingerprint = value.methodologyStateFingerprint,
        .athlete_profile_id = if (resolved_context) |context| context.athleteProfileId else null,
        .athlete_profile_revision = if (resolved_context) |context| context.athleteProfileRevision else null,
        .athlete_profile_fingerprint = if (resolved_context) |context| context.athleteProfileFingerprint else null,
        .training_location_id = if (resolved_context) |context| context.locationId else null,
        .effective_equipment_ids = if (resolved_context) |context| context.availableEquipmentIds else &.{},
        .available_minutes = if (resolved_context) |context| context.availableMinutes else null,
        .hard_maximum_minutes = if (resolved_context) |context| context.hardMaximumMinutes else null,
        .session_goal_id = if (resolved_context) |context| if (context.goals.primary) |goal| goal.id else null else null,
        .active_restriction_ids = if (resolved_context) |context| try canonicalRestrictionIds(allocator, context.restrictions) else &.{},
    }, try instantiationStorage(allocator), allocator.alloc(tracking.Issue, 16) catch return error.OutOfMemory) catch return error.InvalidRequest;
    const wire: workflows.InstantiationDocumentResult = .{ .outcome = switch (result) {
        .accepted => |workout| .{ .accepted = try workflowWorkoutToWire(allocator, workout) },
        .rejected => |issues| .{ .rejected = try workflowIssuesToWire(allocator, issues) },
    } };
    try encodeOwned(runtime, wire, out);
}

fn canonicalRestrictionIds(allocator: std.mem.Allocator, restrictions: []const canonical.ResolvedRestriction) ExecuteError![]const []const u8 {
    const ids = allocator.alloc([]const u8, restrictions.len) catch return error.OutOfMemory;
    for (restrictions, ids) |restriction, *id| id.* = restriction.value.id;
    return ids;
}

fn executeTemplateInstantiation(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = workflows.decodeTemplateInstantiationDocument(runtime.allocator(), input, .{}) catch |err| return mapTrackingError(err);
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const value = document.value;
    const template = workflows.templateToDomain(value.template, .{
        .exercises = allocator.alloc(workflows.TemplateExercise, workflows.max_template_exercises) catch return error.OutOfMemory,
        .sets = allocator.alloc(workflows.TemplateSet, workflows.max_template_sets) catch return error.OutOfMemory,
        .metrics = allocator.alloc(tracking.Metric, tracking_workspace_items) catch return error.OutOfMemory,
        .tags = allocator.alloc(tracking.Id, tracking_workspace_items) catch return error.OutOfMemory,
    }) catch return error.InvalidRequest;
    const result = workflows.instantiateTemplate(template, value.catalog, .{
        .scope = .{
            .host_scope_key = tracking.Id.parse(value.scope.hostScopeKey) catch return error.InvalidRequest,
            .athlete_id = if (value.scope.athleteId) |id| tracking.Id.parse(id) catch return error.InvalidRequest else null,
        },
        .ids = try parseInstantiationIds(allocator, value.ids),
        .created_at = tracking.Timestamp.parse(value.createdAt) catch return error.InvalidRequest,
    }, try instantiationStorage(allocator), allocator.alloc(tracking.Issue, 16) catch return error.OutOfMemory) catch return error.InvalidRequest;
    const wire: workflows.InstantiationDocumentResult = .{ .outcome = switch (result) {
        .accepted => |workout| .{ .accepted = try workflowWorkoutToWire(allocator, workout) },
        .rejected => |issues| .{ .rejected = try workflowIssuesToWire(allocator, issues) },
    } };
    try encodeOwned(runtime, wire, out);
}

fn executeCompletionConversion(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = workflows.decodeCompletionDocument(runtime.allocator(), input, .{}) catch |err| return mapTrackingError(err);
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const snapshot = tracking_protocol.snapshotToDomain(.{ .workouts = &.{document.value.workout} }, try trackingSnapshotStorage(allocator)) catch return error.InvalidRequest;
    const result = workflows.completeForEvaluation(snapshot.workouts[0], document.value.catalog, .{
        .exercises = allocator.alloc(canonical.CompletedExercise, workflows.max_template_exercises) catch return error.OutOfMemory,
        .sets = allocator.alloc(canonical.CompletedSet, workflows.max_template_sets) catch return error.OutOfMemory,
        .metrics = allocator.alloc(canonical.Metric, tracking_workspace_items) catch return error.OutOfMemory,
        .amount_bytes = allocator.alloc([64]u8, tracking_workspace_items) catch return error.OutOfMemory,
        .tags = allocator.alloc([]const u8, tracking_workspace_items) catch return error.OutOfMemory,
    }, allocator.alloc(tracking.Issue, 16) catch return error.OutOfMemory) catch return error.InvalidRequest;
    const wire: workflows.CompletionDocumentResult = .{ .outcome = switch (result) {
        .accepted => |workout| .{ .accepted = workout },
        .rejected => |issues| .{ .rejected = try workflowIssuesToWire(allocator, issues) },
    } };
    try encodeOwned(runtime, wire, out);
}

fn trackingSnapshotStorage(allocator: std.mem.Allocator) error{OutOfMemory}!tracking_protocol.SnapshotConversionStorage {
    return .{
        .workouts = allocator.alloc(tracking.Workout, tracking_protocol.max_workouts) catch return error.OutOfMemory,
        .receipts = allocator.alloc(tracking.StartReceipt, tracking_protocol.max_workouts) catch return error.OutOfMemory,
        .exercises = allocator.alloc(tracking.ExerciseMembership, tracking_workspace_items) catch return error.OutOfMemory,
        .sets = allocator.alloc(tracking.TrackedSet, tracking_workspace_items) catch return error.OutOfMemory,
        .metrics = allocator.alloc(tracking.Metric, tracking_workspace_items) catch return error.OutOfMemory,
        .prescription_exercises = allocator.alloc(tracking.PrescribedExercise, tracking_workspace_items) catch return error.OutOfMemory,
        .prescription_sets = allocator.alloc(tracking.PrescribedSet, tracking_workspace_items) catch return error.OutOfMemory,
        .tags = allocator.alloc(tracking.Id, tracking_workspace_items) catch return error.OutOfMemory,
        .catalog = allocator.alloc(tracking.ExerciseCatalogEntry, tracking_protocol.max_catalog_entries) catch return error.OutOfMemory,
    };
}

fn wireResultStorage(allocator: std.mem.Allocator) error{OutOfMemory}!tracking_protocol.BatchResultStorage {
    return .{
        .snapshot = .{
            .workouts = allocator.alloc(tracking_protocol.TrackedWorkout, tracking_protocol.max_workouts + tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
            .receipts = allocator.alloc(tracking_protocol.StartReceipt, tracking_protocol.max_workouts + tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
            .exercises = allocator.alloc(tracking_protocol.ExerciseMembership, tracking_workspace_items) catch return error.OutOfMemory,
            .sets = allocator.alloc(tracking_protocol.TrackedSet, tracking_workspace_items) catch return error.OutOfMemory,
            .metrics = allocator.alloc(canonical.Metric, tracking_workspace_items) catch return error.OutOfMemory,
            .amountBytes = allocator.alloc([64]u8, tracking_workspace_items) catch return error.OutOfMemory,
            .prescription_exercises = allocator.alloc(tracking_protocol.PrescribedExercise, tracking_workspace_items) catch return error.OutOfMemory,
            .prescription_sets = allocator.alloc(tracking_protocol.PrescribedSet, tracking_workspace_items) catch return error.OutOfMemory,
            .tags = allocator.alloc([]const u8, tracking_workspace_items) catch return error.OutOfMemory,
            .catalog = allocator.alloc(tracking_protocol.ExerciseCatalogEntry, tracking_protocol.max_catalog_entries) catch return error.OutOfMemory,
        },
        .outcomes = allocator.alloc(tracking_protocol.CommandOutcome, tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .accepted = allocator.alloc(tracking_protocol.AcceptedCommand, tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .rejected = allocator.alloc(tracking_protocol.RejectedCommand, 1) catch return error.OutOfMemory,
        .issues = allocator.alloc(tracking_protocol.Issue, tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .relatedIds = allocator.alloc([]const u8, tracking_workspace_items) catch return error.OutOfMemory,
    };
}

fn encodeOwned(runtime: *Runtime, value: anytype, out: *OwnedBuffer) ExecuteError!void {
    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = tracking_protocol.encode(value, bytes) catch return error.OutputLimitReached;
    out.* = .{ .data = bytes.ptr, .len = encoded.len, .capacity = bytes.len };
}

fn executeTrackingCommand(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = tracking_protocol.decodeCommandRequest(runtime.allocator(), input, .{}) catch |err| return mapTrackingError(err);
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const snapshot = tracking_protocol.snapshotToDomain(document.value.snapshot, try trackingSnapshotStorage(allocator)) catch return error.InvalidRequest;
    const metric_storage = allocator.alloc(tracking.Metric, tracking_protocol.max_metrics_per_set) catch return error.OutOfMemory;
    const command = tracking_protocol.commandToDomain(document.value.command, metric_storage) catch return error.InvalidRequest;
    const batch = tracking.applyAtomicBatch(snapshot, &.{command}, .{
        .workouts = allocator.alloc(tracking.Workout, tracking_protocol.max_workouts + 1) catch return error.OutOfMemory,
        .start_receipts = allocator.alloc(tracking.StartReceipt, tracking_protocol.max_workouts + 1) catch return error.OutOfMemory,
        .exercises = allocator.alloc(tracking.ExerciseMembership, tracking_workspace_items) catch return error.OutOfMemory,
        .sets = allocator.alloc(tracking.TrackedSet, tracking_workspace_items) catch return error.OutOfMemory,
        .issues = allocator.alloc(tracking.Issue, 1) catch return error.OutOfMemory,
        .outcomes = allocator.alloc(tracking.AcceptedCommand, 1) catch return error.OutOfMemory,
    }) catch return error.InvalidRequest;
    const result: tracking.CommandResult = switch (batch) {
        .accepted => |accepted| .{ .accepted = accepted.outcomes[0] },
        .rejected => |rejected| .{ .rejected = rejected },
    };
    const next_snapshot = switch (batch) {
        .accepted => |accepted| accepted.snapshot,
        .rejected => snapshot,
    };
    const wire = tracking_protocol.commandResultFromDomain(result, next_snapshot, try wireResultStorage(allocator)) catch return error.InvalidRequest;
    try encodeOwned(runtime, wire, out);
}

fn executeTrackingBatch(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = tracking_protocol.decodeAtomicBatchRequest(runtime.allocator(), input, .{}) catch |err| return mapTrackingError(err);
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const snapshot = tracking_protocol.snapshotToDomain(document.value.snapshot, try trackingSnapshotStorage(allocator)) catch return error.InvalidRequest;
    const commands = allocator.alloc(tracking.Command, document.value.commands.len) catch return error.OutOfMemory;
    const metrics = allocator.alloc(tracking.Metric, tracking_workspace_items) catch return error.OutOfMemory;
    const converted = tracking_protocol.batchCommandsToDomain(document.value.commands, commands, metrics) catch return error.InvalidRequest;
    const result = tracking.applyAtomicBatch(snapshot, converted, .{
        .workouts = allocator.alloc(tracking.Workout, tracking_protocol.max_workouts + tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .start_receipts = allocator.alloc(tracking.StartReceipt, tracking_protocol.max_workouts + tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .exercises = allocator.alloc(tracking.ExerciseMembership, tracking_workspace_items) catch return error.OutOfMemory,
        .sets = allocator.alloc(tracking.TrackedSet, tracking_workspace_items) catch return error.OutOfMemory,
        .issues = allocator.alloc(tracking.Issue, tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
        .outcomes = allocator.alloc(tracking.AcceptedCommand, tracking_protocol.max_commands_per_batch) catch return error.OutOfMemory,
    }) catch return error.InvalidRequest;
    const wire = tracking_protocol.batchResultFromDomain(result, snapshot, try wireResultStorage(allocator)) catch return error.InvalidRequest;
    try encodeOwned(runtime, wire, out);
}

fn mapTrackingError(err: anyerror) ExecuteError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnsupportedVersion => error.UnsupportedVersion,
        error.InputTooLarge => error.InputTooLarge,
        error.InvalidUtf8 => error.InvalidUtf8,
        error.MalformedJson => error.MalformedJson,
        error.NestingLimitExceeded => error.NestingLimitExceeded,
        error.CollectionLimitExceeded => error.CollectionLimitExceeded,
        error.ValueTooLarge => error.ValueTooLarge,
        error.InvalidDecimal => error.InvalidDecimal,
        else => error.InvalidRequest,
    };
}

fn statusForError(err: ExecuteError) Status {
    return switch (err) {
        error.OutOfMemory => .out_of_memory,
        error.UnsupportedVersion => .unsupported_version,
        error.UnsupportedMethodology => .unsupported_methodology,
        error.OutputLimitReached => .output_limit_reached,
        error.CatalogLimitReached,
        error.InvalidRequest,
        error.InputTooLarge,
        error.InvalidUtf8,
        error.MalformedJson,
        error.NestingLimitExceeded,
        error.CollectionLimitExceeded,
        error.ValueTooLarge,
        error.InvalidDecimal,
        => .invalid_request,
    };
}

fn executeRecommendation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const document = try canonical_json.decodeRecommendationRequest(
        runtime.allocator(),
        input,
        .{},
    );
    defer document.deinit();

    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    if (std.mem.eql(
        u8,
        document.value.methodology.id,
        rpe_top_set_backoff.methodology_id,
    )) {
        return executeRpeRecommendation(
            runtime,
            arena.allocator(),
            document.value,
            out,
        );
    }
    var resolved_context: ?athlete_profile.OwnedResolved = null;
    defer if (resolved_context) |*owned| owned.deinit();
    if (document.value.athleteProfile) |profile| {
        resolved_context = athlete_profile.resolve(
            runtime.allocator(),
            try translateAthleteProfile(arena.allocator(), profile),
            .{},
            try translateTrainingContext(arena.allocator(), document.value.trainingContext),
            .{},
        ) catch return error.InvalidRequest;
    }
    const effective_equipment = if (resolved_context) |owned| owned.value.available_equipment_ids else document.value.trainingContext.equipment.override orelse document.value.trainingContext.equipment.additions;
    const request = try translateRequest(arena.allocator(), document.value, effective_equipment, if (resolved_context) |owned| owned.value else null);
    var engine_output: engine.Output = .{};
    var result = try engine.recommendSession(request, &engine_output);
    if (resolved_context) |owned| result.recommendation.?.resolvedTrainingContext = try resolvedToCanonical(arena.allocator(), owned.value);
    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    fingerprintBytes("caudex:recommendation-request:v1\x00", input, &input_fingerprint);
    const result_projection = std.json.Stringify.valueAlloc(arena.allocator(), result.recommendation, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    fingerprintBytes("caudex:recommendation-result:v1\x00", result_projection, &result_fingerprint);
    result.metadata.inputFingerprint = &input_fingerprint;
    result.metadata.resultFingerprint = &result_fingerprint;

    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(result, bytes) catch
        return error.OutputLimitReached;
    out.* = .{
        .data = bytes.ptr,
        .len = encoded.len,
        .capacity = bytes.len,
    };
}

const RpeWireResult = struct {
    ok: bool = true,
    recommendation: canonical.SessionRecommendation,
    explanations: []const canonical.Explanation,
    warnings: []const canonical.ValidationIssue,
    issues: []const canonical.ValidationIssue = &.{},
    metadata: canonical.ResultMetadata,
};

fn executeRpeRecommendation(
    runtime: *Runtime,
    allocator: std.mem.Allocator,
    source: canonical.RecommendationRequest,
    out: *OwnedBuffer,
) ExecuteError!void {
    var resolved_context: ?athlete_profile.OwnedResolved = null;
    defer if (resolved_context) |*owned| owned.deinit();
    if (source.athleteProfile) |profile| {
        resolved_context = athlete_profile.resolve(
            runtime.allocator(),
            try translateAthleteProfile(allocator, profile),
            .{},
            try translateTrainingContext(allocator, source.trainingContext),
            .{},
        ) catch return error.InvalidRequest;
    }
    if (source.methodology.configVersion != rpe_top_set_backoff.config_version) {
        return error.UnsupportedVersion;
    }
    _ = try resolvedVersion(source.methodology.versionRequirement);
    if (source.catalog.len != 1) return error.InvalidRequest;
    const config = std.json.parseFromValueLeaky(
        rpe_top_set_backoff.Config,
        allocator,
        source.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const state = try translateRpeState(allocator, source.methodologyState);
    const catalog = try translateCatalog(allocator, source.catalog);
    const history = try translateHistory(allocator, source.history);
    const exercise = catalog.exercises[0];
    const available = try translateIds(
        allocator,
        if (resolved_context) |owned| owned.value.available_equipment_ids else source.trainingContext.equipment.override orelse source.trainingContext.equipment.additions,
    );
    if (!caudex.exercise_knowledge.requiredEquipmentSatisfied(exercise, available)) return error.InvalidRequest;
    const top = rpe_top_set_backoff.recommendTopSet(
        config,
        state,
        history,
        exercise.id,
    ) catch return error.InvalidRequest;
    const backoff = rpe_top_set_backoff.recommendBackoffs(
        config,
        top,
    ) catch return error.InvalidRequest;

    const set_count: usize = @as(usize, backoff.set_count) + 1;
    const sets = allocator.alloc(canonical.SetRecommendation, set_count) catch
        return error.OutOfMemory;
    const metrics = allocator.alloc(canonical.Metric, 3 + backoff.set_count * 2) catch
        return error.OutOfMemory;
    const top_refs = try allocator.alloc([]const u8, 2);
    top_refs[0] = "explanation-1";
    top_refs[1] = "explanation-2";
    const backoff_refs = try allocator.alloc([]const u8, 1);
    backoff_refs[0] = "explanation-3";
    metrics[0] = .{ .code = "load", .value = try boundaryMeasurement(allocator, top.load) };
    metrics[1] = .{
        .code = "repetitions",
        .value = .{ .amount = try std.fmt.allocPrint(allocator, "{d}", .{top.repetitions}), .unit = "count" },
    };
    metrics[2] = .{
        .code = "rpe",
        .value = .{ .amount = try formatDecimal(allocator, top.target_rpe), .unit = "rpe" },
    };
    sets[0] = .{
        .kind = "top",
        .targetMetrics = metrics[0..3],
        .explanationRefs = top_refs,
    };
    var metric_index: usize = 3;
    for (1..set_count) |set_index| {
        metrics[metric_index] = .{
            .code = "load",
            .value = try boundaryMeasurement(allocator, backoff.load),
        };
        metrics[metric_index + 1] = .{
            .code = "repetitions",
            .value = .{
                .amount = try std.fmt.allocPrint(allocator, "{d}", .{backoff.repetitions}),
                .unit = "count",
            },
        };
        sets[set_index] = .{
            .kind = "backoff",
            .targetMetrics = metrics[metric_index .. metric_index + 2],
            .explanationRefs = backoff_refs,
        };
        metric_index += 2;
    }
    const selection_refs = [_][]const u8{ "explanation-1", "explanation-2", "explanation-3" };
    const exercises = [_]canonical.ExerciseRecommendation{.{
        .exerciseId = exercise.id.bytes,
        .sets = sets,
        .explanationRefs = &selection_refs,
    }};
    const explanations = [_]canonical.Explanation{
        .{
            .id = "explanation-1",
            .code = "exercise.selected.available_equipment",
            .category = "selection",
            .summary = "Available equipment supported the exercise selection.",
            .subject = .{ .exerciseId = exercise.id.bytes },
            .severity = .info,
        },
        .{
            .id = "explanation-2",
            .code = top.explanation.code,
            .category = "load",
            .summary = top.explanation.summary,
            .subject = .{ .exerciseId = exercise.id.bytes },
            .ruleId = top.explanation.rule_id,
            .severity = .info,
        },
        .{
            .id = "explanation-3",
            .code = backoff.explanation.code,
            .category = "load",
            .summary = backoff.explanation.summary,
            .subject = .{ .exerciseId = exercise.id.bytes },
            .ruleId = backoff.explanation.rule_id,
            .severity = .info,
        },
    };
    const warnings: []const canonical.ValidationIssue = if (top.warning) |warning|
        try allocator.dupe(canonical.ValidationIssue, &.{warning})
    else
        &.{};
    const canonical_storage = try allocator.alloc(u8, max_result_bytes);
    const canonical_input = canonical_json.encode(source, canonical_storage) catch
        return error.OutputLimitReached;
    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    fingerprintBytes("caudex:recommendation-request:v1\x00", canonical_input, &input_fingerprint);
    var result_hash = std.crypto.hash.sha2.Sha256.init(.{});
    result_hash.update("caudex:recommendation-result:v1\x00");
    result_hash.update(&input_fingerprint);
    result_hash.update(exercise.id.bytes);
    result_hash.update(top.explanation.code);
    result_hash.update(backoff.explanation.code);
    finishHex(&result_hash, &result_fingerprint);
    const wire = RpeWireResult{
        .recommendation = .{ .exercises = &exercises, .resolvedTrainingContext = if (resolved_context) |owned| try resolvedToCanonical(allocator, owned.value) else null },
        .explanations = &explanations,
        .warnings = warnings,
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = engine.schema_version,
            .methodology = .{
                .id = rpe_top_set_backoff.methodology_id,
                .version = "0.1.0",
                .configVersion = rpe_top_set_backoff.config_version,
            },
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(wire, bytes) catch
        return error.OutputLimitReached;
    out.* = .{ .data = bytes.ptr, .len = encoded.len, .capacity = bytes.len };
}

fn executeProgramRecommendation(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = try canonical_json.decodeProgramRecommendationRequest(runtime.allocator(), input, .{});
    defer document.deinit();
    const source = document.value;
    if (!std.mem.eql(u8, source.program.strategy.id, programming.fixed_session_id)) return error.UnsupportedMethodology;
    if (source.program.strategy.configVersion != programming.fixed_session_config_version) return error.UnsupportedVersion;
    if (source.program.strategy.config != .object or source.program.strategy.config.object.count() != 0) return error.InvalidRequest;
    _ = try resolvedVersion(source.program.strategy.versionRequirement);
    if (source.program.exercises.len == 0 or source.program.exercises.len > programming.max_exercises) return error.InvalidRequest;

    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    var resolved_context: ?athlete_profile.OwnedResolved = null;
    defer if (resolved_context) |*owned| owned.deinit();
    if (source.athleteProfile) |profile| {
        resolved_context = athlete_profile.resolve(
            runtime.allocator(),
            try translateAthleteProfile(allocator, profile),
            try translateProgramContext(allocator, source.program.trainingContext),
            try translateTrainingContext(allocator, source.trainingContext),
            .{},
        ) catch return error.InvalidRequest;
    }
    const slots = allocator.alloc(programming.ExerciseSlot, source.program.exercises.len) catch return error.OutOfMemory;
    for (source.program.exercises, slots) |slot, *translated| {
        translated.* = .{
            .slot_id = primitives.Id.parse(slot.slotId) catch return error.InvalidRequest,
            .exercise_id = primitives.Id.parse(slot.exerciseId) catch return error.InvalidRequest,
            .state_id = primitives.Id.parse(slot.progression.stateId) catch return error.InvalidRequest,
            .progression = try translateProgression(allocator, slot.progression),
        };
    }
    const translated_catalog = try translateCatalog(allocator, source.catalog);
    if (resolved_context) |owned| try validateResolvedProgramContext(translated_catalog, slots, owned.value);
    var recommendation = programming.recommendFixedSession(runtime.allocator(), .{
        .as_of = primitives.Timestamp.parse(source.asOf) catch return error.InvalidRequest,
        .catalog = translated_catalog,
        .history = try translateHistory(allocator, source.history),
        .available_equipment_ids = if (resolved_context) |owned|
            try translateIds(allocator, owned.value.available_equipment_ids)
        else
            try translateIds(allocator, source.trainingContext.equipment.override orelse source.trainingContext.equipment.additions),
        .slots = slots,
        .program_state = if (source.program.state) |state| .{ .schema_version = state.schemaVersion, .data = state.data } else null,
    }) catch |err| return mapProgrammingError(err);
    defer recommendation.deinit();
    if (resolved_context) |owned| {
        const resolved_wire = try resolvedToCanonical(allocator, owned.value);
        recommendation.recommendation.programming.?.resolvedTrainingContext = resolved_wire;
        recommendation.recommendation.resolvedTrainingContext = resolved_wire;
    }

    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    fingerprintBytes("caudex:program-recommendation-request:v1\x00", input, &input_fingerprint);
    const recommendation_bytes = std.json.Stringify.valueAlloc(allocator, recommendation.recommendation, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    fingerprintBytes("caudex:program-recommendation-result:v1\x00", recommendation_bytes, &result_fingerprint);
    const result = canonical.ProgramRecommendationResult{
        .ok = true,
        .recommendation = recommendation.recommendation,
        .explanations = recommendation.explanations,
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = 1,
            .programStrategy = .{ .id = programming.fixed_session_id, .version = programming.fixed_session_version, .configVersion = programming.fixed_session_config_version },
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    try encodeOwned(runtime, result, out);
}

fn validateResolvedProgramContext(catalog: training.ExerciseCatalog, slots: []const programming.ExerciseSlot, context: athlete_profile.Resolved) ExecuteError!void {
    for (context.required_exercises) |required| {
        for (slots) |slot| if (std.mem.eql(u8, slot.exercise_id.bytes, required.exercise_id)) break else {} else return error.InvalidRequest;
    }
    for (slots) |slot| {
        const exercise = catalog.find(slot.exercise_id) orelse return error.InvalidRequest;
        for (context.excluded_exercises) |excluded| if (std.mem.eql(u8, excluded.exercise_id, slot.exercise_id.bytes)) return error.InvalidRequest;
        for (context.restrictions) |restriction| switch (restriction.value.target_kind) {
            .exercise => if (std.mem.eql(u8, restriction.value.target_id, slot.exercise_id.bytes)) return error.InvalidRequest,
            .movement_pattern => if (caudex.exercise_knowledge.hasMovementPattern(exercise.*, restriction.value.target_id)) return error.InvalidRequest,
            .restriction_tag => if (caudex.exercise_knowledge.hasRestriction(exercise.*, restriction.value.target_id)) return error.InvalidRequest,
            .equipment => if (exerciseUsesEquipment(exercise.*, restriction.value.target_id)) return error.InvalidRequest,
            .exercise_family => if (exercise.knowledge) |knowledge| if (knowledge.familyId) |family| if (std.mem.eql(u8, family, restriction.value.target_id)) return error.InvalidRequest,
        };
    }
}

fn exerciseUsesEquipment(exercise: training.Exercise, equipment_id: []const u8) bool {
    if (exercise.knowledge) |knowledge| for (knowledge.equipmentRequirements) |requirement| if (std.mem.eql(u8, requirement.equipmentId, equipment_id)) return true;
    for (exercise.equipment_ids) |equipment| if (std.mem.eql(u8, equipment.bytes, equipment_id)) return true;
    return false;
}

fn executeProgramEvaluation(runtime: *Runtime, input: []const u8, out: *OwnedBuffer) ExecuteError!void {
    const document = try canonical_json.decodeProgramEvaluationRequest(runtime.allocator(), input, .{});
    defer document.deinit();
    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    const completed = training.CompletedWorkout{
        .id = primitives.Id.parse(document.value.completedWorkout.id) catch return error.InvalidRequest,
        .started_at = primitives.Timestamp.parse(document.value.completedWorkout.startedAt) catch return error.InvalidRequest,
        .completed_at = primitives.Timestamp.parse(document.value.completedWorkout.completedAt) catch return error.InvalidRequest,
        .exercises = try translateCompletedExercises(allocator, document.value.completedWorkout.exercises),
    };
    const as_of = primitives.Timestamp.parse(document.value.asOf) catch return error.InvalidRequest;
    if (completed.completed_at.unixSeconds() > as_of.unixSeconds()) return error.InvalidRequest;
    const catalog = try translateCatalog(allocator, document.value.catalog);
    const completed_snapshot = [_]training.CompletedWorkout{completed};
    var validation_storage: [64]training.ValidationIssue = undefined;
    const validation_issues = training.validate(catalog, .{ .workouts = &completed_snapshot }, &validation_storage) catch return error.OutputLimitReached;
    if (validation_issues.len != 0) return error.InvalidRequest;
    var evaluated = programming.evaluateFixedSession(runtime.allocator(), document.value.recommendation, completed) catch |err| return mapProgrammingError(err);
    defer evaluated.deinit();
    const exercise_results = evaluated.evaluation.exercises;
    const proposals = allocator.alloc(canonical.ProgressionStateProposal, evaluated.evaluation.state_proposals.len) catch return error.OutOfMemory;
    for (evaluated.evaluation.state_proposals, proposals) |proposal, *wire| {
        const state = switch (proposal.state) {
            .double_progression => |value| canonical.MethodologyState{ .schemaVersion = value.schemaVersion, .data = try valueToJson(allocator, value.data) },
            .rpe_top_set_backoff => |value| canonical.MethodologyState{ .schemaVersion = value.schemaVersion, .data = try valueToJson(allocator, value.data) },
        };
        wire.* = .{
            .stateId = proposal.state_id.bytes,
            .progression = .{ .id = proposal.method_id, .version = proposal.method_version, .configVersion = 1 },
            .state = state,
        };
    }
    const strategy = document.value.recommendation.programming orelse return error.InvalidRequest;
    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    fingerprintBytes("caudex:program-evaluation-request:v1\x00", input, &input_fingerprint);
    const proposal_bytes = std.json.Stringify.valueAlloc(allocator, proposals, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    fingerprintBytes("caudex:program-evaluation-result:v1\x00", proposal_bytes, &result_fingerprint);
    const result = canonical.ProgramEvaluationResult{
        .ok = true,
        .evaluation = .{ .outcome = "evaluated", .exercises = exercise_results },
        .nextProgramState = if (evaluated.evaluation.next_program_state) |state| .{ .schemaVersion = state.schema_version, .data = state.data } else null,
        .progressionStateProposals = proposals,
        .explanations = evaluated.evaluation.explanations,
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = 1,
            .programStrategy = strategy.strategy,
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    try encodeOwned(runtime, result, out);
}

fn translateProgression(allocator: std.mem.Allocator, source: canonical.ProgressionAssignment) ExecuteError!programming.Method {
    if (source.methodology.configVersion != 1) return error.UnsupportedVersion;
    _ = try resolvedVersion(source.methodology.versionRequirement);
    if (std.mem.eql(u8, source.methodology.id, double_progression.methodology_id)) {
        const config = std.json.parseFromValueLeaky(double_progression.Config, allocator, source.methodology.config, .{ .ignore_unknown_fields = false }) catch return error.InvalidRequest;
        return .{ .double_progression = .{ .config = config, .state = try translateState(allocator, source.state, config) } };
    }
    if (std.mem.eql(u8, source.methodology.id, rpe_top_set_backoff.methodology_id)) {
        const config = std.json.parseFromValueLeaky(rpe_top_set_backoff.Config, allocator, source.methodology.config, .{ .ignore_unknown_fields = false }) catch return error.InvalidRequest;
        return .{ .rpe_top_set_backoff = .{ .config = config, .state = try translateRpeState(allocator, source.state) } };
    }
    return error.UnsupportedMethodology;
}

fn mapProgrammingError(err: programming.Error) ExecuteError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.OutputLimitReached => error.OutputLimitReached,
        error.UnsupportedProgressionVersion => error.UnsupportedVersion,
        else => error.InvalidRequest,
    };
}

fn valueToJson(allocator: std.mem.Allocator, value: anytype) ExecuteError!std.json.Value {
    const bytes = std.json.Stringify.valueAlloc(allocator, value, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    return std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{}) catch return error.InvalidRequest;
}

fn boundaryMeasurement(
    allocator: std.mem.Allocator,
    measurement: primitives.Measurement,
) ExecuteError!canonical.Measurement {
    return .{
        .amount = try formatDecimal(allocator, measurement.value),
        .unit = measurement.unit.code(),
    };
}

fn formatDecimal(
    allocator: std.mem.Allocator,
    decimal: primitives.Decimal,
) ExecuteError![]const u8 {
    const storage = try allocator.alloc(u8, 64);
    return decimal.format(storage) catch return error.OutputLimitReached;
}

fn translateRpeState(
    allocator: std.mem.Allocator,
    source: ?canonical.MethodologyState,
) ExecuteError!?rpe_top_set_backoff.State {
    const state = source orelse return null;
    if (state.schemaVersion != rpe_top_set_backoff.state_schema_version) {
        return error.UnsupportedVersion;
    }
    const data = std.json.parseFromValueLeaky(
        rpe_top_set_backoff.StateData,
        allocator,
        state.data,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    return .{ .schemaVersion = state.schemaVersion, .data = data };
}

const EvaluationWireResult = struct {
    ok: bool = true,
    evaluation: canonical.PerformanceEvaluation,
    nextMethodologyState: double_progression.State,
    explanations: []const canonical.Explanation,
    warnings: []const canonical.ValidationIssue,
    issues: []const canonical.ValidationIssue = &.{},
    metadata: canonical.ResultMetadata,
};

fn executeEvaluation(
    runtime: *Runtime,
    input: []const u8,
    out: *OwnedBuffer,
) ExecuteError!void {
    const document = try canonical_json.decodeEvaluationRequest(
        runtime.allocator(),
        input,
        .{},
    );
    defer document.deinit();

    var arena = std.heap.ArenaAllocator.init(runtime.allocator());
    defer arena.deinit();
    const request = try translateEvaluationRequest(
        arena.allocator(),
        document.value,
    );
    var engine_output: engine.EvaluationOutput = .{};
    const evaluation = try engine.evaluatePerformance(request, &engine_output);

    const exercise_count = evaluation.exercises.len;
    const exercises = arena.allocator().alloc(
        canonical.ExerciseEvaluation,
        exercise_count,
    ) catch return error.OutOfMemory;
    const explanations = arena.allocator().alloc(
        canonical.Explanation,
        exercise_count,
    ) catch return error.OutOfMemory;
    const warning_storage = arena.allocator().alloc(
        canonical.ValidationIssue,
        exercise_count,
    ) catch return error.OutOfMemory;
    const reference_storage = arena.allocator().alloc(
        [1][]const u8,
        exercise_count,
    ) catch return error.OutOfMemory;
    var warning_len: usize = 0;
    for (evaluation.exercises, 0..) |item, index| {
        const explanation_id = std.fmt.allocPrint(
            arena.allocator(),
            "explanation-{d}",
            .{index + 1},
        ) catch return error.OutOfMemory;
        reference_storage[index] = .{explanation_id};
        exercises[index] = .{
            .exerciseId = item.exercise_id,
            .outcome = item.outcome,
            .explanationRefs = &reference_storage[index],
        };
        explanations[index] = .{
            .id = explanation_id,
            .code = item.explanation.code,
            .category = "progression",
            .summary = item.explanation.summary,
            .subject = .{ .exerciseId = item.exercise_id },
            .evidence = &.{.{ .path = "/completedWorkout" }},
            .ruleId = item.explanation.rule_id,
            .severity = .info,
        };
        if (item.warning) |warning| {
            warning_storage[warning_len] = warning;
            warning_len += 1;
        }
    }

    var input_fingerprint: [64]u8 = undefined;
    var result_fingerprint: [64]u8 = undefined;
    const canonical_input_storage = arena.allocator().alloc(
        u8,
        max_result_bytes,
    ) catch return error.OutOfMemory;
    const canonical_input = canonical_json.encode(
        document.value,
        canonical_input_storage,
    ) catch return error.OutputLimitReached;
    fingerprintBytes(
        "caudex:evaluation-request:v1\x00",
        canonical_input,
        &input_fingerprint,
    );
    var result_hash = std.crypto.hash.sha2.Sha256.init(.{});
    result_hash.update("caudex:evaluation-result:v1\x00");
    result_hash.update(&input_fingerprint);
    result_hash.update(evaluation.outcome);
    for (evaluation.exercises) |item| {
        result_hash.update(item.exercise_id);
        result_hash.update(item.outcome);
        result_hash.update(item.explanation.code);
    }
    finishHex(&result_hash, &result_fingerprint);

    const wire = EvaluationWireResult{
        .evaluation = .{
            .outcome = evaluation.outcome,
            .exercises = exercises,
        },
        .nextMethodologyState = evaluation.next_state,
        .explanations = explanations,
        .warnings = warning_storage[0..warning_len],
        .metadata = .{
            .engineVersion = engine.engine_version,
            .schemaVersion = engine.schema_version,
            .methodology = .{
                .id = request.methodology_id.bytes,
                .version = "0.1.0",
                .configVersion = double_progression.config_version,
            },
            .inputFingerprint = &input_fingerprint,
            .resultFingerprint = &result_fingerprint,
        },
    };
    const bytes = runtime.allocator().alloc(u8, max_result_bytes) catch
        return error.OutOfMemory;
    errdefer runtime.allocator().free(bytes);
    const encoded = canonical_json.encode(wire, bytes) catch
        return error.OutputLimitReached;
    out.* = .{
        .data = bytes.ptr,
        .len = encoded.len,
        .capacity = bytes.len,
    };
}

fn translateEvaluationRequest(
    allocator: std.mem.Allocator,
    request: canonical.EvaluationRequest,
) ExecuteError!engine.EvaluationRequest {
    if (!std.mem.eql(
        u8,
        request.methodology.id,
        double_progression.methodology_id,
    )) {
        return error.UnsupportedMethodology;
    }
    if (request.methodology.configVersion != double_progression.config_version) {
        return error.UnsupportedVersion;
    }
    const config = std.json.parseFromValueLeaky(
        double_progression.Config,
        allocator,
        request.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const completed_workout = allocator.create(training.CompletedWorkout) catch
        return error.OutOfMemory;
    completed_workout.* = .{
        .id = primitives.Id.parse(request.completedWorkout.id) catch
            return error.InvalidRequest,
        .started_at = primitives.Timestamp.parse(
            request.completedWorkout.startedAt,
        ) catch return error.InvalidRequest,
        .completed_at = primitives.Timestamp.parse(
            request.completedWorkout.completedAt,
        ) catch return error.InvalidRequest,
        .exercises = try translateCompletedExercises(
            allocator,
            request.completedWorkout.exercises,
        ),
    };
    return .{
        .as_of = primitives.Timestamp.parse(request.asOf) catch
            return error.InvalidRequest,
        .methodology_id = primitives.Id.parse(request.methodology.id) catch
            return error.InvalidRequest,
        .methodology_version = try resolvedVersion(
            request.methodology.versionRequirement,
        ),
        .config = config,
        .methodology_state = try translateState(
            allocator,
            request.methodologyState,
            config,
        ),
        .catalog = try translateCatalog(allocator, request.catalog),
        .completed_workout = completed_workout,
    };
}

fn fingerprintBytes(
    domain: []const u8,
    bytes: []const u8,
    out: *[64]u8,
) void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(domain);
    hash.update(bytes);
    finishHex(&hash, out);
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

fn translateRequest(
    allocator: std.mem.Allocator,
    request: canonical.RecommendationRequest,
    effective_equipment: []const []const u8,
    resolved_context: ?athlete_profile.Resolved,
) ExecuteError!engine.RecommendationRequest {
    if (!std.mem.eql(
        u8,
        request.methodology.id,
        double_progression.methodology_id,
    )) {
        return error.UnsupportedMethodology;
    }
    if (request.methodology.configVersion != double_progression.config_version) {
        return error.UnsupportedVersion;
    }
    const config = std.json.parseFromValueLeaky(
        double_progression.Config,
        allocator,
        request.methodology.config,
        .{ .ignore_unknown_fields = false },
    ) catch return error.InvalidRequest;
    const catalog = try translateCatalog(allocator, request.catalog);
    const history = try translateHistory(allocator, request.history);
    const equipment = try translateIds(
        allocator,
        effective_equipment,
    );
    const excluded_exercises = if (resolved_context) |context| try translateResolvedExercises(allocator, context.excluded_exercises) else &.{};
    const excluded_movements = if (resolved_context) |context| try translateResolvedRestrictions(allocator, context.restrictions, .movement_pattern) else &.{};
    const excluded_restriction_tags = if (resolved_context) |context| try translateResolvedRestrictions(allocator, context.restrictions, .restriction_tag) else &.{};
    const required_exercises = if (resolved_context) |context| try translateResolvedExercises(allocator, context.required_exercises) else &.{};
    return .{
        .as_of = primitives.Timestamp.parse(request.asOf) catch
            return error.InvalidRequest,
        .methodology_id = primitives.Id.parse(request.methodology.id) catch
            return error.InvalidRequest,
        .methodology_version = try resolvedVersion(
            request.methodology.versionRequirement,
        ),
        .config = config,
        .methodology_state = try translateState(
            allocator,
            request.methodologyState,
            config,
        ),
        .catalog = catalog,
        .history = history,
        .available_equipment_ids = equipment,
        .excluded_exercise_ids = excluded_exercises,
        .excluded_movement_pattern_ids = excluded_movements,
        .excluded_restriction_tag_ids = excluded_restriction_tags,
        .required_exercise_ids = required_exercises,
        .max_working_sets = request.trainingContext.maxSets,
    };
}

fn translateResolvedExercises(allocator: std.mem.Allocator, values: []const athlete_profile.SourcedExercise) ExecuteError![]const primitives.Id {
    const result = allocator.alloc(primitives.Id, values.len) catch return error.OutOfMemory;
    for (values, result) |value, *target| target.* = primitives.Id.parse(value.exercise_id) catch return error.InvalidRequest;
    return result;
}

fn translateResolvedRestrictions(allocator: std.mem.Allocator, values: []const athlete_profile.SourcedRestriction, kind: athlete_profile.RestrictionTargetKind) ExecuteError![]const primitives.Id {
    const result = allocator.alloc(primitives.Id, values.len) catch return error.OutOfMemory;
    var count: usize = 0;
    for (values) |value| if (value.value.target_kind == kind) {
        result[count] = primitives.Id.parse(value.value.target_id) catch return error.InvalidRequest;
        count += 1;
    };
    return result[0..count];
}

fn translateAthleteProfile(allocator: std.mem.Allocator, value: canonical.AthleteProfile) ExecuteError!athlete_profile.AthleteProfile {
    const preferences = allocator.alloc(athlete_profile.Preference, value.exercisePreferences.len) catch return error.OutOfMemory;
    for (value.exercisePreferences, preferences) |source, *target| target.* = .{
        .target_kind = @enumFromInt(@intFromEnum(source.targetKind)),
        .target_id = source.targetId,
        .level = @enumFromInt(@intFromEnum(source.level)),
    };
    const priorities = allocator.alloc(athlete_profile.MusclePriority, value.musclePriorities.len) catch return error.OutOfMemory;
    for (value.musclePriorities, priorities) |source, *target| target.* = .{
        .muscle_id = source.muscleId,
        .priority = @enumFromInt(@intFromEnum(source.priority)),
        .weight = source.weight,
    };
    const restrictions = try translateRestrictions(allocator, value.restrictions);
    const locations = allocator.alloc(athlete_profile.TrainingLocation, value.locations.len) catch return error.OutOfMemory;
    for (value.locations, locations) |source, *target| {
        const equipment = allocator.alloc(athlete_profile.EquipmentItem, source.equipment.len) catch return error.OutOfMemory;
        for (source.equipment, equipment) |item, *translated| translated.* = .{
            .equipment_id = item.equipmentId,
            .minimum_load_increment = if (item.minimumLoadIncrement) |measurement| .{ .amount = measurement.amount, .unit = measurement.unit } else null,
        };
        target.* = .{ .id = source.id, .name = source.name, .equipment = equipment, .metadata = source.metadata };
    }
    const capabilities = allocator.alloc(athlete_profile.CapabilityObservation, value.capabilityObservations.len) catch return error.OutOfMemory;
    for (value.capabilityObservations, capabilities) |source, *target| target.* = .{
        .id = source.id,
        .kind = @enumFromInt(@intFromEnum(source.kind)),
        .exercise_id = source.exerciseId,
        .value = if (source.value) |measurement| .{ .amount = measurement.amount, .unit = measurement.unit } else null,
        .observed_at = source.observedAt,
        .provenance = @enumFromInt(@intFromEnum(source.provenance)),
        .custom_kind_id = source.customKindId,
    };
    const secondary = allocator.alloc(athlete_profile.Goal, value.goals.secondary.len) catch return error.OutOfMemory;
    for (value.goals.secondary, secondary) |goal, *target| target.* = try translateGoal(goal);
    const familiarity = allocator.alloc(athlete_profile.ExerciseFamiliarity, value.experience.exercises.len) catch return error.OutOfMemory;
    for (value.experience.exercises, familiarity) |source, *target| target.* = .{ .exercise_id = source.exerciseId, .familiarity = @enumFromInt(@intFromEnum(source.familiarity)) };
    const days = allocator.alloc(athlete_profile.Weekday, value.schedule.preferredDays.len) catch return error.OutOfMemory;
    for (value.schedule.preferredDays, days) |source, *target| target.* = @enumFromInt(@intFromEnum(source));
    return .{
        .schema_version = value.schemaVersion,
        .id = value.id,
        .revision = value.revision,
        .display_name = value.displayName,
        .goals = .{ .primary = if (value.goals.primary) |goal| try translateGoal(goal) else null, .secondary = secondary, .body_composition_objective = value.goals.bodyCompositionObjective },
        .experience = .{
            .resistance_training = if (value.experience.resistanceTraining) |category| @enumFromInt(@intFromEnum(category)) else null,
            .consistent_months = value.experience.consistentMonths,
            .technical_lift_familiarity = if (value.experience.technicalLiftFamiliarity) |item| @enumFromInt(@intFromEnum(item)) else null,
            .exercise = familiarity,
        },
        .schedule = .{
            .preferred_sessions_per_week = value.schedule.preferredSessionsPerWeek,
            .minimum_sessions_per_week = value.schedule.minimumSessionsPerWeek,
            .maximum_sessions_per_week = value.schedule.maximumSessionsPerWeek,
            .preferred_days = days,
            .cadence = @enumFromInt(@intFromEnum(value.schedule.cadence)),
            .prefer_rest_between_sessions = value.schedule.preferRestBetweenSessions,
        },
        .duration = .{
            .preferred_minutes = value.duration.preferredMinutes,
            .acceptable_minimum_minutes = value.duration.acceptableMinimumMinutes,
            .acceptable_maximum_minutes = value.duration.acceptableMaximumMinutes,
            .hard_maximum_minutes = value.duration.hardMaximumMinutes,
        },
        .units = .{
            .load = if (value.units.load) |item| @enumFromInt(@intFromEnum(item)) else null,
            .bodyweight = if (value.units.bodyweight) |item| @enumFromInt(@intFromEnum(item)) else null,
            .distance = if (value.units.distance) |item| @enumFromInt(@intFromEnum(item)) else null,
        },
        .exercise_preferences = preferences,
        .muscle_priorities = priorities,
        .restrictions = restrictions,
        .locations = locations,
        .capability_observations = capabilities,
        .metadata = value.metadata,
    };
}

fn translateGoal(value: canonical.Goal) ExecuteError!athlete_profile.Goal {
    const family: athlete_profile.GoalFamily = if (std.mem.eql(u8, value.id, "hypertrophy")) .hypertrophy else if (std.mem.eql(u8, value.id, "strength")) .strength else if (std.mem.eql(u8, value.id, "general-fitness")) .general_fitness else if (std.mem.eql(u8, value.id, "muscular-endurance")) .muscular_endurance else if (std.mem.eql(u8, value.id, "powerlifting-practice")) .powerlifting_practice else if (std.mem.eql(u8, value.id, "limited-equipment")) .limited_equipment else if (std.mem.eql(u8, value.id, "maintenance")) .maintenance else .{ .custom = value.id };
    return .{ .family = family, .weight = value.weight };
}

fn translateRestrictions(allocator: std.mem.Allocator, values: []const canonical.Restriction) ExecuteError![]const athlete_profile.Restriction {
    const translated = allocator.alloc(athlete_profile.Restriction, values.len) catch return error.OutOfMemory;
    for (values, translated) |source, *target| target.* = .{ .id = source.id, .target_kind = @enumFromInt(@intFromEnum(source.targetKind)), .target_id = source.targetId };
    return translated;
}

fn translatePreferences(allocator: std.mem.Allocator, values: []const canonical.Preference) ExecuteError![]const athlete_profile.Preference {
    const translated = allocator.alloc(athlete_profile.Preference, values.len) catch return error.OutOfMemory;
    for (values, translated) |source, *target| target.* = .{ .target_kind = @enumFromInt(@intFromEnum(source.targetKind)), .target_id = source.targetId, .level = @enumFromInt(@intFromEnum(source.level)) };
    return translated;
}

fn translateGoalSet(allocator: std.mem.Allocator, value: canonical.GoalSet) ExecuteError!athlete_profile.GoalSet {
    const secondary = allocator.alloc(athlete_profile.Goal, value.secondary.len) catch return error.OutOfMemory;
    for (value.secondary, secondary) |goal, *target| target.* = try translateGoal(goal);
    return .{ .primary = if (value.primary) |goal| try translateGoal(goal) else null, .secondary = secondary, .body_composition_objective = value.bodyCompositionObjective };
}

fn translateProgramContext(allocator: std.mem.Allocator, value: canonical.ProgramTrainingContext) ExecuteError!athlete_profile.ProgramContext {
    const priorities = allocator.alloc(athlete_profile.MusclePriority, value.musclePriorities.len) catch return error.OutOfMemory;
    for (value.musclePriorities, priorities) |source, *target| target.* = .{ .muscle_id = source.muscleId, .priority = @enumFromInt(@intFromEnum(source.priority)), .weight = source.weight };
    return .{
        .goals = try translateGoalSet(allocator, value.goals),
        .exercise_preferences = try translatePreferences(allocator, value.exercisePreferences),
        .muscle_priorities = priorities,
        .restrictions = try translateRestrictions(allocator, value.restrictions),
        .required_exercise_ids = value.requiredExerciseIds,
        .excluded_exercise_ids = value.excludedExerciseIds,
    };
}

fn translateTrainingContext(allocator: std.mem.Allocator, value: canonical.TrainingContext) ExecuteError!athlete_profile.Context {
    const readiness = allocator.alloc(athlete_profile.ReadinessObservation, value.readiness.len) catch return error.OutOfMemory;
    for (value.readiness, readiness) |source, *target| target.* = .{
        .id = source.id,
        .dimension = @enumFromInt(@intFromEnum(source.dimension)),
        .subject_id = source.subjectId,
        .value = source.value,
        .scale_maximum = source.scaleMaximum,
        .observed_at = source.observedAt,
        .provenance = @enumFromInt(@intFromEnum(source.provenance)),
    };
    return .{
        .location_id = value.locationId,
        .equipment = .{ .override = value.equipment.override, .additions = value.equipment.additions, .removals = value.equipment.removals },
        .available_minutes = if (value.availableMinutes) |minutes| std.math.cast(u16, minutes) orelse return error.InvalidRequest else null,
        .hard_maximum_minutes = if (value.hardMaximumMinutes) |minutes| std.math.cast(u16, minutes) orelse return error.InvalidRequest else null,
        .goals = try translateGoalSet(allocator, value.goals),
        .preferences = try translatePreferences(allocator, value.preferences),
        .restrictions = try translateRestrictions(allocator, value.restrictions),
        .required_exercise_ids = value.requiredExerciseIds,
        .excluded_exercise_ids = value.excludedExerciseIds,
        .readiness = readiness,
    };
}

fn resolvedToCanonical(allocator: std.mem.Allocator, value: athlete_profile.Resolved) ExecuteError!canonical.ResolvedTrainingContext {
    const equipment = try allocator.dupe([]const u8, value.available_equipment_ids);
    const preferences = allocator.alloc(canonical.ResolvedPreference, value.preferences.len) catch return error.OutOfMemory;
    for (value.preferences, preferences) |source, *target| target.* = .{ .value = .{ .targetKind = @enumFromInt(@intFromEnum(source.value.target_kind)), .targetId = source.value.target_id, .level = @enumFromInt(@intFromEnum(source.value.level)) }, .source = @enumFromInt(@intFromEnum(source.source)) };
    const restrictions = allocator.alloc(canonical.ResolvedRestriction, value.restrictions.len) catch return error.OutOfMemory;
    for (value.restrictions, restrictions) |source, *target| target.* = .{ .value = .{ .id = source.value.id, .targetKind = @enumFromInt(@intFromEnum(source.value.target_kind)), .targetId = source.value.target_id }, .source = @enumFromInt(@intFromEnum(source.source)) };
    const priorities = allocator.alloc(canonical.ResolvedMusclePriority, value.muscle_priorities.len) catch return error.OutOfMemory;
    for (value.muscle_priorities, priorities) |source, *target| target.* = .{ .value = .{ .muscleId = source.value.muscle_id, .priority = @enumFromInt(@intFromEnum(source.value.priority)), .weight = source.value.weight }, .source = @enumFromInt(@intFromEnum(source.source)) };
    const required = allocator.alloc(canonical.ResolvedExerciseConstraint, value.required_exercises.len) catch return error.OutOfMemory;
    for (value.required_exercises, required) |source, *target| target.* = .{ .exerciseId = source.exercise_id, .source = @enumFromInt(@intFromEnum(source.source)) };
    const excluded = allocator.alloc(canonical.ResolvedExerciseConstraint, value.excluded_exercises.len) catch return error.OutOfMemory;
    for (value.excluded_exercises, excluded) |source, *target| target.* = .{ .exerciseId = source.exercise_id, .source = @enumFromInt(@intFromEnum(source.source)) };
    const secondary = allocator.alloc(canonical.Goal, value.goals.secondary.len) catch return error.OutOfMemory;
    for (value.goals.secondary, secondary) |goal, *target| target.* = goalToCanonical(goal);
    const familiarity = allocator.alloc(@typeInfo(@TypeOf((canonical.Experience{}).exercises)).pointer.child, value.experience.exercise.len) catch return error.OutOfMemory;
    for (value.experience.exercise, familiarity) |source, *target| target.* = .{ .exerciseId = source.exercise_id, .familiarity = @enumFromInt(@intFromEnum(source.familiarity)) };
    const days = allocator.alloc(@typeInfo(@TypeOf((canonical.SchedulePreference{}).preferredDays)).pointer.child, value.schedule.preferred_days.len) catch return error.OutOfMemory;
    for (value.schedule.preferred_days, days) |source, *target| target.* = @enumFromInt(@intFromEnum(source));
    const readiness = allocator.alloc(canonical.ReadinessObservation, value.readiness.len) catch return error.OutOfMemory;
    for (value.readiness, readiness) |source, *target| target.* = .{ .id = source.id, .dimension = @enumFromInt(@intFromEnum(source.dimension)), .subjectId = source.subject_id, .value = source.value, .scaleMaximum = source.scale_maximum, .observedAt = source.observed_at, .provenance = @enumFromInt(@intFromEnum(source.provenance)) };
    const capabilities = allocator.alloc(canonical.CapabilityObservation, value.capability_observations.len) catch return error.OutOfMemory;
    for (value.capability_observations, capabilities) |source, *target| target.* = .{ .id = source.id, .kind = @enumFromInt(@intFromEnum(source.kind)), .exerciseId = source.exercise_id, .value = if (source.value) |measurement| .{ .amount = measurement.amount, .unit = measurement.unit } else null, .observedAt = source.observed_at, .provenance = @enumFromInt(@intFromEnum(source.provenance)), .customKindId = source.custom_kind_id };
    return .{
        .athleteProfileId = value.athlete_profile_id,
        .athleteProfileRevision = value.athlete_profile_revision,
        .athleteProfileFingerprint = value.athlete_profile_fingerprint,
        .goals = .{ .primary = if (value.goals.primary) |goal| goalToCanonical(goal) else null, .secondary = secondary, .bodyCompositionObjective = value.goals.body_composition_objective },
        .experience = .{ .resistanceTraining = if (value.experience.resistance_training) |item| @enumFromInt(@intFromEnum(item)) else null, .consistentMonths = value.experience.consistent_months, .technicalLiftFamiliarity = if (value.experience.technical_lift_familiarity) |item| @enumFromInt(@intFromEnum(item)) else null, .exercises = familiarity },
        .schedule = .{ .preferredSessionsPerWeek = value.schedule.preferred_sessions_per_week, .minimumSessionsPerWeek = value.schedule.minimum_sessions_per_week, .maximumSessionsPerWeek = value.schedule.maximum_sessions_per_week, .preferredDays = days, .cadence = @enumFromInt(@intFromEnum(value.schedule.cadence)), .preferRestBetweenSessions = value.schedule.prefer_rest_between_sessions },
        .preferredDuration = .{ .preferredMinutes = value.preferred_duration.preferred_minutes, .acceptableMinimumMinutes = value.preferred_duration.acceptable_minimum_minutes, .acceptableMaximumMinutes = value.preferred_duration.acceptable_maximum_minutes, .hardMaximumMinutes = value.preferred_duration.hard_maximum_minutes },
        .availableMinutes = value.available_minutes,
        .hardMaximumMinutes = value.hard_maximum_minutes,
        .units = .{ .load = if (value.units.load) |item| @enumFromInt(@intFromEnum(item)) else null, .bodyweight = if (value.units.bodyweight) |item| @enumFromInt(@intFromEnum(item)) else null, .distance = if (value.units.distance) |item| @enumFromInt(@intFromEnum(item)) else null },
        .locationId = value.location_id,
        .availableEquipmentIds = equipment,
        .preferences = preferences,
        .restrictions = restrictions,
        .musclePriorities = priorities,
        .requiredExercises = required,
        .excludedExercises = excluded,
        .readiness = readiness,
        .capabilityObservations = capabilities,
    };
}

fn goalToCanonical(value: athlete_profile.Goal) canonical.Goal {
    return .{ .id = switch (value.family) {
        .hypertrophy => "hypertrophy",
        .strength => "strength",
        .general_fitness => "general-fitness",
        .muscular_endurance => "muscular-endurance",
        .powerlifting_practice => "powerlifting-practice",
        .limited_equipment => "limited-equipment",
        .maintenance => "maintenance",
        .custom => |id| id,
    }, .weight = value.weight };
}

fn resolvedVersion(requirement: ?[]const u8) ExecuteError!methodology.Version {
    if (requirement) |value| {
        if (!std.mem.eql(u8, value, "^0.1.0") and
            !std.mem.eql(u8, value, "0.1.0"))
        {
            return error.UnsupportedVersion;
        }
    }
    return .{ .major = 0, .minor = 1, .patch = 0 };
}

fn translateCatalog(
    allocator: std.mem.Allocator,
    source: []const canonical.Exercise,
) ExecuteError!training.ExerciseCatalog {
    const exercises = allocator.alloc(training.Exercise, source.len) catch
        return error.OutOfMemory;
    for (source, exercises) |input, *output| {
        output.* = .{
            .id = primitives.Id.parse(input.id) catch return error.InvalidRequest,
            .name = input.name,
            .equipment_ids = try translateIds(allocator, input.equipmentIds),
            .movement_tags = try translateIds(allocator, input.movementTags),
            .unilateral = input.unilateral,
            .aliases = input.aliases,
            .muscle_contributions = try translateMuscles(allocator, input.muscleContributions),
            .knowledge = input.knowledge,
        };
    }
    return .{ .exercises = exercises };
}

fn translateMuscles(
    allocator: std.mem.Allocator,
    source: []const canonical.MuscleContribution,
) ExecuteError![]const training.MuscleContribution {
    const values = allocator.alloc(training.MuscleContribution, source.len) catch return error.OutOfMemory;
    for (source, values) |input, *output| output.* = .{
        .muscle_id = primitives.Id.parse(input.muscleId) catch return error.InvalidRequest,
        .role = switch (input.role) {
            .primary => .primary,
            .secondary => .secondary,
            .stabilizer => .stabilizer,
            .custom => .custom,
        },
        .weight = if (input.weight) |weight| primitives.Decimal.parse(weight) catch return error.InvalidRequest else null,
    };
    return values;
}

fn translateIds(
    allocator: std.mem.Allocator,
    source: []const []const u8,
) ExecuteError![]const primitives.Id {
    const ids = allocator.alloc(primitives.Id, source.len) catch
        return error.OutOfMemory;
    for (source, ids) |input, *output| {
        output.* = primitives.Id.parse(input) catch return error.InvalidRequest;
    }
    return ids;
}

fn translateHistory(
    allocator: std.mem.Allocator,
    source: canonical.HistorySnapshot,
) ExecuteError!training.HistorySnapshot {
    const workouts = allocator.alloc(training.CompletedWorkout, source.workouts.len) catch
        return error.OutOfMemory;
    for (source.workouts, workouts) |input, *output| {
        output.* = .{
            .id = primitives.Id.parse(input.id) catch return error.InvalidRequest,
            .started_at = primitives.Timestamp.parse(input.startedAt) catch
                return error.InvalidRequest,
            .completed_at = primitives.Timestamp.parse(input.completedAt) catch
                return error.InvalidRequest,
            .exercises = try translateCompletedExercises(allocator, input.exercises),
        };
    }
    return .{ .workouts = workouts };
}

fn translateCompletedExercises(
    allocator: std.mem.Allocator,
    source: []const canonical.CompletedExercise,
) ExecuteError![]const training.CompletedExercise {
    const exercises = allocator.alloc(training.CompletedExercise, source.len) catch
        return error.OutOfMemory;
    for (source, exercises) |input, *output| {
        output.* = .{
            .exercise_id = primitives.Id.parse(input.exerciseId) catch
                return error.InvalidRequest,
            .sets = try translateSets(allocator, input.sets),
            .tags = try translateIds(allocator, input.tags),
            .notes = input.notes,
        };
    }
    return exercises;
}

fn translateSets(
    allocator: std.mem.Allocator,
    source: []const canonical.CompletedSet,
) ExecuteError![]const training.CompletedSet {
    const sets = allocator.alloc(training.CompletedSet, source.len) catch
        return error.OutOfMemory;
    for (source, sets) |input, *output| {
        output.* = .{
            .id = if (input.id) |id|
                primitives.Id.parse(id) catch return error.InvalidRequest
            else
                null,
            .kind = primitives.Id.parse(input.kind) catch
                return error.InvalidRequest,
            .actual_metrics = try translateMetrics(allocator, input.actualMetrics),
            .target_metrics = try translateMetrics(allocator, input.targetMetrics),
            .completed_at = if (input.completedAt) |timestamp|
                primitives.Timestamp.parse(timestamp) catch return error.InvalidRequest
            else
                null,
            .status = @enumFromInt(@intFromEnum(input.status)),
        };
    }
    return sets;
}

fn translateMetrics(
    allocator: std.mem.Allocator,
    source: []const canonical.Metric,
) ExecuteError![]const training.Metric {
    const metrics = allocator.alloc(training.Metric, source.len) catch
        return error.OutOfMemory;
    for (source, metrics) |input, *output| {
        output.* = .{
            .code = primitives.Id.parse(input.code) catch
                return error.InvalidRequest,
            .value = .{
                .value = primitives.Decimal.parse(input.value.amount) catch
                    return error.InvalidRequest,
                .unit = primitives.Unit.parse(input.value.unit) catch
                    return error.InvalidRequest,
            },
        };
    }
    return metrics;
}

fn translateState(
    allocator: std.mem.Allocator,
    source: ?canonical.MethodologyState,
    config: double_progression.Config,
) ExecuteError!?double_progression.State {
    const state = source orelse return null;
    if (state.schemaVersion != double_progression.state_schema_version) {
        return error.UnsupportedVersion;
    }
    const data = switch (state.data) {
        .object => |object| object,
        else => return error.InvalidRequest,
    };
    const exercise_value = data.get("exercises") orelse return error.InvalidRequest;
    if (exercise_value == .array) {
        const exercises = std.json.parseFromValueLeaky(
            []const double_progression.ExerciseState,
            allocator,
            exercise_value,
            .{},
        ) catch return error.InvalidRequest;
        return .{
            .schemaVersion = state.schemaVersion,
            .data = .{ .exercises = exercises },
        };
    }
    const keyed = switch (exercise_value) {
        .object => |object| object,
        else => return error.InvalidRequest,
    };
    const exercises = allocator.alloc(
        double_progression.ExerciseState,
        keyed.count(),
    ) catch return error.OutOfMemory;
    var iterator = keyed.iterator();
    var index: usize = 0;
    while (iterator.next()) |entry| : (index += 1) {
        const value = switch (entry.value_ptr.*) {
            .object => |object| object,
            else => return error.InvalidRequest,
        };
        const load_value = value.get("load") orelse return error.InvalidRequest;
        const load = std.json.parseFromValueLeaky(
            canonical.Measurement,
            allocator,
            load_value,
            .{},
        ) catch return error.InvalidRequest;
        exercises[index] = .{
            .exerciseId = entry.key_ptr.*,
            .load = load,
            .targetRepetitions = config.repRange.min,
        };
    }
    return .{
        .schemaVersion = state.schemaVersion,
        .data = .{ .exercises = exercises },
    };
}

test "C runtime reports required size and writes caller-owned output" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var required: usize = 0;
    try std.testing.expectEqual(
        Status.insufficient_output,
        caudex_runtime_execute(runtime, input.ptr, input.len, null, 0, &required),
    );
    try std.testing.expect(required != 0);
    const output = try std.testing.allocator.alloc(u8, required);
    defer std.testing.allocator.free(output);
    var exact_required: usize = 0;
    try std.testing.expectEqual(
        Status.ok,
        caudex_runtime_execute(runtime, input.ptr, input.len, output.ptr, output.len, &exact_required),
    );
    try std.testing.expectEqual(required, exact_required);
    const parsed = try canonical_json.decodeRecommendationResult(
        std.testing.allocator,
        output,
        .{},
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value.ok);
}

test "versioned dispatcher accepts recommendation envelope" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();
    var output: OwnedBuffer = .{};
    defer if (output.data) |data| runtime.allocator().free(data[0..output.capacity]);
    try executeDispatch(
        &runtime,
        @embedFile("../fixtures/operations/recommendation-v1.json"),
        &output,
    );
    try std.testing.expect(output.len != 0);
}

test "versioned dispatcher applies canonical tracking command and batch" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();

    var command_output: OwnedBuffer = .{};
    defer if (command_output.data) |data| runtime.allocator().free(data[0..command_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/tracking-command-v1.json"), &command_output);
    const command_result = try tracking_protocol.decodeCommandResult(
        std.testing.allocator,
        command_output.data.?[0..command_output.len],
        .{},
    );
    defer command_result.deinit();
    try std.testing.expectEqual(@as(u64, 1), command_result.value.outcome.accepted.workout.revision);

    var batch_output: OwnedBuffer = .{};
    defer if (batch_output.data) |data| runtime.allocator().free(data[0..batch_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/tracking-batch-v1.json"), &batch_output);
    const batch_result = try tracking_protocol.decodeAtomicBatchResult(
        std.testing.allocator,
        batch_output.data.?[0..batch_output.len],
        .{},
    );
    defer batch_result.deinit();
    try std.testing.expect(batch_result.value.applied);
    try std.testing.expectEqual(@as(u64, 2), batch_result.value.snapshot.workouts[0].revision);
    try std.testing.expectEqualStrings("squat", batch_result.value.snapshot.exerciseCatalog[0].exerciseId);
}

test "versioned dispatcher exports and validates portable documents" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();

    var export_output: OwnedBuffer = .{};
    defer if (export_output.data) |data| runtime.allocator().free(data[0..export_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/portable-export-v1.json"), &export_output);
    const exported = try canonical_json.decodeValue(
        portable.ExportResult,
        std.testing.allocator,
        export_output.data.?[0..export_output.len],
        .{ .max_input_bytes = portable.max_input_bytes },
    );
    defer exported.deinit();
    try std.testing.expectEqualStrings(
        "185.00",
        exported.value.outcome.accepted.completedWorkouts[0].workout.exercises[0].sets[0].actualMetrics[0].value.amount,
    );

    var import_output: OwnedBuffer = .{};
    defer if (import_output.data) |data| runtime.allocator().free(data[0..import_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/portable-import-v1.json"), &import_output);
    const planned = try canonical_json.decodeValue(
        portable.ImportPlan,
        std.testing.allocator,
        import_output.data.?[0..import_output.len],
        .{},
    );
    defer planned.deinit();
    try std.testing.expect(planned.value.valid);
    try std.testing.expect(planned.value.dryRun);
    try std.testing.expectEqual(@as(usize, 1), planned.value.counts.completedWorkouts);
}

test "versioned dispatcher instantiates a canonical template" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();
    var output: OwnedBuffer = .{};
    defer if (output.data) |data| runtime.allocator().free(data[0..output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/template-instantiation-v1.json"), &output);
    const parsed = try canonical_json.decodeValue(
        workflows.InstantiationDocumentResult,
        std.testing.allocator,
        output.data.?[0..output.len],
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectEqual(tracking_protocol.WorkoutOrigin.template, parsed.value.outcome.accepted.origin);
    try std.testing.expectEqual(@as(u64, 7), parsed.value.outcome.accepted.provenance.?.template.templateRevision);
}

test "versioned dispatcher discovers and validates methodologies" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();
    var list_output: OwnedBuffer = .{};
    defer if (list_output.data) |data| runtime.allocator().free(data[0..list_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/discovery-list-v1.json"), &list_output);
    const listed = try canonical_json.decodeValue(
        discovery.RegistryDescriptor,
        std.testing.allocator,
        list_output.data.?[0..list_output.len],
        .{},
    );
    defer listed.deinit();
    try std.testing.expectEqual(@as(usize, 2), listed.value.methodologies.len);
    try std.testing.expectEqualStrings(double_progression.methodology_id, listed.value.methodologies[0].id);

    var validation_output: OwnedBuffer = .{};
    defer if (validation_output.data) |data| runtime.allocator().free(data[0..validation_output.capacity]);
    try executeDispatch(&runtime, @embedFile("../fixtures/operations/discovery-validate-invalid-v1.json"), &validation_output);
    const validation = try canonical_json.decodeValue(
        ValidationResult,
        std.testing.allocator,
        validation_output.data.?[0..validation_output.len],
        .{},
    );
    defer validation.deinit();
    try std.testing.expect(!validation.value.valid);
    try std.testing.expectEqualStrings("methodology.config_invalid", validation.value.issues[0].code);
}

test "versioned dispatcher plans programs without accepting proposals" {
    var runtime: Runtime = .{ .debug_allocator = .init };
    defer _ = runtime.debug_allocator.deinit();

    const definition =
        \\{"schemaVersion":1,"id":"program","version":"1","displayName":"Program","strategy":{"id":"caudex.fixed-session","configVersion":1,"config":{}},"configurationFingerprint":"fixture-v1","blocks":[{"id":"block","microcycleCount":1,"schedule":{"rotation":{"roleIds":["day"]}},"sessionRoles":[{"id":"day","items":[]}]}]}
    ;
    const validate_request = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"schemaVersion":1,"operation":"validateProgramDefinition","payload":{{"schemaVersion":1,"definition":{s}}}}}
    , .{definition});
    defer std.testing.allocator.free(validate_request);
    var validation_output: OwnedBuffer = .{};
    defer if (validation_output.data) |data| runtime.allocator().free(
        data[0..validation_output.capacity],
    );
    try executeDispatch(&runtime, validate_request, &validation_output);
    const validation = try canonical_json.decodeValue(
        canonical.ProgramDefinitionValidationResult,
        std.testing.allocator,
        validation_output.data.?[0..validation_output.len],
        .{},
    );
    defer validation.deinit();
    try std.testing.expect(validation.value.valid);

    const instantiate_request = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"schemaVersion":1,"operation":"instantiateProgram","payload":{{"schemaVersion":1,"definition":{s},"instanceId":"run","athleteId":"athlete","lifecycle":"active","configuration":{{}}}}}}
    , .{definition});
    defer std.testing.allocator.free(instantiate_request);
    var instantiate_output: OwnedBuffer = .{};
    defer if (instantiate_output.data) |data| runtime.allocator().free(
        data[0..instantiate_output.capacity],
    );
    try executeDispatch(&runtime, instantiate_request, &instantiate_output);
    const instantiated = try canonical_json.decodeValue(
        canonical.ProgramInstantiationResult,
        std.testing.allocator,
        instantiate_output.data.?[0..instantiate_output.len],
        .{},
    );
    defer instantiated.deinit();
    try std.testing.expectEqual(@as(u64, 0), instantiated.value.state.revision);

    const instance =
        \\{"schemaVersion":1,"id":"run","athleteId":"athlete","definition":{"id":"program","version":"1","configurationFingerprint":"fixture-v1"},"lifecycle":"active","configuration":{}}
    ;
    const state =
        \\{"schemaVersion":1,"instanceId":"run","definition":{"id":"program","version":"1","configurationFingerprint":"fixture-v1"},"revision":0,"blockIndex":0,"microcycleIndex":0,"sessionCursor":0,"completedOccurrenceCount":0,"completed":false}
    ;
    const resolve_request = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"schemaVersion":1,"operation":"resolvePlannedSession","payload":{{"schemaVersion":1,"definition":{s},"instance":{s},"state":{s},"catalog":[]}}}}
    , .{ definition, instance, state });
    defer std.testing.allocator.free(resolve_request);
    var resolve_output: OwnedBuffer = .{};
    defer if (resolve_output.data) |data| runtime.allocator().free(
        data[0..resolve_output.capacity],
    );
    try executeDispatch(&runtime, resolve_request, &resolve_output);
    const intent = try canonical_json.decodeValue(
        canonical.PlannedSessionIntentDocument,
        std.testing.allocator,
        resolve_output.data.?[0..resolve_output.len],
        .{},
    );
    defer intent.deinit();
    try std.testing.expectEqualStrings("day", intent.value.roleId);

    const intent_json =
        \\{"schemaVersion":1,"instanceId":"run","definition":{"id":"program","version":"1","configurationFingerprint":"fixture-v1"},"blockId":"block","roleId":"day","occurrenceId":"run:block:0:0:day","planningStateRevision":0,"program":{"strategy":{"id":"caudex.fixed-session","configVersion":1,"config":{}},"exercises":[]}}
    ;
    const advance_request = try std.fmt.allocPrint(std.testing.allocator,
        \\{{"schemaVersion":1,"operation":"proposeProgramAdvancement","payload":{{"schemaVersion":1,"definition":{s},"instance":{s},"state":{s},"intent":{s},"status":"completed"}}}}
    , .{ definition, instance, state, intent_json });
    defer std.testing.allocator.free(advance_request);
    var advance_output: OwnedBuffer = .{};
    defer if (advance_output.data) |data| runtime.allocator().free(
        data[0..advance_output.capacity],
    );
    try executeDispatch(&runtime, advance_request, &advance_output);
    const proposal = try canonical_json.decodeValue(
        canonical.ProgramStateProposalDocument,
        std.testing.allocator,
        advance_output.data.?[0..advance_output.len],
        .{},
    );
    defer proposal.deinit();
    try std.testing.expectEqual(@as(u64, 0), proposal.value.expectedRevision);
    try std.testing.expectEqual(@as(u64, 1), proposal.value.nextState.revision);
}

test "C ABI rejects invalid arguments without exposing errors" {
    var required: usize = 99;
    try std.testing.expectEqual(
        Status.invalid_argument,
        caudex_runtime_execute(null, null, 0, null, 0, &required),
    );
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_create(null));
    try std.testing.expectEqual(@as(u32, 2), caudex_abi_version());
}

test "C ABI leaves insufficient caller output untouched" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var required: usize = 0;
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(runtime, input.ptr, input.len, null, 0, &required));
    const short = try std.testing.allocator.alloc(u8, required - 1);
    defer std.testing.allocator.free(short);
    @memset(short, 0xaa);
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(runtime, input.ptr, input.len, short.ptr, short.len, &required));
    for (short) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
}

test "C ABI validates pointer length and UTF-8 combinations" {
    var runtime: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&runtime));
    defer caudex_runtime_destroy(runtime);
    var required: usize = 0;
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 1, null, 0, &required));
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 0, null, 1, &required));
    try std.testing.expectEqual(Status.invalid_argument, caudex_runtime_execute(runtime, null, 0, null, 0, null));
    const invalid_utf8 = [_]u8{0xff};
    try std.testing.expectEqual(Status.invalid_request, caudex_runtime_execute(runtime, &invalid_utf8, invalid_utf8.len, null, 0, &required));
}

test "C ABI supports independent runtimes" {
    var first: ?*Runtime = null;
    var second: ?*Runtime = null;
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&first));
    defer caudex_runtime_destroy(first);
    try std.testing.expectEqual(Status.ok, caudex_runtime_create(&second));
    defer caudex_runtime_destroy(second);
    try std.testing.expect(first != second);
    const input = @embedFile("../fixtures/operations/recommendation-v1.json");
    var first_required: usize = 0;
    var second_required: usize = 0;
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(first, input.ptr, input.len, null, 0, &first_required));
    try std.testing.expectEqual(Status.insufficient_output, caudex_runtime_execute(second, input.ptr, input.len, null, 0, &second_required));
    try std.testing.expectEqual(first_required, second_required);
}
