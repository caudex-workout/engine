import type { JsonValue, MusclePriority, ProgramExerciseSlot, ProgramStrategyRef, ProgramStrategyState, ProgramTrainingContext, ProgressionCapabilities, ProgressionAssignment, ValidationIssue } from "./index.js";

export type ProgramWeekday = "monday" | "tuesday" | "wednesday" | "thursday" | "friday" | "saturday" | "sunday";
export interface RollingProgramSchedule { kind: "rolling"; roleIds: string[] }
export interface FixedWeekdayProgramSchedule { kind: "fixed_weekdays"; sessions: Array<{ weekday: ProgramWeekday; roleId: string }> }
export interface FrequencyTargetedProgramSchedule { kind: "frequency_targeted"; sessionsPerMicrocycle: number; roleIds: string[] }
export interface ExplicitDatesProgramSchedule { kind: "explicit_dates"; sessions: Array<{ date: string; roleId: string }> }
export interface HybridProgramSchedule { kind: "hybrid"; roleIds: string[]; overrides: Array<{ occurrenceId: string; roleId: string }> }
export type ProgramSchedule = RollingProgramSchedule | FixedWeekdayProgramSchedule | FrequencyTargetedProgramSchedule | ExplicitDatesProgramSchedule | HybridProgramSchedule;

export interface FixedProgramSlot<TConfig = JsonValue> {
  kind: "fixed";
  slotId: string;
  exerciseId: string;
  progression: ProgressionAssignment<TConfig>;
}
/** A host-resolved slot; Caudex validates the choice but does not rank candidates. */
export interface DynamicProgramSlot<TConfig = JsonValue> {
  kind: "dynamic";
  slotId: string;
  candidateExerciseIds?: string[];
  criteria?: {
    movementPatterns?: string[];
    muscleIds?: string[];
    equipmentIds?: string[];
    excludedExerciseIds?: string[];
    requiredCapabilities?: ProgressionCapabilities;
  };
  progression: ProgressionAssignment<TConfig>;
}
export type ProgramSlot<TConfig = JsonValue> = FixedProgramSlot<TConfig> | DynamicProgramSlot<TConfig>;
export interface ProgramSessionRole {
  id: string;
  displayName?: string;
  description?: string;
  slots: ProgramSlot[];
  trainingContext?: ProgramTrainingContext;
  configuration?: JsonValue;
}
export interface ProgramBlock {
  id: string;
  displayName?: string;
  description?: string;
  microcycleCount: number;
  phase?: "accumulation" | "intensification" | "realization" | "deload" | "custom";
  musclePriorities?: MusclePriority[];
  schedule: ProgramSchedule;
  sessionRoles: ProgramSessionRole[];
  configuration?: JsonValue;
}
export interface ProgramDefinitionSource { kind: "built_in_preset" | "host_custom" | "imported"; id?: string; version?: string }
export interface ProgramDefinitionReference { id: string; version: string; configurationFingerprint: string }
export interface ProgramDefinition {
  schemaVersion: 1;
  id: string;
  version: string;
  displayName: string;
  description?: string;
  strategy: ProgramStrategyRef;
  configurationFingerprint: string;
  source?: ProgramDefinitionSource;
  blocks: ProgramBlock[];
}
export type ProgramDefinitionInput = Omit<ProgramDefinition, "schemaVersion" | "configurationFingerprint"> & { schemaVersion?: 1 };
export type ProgramInstanceLifecycle = "planned" | "active" | "paused" | "completed" | "abandoned";
export interface ProgramInstance {
  schemaVersion: 1;
  id: string;
  athleteId: string;
  definition: ProgramDefinitionReference;
  startedOn?: string;
  lifecycle: ProgramInstanceLifecycle;
  configuration: JsonValue;
}
export interface ProgramState {
  schemaVersion: 1;
  instanceId: string;
  definition: ProgramDefinitionReference;
  revision: number;
  blockIndex: number;
  microcycleIndex: number;
  sessionCursor: number;
  completedOccurrenceCount: number;
  completed: boolean;
  strategyState?: ProgramStrategyState;
}
export interface ProgramOccurrence { id: string; weekday?: ProgramWeekday; date?: string }
export interface PlannedSessionIntent {
  schemaVersion: 1;
  instanceId: string;
  definition: ProgramDefinitionReference;
  blockId: string;
  phase?: ProgramBlock["phase"];
  musclePriorities?: MusclePriority[];
  roleId: string;
  occurrenceId: string;
  planningStateRevision: number;
  program: {
    strategy: ProgramStrategyRef;
    state?: ProgramStrategyState;
    exercises: ProgramExerciseSlot[];
    trainingContext?: ProgramTrainingContext;
  };
}
export interface ProgramOccurrenceRecord {
  schemaVersion: 1;
  instanceId: string;
  definition: ProgramDefinitionReference;
  blockId: string;
  roleId: string;
  occurrenceId: string;
  status: "completed" | "skipped";
  beforeRevision: number;
  afterRevision: number;
}
export interface ProgramStateProposal {
  schemaVersion: 1;
  instanceId: string;
  definition: ProgramDefinitionReference;
  expectedRevision: number;
  nextState: ProgramState;
  occurrence: ProgramOccurrenceRecord;
}
export type ProgramValidationResult = { valid: true; issues: [] } | { valid: false; issues: ValidationIssue[] };
export declare class ProgramDefinitionError extends TypeError {
  readonly issues: ValidationIssue[];
  constructor(issues: ValidationIssue[]);
}
export declare function defineProgram(input: ProgramDefinitionInput): ProgramDefinition;
export declare function validateProgram(definition: ProgramDefinition): ProgramValidationResult;
export declare function instantiateProgram(definition: ProgramDefinition, input: {
  instanceId: string;
  athleteId: string;
  startedOn?: string;
  lifecycle?: ProgramInstanceLifecycle;
  configuration?: JsonValue;
  strategyState?: ProgramStrategyState;
}): { instance: ProgramInstance; state: ProgramState };
export declare function resolveNextSession(input: {
  definition: ProgramDefinition;
  instance: ProgramInstance;
  state: ProgramState;
  occurrence: ProgramOccurrence;
  dynamicSelections?: Readonly<Record<string, string>>;
}): PlannedSessionIntent;
export declare function proposeProgramAdvancement(input: {
  definition: ProgramDefinition;
  instance: ProgramInstance;
  state: ProgramState;
  intent: PlannedSessionIntent;
  status: "completed" | "skipped";
  nextStrategyState?: ProgramStrategyState;
}): ProgramStateProposal;
export declare function acceptProgramAdvancement(current: ProgramState, proposal: ProgramStateProposal): ProgramState;

