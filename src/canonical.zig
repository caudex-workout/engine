const std = @import("std");

pub const Measurement = struct {
    amount: []const u8,
    unit: []const u8,
};

pub const Metric = struct {
    code: []const u8,
    value: Measurement,
};

pub const MuscleRole = enum {
    primary,
    secondary,
    stabilizer,
    custom,
};

pub const MuscleContribution = struct {
    muscleId: []const u8,
    role: MuscleRole,
    weight: ?[]const u8 = null,
};

pub const KnowledgeAuthority = enum {
    source_provided,
    caudex_curated,
    mechanically_derived,
    host_provided,
    unknown,
};

pub const KnowledgeEvidence = struct {
    authority: KnowledgeAuthority,
    sourceId: ?[]const u8 = null,
    version: ?[]const u8 = null,
    confidence: enum { low, moderate, high, unknown } = .unknown,
};

pub const EquipmentRequirement = struct {
    equipmentId: []const u8,
    equipmentFamilyId: ?[]const u8 = null,
    requirement: enum { required, optional, one_of } = .required,
    role: enum { load_bearing, support, setup, other } = .other,
    alternativeGroup: ?[]const u8 = null,
};

pub const TrackingDimension = struct {
    metricCode: []const u8,
    requirement: enum { required, optional } = .required,
    scope: enum { total, per_side, per_hand, left_right_independent } = .total,
};

pub const ProgressionCapabilities = struct {
    externalLoad: ?bool = null,
    repetitions: ?bool = null,
    percentageOneRepMax: ?bool = null,
    effortTarget: ?bool = null,
    amrap: ?bool = null,
    failureTraining: ?bool = null,
    duration: ?bool = null,
    distance: ?bool = null,
    assistanceReduction: ?bool = null,
};

pub const ExerciseRelationships = struct {
    variantOf: ?[]const u8 = null,
    variantIds: []const []const u8 = &.{},
    substituteIds: []const []const u8 = &.{},
    similarExerciseIds: []const []const u8 = &.{},
    sharedProgressionStateIds: []const []const u8 = &.{},
};

/// The compact, replayable projection of programming-relevant exercise facts.
/// Catalog-only content such as instructions and media deliberately stays out.
pub const ExerciseKnowledge = struct {
    schemaVersion: u32 = 1,
    familyId: ?[]const u8 = null,
    variantDimensions: []const struct {
        dimension: []const u8,
        value: []const u8,
    } = &.{},
    movementPatterns: []const []const u8 = &.{},
    structuralType: ?enum { compound, isolation, isometric, locomotor, conditioning, mobility, other } = null,
    laterality: ?enum { bilateral, unilateral, alternating, independent_bilateral, not_applicable, unknown } = null,
    repetitionSemantics: ?enum { total, per_side, alternating_total, left_right_independent, not_applicable, unknown } = null,
    equipmentRequirements: []const EquipmentRequirement = &.{},
    trackingDimensions: []const TrackingDimension = &.{},
    loadingMode: ?enum { external_load, bodyweight, bodyweight_plus_load, assisted_bodyweight, repetitions_only, duration, distance, load_duration, distance_duration, machine_load, other } = null,
    progressionCapabilities: ?ProgressionCapabilities = null,
    restrictionTags: []const []const u8 = &.{},
    relationships: ExerciseRelationships = .{},
    skillLevel: ?enum { beginner_friendly, intermediate, advanced_technical, highly_technical, unknown } = null,
    stabilityDemand: ?enum { externally_stabilized, supported, free, highly_unstable, unknown } = null,
    setupBurden: ?enum { trivial, low, moderate, high, unknown } = null,
    fatigue: ?struct {
        localMuscular: ?enum { low, moderate, high, unknown } = null,
        axial: ?enum { low, moderate, high, unknown } = null,
        systemic: ?enum { low, moderate, high, unknown } = null,
        grip: ?enum { low, moderate, high, unknown } = null,
        cardiorespiratory: ?enum { low, moderate, high, unknown } = null,
        technical: ?enum { low, moderate, high, unknown } = null,
    } = null,
    evidence: []const KnowledgeEvidence = &.{},
};

