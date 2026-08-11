# ADR-0010: Make Program Planning an Explicit Deterministic Lifecycle

- **Status:** Accepted
- **Date:** 2026-08-10
- **Clarifies:** ADR-0003, ADR-0006, ADR-0007, and ADR-0009
- **Preserves:** Host-owned identity and persistence, complete deterministic
  snapshots, explicit acceptance, separately owned progression lanes, and
  optional portability

## Context

ADR-0007 established that a program strategy owns session composition while a
progression method owns one exercise-local lane. Its first strategy preserves
a supplied fixed session. That remains useful, but it cannot express a reusable
multi-session program, its intended cadence, a current block or phase, or the
difference between a Tuesday upper-body occurrence and the reusable upper-body
role it instantiates.

Putting those facts in a mutable host calendar would make them unavailable to
the direct snapshot API and difficult to replay. Conversely, treating a
calendar event as the program would give display dates accidental ownership of
program roles, slots, and progression lanes. Program planning needs a small
model that describes intended structure without giving Caudex a clock,
calendar, account, recovery model, or database.

## Decision

Caudex models planning as explicit values and pure operations:

```text
validated ProgramDefinition
          |
          | instantiate (host supplies identity and anchor values)
          v
ProgramInstance + accepted ProgramState
          |
          | resolve a host-requested SessionOccurrence
          v
PlannedSessionIntent -> recommendation -> completed workout
          |
          | proposeAdvancement
          v
ProgramStateProposal -- host explicitly accepts --> next ProgramState
```

`validateDefinition`, `instantiate`, `resolvePlannedSession`, and
`proposeAdvancement` are deterministic operations over supplied values. They do
not read a clock, select a time zone, create an identifier, store an instance,
mark a workout complete, or accept a proposal.

### Separate definition, instance, state, role, occurrence, and intent

The following concepts have intentionally different identities and lifetimes.

| Concept | Meaning | Mutability / owner |
| --- | --- | --- |
| `ProgramDefinition` | A reusable, versioned description of phases, session roles, schedule rules, slot assignments, strategy configuration, and program specialization. | A host-authored definition snapshot. Editing creates a new host-defined revision/version; it does not edit a historical instance. |
| `ProgramInstance` | One run of one captured definition for one host scope. It binds the definition identity/version/fingerprint and explicit instantiation facts. | Created and persisted only when the host chooses. It is not an account or a calendar subscription. |
| `ProgramState` | The accepted dynamic position of an instance: for example, current phase, completed/planned occurrence bookkeeping, and strategy-owned program state. | Versioned host-owned state; passed in and returned only as a proposal. |
| `SessionRole` | A stable reusable role such as `upper-a`, `lower-b`, or `full-body`. The schedule references a role, not a particular calendar event. | Defined by `ProgramDefinition`. Its stable ID is a program role identity, not an exercise ID or progression state ID. |
| `SessionOccurrence` | One requested occurrence of a role within an instance and schedule sequence. | Identified explicitly by the planning request/instance state. It is neither a role nor an accepted workout. |
| `PlannedSessionIntent` | The resolved, immutable intent for one occurrence: role, applicable phase, ordered slots, and decision-relevant planning provenance. | A derived snapshot used to build a recommendation; it never silently updates the definition or state. |

`ProgramDefinition` is not a `ProgramInstance`, and a `ProgramInstance` is not
the current `ProgramState`. A definition can be instantiated more than once;
an instance can produce many occurrences; and an occurrence can be previewed
without becoming an accepted workout.

### Schedules express intent, not calendar ownership

A definition contains a bounded, explicit schedule that selects a
`SessionRole` for an occurrence. A schedule is planning data, not a background
job. It is valid to use either a weekday-oriented host policy or a rolling
sequence policy, but both must yield explicit occurrence inputs before Caudex
resolves a session.

| Schedule concern | Caudex contract | Host responsibility |
| --- | --- | --- |
| Role selection | Deterministically resolve the scheduled role from the supplied definition, instance/state, and occurrence values. | Supply the occurrence to plan and decide whether it is skipped, previewed, or completed. |
| Civil date and time zone | Consume an explicit value only when the selected schedule policy needs it. | Choose time zone, local-date conversion, travel behavior, daylight-saving treatment, holiday policy, reminders, and notifications. |
| Rolling cadence | Preserve schedule order and explicit completed/skipped occurrence facts. | Decide when a missed session is skipped, deferred, or resumed, then provide that decision as input. |
| Concurrency | Produce a state proposal from one stated input revision. | Compare-and-set or otherwise reconcile concurrent acceptance. |

Schedules must not infer an occurrence from wall-clock time. A host that wants
"next session" supplies the anchor, local-date/cadence interpretation, and
current accepted state snapshot. A host that does not need dates may plan an
explicit sequence occurrence directly.

### Roles contain ordered slots; lanes remain distinct

Each applicable `SessionRole` resolves to ordered exercise slots. A slot has a
stable program-role identity (`slotId`), a catalog movement identity
(`exerciseId`), and a progression-lane identity (`stateId`). These identifiers
are deliberately not interchangeable:

- A role is a session-level place in a schedule; a slot is a place within that
  session.
- An `exerciseId` names a catalog movement, while a `stateId` names the
  progression lane that owns method state.
- Two slots can use the same exercise with independent lanes. A phase can also
  use a different exercise without thereby inheriting the old lane's state.
- Duplicate active slot or state identities that make routing ambiguous are
  validation errors. The planning layer preserves stable slot order for
  recommendation, tracking, and evaluation routing.

