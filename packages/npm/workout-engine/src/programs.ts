import type {
  JsonValue,
  ProgramExerciseSlot,
  ProgramStrategyRef,
  ProgramStrategyState,
  ProgramTrainingContext,
  ProgressionCapabilities,
  ProgressionAssignment,
  MusclePriority,
  ValidationIssue,
} from "./index.ts";

export type ProgramWeekday =
  | "monday"
  | "tuesday"
  | "wednesday"
  | "thursday"
  | "friday"
  | "saturday"
  | "sunday";

export interface RollingProgramSchedule {
  kind: "rolling";
  roleIds: string[];
}

export interface FixedWeekdayProgramSchedule {
  kind: "fixed_weekdays";
  sessions: Array<{ weekday: ProgramWeekday; roleId: string }>;
}

export interface FrequencyTargetedProgramSchedule {
  kind: "frequency_targeted";
  sessionsPerMicrocycle: number;
  roleIds: string[];
}

export interface ExplicitDatesProgramSchedule {
  kind: "explicit_dates";
  sessions: Array<{ date: string; roleId: string }>;
}

/** A rolling base sequence with host-authored exceptions by occurrence ID. */
export interface HybridProgramSchedule {
  kind: "hybrid";
  roleIds: string[];
  overrides: Array<{ occurrenceId: string; roleId: string }>;
}

export type ProgramSchedule =
  | RollingProgramSchedule
  | FixedWeekdayProgramSchedule
  | FrequencyTargetedProgramSchedule
  | ExplicitDatesProgramSchedule
  | HybridProgramSchedule;

export interface FixedProgramSlot<TConfig = JsonValue> {
  kind: "fixed";
  slotId: string;
  exerciseId: string;
  progression: ProgressionAssignment<TConfig>;
}

/**
 * A host-resolved slot. Caudex validates the supplied choice but does not rank
 * candidates or duplicate a program strategy's recommendation algorithm.
 */
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

export type ProgramSlot<TConfig = JsonValue> =
  | FixedProgramSlot<TConfig>
  | DynamicProgramSlot<TConfig>;

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

export interface ProgramDefinitionSource {
  kind: "built_in_preset" | "host_custom" | "imported";
  id?: string;
  version?: string;
}

export interface ProgramDefinitionReference {
  id: string;
  version: string;
  configurationFingerprint: string;
}

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

export type ProgramDefinitionInput = Omit<
  ProgramDefinition,
  "schemaVersion" | "configurationFingerprint"
> & {
  schemaVersion?: 1;
};

export type ProgramInstanceLifecycle =
  | "planned"
  | "active"
  | "paused"
  | "completed"
  | "abandoned";

export interface ProgramInstance {
  schemaVersion: 1;
  id: string;
  athleteId: string;
  definition: ProgramDefinitionReference;
  startedOn?: string;
  lifecycle: ProgramInstanceLifecycle;
  configuration: JsonValue;
}

/** Explicit host-owned planning cursor. It is never mutated by an operation. */
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

export interface ProgramOccurrence {
  id: string;
  /** Required for fixed-weekday schedules; interpreted by the host. */
  weekday?: ProgramWeekday;
  /** Required for explicit-date schedules; interpreted by the host. */
  date?: string;
}

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

export type ProgramValidationResult =
  | { valid: true; issues: [] }
  | { valid: false; issues: ValidationIssue[] };

export class ProgramDefinitionError extends TypeError {
  readonly issues: ValidationIssue[];

  constructor(issues: ValidationIssue[]) {
    super(issues[0]?.message ?? "The program definition is invalid.");
    this.name = "ProgramDefinitionError";
    this.issues = issues;
  }
}

/** Defines and snapshots a reusable program blueprint. */
export function defineProgram(input: ProgramDefinitionInput): ProgramDefinition {
  const withoutFingerprint = clone({ schemaVersion: 1 as const, ...input });
  const definition: ProgramDefinition = {
    ...withoutFingerprint,
    configurationFingerprint: fingerprint(withoutFingerprint),
  };
  const validation = validateProgram(definition);
  if (!validation.valid) throw new ProgramDefinitionError(validation.issues);
  return clone(definition);
}