pub const Exercise = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    equipmentIds: []const []const u8 = &.{},
    movementTags: []const []const u8 = &.{},
    muscleContributions: []const MuscleContribution = &.{},
    unilateral: ?bool = null,
    aliases: []const []const u8 = &.{},
    attributes: ?std.json.Value = null,
    /// Authoritative when present. Legacy fields remain a compatibility
    /// projection and are consulted only for concepts absent from knowledge.
    knowledge: ?ExerciseKnowledge = null,
};

pub const Goal = struct {
    /// Built-in IDs include hypertrophy, strength, general-fitness,
    /// muscular-endurance, powerlifting-practice, limited-equipment, and
    /// maintenance. Namespaced host strategy IDs are also valid.
    id: []const u8,
    weight: ?u16 = null,
};

pub const GoalSet = struct {
    primary: ?Goal = null,
    secondary: []const Goal = &.{},
    bodyCompositionObjective: ?[]const u8 = null,
};

pub const Experience = struct {
    resistanceTraining: ?enum { novice, intermediate, advanced } = null,
    consistentMonths: ?u16 = null,
    technicalLiftFamiliarity: ?enum { unfamiliar, learning, familiar, proficient } = null,
    exercises: []const struct {
        exerciseId: []const u8,
        familiarity: enum { unfamiliar, learning, familiar, proficient },
    } = &.{},
};

pub const SchedulePreference = struct {
    preferredSessionsPerWeek: ?u8 = null,
    minimumSessionsPerWeek: ?u8 = null,
    maximumSessionsPerWeek: ?u8 = null,
    preferredDays: []const enum { monday, tuesday, wednesday, thursday, friday, saturday, sunday } = &.{},
    cadence: enum { unspecified, fixed_weekdays, rolling } = .unspecified,
    preferRestBetweenSessions: ?bool = null,
};

pub const DurationPreference = struct {
    preferredMinutes: ?u16 = null,
    acceptableMinimumMinutes: ?u16 = null,
    acceptableMaximumMinutes: ?u16 = null,
    hardMaximumMinutes: ?u16 = null,
};

pub const UnitPreferences = struct {
    load: ?enum { kilograms, pounds } = null,
    bodyweight: ?enum { kilograms, pounds } = null,
    distance: ?enum { meters, kilometers, feet, miles } = null,
};

pub const Preference = struct {
    targetKind: enum { exercise, exercise_family, movement_pattern, equipment_category },
    targetId: []const u8,
    level: enum { preferred, deprioritized, excluded, required },
};

pub const MusclePriority = struct {
    muscleId: []const u8,
    priority: enum { emphasize, balanced, maintain, deprioritize },
    weight: ?u16 = null,
};

pub const Restriction = struct {
    id: []const u8,
    targetKind: enum { exercise, exercise_family, movement_pattern, restriction_tag, equipment },
    targetId: []const u8,
};

pub const EquipmentItem = struct {
    equipmentId: []const u8,
    minimumLoadIncrement: ?Measurement = null,
};

pub const TrainingLocation = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    equipment: []const EquipmentItem = &.{},
    metadata: ?std.json.Value = null,
};

pub const CapabilityObservation = struct {
    id: []const u8,
    kind: enum { recent_performance, estimated_one_rep_max, assistance_capacity, exercise_familiarity, benchmark, custom },
    exerciseId: ?[]const u8 = null,
    value: ?Measurement = null,
    observedAt: []const u8,
    provenance: enum { athlete_reported, host_observed, device_supplied, imported, unknown } = .unknown,
    customKindId: ?[]const u8 = null,
};

