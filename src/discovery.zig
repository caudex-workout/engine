//! Stable, UI-neutral discovery metadata for compiled methodologies.
//!
//! This module owns the descriptor data serialized by canonical, C, WASM, and
//! npm boundaries. Presentation layout remains a host concern.

const std = @import("std");
const canonical = @import("canonical.zig");
const diagnostics = @import("diagnostics.zig");
const double_progression = @import("double_progression.zig");
const rpe_top_set_backoff = @import("rpe_top_set_backoff.zig");

pub const schema_version: u32 = 1;
pub const max_validation_issues: usize = 128;

pub const Operation = enum {
    recommend,
    evaluate,
    validateConfig,
    validateState,
};

pub const FieldType = enum {
    integer,
    exactDecimal,
    measurement,
    enumeration,
    object,
    array,
    identifier,
};

pub const FieldDescriptor = struct {
    name: []const u8,
    description: []const u8,
    fieldType: FieldType,
    required: bool,
    defaultJson: ?[]const u8 = null,
    minimum: ?[]const u8 = null,
    maximum: ?[]const u8 = null,
    exactDecimal: bool = false,
    unitDimension: ?[]const u8 = null,
    enumChoices: []const []const u8 = &.{},
    deprecated: bool = false,
};

pub const MethodologyDescriptor = struct {
    id: []const u8,
    displayName: []const u8,
    description: []const u8,
    methodologyVersion: []const u8,
    configurationSchemaVersion: u32,
    stateSchemaVersion: u32,
    supportedOperations: []const Operation,
    fields: []const FieldDescriptor,
    configurationSchemaRef: []const u8,
    stateSchemaRef: []const u8,
    deprecated: bool = false,
};

pub const RegistryDescriptor = struct {
    schemaVersion: u32 = schema_version,
    methodologies: []const MethodologyDescriptor,
    supportedOperations: []const []const u8,
};

const all_operations = [_]Operation{ .recommend, .evaluate, .validateConfig, .validateState };
const rpe_operations = [_]Operation{ .recommend, .validateConfig, .validateState };
const canonical_operations = [_][]const u8{
    "recommend",
    "evaluate",
    "applyTrackingCommand",
    "applyTrackingBatch",
    "instantiateRecommendation",
    "instantiateTemplate",
    "completeForEvaluation",
    "listMethodologies",
    "describeMethodology",
    "validateMethodologyConfig",
    "validateMethodologyState",
    "listCapabilities",
};

const rounding_choices = [_][]const u8{ "nearest", "up", "down" };
const hold_regress_choices = [_][]const u8{ "hold", "regress" };
const backoff_choices = [_][]const u8{ "percentage_of_top_set", "percentage_of_estimated_one_rep_max" };
const overshoot_choices = [_][]const u8{ "hold", "decrease_estimate" };
const undershoot_choices = [_][]const u8{ "hold", "increase_estimate" };
const formula_choices = [_][]const u8{"epley"};

