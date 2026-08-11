export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };
export type JsonObject = { [key: string]: JsonValue };

export interface Measurement {
  amount: string;
  unit: string;
}

export {
  CaudexMeasurementError,
  kg,
  lb,
  load,
  metrics,
  minutes,
  reps,
  rir,
  rpe,
  seconds,
  type DecimalInput,
  type MassMeasurement,
} from "./measurements.ts";
import { type DecimalInput, type MassMeasurement } from "./measurements.ts";
import { createProgramFacade } from "./application.ts";
import { createActiveWorkout } from "./active-workout.ts";
import { initializeWasm, type WasmExports } from "./wasm-runtime.ts";

export interface Metric {
  code: string;
  value: Measurement;
}

export interface MuscleContribution {
  muscleId: string;
  role: "primary" | "secondary" | "stabilizer" | "custom";
  weight?: string;
}

export type KnowledgeAuthority =
  | "source_provided"
  | "caudex_curated"
  | "mechanically_derived"
  | "host_provided"
  | "unknown";

export type KnowledgeConfidence = "low" | "moderate" | "high" | "unknown";

export interface KnowledgeEvidence {
  authority: KnowledgeAuthority;
  sourceId?: string;
  version?: string;
  confidence?: KnowledgeConfidence;
}

export interface EquipmentRequirement {
  equipmentId: string;
  equipmentFamilyId?: string;
  requirement?: "required" | "optional" | "one_of";
  role?: "load_bearing" | "support" | "setup" | "other";
  alternativeGroup?: string;
}

export interface TrackingDimension {
  metricCode: string;
  requirement?: "required" | "optional";
  scope?: "total" | "per_side" | "per_hand" | "left_right_independent";
}

export interface ProgressionCapabilities {
  externalLoad?: boolean;
  repetitions?: boolean;
  percentageOneRepMax?: boolean;
  effortTarget?: boolean;
  amrap?: boolean;
  failureTraining?: boolean;
  duration?: boolean;
  distance?: boolean;
  assistanceReduction?: boolean;
}

export interface ExerciseRelationships {
  variantOf?: string;
  variantIds?: string[];
  substituteIds?: string[];
  similarExerciseIds?: string[];
  sharedProgressionStateIds?: string[];
}

export interface ExerciseVariantDimension {
  dimension: string;
  value: string;
}

export interface ExerciseFatigue {
  localMuscular?: "low" | "moderate" | "high" | "unknown";
  axial?: "low" | "moderate" | "high" | "unknown";
  systemic?: "low" | "moderate" | "high" | "unknown";
  grip?: "low" | "moderate" | "high" | "unknown";
  cardiorespiratory?: "low" | "moderate" | "high" | "unknown";
  technical?: "low" | "moderate" | "high" | "unknown";
}

/** Compact, replayable programming facts; instructions and media stay catalog-side. */
export interface ExerciseKnowledge {
  schemaVersion?: 1;
  familyId?: string;
  variantDimensions?: ExerciseVariantDimension[];
  movementPatterns?: string[];
  structuralType?: "compound" | "isolation" | "isometric" | "locomotor" | "conditioning" | "mobility" | "other";
  laterality?: "bilateral" | "unilateral" | "alternating" | "independent_bilateral" | "not_applicable" | "unknown";
  repetitionSemantics?: "total" | "per_side" | "alternating_total" | "left_right_independent" | "not_applicable" | "unknown";
  equipmentRequirements?: EquipmentRequirement[];
  trackingDimensions?: TrackingDimension[];
  loadingMode?: "external_load" | "bodyweight" | "bodyweight_plus_load" | "assisted_bodyweight" | "repetitions_only" | "duration" | "distance" | "load_duration" | "distance_duration" | "machine_load" | "other";
  progressionCapabilities?: ProgressionCapabilities;
  restrictionTags?: string[];
  relationships?: ExerciseRelationships;
  skillLevel?: "beginner_friendly" | "intermediate" | "advanced_technical" | "highly_technical" | "unknown";
  stabilityDemand?: "externally_stabilized" | "supported" | "free" | "highly_unstable" | "unknown";
  setupBurden?: "trivial" | "low" | "moderate" | "high" | "unknown";
  fatigue?: ExerciseFatigue;
  evidence?: KnowledgeEvidence[];
}

export interface Exercise {
  id: string;
  name?: string;
  equipmentIds?: string[];
  movementTags?: string[];
  muscleContributions?: MuscleContribution[];
  unilateral?: boolean;
  aliases?: string[];
  attributes?: JsonValue;
  knowledge?: ExerciseKnowledge;
}

export interface CompletedSet {
  id?: string;
  kind: string;
  actualMetrics: Metric[];
  targetMetrics?: Metric[];
  completedAt?: string;
  status: "completed" | "partial" | "skipped" | "failed";
}

export interface CompletedExercise {
  exerciseId: string;
  sets: CompletedSet[];
  tags?: string[];
  notes?: string;
}

export interface CompletedWorkout {
  id: string;
  startedAt: string;
  completedAt: string;
  exercises: CompletedExercise[];
}

export interface MethodologyRef<TConfig = JsonValue> {
  id: string;
  versionRequirement?: string;
  configVersion: number;
  config: TConfig;
}

export {
  MethodologyConfigError,
  methodologies,
  type AdvancementCriteria,
  type BackoffCalculation,
  type DoubleProgressionConfig,
  type DoubleProgressionExerciseOverride,
  type DoubleProgressionHypertrophyOptions,
  type DoubleProgressionMethodology,
  type FailureAction,
  type FailurePolicy,
  type LoadRounding,
  type RepRange,
  type RpeTopSetBackoffConfig,
  type RpeTopSetBackoffMethodology,
  type RoundingMode,
} from "./methodologies.ts";

export interface MethodologyState {
  schemaVersion: number;
  data: JsonValue;
}

export interface ProgramState {
  schemaVersion: number;
  data: JsonValue;
}

export interface ProgramStrategyRef<TConfig = JsonValue> {
  id: string;
  versionRequirement?: string;
  configVersion: number;
  config: TConfig;
}

export interface ProgressionAssignment<TConfig = JsonValue> {
  /** Stable program-slot/lane identity; it is intentionally not exerciseId. */
  stateId: string;
  methodology: MethodologyRef<TConfig>;
  state?: MethodologyState;
}

export interface ProgramExerciseSlot<TConfig = JsonValue> {
  slotId: string;
  exerciseId: string;
  progression: ProgressionAssignment<TConfig>;
}

export interface ProgramRecommendationRequest {
  schemaVersion: 1;
  asOf: string;
  program: {
    strategy: ProgramStrategyRef;
    state?: ProgramState;
    exercises: ProgramExerciseSlot[];
    trainingContext?: ProgramTrainingContext;
  };
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  trainingContext?: TrainingContext;
}