/// Explicit persistent training intent. It is neither an account nor derived
/// athlete state, and it never owns progression-method state.
pub const AthleteProfile = struct {
    schemaVersion: u32 = 1,
    id: []const u8,
    revision: u64 = 0,
    displayName: ?[]const u8 = null,
    goals: GoalSet = .{},
    experience: Experience = .{},
    schedule: SchedulePreference = .{},
    duration: DurationPreference = .{},
    units: UnitPreferences = .{},
    exercisePreferences: []const Preference = &.{},
    musclePriorities: []const MusclePriority = &.{},
    restrictions: []const Restriction = &.{},
    locations: []const TrainingLocation = &.{},
    capabilityObservations: []const CapabilityObservation = &.{},
    metadata: ?std.json.Value = null,
};

pub const SetStatus = enum {
    completed,
    partial,
    skipped,
    failed,
};

pub const CompletedSet = struct {
    id: ?[]const u8 = null,
    kind: []const u8,
    actualMetrics: []const Metric,
    targetMetrics: []const Metric = &.{},
    completedAt: ?[]const u8 = null,
    status: SetStatus,
};

pub const CompletedExercise = struct {
    exerciseId: []const u8,
    sets: []const CompletedSet,
    tags: []const []const u8 = &.{},
    notes: ?[]const u8 = null,
};

pub const CompletedWorkout = struct {
    id: []const u8,
    startedAt: []const u8,
    completedAt: []const u8,
    exercises: []const CompletedExercise,
};

pub const TemplateSet = struct {
    kind: ?[]const u8 = null,
    targetMetrics: []const Metric = &.{},
};

pub const TemplateExercise = struct {
    exerciseId: []const u8,
    sets: []const TemplateSet = &.{},
    notes: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
};

pub const WorkoutTemplate = struct {
    schemaVersion: u32,
    id: []const u8,
    displayName: []const u8,
    description: ?[]const u8 = null,
    exercises: []const TemplateExercise,
    notes: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
    revision: u64,
};

pub const HistorySnapshot = struct {
    workouts: []const CompletedWorkout = &.{},
    summaries: ?std.json.Value = null,
};

pub const ReadinessObservation = struct {
    id: []const u8,
    dimension: enum { overall, fatigue, sleep_quality, pain, soreness },
    subjectId: ?[]const u8 = null,
    value: u8,
    scaleMaximum: u8,
    observedAt: []const u8,
    provenance: enum { athlete_reported, host_observed, device_supplied, imported, unknown } = .athlete_reported,
};

pub const EquipmentDelta = struct {
    override: ?[]const []const u8 = null,
    additions: []const []const u8 = &.{},
    removals: []const []const u8 = &.{},
};

/// Facts and constraints scoped only to the recommendation being made.
pub const TrainingContext = struct {
    locationId: ?[]const u8 = null,
    equipment: EquipmentDelta = .{},
    availableMinutes: ?u32 = null,
    hardMaximumMinutes: ?u32 = null,
    goals: GoalSet = .{},
    preferences: []const Preference = &.{},
    restrictions: []const Restriction = &.{},
    minExercises: ?u16 = null,
    maxExercises: ?u16 = null,
    maxSets: ?u16 = null,
    excludedExerciseIds: []const []const u8 = &.{},
    requiredExerciseIds: []const []const u8 = &.{},
    readiness: []const ReadinessObservation = &.{},
};

pub const ProgramTrainingContext = struct {
    goals: GoalSet = .{},
    exercisePreferences: []const Preference = &.{},
    musclePriorities: []const MusclePriority = &.{},
    restrictions: []const Restriction = &.{},
    requiredExerciseIds: []const []const u8 = &.{},
    excludedExerciseIds: []const []const u8 = &.{},
};

pub const MethodologyRef = struct {
    id: []const u8,
    versionRequirement: ?[]const u8 = null,
    configVersion: u32,
    config: std.json.Value,
};

pub const MethodologyState = struct {
    schemaVersion: u32,
    data: std.json.Value,
};

/// A program strategy owns session-level intent and composition. Methodology
/// references nested beneath exercise slots remain exercise progression
/// implementations; this additive model leaves the v0.1 single-methodology
/// request unchanged.
pub const ProgramStrategyRef = struct {
    id: []const u8,
    versionRequirement: ?[]const u8 = null,
    configVersion: u32,
    config: std.json.Value,
};

