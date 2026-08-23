//! Program-strategy output consumed by the shared planning kernel.

const primitives = @import("../primitives.zig");
const planning = @import("../planning/problem.zig");

pub const Presence = planning.Presence;
pub const MatchMode = planning.MatchMode;
pub const IdRequirement = planning.IdRequirement;
pub const ExerciseSet = planning.ExerciseSet;
pub const CandidateUniverse = planning.CandidateUniverse;
pub const SlotRequirements = planning.SlotRequirements;
pub const AdaptiveSelection = planning.AdaptiveSelection;
pub const Selection = planning.Selection;
pub const Ordering = planning.Ordering;
pub const Slot = planning.Slot;
pub const Strategy = planning.Strategy;
pub const PlannedSessionIntent = struct {
    definition_id: primitives.Id,
    definition_version: u32,
    definition_fingerprint: []const u8,
    instance_id: primitives.Id,
    occurrence_id: primitives.Id,
    block_id: primitives.Id,
    role_id: primitives.Id,
    planning_state_revision: u64,
    strategy: Strategy,
    slots: []const Slot,
};