/** Returns every structural issue without partially instantiating a program. */
export function validateProgram(definition: ProgramDefinition): ProgramValidationResult {
  const issues: ValidationIssue[] = [];
  requiredId(issues, definition.id, "$.id", "definition");
  requiredId(issues, definition.version, "$.version", "definition version");
  requiredId(issues, definition.displayName, "$.displayName", "display name");
  requiredId(issues, definition.strategy?.id, "$.strategy.id", "program strategy");
  positiveInteger(issues, definition.strategy?.configVersion, "$.strategy.configVersion", "strategy config version");
  if (definition.schemaVersion !== 1) issue(issues, "program.schema_version_unsupported", "$.schemaVersion", "Program schemaVersion must be 1.");
  if (!Array.isArray(definition.blocks) || definition.blocks.length === 0) {
    issue(issues, "program.blocks_required", "$.blocks", "A program must define at least one block.");
  } else if (definition.blocks.length > 64) {
    issue(issues, "program.bounds_exceeded", "$.blocks", "A program may define at most 64 blocks.");
  }

  duplicateIds(issues, definition.blocks ?? [], "$.blocks", "block");
  for (const [blockIndex, block] of (definition.blocks ?? []).entries()) {
    const blockPath = `$.blocks[${blockIndex}]`;
    requiredId(issues, block.id, `${blockPath}.id`, "block");
    positiveInteger(issues, block.microcycleCount, `${blockPath}.microcycleCount`, "microcycle count", 52);
    if (!Array.isArray(block.sessionRoles) || block.sessionRoles.length === 0) {
      issue(issues, "program.roles_required", `${blockPath}.sessionRoles`, "A block must define at least one session role.");
      continue;
    }
    if (block.sessionRoles.length > 32) issue(issues, "program.bounds_exceeded", `${blockPath}.sessionRoles`, "A block may define at most 32 session roles.");
    duplicateIds(issues, block.sessionRoles, `${blockPath}.sessionRoles`, "role");
    const roles = new Set(block.sessionRoles.map((role) => role.id));
    const schedule = block.schedule;
    const scheduledRoles = scheduleRoleIds(schedule);
    if (scheduledRoles.length === 0) issue(issues, "program.schedule_empty", `${blockPath}.schedule`, "A block schedule must contain at least one session.");
    if (scheduledRoles.length > 32) issue(issues, "program.bounds_exceeded", `${blockPath}.schedule`, "A block schedule may contain at most 32 sessions.");
    for (const [scheduleIndex, roleId] of scheduledRoles.entries()) {
      if (!roles.has(roleId)) issue(issues, "program.schedule_unknown_role", `${blockPath}.schedule[${scheduleIndex}]`, `Schedule references unknown role: ${roleId}`);
    }
    if (schedule?.kind === "fixed_weekdays") {
      const seenDays = new Set<ProgramWeekday>();
      for (const [sessionIndex, session] of schedule.sessions.entries()) {
        if (seenDays.has(session.weekday)) issue(issues, "program.schedule_duplicate_weekday", `${blockPath}.schedule.sessions[${sessionIndex}].weekday`, `Weekday is scheduled more than once: ${session.weekday}`);
        seenDays.add(session.weekday);
      }
    } else if (schedule?.kind === "frequency_targeted") {
      positiveInteger(issues, schedule.sessionsPerMicrocycle, `${blockPath}.schedule.sessionsPerMicrocycle`, "target session frequency", 32);
    } else if (schedule?.kind === "explicit_dates") {
      if (block.microcycleCount !== 1) issue(issues, "program.explicit_dates_block_length", `${blockPath}.microcycleCount`, "An explicit-date block must use one microcycle because its dates do not repeat.");
      const dates = new Set<string>();
      for (const [sessionIndex, session] of schedule.sessions.entries()) {
        requiredId(issues, session.date, `${blockPath}.schedule.sessions[${sessionIndex}].date`, "explicit date");
        if (dates.has(session.date)) issue(issues, "program.schedule_duplicate_date", `${blockPath}.schedule.sessions[${sessionIndex}].date`, `Date is scheduled more than once: ${session.date}`);
        dates.add(session.date);
      }
    } else if (schedule?.kind === "hybrid") {
      const occurrences = new Set<string>();
      for (const [overrideIndex, override] of schedule.overrides.entries()) {
        requiredId(issues, override.occurrenceId, `${blockPath}.schedule.overrides[${overrideIndex}].occurrenceId`, "hybrid occurrence");
        if (occurrences.has(override.occurrenceId)) issue(issues, "program.schedule_duplicate_override", `${blockPath}.schedule.overrides[${overrideIndex}].occurrenceId`, `Occurrence is overridden more than once: ${override.occurrenceId}`);
        occurrences.add(override.occurrenceId);
      }
    } else if (schedule?.kind !== "rolling") {
      issue(issues, "program.schedule_kind_unsupported", `${blockPath}.schedule.kind`, "Schedule kind is unsupported.");
    }

    for (const [roleIndex, role] of block.sessionRoles.entries()) {
      const rolePath = `${blockPath}.sessionRoles[${roleIndex}]`;
      requiredId(issues, role.id, `${rolePath}.id`, "role");
      if (!Array.isArray(role.slots)) {
        issue(issues, "program.slots_invalid", `${rolePath}.slots`, "Role slots must be an array.");
        continue;
      }
      if (role.slots.length > 32) issue(issues, "program.bounds_exceeded", `${rolePath}.slots`, "A session role may define at most 32 slots.");
      duplicateIds(issues, role.slots, `${rolePath}.slots`, "slot");
      const stateIds = new Set<string>();
      for (const [slotIndex, slot] of role.slots.entries()) {
        const slotPath = `${rolePath}.slots[${slotIndex}]`;
        requiredId(issues, slot.slotId, `${slotPath}.slotId`, "slot");
        requiredId(issues, slot.progression?.stateId, `${slotPath}.progression.stateId`, "progression state");
        requiredId(issues, slot.progression?.methodology?.id, `${slotPath}.progression.methodology.id`, "progression methodology");
        positiveInteger(issues, slot.progression?.methodology?.configVersion, `${slotPath}.progression.methodology.configVersion`, "progression config version");
        if (stateIds.has(slot.progression?.stateId)) issue(issues, "program.duplicate_state_id", `${slotPath}.progression.stateId`, `Progression state identity is ambiguous within the role: ${slot.progression?.stateId}`);
        stateIds.add(slot.progression?.stateId);
        if (slot.kind === "fixed") {
          requiredId(issues, slot.exerciseId, `${slotPath}.exerciseId`, "exercise");
        } else if (slot.kind === "dynamic") {
          const candidates = slot.candidateExerciseIds ?? [];
          const hasCriteria = slot.criteria !== undefined && Object.values(slot.criteria).some((value) => value !== undefined);
          if (candidates.length === 0 && !hasCriteria) {
            issue(issues, "program.dynamic_selection_required", slotPath, "A dynamic slot must declare candidates, selection criteria, or both.");
          } else if (new Set(candidates).size !== candidates.length) {
            issue(issues, "program.dynamic_candidates_duplicate", `${slotPath}.candidateExerciseIds`, "Dynamic slot candidates must be unique.");
          }
        } else {
          issue(issues, "program.slot_kind_unsupported", `${slotPath}.kind`, "Slot kind must be fixed or dynamic.");
        }
      }
    }
  }

  if (definition.configurationFingerprint) {
    const { configurationFingerprint: ignored, ...content } = definition;
    void ignored;
    if (definition.configurationFingerprint !== fingerprint(content)) {
      issue(issues, "program.fingerprint_mismatch", "$.configurationFingerprint", "Program definition content does not match its fingerprint.");
    }
  } else {
    issue(issues, "program.fingerprint_required", "$.configurationFingerprint", "Program definition fingerprint is required.");
  }
  return issues.length === 0 ? { valid: true, issues: [] } : { valid: false, issues };
}