const double_progression_fields = [_]FieldDescriptor{
    .{ .name = "repRange", .description = "Inclusive repetition range for working sets.", .fieldType = .object, .required = true },
    .{ .name = "repRange.min", .description = "Minimum target repetitions.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "65535" },
    .{ .name = "repRange.max", .description = "Maximum target repetitions.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "65535" },
    .{ .name = "workingSets", .description = "Number of prescribed working sets.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "64" },
    .{ .name = "advancementCriteria", .description = "Success thresholds used to advance load or repetitions.", .fieldType = .object, .required = true },
    .{ .name = "advancementCriteria.minimumSuccessfulSets", .description = "Minimum number of successful sets required to advance.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "64" },
    .{ .name = "advancementCriteria.minimumRepetitions", .description = "Minimum repetitions per successful set required to advance.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "65535" },
    .{ .name = "initialLoad", .description = "Initial load when history and methodology state have no value.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "loadIncrement", .description = "Exact load increase after successful progression.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "failurePolicy.onPartial", .description = "Action after a partial performance.", .fieldType = .enumeration, .required = true, .enumChoices = &hold_regress_choices },
    .{ .name = "failurePolicy.onFailure", .description = "Action after a failed performance.", .fieldType = .enumeration, .required = true, .enumChoices = &hold_regress_choices },
    .{ .name = "failurePolicy.regressionAmount", .description = "Exact load decrease when regression is selected.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "rounding.mode", .description = "Direction used to round prescribed loads.", .fieldType = .enumeration, .required = true, .enumChoices = &rounding_choices },
    .{ .name = "rounding.quantum", .description = "Exact available load increment.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "exerciseOverrides", .description = "Optional per-exercise configuration overrides.", .fieldType = .array, .required = false, .defaultJson = "[]" },
};

const rpe_fields = [_]FieldDescriptor{
    .{ .name = "initialEstimatedOneRepMax", .description = "Initial estimated one-repetition maximum.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "topSetRepetitions", .description = "Repetitions prescribed for the top set.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "65535" },
    .{ .name = "targetRpe", .description = "Exact target rating of perceived exertion.", .fieldType = .exactDecimal, .required = true, .minimum = "0", .maximum = "10", .exactDecimal = true, .unitDimension = "rpe" },
    .{ .name = "backoff.calculation", .description = "Reference used to calculate backoff load.", .fieldType = .enumeration, .required = true, .enumChoices = &backoff_choices },
    .{ .name = "backoff.percentage", .description = "Exact percentage used for backoff load.", .fieldType = .exactDecimal, .required = true, .minimum = "0", .maximum = "100", .exactDecimal = true, .unitDimension = "ratio" },
    .{ .name = "backoff.repetitions", .description = "Repetitions per backoff set.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "65535" },
    .{ .name = "backoff.setCount", .description = "Number of backoff sets.", .fieldType = .integer, .required = true, .minimum = "1", .maximum = "64" },
    .{ .name = "rounding.mode", .description = "Direction used to round prescribed loads.", .fieldType = .enumeration, .required = true, .enumChoices = &rounding_choices },
    .{ .name = "rounding.quantum", .description = "Exact available load increment.", .fieldType = .measurement, .required = true, .exactDecimal = true, .unitDimension = "mass" },
    .{ .name = "exertionPolicy.tolerance", .description = "Exact RPE tolerance before applying policy.", .fieldType = .exactDecimal, .required = true, .minimum = "0", .maximum = "10", .exactDecimal = true, .unitDimension = "rpe" },
    .{ .name = "exertionPolicy.onOvershoot", .description = "Action when observed exertion exceeds target.", .fieldType = .enumeration, .required = true, .enumChoices = &overshoot_choices },
    .{ .name = "exertionPolicy.onUndershoot", .description = "Action when observed exertion is below target.", .fieldType = .enumeration, .required = true, .enumChoices = &undershoot_choices },
    .{ .name = "exertionPolicy.estimateAdjustmentPercentage", .description = "Exact percentage used to adjust the estimate.", .fieldType = .exactDecimal, .required = true, .minimum = "0", .maximum = "100", .exactDecimal = true, .unitDimension = "ratio" },
    .{ .name = "estimationFormula", .description = "Formula used to estimate one-repetition maximum.", .fieldType = .enumeration, .required = true, .enumChoices = &formula_choices },
};

pub const descriptors = [_]MethodologyDescriptor{
    .{
        .id = double_progression.methodology_id,
        .displayName = "Double progression",
        .description = "Progress repetitions within a range, then advance load after the configured success criteria are met.",
        .methodologyVersion = "0.1.0",
        .configurationSchemaVersion = double_progression.config_version,
        .stateSchemaVersion = double_progression.state_schema_version,
        .supportedOperations = &all_operations,
        .fields = &double_progression_fields,
        .configurationSchemaRef = "schemas/methodologies/double-progression-config-v1.schema.json",
        .stateSchemaRef = "schemas/methodologies/double-progression-state-v1.schema.json",
    },
    .{
        .id = rpe_top_set_backoff.methodology_id,
        .displayName = "RPE top set and backoff",
        .description = "Prescribe an RPE-targeted top set and deterministic percentage-based backoff work.",
        .methodologyVersion = "0.1.0",
        .configurationSchemaVersion = rpe_top_set_backoff.config_version,
        .stateSchemaVersion = rpe_top_set_backoff.state_schema_version,
        .supportedOperations = &rpe_operations,
        .fields = &rpe_fields,
        .configurationSchemaRef = "schemas/methodologies/rpe-top-set-backoff-config-v1.schema.json",
        .stateSchemaRef = "schemas/methodologies/rpe-top-set-backoff-state-v1.schema.json",
    },
};

pub fn registry() RegistryDescriptor {
    return .{ .methodologies = &descriptors, .supportedOperations = &canonical_operations };
}

pub fn find(id: []const u8) ?*const MethodologyDescriptor {
    for (&descriptors) |*descriptor| {
        if (std.mem.eql(u8, descriptor.id, id)) return descriptor;
    }
    return null;
}

pub const Config = union(enum) {
    doubleProgression: double_progression.Config,
    rpeTopSetBackoff: rpe_top_set_backoff.Config,
};

pub const State = union(enum) {
    doubleProgression: struct { config: double_progression.Config, state: double_progression.State },
    rpeTopSetBackoff: struct { config: rpe_top_set_backoff.Config, state: rpe_top_set_backoff.State },
};

pub fn validateConfig(value: Config, issue_storage: []canonical.ValidationIssue) diagnostics.IssueWriter.AppendError![]const canonical.ValidationIssue {
    var issues: diagnostics.IssueWriter = .init(issue_storage);
    switch (value) {
        .doubleProgression => |config| try double_progression.validateConfig(config, &issues),
        .rpeTopSetBackoff => |config| try rpe_top_set_backoff.validateConfig(config, &issues),
    }
    return issues.items();
}

pub fn validateState(value: State, issue_storage: []canonical.ValidationIssue) diagnostics.IssueWriter.AppendError![]const canonical.ValidationIssue {
    var issues: diagnostics.IssueWriter = .init(issue_storage);
    switch (value) {
        .doubleProgression => |input| try double_progression.validateState(input.config, input.state, &issues),
        .rpeTopSetBackoff => |input| try rpe_top_set_backoff.validateState(input.config, input.state, &issues),
    }
    return issues.items();
}

test "descriptors and typed validation share methodology sources" {
    try std.testing.expectEqual(@as(usize, 2), registry().methodologies.len);
    const descriptor = find(double_progression.methodology_id).?;
    try std.testing.expectEqual(double_progression.config_version, descriptor.configurationSchemaVersion);
    try std.testing.expect(descriptor.fields.len >= 10);
    try std.testing.expect(find("missing") == null);
}
