//! Exercise-local prescription and evaluation capabilities.

const primitives = @import("../primitives.zig");
const exercise_knowledge = @import("../exercise_knowledge.zig");

pub const double_progression = @import("../double_progression.zig");
pub const rpe_top_set_backoff = @import("../rpe_top_set_backoff.zig");

pub const Method = union(enum) {
    double_progression: DoubleProgression,
    rpe_top_set_backoff: RpeTopSetBackoff,

    pub const DoubleProgression = struct {
        config: double_progression.Config,
        state: ?double_progression.State = null,
    };
    pub const RpeTopSetBackoff = struct {
        config: rpe_top_set_backoff.Config,
        state: ?rpe_top_set_backoff.State = null,
    };

    pub fn id(self: Method) []const u8 {
        return switch (self) {
            .double_progression => double_progression.methodology_id,
            .rpe_top_set_backoff => rpe_top_set_backoff.methodology_id,
        };
    }

    pub fn requirement(self: Method) exercise_knowledge.ProgressionRequirement {
        return switch (self) {
            .double_progression, .rpe_top_set_backoff => .externally_loadable_repetitions,
        };
    }
};

pub const Lane = struct {
    state_id: primitives.Id,
    method: Method,
};
