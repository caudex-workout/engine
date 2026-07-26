const std = @import("std");
const canonical = @import("canonical.zig");
const primitives = @import("primitives.zig");

pub const Limits = struct {
    max_input_bytes: usize = 1024 * 1024,
    max_nesting: usize = 32,
    max_collection_items: usize = 4096,
    max_string_bytes: usize = 64 * 1024,
};

pub const DecodeError = error{
    InputTooLarge,
    InvalidUtf8,
    MalformedJson,
    NestingLimitExceeded,
    CollectionLimitExceeded,
    ValueTooLarge,
    UnsupportedVersion,
    InvalidDecimal,
    OutOfMemory,
};

pub const EncodeError = error{
    OutputLimitReached,
};

pub fn decodeRecommendationRequest(
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
) DecodeError!std.json.Parsed(canonical.RecommendationRequest) {
    const parsed = try decode(
        canonical.RecommendationRequest,
        allocator,
        input,
        limits,
    );
    if (parsed.value.schemaVersion != 1) {
        parsed.deinit();
        return error.UnsupportedVersion;
    }
    return parsed;
}

pub fn decodeEvaluationRequest(
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
) DecodeError!std.json.Parsed(canonical.EvaluationRequest) {
    const parsed = try decode(
        canonical.EvaluationRequest,
        allocator,
        input,
        limits,
    );
    if (parsed.value.schemaVersion != 1) {
        parsed.deinit();
        return error.UnsupportedVersion;
    }
    return parsed;
}

pub fn decodeRecommendationResult(
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
) DecodeError!std.json.Parsed(canonical.RecommendationResult) {
    const parsed = try decode(
        canonical.RecommendationResult,
        allocator,
        input,
        limits,
    );
    if (parsed.value.metadata.schemaVersion != 1) {
        parsed.deinit();
        return error.UnsupportedVersion;
    }
    return parsed;
}

pub fn decodeEvaluationResult(
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
) DecodeError!std.json.Parsed(canonical.EvaluationResult) {
    const parsed = try decode(
        canonical.EvaluationResult,
        allocator,
        input,
        limits,
    );
    if (parsed.value.metadata.schemaVersion != 1) {
        parsed.deinit();
        return error.UnsupportedVersion;
    }
    return parsed;
}

pub fn encode(value: anytype, out: []u8) EncodeError![]const u8 {
    var writer: std.Io.Writer = .fixed(out);
    std.json.Stringify.value(
        value,
        .{ .emit_null_optional_fields = false },
        &writer,
    ) catch return error.OutputLimitReached;
    return writer.buffered();
}

fn decode(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: []const u8,
    limits: Limits,
) DecodeError!std.json.Parsed(T) {
    try preflight(input, limits);

    const dynamic = std.json.parseFromSlice(
        std.json.Value,
        allocator,
        input,
        .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
            .max_value_len = limits.max_string_bytes,
            .allocate = .alloc_always,
            .parse_numbers = false,
        },
    ) catch |err| return mapParseError(err);
    defer dynamic.deinit();
    validateDecimalFields(dynamic.value) catch return error.InvalidDecimal;

    return std.json.parseFromSlice(
        T,
        allocator,
        input,
        .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
            .max_value_len = limits.max_string_bytes,
            .allocate = .alloc_always,
        },
    ) catch |err| return mapParseError(err);
}

fn mapParseError(err: anyerror) DecodeError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ValueTooLong => error.ValueTooLarge,
        else => error.MalformedJson,
    };
}

