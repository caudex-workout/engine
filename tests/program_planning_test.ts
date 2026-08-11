import {
  ProgramDefinitionError,
  acceptProgramAdvancement,
  defineProgram,
  instantiateProgram,
  programs,
  proposeProgramAdvancement,
  resolveNextSession,
  validateProgram,
  type ProgramDefinition,
  type ProgramStrategyRef,
} from "../packages/npm/workout-engine/src/index.ts";

const strategy: ProgramStrategyRef = {
  id: "caudex.fixed-session",
  versionRequirement: "^0.1.0",
  configVersion: 1,
  config: {},
};
const progression = {
  stateId: "lane:press",
  methodology: {
    id: "caudex.double-progression",
    versionRequirement: "^0.1.0",
    configVersion: 1,
    config: {},
  },
};
const authored = {
  id: "host:program:upper-lower",
  version: "3",
  displayName: "Upper / Lower",
  strategy,
  source: { kind: "host_custom" as const },
  blocks: [{
    id: "main",
    microcycleCount: 1,
    schedule: programs.schedules.rolling(["upper", "lower"]),
    sessionRoles: [{
      id: "upper",
      slots: [
        programs.slots.fixed({ slotId: "press", exerciseId: "bench-press", progression }),
        programs.slots.dynamic({
          slotId: "row",
          candidateExerciseIds: ["barbell-row", "cable-row"],
          progression: { ...progression, stateId: "lane:row" },
        }),
      ],
    }, { id: "lower", slots: [] }],
  }],
};

const definition = defineProgram(authored);
assert(definition.schemaVersion === 1, "definition is versioned");
assert(definition.configurationFingerprint.startsWith("fnv1a64:"), "definition is fingerprinted");
assert(validateProgram(definition).valid, "defined program validates");
authored.blocks[0]!.id = "changed-after-definition";
assert(definition.blocks[0]?.id === "main", "definition snapshots caller input");
assert(
  defineProgram({ ...authored, blocks: [{ ...authored.blocks[0]!, id: "main" }] }).configurationFingerprint === definition.configurationFingerprint,
  "equivalent definitions fingerprint identically",
);

expectError(() => defineProgram({ ...authored, blocks: [] }), ProgramDefinitionError);
const damaged = structuredClone(definition) as ProgramDefinition;
damaged.blocks[0]!.schedule = programs.schedules.rolling(["missing-role"]);
const invalid = validateProgram(damaged);
assert(!invalid.valid && invalid.issues.some((issue) => issue.code === "program.schedule_unknown_role"), "validation reports schedule routing errors");

const instantiated = instantiateProgram(definition, {
  instanceId: "host:instance:42",
  athleteId: "athlete:7",
  startedOn: "2026-08-10",
  lifecycle: "active",
});
assert(instantiated.state.revision === 0 && instantiated.state.instanceId === instantiated.instance.id, "instantiation returns separate versioned instance and state");

expectError(() => resolveNextSession({
  definition,
  ...instantiated,
  occurrence: { id: "occurrence:1" },
}), TypeError);
const firstIntent = resolveNextSession({
  definition,
  ...instantiated,
  occurrence: { id: "occurrence:1" },
  dynamicSelections: { row: "cable-row" },
});
const replayedIntent = resolveNextSession({
  definition,
  ...instantiated,
  occurrence: { id: "occurrence:1" },
  dynamicSelections: { row: "cable-row" },
});
assert(JSON.stringify(firstIntent) === JSON.stringify(replayedIntent), "session resolution is deterministic");
assert(firstIntent.roleId === "upper" && firstIntent.program.exercises[1]?.exerciseId === "cable-row", "resolution preserves role order and explicit dynamic choice");
expectError(() => resolveNextSession({
  definition,
  ...instantiated,
  occurrence: { id: "occurrence:bad-choice" },
  dynamicSelections: { row: "invented-row" },
}), TypeError);

