# ADR-0007: Separate Program Strategies from Exercise Progression

- **Status:** Accepted
- **Date:** 2026-08-10
- **Clarifies:** ADR-0001, ADR-0003, and ADR-0006
- **Preserves:** Deterministic snapshot inputs, proposal-only state transitions, and the v0.1 single-methodology contract

## Context

The v0.1 document names one methodology. Treating that methodology as an
entire program would eventually combine exercise selection, scheduling,
recovery, volume, ordering, deloading, and progression in one implementation.
It would also prevent one session from using RPE progression for one exercise
and double progression for another.

Double progression and RPE top-set/backoff answer exercise-local questions:
which load and repetitions to prescribe, how performance is classified, and
what progression state should be proposed next. They do not decide why an
exercise belongs in the session.

## Decision

Caudex has two explicit levels:

```text
athlete + host inputs
  -> program strategy and program state
  -> ordered session exercise slots
  -> one progression method/config/state lane per slot
  -> combined recommendation
  -> completed workout
  -> per-lane progression proposals + optional program-state proposal
```

A **program strategy** owns session intent and composition. An **exercise
progression method** owns prescription and evaluation for one assigned lane.
Session composition remains a seam inside the strategy boundary; the first
implementation does not add an empty composer interface because no second
composer behavior exists yet.

`caudex.fixed-session` v0.1 is the proving strategy. It preserves supplied slot
order, validates assignments, dispatches each slot independently, and combines
the results. It performs no adaptive selection.

### Identity and state ownership

Each slot has `slotId` (program role), `exerciseId` (catalog movement), and
`stateId` (progression lane). `stateId` is deliberately not derived from
`exerciseId`: the same movement may appear in multiple slots or blocks with
different configuration, state, or methods. Duplicate slot or state identities
in one request are rejected.

When an exercise occurs more than once in a session, completed occurrences are
paired with prescribed occurrences in their stable session order; routing still
uses each prescription's distinct `stateId`. Hosts must preserve that order when
building the completed snapshot.

Program state is a separately versioned `ProgramState`. Progression state is
stored and proposed with its `stateId`, method ID/version, and state schema.
Migrating a strategy does not imply migrating progression state, and migrating
a progression method does not rewrite program state.

### Canonical provenance and routing

The session records the resolved strategy plus its config and input state. Each
exercise prescription records its slot, state lane, progression method/version,
config version, config, and input state. These are canonical values, not runtime
objects.

Evaluation consumes that persisted recommendation, validates its provenance,
routes each completed exercise through the recorded implementation, and returns
distinct `progressionStateProposals` and `nextProgramState`. It never silently
accepts or persists either proposal. Complete explicit inputs retain the rule:
same input produces the same recommendation, evaluation, and fingerprints.

### Compatibility, discovery, and persistence

The existing `recommend` and `evaluate` operations keep their single-methodology
meaning. New `recommendProgram` and `evaluateProgram` operations share the same
underlying progression implementations. Existing methodology IDs and schemas
are unchanged.

Discovery retains `methodologies`, aliases those descriptors as
`progressionMethods`, and separately exposes `programStrategies`. Portable
documents use distinct accepted-program-recommendation, program-state, and
progression-state records instead of overloading legacy methodology state.

## Extension points

Future rolling, mesocycle, or hybrid strategies can derive different slot
intent while continuing to assign existing progression methods. A separately
registered session composer may be introduced when multiple concrete composer
behaviors justify that seam.

## Alternatives considered

- **Expand methodology into the whole program:** rejected because it couples
  unrelated policies and prevents heterogeneous sessions.
- **Compose unrelated recommendations in the host:** rejected as the canonical
  model because it loses central validation, provenance, combined determinism,
  and later evaluation routing.
- **Rename every methodology symbol:** rejected because those symbols are
  compatibility surfaces; the clearer model is additive.
- **Add recovery, volume, scheduling, and periodization interfaces now:**
  rejected as speculative framework-building.

## Non-goals

This decision does not implement recovery, fatigue, weekly volume, calendars,
mesocycles, deloads, adaptive exercise selection, substitutions, readiness
adaptation, or optimization. It creates the ownership and routing boundaries in
which concrete versions of those behaviors can later live.
