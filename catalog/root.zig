//! Optional first-party exercise catalog generated from a pinned textual
//! free-exercise-db snapshot. The programming core does not import this module.

const std = @import("std");
const caudex = @import("caudex");

pub const schema_version: u32 = 2;
pub const max_records: usize = 2000;
pub const max_search_results: usize = 256;
pub const embedded_json = @embedFile("generated/catalog.json");

pub const TaxonomyRef = struct {
    sourceValue: []const u8,
    sourceId: []const u8,
    normalizedId: []const u8,
};

pub const SourceProvenance = struct {
    dataset: []const u8,
    upstreamRepository: []const u8,
    upstreamCommit: []const u8,
    upstreamId: []const u8,
    license: []const u8,
};

pub const Record = struct {
    id: []const u8,
    upstreamId: []const u8,
    name: []const u8,
    aliases: []const []const u8 = &.{},
    force: ?[]const u8 = null,
    difficulty: ?[]const u8 = null,
    mechanic: ?[]const u8 = null,
    equipment: ?TaxonomyRef = null,
    primaryMuscles: []const TaxonomyRef = &.{},
    secondaryMuscles: []const TaxonomyRef = &.{},
    instructions: []const []const u8 = &.{},
    category: ?[]const u8 = null,
    movementPatterns: []const []const u8 = &.{},
    knowledge: ?caudex.canonical.ExerciseKnowledge = null,
    source: SourceProvenance,
};

pub const Document = struct {
    schemaVersion: u32,
    catalogId: []const u8,
    version: []const u8,
    fingerprint: []const u8,
    baseVersion: []const u8,
    baseFingerprint: []const u8,
    enrichmentVersion: []const u8,
    enrichmentFingerprint: []const u8,
    enrichmentRecordCount: usize,
    recordCount: usize,
    mediaIncluded: bool,
    records: []const Record,
};

pub const DecodeError = caudex.canonical_json.DecodeError || error{
    RecordLimitExceeded,
    RecordCountMismatch,
};

pub fn load(allocator: std.mem.Allocator) DecodeError!std.json.Parsed(Document) {
    const parsed = try caudex.canonical_json.decodeValue(Document, allocator, embedded_json, .{
        .max_input_bytes = 2 * 1024 * 1024,
        .max_nesting = 16,
        .max_collection_items = 64 * 1024,
        .max_string_bytes = 16 * 1024,
    });
    errdefer parsed.deinit();
    if (parsed.value.schemaVersion != schema_version) return error.UnsupportedVersion;
    if (parsed.value.records.len > max_records) return error.RecordLimitExceeded;
    if (parsed.value.recordCount != parsed.value.records.len) return error.RecordCountMismatch;
    return parsed;
}

pub const SearchQuery = struct {
    text: []const u8 = "",
    equipment_id: ?[]const u8 = null,
    muscle_id: ?[]const u8 = null,
    difficulty: ?[]const u8 = null,
    category: ?[]const u8 = null,
    force: ?[]const u8 = null,
    mechanic: ?[]const u8 = null,
    movement_pattern: ?[]const u8 = null,
    family_id: ?[]const u8 = null,
    loading_mode: ?[]const u8 = null,
    structural_type: ?[]const u8 = null,
    tracking_metric: ?[]const u8 = null,
    progression_capability: ?[]const u8 = null,
    relationship_kind: ?[]const u8 = null,
    related_exercise_id: ?[]const u8 = null,
    max_results: usize = 50,
};

pub const SearchError = error{ ResultLimitExceeded, OutputTooSmall };

/// Writes record pointers in the catalog's deterministic ID order.
pub fn search(records: []const Record, query: SearchQuery, output: []*const Record) SearchError![]const *const Record {
    if (query.max_results > max_search_results) return error.ResultLimitExceeded;
    if (output.len < query.max_results) return error.OutputTooSmall;
    var count: usize = 0;
    for (records) |*record| {
        if (!matches(record.*, query)) continue;
        output[count] = record;
        count += 1;
        if (count == query.max_results) break;
    }
    return output[0..count];
}

