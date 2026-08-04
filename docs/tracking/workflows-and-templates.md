# Programming, Tracking, and Template Workflows

The public `caudex_workflows` Zig module bridges programming results and the
pure tracking lifecycle. It performs no I/O, persistence, clock reads, ID
generation, or hidden allocation in domain decisions.

## Recommendation workflow

`instantiateRecommendation` requires an accepted recommendation result plus
host-supplied workout, membership, set, acceptance, scope, and timestamp values.
It creates an active tracked workout and preserves:

- input and result fingerprints;
- methodology identity, version, and configuration version;
- optional methodology-state revision and fingerprint;
- accepted-recommendation ID;
- original exercise ordering, set ordering, kinds, and exact targets.

The live workout and immutable prescription are separate. Tracking edits change
the live structure while preserving the prescription. `collectModifications`
returns structured added, removed, and reordered exercise/set differences.

After completion, `completeForEvaluation` validates status, catalog references,
IDs, actual values, provenance, and output capacity before producing the
canonical `CompletedWorkout` consumed by evaluation. `proposeStateAcceptance`
turns an evaluation's optional next state into an explicit compare-and-set
proposal; it never persists or accepts state automatically.

## Templates

A `WorkoutTemplate` is reusable planned structure with a stable ID, display
metadata, ordered exercises and sets, exact optional targets, notes/tags, and a
revision. It is distinct from a recommendation, active workout, completed
workout, and methodology state.

`instantiateTemplate` requires host-supplied IDs and time and records template
ID/revision provenance. Canonical template documents use schema version 1;
their schema and deterministic fixture live under `schemas/templates/v1/` and
`fixtures/templates/`. Optional persistence exposes `WorkoutTemplateStore` with
optimistic revision checks. First-party adapter storage is implemented in the
adapter expansion phase.

