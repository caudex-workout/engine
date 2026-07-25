const std = @import("std");

/// A validated, host-defined identifier that borrows its input bytes.
pub const Id = struct {
    bytes: []const u8,

    pub const ParseError = error{
        Empty,
        TooLong,
        InvalidUtf8,
    };

    /// Validates UTF-8 and the canonical boundary length without allocating.
    pub fn parse(bytes: []const u8) ParseError!Id {
        if (bytes.len == 0) return error.Empty;
        if (bytes.len > 200) return error.TooLong;
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        return .{ .bytes = bytes };
    }

    /// Copies the identifier into caller-owned storage.
    pub fn format(self: Id, out: []u8) error{NoSpaceLeft}![]const u8 {
        if (out.len < self.bytes.len) return error.NoSpaceLeft;
        @memcpy(out[0..self.bytes.len], self.bytes);
        return out[0..self.bytes.len];
    }
};

/// An exact base-10 value represented by a signed mantissa and decimal scale.
pub const Decimal = struct {
    mantissa: i64,
    scale: u8,

    pub const max_scale: u8 = 18;

    pub const ParseError = error{
        Empty,
        InvalidCharacter,
        NonCanonical,
        ScaleOverflow,
        Overflow,
    };

    pub const ArithmeticError = error{
        ScaleOverflow,
        Overflow,
    };

    /// Parses a canonical decimal string without floating-point conversion.
    pub fn parse(text: []const u8) ParseError!Decimal {
        if (text.len == 0) return error.Empty;

        var index: usize = 0;
        const negative = text[0] == '-';
        if (negative) {
            index = 1;
            if (index == text.len) return error.InvalidCharacter;
        } else if (text[0] == '+') {
            return error.NonCanonical;
        }

        const integer_start = index;
        while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {}
        if (index == integer_start) return error.InvalidCharacter;
        if (index - integer_start > 1 and text[integer_start] == '0') {
            return error.NonCanonical;
        }

        var scale: u8 = 0;
        if (index < text.len) {
            if (text[index] != '.') return error.InvalidCharacter;
            index += 1;
            const fraction_start = index;
            while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {}
            if (index == fraction_start or index != text.len) {
                return error.InvalidCharacter;
            }
            const fraction_len = index - fraction_start;
            if (fraction_len > max_scale) return error.ScaleOverflow;
            scale = @intCast(fraction_len);
        }

        var magnitude: i128 = 0;
        for (text) |byte| {
            if (byte == '-' or byte == '.') continue;
            const multiplied, const multiply_overflow = @mulWithOverflow(magnitude, 10);
            if (multiply_overflow != 0) return error.Overflow;
            const added, const add_overflow = @addWithOverflow(
                multiplied,
                @as(i128, byte - '0'),
            );
            if (add_overflow != 0) return error.Overflow;
            magnitude = added;
        }

        if (negative) magnitude = -magnitude;
        if (magnitude < std.math.minInt(i64) or magnitude > std.math.maxInt(i64)) {
            return error.Overflow;
        }

        return .{
            .mantissa = @intCast(magnitude),
            .scale = scale,
        };
    }

    /// Formats into caller-owned storage while preserving the stored scale.
    pub fn format(self: Decimal, out: []u8) error{NoSpaceLeft}![]const u8 {
        if (self.scale > max_scale) return error.NoSpaceLeft;

        const negative = self.mantissa < 0;
        const magnitude: u64 = @intCast(if (negative)
            -@as(i128, self.mantissa)
        else
            self.mantissa);
        var digits_buffer: [20]u8 = undefined;
        const digits = std.fmt.bufPrint(&digits_buffer, "{d}", .{magnitude}) catch
            return error.NoSpaceLeft;

        if (self.scale == 0) {
            const required = digits.len + @intFromBool(negative);
            if (out.len < required) return error.NoSpaceLeft;
            var offset: usize = 0;
            if (negative) {
                out[0] = '-';
                offset = 1;
            }
            @memcpy(out[offset..required], digits);
            return out[0..required];
        }

        const scale: usize = self.scale;
        const integer_digits = if (digits.len > scale) digits.len - scale else 1;
        const leading_fraction_zeros = if (digits.len < scale) scale - digits.len else 0;
        const fraction_digits = @min(digits.len, scale);
        const required = @intFromBool(negative) +
            integer_digits +
            1 +
            leading_fraction_zeros +
            fraction_digits;
        if (out.len < required) return error.NoSpaceLeft;

        var offset: usize = 0;
        if (negative) {
            out[offset] = '-';
            offset += 1;
        }
        if (digits.len > scale) {
            const split = digits.len - scale;
            @memcpy(out[offset .. offset + split], digits[0..split]);
            offset += split;
        } else {
            out[offset] = '0';
            offset += 1;
        }
        out[offset] = '.';
        offset += 1;
        @memset(out[offset .. offset + leading_fraction_zeros], '0');
        offset += leading_fraction_zeros;
        const fraction = if (digits.len > scale) digits[digits.len - scale ..] else digits;
        @memcpy(out[offset .. offset + fraction.len], fraction);
        offset += fraction.len;
        return out[0..offset];
    }

    pub fn add(left: Decimal, right: Decimal) ArithmeticError!Decimal {
        const result_scale = @max(left.scale, right.scale);
        const left_value = try scaledMantissa(left, result_scale);
        const right_value = try scaledMantissa(right, result_scale);
        const result, const overflow = @addWithOverflow(left_value, right_value);
        if (overflow != 0) return error.Overflow;
        return fromIntermediate(result, result_scale);
    }

    pub fn subtract(left: Decimal, right: Decimal) ArithmeticError!Decimal {
        const result_scale = @max(left.scale, right.scale);
        const left_value = try scaledMantissa(left, result_scale);
        const right_value = try scaledMantissa(right, result_scale);
        const result, const overflow = @subWithOverflow(left_value, right_value);
        if (overflow != 0) return error.Overflow;
        return fromIntermediate(result, result_scale);
    }

    pub fn multiply(left: Decimal, right: Decimal) ArithmeticError!Decimal {
        const result_scale, const scale_overflow = @addWithOverflow(left.scale, right.scale);
        if (scale_overflow != 0 or result_scale > max_scale) {
            return error.ScaleOverflow;
        }
        const result, const overflow = @mulWithOverflow(
            @as(i128, left.mantissa),
            @as(i128, right.mantissa),
        );
        if (overflow != 0) return error.Overflow;
        return fromIntermediate(result, result_scale);
    }

    fn scaledMantissa(value: Decimal, target_scale: u8) ArithmeticError!i128 {
        if (target_scale < value.scale or target_scale > max_scale) {
            return error.ScaleOverflow;
        }
        var result: i128 = value.mantissa;
        var remaining = target_scale - value.scale;
        while (remaining > 0) : (remaining -= 1) {
            const next, const overflow = @mulWithOverflow(result, 10);
            if (overflow != 0) return error.Overflow;
            result = next;
        }
        return result;
    }

    fn fromIntermediate(value: i128, scale: u8) ArithmeticError!Decimal {
        if (value < std.math.minInt(i64) or value > std.math.maxInt(i64)) {
            return error.Overflow;
        }
        return .{ .mantissa = @intCast(value), .scale = scale };
    }
};