fn matches(record: Record, query: SearchQuery) bool {
    if (query.text.len != 0 and !containsIgnoreCase(record.name, query.text) and
        !containsIgnoreCase(record.id, query.text) and
        !containsAnyIgnoreCase(record.aliases, query.text)) return false;
    if (query.equipment_id) |id| {
        const equipment = record.equipment orelse return false;
        if (!std.mem.eql(u8, equipment.normalizedId, id)) return false;
    }
    if (query.muscle_id) |id| {
        if (!hasTaxonomy(record.primaryMuscles, id) and !hasTaxonomy(record.secondaryMuscles, id)) return false;
    }
    if (query.difficulty) |value| {
        const difficulty = record.difficulty orelse return false;
        if (!std.mem.eql(u8, difficulty, value)) return false;
    }
    if (query.category) |value| {
        const category = record.category orelse return false;
        if (!std.mem.eql(u8, category, value)) return false;
    }
    if (query.force) |value| {
        const force = record.force orelse return false;
        if (!std.mem.eql(u8, force, value)) return false;
    }
    if (query.mechanic) |value| {
        const mechanic = record.mechanic orelse return false;
        if (!std.mem.eql(u8, mechanic, value)) return false;
    }
    if (query.movement_pattern) |value| if (!hasString(record.movementPatterns, value)) return false;
    if (query.family_id != null or query.loading_mode != null or query.structural_type != null or query.tracking_metric != null or query.progression_capability != null) {
        const knowledge = record.knowledge orelse return false;
        if (query.family_id) |value| if (!optionalStringEquals(knowledge.familyId, value)) return false;
        if (query.loading_mode) |value| if (!enumEquals(knowledge.loadingMode, value)) return false;
        if (query.structural_type) |value| if (!enumEquals(knowledge.structuralType, value)) return false;
        if (query.tracking_metric) |value| if (!hasTrackingMetric(knowledge, value)) return false;
        if (query.progression_capability) |value| if (!supportsProgressionCapability(record, value)) return false;
    }
    if (query.relationship_kind != null or query.related_exercise_id != null) {
        if (!hasRelationship(record, query.relationship_kind, query.related_exercise_id)) return false;
    }
    return true;
}

fn containsAnyIgnoreCase(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| if (containsIgnoreCase(value, needle)) return true;
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |index| {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn hasTaxonomy(values: []const TaxonomyRef, id: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value.normalizedId, id)) return true;
    return false;
}

fn hasString(values: []const []const u8, value: []const u8) bool {
    for (values) |candidate| if (std.mem.eql(u8, candidate, value)) return true;
    return false;
}

fn optionalStringEquals(value: ?[]const u8, expected: []const u8) bool {
    return if (value) |actual| std.mem.eql(u8, actual, expected) else false;
}

fn enumEquals(value: anytype, expected: []const u8) bool {
    if (value) |actual| return std.mem.eql(u8, @tagName(actual), expected);
    return false;
}

fn hasTrackingMetric(knowledge: caudex.canonical.ExerciseKnowledge, metric_code: []const u8) bool {
    for (knowledge.trackingDimensions) |dimension| if (std.mem.eql(u8, dimension.metricCode, metric_code)) return true;
    return false;
}

/// Returns the structured, curated capability projection when it exists.
pub fn projectKnowledge(record: Record) ?caudex.canonical.ExerciseKnowledge {
    return record.knowledge;
}

/// Returns whether the named known progression capability is explicitly true.
pub fn supportsProgressionCapability(record: Record, capability_id: []const u8) bool {
    const knowledge = record.knowledge orelse return false;
    const capabilities = knowledge.progressionCapabilities orelse return false;
    if (std.mem.eql(u8, capability_id, "externalLoad")) return capabilities.externalLoad orelse false;
    if (std.mem.eql(u8, capability_id, "repetitions")) return capabilities.repetitions orelse false;
    if (std.mem.eql(u8, capability_id, "percentageOneRepMax")) return capabilities.percentageOneRepMax orelse false;
    if (std.mem.eql(u8, capability_id, "effortTarget")) return capabilities.effortTarget orelse false;
    if (std.mem.eql(u8, capability_id, "amrap")) return capabilities.amrap orelse false;
    if (std.mem.eql(u8, capability_id, "failureTraining")) return capabilities.failureTraining orelse false;
    if (std.mem.eql(u8, capability_id, "duration")) return capabilities.duration orelse false;
    if (std.mem.eql(u8, capability_id, "distance")) return capabilities.distance orelse false;
    if (std.mem.eql(u8, capability_id, "assistanceReduction")) return capabilities.assistanceReduction orelse false;
    return false;
}