export function instantiateProgram(
  definition: ProgramDefinition,
  input: {
    instanceId: string;
    athleteId: string;
    startedOn?: string;
    lifecycle?: ProgramInstanceLifecycle;
    configuration?: JsonValue;
    strategyState?: ProgramStrategyState;
  },
): { instance: ProgramInstance; state: ProgramState } {
  const validation = validateProgram(definition);
  if (!validation.valid) throw new ProgramDefinitionError(validation.issues);
  if (!input.instanceId) throw new TypeError("Program instance id is required.");
  if (!input.athleteId) throw new TypeError("Program athlete id is required.");
  const reference = definitionReference(definition);
  return clone({
    instance: {
      schemaVersion: 1 as const,
      id: input.instanceId,
      athleteId: input.athleteId,
      definition: reference,
      startedOn: input.startedOn,
      lifecycle: input.lifecycle ?? "planned",
      configuration: input.configuration ?? {},
    },
    state: {
      schemaVersion: 1 as const,
      instanceId: input.instanceId,
      definition: reference,
      revision: 0,
      blockIndex: 0,
      microcycleIndex: 0,
      sessionCursor: 0,
      completedOccurrenceCount: 0,
      completed: false,
      strategyState: input.strategyState,
    },
  });
}

export function resolveNextSession(input: {
  definition: ProgramDefinition;
  instance: ProgramInstance;
  state: ProgramState;
  occurrence: ProgramOccurrence;
  dynamicSelections?: Readonly<Record<string, string>>;
}): PlannedSessionIntent {
  assertSnapshots(input.definition, input.instance, input.state);
  if (!input.occurrence.id) throw new TypeError("Program occurrence id is required.");
  if (input.state.completed) throw new TypeError("The program state is complete and has no next session.");
  const block = input.definition.blocks[input.state.blockIndex];
  if (!block) throw new TypeError("Program state references an unknown block.");
  const scheduled = scheduleEntries(block.schedule, input.occurrence);
  const scheduledEntry = scheduled[input.state.sessionCursor];
  const hybridOverride = block.schedule.kind === "hybrid"
    ? block.schedule.overrides.find((candidate) => candidate.occurrenceId === input.occurrence.id)
    : undefined;
  const expected = scheduledEntry && hybridOverride
    ? { ...scheduledEntry, roleId: hybridOverride.roleId }
    : scheduledEntry;
  if (!expected) throw new TypeError("Program state session cursor is outside the block schedule.");
  if (block.schedule.kind === "fixed_weekdays" && input.occurrence.weekday !== expected.weekday) {
    throw new TypeError(`The next fixed-weekday occurrence must be ${expected.weekday}.`);
  }
  if (block.schedule.kind === "explicit_dates" && input.occurrence.date !== expected.date) {
    throw new TypeError(`The next explicit-date occurrence must be ${expected.date}.`);
  }
  const role = block.sessionRoles.find((candidate) => candidate.id === expected.roleId);
  if (!role) throw new TypeError(`Program schedule references unknown role: ${expected.roleId}`);
  const exercises = role.slots.map((slot): ProgramExerciseSlot => {
    const exerciseId = slot.kind === "fixed"
      ? slot.exerciseId
      : input.dynamicSelections?.[slot.slotId];
    if (!exerciseId) throw new TypeError(`Dynamic program slot requires an explicit selection: ${slot.slotId}`);
    if (slot.kind === "dynamic" && slot.candidateExerciseIds?.length && !slot.candidateExerciseIds.includes(exerciseId)) {
      throw new TypeError(`Exercise ${exerciseId} is not a candidate for dynamic slot ${slot.slotId}.`);
    }
    return clone({ slotId: slot.slotId, exerciseId, progression: slot.progression });
  });
  return clone({
    schemaVersion: 1 as const,
    instanceId: input.instance.id,
    definition: input.instance.definition,
    blockId: block.id,
    phase: block.phase,
    musclePriorities: block.musclePriorities,
    roleId: role.id,
    occurrenceId: input.occurrence.id,
    planningStateRevision: input.state.revision,
    program: {
      strategy: input.definition.strategy,
      state: input.state.strategyState,
      exercises,
      trainingContext: block.musclePriorities?.length
        ? {
            ...role.trainingContext,
            musclePriorities: [...block.musclePriorities, ...(role.trainingContext?.musclePriorities ?? [])],
          }
        : role.trainingContext,
    },
  });
}