export type GoalId = "hypertrophy" | "strength" | "general-fitness" | "muscular-endurance" | "powerlifting-practice" | "limited-equipment" | "maintenance" | (string & {});
export interface Goal { id: GoalId; weight?: number }
export interface GoalSet { primary?: Goal; secondary?: Goal[]; bodyCompositionObjective?: string }
export type Familiarity = "unfamiliar" | "learning" | "familiar" | "proficient";
export interface Experience {
  resistanceTraining?: "novice" | "intermediate" | "advanced";
  consistentMonths?: number;
  technicalLiftFamiliarity?: Familiarity;
  exercises?: Array<{ exerciseId: string; familiarity: Familiarity }>;
}
export interface SchedulePreference {
  preferredSessionsPerWeek?: number;
  minimumSessionsPerWeek?: number;
  maximumSessionsPerWeek?: number;
  preferredDays?: Array<"monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday">;
  cadence?: "unspecified" | "fixed_weekdays" | "rolling";
  preferRestBetweenSessions?: boolean;
}
export interface DurationPreference { preferredMinutes?: number; acceptableMinimumMinutes?: number; acceptableMaximumMinutes?: number; hardMaximumMinutes?: number }
export interface UnitPreferences { load?: "kilograms" | "pounds"; bodyweight?: "kilograms" | "pounds"; distance?: "meters" | "kilometers" | "feet" | "miles" }
export type PreferenceTargetKind = "exercise" | "exercise_family" | "movement_pattern" | "equipment_category";
export type PreferenceLevel = "preferred" | "deprioritized" | "excluded" | "required";
export interface ExercisePreference { targetKind: PreferenceTargetKind; targetId: string; level: PreferenceLevel }
export interface MusclePriority { muscleId: string; priority: "emphasize" | "balanced" | "maintain" | "deprioritize"; weight?: number }
export interface TrainingRestriction { id: string; targetKind: "exercise" | "exercise_family" | "movement_pattern" | "restriction_tag" | "equipment"; targetId: string }
export interface EquipmentItem { equipmentId: string; minimumLoadIncrement?: Measurement }
export interface TrainingLocation { id: string; name?: string; equipment?: EquipmentItem[]; metadata?: JsonValue }
export interface CapabilityObservation {
  id: string; kind: "recent_performance" | "estimated_one_rep_max" | "assistance_capacity" | "exercise_familiarity" | "benchmark" | "custom";
  exerciseId?: string; value?: Measurement; observedAt: string;
  provenance?: "athlete_reported" | "host_observed" | "device_supplied" | "imported" | "unknown"; customKindId?: string;
}
export interface AthleteProfile {
  schemaVersion?: 1; id: string; revision?: number; displayName?: string; goals?: GoalSet; experience?: Experience;
  schedule?: SchedulePreference; duration?: DurationPreference; units?: UnitPreferences;
  exercisePreferences?: ExercisePreference[]; musclePriorities?: MusclePriority[]; restrictions?: TrainingRestriction[];
  locations?: TrainingLocation[]; capabilityObservations?: CapabilityObservation[]; metadata?: JsonValue;
}
export interface ReadinessObservation {
  id: string; dimension: "overall" | "fatigue" | "sleep_quality" | "pain" | "soreness"; subjectId?: string;
  value: number; scaleMaximum: number; observedAt: string;
  provenance?: "athlete_reported" | "host_observed" | "device_supplied" | "imported" | "unknown";
}
export interface EquipmentDelta { override?: string[]; additions?: string[]; removals?: string[] }
export interface TrainingContext {
  locationId?: string; equipment?: EquipmentDelta; availableMinutes?: number; hardMaximumMinutes?: number; goals?: GoalSet;
  preferences?: ExercisePreference[]; restrictions?: TrainingRestriction[]; minExercises?: number; maxExercises?: number; maxSets?: number;
  excludedExerciseIds?: string[]; requiredExerciseIds?: string[]; readiness?: ReadinessObservation[];
}
export type ContextSource = "engine_default" | "athlete_profile" | "program" | "location_profile" | "session" | "explicit_request";
export interface ProgramTrainingContext {
  goals?: GoalSet; exercisePreferences?: ExercisePreference[]; musclePriorities?: MusclePriority[]; restrictions?: TrainingRestriction[];
  requiredExerciseIds?: string[]; excludedExerciseIds?: string[];
}
export interface ResolvedTrainingContext {
  schemaVersion: 1; athleteProfileId: string; athleteProfileRevision: number; athleteProfileFingerprint: string;
  goals: GoalSet; experience: Experience; schedule: SchedulePreference; preferredDuration: DurationPreference;
  availableMinutes?: number; hardMaximumMinutes?: number; units: UnitPreferences; locationId?: string;
  availableEquipmentIds: string[];
  preferences: Array<{ value: ExercisePreference; source: ContextSource }>;
  restrictions: Array<{ value: TrainingRestriction; source: ContextSource }>;
  musclePriorities: Array<{ value: MusclePriority; source: ContextSource }>;
  requiredExercises: Array<{ exerciseId: string; source: ContextSource }>;
  excludedExercises: Array<{ exerciseId: string; source: ContextSource }>;
  readiness: ReadinessObservation[]; capabilityObservations: CapabilityObservation[];
}

/** Defines explicit host-owned profile state without inventing missing values. */
export function defineAthleteProfile(profile: AthleteProfile): AthleteProfile {
  if (!profile.id) throw new TypeError("Athlete profile id is required.");
  return structuredClone({ schemaVersion: 1, revision: 0, ...profile });
}

export interface AthleteProfileDiff { fromRevision: number; toRevision: number; changedFields: string[] }
export function diffAthleteProfiles(before: AthleteProfile, after: AthleteProfile): AthleteProfileDiff {
  if (before.id !== after.id) throw new TypeError("Athlete profile IDs must match to compute a diff.");
  const fields: Array<keyof AthleteProfile> = ["goals", "experience", "schedule", "duration", "units", "exercisePreferences", "musclePriorities", "restrictions", "locations", "capabilityObservations"];
  return { fromRevision: before.revision ?? 0, toRevision: after.revision ?? 0, changedFields: fields.filter((field) => JSON.stringify(before[field]) !== JSON.stringify(after[field])) };
}

/** Ergonomic mirror of the engine's field-specific context resolution rules. */
export function resolveTrainingContext(
  profileInput: AthleteProfile,
  session: TrainingContext = {},
  program: ProgramTrainingContext = {},
  request: TrainingContext = {},
): ResolvedTrainingContext {
  const profile = defineAthleteProfile(profileInput);
  const locationId = request.locationId ?? session.locationId;
  const location = locationId === undefined ? undefined : profile.locations?.find((candidate) => candidate.id === locationId);
  if (locationId !== undefined && !location) throw new TypeError(`Unknown training location: ${locationId}`);
  for (const layer of [session.equipment, request.equipment]) {
    for (const id of layer?.additions ?? []) if (layer?.removals?.includes(id)) throw new TypeError(`Equipment is both added and removed: ${id}`);
  }
  let equipment = [...(request.equipment?.override ?? session.equipment?.override ?? location?.equipment?.map((item) => item.equipmentId) ?? [])];
  const applyEquipment = (delta?: EquipmentDelta) => {
    if (delta?.override) equipment = [...delta.override];
    equipment = equipment.filter((id) => !delta?.removals?.includes(id));
    for (const id of delta?.additions ?? []) if (!equipment.includes(id)) equipment.push(id);
  };
  applyEquipment(session.equipment); applyEquipment(request.equipment);
  const sourced = <T>(source: ContextSource, values: readonly T[] | undefined) => (values ?? []).map((value) => ({ value: structuredClone(value), source }));
  const requiredExercises = [
    ...(profile.exercisePreferences ?? []).filter((item) => item.targetKind === "exercise" && item.level === "required").map((item) => ({ exerciseId: item.targetId, source: "athlete_profile" as const })),
    ...(program.requiredExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "program" as const })),
    ...(session.requiredExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "session" as const })),
    ...(request.requiredExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "explicit_request" as const })),
  ];
  const excludedExercises = [
    ...(profile.exercisePreferences ?? []).filter((item) => item.targetKind === "exercise" && item.level === "excluded").map((item) => ({ exerciseId: item.targetId, source: "athlete_profile" as const })),
    ...(program.excludedExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "program" as const })),
    ...(session.excludedExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "session" as const })),
    ...(request.excludedExerciseIds ?? []).map((exerciseId) => ({ exerciseId, source: "explicit_request" as const })),
  ];
  for (const required of requiredExercises) if (excludedExercises.some((item) => item.exerciseId === required.exerciseId)) throw new TypeError(`Exercise is both required and excluded: ${required.exerciseId}`);
  const goals: GoalSet = {
    primary: request.goals?.primary ?? session.goals?.primary ?? program.goals?.primary ?? profile.goals?.primary,
    secondary: structuredClone(request.goals?.secondary?.length ? request.goals.secondary : session.goals?.secondary?.length ? session.goals.secondary : program.goals?.secondary?.length ? program.goals.secondary : profile.goals?.secondary ?? []),
    bodyCompositionObjective: request.goals?.bodyCompositionObjective ?? session.goals?.bodyCompositionObjective ?? program.goals?.bodyCompositionObjective ?? profile.goals?.bodyCompositionObjective,
  };
  const revision = profile.revision ?? 0;
  return {
    schemaVersion: 1, athleteProfileId: profile.id, athleteProfileRevision: revision,
    athleteProfileFingerprint: `profile:${profile.id}:${revision}`,
    goals: structuredClone(goals), experience: structuredClone(profile.experience ?? {}), schedule: structuredClone(profile.schedule ?? {}),
    preferredDuration: structuredClone(profile.duration ?? {}), availableMinutes: request.availableMinutes ?? session.availableMinutes,
    hardMaximumMinutes: request.hardMaximumMinutes ?? request.availableMinutes ?? session.hardMaximumMinutes ?? session.availableMinutes ?? profile.duration?.hardMaximumMinutes,
    units: structuredClone(profile.units ?? {}), locationId, availableEquipmentIds: equipment,
    preferences: [...sourced("athlete_profile", profile.exercisePreferences), ...sourced("program", program.exercisePreferences), ...sourced("session", session.preferences), ...sourced("explicit_request", request.preferences)],
    restrictions: [...sourced("athlete_profile", profile.restrictions), ...sourced("program", program.restrictions), ...sourced("session", session.restrictions), ...sourced("explicit_request", request.restrictions)],
    musclePriorities: [...sourced("athlete_profile", profile.musclePriorities), ...sourced("program", program.musclePriorities)],
    requiredExercises, excludedExercises, readiness: structuredClone(request.readiness ?? session.readiness ?? []),
    capabilityObservations: structuredClone(profile.capabilityObservations ?? []),
  };
}