const firstProposal = proposeProgramAdvancement({
  definition,
  ...instantiated,
  intent: firstIntent,
  status: "completed",
});
assert(instantiated.state.revision === 0, "proposing does not mutate accepted state");
const afterFirst = acceptProgramAdvancement(instantiated.state, firstProposal);
assert(afterFirst.revision === 1 && afterFirst.sessionCursor === 1 && afterFirst.completedOccurrenceCount === 1, "acceptance advances exactly one occurrence");
expectError(() => acceptProgramAdvancement(afterFirst, firstProposal), TypeError);

const secondIntent = resolveNextSession({
  definition,
  instance: instantiated.instance,
  state: afterFirst,
  occurrence: { id: "occurrence:2" },
});
assert(secondIntent.roleId === "lower", "rolling schedules use the accepted cursor");
const afterSecond = acceptProgramAdvancement(afterFirst, proposeProgramAdvancement({
  definition,
  instance: instantiated.instance,
  state: afterFirst,
  intent: secondIntent,
  status: "skipped",
}));
assert(afterSecond.completed && afterSecond.completedOccurrenceCount === 1, "skips consume schedule position without becoming completions");
expectError(() => resolveNextSession({
  definition,
  instance: instantiated.instance,
  state: afterSecond,
  occurrence: { id: "occurrence:3" },
}), TypeError);

const fixedDefinition = programs.presets.fixedWeekdayUpperLower({ id: "fixed", version: "1", strategy });
const fixed = instantiateProgram(fixedDefinition, { instanceId: "fixed:1", athleteId: "athlete:7" });
expectError(() => resolveNextSession({
  definition: fixedDefinition,
  ...fixed,
  occurrence: { id: "fixed-occurrence", weekday: "tuesday" },
}), TypeError);
assert(resolveNextSession({
  definition: fixedDefinition,
  ...fixed,
  occurrence: { id: "fixed-occurrence", weekday: "monday" },
}).roleId === "upper", "weekday interpretation remains explicit host input");

for (const [schedule, occurrence, expectedRole] of [
  [programs.schedules.frequencyTargeted(3, ["upper", "lower"]), { id: "frequency:1" }, "upper"],
  [programs.schedules.explicitDates([{ date: "2026-08-10", roleId: "upper" }]), { id: "dated:1", date: "2026-08-10" }, "upper"],
  [programs.schedules.hybrid(["upper", "lower"], [{ occurrenceId: "hybrid:1", roleId: "lower" }]), { id: "hybrid:1" }, "lower"],
] as const) {
  const scheduledDefinition = defineProgram({
    id: `schedule:${schedule.kind}`, version: "1", displayName: schedule.kind, strategy,
    blocks: [{ id: "main", microcycleCount: 1, schedule, sessionRoles: [{ id: "upper", slots: [] }, { id: "lower", slots: [] }] }],
  });
  const scheduled = instantiateProgram(scheduledDefinition, { instanceId: `instance:${schedule.kind}`, athleteId: "athlete:7" });
  assert(resolveNextSession({ definition: scheduledDefinition, ...scheduled, occurrence }).roleId === expectedRole, `${schedule.kind} schedule resolves explicit host facts`);
}

for (const create of [
  programs.presets.asynchronousUpperLower,
  programs.presets.fixedWeekdayUpperLower,
  programs.presets.pplRotation,
  programs.presets.structuredHypertrophyBlock,
]) {
  const preset = create({ id: `preset:${create.name}`, version: "1", strategy });
  assert(preset.source?.kind === "built_in_preset" && programs.validate(preset).valid, "structural preset is embedded and replayable");
}

console.log("first-class TypeScript program planning lifecycle validated");

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function expectError(action: () => unknown, errorType: abstract new (...args: never[]) => Error): void {
  try {
    action();
    throw new Error("expected operation to fail");
  } catch (error) {
    if (!(error instanceof errorType)) throw error;
  }
}