export function proposeProgramAdvancement(input: {
  definition: ProgramDefinition;
  instance: ProgramInstance;
  state: ProgramState;
  intent: PlannedSessionIntent;
  status: "completed" | "skipped";
  nextStrategyState?: ProgramStrategyState;
}): ProgramStateProposal {
  assertSnapshots(input.definition, input.instance, input.state);
  if (input.intent.instanceId !== input.instance.id || input.intent.planningStateRevision !== input.state.revision) {
    throw new TypeError("Planned session intent does not match the supplied program state revision.");
  }
  if (!sameReference(input.intent.definition, input.state.definition)) throw new TypeError("Planned session intent references a different program definition.");
  const block = input.definition.blocks[input.state.blockIndex];
  if (!block || block.id !== input.intent.blockId) throw new TypeError("Planned session intent does not match the active block.");
  const scheduledRole = scheduleEntries(block.schedule, { id: input.intent.occurrenceId })[input.state.sessionCursor]?.roleId;
  const overriddenRole = block.schedule.kind === "hybrid"
    ? block.schedule.overrides.find((candidate) => candidate.occurrenceId === input.intent.occurrenceId)?.roleId
    : undefined;
  if ((overriddenRole ?? scheduledRole) !== input.intent.roleId) throw new TypeError("Planned session intent does not match the active schedule position.");
  const scheduleLength = scheduleEntries(block.schedule, { id: input.intent.occurrenceId }).length;
  let blockIndex = input.state.blockIndex;
  let microcycleIndex = input.state.microcycleIndex;
  let sessionCursor = input.state.sessionCursor + 1;
  let completed = false;
  if (sessionCursor === scheduleLength) {
    sessionCursor = 0;
    microcycleIndex += 1;
    if (microcycleIndex === block.microcycleCount) {
      microcycleIndex = 0;
      blockIndex += 1;
      if (blockIndex === input.definition.blocks.length) {
        blockIndex = input.definition.blocks.length - 1;
        microcycleIndex = block.microcycleCount;
        completed = true;
      }
    }
  }
  const revision = input.state.revision + 1;
  if (!Number.isSafeInteger(revision)) throw new RangeError("Program state revision exceeds the safe-integer range.");
  const nextState: ProgramState = {
    ...clone(input.state),
    revision,
    blockIndex,
    microcycleIndex,
    sessionCursor,
    completedOccurrenceCount: input.state.completedOccurrenceCount + (input.status === "completed" ? 1 : 0),
    completed,
    strategyState: clone(input.nextStrategyState ?? input.state.strategyState),
  };
  if (!Number.isSafeInteger(nextState.completedOccurrenceCount)) throw new RangeError("Completed occurrence count exceeds the safe-integer range.");
  return clone({
    schemaVersion: 1 as const,
    instanceId: input.instance.id,
    definition: input.state.definition,
    expectedRevision: input.state.revision,
    nextState,
    occurrence: {
      schemaVersion: 1 as const,
      instanceId: input.instance.id,
      definition: input.state.definition,
      blockId: input.intent.blockId,
      roleId: input.intent.roleId,
      occurrenceId: input.intent.occurrenceId,
      status: input.status,
      beforeRevision: input.state.revision,
      afterRevision: revision,
    },
  });
}