The progression-method ID/version, configuration, and input state remain
recorded with the relevant slot, as required by ADR-0007. A session role does
not make independently configured slots share state merely because they have a
similar name or exercise.

### Phases are structural; deload policy is bounded

A `ProgramDefinition` can arrange its session roles and assignments into
ordered phases. The resolved intent records the phase that applied. Advancing
between phases is visible in `ProgramState` and in any
`ProgramStateProposal`; it is never an unrecorded mutation of a definition.

A deload is represented only as an explicit, definition-owned phase or
phase-level policy whose concrete effects are supported by the selected
strategy and slot configurations. It may reduce or alter planned work only
through those declared values. Caudex does not diagnose accumulated fatigue,
guess that an athlete needs a deload, automatically insert one after a number
of weeks, or redefine a failed workout as a deload. A host or a future,
separately specified policy must supply any trigger as explicit input and
accept the resulting proposal.

This boundary keeps phase planning deterministic while leaving recovery,
readiness interpretation, and medical decisions outside the current contract.

### Advancement is proposed, then accepted

`proposeAdvancement` consumes explicit program-instance/state snapshots and
the relevant accepted recommendation and completed-workout evidence. It can
produce a `ProgramStateProposal` describing the next planning state, including
an occurrence/phase advance when the configured policy supports it. It does
not itself persist that state, advance a calendar, or accept an exercise
progression proposal.

The host independently decides whether to accept:

1. the recommendation and its provenance;
2. the completed-workout record and any progression-lane proposals; and
3. the `ProgramStateProposal` using the revision read for the request.

The host may accept all applicable proposals atomically when its storage can
do so, or reject/discard them for a preview, edited workout, conflict, or
business rule. An accepted next program state must retain its source instance,
definition snapshot identity, prior state revision/fingerprint, and the
evidence/provenance needed for replay. Acceptance of program state does not
implicitly accept every progression-lane proposal, and vice versa.

### Identity, versions, and replayable snapshots

Program identity is host-provided and scoped. A definition ID, instance ID,
session-role ID, occurrence ID, slot ID, `exerciseId`, and `stateId` each name
a different domain object; no caller may derive one by parsing another. IDs are
opaque strings to Caudex and are not account, authentication, database-row, or
display-name identities.

The model distinguishes:

- schema versions for the canonical value shapes;
- host definition revisions/versions for intentional definition edits;
- content fingerprints for exact captured definition and state snapshots;
- program-strategy and progression-method IDs, versions, configuration
  versions, and state schemas; and
- host persistence revisions for optimistic concurrency.

`ProgramInstance` captures the exact `ProgramDefinition` identity,
version/revision, and fingerprint from which it was instantiated. A planned
intent and accepted recommendation retain the applicable instance, occurrence,
phase, role, ordered slots, resolved training-context provenance, catalog
projection, and method/strategy provenance that affected the decision. Later
edits to an authoring definition, athlete profile, catalog, or schedule policy
therefore affect later snapshots only; they do not reinterpret an accepted
recommendation or historical workout.

### Portability

The canonical snapshot types are the portable contract. Portable records carry
host-neutral program definitions, instances, accepted program states, and the
accepted program-recommendation/progression evidence needed to preserve their
relationships. They retain explicit schema versions, stable IDs, captured
definition/state fingerprints, and strategy/progression compatibility data.

Import/export remains a data exchange boundary, not synchronization magic.
The existing portable protocol controls validation, ordering, host scope, and
merge/replace conflict policy. It does not export account credentials,
authorization, calendar-provider tokens, notifications, mutable host display
metadata, or an instruction to overwrite a newer local state. A host validates
an import and explicitly applies its selected conflict policy.

## Consequences

- A host can author reusable schedules and phase structure while retaining
  control of storage, calendars, and acceptance.
- Program recommendations gain stable occurrence and phase provenance without
  weakening the slot and progression routing rules of ADR-0007.
- Definitions can evolve without rewriting already-instantiated programs.
- Direct snapshot, adapter-backed, Zig, C, and WASM/npm consumers share one
  canonical planning meaning.
- Recovery or adaptive scheduling features must add their own explicit inputs
  and accepted state rather than smuggling mutable policy into schedule logic.

## Alternatives considered

- **Let hosts schedule sessions and pass only a fixed session to the engine:**
  rejected as the only model because the role/phase/occurrence provenance and
  deterministic planning semantics would be inconsistent across hosts.
- **Make a schedule a live calendar integration:** rejected because clocks,
  time zones, provider authorization, reminders, and missed-event behavior are
  host concerns and would violate the stateless core.
- **Use an exercise ID as the program slot or progression state ID:** rejected
  because the same movement can occur in several roles, slots, and lanes.
- **Mutate an instance/state during recommendation or evaluation:** rejected
  because preview, edits, retries, replay, and persistence conflicts require a
  proposal/acceptance boundary.
- **Automatically deload based on inferred fatigue or missed sessions:**
  rejected because it requires recovery and scheduling policies not established
  by this decision.
- **Persist only a reference to the latest definition:** rejected because
  authoring edits would silently change the meaning of existing instances and
  historical recommendations.

## Non-goals

This decision does not create a calendar service, scheduling UI, reminders,
notifications, timezone database policy, account system, synchronization
service, database requirement, recovery or fatigue model, medical assessment,
automatic deload trigger, adaptive exercise selection, volume optimization,
behavioral learning, wearable integration, or automatic migration/merging of
progression lanes. It also does not make a program definition a workout
template or make a planned occurrence an accepted/active workout.
