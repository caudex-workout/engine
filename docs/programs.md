# Program planning

Program planning lets a host describe reusable training structure and resolve
one intended session at a time without making Caudex own a calendar or stored
program. It extends the [programming hierarchy](programming-hierarchy.md): a
program plans *which* ordered slots belong in an occurrence, while the
assigned progression method prescribes and evaluates each slot.

The typed Zig API is authoritative. Its canonical snapshot types are also the
contract carried across C, WASM/npm, and the portable protocol. This guide uses
the public names and lifecycle; the abbreviated Zig is schematic so it can
explain the value flow without duplicating every language binding signature.

## The planning model

```text
ProgramDefinition --instantiate--> ProgramInstance + ProgramState
      |                                        |
      |                             SessionOccurrence
      |                                        |
      +-----------------resolvePlannedSession-+
                                               v
                                  PlannedSessionIntent
                                               |
                                  recommend / track / evaluate
                                               |
                                      proposeAdvancement
                                               v
                                   ProgramStateProposal
                                               |
                                      host accepts or rejects
```

The values in that diagram are deliberately distinct:

| Value | What it represents |
| --- | --- |
| `ProgramDefinition` | A reusable versioned blueprint: session roles, schedule policy, phases, ordered slots, program strategy configuration, and program training context. |
| `ProgramInstance` | One host-owned run of a captured definition. It is not an account, a mutable authoring record, or a calendar subscription. |
| `ProgramState` | The accepted dynamic planning position for that instance. It is input to a calculation, never hidden engine state. |
| `SessionRole` | A stable reusable session identity, such as `upper-a`; schedules refer to roles. |
| `SessionOccurrence` | One explicit occurrence of a role in an instance/sequence. It can be planned or previewed without being completed. |
| `PlannedSessionIntent` | The immutable result of resolving one occurrence: applicable phase, role, ordered slots, and planning provenance. |
| `ProgramStateProposal` | A proposed successor to the supplied state after explicit evidence. Only the host can accept/persist it. |

Do not use a display name or a bare exercise ID in place of any of these stable
identities. `SessionRole`, slot, exercise, and progression-lane identifiers
are all different.

## Author a definition

A definition declares the structure that repeats. Give the definition a stable
host ID and an explicit revision/version. It must contain bounded schedule and
phase data and reference stable `SessionRole` values. A role resolves to an
ordered list of slots; a slot preserves the existing programming identities:

```text
slotId       the role within its planned session
exerciseId   the catalog movement
stateId      the progression-method lane
```

For example, a three-role plan might use the roles `upper-a`, `lower-a`, and
`upper-b`. `upper-a` can have a `primary-press` slot using
`host:incline-press` and the `block-1-primary-press` progression lane. If a
later phase changes it to a flat press, the host chooses an explicit lane
policy; the new exercise does not silently inherit `block-1-primary-press`.
Two slots may prescribe the same exercise, but they need distinct active
`slotId` and `stateId` values when their configuration or progress differs.

Validate before storing or instantiating:

```zig
// Schematic: consult the current typed Zig declarations for exact fields.
const checked = try programs.validateDefinition(allocator, definition);
defer checked.deinit();
```

Validation catches structural problems such as unsupported strategy/method
references, duplicate identities that make slot routing ambiguous, an unknown
role referenced by a schedule, invalid bounded phase/schedule data, and
incompatible configuration. A rejected definition is not partially
instantiated.

## Schedules and occurrences

Schedules say which role is intended next; they do not read time. A
weekday-oriented host supplies the relevant local date/time-zone interpretation
as explicit input. A rolling host supplies the current accepted sequence facts
and the occurrence it wants to resolve. In both cases, Caudex receives an
explicit `SessionOccurrence`.

This is intentional:

- Caudex does not decide the device time zone, daylight-saving behavior,
  holidays, reminders, or calendar-provider synchronization.
- It does not infer whether a missed occurrence is skipped, deferred, or
  completed late. The host records and supplies that choice.
- Planning the same definition, instance, state, occurrence, context, catalog,
  and explicit `asOf` value gives the same intent. Previewing does not advance
  the program.

When a product needs a “next workout” button, its orchestration layer derives
the requested occurrence from its own calendar/rolling-cadence policy and then
calls the deterministic planner. That keeps calendar policy out of the core
and makes the requested occurrence replayable.

## Phases and deloads

Phases organize a definition into ordered structural portions. A resolved
intent records which phase applied, and a future accepted `ProgramState`
records any phase transition. Changing the authoring definition later does not
rewrite an instance's captured phase meaning.

A deload is only an explicit phase or supported phase-level policy. Its reduced
or altered work must be declared through the selected strategy and slot
configuration. Caudex does not calculate fatigue, prescribe a deload after a
fixed time, infer a deload from missed workouts, or make medical/readiness
claims. A host can request a defined deload path or implement a later policy
with explicit inputs, but it must still accept the resulting state proposal.