fn preflight(input: []const u8, limits: Limits) DecodeError!void {
    if (input.len > limits.max_input_bytes) return error.InputTooLarge;
    if (!std.unicode.utf8ValidateSlice(input)) return error.InvalidUtf8;

    var depth: usize = 0;
    var structural_items: usize = 0;
    var string_bytes: usize = 0;
    var in_string = false;
    var escaped = false;
    for (input) |byte| {
        if (in_string) {
            if (escaped) {
                escaped = false;
                string_bytes += 1;
                continue;
            }
            if (byte == '\\') {
                escaped = true;
                string_bytes += 1;
                continue;
            }
            if (byte == '"') {
                in_string = false;
                continue;
            }
            string_bytes += 1;
            if (string_bytes > limits.max_string_bytes) {
                return error.ValueTooLarge;
            }
            continue;
        }
        switch (byte) {
            '"' => {
                in_string = true;
                string_bytes = 0;
            },
            '[', '{' => {
                depth += 1;
                structural_items += 1;
                if (depth > limits.max_nesting) {
                    return error.NestingLimitExceeded;
                }
            },
            ']', '}' => {
                if (depth == 0) return error.MalformedJson;
                depth -= 1;
            },
            ',' => structural_items += 1,
            else => {},
        }
        if (structural_items > limits.max_collection_items) {
            return error.CollectionLimitExceeded;
        }
    }
    if (in_string or depth != 0) return error.MalformedJson;
}

fn validateDecimalFields(value: std.json.Value) error{InvalidDecimal}!void {
    switch (value) {
        .array => |items| for (items.items) |item| try validateDecimalFields(item),
        .object => |object| {
            if (object.get("amount") != null and object.get("unit") != null) {
                try validateDecimalValue(object.get("amount").?);
            }
            if (object.get("muscleId") != null and object.get("weight") != null) {
                try validateDecimalValue(object.get("weight").?);
            }
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (isDecimalField(entry.key_ptr.*)) {
                    try validateDecimalValue(entry.value_ptr.*);
                }
                try validateDecimalFields(entry.value_ptr.*);
            }
        },
        else => {},
    }
}

fn validateDecimalValue(value: std.json.Value) error{InvalidDecimal}!void {
    const text = switch (value) {
        .string => |text| text,
        else => return error.InvalidDecimal,
    };
    _ = primitives.Decimal.parse(text) catch return error.InvalidDecimal;
}

fn isDecimalField(name: []const u8) bool {
    return std.mem.eql(u8, name, "targetRpe") or
        std.mem.eql(u8, name, "percentage") or
        std.mem.eql(u8, name, "tolerance") or
        std.mem.eql(u8, name, "estimateAdjustmentPercentage");
}

test "request and result fixtures round trip deterministically" {
    inline for (.{
        .{
            canonical.RecommendationRequest,
            decodeRecommendationRequest,
            @embedFile("../fixtures/requests/recommendation.json"),
        },
        .{
            canonical.EvaluationRequest,
            decodeEvaluationRequest,
            @embedFile("../fixtures/requests/evaluation.json"),
        },
        .{
            canonical.RecommendationResult,
            decodeRecommendationResult,
            @embedFile("../fixtures/results/recommendation-no-history.json"),
        },
    }) |fixture| {
        const parsed = try fixture[1](std.testing.allocator, fixture[2], .{});
        defer parsed.deinit();
        var first_storage: [16 * 1024]u8 = undefined;
        var second_storage: [16 * 1024]u8 = undefined;
        const first = try encode(parsed.value, &first_storage);
        const second = try encode(parsed.value, &second_storage);
        try std.testing.expectEqualStrings(first, second);

        const reparsed = try fixture[1](std.testing.allocator, first, .{});
        defer reparsed.deinit();
    }
}

test "evaluation result round trips" {
    const input =
        \\{"ok":true,"evaluation":{"outcome":"held","exercises":[]},"explanations":[],"warnings":[],"issues":[],"metadata":{"engineVersion":"0.1.0-dev","schemaVersion":1,"methodology":{"id":"caudex.rpe-top-set-backoff","version":"0.1.0","configVersion":1},"inputFingerprint":"input","resultFingerprint":"result"}}
    ;
    const parsed = try decodeEvaluationResult(std.testing.allocator, input, .{});
    defer parsed.deinit();
    var storage: [2048]u8 = undefined;
    const encoded = try encode(parsed.value, &storage);
    const reparsed = try decodeEvaluationResult(std.testing.allocator, encoded, .{});
    defer reparsed.deinit();
    try std.testing.expectEqualStrings("held", reparsed.value.evaluation.?.outcome);
}

