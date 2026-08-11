# ADR-0009: Separate Athlete Profiles From Training Context

- **Status:** Accepted
- **Date:** 2026-08-10
- **Clarifies:** ADR-0001, ADR-0003, ADR-0006, ADR-0007, and ADR-0008
- **Preserves:** Host-owned identity, deterministic snapshots, optional
  persistence, and separately owned program/progression state

## Context

Workout decisions need facts that have different lifetimes. An athlete may
normally train four times per week, prefer pounds, emphasize chest, and have a
home equipment profile. On a particular day they may have 35 minutes, be at
home without a pull-up bar, and avoid overhead work. A single mutable settings
object obscures those lifetimes, makes overrides ambiguous, and risks changing
the meaning of a historical recommendation when a profile is edited later.

Caudex is not an account system, a medical assessor, or a recovery model. It
needs a deterministic model of explicit training intent and current constraints
that strategies can consume without independently reimplementing merge rules.

## Decision

Caudex distinguishes four domains:

```text
AthleteProfile       persistent, explicit athlete intent and evidence
ProgramTrainingContext  block/strategy-owned specialization
TrainingContext      facts and constraints for one recommendation/session
ResolvedTrainingContext  immutable decision projection for a request/result
```

`AthleteProfile.id` is a stable, opaque host-provided profile scope. It is not
an authentication ID, account ID, or personally identifying field. Optional
`displayName` and host metadata are non-canonical presentation data unless a
host deliberately projects them into a programming-relevant value.

The profile contains only facts normally true over many sessions: structured
goals, experience and exercise familiarity, schedule and duration preferences,
unit preferences, explicit exercise preferences, muscle priorities, persistent
restrictions, reusable training locations, and capability observations.
Missing fields remain unknown or unspecified: missing experience is not novice,
missing readiness is not recovered, and missing frequency is not three sessions
per week.

`TrainingContext` carries facts true now: selected location, equipment delta,
available time, a session goal, temporary preferences/restrictions,
required/excluded exercises, and time-bound readiness observations. It never
mutates the profile. A host may later offer an explicit “promote to profile”
operation, but that is a host/user edit, not a side effect of recommendation or
workout tracking.

`ProgramTrainingContext` is separate from the athlete. It can specialize goals,
priorities, preferences, restrictions, or fixed exercises for a program block;
it is never written back to the athlete profile. Derived athlete state is also
outside the profile. Future weekly volume, recovery estimates, capability
confidence, and fatigue models may consume explicit observations, but must own
their calculated state and methodology separately.

### Explicit facts, not inference or diagnosis

Exercise preferences retain their semantics: `preferred` ranks a target up,
`deprioritized` ranks it down, `excluded` forbids it, and `required` expresses
an inclusion constraint. Targets may be a specific exercise, exercise family,
movement pattern, or equipment category; an exercise preference does not imply
a family preference unless its target kind says so.

Restrictions are host/user-provided non-medical constraints against structured
exercise knowledge (exercise, family, movement pattern, restriction tag, or
equipment), never name matching. Caudex does not diagnose a condition or decide
medical safety. Persistent restrictions and session restrictions accumulate.

Readiness is an observation with dimension, value/scale, time, subject, and
provenance. “Quadriceps soreness is 8/10” is allowed; “quadriceps recovery is
32%” is a future derived interpretation and is not profile data. Likewise,
capability observations such as a host-supplied estimated 1RM are athlete
evidence, not double-progression or RPE method state.

Explicit profile preferences are intentionally distinct from future inferred
behavioral evidence. Repeated exercise swaps must not silently change an
explicit exclusion or preference.

### Location and equipment semantics

A training location is a reusable equipment profile, not an address or map.
Its stable ID identifies a baseline inventory and optional load increment
facts. The selected context location supplies that baseline. An equipment
`override` replaces the baseline; then removals are applied and additions are
added. Session deltas are applied before explicit-request deltas. The resolver
rejects an item both added and removed in one layer. This is the one
authoritative effective-equipment operation, and exercise eligibility uses the
structured equipment requirements from ADR-0008.

### Field-specific precedence

Resolution is deliberately not a generic deep merge. The layers are engine
defaults, athlete profile, program context, selected location, session context,
and final explicit request. The final request is for an embedding host’s
one-call constraint; it does not persist.

