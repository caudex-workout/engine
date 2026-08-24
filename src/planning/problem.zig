//! Strong, explicit input and output values for deterministic session planning.

const std = @import("std");
const primitives = @import("../primitives.zig");
const training = @import("../training.zig");
const progression = @import("../progression/root.zig");
const volume = @import("../volume.zig");

pub const schema_version: u32 = 1;
pub const planner_id = "caudex.session-planner";
pub const planner_version: u32 = 1;

pub const Id = primitives.Id;
pub const Timestamp = primitives.Timestamp;
pub const Presence = enum { required, optional };
pub const MatchMode = enum { any, all };
pub const IdRequirement = struct { ids: []const Id = &.{}, mode: MatchMode = .any };
pub const ExerciseSet = struct { exercise_ids: []const Id = &.{}, family_ids: []const Id = &.{} };
pub const CandidateUniverse = union(enum) { catalog, allowlist: ExerciseSet };
pub const SlotRequirements = struct {
    muscles: IdRequirement = .{},
    movement_patterns: IdRequirement = .{},
    exercise_families: IdRequirement = .{},
    equipment: IdRequirement = .{},
    excluded_exercise_ids: []const Id = &.{},
};
pub const AdaptiveSelection = struct {
    universe: CandidateUniverse = .catalog,
    preferred: ExerciseSet = .{},
    requirements: SlotRequirements = .{},
};
pub const Selection = union(enum) { fixed: Id, adaptive: AdaptiveSelection };
pub const Ordering = struct {
    priority_tier: u8 = 0,
    before_slot_ids: []const Id = &.{},
    after_slot_ids: []const Id = &.{},
};
pub const Slot = struct {
    id: Id,
    presence: Presence = .required,
    selection: Selection,
    progression: progression.Lane,
    ordering: Ordering = .{},
};
pub const Strategy = enum { fixed, adaptive_hypertrophy };

pub const Origin = struct {
    definition_id: Id,
    definition_version: u32,
    definition_fingerprint: []const u8,
    instance_id: Id,
    occurrence_id: Id,
    block_id: Id,
    role_id: Id,
    planning_state_revision: u64,
    strategy: Strategy,
};

pub const UnknownDurationPolicy = enum {
    allow,
    reject,
};

pub const SessionConstraints = struct {
    available_equipment_ids: []const Id = &.{},
    required_exercise_ids: []const Id = &.{},
    excluded_exercise_ids: []const Id = &.{},
    excluded_family_ids: []const Id = &.{},
    excluded_movement_pattern_ids: []const Id = &.{},
    excluded_restriction_tag_ids: []const Id = &.{},
    excluded_equipment_ids: []const Id = &.{},
    minimum_exercises: ?u8 = null,
    maximum_exercises: ?u8 = null,
    hard_maximum_minutes: ?u16 = null,
    unknown_duration_policy: UnknownDurationPolicy = .allow,
};

pub const DurationEstimate = struct {
    slot_id: Id,
    exercise_id: Id,
    minutes: u16,
};

pub const PreferenceTarget = union(enum) {
    exercise: Id,
    family: Id,
};

pub const PreferenceDirection = enum { prefer, avoid };

/// Objectives are a closed training-domain vocabulary. Their tier is fixed by
/// the planner; a caller-provided weight cannot cross a semantic tier.
pub const Objective = union(enum) {
    muscle_priority: struct { muscle_id: Id, weight: u16 },
    exercise_preference: struct {
        target: PreferenceTarget,
        direction: PreferenceDirection,
        weight: u16,
    },
    avoid_exercise_reuse: struct { weight: u16 },
    movement_variety: struct { weight: u16 },
    minimize_equipment_transitions: struct { weight: u16 },
    target_duration: struct { minutes: u16, weight: u16 },
};

pub const PlanningProblem = struct {
    schema_version: u32 = schema_version,
    origin: Origin,
    as_of: Timestamp,
    catalog: training.ExerciseCatalog,
    slots: []const Slot,
    constraints: SessionConstraints = .{},
    objectives: []const Objective = &.{},
    duration_estimates: []const DurationEstimate = &.{},
    volume_context: ?VolumeContext = null,
};

pub const VolumeContext = struct {
    state: volume.State,
    policy: volume.CreditPolicy,
};

pub const ScoreVector = struct {
    program: i64 = 0,
    training: i64 = 0,
    preference: i64 = 0,

    pub fn order(left: ScoreVector, right: ScoreVector) std.math.Order {
        if (left.program != right.program) return std.math.order(left.program, right.program);
        if (left.training != right.training) return std.math.order(left.training, right.training);
        return std.math.order(left.preference, right.preference);
    }
};

