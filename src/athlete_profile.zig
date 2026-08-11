//! Persistent athlete intent and one-session training-context resolution.
//!
//! This module is deliberately strategy-neutral. It combines explicit input
//! snapshots; it does not infer preferences, diagnose restrictions, estimate
//! recovery, or own progression state.

const std = @import("std");
const primitives = @import("primitives.zig");

pub const schema_version: u32 = 1;
pub const max_items: usize = 128;

pub const GoalFamily = union(enum) {
    hypertrophy,
    strength,
    general_fitness,
    muscular_endurance,
    powerlifting_practice,
    limited_equipment,
    maintenance,
    custom: []const u8,
};

pub const Goal = struct {
    family: GoalFamily,
    weight: ?u16 = null,
};

pub const GoalSet = struct {
    primary: ?Goal = null,
    secondary: []const Goal = &.{},
    body_composition_objective: ?[]const u8 = null,
};

pub const ExperienceCategory = enum { novice, intermediate, advanced };
pub const Familiarity = enum { unfamiliar, learning, familiar, proficient };

pub const ExerciseFamiliarity = struct {
    exercise_id: []const u8,
    familiarity: Familiarity,
};

pub const Experience = struct {
    resistance_training: ?ExperienceCategory = null,
    consistent_months: ?u16 = null,
    technical_lift_familiarity: ?Familiarity = null,
    exercise: []const ExerciseFamiliarity = &.{},
};

pub const Weekday = enum { monday, tuesday, wednesday, thursday, friday, saturday, sunday };
pub const Cadence = enum { unspecified, fixed_weekdays, rolling };

pub const SchedulePreference = struct {
    preferred_sessions_per_week: ?u8 = null,
    minimum_sessions_per_week: ?u8 = null,
    maximum_sessions_per_week: ?u8 = null,
    preferred_days: []const Weekday = &.{},
    cadence: Cadence = .unspecified,
    prefer_rest_between_sessions: ?bool = null,
};

pub const DurationPreference = struct {
    preferred_minutes: ?u16 = null,
    acceptable_minimum_minutes: ?u16 = null,
    acceptable_maximum_minutes: ?u16 = null,
    hard_maximum_minutes: ?u16 = null,
};

pub const UnitPreferences = struct {
    load: ?enum { kilograms, pounds } = null,
    bodyweight: ?enum { kilograms, pounds } = null,
    distance: ?enum { meters, kilometers, feet, miles } = null,
};

pub const PreferenceLevel = enum { preferred, deprioritized, excluded, required };
pub const PreferenceTargetKind = enum { exercise, exercise_family, movement_pattern, equipment_category };
pub const Preference = struct {
    target_kind: PreferenceTargetKind,
    target_id: []const u8,
    level: PreferenceLevel,
};

pub const MusclePriorityLevel = enum { emphasize, balanced, maintain, deprioritize };
pub const MusclePriority = struct {
    muscle_id: []const u8,
    priority: MusclePriorityLevel,
    weight: ?u16 = null,
};

pub const RestrictionTargetKind = enum { exercise, exercise_family, movement_pattern, restriction_tag, equipment };
pub const Restriction = struct {
    id: []const u8,
    target_kind: RestrictionTargetKind,
    target_id: []const u8,
};

pub const EquipmentItem = struct {
    equipment_id: []const u8,
    minimum_load_increment: ?Measurement = null,
};

pub const TrainingLocation = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    equipment: []const EquipmentItem = &.{},
    metadata: ?std.json.Value = null,
};

pub const Measurement = struct {
    amount: []const u8,
    unit: []const u8,
};

pub const ObservationProvenance = enum { athlete_reported, host_observed, device_supplied, imported, unknown };
pub const CapabilityKind = enum { recent_performance, estimated_one_rep_max, assistance_capacity, exercise_familiarity, benchmark, custom };
pub const CapabilityObservation = struct {
    id: []const u8,
    kind: CapabilityKind,
    exercise_id: ?[]const u8 = null,
    value: ?Measurement = null,
    observed_at: []const u8,
    provenance: ObservationProvenance = .unknown,
    custom_kind_id: ?[]const u8 = null,
};