export interface RecommendationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: {
    workouts?: CompletedWorkout[];
    summaries?: JsonValue;
  };
  trainingContext?: TrainingContext;
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

export interface EvaluationRequest {
  schemaVersion: 1;
  asOf: string;
  methodology: MethodologyRef<unknown>;
  methodologyState?: MethodologyState;
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  completedWorkout: CompletedWorkout;
}

export type Severity = "info" | "warning" | "error";

export interface ValidationIssue {
  code: string;
  path: string;
  message: string;
  severity: Severity;
  parameters?: JsonValue;
  suggestion?: string;
}

export interface Explanation {
  id: string;
  code: string;
  category: string;
  summary: string;
  subject?: { exerciseId?: string; setIndex?: number };
  evidence?: Array<{ path: string }>;
  parameters?: JsonValue;
  ruleId?: string;
  severity: Severity;
}

export interface SetRecommendation {
  kind: string;
  targetMetrics: Metric[];
  restDuration?: Measurement;
  explanationRefs?: string[];
}

export interface SessionRecommendation {
  title?: string;
  estimatedDuration?: Measurement;
  exercises: Array<{
    exerciseId: string;
    sets: SetRecommendation[];
    substitutionGroup?: string;
    explanationRefs?: string[];
    programming?: ExerciseProgrammingProvenance;
  }>;
  resolvedTrainingContext?: ResolvedTrainingContext;
  programming?: {
    strategy: ResolvedComponent;
    config: JsonValue;
    inputState?: ProgramState;
    resolvedTrainingContext?: ResolvedTrainingContext;
  };
}

export interface ResolvedComponent {
  id: string;
  version: string;
  configVersion: number;
}

export interface ExerciseProgrammingProvenance {
  slotId: string;
  stateId: string;
  progression: ResolvedComponent;
  config: JsonValue;
  inputState?: MethodologyState;
}

export interface ResultMetadata {
  engineVersion: string;
  schemaVersion: number;
  methodology: {
    id: string;
    version: string;
    configVersion: number;
  };
  inputFingerprint: string;
  resultFingerprint: string;
}

interface ProgrammingResultCommon {
  explanations?: Explanation[];
  warnings?: ValidationIssue[];
  metadata: ResultMetadata;
}

export type RecommendationResult = ProgrammingResultCommon & (
  | {
      ok: true;
      recommendation: SessionRecommendation;
      alternatives?: SessionRecommendation[];
      nextMethodologyState?: MethodologyState;
      issues?: never;
    }
  | {
      ok: false;
      recommendation?: never;
      alternatives?: never;
      nextMethodologyState?: never;
      issues: ValidationIssue[];
    }
);

export interface ExerciseEvaluation {
  exerciseId: string;
  outcome: string;
  explanationRefs?: string[];
}

export interface PerformanceEvaluation {
  outcome: string;
  exercises: ExerciseEvaluation[];
}

export type EvaluationResult = ProgrammingResultCommon & (
  | { ok: true; evaluation: PerformanceEvaluation; nextMethodologyState?: MethodologyState; issues?: never }
  | { ok: false; evaluation?: never; nextMethodologyState?: never; issues: ValidationIssue[] }
);

export interface ProgramEvaluationRequest {
  schemaVersion: 1;
  asOf: string;
  recommendation: SessionRecommendation;
  catalog: Exercise[];
  athleteProfile?: AthleteProfile;
  history?: { workouts?: CompletedWorkout[]; summaries?: JsonValue };
  completedWorkout: CompletedWorkout;
}

export interface ProgramResultMetadata {
  engineVersion: string;
  schemaVersion: number;
  programStrategy: ResolvedComponent;
  inputFingerprint: string;
  resultFingerprint: string;
}

export type ProgramRecommendationResult =
  | { ok: true; recommendation: SessionRecommendation; explanations?: Explanation[]; warnings?: ValidationIssue[]; metadata: ProgramResultMetadata; issues?: never }
  | { ok: false; recommendation?: never; explanations?: Explanation[]; warnings?: ValidationIssue[]; issues: ValidationIssue[]; metadata: ProgramResultMetadata };

export interface ProgressionStateProposal {
  stateId: string;
  progression: ResolvedComponent;
  state: MethodologyState;
}

export type ProgramEvaluationResult =
  | { ok: true; evaluation: PerformanceEvaluation; nextProgramState?: ProgramState; progressionStateProposals: ProgressionStateProposal[]; explanations?: Explanation[]; warnings?: ValidationIssue[]; metadata: ProgramResultMetadata; issues?: never }
  | { ok: false; evaluation?: never; nextProgramState?: never; progressionStateProposals?: never; explanations?: Explanation[]; warnings?: ValidationIssue[]; issues: ValidationIssue[]; metadata: ProgramResultMetadata };

export type TrackingWorkoutStatus = "active" | "completed" | "cancelled";
export type TrackingSetStatus = "open" | "completed" | "partial" | "failed" | "skipped";
export type TrackingAvailability = "active" | "archived";

export interface TrackingIssue {
  code: string;
  category: "validation" | "not_found" | "conflict";
  severity: "warning" | "error";
  path?: string;
  message: string;
  relatedIds?: string[];
}

export interface TrackedSet {
  id: string;
  kind: string;
  targetMetrics?: Metric[];
  actualMetrics?: Metric[];
  status: TrackingSetStatus;
  recordedAt?: string;
}

export interface ExerciseMembership {
  id: string;
  exerciseId: string;
  sets?: TrackedSet[];
}

export interface TrackedWorkout {
  id: string;
  scope: { hostScopeKey: string; athleteId?: string };
  revision: number;
  status: TrackingWorkoutStatus;
  startedAt: string;
  completedAt?: string;
  exercises?: ExerciseMembership[];
  origin?: "manual" | "template" | "recommendation";
  provenance?: JsonValue;
  prescription?: JsonValue[];
}

export interface TrackingSnapshot {
  workouts?: TrackedWorkout[];
  startReceipts?: JsonValue[];
  exerciseCatalog?: Array<{ exerciseId: string; availability: TrackingAvailability }>;
}

export type TrackingCommand =
  | { startWorkout: Record<string, unknown> }
  | { addExercise: Record<string, unknown> }
  | { removeExercise: Record<string, unknown> }
  | { reorderExercise: Record<string, unknown> }
  | { addSet: Record<string, unknown> }
  | { completeSet: Record<string, unknown> }
  | { skipSet: Record<string, unknown> }
  | { reopenSet: Record<string, unknown> }
  | { removeSet: Record<string, unknown> }
  | { reorderSet: Record<string, unknown> }
  | { completeWorkout: Record<string, unknown> };

export interface TrackingCommandRequest {
  schemaVersion: 1;
  snapshot: TrackingSnapshot;
  command: TrackingCommand;
}

export interface TrackingBatchRequest {
  schemaVersion: 1;
  snapshot: TrackingSnapshot;
  commands: TrackingCommand[];
}

export type TrackingCommandOutcome =
  | { accepted: { commandId: string; disposition: "applied" | "replayed"; workout: TrackedWorkout; warnings?: TrackingIssue[] } }
  | { rejected: { commandId: string; issues: TrackingIssue[] } };

export interface TrackingCommandResult {
  schemaVersion: 1;
  outcome: TrackingCommandOutcome;
  snapshot: TrackingSnapshot;
}

export interface TrackingBatchResult {
  schemaVersion: 1;
  applied: boolean;
  outcomes: TrackingCommandOutcome[];
  snapshot: TrackingSnapshot;
  issues?: TrackingIssue[];
}

export interface WorkoutTemplateDocument {
  schemaVersion: 1;
  id: string;
  displayName: string;
  description?: string;
  exercises: Array<{ exerciseId: string; sets?: Array<{ kind?: string; targetMetrics?: Metric[] }>; notes?: string; tags?: string[] }>;
  notes?: string;
  tags?: string[];
  revision: number;
}

export interface InstantiationIds {
  workoutId: string;
  membershipIds: string[];
  setIds: string[];
}

export interface RecommendationInstantiationRequest {
  schemaVersion: 1;
  recommendationResult: RecommendationResult;
  catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string };
  ids: InstantiationIds;
  createdAt: string;
  acceptedRecommendationId: string;
  methodologyStateRevision?: string;
  methodologyStateFingerprint?: string;
}

export interface TemplateInstantiationRequest {
  schemaVersion: 1;
  template: WorkoutTemplateDocument;
  catalog: Exercise[];
  scope: { hostScopeKey: string; athleteId?: string };
  ids: InstantiationIds;
  createdAt: string;
}

export interface CompletionConversionRequest {
  schemaVersion: 1;
  workout: TrackedWorkout;
  catalog: Exercise[];
}

