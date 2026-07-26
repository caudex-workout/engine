const std = @import("std");

pub const canonical = @import("canonical.zig");
pub const canonical_json = @import("canonical_json.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const double_progression = @import("double_progression.zig");
pub const duration = @import("duration.zig");
pub const engine = @import("engine.zig");
pub const filtering = @import("filtering.zig");
pub const history = @import("history.zig");
pub const load_math = @import("load_math.zig");
pub const methodology = @import("methodology.zig");
pub const ordering = @import("ordering.zig");
pub const primitives = @import("primitives.zig");
pub const rpe_top_set_backoff = @import("rpe_top_set_backoff.zig");
pub const training = @import("training.zig");

test "library test target is wired" {
    try std.testing.expect(true);
}