export interface StructuralPresetOptions {
  id: string;
  version: string;
  strategy: ProgramStrategyRef;
  displayName?: string;
}
export declare const programs: {
  readonly slots: {
    readonly fixed: <TConfig = JsonValue>(slot: Omit<FixedProgramSlot<TConfig>, "kind">) => FixedProgramSlot<TConfig>;
    readonly dynamic: <TConfig = JsonValue>(slot: Omit<DynamicProgramSlot<TConfig>, "kind">) => DynamicProgramSlot<TConfig>;
  };
  readonly schedules: {
    readonly rolling: (roleIds: readonly string[]) => RollingProgramSchedule;
    readonly fixedWeekdays: (sessions: readonly { weekday: ProgramWeekday; roleId: string }[]) => FixedWeekdayProgramSchedule;
    readonly frequencyTargeted: (sessionsPerMicrocycle: number, roleIds: readonly string[]) => FrequencyTargetedProgramSchedule;
    readonly explicitDates: (sessions: readonly { date: string; roleId: string }[]) => ExplicitDatesProgramSchedule;
    readonly hybrid: (roleIds: readonly string[], overrides: readonly { occurrenceId: string; roleId: string }[]) => HybridProgramSchedule;
  };
  readonly validate: typeof validateProgram;
  readonly presets: {
    readonly asynchronousUpperLower: (options: StructuralPresetOptions) => ProgramDefinition;
    readonly fixedWeekdayUpperLower: (options: StructuralPresetOptions) => ProgramDefinition;
    readonly pplRotation: (options: StructuralPresetOptions) => ProgramDefinition;
    readonly structuredHypertrophyBlock: (options: StructuralPresetOptions) => ProgramDefinition;
  };
};
