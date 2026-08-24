# Muscle-volume contract

Caudex derives muscle volume from immutable raw prescription and completed
work. Program intent, prescribed work, performed work, and credited muscle
volume are separate values and are never substituted for one another.

## Credit units and policies

`volume.units_per_set` is one million. Public totals are integer millionths of
a set-equivalent, avoiding floating-point and iteration-order differences. A
credit is a programming heuristic, not a physiological percentage and not an
"effective set" claim.

Credit per muscle/set and total contributing work are bounded so every public
total remains an exact JavaScript safe integer at the npm/WASM boundary.

The first-party `caudex.contribution-sets` policy counts completed `working`,
`top`, and `backoff`
sets, gives primary contributions one unit and secondary contributions one
half unit, and excludes stabilizers, warmups, partial, failed, and skipped sets
by default. Hosts and strategies can explicitly opt into partial or failed
work, configure qualifying kinds and role credits, count primary work only, or
use catalog weights. Catalog decimals are rounded half-up to the nearest
millionth. Policy identity and version are returned with every state.

One tracked set is one raw set event. Unilateral/per-side repetition semantics
do not multiply that event; a host that records independent left and right set
events has explicitly recorded two events.

## Inputs and replay

`volume.calculate` accepts an exercise catalog, canonical completed history,
an explicit prescribed-workout snapshot, resolved targets, an explicit scope,
and a credit policy. Prescription is a separate input because completed
history alone cannot distinguish original prescription from athlete-added
work. Completed credit always follows the exercise actually recorded, so a
substitution uses the substituted exercise's contribution metadata.

Scopes are either all supplied history or an inclusive bounded interval. A
program-cycle/microcycle caller supplies the canonical bounded slice belonging
to that occurrence sequence; the volume layer does not infer program cycles
from weekdays. This keeps rotations and asynchronous schedules coherent.

Derived totals retain workout, exercise, set, muscle role, phase, credit, and
policy provenance. Canonical history therefore remains replayable under a
different policy without migration or mutation.

## Targets, remaining work, and frequency

Targets may define a minimum, preferred range, hard cap, desired exposures,
priority weight, and resolved source. Bounds must satisfy:

`minimum <= preferred minimum <= preferred maximum <= hard cap`

Missing bounds stay missing; they are not invented. The state derives required
remaining, preferred remaining, maximum additional credit, excess, and a
structured relationship-to-target status. These statuses make no claims about
fatigue, readiness, recovery, soreness, or overtraining.

An exposure is one qualifying completed workout involving a muscle regardless
of the number of contributing exercises or sets in that workout. Exposure
count and last exposure are reported separately from volume.

`volume.estimate` applies the same policy to proposed exercise/set counts.
`session_composer.composeIntentWithVolume` uses that prospective impact and
returns a structured conflict if direct or indirect compound credit would
exceed a resolved hard cap. The composer owns allocation; the volume module
owns credit and target relationships.