/** Accepts a proposal locally after an explicit optimistic-revision check. */
export function acceptProgramAdvancement(
  current: ProgramState,
  proposal: ProgramStateProposal,
): ProgramState {
  if (proposal.instanceId !== current.instanceId || proposal.expectedRevision !== current.revision) {
    throw new TypeError("Program state proposal does not match the current instance revision.");
  }
  if (!sameReference(proposal.definition, current.definition) || !sameReference(proposal.nextState.definition, current.definition)) {
    throw new TypeError("Program state proposal references a different definition.");
  }
  if (proposal.nextState.instanceId !== current.instanceId || !sameReference(proposal.occurrence.definition, current.definition)) {
    throw new TypeError("Program state proposal contains state or occurrence data for a different program instance.");
  }
  if (proposal.nextState.revision !== current.revision + 1) {
    throw new TypeError("Program state proposal must advance the revision exactly once.");
  }
  if (proposal.occurrence.instanceId !== current.instanceId ||
      proposal.occurrence.beforeRevision !== current.revision ||
      proposal.occurrence.afterRevision !== proposal.nextState.revision) {
    throw new TypeError("Program occurrence record does not match the proposed revision transition.");
  }
  return clone(proposal.nextState);
}

export interface StructuralPresetOptions {
  id: string;
  version: string;
  strategy: ProgramStrategyRef;
  displayName?: string;
}

const emptyRole = (id: string): ProgramSessionRole => ({ id, slots: [] });
const preset = (
  options: StructuralPresetOptions,
  presetId: string,
  fallbackName: string,
  blocks: ProgramBlock[],
): ProgramDefinition => defineProgram({
  id: options.id,
  version: options.version,
  displayName: options.displayName ?? fallbackName,
  strategy: options.strategy,
  source: { kind: "built_in_preset", id: presetId, version: "1" },
  blocks,
});