/// The methodology-neutral dimension of a measurement unit.
pub const Dimension = enum {
    count,
    mass,
    duration,
    distance,
    rpe,
    rir,
    resistance_level,
    percentage,
};

/// Built-in v0 unit codes. Host-defined taxonomies remain separate from units.
pub const Unit = enum {
    count,
    g,
    kg,
    lb,
    s,
    min,
    m,
    km,
    mi,
    rpe,
    rir,
    level,
    percent,

    pub fn parse(code_text: []const u8) error{UnknownUnit}!Unit {
        inline for (std.meta.fields(Unit)) |field| {
            if (std.mem.eql(u8, code_text, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return error.UnknownUnit;
    }

    pub fn code(self: Unit) []const u8 {
        return @tagName(self);
    }

    pub fn dimension(self: Unit) Dimension {
        return switch (self) {
            .count => .count,
            .g, .kg, .lb => .mass,
            .s, .min => .duration,
            .m, .km, .mi => .distance,
            .rpe => .rpe,
            .rir => .rir,
            .level => .resistance_level,
            .percent => .percentage,
        };
    }
};

/// An exact decimal paired with an explicit unit code.
pub const Measurement = struct {
    value: Decimal,
    unit: Unit,

    pub fn requireDimension(
        self: Measurement,
        expected: Dimension,
    ) error{IncompatibleDimension}!void {
        if (self.unit.dimension() != expected) return error.IncompatibleDimension;
    }
};

/// A validated RFC 3339 timestamp that borrows its input bytes.
///
/// Timestamps are supplied explicitly by the host; this type never reads a clock.
pub const Timestamp = struct {
    bytes: []const u8,

    pub fn parse(bytes: []const u8) error{InvalidTimestamp}!Timestamp {
        if (!isValidRfc3339(bytes)) return error.InvalidTimestamp;
        return .{ .bytes = bytes };
    }

    pub fn format(self: Timestamp, out: []u8) error{NoSpaceLeft}![]const u8 {
        if (out.len < self.bytes.len) return error.NoSpaceLeft;
        @memcpy(out[0..self.bytes.len], self.bytes);
        return out[0..self.bytes.len];
    }

    fn isValidRfc3339(bytes: []const u8) bool {
        if (bytes.len < 20) return false;
        if (bytes[4] != '-' or bytes[7] != '-' or bytes[10] != 'T' or
            bytes[13] != ':' or bytes[16] != ':')
        {
            return false;
        }
        const year = parseFixedDigits(bytes[0..4]) orelse return false;
        const month = parseFixedDigits(bytes[5..7]) orelse return false;
        const day = parseFixedDigits(bytes[8..10]) orelse return false;
        const hour = parseFixedDigits(bytes[11..13]) orelse return false;
        const minute = parseFixedDigits(bytes[14..16]) orelse return false;
        const second = parseFixedDigits(bytes[17..19]) orelse return false;
        if (month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59) {
            return false;
        }
        if (day < 1 or day > daysInMonth(year, month)) return false;

        var index: usize = 19;
        if (index < bytes.len and bytes[index] == '.') {
            index += 1;
            const fraction_start = index;
            while (index < bytes.len and std.ascii.isDigit(bytes[index])) : (index += 1) {}
            if (index == fraction_start) return false;
        }
        if (index >= bytes.len) return false;
        if (bytes[index] == 'Z') return index + 1 == bytes.len;
        if (bytes[index] != '+' and bytes[index] != '-') return false;
        if (index + 6 != bytes.len or bytes[index + 3] != ':') return false;
        const offset_hour = parseFixedDigits(bytes[index + 1 .. index + 3]) orelse return false;
        const offset_minute = parseFixedDigits(bytes[index + 4 .. index + 6]) orelse return false;
        return offset_hour <= 23 and offset_minute <= 59;
    }

    fn parseFixedDigits(bytes: []const u8) ?u16 {
        var value: u16 = 0;
        for (bytes) |byte| {
            if (!std.ascii.isDigit(byte)) return null;
            value = value * 10 + (byte - '0');
        }
        return value;
    }

    fn daysInMonth(year: u16, month: u16) u16 {
        return switch (month) {
            1, 3, 5, 7, 8, 10, 12 => 31,
            4, 6, 9, 11 => 30,
            2 => if (isLeapYear(year)) 29 else 28,
            else => 0,
        };
    }

    fn isLeapYear(year: u16) bool {
        return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
    }
};

test "id parsing and formatting round-trip" {
    const id = try Id.parse("incline-dumbbell-press");
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings(
        "incline-dumbbell-press",
        try id.format(&buffer),
    );
}

test "decimal parsing and formatting preserve scale" {
    const cases = .{
        .{ "70", Decimal{ .mantissa = 70, .scale = 0 } },
        .{ "2.50", Decimal{ .mantissa = 250, .scale = 2 } },
        .{ "-0.125", Decimal{ .mantissa = -125, .scale = 3 } },
        .{ "0.005", Decimal{ .mantissa = 5, .scale = 3 } },
    };
    inline for (cases) |case| {
        const parsed = try Decimal.parse(case[0]);
        try std.testing.expectEqual(case[1], parsed);
        var buffer: [32]u8 = undefined;
        try std.testing.expectEqualStrings(case[0], try parsed.format(&buffer));
    }
}

test "decimal arithmetic is checked and exact" {
    const left = try Decimal.parse("1.25");
    const right = try Decimal.parse("2.5");
    var exact_buffer: [4]u8 = undefined;
    try std.testing.expectEqualStrings("1.25", try left.format(&exact_buffer));
    try std.testing.expectEqual(
        Decimal{ .mantissa = 375, .scale = 2 },
        try Decimal.add(left, right),
    );
    try std.testing.expectEqual(
        Decimal{ .mantissa = 3125, .scale = 3 },
        try Decimal.multiply(left, right),
    );
    try std.testing.expectError(
        error.Overflow,
        Decimal.add(
            .{ .mantissa = std.math.maxInt(i64), .scale = 0 },
            .{ .mantissa = 1, .scale = 0 },
        ),
    );
    try std.testing.expectError(
        error.Overflow,
        Decimal.multiply(
            .{ .mantissa = std.math.maxInt(i64), .scale = 0 },
            .{ .mantissa = 2, .scale = 0 },
        ),
    );
    try std.testing.expectError(
        error.ScaleOverflow,
        Decimal.multiply(
            .{ .mantissa = 1, .scale = Decimal.max_scale },
            .{ .mantissa = 1, .scale = 1 },
        ),
    );
}

test "units validate dimensions" {
    const load = Measurement{
        .value = try Decimal.parse("72.5"),
        .unit = try Unit.parse("kg"),
    };
    try load.requireDimension(.mass);
    try std.testing.expectError(
        error.IncompatibleDimension,
        load.requireDimension(.duration),
    );
    try std.testing.expectEqualStrings("kg", load.unit.code());
}

test "timestamp is explicit and round-trips" {
    const timestamp = try Timestamp.parse("2026-07-25T14:00:00.125-04:00");
    var buffer: [40]u8 = undefined;
    try std.testing.expectEqualStrings(
        "2026-07-25T14:00:00.125-04:00",
        try timestamp.format(&buffer),
    );
    try std.testing.expectError(
        error.InvalidTimestamp,
        Timestamp.parse("2025-02-29T14:00:00Z"),
    );
}
