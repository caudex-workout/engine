const std = @import("std");
const caudex = @import("caudex");
const canonical = caudex.canonical;
const canonical_json = caudex.canonical_json;
const double_progression = caudex.double_progression;
const discovery = caudex.discovery;
const engine = caudex.engine;
const methodology = caudex.methodology;
const primitives = caudex.primitives;
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
    };
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
    }, try instantiationStorage(allocator), allocator.alloc(tracking.Issue, 16) catch return error.OutOfMemory) catch return error.InvalidRequest;
    const wire: workflows.InstantiationDocumentResult = .{ .outcome = switch (result) {
        .accepted => |workout| .{ .accepted = try workflowWorkoutToWire(allocator, workout) },
        .rejected => |issues| .{ .rejected = try workflowIssuesToWire(allocator, issues) },
    } };
    try encodeOwned(runtime, wire, out);
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
    const request = try translateRequest(arena.allocator(), document.value);
    var engine_output: engine.Output = .{};
    const result = try engine.recommendSession(request, &engine_output);

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
        source.session.availableEquipmentIds,
    );
    for (exercise.equipment_ids) |required| {
        for (available) |candidate| {
            if (required.eql(candidate)) break;
        } else return error.InvalidRequest;
    }
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
        .recommendation = .{ .exercises = &exercises },
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
        request.session.availableEquipmentIds,
    );
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
        .max_working_sets = request.session.maxSets,
    };
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
        };
    }
    return .{ .exercises = exercises };
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