## Resolve a session and make a recommendation

Instantiate a validated definition once the host has chosen the instance ID,
scope, definition snapshot, and any explicit anchor values. Keep the returned
instance and accepted initial state beside one another in host storage if the
application persists programs.

```zig
const instantiated = try programs.instantiate(allocator, .{
    .definition = definition_snapshot,
    .instance_id = "host:program-instance:42",
    // Host-supplied scope and anchor facts belong here.
});
defer instantiated.deinit();

const intent = try programs.resolvePlannedSession(allocator, .{
    .definition = definition_snapshot,
    .instance = instantiated.instance,
    .state = accepted_program_state,
    .occurrence = requested_occurrence,
    .as_of = "2026-08-10T14:00:00Z",
    .training_context = today_context,
    .catalog = catalog_snapshot,
});
defer intent.deinit();
```

Use the resulting `PlannedSessionIntent` to build the program recommendation.
The recommendation keeps the phase, role, occurrence, ordered slot, strategy,
progression, resolved-context, and catalog provenance that affected it. Feed
that accepted recommendation into the normal active-workout and evaluation
workflow; do not rebuild routing from current definition data or bare exercise
IDs.

The following timeline illustrates a rolling plan without implying a calendar
implementation:

```text
definition v3: upper-a -> lower-a -> upper-b (phase: accumulation)
instance 42:  accepted state rev 7; next occurrence = 12
request:      occurrence 12 / role upper-b / explicit asOf + context
result:       planned upper-b intent with its stable slots and lane provenance
host:         accepts recommendation, records a completed workout
evaluation:   produces lane proposals and program advancement proposal
```

If the host edits the definition to v4 before occurrence 12 is completed,
instance 42 still uses its captured v3 snapshot. The host may explicitly start
a new instance from v4; it must not silently reinterpret v3 history.

## Advance only by accepting a proposal

After a completed workout has been evaluated, ask the planner for its state
proposal using that accepted recommendation, the completed-workout snapshot,
the same instance, and the state revision that was current when the occurrence
was planned:

```zig
const proposed = try programs.proposeAdvancement(allocator, .{
    .instance = instance_snapshot,
    .state = accepted_program_state,
    .recommendation = accepted_recommendation,
    .completed_workout = completed_workout,
    .as_of = completed_workout.completed_at,
});
defer proposed.deinit();

// Application code—not Caudex—checks the expected revision and persists an
// explicit decision to accept or reject `proposed.program_state_proposal`.
```

An `ok` calculation and a `ProgramStateProposal` do not mean the state has
advanced. The host may discard a proposal for a preview, reject it because the
workout was edited, or compare-and-set it against the stored state revision.
It can atomically persist an accepted program state, accepted recommendation,
completed workout, and compatible per-slot progression proposals when its
database supports that transaction.

Program-state advancement and exercise progression are separate acceptance
decisions. A program proposal does not automatically persist every `stateId`
lane proposal; accepting a lane proposal does not automatically advance phase
or occurrence state. Store their recorded provenance and resolve a conflict at
the host boundary rather than turning a persistence conflict into an engine
validation error.

## Snapshot, version, and portability rules

Keep these values with an accepted planning decision:

- definition ID, schema version, host revision/version, and content fingerprint;
- instance ID and its captured definition identity/fingerprint;
- program-state schema/version and host persistence revision/fingerprint;
- occurrence, role, phase, and stable ordered-slot identities;
- selected program strategy and each progression method's ID, version,
  configuration version, configuration, and input state;
- resolved training-context/profile provenance and exact catalog projection;
- accepted recommendation, completed-workout evidence, and proposal/acceptance
  provenance.

Those snapshots make replay possible after a user changes their profile, a
catalog record changes, or an author publishes a new definition revision.
Missing information stays unknown—do not fill it with a current profile,
catalog, or calendar lookup while replaying history.

For export/import, use the canonical portable types. They carry host-neutral
program definitions, instances, accepted state, and accepted recommendation/
progression evidence as versioned records. The portable protocol validates
ordering and references, then lets the host choose its merge/replace and
conflict policy. It is not an account sync protocol and must never carry
credentials, authorization data, calendar tokens, or instructions to overwrite
unrelated/newer host state.

## What program planning does not do

Program planning does not provide a hosted calendar, schedule UI, reminders,
notifications, recovery or fatigue estimation, medical assessment, automatic
deloads, volume optimization, wearable import, user accounts, synchronization,
or required persistence. It also does not turn a program definition into a
workout template or a planned occurrence into an accepted/active workout.

For profile/context precedence, see [athlete profiles and training
context](athlete-profiles-and-training-context.md). For slot and progression
routing, see [programming hierarchy](programming-hierarchy.md). The full
architectural decision is [ADR-0010](adr/ADR-0010-deterministic-program-planning.md).