export type InstantiationResult = { schemaVersion: 1; outcome: { accepted: TrackedWorkout } | { rejected: TrackingIssue[] } };
export type CompletionConversionResult = { schemaVersion: 1; outcome: { accepted: CompletedWorkout } | { rejected: TrackingIssue[] } };

export type MethodologyOperation = "recommend" | "evaluate" | "validateConfig" | "validateState";
export type MethodologyFieldType = "integer" | "exactDecimal" | "measurement" | "enumeration" | "object" | "array" | "identifier";
export interface MethodologyFieldDescriptor {
  name: string;
  description: string;
  fieldType: MethodologyFieldType;
  required: boolean;
  defaultJson?: string;
  minimum?: string;
  maximum?: string;
  exactDecimal?: boolean;
  unitDimension?: string;
  enumChoices?: string[];
  deprecated?: boolean;
}
export interface MethodologyDescriptor {
  id: string;
  displayName: string;
  description: string;
  methodologyVersion: string;
  configurationSchemaVersion: number;
  stateSchemaVersion: number;
  supportedOperations: MethodologyOperation[];
  fields: MethodologyFieldDescriptor[];
  configurationSchemaRef: string;
  stateSchemaRef: string;
  deprecated?: boolean;
}
export interface DiscoveryRegistry {
  schemaVersion: 1;
  methodologies: MethodologyDescriptor[];
  progressionMethods: MethodologyDescriptor[];
  programStrategies: ProgramStrategyDescriptor[];
  supportedOperations: string[];
}
export interface ProgramStrategyDescriptor {
  id: string;
  displayName: string;
  description: string;
  strategyVersion: string;
  configurationSchemaVersion: number;
  stateSchemaVersion: number;
  supportedOperations: MethodologyOperation[];
  configurationSchemaRef: string;
  stateSchemaRef?: string;
}
export type MethodologyValidationResult =
  | { schemaVersion: 1; valid: true; issues: [] }
  | { schemaVersion: 1; valid: false; issues: ValidationIssue[] };

export type InitializationErrorCode =
  | "wasm_load_failed"
  | "wasm_compile_failed"
  | "abi_mismatch"
  | "missing_export"
  | "runtime_create_failed";

export class CaudexInitializationError extends Error {
  readonly code: InitializationErrorCode;
  readonly cause?: unknown;

  constructor(code: InitializationErrorCode, message: string, cause?: unknown) {
    super(message);
    this.name = "CaudexInitializationError";
    this.code = code;
    this.cause = cause;
  }
}

export class CaudexRuntimeError extends Error {
  readonly status?: number;

  constructor(message: string, status?: number) {
    super(message);
    this.name = "CaudexRuntimeError";
    this.status = status;
  }
}

export class CaudexTrackingRejectedError extends Error {
  readonly issues: TrackingIssue[];
  constructor(issues: TrackingIssue[]) {
    super(issues[0]?.message ?? "The tracking command was rejected.");
    this.name = "CaudexTrackingRejectedError";
    this.issues = issues;
  }
}

export interface ClockProvider { now(): string }
export interface IdProvider { next(kind: "workout" | "membership" | "set" | "command" | "acceptedRecommendation"): string }
export interface ActiveWorkoutRecord { hostScopeKey: string; athleteId?: string; workoutId: string; snapshot: TrackingSnapshot }
export interface ActiveWorkoutPersistence {
  loadActiveWorkout(hostScopeKey: string, workoutId: string): Promise<ActiveWorkoutRecord | null>;
  saveActiveWorkout(record: ActiveWorkoutRecord, expectedRevision: number | null): Promise<void>;
}
export interface MethodologyStateAcceptancePersistence {
  compareAndSetState(change: {
    key: { hostScopeKey: string; methodologyId: string };
    expectedRevision: string | null;
    methodologyVersion: string;
    nextState: MethodologyState;
    updatedAt: string;
  }): Promise<unknown>;
}

export interface OrchestrationPersistence {
  loadAthleteProfile?(key: { hostScopeKey: string; athleteProfileId: string }): Promise<{ profile: AthleteProfile } | null>;
  loadCatalog(input: { hostScopeKey: string; asOf: string }): Promise<readonly Exercise[]>;
  loadHistory(input: { hostScopeKey: string; through: string }): Promise<{
    workouts: readonly CompletedWorkout[];
    summaries?: JsonValue;
  }>;
  loadState(input: { hostScopeKey: string; methodologyId: string }): Promise<{
    state: MethodologyState;
    revision: string;
  } | null>;
  appendAcceptedRecommendation(record: {
    id: string;
    hostScopeKey: string;
    acceptedAt: string;
    result: RecommendationResult | ProgramRecommendationResult;
  }): Promise<void>;
  appendCompletedWorkout(hostScopeKey: string, workout: CompletedWorkout): Promise<void>;
  loadWorkflowRecovery(hostScopeKey: string, workflowId: string): Promise<WorkflowRecoveryRecord | null>;
  saveWorkflowRecovery(record: WorkflowRecoveryRecord): Promise<void>;
}

export interface WorkflowRecoveryRecord {
  hostScopeKey: string;
  workflowId: string;
  kind: string;
  status: "pending" | "completed";
  idempotencyKey: string;
  payload: JsonValue;
  updatedAt: string;
}

export interface PortableCatalogReference {
  hostScopeKey: string;
  exerciseId: string;
  catalogId?: string;
  catalogVersion?: string;
}
export interface PortableCustomExerciseRecord { hostScopeKey: string; exercise: Exercise }
export interface PortableTemplateRecord { hostScopeKey: string; template: WorkoutTemplateDocument }
export interface PortableAthleteProfileRecord { hostScopeKey: string; profile: AthleteProfile }
export interface PortableCompletedWorkoutRecord { hostScopeKey: string; workout: CompletedWorkout }
export interface PortableAcceptedRecommendationRecord {
  id: string;
  hostScopeKey: string;
  acceptedAt: string;
  result: RecommendationResult;
}
export interface PortableAcceptedProgramRecommendationRecord {
  id: string;
  hostScopeKey: string;
  acceptedAt: string;
  result: ProgramRecommendationResult;
}
export interface PortableProgressionStateRecord {
  hostScopeKey: string;
  stateId: string;
  progressionId: string;
  progressionVersion: string;
  state: MethodologyState;
  revision: string;
  updatedAt: string;
}
export interface PortableProgramStateRecord {
  hostScopeKey: string;
  programId: string;
  strategyId: string;
  strategyVersion: string;
  state: ProgramState;
  revision: string;
  updatedAt: string;
}
export interface PortableMethodologyStateRecord {
  hostScopeKey: string;
  methodologyId: string;
  methodologyVersion: string;
  state: MethodologyState;
  revision: string;
  updatedAt: string;
}
export interface PortableDocument {
  schemaVersion: 1;
  exportedAt: string;
  catalogReferences?: PortableCatalogReference[];
  customExercises?: PortableCustomExerciseRecord[];
  templates?: PortableTemplateRecord[];
  athleteProfiles?: PortableAthleteProfileRecord[];
  activeWorkouts?: ActiveWorkoutRecord[];
  completedWorkouts?: PortableCompletedWorkoutRecord[];
  acceptedRecommendations?: PortableAcceptedRecommendationRecord[];
  acceptedProgramRecommendations?: PortableAcceptedProgramRecommendationRecord[];
  methodologyStates?: PortableMethodologyStateRecord[];
  progressionStates?: PortableProgressionStateRecord[];
  programStates?: PortableProgramStateRecord[];
  workflowRecovery?: WorkflowRecoveryRecord[];
}
export type PortableImportMode = "merge" | "replace";
export type PortableConflictPolicy = "reject" | "keepExisting" | "overwrite";
export interface PortableImportRequest {
  schemaVersion: 1;
  mode: PortableImportMode;
  conflictPolicy: PortableConflictPolicy;
  dryRun?: boolean;
  document: PortableDocument;
}
export interface PortableIssue {
  code: string;
  path: string;
  message: string;
  severity: "warning" | "error";
}
export interface PortableCounts {
  catalogReferences: number;
  customExercises: number;
  templates: number;
  athleteProfiles: number;
  activeWorkouts: number;
  completedWorkouts: number;
  acceptedRecommendations: number;
  acceptedProgramRecommendations: number;
  methodologyStates: number;
  progressionStates: number;
  programStates: number;
  workflowRecovery: number;
}
export interface PortableImportPlan {
  schemaVersion: 1;
  valid: boolean;
  dryRun: boolean;
  mode: PortableImportMode;
  conflictPolicy: PortableConflictPolicy;
  counts: PortableCounts;
  issues: PortableIssue[];
}
export type PortableExportResult = {
  schemaVersion: 1;
  outcome: { accepted: PortableDocument } | { rejected: PortableIssue[] };
};

