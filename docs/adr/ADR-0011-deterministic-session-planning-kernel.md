# ADR-0011: Use a Deterministic Session-Planning Kernel

- **Status:** Accepted
- **Date:** 2026-08-17
- **Supersedes:** The fixed-session composition and generic-methodology portions
  of ADR-0007 and ADR-0010
- **Preserves:** Host-owned state and acceptance, explicit snapshots, replay,
  and deterministic behavior

## Context

The original programming architecture combined three different decisions:
program composition, exercise selection, and exercise-local progression. Its
fixed-session path was deterministic, but adaptive slots were resolved by a
greedy first match and the generic `Methodology` registry allowed one opaque
implementation to own the whole recommendation operation. That ownership
cannot support session-wide constraints or optimization without turning each
program strategy or progression method into a bespoke planner.

## Decision

Programming is divided into four capabilities with inward-only dependencies:

```text
program lifecycle -> program strategy -> planning/optimization -> progression
```

The authoritative recommendation flow is:

```text
PlannedSessionIntent
  -> build PlanningProblem
  -> solve
  -> ResolvedSessionPlan
  -> prescribe each progression lane
  -> SessionRecommendation
```

Program lifecycle resolves a due occurrence and proposes program-state
changes. A strategy expresses composition intent: required and optional slots,
candidate universes, preferences, ordering, constraints, objectives, and fully
resolved progression lanes. It does not search a catalog. Progression owns
exercise-local configuration, state, prescription, evaluation, and explicit
state proposals. It never selects an exercise.

The shared planner owns deterministic candidate generation, hard filtering,
local ranking, bounded session optimization, final ordering, explanations, and
provenance. Fixed work uses the same planner: a fixed slot has one permitted
exercise.

### Planning contract

`PlanningProblem` is a complete immutable snapshot containing origin, explicit
time, a planner catalog, slots, session constraints, typed objectives, and
slot/exercise duration estimates. Multi-value taxonomy requirements state
`any` or `all` semantics. Candidate allowlists are hard eligibility rules;
preferred sets are soft objectives. Progression compatibility is derived from
the lane method.

Hard constraints are evaluated before scoring and never become score
contributions. Feasible plans are compared lexicographically using the tiers
program correctness, training quality, and user preference. Weights only
operate inside their tier.

The domain result distinguishes a resolved plan, a proved contradiction, and
bounded search exhaustion. Failure to find a plan within configured bounds is
not proof of infeasibility. Required work is never silently omitted; omitted
optional work is recorded with a reason.

### Search and resources

The production optimizer is iterative, stateless, and bounded. Candidate
retention, search width/state count, slots, ordering edges, reasons, and memory
have explicit limits. The low-level API uses caller-owned workspace; an
allocator-backed convenience wrapper may allocate that workspace visibly.
Stable identifiers are the default tie break. A caller-provided seed may alter
ties deterministically and is recorded in provenance.

Final ordering is a deterministic topological ordering over explicit edges and
priority tiers, not a search over permutations. An independent validator
checks the returned plan against every hard constraint without trusting solver
internals. Tiny exhaustive search exists only as a test oracle.

### Identity and explanation

The normalized, decision-relevant problem has a deterministic fingerprint.
Semantically irrelevant ordering is canonicalized before hashing. Resolved
slots retain the exact progression lane, fixed-versus-optimized selection
source, local candidate statistics, duration, tiered contribution, and typed
reason references. Local rank is evidence about candidate generation, not a
claim that it caused the globally optimal choice.

Direct Zig APIs use strong IDs, enums, and tagged unions. Dynamic identifiers,
JSON representations, discovery metadata, and C/WASM/npm conversions live at
protocol boundaries. No optimizer DSL, arbitrary callback language, or runtime
plugin system is introduced.

## Consequences

- Session-wide tradeoffs are solved once by Caudex rather than reimplemented
  by strategies.
- Fixed and adaptive strategies share one decision path and one validator.
- Recommendation provenance is sufficient to route completed exercises back
  to their progression lanes.
- Program-state and progression-state outputs remain separate proposals that
  a host may accept or reject.
- The generic `Methodology` registry, legacy engine entry point, greedy slot
  materialization, and old filtering/ordering ownership are removed as their
  responsibilities migrate.
- Protocol and persistence migrations must version historical methodology
  records; they must not reinterpret those records as progression lanes.

## Rejected alternatives

- **Let each strategy search the catalog:** duplicates mechanics and prevents
  consistent constraints, bounds, and explanations.
- **Let progression choose exercises:** mixes session composition with
  exercise-local state and prescription.
- **Use one scalar score:** allows low-value preferences to overpower program
  correctness.
- **Treat bounded failure as infeasible:** makes an unproved domain claim.
- **Add a general solver DSL or callbacks:** weakens the typed domain boundary
  and makes determinism and resource use difficult to audit.
- **Keep a separate fixed-session path:** creates two planning semantics for
  the same domain operation.
