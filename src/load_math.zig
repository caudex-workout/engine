const std = @import("std");
const canonical = @import("canonical.zig");
const primitives = @import("primitives.zig");

pub const RoundingMode = enum {
    nearest,
    up,
    down,
};

pub const Rounding = struct {
    mode: RoundingMode,
    quantum: canonical.Measurement,
};

pub const Error = error{
    InvalidConfig,
    IncompatibleUnit,
    Overflow,
};

pub fn parseMeasurement(
    measurement: canonical.Measurement,
) (primitives.Decimal.ParseError || error{UnknownUnit})!primitives.Measurement {
    return .{
        .value = try primitives.Decimal.parse(measurement.amount),
        .unit = try primitives.Unit.parse(measurement.unit),
    };
}

/// Rounds a non-negative load to a positive same-unit quantum.
pub fn roundLoad(
    load: primitives.Measurement,
    rounding: Rounding,
) Error!primitives.Measurement {
    const quantum = parseMeasurement(rounding.quantum) catch
        return error.InvalidConfig;
    if (load.unit != quantum.unit) return error.IncompatibleUnit;
    const scale = @max(load.value.scale, quantum.value.scale);
    const load_value = try scaledMantissa(load.value, scale);
    const quantum_value = try scaledMantissa(quantum.value, scale);
    if (load_value < 0 or quantum_value <= 0) return error.InvalidConfig;
    var quotient = @divFloor(load_value, quantum_value);
    const remainder = @mod(load_value, quantum_value);
    switch (rounding.mode) {
        .down => {},
        .up => if (remainder != 0) {
            quotient += 1;
        },
        .nearest => if (remainder * 2 >= quantum_value) {
            quotient += 1;
        },
    }
    const rounded, const overflow = @mulWithOverflow(quotient, quantum_value);
    if (overflow != 0 or rounded > std.math.maxInt(i64)) return error.Overflow;
    return .{
        .value = .{ .mantissa = @intCast(rounded), .scale = scale },
        .unit = load.unit,
    };
}

fn scaledMantissa(
    value: primitives.Decimal,
    scale: u8,
) Error!i128 {
    var result: i128 = value.mantissa;
    var remaining = scale - value.scale;
    while (remaining > 0) : (remaining -= 1) {
        const next, const overflow = @mulWithOverflow(result, 10);
        if (overflow != 0) return error.Overflow;
        result = next;
    }
    return result;
}

test "load rounding modes are deterministic" {
    const load: primitives.Measurement = .{
        .value = .{ .mantissa = 1025, .scale = 1 },
        .unit = .kg,
    };
    const quantum: canonical.Measurement = .{ .amount = "5", .unit = "kg" };

    const nearest = try roundLoad(load, .{ .mode = .nearest, .quantum = quantum });
    const down = try roundLoad(load, .{ .mode = .down, .quantum = quantum });
    const up = try roundLoad(load, .{ .mode = .up, .quantum = quantum });

    try std.testing.expectEqual(primitives.Decimal{ .mantissa = 1050, .scale = 1 }, nearest.value);
    try std.testing.expectEqual(primitives.Decimal{ .mantissa = 1000, .scale = 1 }, down.value);
    try std.testing.expectEqual(primitives.Decimal{ .mantissa = 1050, .scale = 1 }, up.value);
}

test "load rounding rejects incompatible quantum units" {
    const load: primitives.Measurement = .{
        .value = .{ .mantissa = 100, .scale = 0 },
        .unit = .lb,
    };
    try std.testing.expectError(
        error.IncompatibleUnit,
        roundLoad(load, .{
            .mode = .nearest,
            .quantum = .{ .amount = "2.5", .unit = "kg" },
        }),
    );
}