pub const AthleteProfile = struct {
    schema_version: u32 = schema_version,
    id: []const u8,
    revision: u64 = 0,
    display_name: ?[]const u8 = null,
    goals: GoalSet = .{},
    experience: Experience = .{},
    schedule: SchedulePreference = .{},
    duration: DurationPreference = .{},
    units: UnitPreferences = .{},
    exercise_preferences: []const Preference = &.{},
    muscle_priorities: []const MusclePriority = &.{},
    restrictions: []const Restriction = &.{},
    locations: []const TrainingLocation = &.{},
    capability_observations: []const CapabilityObservation = &.{},
    metadata: ?std.json.Value = null,
};

pub const ReadinessDimension = enum { overall, fatigue, sleep_quality, pain, soreness };
pub const ReadinessObservation = struct {
    id: []const u8,
    dimension: ReadinessDimension,
    subject_id: ?[]const u8 = null,
    value: u8,
    scale_maximum: u8,
    observed_at: []const u8,
    provenance: ObservationProvenance = .athlete_reported,
};

pub const EquipmentDelta = struct {
    /// When non-null, replaces the selected location baseline before deltas.
    override: ?[]const []const u8 = null,
    additions: []const []const u8 = &.{},
    removals: []const []const u8 = &.{},
};

pub const Context = struct {
    location_id: ?[]const u8 = null,
    equipment: EquipmentDelta = .{},
    available_minutes: ?u16 = null,
    hard_maximum_minutes: ?u16 = null,
    goals: GoalSet = .{},
    preferences: []const Preference = &.{},
    restrictions: []const Restriction = &.{},
    required_exercise_ids: []const []const u8 = &.{},
    excluded_exercise_ids: []const []const u8 = &.{},
    readiness: []const ReadinessObservation = &.{},
};

/// Program-owned specialization. It is never written back to the profile.
pub const ProgramContext = struct {
    goals: GoalSet = .{},
    exercise_preferences: []const Preference = &.{},
    muscle_priorities: []const MusclePriority = &.{},
    restrictions: []const Restriction = &.{},
    required_exercise_ids: []const []const u8 = &.{},
    excluded_exercise_ids: []const []const u8 = &.{},
};

pub const Source = enum { engine_default, athlete_profile, program, location_profile, session, explicit_request };
pub const SourcedRestriction = struct { value: Restriction, source: Source };
pub const SourcedPreference = struct { value: Preference, source: Source };
pub const SourcedMusclePriority = struct { value: MusclePriority, source: Source };
pub const SourcedExercise = struct { exercise_id: []const u8, source: Source };

pub const Resolved = struct {
    schema_version: u32 = schema_version,
    athlete_profile_id: []const u8,
    athlete_profile_revision: u64,
    athlete_profile_fingerprint: []const u8,
    goals: GoalSet,
    experience: Experience,
    schedule: SchedulePreference,
    preferred_duration: DurationPreference,
    available_minutes: ?u16,
    hard_maximum_minutes: ?u16,
    units: UnitPreferences,
    location_id: ?[]const u8,
    available_equipment_ids: []const []const u8,
    preferences: []const SourcedPreference,
    restrictions: []const SourcedRestriction,
    muscle_priorities: []const SourcedMusclePriority,
    required_exercises: []const SourcedExercise,
    excluded_exercises: []const SourcedExercise,
    readiness: []const ReadinessObservation,
    capability_observations: []const CapabilityObservation,
};

pub const Issue = struct {
    code: []const u8,
    path: []const u8,
    message: []const u8,
};

pub const ResolveError = error{ InvalidProfile, InvalidContext, OutOfMemory };