pub const ProgramState = struct {
    schemaVersion: u32,
    data: std.json.Value,
};

pub const ProgressionAssignment = struct {
    stateId: []const u8,
    methodology: MethodologyRef,
    state: ?MethodologyState = null,
};

pub const ProgramExerciseSlot = struct {
    slotId: []const u8,
    exerciseId: []const u8,
    progression: ProgressionAssignment,
};

pub const ProgramPlan = struct {
    strategy: ProgramStrategyRef,
    state: ?ProgramState = null,
    exercises: []const ProgramExerciseSlot,
    trainingContext: ProgramTrainingContext = .{},
};

pub const ProgramRecommendationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    program: ProgramPlan,
    catalog: []const Exercise,
    athleteProfile: ?AthleteProfile = null,
    history: HistorySnapshot = .{},
    trainingContext: TrainingContext = .{},
};

pub const RecommendationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    methodology: MethodologyRef,
    methodologyState: ?MethodologyState = null,
    catalog: []const Exercise,
    athleteProfile: ?AthleteProfile = null,
    history: HistorySnapshot = .{},
    trainingContext: TrainingContext = .{},
    alternativeLimit: u16 = 0,
    tieBreakSeed: ?[]const u8 = null,
};

pub const EvaluationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    methodology: MethodologyRef,
    methodologyState: ?MethodologyState = null,
    catalog: []const Exercise,
    athleteProfile: ?AthleteProfile = null,
    history: HistorySnapshot = .{},
    completedWorkout: CompletedWorkout,
};

pub const Severity = enum {
    info,
    warning,
    @"error",
};

pub const ValidationIssue = struct {
    code: []const u8,
    path: []const u8,
    message: []const u8,
    severity: Severity,
    parameters: ?std.json.Value = null,
    suggestion: ?[]const u8 = null,
};

pub const ExplanationSubject = struct {
    exerciseId: ?[]const u8 = null,
    setIndex: ?u32 = null,
};

pub const EvidenceRef = struct {
    path: []const u8,
};

pub const Explanation = struct {
    id: []const u8,
    code: []const u8,
    category: []const u8,
    summary: []const u8,
    subject: ?ExplanationSubject = null,
    evidence: []const EvidenceRef = &.{},
    parameters: ?std.json.Value = null,
    ruleId: ?[]const u8 = null,
    severity: Severity,
};

pub const SetRecommendation = struct {
    kind: []const u8,
    targetMetrics: []const Metric,
    restDuration: ?Measurement = null,
    explanationRefs: []const []const u8 = &.{},
};

pub const ExerciseRecommendation = struct {
    exerciseId: []const u8,
    sets: []const SetRecommendation,
    substitutionGroup: ?[]const u8 = null,
    explanationRefs: []const []const u8 = &.{},
    programming: ?ExerciseProgrammingProvenance = null,
};

pub const ResolvedComponent = struct {
    id: []const u8,
    version: []const u8,
    configVersion: u32,
};

pub const ResolvedSource = enum { engine_default, athlete_profile, program, location_profile, session, explicit_request };
pub const ResolvedRestriction = struct { value: Restriction, source: ResolvedSource };
pub const ResolvedPreference = struct { value: Preference, source: ResolvedSource };
pub const ResolvedMusclePriority = struct { value: MusclePriority, source: ResolvedSource };
pub const ResolvedExerciseConstraint = struct { exerciseId: []const u8, source: ResolvedSource };

/// Minimal deterministic projection captured with the recommendation. It is
/// sufficient to explain/replay decisions without consulting a mutable profile.
pub const ResolvedTrainingContext = struct {
    schemaVersion: u32 = 1,
    athleteProfileId: []const u8,
    athleteProfileRevision: u64,
    athleteProfileFingerprint: []const u8,
    goals: GoalSet,
    experience: Experience,
    schedule: SchedulePreference,
    preferredDuration: DurationPreference,
    availableMinutes: ?u16 = null,
    hardMaximumMinutes: ?u16 = null,
    units: UnitPreferences,
    locationId: ?[]const u8 = null,
    availableEquipmentIds: []const []const u8,
    preferences: []const ResolvedPreference,
    restrictions: []const ResolvedRestriction,
    musclePriorities: []const ResolvedMusclePriority,
    requiredExercises: []const ResolvedExerciseConstraint,
    excludedExercises: []const ResolvedExerciseConstraint,
    readiness: []const ReadinessObservation,
    capabilityObservations: []const CapabilityObservation,
};

