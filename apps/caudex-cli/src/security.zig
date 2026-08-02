const std = @import("std");

pub const max_argument_count: usize = 256;
pub const max_argument_bytes: usize = 4096;
pub const max_batch_bytes: usize = 64 * 1024;
pub const max_batch_line_bytes: usize = 2048;
pub const max_batch_operations: usize = 100;

pub const InputError = error{ Empty, TooLong, InvalidUtf8 };

pub fn validateInput(value: []const u8, limit: usize, allow_empty: bool) InputError!void {
    if (!allow_empty and value.len == 0) return error.Empty;
    if (value.len > limit) return error.TooLong;
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
}

pub fn validateArgs(args: []const []const u8) InputError!void {
    if (args.len > max_argument_count) return error.TooLong;
    for (args) |arg| try validateInput(arg, max_argument_bytes, true);
}

pub fn validatePath(path: []const u8) InputError!void {
    try validateInput(path, max_argument_bytes, false);
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidUtf8;
}

/// Writes user-controlled text without allowing it to create terminal control
/// sequences or additional output lines. Valid UTF-8 remains readable; invalid
/// bytes are rendered as byte escapes.
pub fn writeEscaped(writer: *std.Io.Writer, value: []const u8) !void {
    const valid_utf8 = std.unicode.utf8ValidateSlice(value);
    for (value) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte == 0x1b or (!valid_utf8 and byte >= 0x80)) {
            try writer.print("\\x{X:0>2}", .{byte});
        } else {
            try writer.writeByte(byte);
        }
    }
}

pub fn isClosedOutput(err: anyerror) bool {
    return err == error.BrokenPipe or err == error.NotOpen;
}

test "input validation is bounded and rejects invalid UTF-8" {
    try std.testing.expectError(error.Empty, validateInput("", 4, false));
    try std.testing.expectError(error.TooLong, validateInput("12345", 4, true));
    try std.testing.expectError(error.InvalidUtf8, validateInput("\xff", 4, true));
    try validateArgs(&.{ "caudex", "--help" });
}

test "terminal escaping removes control bytes and unsafe invalid bytes" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeEscaped(&writer, "ok\n\x1b[31m\xff");
    try std.testing.expectEqualStrings("ok\\x0A\\x1B[31m\\xFF", writer.buffered());
}

test "closed output errors are recognized without treating other failures as closed" {
    try std.testing.expect(isClosedOutput(error.BrokenPipe));
    try std.testing.expect(!isClosedOutput(error.OutOfMemory));
}