pub const OwnedResolved = struct {
    arena: std.heap.ArenaAllocator,
    value: Resolved,
    pub fn deinit(self: *OwnedResolved) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Resolves profile, program, session, and final request layers using
/// field-specific semantics. `request` is the final explicit request layer.
pub fn resolve(
    backing_allocator: std.mem.Allocator,
    profile: AthleteProfile,
    program: ProgramContext,
    session: Context,
    request: Context,
) ResolveError!OwnedResolved {
    var issue_storage: [64]Issue = undefined;
    if ((validate(profile, program, session, request, &issue_storage) catch return error.InvalidProfile).len != 0)
        return error.InvalidContext;

    var arena = std.heap.ArenaAllocator.init(backing_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();
    const location = selectedLocation(profile.locations, request.location_id orelse session.location_id);
    const equipment = resolveEquipment(allocator, location, session.equipment, request.equipment) catch return error.OutOfMemory;
    const restrictions = try sourceRestrictions(allocator, profile.restrictions, program.restrictions, session.restrictions, request.restrictions);
    const preferences = try sourcePreferences(allocator, profile.exercise_preferences, program.exercise_preferences, session.preferences, request.preferences);
    const priorities = try sourcePriorities(allocator, profile.muscle_priorities, program.muscle_priorities);
    const required = try sourceExercises(allocator, profile.exercise_preferences, program.required_exercise_ids, session.required_exercise_ids, request.required_exercise_ids);
    const excluded = try sourceExcluded(allocator, profile.exercise_preferences, program.excluded_exercise_ids, session.excluded_exercise_ids, request.excluded_exercise_ids);
    const fingerprint = try profileFingerprint(allocator, profile);
    const resolved_goals = GoalSet{
        .primary = request.goals.primary orelse session.goals.primary orelse program.goals.primary orelse profile.goals.primary,
        .secondary = if (request.goals.secondary.len != 0) request.goals.secondary else if (session.goals.secondary.len != 0) session.goals.secondary else if (program.goals.secondary.len != 0) program.goals.secondary else profile.goals.secondary,
        .body_composition_objective = request.goals.body_composition_objective orelse session.goals.body_composition_objective orelse program.goals.body_composition_objective orelse profile.goals.body_composition_objective,
    };
    const session_limit = request.hard_maximum_minutes orelse request.available_minutes orelse session.hard_maximum_minutes orelse session.available_minutes;
    return .{ .arena = arena, .value = .{
        .athlete_profile_id = profile.id,
        .athlete_profile_revision = profile.revision,
        .athlete_profile_fingerprint = fingerprint,
        .goals = resolved_goals,
        .experience = profile.experience,
        .schedule = profile.schedule,
        .preferred_duration = profile.duration,
        .available_minutes = request.available_minutes orelse session.available_minutes,
        .hard_maximum_minutes = session_limit orelse profile.duration.hard_maximum_minutes,
        .units = profile.units,
        .location_id = if (location) |value| value.id else null,
        .available_equipment_ids = equipment,
        .preferences = preferences,
        .restrictions = restrictions,
        .muscle_priorities = priorities,
        .required_exercises = required,
        .excluded_exercises = excluded,
        .readiness = if (request.readiness.len != 0) request.readiness else session.readiness,
        .capability_observations = profile.capability_observations,
    } };
}

pub fn validate(profile: AthleteProfile, program: ProgramContext, session: Context, request: Context, storage: []Issue) error{IssueBufferFull}![]const Issue {
    var count: usize = 0;
    if (profile.id.len == 0) try addIssue(storage, &count, "profile.id_required", "/profile/id", "A stable opaque profile ID is required.");
    if (profile.schema_version != schema_version) try addIssue(storage, &count, "profile.version_unsupported", "/profile/schemaVersion", "The athlete profile schema version is unsupported.");
    validateSchedule(profile.schedule, storage, &count) catch return error.IssueBufferFull;
    validateDuration(profile.duration, "/profile/duration", storage, &count) catch return error.IssueBufferFull;
    validateGoals(profile.goals, "/profile/goals", storage, &count) catch return error.IssueBufferFull;
    try validateUniqueLocations(profile.locations, storage, &count);
    try validatePreferences(profile.exercise_preferences, "/profile/exercisePreferences", storage, &count);
    try validatePriorities(profile.muscle_priorities, "/profile/musclePriorities", storage, &count);
    try validateRestrictions(profile.restrictions, "/profile/restrictions", storage, &count);
    try validateObservations(profile.capability_observations, storage, &count);
    try validateContext(profile, program, session, "/session", storage, &count);
    try validateContext(profile, program, request, "/request", storage, &count);
    try validateCrossLayerConflicts(profile, program, session, request, storage, &count);
    return storage[0..count];
}

fn validateSchedule(value: SchedulePreference, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    const min = value.minimum_sessions_per_week;
    const preferred = value.preferred_sessions_per_week;
    const max = value.maximum_sessions_per_week;
    if ((min orelse 0) > 7 or (preferred orelse 0) > 7 or (max orelse 0) > 7 or
        (min != null and max != null and min.? > max.?) or
        (preferred != null and min != null and preferred.? < min.?) or
        (preferred != null and max != null and preferred.? > max.?))
        try addIssue(storage, count, "profile.frequency_invalid", "/profile/schedule", "Weekly frequency bounds must be ordered values from zero through seven.");
    if (value.cadence == .fixed_weekdays and value.preferred_days.len == 0)
        try addIssue(storage, count, "profile.schedule_days_required", "/profile/schedule/preferredDays", "A fixed-weekday cadence requires preferred days.");
}

fn validateDuration(value: DurationPreference, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    if ((value.acceptable_minimum_minutes orelse 0) > (value.acceptable_maximum_minutes orelse std.math.maxInt(u16)) or
        (value.preferred_minutes != null and value.acceptable_minimum_minutes != null and value.preferred_minutes.? < value.acceptable_minimum_minutes.?) or
        (value.preferred_minutes != null and value.acceptable_maximum_minutes != null and value.preferred_minutes.? > value.acceptable_maximum_minutes.?) or
        (value.hard_maximum_minutes != null and value.acceptable_minimum_minutes != null and value.hard_maximum_minutes.? < value.acceptable_minimum_minutes.?))
        try addIssue(storage, count, "profile.duration_invalid", path, "Duration minimum, preference, maximum, and hard maximum are contradictory.");
}

fn validateGoals(value: GoalSet, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    var total: u32 = if (value.primary) |goal| goal.weight orelse 0 else 0;
    for (value.secondary, 0..) |goal, index| {
        total = std.math.add(u32, total, goal.weight orelse 0) catch std.math.maxInt(u32);
        for (value.secondary[0..index]) |prior| if (goalEqual(goal, prior))
            try addIssue(storage, count, "profile.goal_duplicate", path, "Goal families must be unique within a goal set.");
        if (value.primary) |primary| if (goalEqual(goal, primary))
            try addIssue(storage, count, "profile.goal_duplicate", path, "The primary goal cannot also be a secondary goal.");
    }
    if (total > 1000) try addIssue(storage, count, "profile.goal_weight_invalid", path, "Goal weights must have a bounded total no greater than 1000.");
}

fn validateUniqueLocations(values: []const TrainingLocation, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    if (values.len > max_items) try addIssue(storage, count, "profile.location_limit", "/profile/locations", "The location limit was exceeded.");
    for (values, 0..) |location, index| {
        if (location.id.len == 0) try addIssue(storage, count, "profile.location_id_required", "/profile/locations", "Every location requires a stable ID.");
        for (values[0..index]) |prior| if (std.mem.eql(u8, prior.id, location.id))
            try addIssue(storage, count, "profile.location_duplicate", "/profile/locations", "Training location IDs must be unique.");
        for (location.equipment, 0..) |item, item_index| for (location.equipment[0..item_index]) |prior| if (std.mem.eql(u8, prior.equipment_id, item.equipment_id))
            try addIssue(storage, count, "profile.equipment_duplicate", "/profile/locations/equipment", "Equipment IDs must be unique within a location.");
    }
}

fn validatePreferences(values: []const Preference, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    for (values, 0..) |value, index| for (values[0..index]) |prior| if (value.target_kind == prior.target_kind and std.mem.eql(u8, value.target_id, prior.target_id))
        try addIssue(storage, count, "profile.exercise_preference_conflict", path, "A preference target must have exactly one explicit level in a layer.");
}

fn validatePriorities(values: []const MusclePriority, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    for (values, 0..) |value, index| {
        if (value.muscle_id.len == 0 or (value.weight orelse 0) > 1000) try addIssue(storage, count, "profile.muscle_priority_invalid", path, "Muscle priorities require an ID and a weight no greater than 1000.");
        for (values[0..index]) |prior| if (std.mem.eql(u8, value.muscle_id, prior.muscle_id))
            try addIssue(storage, count, "profile.muscle_priority_duplicate", path, "Muscle priority IDs must be unique within a layer.");
    }
}

fn validateRestrictions(values: []const Restriction, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    for (values, 0..) |value, index| {
        if (value.id.len == 0 or value.target_id.len == 0)
            try addIssue(storage, count, "profile.restriction_invalid", path, "Restrictions require stable IDs and authoritative target IDs.");
        for (values[0..index]) |prior| if (std.mem.eql(u8, value.id, prior.id))
            try addIssue(storage, count, "profile.restriction_duplicate", path, "Restriction IDs must be unique within a layer.");
    }
}

fn validateObservations(values: []const CapabilityObservation, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    for (values, 0..) |value, index| {
        const invalid_measurement = if (value.value) |measurement|
            (primitives.Decimal.parse(measurement.amount) catch null) == null or
                (primitives.Unit.parse(measurement.unit) catch null) == null
        else
            false;
        const invalid_timestamp = if (primitives.Timestamp.parse(value.observed_at)) |_| false else |_| true;
        if (value.id.len == 0 or invalid_timestamp or
            (value.kind == .custom and value.custom_kind_id == null) or invalid_measurement)
            try addIssue(storage, count, "profile.capability_observation_invalid", "/profile/capabilityObservations", "Capability observations require stable identity, time, and well-formed typed values.");
        for (values[0..index]) |prior| if (std.mem.eql(u8, value.id, prior.id))
            try addIssue(storage, count, "profile.capability_observation_duplicate", "/profile/capabilityObservations", "Capability observation IDs must be unique.");
    }
}

fn validateContext(profile: AthleteProfile, program: ProgramContext, value: Context, path: []const u8, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    _ = program;
    if (value.location_id) |id| if (selectedLocation(profile.locations, id) == null)
        try addIssue(storage, count, "context.location_unknown", path, "The selected training-location profile does not exist.");
    try validatePreferences(value.preferences, path, storage, count);
    try validateRestrictions(value.restrictions, path, storage, count);
    try validateGoals(value.goals, path, storage, count);
    for (value.equipment.additions) |added| for (value.equipment.removals) |removed| if (std.mem.eql(u8, added, removed))
        try addIssue(storage, count, "context.equipment_delta_conflict", path, "Equipment cannot be both added and removed in one context layer.");
    for (value.readiness, 0..) |observation, index| {
        const invalid_timestamp = if (primitives.Timestamp.parse(observation.observed_at)) |_| false else |_| true;
        if (observation.id.len == 0 or invalid_timestamp or observation.scale_maximum == 0 or observation.value > observation.scale_maximum)
            try addIssue(storage, count, "context.readiness_observation_invalid", path, "Readiness is a time-bound observation with a value inside its declared scale.");
        for (value.readiness[0..index]) |prior| if (std.mem.eql(u8, observation.id, prior.id))
            try addIssue(storage, count, "context.readiness_observation_duplicate", path, "Readiness observation IDs must be unique within a layer.");
    }
}

fn validateCrossLayerConflicts(profile: AthleteProfile, program: ProgramContext, session: Context, request: Context, storage: []Issue, count: *usize) error{IssueBufferFull}!void {
    const required_layers = [_][]const []const u8{ program.required_exercise_ids, session.required_exercise_ids, request.required_exercise_ids };
    const excluded_layers = [_][]const []const u8{ program.excluded_exercise_ids, session.excluded_exercise_ids, request.excluded_exercise_ids };
    for (required_layers) |required| {
        for (required) |id| {
            for (excluded_layers) |excluded| {
                for (excluded) |candidate| if (std.mem.eql(u8, id, candidate))
                    try addIssue(storage, count, "context.exercise_required_excluded", "/context", "An exercise cannot be both required and excluded.");
            }
            for (profile.exercise_preferences) |preference| if (preference.target_kind == .exercise and preference.level == .excluded and std.mem.eql(u8, id, preference.target_id))
                try addIssue(storage, count, "context.exercise_required_excluded", "/context", "A required exercise conflicts with a persistent exclusion.");
            for (profile.restrictions) |restriction| if (restriction.target_kind == .exercise and std.mem.eql(u8, id, restriction.target_id))
                try addIssue(storage, count, "context.exercise_required_restricted", "/context", "A required exercise conflicts with a persistent hard restriction.");
        }
    }
}

fn resolveEquipment(allocator: std.mem.Allocator, location: ?TrainingLocation, session: EquipmentDelta, request: EquipmentDelta) ![]const []const u8 {
    var values: std.ArrayList([]const u8) = .empty;
    if (request.override orelse session.override) |override| {
        for (override) |id| try appendUnique(&values, allocator, id);
    } else if (location) |selected| for (selected.equipment) |item| try appendUnique(&values, allocator, item.equipment_id);
    try applyEquipmentDelta(&values, allocator, session);
    try applyEquipmentDelta(&values, allocator, request);
    return values.toOwnedSlice(allocator);
}

fn applyEquipmentDelta(values: *std.ArrayList([]const u8), allocator: std.mem.Allocator, delta: EquipmentDelta) !void {
    if (delta.override) |override| {
        values.clearRetainingCapacity();
        for (override) |id| try appendUnique(values, allocator, id);
    }
    for (delta.removals) |removed| {
        var index: usize = 0;
        while (index < values.items.len) {
            if (std.mem.eql(u8, values.items[index], removed)) {
                _ = values.orderedRemove(index);
            } else {
                index += 1;
            }
        }
    }
    for (delta.additions) |added| try appendUnique(values, allocator, added);
}

fn appendUnique(values: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (values.items) |candidate| if (std.mem.eql(u8, candidate, value)) return;
    try values.append(allocator, value);
}

fn selectedLocation(locations: []const TrainingLocation, id: ?[]const u8) ?TrainingLocation {
    const wanted = id orelse return null;
    for (locations) |location| if (std.mem.eql(u8, location.id, wanted)) return location;
    return null;
}

fn sourceRestrictions(allocator: std.mem.Allocator, profile: []const Restriction, program: []const Restriction, session: []const Restriction, request: []const Restriction) ![]const SourcedRestriction {
    var values: std.ArrayList(SourcedRestriction) = .empty;
    for (profile) |value| try values.append(allocator, .{ .value = value, .source = .athlete_profile });
    for (program) |value| try values.append(allocator, .{ .value = value, .source = .program });
    for (session) |value| try values.append(allocator, .{ .value = value, .source = .session });
    for (request) |value| try values.append(allocator, .{ .value = value, .source = .explicit_request });
    return values.toOwnedSlice(allocator);
}

fn sourcePreferences(allocator: std.mem.Allocator, profile: []const Preference, program: []const Preference, session: []const Preference, request: []const Preference) ![]const SourcedPreference {
    var values: std.ArrayList(SourcedPreference) = .empty;
    for (profile) |value| try values.append(allocator, .{ .value = value, .source = .athlete_profile });
    for (program) |value| try values.append(allocator, .{ .value = value, .source = .program });
    for (session) |value| try values.append(allocator, .{ .value = value, .source = .session });
    for (request) |value| try values.append(allocator, .{ .value = value, .source = .explicit_request });
    return values.toOwnedSlice(allocator);
}

fn sourcePriorities(allocator: std.mem.Allocator, profile: []const MusclePriority, program: []const MusclePriority) ![]const SourcedMusclePriority {
    var values: std.ArrayList(SourcedMusclePriority) = .empty;
    for (profile) |value| try values.append(allocator, .{ .value = value, .source = .athlete_profile });
    for (program) |value| try values.append(allocator, .{ .value = value, .source = .program });
    return values.toOwnedSlice(allocator);
}

fn sourceExercises(allocator: std.mem.Allocator, preferences: []const Preference, program: []const []const u8, session: []const []const u8, request: []const []const u8) ![]const SourcedExercise {
    var values: std.ArrayList(SourcedExercise) = .empty;
    for (preferences) |preference| if (preference.target_kind == .exercise and preference.level == .required)
        try values.append(allocator, .{ .exercise_id = preference.target_id, .source = .athlete_profile });
    for (program) |id| try values.append(allocator, .{ .exercise_id = id, .source = .program });
    for (session) |id| try values.append(allocator, .{ .exercise_id = id, .source = .session });
    for (request) |id| try values.append(allocator, .{ .exercise_id = id, .source = .explicit_request });
    return values.toOwnedSlice(allocator);
}

fn sourceExcluded(allocator: std.mem.Allocator, preferences: []const Preference, program: []const []const u8, session: []const []const u8, request: []const []const u8) ![]const SourcedExercise {
    var values: std.ArrayList(SourcedExercise) = .empty;
    for (preferences) |preference| if (preference.target_kind == .exercise and preference.level == .excluded)
        try values.append(allocator, .{ .exercise_id = preference.target_id, .source = .athlete_profile });
    for (program) |id| try values.append(allocator, .{ .exercise_id = id, .source = .program });
    for (session) |id| try values.append(allocator, .{ .exercise_id = id, .source = .session });
    for (request) |id| try values.append(allocator, .{ .exercise_id = id, .source = .explicit_request });
    return values.toOwnedSlice(allocator);
}

fn profileFingerprint(allocator: std.mem.Allocator, profile: AthleteProfile) ![]const u8 {
    // A programming-relevant edit must advance the profile revision. Keeping
    // this token structural makes it identical across Zig, C/JSON, and JS
    // without defining a second language-specific JSON canonicalization.
    return std.fmt.allocPrint(allocator, "profile:{s}:{d}", .{ profile.id, profile.revision });
}

fn goalEqual(left: Goal, right: Goal) bool {
    if (std.meta.activeTag(left.family) != std.meta.activeTag(right.family)) return false;
    return switch (left.family) {
        .custom => |id| std.mem.eql(u8, id, right.family.custom),
        else => true,
    };
}

fn addIssue(storage: []Issue, count: *usize, code: []const u8, path: []const u8, message: []const u8) error{IssueBufferFull}!void {
    if (count.* == storage.len) return error.IssueBufferFull;
    storage[count.*] = .{ .code = code, .path = path, .message = message };
    count.* += 1;
}

test "persistent and session context resolve with explicit provenance" {
    const locations = [_]TrainingLocation{
        .{ .id = "gym", .equipment = &.{ .{ .equipment_id = "barbell" }, .{ .equipment_id = "cable-stack" } } },
        .{ .id = "home", .equipment = &.{ .{ .equipment_id = "dumbbell" }, .{ .equipment_id = "adjustable-bench" }, .{ .equipment_id = "pull-up-bar" } } },
    };
    var resolved = try resolve(std.testing.allocator, .{
        .id = "athlete-1",
        .revision = 17,
        .goals = .{ .primary = .{ .family = .hypertrophy } },
        .experience = .{ .resistance_training = .intermediate },
        .schedule = .{ .preferred_sessions_per_week = 4 },
        .duration = .{ .preferred_minutes = 60, .acceptable_minimum_minutes = 45, .acceptable_maximum_minutes = 75 },
        .exercise_preferences = &.{.{ .target_kind = .exercise, .target_id = "incline-dumbbell-press", .level = .preferred }},
        .muscle_priorities = &.{.{ .muscle_id = "chest", .priority = .emphasize }},
        .restrictions = &.{.{ .id = "no-jumping", .target_kind = .restriction_tag, .target_id = "jumping" }},
        .locations = &locations,
    }, .{}, .{
        .location_id = "home",
        .available_minutes = 35,
        .equipment = .{ .removals = &.{"pull-up-bar"} },
        .restrictions = &.{.{ .id = "today-no-overhead", .target_kind = .movement_pattern, .target_id = "overhead-push" }},
    }, .{});
    defer resolved.deinit();
    try std.testing.expectEqual(@as(?u16, 60), resolved.value.preferred_duration.preferred_minutes);
    try std.testing.expectEqual(@as(?u16, 35), resolved.value.available_minutes);
    try std.testing.expectEqualStrings("home", resolved.value.location_id.?);
    try std.testing.expectEqualDeep(&[_][]const u8{ "dumbbell", "adjustable-bench" }, resolved.value.available_equipment_ids);
    try std.testing.expectEqual(@as(usize, 2), resolved.value.restrictions.len);
    try std.testing.expectEqual(Source.athlete_profile, resolved.value.restrictions[0].source);
    try std.testing.expectEqual(Source.session, resolved.value.restrictions[1].source);
    try std.testing.expectEqual(@as(usize, 1), resolved.value.muscle_priorities.len);
}

test "required and excluded exercise is a structured conflict" {
    var issues: [8]Issue = undefined;
    const found = try validate(.{ .id = "athlete", .exercise_preferences = &.{.{ .target_kind = .exercise, .target_id = "squat", .level = .excluded }} }, .{}, .{ .required_exercise_ids = &.{"squat"} }, .{}, &issues);
    try std.testing.expectEqualStrings("context.exercise_required_excluded", found[0].code);
}

test "missing optional profile observations remain unknown" {
    var resolved = try resolve(std.testing.allocator, .{ .id = "minimal" }, .{}, .{}, .{});
    defer resolved.deinit();
    try std.testing.expectEqual(@as(?ExperienceCategory, null), resolved.value.experience.resistance_training);
    try std.testing.expectEqual(@as(?u8, null), resolved.value.schedule.preferred_sessions_per_week);
    try std.testing.expectEqual(@as(usize, 0), resolved.value.readiness.len);
}