pub const ExerciseProgrammingProvenance = struct {
    slotId: []const u8,
    stateId: []const u8,
    progression: ResolvedComponent,
    config: std.json.Value,
    inputState: ?MethodologyState = null,
};

pub const SessionProgrammingProvenance = struct {
    strategy: ResolvedComponent,
    config: std.json.Value,
    inputState: ?ProgramState = null,
    resolvedTrainingContext: ?ResolvedTrainingContext = null,
};

pub const SessionRecommendation = struct {
    title: ?[]const u8 = null,
    estimatedDuration: ?Measurement = null,
    exercises: []const ExerciseRecommendation,
    programming: ?SessionProgrammingProvenance = null,
    resolvedTrainingContext: ?ResolvedTrainingContext = null,
};

pub const ExerciseEvaluation = struct {
    exerciseId: []const u8,
    outcome: []const u8,
    explanationRefs: []const []const u8 = &.{},
    stateId: ?[]const u8 = null,
    progression: ?ResolvedComponent = null,
};

pub const PerformanceEvaluation = struct {
    outcome: []const u8,
    exercises: []const ExerciseEvaluation,
};

pub const ResolvedMethodology = struct {
    id: []const u8,
    version: []const u8,
    configVersion: u32,
};

pub const ResultMetadata = struct {
    engineVersion: []const u8,
    schemaVersion: u32,
    methodology: ResolvedMethodology,
    inputFingerprint: []const u8,
    resultFingerprint: []const u8,
};

pub const RecommendationResult = struct {
    ok: bool,
    recommendation: ?SessionRecommendation = null,
    alternatives: []const SessionRecommendation = &.{},
    nextMethodologyState: ?MethodologyState = null,
    explanations: []const Explanation = &.{},
    warnings: []const ValidationIssue = &.{},
    issues: []const ValidationIssue = &.{},
    metadata: ResultMetadata,
};

pub const EvaluationResult = struct {
    ok: bool,
    evaluation: ?PerformanceEvaluation = null,
    nextMethodologyState: ?MethodologyState = null,
    explanations: []const Explanation = &.{},
    warnings: []const ValidationIssue = &.{},
    issues: []const ValidationIssue = &.{},
    metadata: ResultMetadata,
};

pub const ProgramEvaluationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    recommendation: SessionRecommendation,
    catalog: []const Exercise,
    athleteProfile: ?AthleteProfile = null,
    history: HistorySnapshot = .{},
    completedWorkout: CompletedWorkout,
};

pub const ProgressionStateProposal = struct {
    stateId: []const u8,
    progression: ResolvedComponent,
    state: MethodologyState,
};

pub const ProgramResultMetadata = struct {
    engineVersion: []const u8,
    schemaVersion: u32,
    programStrategy: ResolvedComponent,
    inputFingerprint: []const u8,
    resultFingerprint: []const u8,
};

pub const ProgramRecommendationResult = struct {
    ok: bool,
    recommendation: ?SessionRecommendation = null,
    explanations: []const Explanation = &.{},
    warnings: []const ValidationIssue = &.{},
    issues: []const ValidationIssue = &.{},
    metadata: ProgramResultMetadata,
};

pub const ProgramEvaluationResult = struct {
    ok: bool,
    evaluation: ?PerformanceEvaluation = null,
    nextProgramState: ?ProgramState = null,
    progressionStateProposals: []const ProgressionStateProposal = &.{},
    explanations: []const Explanation = &.{},
    warnings: []const ValidationIssue = &.{},
    issues: []const ValidationIssue = &.{},
    metadata: ProgramResultMetadata,
};
