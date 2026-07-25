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

pub const Exercise = struct {
    id: []const u8,
    name: ?[]const u8 = null,
    equipmentIds: []const []const u8 = &.{},
    movementTags: []const []const u8 = &.{},
    muscleContributions: []const MuscleContribution = &.{},
    unilateral: ?bool = null,
    aliases: []const []const u8 = &.{},
    attributes: ?std.json.Value = null,
};

pub const AthletePreferences = struct {
    preferredExerciseIds: []const []const u8 = &.{},
    dislikedExerciseIds: []const []const u8 = &.{},
    avoidedEquipmentIds: []const []const u8 = &.{},
    muscleEmphasis: []const MuscleEmphasis = &.{},
};

pub const MuscleEmphasis = struct {
    muscleId: []const u8,
    weight: []const u8,
};

pub const AthleteRestrictions = struct {
    excludedExerciseIds: []const []const u8 = &.{},
    excludedMovementTags: []const []const u8 = &.{},
    equipmentLimitations: []const []const u8 = &.{},
    constraints: []const Constraint = &.{},
};

pub const Constraint = struct {
    code: []const u8,
    subjectId: ?[]const u8 = null,
    details: ?std.json.Value = null,
};

pub const Athlete = struct {
    id: ?[]const u8 = null,
    preferences: AthletePreferences = .{},
    restrictions: AthleteRestrictions = .{},
    capabilities: ?std.json.Value = null,
    readiness: ?std.json.Value = null,
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

pub const HistorySnapshot = struct {
    workouts: []const CompletedWorkout = &.{},
    summaries: ?std.json.Value = null,
};

pub const SessionContext = struct {
    availableMinutes: ?u32 = null,
    availableEquipmentIds: []const []const u8 = &.{},
    goals: []const []const u8 = &.{},
    minExercises: ?u16 = null,
    maxExercises: ?u16 = null,
    maxSets: ?u16 = null,
    excludedExerciseIds: []const []const u8 = &.{},
    requiredExerciseIds: []const []const u8 = &.{},
    locationTags: []const []const u8 = &.{},
    readiness: ?std.json.Value = null,
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

pub const RecommendationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    methodology: MethodologyRef,
    methodologyState: ?MethodologyState = null,
    catalog: []const Exercise,
    athlete: Athlete = .{},
    history: HistorySnapshot = .{},
    session: SessionContext = .{},
    alternativeLimit: u16 = 0,
    tieBreakSeed: ?[]const u8 = null,
};

pub const EvaluationRequest = struct {
    schemaVersion: u32,
    asOf: []const u8,
    methodology: MethodologyRef,
    methodologyState: ?MethodologyState = null,
    catalog: []const Exercise,
    athlete: Athlete = .{},
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
};

pub const SessionRecommendation = struct {
    title: ?[]const u8 = null,
    estimatedDuration: ?Measurement = null,
    exercises: []const ExerciseRecommendation,
};

pub const ExerciseEvaluation = struct {
    exerciseId: []const u8,
    outcome: []const u8,
    explanationRefs: []const []const u8 = &.{},
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
