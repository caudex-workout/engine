//! Optional first-party exercise catalog generated from a pinned textual
//! free-exercise-db snapshot. The programming core does not import this module.

const std = @import("std");
const caudex = @import("caudex");

pub const schema_version: u32 = 1;
pub const max_records: usize = 2000;
pub const max_search_results: usize = 256;
pub const embedded_json = @embedFile("generated/catalog.json");

pub const TaxonomyRef = struct {
    sourceValue: []const u8,
    id: []const u8,
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
    source: SourceProvenance,
};

pub const Document = struct {
    schemaVersion: u32,
    catalogId: []const u8,
    version: []const u8,
    fingerprint: []const u8,
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
        if (!std.mem.eql(u8, equipment.id, id)) return false;
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
    for (values) |value| if (std.mem.eql(u8, value.id, id)) return true;
    return false;
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
    if (record.equipment) |equipment| storage.equipment_ids[0] = equipment.id;
    const muscle_count = std.math.add(usize, record.primaryMuscles.len, record.secondaryMuscles.len) catch return error.MuscleBufferTooSmall;
    if (storage.muscle_contributions.len < muscle_count) return error.MuscleBufferTooSmall;
    var index: usize = 0;
    for (record.primaryMuscles) |muscle| {
        storage.muscle_contributions[index] = .{ .muscleId = muscle.id, .role = .primary };
        index += 1;
    }
    for (record.secondaryMuscles) |muscle| {
        storage.muscle_contributions[index] = .{ .muscleId = muscle.id, .role = .secondary };
        index += 1;
    }
    return .{
        .id = record.id,
        .name = record.name,
        .equipmentIds = storage.equipment_ids[0..equipment_count],
        .movementTags = record.movementPatterns,
        .muscleContributions = storage.muscle_contributions[0..muscle_count],
        .aliases = record.aliases,
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
