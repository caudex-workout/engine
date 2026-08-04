//! Caudex Workout Engine's public Zig module.
//!
//! Hosts provide complete, borrowed request snapshots and caller-owned output
//! storage. Core calculations are deterministic and perform no persistence,
//! network access, clock reads, hidden randomness, or implicit allocation.
//!
//! Start with `engine.recommendSession` and `engine.evaluatePerformance` for
//! the typed v0.1 operations. Custom builds can compose implementations with
//! `methodology.Methodology` and `methodology.Registry`. Canonical JSON and
//! ABI adapters are boundary tools; direct Zig consumers should prefer the
//! typed domain modules exported here.

const std = @import("std");

pub const canonical = @import("canonical.zig");
pub const canonical_json = @import("canonical_json.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const discovery = @import("discovery.zig");
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