fn hasRelationship(record: Record, kind: ?[]const u8, exercise_id: ?[]const u8) bool {
    const knowledge = record.knowledge orelse return false;
    const relationships = knowledge.relationships;
    if (kind) |value| {
        if (std.mem.eql(u8, value, "variant")) return relationshipListMatches(relationships.variantIds, exercise_id) or optionalStringEquals(relationships.variantOf, exercise_id orelse "");
        if (std.mem.eql(u8, value, "substitute")) return relationshipListMatches(relationships.substituteIds, exercise_id);
        if (std.mem.eql(u8, value, "similar")) return relationshipListMatches(relationships.similarExerciseIds, exercise_id);
        if (std.mem.eql(u8, value, "shared_progression_state")) return relationshipListMatches(relationships.sharedProgressionStateIds, exercise_id);
        return false;
    }
    return relationshipListMatches(relationships.variantIds, exercise_id) or
        optionalStringEquals(relationships.variantOf, exercise_id orelse "") or
        relationshipListMatches(relationships.substituteIds, exercise_id) or
        relationshipListMatches(relationships.similarExerciseIds, exercise_id) or
        relationshipListMatches(relationships.sharedProgressionStateIds, exercise_id);
}

fn relationshipListMatches(ids: []const []const u8, exercise_id: ?[]const u8) bool {
    if (exercise_id) |target| return hasString(ids, target);
    return ids.len != 0;
}

pub const ProjectionStorage = struct {
    equipment_ids: [][]const u8,
    muscle_contributions: []caudex.canonical.MuscleContribution,
};

pub const ProjectionError = error{ EquipmentBufferTooSmall, MuscleBufferTooSmall };

/// Projects richer catalog data into the storage-agnostic core exercise type.
/// Source category/force/mechanic are not mislabeled as movement patterns.
pub fn project(record: Record, storage: ProjectionStorage) ProjectionError!caudex.canonical.Exercise {
    const equipment_count: usize = if (record.equipment == null) 0 else 1;
    if (storage.equipment_ids.len < equipment_count) return error.EquipmentBufferTooSmall;
    if (record.equipment) |equipment| storage.equipment_ids[0] = equipment.normalizedId;
    const muscle_count = std.math.add(usize, record.primaryMuscles.len, record.secondaryMuscles.len) catch return error.MuscleBufferTooSmall;
    if (storage.muscle_contributions.len < muscle_count) return error.MuscleBufferTooSmall;
    var index: usize = 0;
    for (record.primaryMuscles) |muscle| {
        storage.muscle_contributions[index] = .{ .muscleId = muscle.normalizedId, .role = .primary };
        index += 1;
    }
    for (record.secondaryMuscles) |muscle| {
        storage.muscle_contributions[index] = .{ .muscleId = muscle.normalizedId, .role = .secondary };
        index += 1;
    }
    return .{
        .id = record.id,
        .name = record.name,
        .equipmentIds = storage.equipment_ids[0..equipment_count],
        .movementTags = record.movementPatterns,
        .unilateral = if (record.knowledge) |knowledge| switch (knowledge.laterality orelse .unknown) {
            .unilateral => true,
            .bilateral => false,
            else => null,
        } else null,
        .muscleContributions = storage.muscle_contributions[0..muscle_count],
        .aliases = record.aliases,
        .knowledge = record.knowledge,
    };
}

pub const MergeError = error{ OutputTooSmall, DuplicateOverrideId };

/// Host records replace matching first-party IDs or extend the catalog. The
/// result is sorted by stable ID and borrows every input record.
pub fn merge(base: []const Record, overrides: []const Record, output: []Record) MergeError![]const Record {
    for (overrides, 0..) |candidate, index| {
        for (overrides[0..index]) |prior| if (std.mem.eql(u8, prior.id, candidate.id)) return error.DuplicateOverrideId;
    }
    const required = std.math.add(usize, base.len, overrides.len) catch return error.OutputTooSmall;
    if (output.len < required) return error.OutputTooSmall;
    var count: usize = 0;
    for (base) |record| {
        for (overrides) |override| {
            if (std.mem.eql(u8, override.id, record.id)) break;
        } else {
            output[count] = record;
            count += 1;
        }
    }
    for (overrides) |override| {
        output[count] = override;
        count += 1;
    }
    std.mem.sort(Record, output[0..count], {}, struct {
        fn lessThan(_: void, left: Record, right: Record) bool {
            return std.mem.order(u8, left.id, right.id) == .lt;
        }
    }.lessThan);
    return output[0..count];
}