export interface CreateCaudexOptions {
  wasm?: WebAssembly.Module | BufferSource;
  wasmUrl?: string | URL;
  fetch?: typeof globalThis.fetch;
  clock?: ClockProvider;
  ids?: IdProvider;
  persistence?: Partial<ActiveWorkoutPersistence & MethodologyStateAcceptancePersistence & OrchestrationPersistence>;
}

export interface ActiveWorkout {
  readonly snapshot: TrackingSnapshot;
  readonly workout: TrackedWorkout;
  completeSet(setId: string, result: SetResult): Promise<TrackedWorkout>;
  completeSet(input: { membershipId: string; setId: string; actual: Metric[]; status?: "completed" | "partial" | "failed" }): Promise<TrackedWorkout>;
  complete(): Promise<CompletedWorkout>;
}

export interface SetResult {
  reps?: number;
  load?: MassMeasurement;
  rpe?: DecimalInput;
  rir?: DecimalInput;
  metrics?: readonly Metric[];
  status?: "completed" | "partial" | "failed";
}

export interface ProgramOptions {
  catalog: readonly Exercise[];
  methodology: MethodologyRef<unknown>;
  hostScopeKey: string;
  athleteProfile?: AthleteProfile;
  history?: RecommendationRequest["history"];
  methodologyState?: MethodologyState;
  methodologyStateRevision?: string | null;
}

export interface RecommendationOptions {
  asOf?: string;
  trainingContext?: TrainingContext;
  alternativeLimit?: number;
  tieBreakSeed?: string;
}

export interface Program {
  recommend(options?: RecommendationOptions): RecommendationResult;
  startWorkout(result: RecommendationResult, options?: { acceptedRecommendationId?: string }): Promise<ActiveWorkout>;
  reloadWorkout(workoutId: string): Promise<ActiveWorkout | null>;
  /** Replaces the host-authoritative history used by subsequent calls. */
  replaceHistory(history: RecommendationRequest["history"]): void;
  /** Adds or replaces one completed workout in the retained history snapshot. */
  appendCompletedWorkout(workout: CompletedWorkout): void;
  evaluate(completedWorkout: CompletedWorkout, options?: { asOf?: string; history?: EvaluationRequest["history"] }): EvaluationResult;
  acceptState(evaluation: EvaluationResult): Promise<unknown>;
}

export interface RuntimeFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  evaluate(request: EvaluationRequest): EvaluationResult;
  recommendProgram(request: ProgramRecommendationRequest): ProgramRecommendationResult;
  evaluateProgram(request: ProgramEvaluationRequest): ProgramEvaluationResult;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
}

function invalidProgramRequest(request: ProgramRecommendationRequest): ProgramRecommendationResult | null {
  const reject = (code: string, path: string, message: string): ProgramRecommendationResult => ({
    ok: false,
    issues: [{ code, path, message, severity: "error" }],
    metadata: {
      engineVersion: "unresolved", schemaVersion: 1,
      programStrategy: { id: request.program?.strategy?.id ?? "unresolved", version: "unresolved", configVersion: request.program?.strategy?.configVersion ?? 0 },
      inputFingerprint: "", resultFingerprint: "",
    },
  });
  if (request.program?.strategy?.id !== "caudex.fixed-session") return reject("program_strategy.unknown", "/program/strategy/id", "The requested program strategy is not compiled into this runtime.");
  if (request.program.strategy.configVersion !== 1 || ![undefined, "0.1.0", "^0.1.0"].includes(request.program.strategy.versionRequirement)) return reject("program_strategy.unsupported_version", "/program/strategy", "The fixed-session strategy version is unsupported.");
  if (!Array.isArray(request.program.exercises) || request.program.exercises.length === 0) return reject("program_strategy.config_invalid", "/program/exercises", "The fixed-session strategy requires at least one exercise slot.");
  const slots = new Set<string>();
  const states = new Set<string>();
  for (let index = 0; index < request.program.exercises.length; index++) {
    const slot = request.program.exercises[index];
    if (!slot?.progression?.methodology) return reject("progression.assignment_missing", `/program/exercises/${index}/progression`, "Every exercise slot requires a progression assignment.");
    if (slots.has(slot.slotId)) return reject("program_strategy.duplicate_slot_id", `/program/exercises/${index}/slotId`, "Exercise slot identities must be unique.");
    if (states.has(slot.progression.stateId)) return reject("progression.duplicate_state_id", `/program/exercises/${index}/progression/stateId`, "Progression state identities must be unique within the program request.");
    slots.add(slot.slotId); states.add(slot.progression.stateId);
    const method = slot.progression.methodology;
    if (method.id !== "caudex.double-progression" && method.id !== "caudex.rpe-top-set-backoff") return reject("progression.unknown", `/program/exercises/${index}/progression/methodology/id`, "The requested exercise progression method is not compiled into this runtime.");
    if (method.configVersion !== 1 || ![undefined, "0.1.0", "^0.1.0"].includes(method.versionRequirement)) return reject("progression.unsupported_version", `/program/exercises/${index}/progression/methodology`, "The requested exercise progression version is unsupported.");
    const capabilities = request.catalog.find((exercise) => exercise.id === slot.exerciseId)?.knowledge?.progressionCapabilities;
    if (capabilities?.externalLoad === false || capabilities?.repetitions === false) return reject("exercise.rejected.incompatible_progression", `/program/exercises/${index}`, "The exercise explicitly does not support the external-load and repetition progression required by this slot.");
    const stateData = slot.progression.state?.data as Record<string, unknown> | undefined;
    const first = Array.isArray(stateData?.exercises) ? stateData.exercises[0] as Record<string, unknown> | undefined : undefined;
    if ((method.id === "caudex.double-progression" && first?.estimatedOneRepMax !== undefined) || (method.id === "caudex.rpe-top-set-backoff" && first?.load !== undefined)) return reject("progression.state_mismatch", `/program/exercises/${index}/progression/state`, "The supplied state belongs to a different progression implementation.");
  }
  return null;
}

function invalidProfileContext(request: { athleteProfile?: AthleteProfile; trainingContext?: TrainingContext }): ValidationIssue | null {
  const profile = request.athleteProfile;
  const context = request.trainingContext;
  if (profile && !profile.id) return { code: "profile.id_required", path: "/athleteProfile/id", message: "A stable opaque profile ID is required.", severity: "error" };
  const schedule = profile?.schedule;
  if ([schedule?.preferredSessionsPerWeek, schedule?.minimumSessionsPerWeek, schedule?.maximumSessionsPerWeek].some((value) => value !== undefined && (!Number.isInteger(value) || value < 0 || value > 7)) ||
      (schedule?.minimumSessionsPerWeek !== undefined && schedule.maximumSessionsPerWeek !== undefined && schedule.minimumSessionsPerWeek > schedule.maximumSessionsPerWeek))
    return { code: "profile.frequency_invalid", path: "/athleteProfile/schedule", message: "Weekly frequency bounds must be ordered values from zero through seven.", severity: "error" };
  const duration = profile?.duration;
  if (duration?.acceptableMinimumMinutes !== undefined && duration.acceptableMaximumMinutes !== undefined && duration.acceptableMinimumMinutes > duration.acceptableMaximumMinutes)
    return { code: "profile.duration_invalid", path: "/athleteProfile/duration", message: "Duration constraints are contradictory.", severity: "error" };
  if (context?.locationId && !profile?.locations?.some((location) => location.id === context.locationId))
    return { code: "context.location_unknown", path: "/trainingContext/locationId", message: "The selected training-location profile does not exist.", severity: "error" };
  for (const id of context?.equipment?.additions ?? []) if (context?.equipment?.removals?.includes(id))
    return { code: "context.equipment_delta_conflict", path: "/trainingContext/equipment", message: "Equipment cannot be both added and removed.", severity: "error" };
  const persistentExcluded = new Set((profile?.exercisePreferences ?? []).filter((item) => item.targetKind === "exercise" && item.level === "excluded").map((item) => item.targetId));
  const excluded = new Set([...(context?.excludedExerciseIds ?? []), ...persistentExcluded]);
  for (const id of context?.requiredExerciseIds ?? []) if (excluded.has(id))
    return { code: "context.exercise_required_excluded", path: "/trainingContext", message: "An exercise cannot be both required and excluded.", severity: "error" };
  return null;
}

export interface WorkflowFacade {
  recommend(request: RecommendationRequest): RecommendationResult;
  recommendFromPersistence(input: Omit<RecommendationRequest, "catalog" | "history" | "methodologyState" | "athleteProfile"> & {
    hostScopeKey: string; athleteProfileId?: string;
  }): Promise<RecommendationResult>;
  startRecommendation(result: RecommendationResult, input: {
    catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string };
    acceptedRecommendationId?: string; methodologyStateRevision?: string; methodologyStateFingerprint?: string;
  }): Promise<ActiveWorkout>;
  startTemplate(template: WorkoutTemplateDocument, input: {
    catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string };
  }): Promise<ActiveWorkout>;
  reloadActiveWorkout(input: { hostScopeKey: string; workoutId: string; catalog: Exercise[] }): Promise<ActiveWorkout | null>;
  evaluateCompletion(request: EvaluationRequest): EvaluationResult;
  evaluateCompletionFromPersistence(input: Omit<EvaluationRequest, "catalog" | "history" | "methodologyState"> & {
    hostScopeKey: string;
  }): Promise<EvaluationResult>;
  acceptProposedState(evaluation: EvaluationResult, input: { hostScopeKey: string; expectedRevision: string | null }): Promise<unknown>;
}