export const programs = {
  slots: {
    fixed<TConfig = JsonValue>(slot: Omit<FixedProgramSlot<TConfig>, "kind">): FixedProgramSlot<TConfig> {
      return clone({ kind: "fixed" as const, ...slot });
    },
    dynamic<TConfig = JsonValue>(slot: Omit<DynamicProgramSlot<TConfig>, "kind">): DynamicProgramSlot<TConfig> {
      return clone({ kind: "dynamic" as const, ...slot });
    },
  },
  schedules: {
    rolling(roleIds: readonly string[]): RollingProgramSchedule {
      return clone({ kind: "rolling" as const, roleIds: [...roleIds] });
    },
    fixedWeekdays(sessions: readonly { weekday: ProgramWeekday; roleId: string }[]): FixedWeekdayProgramSchedule {
      return clone({ kind: "fixed_weekdays" as const, sessions: [...sessions] });
    },
    frequencyTargeted(sessionsPerMicrocycle: number, roleIds: readonly string[]): FrequencyTargetedProgramSchedule {
      return clone({ kind: "frequency_targeted" as const, sessionsPerMicrocycle, roleIds: [...roleIds] });
    },
    explicitDates(sessions: readonly { date: string; roleId: string }[]): ExplicitDatesProgramSchedule {
      return clone({ kind: "explicit_dates" as const, sessions: [...sessions] });
    },
    hybrid(roleIds: readonly string[], overrides: readonly { occurrenceId: string; roleId: string }[]): HybridProgramSchedule {
      return clone({ kind: "hybrid" as const, roleIds: [...roleIds], overrides: [...overrides] });
    },
  },
  validate: validateProgram,
  presets: {
    asynchronousUpperLower(options: StructuralPresetOptions): ProgramDefinition {
      return preset(options, "asynchronous-upper-lower", "Asynchronous Upper / Lower", [{
        id: "main", microcycleCount: 4,
        schedule: { kind: "rolling", roleIds: ["upper", "lower"] },
        sessionRoles: [emptyRole("upper"), emptyRole("lower")],
      }]);
    },
    fixedWeekdayUpperLower(options: StructuralPresetOptions): ProgramDefinition {
      return preset(options, "fixed-weekday-upper-lower", "Fixed-weekday Upper / Lower", [{
        id: "main", microcycleCount: 4,
        schedule: { kind: "fixed_weekdays", sessions: [
          { weekday: "monday", roleId: "upper" },
          { weekday: "tuesday", roleId: "lower" },
          { weekday: "thursday", roleId: "upper" },
          { weekday: "friday", roleId: "lower" },
        ] },
        sessionRoles: [emptyRole("upper"), emptyRole("lower")],
      }]);
    },
    pplRotation(options: StructuralPresetOptions): ProgramDefinition {
      return preset(options, "ppl-rotation", "Push / Pull / Legs Rotation", [{
        id: "main", microcycleCount: 4,
        schedule: { kind: "rolling", roleIds: ["push", "pull", "legs"] },
        sessionRoles: [emptyRole("push"), emptyRole("pull"), emptyRole("legs")],
      }]);
    },
    structuredHypertrophyBlock(options: StructuralPresetOptions): ProgramDefinition {
      const roles = () => [emptyRole("upper"), emptyRole("lower")];
      const schedule = (): RollingProgramSchedule => ({ kind: "rolling", roleIds: ["upper", "lower"] });
      return preset(options, "structured-hypertrophy-block", "Structured Hypertrophy Block", [
        { id: "accumulation", displayName: "Accumulation", phase: "accumulation", microcycleCount: 4, schedule: schedule(), sessionRoles: roles() },
        { id: "intensification", displayName: "Intensification", phase: "intensification", microcycleCount: 3, schedule: schedule(), sessionRoles: roles() },
        { id: "deload", displayName: "Deload", phase: "deload", microcycleCount: 1, schedule: schedule(), sessionRoles: roles() },
      ]);
    },
  },
} as const;

function definitionReference(definition: ProgramDefinition): ProgramDefinitionReference {
  return {
    id: definition.id,
    version: definition.version,
    configurationFingerprint: definition.configurationFingerprint,
  };
}

