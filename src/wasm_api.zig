const std = @import("std");
const c_api = @import("c_api.zig");

comptime {
    _ = c_api.caudex_abi_version;
    _ = c_api.caudex_runtime_create;
    _ = c_api.caudex_runtime_destroy;
    _ = c_api.caudex_runtime_execute;
}

/// Allocates host-visible linear memory. Zero is returned on failure.
pub export fn caudex_wasm_alloc(len: usize) usize {
    if (len == 0) return 0;
    const bytes = std.heap.wasm_allocator.alloc(u8, len) catch return 0;
    return @intFromPtr(bytes.ptr);
}

/// Releases memory allocated by `caudex_wasm_alloc`.
pub export fn caudex_wasm_free(pointer: usize, len: usize) void {
    if (pointer == 0 or len == 0) return;
    const data: [*]u8 = @ptrFromInt(pointer);
    std.heap.wasm_allocator.free(data[0..len]);
}

/// Creates a runtime and returns its linear-memory address, or zero on failure.
pub export fn caudex_wasm_runtime_create() usize {
    var runtime: ?*c_api.Runtime = null;
    if (c_api.caudex_runtime_create(&runtime) != .ok) return 0;
    return @intFromPtr(runtime.?);
}

/// Destroys a runtime created by `caudex_wasm_runtime_create`.
pub export fn caudex_wasm_runtime_destroy(runtime: usize) void {
    if (runtime == 0) return;
    c_api.caudex_runtime_destroy(@ptrFromInt(runtime));
}