export interface Caudex {
  /** Direct deterministic operations over complete canonical request snapshots. */
  readonly runtime: RuntimeFacade;
  /** Binds stable host context while constructing complete requests for every engine call. */
  createProgram(options: ProgramOptions): Program;
  recommendSession(request: RecommendationRequest): RecommendationResult;
  evaluatePerformance(request: EvaluationRequest): EvaluationResult;
  recommendProgram(request: ProgramRecommendationRequest): ProgramRecommendationResult;
  evaluateProgram(request: ProgramEvaluationRequest): ProgramEvaluationResult;
  startProgramWorkout(result: ProgramRecommendationResult, input: { catalog: Exercise[]; scope: { hostScopeKey: string; athleteId?: string }; acceptedRecommendationId?: string }): Promise<ActiveWorkout>;
  applyTrackingCommand(request: TrackingCommandRequest): TrackingCommandResult;
  applyTrackingBatch(request: TrackingBatchRequest): TrackingBatchResult;
  instantiateRecommendation(request: RecommendationInstantiationRequest): InstantiationResult;
  instantiateTemplate(request: TemplateInstantiationRequest): InstantiationResult;
  completeForEvaluation(request: CompletionConversionRequest): CompletionConversionResult;
  listMethodologies(): DiscoveryRegistry;
  describeMethodology(id: string): MethodologyDescriptor;
  listCapabilities(): DiscoveryRegistry;
  validateMethodologyConfiguration(input: { methodologyId: string; configurationSchemaVersion: number; config: JsonValue }): MethodologyValidationResult;
  validateMethodologyState(input: { methodologyId: string; configurationSchemaVersion: number; config: JsonValue; state: MethodologyState }): MethodologyValidationResult;
  exportPortable(document: PortableDocument): PortableExportResult;
  validatePortableImport(request: PortableImportRequest): PortableImportPlan;
  readonly workflows: WorkflowFacade;
  dispose(): void;
}

const STATUS_INVALID_REQUEST = 3;
const STATUS_UNSUPPORTED_VERSION = 4;
const STATUS_UNSUPPORTED_METHODOLOGY = 5;
const STATUS_INSUFFICIENT_OUTPUT = 7;

export async function createCaudex(
  options: CreateCaudexOptions = {},
): Promise<Caudex> {
  const { exports, runtime } = await initializeWasm(
    options,
    (code, message, cause) => new CaudexInitializationError(code, message, cause),
  );
  return createFacade(exports, runtime, options);
}

