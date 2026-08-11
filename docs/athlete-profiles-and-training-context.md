# Athlete profiles and training context

Caudex models persistent training intent separately from the facts of today’s
session. Resolve them once, pass the resulting snapshot to recommendation
logic, and retain the relevant resolved values with the recommendation.

## What belongs where

`AthleteProfile` answers “what is generally true about this athlete?” It has a
stable opaque `id`, programming revision, optional display metadata, structured
goals, experience, schedule/duration/unit preferences, exercise preferences,
muscle priorities, persistent restrictions, reusable equipment locations, and
capability observations. It is not an account, authentication user, program,
workout record, or derived athlete state.

`TrainingContext` answers “what is true right now?” It selects a location and
equipment delta, sets today’s time constraint/goal, and carries temporary
preferences, restrictions, required/excluded exercises, and readiness
observations. It does not persist by implication.

`ProgramTrainingContext` is a program block’s specialization. A program may
fix bench press or emphasize chest for six weeks without changing a profile that
normally likes incline dumbbell press. Calculated volume, recovery, and
capability estimates are future derived state, not profile fields.

## TypeScript example

```ts
import {
  defineAthleteProfile,
  resolveTrainingContext,
} from "@caudex-workout/engine";

const profile = defineAthleteProfile({
  id: "athlete-1",
  revision: 17,
  goals: { primary: { id: "hypertrophy" } },
  experience: { resistanceTraining: "intermediate" },
  schedule: { preferredSessionsPerWeek: 4, cadence: "rolling" },
  duration: {
    preferredMinutes: 60,
    acceptableMinimumMinutes: 45,
    acceptableMaximumMinutes: 75,
  },
  units: { load: "pounds" },
  exercisePreferences: [
    {
      targetKind: "exercise",
      targetId: "incline-dumbbell-press",
      level: "preferred",
    },
    {
      targetKind: "exercise",
      targetId: "bulgarian-split-squat",
      level: "excluded",
    },
  ],
  musclePriorities: [
    { muscleId: "chest", priority: "emphasize" },
    { muscleId: "lateral-delts", priority: "emphasize" },
  ],
  locations: [
    {
      id: "commercial-gym",
      equipment: [
        { equipmentId: "dumbbell" },
        { equipmentId: "barbell" },
        { equipmentId: "cable-station" },
        { equipmentId: "adjustable-bench" },
      ],
    },
    {
      id: "home",
      equipment: [
        { equipmentId: "dumbbell" },
        { equipmentId: "adjustable-bench" },
        { equipmentId: "pull-up-bar" },
      ],
    },
  ],
});

const resolved = resolveTrainingContext(profile, {
  locationId: "home",
  availableMinutes: 35,
  equipment: { removals: ["pull-up-bar"] },
  restrictions: [{
    id: "no-overhead-today",
    targetKind: "movement_pattern",
    targetId: "overhead-push",
  }],
});
```

`resolved` preserves the normal 60-minute preference and exposes 35 minutes as
today’s hard limit. Its effective equipment is dumbbells plus adjustable bench,
not commercial-gym equipment; it carries the temporary overhead restriction,
persistent chest priority, and profile revision/fingerprint. Supply the same
profile and context in `athleteProfile` and `trainingContext` on a canonical
recommendation/program request. Recommendation provenance captures the
resolved training context needed for explanation and replay.

## Locations and equipment

A `TrainingLocation` is a reusable equipment inventory, not a physical address.
Selecting it establishes the baseline. Equipment `override` replaces that
baseline, then `removals` are applied, then `additions` are added. Session
deltas apply before a final explicit request delta. Do not also build a second
effective-equipment list elsewhere; use the resolved list. Structured exercise
knowledge evaluates required equipment and restriction metadata, not names.

## Preferences and restrictions

`preferred` affects ranking, `deprioritized` reduces ranking, `excluded`
forbids a target, and `required` carries an inclusion constraint. These are
different values, not aliases for a list of exercise IDs. Targets can be a
specific exercise, family, movement pattern, or equipment category.

Persistent restrictions and temporary restrictions accumulate. A session cannot
silently erase a persistent hard restriction. Required and excluded exercises
also accumulate across program, session, and explicit request layers. If the
same exercise appears on both sides, resolution fails with a structured issue;
it does not guess a winner. Equivalent checks expose an active restriction that
makes a required exercise incompatible, or unavailable effective equipment.

## Resolution and explanations

The resolver uses field-specific rules, summarized in
[ADR-0009](adr/ADR-0009-athlete-profiles-and-training-context.md): session or
explicit goals/time override normal preferences, equipment applies location
deltas, while restrictions/requirements accumulate. `ResolvedTrainingContext`
retains each preference, restriction, priority, and exercise constraint with
its source (`athlete_profile`, `program`, `location_profile`, `session`, or
`explicit_request`). Hosts can use this structured provenance in an interface
without parsing prose.

Invalid ranges, duplicate stable IDs, contradictory preferences, unknown
locations, malformed observations, invalid capability measurements, and
contradictory equipment deltas are validation issues. Missing data has no
invented default: no experience means unknown, no readiness means no
observation, and no muscle priority means no explicit priority.

## Observations, not calculated state

Readiness is time-bound input such as an athlete-reported soreness value and
provenance. It is not a recovery score. Capability observations are evidence
such as a recent performance or externally supplied estimated 1RM. They are not
progression method state. Future models may interpret either value, but do not
silently change explicit preferences or profile fields from behavior.

## Historical behavior and persistence

Hosts advance the profile revision for programming-relevant changes; the
resolved snapshot records that revision and its fingerprint. Persist or export
the profile/location state when an adapter supports it, but persistence is never
required: a custom host can provide a minimal `{ id: "opaque-id" }` profile and
direct request snapshots. Do not export host account/auth details.

The recommendation stores the minimal resolved decision inputs it used. If a
profile changes from chest emphasis at revision 17 to back emphasis at revision
18, replaying a revision-17 recommendation still uses its captured context; it
does not query revision 18. Workout swaps likewise remain workout events, not
implicit profile edits.

## Current scope

This substrate intentionally does not optimize the workout around time,
readiness, priorities, or goals yet. It does not implement adaptive composition,
weekly volume, recovery, mesocycles, schedule adaptation, behavioral learning,
capability aggregation, medical assessment, accounts, or wearables. Those
features can consume the resolved context in later work.