function assertSnapshots(definition: ProgramDefinition, instance: ProgramInstance, state: ProgramState): void {
  const validation = validateProgram(definition);
  if (!validation.valid) throw new ProgramDefinitionError(validation.issues);
  const reference = definitionReference(definition);
  if (!sameReference(instance.definition, reference) || !sameReference(state.definition, reference)) throw new TypeError("Program snapshots reference different definition content.");
  if (state.instanceId !== instance.id) throw new TypeError("Program state belongs to a different instance.");
  for (const [name, value] of [["revision", state.revision], ["blockIndex", state.blockIndex], ["microcycleIndex", state.microcycleIndex], ["sessionCursor", state.sessionCursor], ["completedOccurrenceCount", state.completedOccurrenceCount]] as const) {
    if (!Number.isSafeInteger(value) || value < 0) throw new TypeError(`Program state ${name} must be a non-negative safe integer.`);
  }
}

function sameReference(left: ProgramDefinitionReference, right: ProgramDefinitionReference): boolean {
  return left.id === right.id && left.version === right.version && left.configurationFingerprint === right.configurationFingerprint;
}

function scheduleEntries(schedule: ProgramSchedule, occurrence: ProgramOccurrence): Array<{ roleId: string; weekday?: ProgramWeekday; date?: string }> {
  if (schedule.kind === "rolling") return schedule.roleIds.map((roleId) => ({ roleId }));
  if (schedule.kind === "fixed_weekdays" || schedule.kind === "explicit_dates") return schedule.sessions.map((session) => ({ ...session }));
  if (schedule.kind === "frequency_targeted") {
    return Array.from({ length: schedule.sessionsPerMicrocycle }, (_, index) => ({ roleId: schedule.roleIds[index % schedule.roleIds.length]! }));
  }
  void occurrence;
  return schedule.roleIds.map((roleId) => ({ roleId }));
}

function scheduleRoleIds(schedule: ProgramSchedule | undefined): string[] {
  if (!schedule) return [];
  if (schedule.kind === "rolling" || schedule.kind === "frequency_targeted") return schedule.roleIds;
  if (schedule.kind === "fixed_weekdays" || schedule.kind === "explicit_dates") return schedule.sessions.map((session) => session.roleId);
  if (schedule.kind === "hybrid") return [...schedule.roleIds, ...schedule.overrides.map((override) => override.roleId)];
  return [];
}

function requiredId(issues: ValidationIssue[], value: unknown, path: string, label: string): void {
  if (typeof value !== "string" || value.length === 0) issue(issues, "program.id_required", path, `Program ${label} identity is required.`);
}

function positiveInteger(issues: ValidationIssue[], value: unknown, path: string, label: string, maximum = Number.MAX_SAFE_INTEGER): void {
  if (!Number.isSafeInteger(value) || Number(value) < 1 || Number(value) > maximum) issue(issues, "program.integer_invalid", path, `Program ${label} must be an integer from 1 through ${maximum}.`);
}

function duplicateIds(issues: ValidationIssue[], values: readonly { id?: string; slotId?: string }[], path: string, label: string): void {
  const seen = new Set<string>();
  for (const [index, value] of values.entries()) {
    const id = value.id ?? value.slotId;
    if (typeof id === "string" && seen.has(id)) issue(issues, `program.duplicate_${label}_id`, `${path}[${index}]`, `Duplicate program ${label} identity: ${id}`);
    if (typeof id === "string") seen.add(id);
  }
}

function issue(issues: ValidationIssue[], code: string, path: string, message: string): void {
  issues.push({ code, path, message, severity: "error" });
}

function clone<T>(value: T): T {
  return value === undefined ? value : structuredClone(value);
}

function fingerprint(value: unknown): string {
  const serialized = stableJson(value);
  let hash = 0xcbf29ce484222325n;
  for (let index = 0; index < serialized.length; index += 1) {
    hash ^= BigInt(serialized.charCodeAt(index));
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `fnv1a64:${hash.toString(16).padStart(16, "0")}`;
}

function stableJson(value: unknown): string {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new TypeError("Program definitions must contain finite numbers.");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map((item) => stableJson(item ?? null)).join(",")}]`;
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const fields = Object.keys(record).filter((key) => record[key] !== undefined).sort();
    return `{${fields.map((key) => `${JSON.stringify(key)}:${stableJson(record[key])}`).join(",")}}`;
  }
  if (value === undefined) return "null";
  throw new TypeError("Program definitions must contain JSON-compatible values.");
}