function createFacade(exports: WasmExports, runtime: number, options: CreateCaudexOptions): Caudex {
  let disposed = false;
  const clock = options.clock ?? { now: () => new Date().toISOString() };
  const ids = options.ids ?? { next: (kind: string) => `${kind}-${secureRandomId()}` };
  const persistence = options.persistence;
  const volatileActiveWorkouts = new Map<string, ActiveWorkoutRecord>();
  const execute = <Request, Result>(
    request: Request,
    operation: "recommend" | "evaluate" | "recommendProgram" | "evaluateProgram" | "applyTrackingCommand" | "applyTrackingBatch" | "instantiateRecommendation" | "instantiateTemplate" | "completeForEvaluation" | "listMethodologies" | "describeMethodology" | "validateMethodologyConfig" | "validateMethodologyState" | "listCapabilities" | "exportPortable" | "validatePortableImport",
    programmingResult: boolean,
  ): Result => {
    if (disposed) {
      throw new CaudexRuntimeError("The Caudex runtime has been disposed.");
    }
    let requestBytes: Uint8Array;
    try {
      requestBytes = new TextEncoder().encode(JSON.stringify({ schemaVersion: 1, operation, payload: request }));
    } catch {
      if (programmingResult) return invalidResult(
        request as RecommendationRequest | EvaluationRequest,
        "protocol.invalid_request",
        "The request is not JSON serializable.",
      ) as Result;
      throw new CaudexRuntimeError("The tracking request is not JSON serializable.", STATUS_INVALID_REQUEST);
    }

    const requestPointer = exports.caudex_wasm_alloc(requestBytes.length);
    const requiredPointer = exports.caudex_wasm_alloc(4);
    if (requestPointer === 0 || requiredPointer === 0) {
      if (requiredPointer !== 0) exports.caudex_wasm_free(requiredPointer, 4);
      if (requestPointer !== 0) {
        exports.caudex_wasm_free(requestPointer, requestBytes.length);
      }
      throw new CaudexRuntimeError("WebAssembly request allocation failed.");
    }
    try {
      new Uint8Array(
        exports.memory.buffer,
        requestPointer,
        requestBytes.length,
      ).set(requestBytes);
      new Uint8Array(exports.memory.buffer, requiredPointer, 4).fill(0);
      const sizingStatus = exports.caudex_runtime_execute(
        runtime,
        requestPointer,
        requestBytes.length,
        0,
        0,
        requiredPointer,
      );
      if (sizingStatus !== STATUS_INSUFFICIENT_OUTPUT) {
        if (programmingResult) return statusResult(
          request as RecommendationRequest | EvaluationRequest | ProgramRecommendationRequest | ProgramEvaluationRequest,
          sizingStatus,
        ) as Result;
        throw new CaudexRuntimeError("The canonical tracking request was rejected by the runtime boundary.", sizingStatus);
      }
      const resultLength = new DataView(exports.memory.buffer).getUint32(requiredPointer, true);
      const resultPointer = exports.caudex_wasm_alloc(resultLength);
      if (resultPointer === 0) throw new CaudexRuntimeError("WebAssembly result allocation failed.");
      const status = exports.caudex_runtime_execute(runtime, requestPointer, requestBytes.length, resultPointer, resultLength, requiredPointer);
      if (status !== 0) {
        exports.caudex_wasm_free(resultPointer, resultLength);
        if (programmingResult) return statusResult(
          request as RecommendationRequest | EvaluationRequest,
          status,
        ) as Result;
        throw new CaudexRuntimeError("The canonical tracking request was rejected by the runtime boundary.", status);
      }
      const resultBytes = new Uint8Array(
        exports.memory.buffer,
        resultPointer,
        resultLength,
      );
      try {
        return JSON.parse(new TextDecoder().decode(resultBytes)) as Result;
      } finally {
        exports.caudex_wasm_free(resultPointer, resultLength);
      }
    } catch (cause) {
      if (cause instanceof CaudexRuntimeError) throw cause;
      throw new CaudexRuntimeError(
        "The WebAssembly runtime returned an unreadable result.",
      );
    } finally {
      exports.caudex_wasm_free(requiredPointer, 4);
      exports.caudex_wasm_free(requestPointer, requestBytes.length);
    }
  };
  const persistSnapshot = async (hostScopeKey: string, workoutId: string, snapshot: TrackingSnapshot, expectedRevision: number | null): Promise<void> => {
    const record = { hostScopeKey, workoutId, snapshot };
    if (persistence?.saveActiveWorkout) {
      await persistence.saveActiveWorkout(record, expectedRevision);
    }
    volatileActiveWorkouts.set(`${hostScopeKey}/${workoutId}`, structuredClone(record));
  };
  const activeWorkout = (snapshot: TrackingSnapshot, workoutId: string, catalog: Exercise[]): ActiveWorkout =>
    createActiveWorkout(snapshot, workoutId, catalog, {
      clock,
      ids,
      persistence,
      applyTracking: (current, command) => execute(
        { schemaVersion: 1, snapshot: current, command },
        "applyTrackingCommand",
        false,
      ),
      convertCompletion: (workout, workoutCatalog) => execute(
        { schemaVersion: 1, workout, catalog: workoutCatalog },
        "completeForEvaluation",
        false,
      ),
      persistSnapshot,
      runtimeError: (message) => new CaudexRuntimeError(message),
      trackingRejected: (issues) => new CaudexTrackingRejectedError(issues),
    });
  const runtimeFacade: RuntimeFacade = {
    recommend: (request) => profileIssueResult<RecommendationResult>(request) ?? execute(request, "recommend", true),
    evaluate: (request) => execute(request, "evaluate", true),
    recommendProgram: (request) => profileIssueResult<ProgramRecommendationResult>(request) ?? invalidProgramRequest(request) ?? execute(request, "recommendProgram", true),
    evaluateProgram: (request) => execute(request, "evaluateProgram", true),
    applyTrackingCommand: (request) => execute(request, "applyTrackingCommand", false),
    applyTrackingBatch: (request) => execute(request, "applyTrackingBatch", false),
    instantiateRecommendation: (request) => execute(request, "instantiateRecommendation", false),
    instantiateTemplate: (request) => execute(request, "instantiateTemplate", false),
    completeForEvaluation: (request) => execute(request, "completeForEvaluation", false),
  };
  const facade: Caudex = {
    runtime: runtimeFacade,
    createProgram(programOptions) {
      return createProgramFacade(programOptions, {
        clock,
        runtime: runtimeFacade,
        workflows: facade.workflows,
        hasStatePersistence: Boolean(persistence?.compareAndSetState),
        runtimeError: (message) => new CaudexRuntimeError(message),
      });
    },
    recommendSession(request) {
      return profileIssueResult<RecommendationResult>(request) ?? execute<RecommendationRequest, RecommendationResult>(
        request,
        "recommend",
        true,
      );
    },
    evaluatePerformance(request) {
      return execute<EvaluationRequest, EvaluationResult>(
        request,
        "evaluate",
        true,
      );
    },
    recommendProgram(request) {
      return profileIssueResult<ProgramRecommendationResult>(request) ?? invalidProgramRequest(request) ?? execute<ProgramRecommendationRequest, ProgramRecommendationResult>(request, "recommendProgram", true);
    },
    evaluateProgram(request) {
      return execute<ProgramEvaluationRequest, ProgramEvaluationResult>(request, "evaluateProgram", true);
    },
    async startProgramWorkout(result, input) {
      if (!result.ok) throw new CaudexRuntimeError("A rejected program recommendation cannot start a workout.");
      const acceptedRecommendationId = input.acceptedRecommendationId ?? ids.next("acceptedRecommendation");
      const membershipIds = result.recommendation.exercises.map(() => ids.next("membership"));
      const setIds = result.recommendation.exercises.flatMap((exercise) => exercise.sets.map(() => ids.next("set")));
      const compatibilityResult: RecommendationResult = {
        ok: true,
        recommendation: result.recommendation,
        explanations: result.explanations,
        warnings: result.warnings,
        metadata: {
          engineVersion: result.metadata.engineVersion,
          schemaVersion: result.metadata.schemaVersion,
          methodology: result.metadata.programStrategy,
          inputFingerprint: result.metadata.inputFingerprint,
          resultFingerprint: result.metadata.resultFingerprint,
        },
      };
      const instantiated = execute<RecommendationInstantiationRequest, InstantiationResult>({
        schemaVersion: 1, recommendationResult: compatibilityResult, catalog: input.catalog, scope: input.scope,
        ids: { workoutId: ids.next("workout"), membershipIds, setIds },
        createdAt: clock.now(), acceptedRecommendationId,
      }, "instantiateRecommendation", false);
      if ("rejected" in instantiated.outcome) throw new CaudexTrackingRejectedError(instantiated.outcome.rejected);
      const snapshot: TrackingSnapshot = { workouts: [instantiated.outcome.accepted], startReceipts: [], exerciseCatalog: input.catalog.map((exercise) => ({ exerciseId: exercise.id, availability: "active" })) };
      await persistence?.appendAcceptedRecommendation?.({ id: acceptedRecommendationId, hostScopeKey: input.scope.hostScopeKey, acceptedAt: instantiated.outcome.accepted.startedAt, result });
      await persistSnapshot(input.scope.hostScopeKey, instantiated.outcome.accepted.id, snapshot, null);
      return activeWorkout(snapshot, instantiated.outcome.accepted.id, input.catalog);
    },
    applyTrackingCommand(request) {
      return execute<TrackingCommandRequest, TrackingCommandResult>(request, "applyTrackingCommand", false);
    },
    applyTrackingBatch(request) {
      return execute<TrackingBatchRequest, TrackingBatchResult>(request, "applyTrackingBatch", false);
    },
    instantiateRecommendation(request) {
      return execute<RecommendationInstantiationRequest, InstantiationResult>(request, "instantiateRecommendation", false);
    },
    instantiateTemplate(request) {
      return execute<TemplateInstantiationRequest, InstantiationResult>(request, "instantiateTemplate", false);
    },
    completeForEvaluation(request) {
      return execute<CompletionConversionRequest, CompletionConversionResult>(request, "completeForEvaluation", false);
    },
    listMethodologies() {
      return execute<{ schemaVersion: 1 }, DiscoveryRegistry>({ schemaVersion: 1 }, "listMethodologies", false);
    },
    describeMethodology(id) {
      const result = execute<{ schemaVersion: 1; id: string }, { schemaVersion: 1; methodology: MethodologyDescriptor }>({ schemaVersion: 1, id }, "describeMethodology", false);
      return result.methodology;
    },
    listCapabilities() {
      return execute<{ schemaVersion: 1 }, DiscoveryRegistry>({ schemaVersion: 1 }, "listCapabilities", false);
    },
    validateMethodologyConfiguration(input) {
      return execute<typeof input & { schemaVersion: 1 }, MethodologyValidationResult>({ schemaVersion: 1, ...input }, "validateMethodologyConfig", false);
    },
    validateMethodologyState(input) {
      return execute<typeof input & { schemaVersion: 1 }, MethodologyValidationResult>({ schemaVersion: 1, ...input }, "validateMethodologyState", false);
    },
    exportPortable(document) {
      return execute<PortableDocument, PortableExportResult>(document, "exportPortable", false);
    },
    validatePortableImport(request) {
      return execute<PortableImportRequest, PortableImportPlan>(request, "validatePortableImport", false);
    },
    workflows: {
      recommend(request) {
        return profileIssueResult<RecommendationResult>(request) ?? execute<RecommendationRequest, RecommendationResult>(request, "recommend", true);
      },
      async recommendFromPersistence(input) {
        if (!persistence?.loadCatalog || !persistence.loadHistory) {
          throw new CaudexRuntimeError("Catalog and history persistence capabilities are required.");
        }
        if (input.athleteProfileId && !persistence.loadAthleteProfile) throw new CaudexRuntimeError("Athlete-profile persistence is required when athleteProfileId is supplied.");
        const [catalog, history, stateRecord, profileRecord] = await Promise.all([
          persistence.loadCatalog({ hostScopeKey: input.hostScopeKey, asOf: input.asOf }),
          persistence.loadHistory({ hostScopeKey: input.hostScopeKey, through: input.asOf }),
          persistence.loadState?.({
            hostScopeKey: input.hostScopeKey,
            methodologyId: input.methodology.id,
          }) ?? Promise.resolve(null),
          input.athleteProfileId ? persistence.loadAthleteProfile?.({ hostScopeKey: input.hostScopeKey, athleteProfileId: input.athleteProfileId }) : Promise.resolve(null),
        ]);
        const { hostScopeKey: _, athleteProfileId: __, ...request } = input;
        return execute<RecommendationRequest, RecommendationResult>({
          ...request,
          catalog: [...catalog],
          history: { ...history, workouts: [...history.workouts] },
          methodologyState: stateRecord?.state,
          ...(input.athleteProfileId ? { athleteProfile: profileRecord?.profile } : {}),
        }, "recommend", true);
      },
      async startRecommendation(result, input) {
        const acceptedRecommendationId = input.acceptedRecommendationId ?? ids.next("acceptedRecommendation");
        const workflowId = `recommendation:${acceptedRecommendationId}`;
        const existing = await persistence?.loadWorkflowRecovery?.(input.scope.hostScopeKey, workflowId);
        if (existing) {
          const recovered = parseInstantiationRecovery(existing);
          if (existing.status === "pending") {
            await persistence?.appendAcceptedRecommendation?.({
              id: acceptedRecommendationId,
              hostScopeKey: input.scope.hostScopeKey,
              acceptedAt: recovered.workout.startedAt,
              result,
            });
            await persistSnapshot(input.scope.hostScopeKey, recovered.workout.id, recovered.snapshot, null);
            await persistence?.saveWorkflowRecovery?.({ ...existing, status: "completed", updatedAt: clock.now() });
          }
          return activeWorkout(recovered.snapshot, recovered.workout.id, input.catalog);
        }
        const recommendation = result.recommendation;
        const membershipIds = recommendation?.exercises.map(() => ids.next("membership")) ?? [];
        const setIds = recommendation?.exercises.flatMap((exercise) => exercise.sets.map(() => ids.next("set"))) ?? [];
        const instantiated = execute<RecommendationInstantiationRequest, InstantiationResult>({
          schemaVersion: 1,
          recommendationResult: result,
          catalog: input.catalog,
          scope: input.scope,
          ids: { workoutId: ids.next("workout"), membershipIds, setIds },
          createdAt: clock.now(),
          acceptedRecommendationId,
          methodologyStateRevision: input.methodologyStateRevision,
          methodologyStateFingerprint: input.methodologyStateFingerprint,
        }, "instantiateRecommendation", false);
        if ("rejected" in instantiated.outcome) throw new CaudexTrackingRejectedError(instantiated.outcome.rejected);
        const snapshot: TrackingSnapshot = {
          workouts: [instantiated.outcome.accepted],
          startReceipts: [],
          exerciseCatalog: input.catalog.map((exercise) => ({ exerciseId: exercise.id, availability: "active" })),
        };
        const recovery: WorkflowRecoveryRecord = {
          hostScopeKey: input.scope.hostScopeKey,
          workflowId,
          kind: "recommendation_instantiation",
          status: "pending",
          idempotencyKey: acceptedRecommendationId,
          payload: { workout: instantiated.outcome.accepted, snapshot } as unknown as JsonValue,
          updatedAt: clock.now(),
        };
        await persistence?.saveWorkflowRecovery?.(recovery);
        await persistence?.appendAcceptedRecommendation?.({
          id: acceptedRecommendationId,
          hostScopeKey: input.scope.hostScopeKey,
          acceptedAt: instantiated.outcome.accepted.startedAt,
          result,
        });
        await persistSnapshot(input.scope.hostScopeKey, instantiated.outcome.accepted.id, snapshot, null);
        await persistence?.saveWorkflowRecovery?.({ ...recovery, status: "completed", updatedAt: clock.now() });
        return activeWorkout(snapshot, instantiated.outcome.accepted.id, input.catalog);
      },
      async startTemplate(template, input) {
        const membershipIds = template.exercises.map(() => ids.next("membership"));
        const setIds = template.exercises.flatMap((exercise) => (exercise.sets ?? []).map(() => ids.next("set")));
        const instantiated = execute<TemplateInstantiationRequest, InstantiationResult>({
          schemaVersion: 1,
          template,
          catalog: input.catalog,
          scope: input.scope,
          ids: { workoutId: ids.next("workout"), membershipIds, setIds },
          createdAt: clock.now(),
        }, "instantiateTemplate", false);
        if ("rejected" in instantiated.outcome) throw new CaudexTrackingRejectedError(instantiated.outcome.rejected);
        const snapshot: TrackingSnapshot = {
          workouts: [instantiated.outcome.accepted],
          startReceipts: [],
          exerciseCatalog: input.catalog.map((exercise) => ({ exerciseId: exercise.id, availability: "active" })),
        };
        await persistSnapshot(input.scope.hostScopeKey, instantiated.outcome.accepted.id, snapshot, null);
        return activeWorkout(snapshot, instantiated.outcome.accepted.id, input.catalog);
      },
      async reloadActiveWorkout(input) {
        const record = persistence?.loadActiveWorkout
          ? await persistence.loadActiveWorkout(input.hostScopeKey, input.workoutId)
          : volatileActiveWorkouts.get(`${input.hostScopeKey}/${input.workoutId}`) ?? null;
        return record ? activeWorkout(record.snapshot, record.workoutId, input.catalog) : null;
      },
      evaluateCompletion(request) {
        return execute<EvaluationRequest, EvaluationResult>(request, "evaluate", true);
      },
      async evaluateCompletionFromPersistence(input) {
        if (!persistence?.loadCatalog || !persistence.loadHistory) {
          throw new CaudexRuntimeError("Catalog and history persistence capabilities are required.");
        }
        const [catalog, history, stateRecord] = await Promise.all([
          persistence.loadCatalog({ hostScopeKey: input.hostScopeKey, asOf: input.asOf }),
          persistence.loadHistory({ hostScopeKey: input.hostScopeKey, through: input.asOf }),
          persistence.loadState?.({
            hostScopeKey: input.hostScopeKey,
            methodologyId: input.methodology.id,
          }) ?? Promise.resolve(null),
        ]);
        const { hostScopeKey: _, ...request } = input;
        return execute<EvaluationRequest, EvaluationResult>({
          ...request,
          catalog: [...catalog],
          history: { ...history, workouts: [...history.workouts] },
          methodologyState: stateRecord?.state,
        }, "evaluate", true);
      },
      async acceptProposedState(evaluation, input) {
        if (!evaluation.ok || !evaluation.nextMethodologyState) {
          throw new CaudexRuntimeError("The evaluation has no methodology-state proposal to accept.");
        }
        if (!persistence?.compareAndSetState) {
          throw new CaudexRuntimeError("No methodology-state persistence capability was supplied.");
        }
        return persistence.compareAndSetState({
          key: { hostScopeKey: input.hostScopeKey, methodologyId: evaluation.metadata.methodology.id },
          expectedRevision: input.expectedRevision,
          methodologyVersion: evaluation.metadata.methodology.version,
          nextState: evaluation.nextMethodologyState,
          updatedAt: clock.now(),
        });
      },
    },
    dispose() {
      if (!disposed) {
        exports.caudex_wasm_runtime_destroy(runtime);
        disposed = true;
      }
    },
  };
  return facade;
}