| Field | Resolution |
| --- | --- |
| Goal set | explicit request, then session, then program, then profile; the first layer with a primary goal wins. |
| Typical duration, units, experience, schedule, capability evidence | profile values remain visible; absence remains unknown. |
| Today’s available/hard maximum time | explicit request, then session, then profile hard maximum. A session limit does not rewrite the profile preference. |
| Location/equipment | selected location baseline, with session then explicit request override/removals/additions. |
| Restrictions | profile + program + session + explicit request accumulate, with source retained. |
| Preferences | profile + program + session + explicit request accumulate for ranking/explanation, with source retained. |
| Muscle priorities | profile plus program specialization, with source retained. |
| Required/excluded exercises | program + session + explicit request accumulate; persistent profile exclusions also contribute exclusions. |
| Readiness | explicit-request observations replace session observations for that snapshot; neither persists. |

The resolved projection retains source provenance so clients can display
machine-readable reasons such as `duration.session`, `equipment.location_profile`,
`restriction.athlete_profile`, or `exercise.required.session` without trying to
reverse-engineer the merge.

### Conflicts are validation errors

The resolver reports structured issues instead of choosing arbitrary precedence.
Examples include an unknown selected location, duplicate location IDs,
impossible frequency or duration ranges, duplicate preference targets in a
layer, invalid observation units/values, equipment both added and removed, or
the same exercise required and excluded. A required overhead press together
with an active no-overhead restriction, or a required barbell exercise without
the required equipment, must be discoverable as a structured incompatibility
before a deeper session strategy attempts composition. A strategy that does not
support a configured goal must report a capability/configuration issue rather
than silently reinterpret it.

### Snapshots, revisions, and history

`resolveTrainingContext` derives `ResolvedTrainingContext` from explicit input
snapshots. Strategies consume this resolved form rather than mutable profile
storage. The recommendation retains the minimal decision-relevant resolved
projection, including profile ID/revision/fingerprint and the effective values
that affected it. Accepted recommendations and active workouts therefore do
not need to consult the athlete’s current profile to be replayed or explained.

Hosts assign stable revisions for programming-relevant profile changes and the
resolver derives a fingerprint from the supplied profile snapshot. Presentational
metadata alone need not affect a host’s revision policy. Hosts must preserve the
revision/fingerprint used by a recommendation. A Monday recommendation made
from profile revision 17 remains revision-17 meaning after a Friday revision 18
changes chest priority. This is also the portable export/import boundary: export
host-neutral programming state, not account/authentication data, and follow the
portable protocol’s existing conflict semantics.

### Consumer boundaries

Program strategies receive resolved athlete/training context plus program state
and history. Progression methods receive only the resolved exercise-local input
they need, never the full location, scheduling, or profile object. Workout
tracking records recommendation provenance; swaps or completed-workout edits do
not alter profile preferences. Persistence is optional: hosts can supply a
complete profile and context snapshot directly, while first-party adapters may
store profile/location records with revision-aware updates.

## Consequences

- Future adaptive composition, scheduling, volume, capability, and recovery
  work has a common explicit input substrate without implementing those models.
- Hosts can support minimal opaque-ID profiles or rich multi-location profiles.
- Clients share deterministic override and validation behavior.
- Historical recommendations remain reproducible after profile editing.
- Account, cloud, authentication, and UI ownership remain outside Caudex.

## Alternatives considered

- **One giant settings object:** rejected because persistent intent, block
  configuration, present constraints, and derived state have different
  lifetimes and precedence.
- **Generic recursive merge:** rejected because limits override, restrictions
  accumulate, equipment applies deltas, and required/excluded exercises need
  conflict detection.
- **Profile lookup during replay:** rejected because mutable profile edits
  would rewrite historical meaning.
- **Progression state inside a profile:** rejected because each progression
  method owns lane-specific state under ADR-0007.
- **Implicit behavioral preference learning:** rejected because explicit user
  choices must not silently mutate from observed behavior.

## Non-goals

This decision does not implement adaptive session composition, weekly volume
targets, recovery/fatigue calculations, muscle freshness percentages,
mesocycles, progression strategy, scheduling or missed-session adaptation,
behavioral learning, capability aggregation/e1RM confidence, medical or injury
assessment, cloud accounts, authentication, notifications, wearables/health
imports, or body-composition coaching.