test "canonical result fixture has stable encoded bytes" {
    const fixture = @embedFile("../fixtures/results/recommendation-no-history.json");
    const parsed = try decodeRecommendationResult(std.testing.allocator, fixture, .{});
    defer parsed.deinit();
    var storage: [4096]u8 = undefined;
    const encoded = try encode(parsed.value, &storage);
    try std.testing.expectEqualStrings(fixture, encoded);
}

test "invalid UTF-8 malformed JSON and unknown fields fail safely" {
    const invalid_utf8 = [_]u8{ '{', '"', 0xff, '"', ':', '1', '}' };
    try std.testing.expectError(
        error.InvalidUtf8,
        decodeRecommendationRequest(std.testing.allocator, &invalid_utf8, .{}),
    );
    try std.testing.expectError(
        error.MalformedJson,
        decodeRecommendationRequest(std.testing.allocator, "{\"schemaVersion\":", .{}),
    );
    const unknown =
        \\{"schemaVersion":1,"asOf":"2026-07-25T15:00:00Z","methodology":{"id":"x","configVersion":1,"config":{}},"catalog":[],"unknown":true}
    ;
    try std.testing.expectError(
        error.MalformedJson,
        decodeRecommendationRequest(std.testing.allocator, unknown, .{}),
    );
    const duplicate =
        \\{"schemaVersion":1,"schemaVersion":1,"asOf":"2026-07-25T15:00:00Z","methodology":{"id":"x","configVersion":1,"config":{}},"catalog":[]}
    ;
    try std.testing.expectError(
        error.MalformedJson,
        decodeRecommendationRequest(std.testing.allocator, duplicate, .{}),
    );
}

test "limits and unsupported versions are explicit" {
    try std.testing.expectError(
        error.InputTooLarge,
        decodeRecommendationRequest(
            std.testing.allocator,
            @embedFile("../fixtures/requests/recommendation.json"),
            .{ .max_input_bytes = 16 },
        ),
    );
    try std.testing.expectError(
        error.NestingLimitExceeded,
        decodeRecommendationRequest(
            std.testing.allocator,
            "{\"schemaVersion\":1,\"asOf\":\"x\",\"methodology\":{\"id\":\"x\",\"configVersion\":1,\"config\":{}},\"catalog\":[]}",
            .{ .max_nesting = 1 },
        ),
    );
    try std.testing.expectError(
        error.CollectionLimitExceeded,
        decodeRecommendationRequest(
            std.testing.allocator,
            @embedFile("../fixtures/requests/recommendation.json"),
            .{ .max_collection_items = 2 },
        ),
    );
    const unsupported =
        \\{"schemaVersion":2,"asOf":"2026-07-25T15:00:00Z","methodology":{"id":"x","configVersion":1,"config":{}},"catalog":[]}
    ;
    try std.testing.expectError(
        error.UnsupportedVersion,
        decodeRecommendationRequest(std.testing.allocator, unsupported, .{}),
    );
}

test "decimal-bearing fields require canonical decimal strings" {
    const number =
        \\{"schemaVersion":1,"asOf":"2026-07-25T15:00:00Z","methodology":{"id":"x","configVersion":1,"config":{"initialLoad":{"amount":45,"unit":"lb"}}},"catalog":[]}
    ;
    const noncanonical =
        \\{"schemaVersion":1,"asOf":"2026-07-25T15:00:00Z","methodology":{"id":"x","configVersion":1,"config":{"initialLoad":{"amount":"045","unit":"lb"}}},"catalog":[]}
    ;
    try std.testing.expectError(
        error.InvalidDecimal,
        decodeRecommendationRequest(std.testing.allocator, number, .{}),
    );
    try std.testing.expectError(
        error.InvalidDecimal,
        decodeRecommendationRequest(std.testing.allocator, noncanonical, .{}),
    );
}