function secureRandomId(): string {
  const crypto = globalThis.crypto;
  if (!crypto?.randomUUID) throw new CaudexRuntimeError("Secure platform randomness is unavailable; inject an ID provider.");
  return crypto.randomUUID();
}

function parseInstantiationRecovery(record: WorkflowRecoveryRecord): {
  workout: TrackedWorkout;
  snapshot: TrackingSnapshot;
} {
  if (record.kind !== "recommendation_instantiation") {
    throw new CaudexRuntimeError("The workflow recovery record has an unexpected kind.");
  }
  try {
    const value = record.payload as {
      workout?: TrackedWorkout;
      snapshot?: TrackingSnapshot;
    };
    if (!value.workout?.id || !Array.isArray(value.snapshot?.workouts)) {
      throw new Error("missing workout snapshot");
    }
    return { workout: value.workout, snapshot: value.snapshot };
  } catch {
    throw new CaudexRuntimeError("The workflow recovery record is malformed.");
  }
}

function statusResult<Result extends RecommendationResult | EvaluationResult | ProgramRecommendationResult | ProgramEvaluationResult>(
  request: RecommendationRequest | EvaluationRequest | ProgramRecommendationRequest | ProgramEvaluationRequest,
  status: number,
): Result {
  if (status === STATUS_INVALID_REQUEST) {
    return invalidResult<Result>(
      request,
      "protocol.invalid_request",
      "The canonical request is invalid.",
    );
  }
  if (status === STATUS_UNSUPPORTED_VERSION) {
    return invalidResult<Result>(
      request,
      "protocol.unsupported_version",
      "A requested protocol or methodology version is unsupported.",
    );
  }
  if (status === STATUS_UNSUPPORTED_METHODOLOGY) {
    return invalidResult<Result>(
      request,
      "methodology.unsupported",
      "The requested methodology is not compiled into this runtime.",
    );
  }
  throw new CaudexRuntimeError(
    `The WebAssembly runtime could not complete the request (status ${status}).`,
    status,
  );
}

function invalidResult<
  Result extends RecommendationResult | EvaluationResult | ProgramRecommendationResult | ProgramEvaluationResult,
>(
  request: RecommendationRequest | EvaluationRequest | ProgramRecommendationRequest | ProgramEvaluationRequest,
  code: string,
  message: string,
): Result {
  const programRequest = "program" in request || "recommendation" in request;
  const metadata = programRequest ? {
    engineVersion: "unresolved",
    schemaVersion: 1,
    programStrategy: {
      id: "program" in request ? request.program?.strategy?.id ?? "unresolved" : request.recommendation?.programming?.strategy?.id ?? "unresolved",
      version: "unresolved",
      configVersion: "program" in request ? request.program?.strategy?.configVersion ?? 0 : request.recommendation?.programming?.strategy?.configVersion ?? 0,
    },
    inputFingerprint: "",
    resultFingerprint: "",
  } : {
    engineVersion: "unresolved",
    schemaVersion: 1,
    methodology: {
      id: "methodology" in request ? request.methodology?.id ?? "unresolved" : "unresolved",
      version: "unresolved",
      configVersion: "methodology" in request ? request.methodology?.configVersion ?? 0 : 0,
    },
    inputFingerprint: "",
    resultFingerprint: "",
  };
  return {
    ok: false,
    explanations: [],
    warnings: [],
    issues: [
      {
        code,
        path: "/",
        message,
        severity: "error",
      },
    ],
    metadata,
  } as unknown as Result;
}

function profileIssueResult<Result extends RecommendationResult | ProgramRecommendationResult>(request: RecommendationRequest | ProgramRecommendationRequest): Result | null {
  const issue = invalidProfileContext(request);
  if (!issue) return null;
  const result = invalidResult<Result>(request, issue.code, issue.message);
  result.issues = [issue];
  return result;
}