pub const TieBreakPolicy = union(enum) {
    stable_id,
    seeded: []const u8,
};

pub const SolveOptions = struct {
    candidate_limit_per_slot: u8 = 8,
    /// Maximum complete assignments examined by the bounded enumerator.
    beam_width: u16 = 256,
    tie_break: TieBreakPolicy = .stable_id,
};

pub const PlannerProvenance = struct {
    id: []const u8 = planner_id,
    version: u32 = planner_version,
    candidate_limit_per_slot: u8,
    search_bound: u16,
    tie_break: TieBreakPolicy,
    explored_state_count: u32,
};

pub const DecisionSubject = union(enum) {
    session,
    slot: Id,
    exercise: Id,
    selection: struct { slot_id: Id, exercise_id: Id },
};

pub const DecisionCode = enum {
    fixed_exercise_selected,
    optimized_exercise_selected,
    optional_slot_omitted,
    session_constraints_satisfied,

    pub fn stableCode(self: DecisionCode) []const u8 {
        return switch (self) {
            .fixed_exercise_selected => "planning.selection.fixed",
            .optimized_exercise_selected => "planning.selection.optimized",
            .optional_slot_omitted => "planning.slot.optional_omitted",
            .session_constraints_satisfied => "planning.session.constraints_satisfied",
        };
    }
};

pub const DecisionReason = struct {
    code: DecisionCode,
    subject: DecisionSubject,
    contribution: ScoreVector = .{},
};

pub const SelectionSource = union(enum) {
    fixed,
    optimized: struct {
        eligible_candidate_count: u16,
        local_rank: u16,
    },
};

/// A bounded slot-local alternative from the same selector pass. Alternatives
/// are not independently composed sessions and therefore cannot imply that a
/// globally different assignment would retain the same aggregate score.
pub const CandidateAlternative = struct {
    pub const RankReason = enum {
        lower_score,
        deterministic_tie_break,
        global_assignment_tradeoff,
    };

    exercise_id: Id,
    local_rank: u16,
    estimated_duration_minutes: ?u16,
    score: ScoreVector,
    ranked_lower_because: RankReason,
};

pub const ResolvedSlot = struct {
    slot_id: Id,
    exercise_id: Id,
    progression: progression.Lane,
    position: u8,
    selection_source: SelectionSource,
    estimated_duration_minutes: ?u16,
    score: ScoreVector,
    reason_refs: []const u16,
    alternatives: []const CandidateAlternative,
};

pub const OmissionReason = enum { optimizer_tradeoff, no_eligible_candidate };

pub const OmittedSlot = struct {
    slot_id: Id,
    reason: OmissionReason,
    reason_refs: []const u16,
};

pub const PlanMetrics = struct {
    exercise_count: u8,
    estimated_duration_minutes: ?u32,
    equipment_transition_count: u8,
};

/// Slot-count workload preserves the distinction between what the program
/// requested and what today's constrained plan retained. Exercise-local set
/// and load decisions remain owned by progression methods.
pub const WorkloadSummary = struct {
    required_slot_count: u8,
    target_slot_count: u8,
    optional_slot_count: u8,
    composed_slot_count: u8,
    omitted_optional_slot_count: u8,
};

pub const ResolvedSessionPlan = struct {
    schema_version: u32 = schema_version,
    origin: Origin,
    planner: PlannerProvenance,
    problem_fingerprint: []const u8,
    slots: []const ResolvedSlot,
    omitted_slots: []const OmittedSlot,
    score: ScoreVector,
    metrics: PlanMetrics,
    workload: WorkloadSummary,
    reasons: []const DecisionReason,
};

pub const InfeasibilityViolation = union(enum) {
    required_slot_has_no_eligible_candidate: Id,
    volume_cap_prevents_required_slot: struct {
        slot_id: Id,
        muscle_id: Id,
        current: u64,
        proposed: u64,
        hard_cap: u64,
    },
    required_exercise_cannot_be_assigned: Id,
    constraints_jointly_unsatisfiable,
    minimum_exercise_count_unreachable,
    maximum_exercise_count_below_required,
    known_minimum_duration_exceeds_maximum,
    ordering_cycle,
};

pub const InfeasiblePlan = struct {
    planner: PlannerProvenance,
    problem_fingerprint: []const u8,
    violations: []const InfeasibilityViolation,
};

pub const SearchExhausted = struct {
    planner: PlannerProvenance,
    problem_fingerprint: []const u8,
    explored_state_count: u32,
};

pub const SolveResult = union(enum) {
    resolved: ResolvedSessionPlan,
    infeasible: InfeasiblePlan,
    search_exhausted: SearchExhausted,
};
