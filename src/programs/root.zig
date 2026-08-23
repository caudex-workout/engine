//! Program lifecycle and composition intent.

pub const definition = @import("definition.zig");
pub const lifecycle = @import("lifecycle.zig");
pub const intent = @import("intent.zig");
pub const hypertrophy = @import("hypertrophy.zig");

test {
    _ = definition;
    _ = lifecycle;
    _ = intent;
    _ = hypertrophy;
}
