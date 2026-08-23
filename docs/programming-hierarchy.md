# Programming hierarchy

Caudex separates a program's lifecycle, its session-composition policy,
session-wide exercise selection, and exercise-local progression:

```text
program lifecycle -> program strategy -> planning/optimization -> progression
```

The authoritative session-recommendation flow is:

```text
PlannedSessionIntent
  -> build PlanningProblem
  -> solve
  -> ResolvedSessionPlan
  -> prescribe each selected progression lane
  -> SessionRecommendation
```

Each arrow operates on an explicit snapshot and returns a value for the host
to accept or persist. None of these capabilities reads host storage, a clock,
or hidden mutable state.

## Responsibilities

Program lifecycle resolves a due occurrence and proposes program-state changes.
A program strategy declares the session's composition intent: required and
optional slots, candidate universes, preferences, ordering, and an
already-resolved progression lane for every slot. Strategy policy and the
explicit host session context together supply hard constraints and typed
objectives. Neither searches the exercise catalog.

The planner converts that intent and explicit session facts into an immutable
`PlanningProblem`. It owns candidate generation, hard filtering, local ranking,
bounded session optimization, deterministic final ordering, explanations, and
provenance. Fixed work uses the same model: a fixed slot permits exactly one
exercise. An adaptive slot may offer a constrained catalog or allowlist, but
its progression lane is still fixed before selection.

`ResolvedSessionPlan` records the chosen exercise for each included slot, the
exact progression lane to prescribe, its selection source, duration estimate,
tiered score contribution, and reason references. Progression then prescribes
sets, repetitions, and loads for those selected lanes, evaluates completed
work, and returns separate lane-state proposals. Progression never chooses an
exercise; planning never mutates progression state.

Required work is never silently omitted. The planner may omit an optional slot
only as an explicit optimizer tradeoff, recorded in `omitted_slots` with a
reason. Program-state proposals and progression-state proposals remain
independent host acceptance decisions.

## Constraints, objectives, and ordering

A `PlanningProblem` is the complete decision snapshot: origin/provenance,
explicit `as_of` time, planner catalog, slots, session constraints, typed
objectives, and slot/exercise duration estimates. Multi-value taxonomy
requirements specify `any` or `all` matching. Candidate allowlists and
exclusions are hard eligibility rules; preferred sets and exercise preferences
are objectives, not eligibility shortcuts.

Hard constraints are checked before scoring and never become score terms. The
planner compares feasible plans lexicographically by program correctness,
training quality, then user preference; a weight only has meaning within its
fixed tier. Final session order is a deterministic topological ordering of
declared before/after edges and priority tiers, rather than a search over every
permutation. The returned resolved plan can be independently validated against
the original problem without trusting optimizer bookkeeping.

## Bounded solver outcomes

The direct Zig planner is deliberately bounded and stateless. A problem may
contain at most 16 slots, 512 catalog exercises, 64 objectives, and 1,024
duration estimates. A solve retains 1–32 candidates per slot (default 8) and
examines at most `beam_width` complete assignments (default 256; the `u16`
option bounds it to 65,535). These are contract limits, not tuning hints.

The low-level solver takes caller-owned workspace and does not allocate while
solving. `planning.FixedWorkspace` covers the documented maximums; the
allocator-backed `planning.Workspace.init` is a visible convenience wrapper
whose result storage remains valid only until that workspace is reused or
freed. The planner also bounds reasons, ordering data, candidate storage, and
violation storage through that workspace. A caller-provided seed may change
ties deterministically; the chosen tie-break policy and explored-state count
are recorded in planner provenance. Stable identifiers are the default tie
break.

`solve` returns a domain result, not a nullable recommendation:

| Result | Meaning | Host response |
| --- | --- | --- |
| `resolved` | A plan was found within the declared bounds. | Validate if required by the boundary, then prescribe its progression lanes. |
| `infeasible` | The planner proved that the supplied problem contradicts its hard constraints. | Surface the recorded violations; do not retry as though this were a runtime failure. |
| `search_exhausted` | Candidate retention or the configured search bound prevented a proof or a resolved plan. | Increase only an explicit bound/workspace as appropriate, simplify the request, or report that no conclusion was reached. |

In particular, a bounded failure is not evidence that the session is
infeasible. Conversely, a problem or workspace limit error is an invalid or
unsupported request at this API boundary, not an `infeasible` result.

## State and identity

Program state belongs to the lifecycle/strategy; progression state belongs to
one lane and its `stateId`. That ID names a program lane, not an exercise. For
example, `block-2-primary-squat` and `block-2-secondary-squat` can both use
squat without sharing state. Evaluation routes from accepted recommendation
provenance—slot ID, state ID, progression method identity/version,
configuration, selected exercise, and input state—not from a bare exercise ID.

Persist the normalized problem/recommendation fingerprint, selected planner
provenance, resolved context, catalog projection, and accepted proposals with a
decision when replay matters. Semantically irrelevant input ordering is
canonicalized for the problem fingerprint; historical replay must not replace
missing facts with current profile, catalog, or calendar data.

## Transitional v0.1 surfaces

The existing `engine.recommendSession` / `engine.evaluatePerformance`,
canonical `recommend` / `evaluate`, generic `Methodology` registry, and
`programming.recommendFixedSession` / `programming.evaluateFixedSession` are
still supported historical v0.1 surfaces. Their single-methodology and
fixed-session semantics are not silently reinterpreted as the planning-kernel
protocol. Likewise, existing C, WASM/npm, portable, and persistence records
remain on their released contracts until an explicit, versioned protocol
migration ships.

The direct Zig session-kernel path currently exposes
`planning.buildProblem`, `planning.solve`, and
`programming.recommendPlannedSession`. It is the architectural target for new
session-wide selection work. The legacy paths are transitional compatibility
surfaces, not evidence that they have already been removed or migrated.

For reusable definitions, schedules, phases, occurrences, and explicit
program-state advancement, see [program planning](programs.md). The governing
decision is [ADR-0011](adr/ADR-0011-deterministic-session-planning-kernel.md);
it supersedes only the fixed-session-composition and generic-methodology parts
of ADR-0007 and ADR-0010, while preserving host-owned state and acceptance.
