# Exercise selection and substitution

`exercise_selection` is the deterministic, allocation-free domain capability
for choosing an exercise for a training role and finding semantic substitutes.
Hosts provide a catalog, role, today's constraints, and caller-owned result
storage. The module does not prescribe sets or loads, mutate programs, or own
progression state.

## Decision model

`Role` describes the slot being filled: target muscles, movement patterns,
families, an optional fixed exercise, laterality or structural requirements,
and progression compatibility. This keeps a primary horizontal press distinct
from a chest isolation or a fixed competition lift.

Eligibility runs before scoring. Explicit exclusions, fixed conflicts,
unavailable equipment combinations, restrictions, incompatible progression,
and unmet role requirements reject a candidate. A rejected candidate cannot
win through another score component.

Eligible candidates retain separate bounded score components for target,
movement, family, preference, continuity, novelty, overlap, setup, and
substitution similarity. Policy weights are explicit signed integers. Final
ordering is total score descending, then canonical exercise ID ascending, so
catalog insertion order cannot affect ties.

`preferred`, `disliked`, and `excluded` are different policies. Preference and
dislike adjust ranking; exclusion is hard. A role's fixed exercise is also a
hard requirement and produces structured rejection evidence when it cannot be
used.

Continuity is explicit: `dynamic`, `sticky`, `fixed`, or `novelty_biased`.
Recent exercise IDs and already selected exercise/family IDs are supplied by
the host. This lets the selector reward block continuity or penalize redundant
session overlap without learning hidden preferences or enforcing novelty.

## Substitution

`findSubstitutes` first applies the same hard role and context eligibility,
then ranks the remaining exercises by role-aware semantic similarity. It uses
represented movement, target, family/relationship, structural, and loading
facts; it never infers equivalence from exercise names.

Substitution results explicitly report `progression_state_transfer =
independent`. Preserving today's role never silently transfers exercise-local
loads, capability, history, or methodology state. A host may route state only
through a separate explicit progression policy.

## Session composition

The session planner uses the selector's shared exercise-local eligibility for
role matching, equipment, restriction, and progression checks. It then adds slot-universe,
duration, ordering, and global assignment constraints. Global reuse, movement
variety, and equipment-transition objectives remain planner concerns rather
than being duplicated in the session composer.

The standalone API returns a winner, bounded viable alternatives, bounded
rejections with structured reason codes, and an explicit unsatisfiable state.
Requests support at most 2,048 catalog exercises, 64 alternatives, and 64
rejections. Ranking retains only the requested top candidates while scanning
the catalog, and duplicate canonical IDs cannot appear in one result.
Direct Zig consumers access it as `caudex.exercise_selection.rankExercises`
and `caudex.exercise_selection.findSubstitutes`.

The generic C/WASM execution boundary exposes `rankExercises` and
`findSubstitutes`; the npm facade provides synchronous methods with the same
names and strong request/result types.
