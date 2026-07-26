# RPE top-set/backoff methodology v1

Methodology ID: `caudex.rpe-top-set-backoff`

Configuration version: `1`

State schema version: `1`

CWE-040 defines and validates this methodology contract. CWE-041 defines the
top-set recommendation below. Backoff prescription and evaluation behavior
belong to CWE-042.

## Configuration

- `initialEstimatedOneRepMax` is a non-negative mass measurement used when
  usable evidence and state are absent.
- `topSetRepetitions` is a positive integer.
- `targetRpe` is an exact decimal from 1 through 10.
- `backoff.calculation` explicitly selects either a percentage of the top-set
  load or a percentage of estimated 1RM.
- Backoff percentage is greater than zero and at most 100. Backoff repetitions
  are positive and set count is between 1 and 64.
- `rounding` specifies `nearest`, `up`, or `down` with a positive mass quantum
  using the estimated-1RM unit.
- `exertionPolicy.tolerance` defines the exact RPE dead band.
- Overshoot may hold or decrease the estimate; undershoot may hold or increase
  it. Estimate adjustment percentage is explicit.
- `estimationFormula` is `epley` in v1. Formula identity is state/result
  provenance and is never selected implicitly.

The authoritative schema is
[`rpe-top-set-backoff-config-v1.schema.json`](../../schemas/methodologies/rpe-top-set-backoff-config-v1.schema.json).

## State

State schema v1 contains unique per-exercise IDs and exact estimated-1RM mass
measurements. State units must match the configured initial estimate. State is a
proposal owned by the host and is never implicitly persisted or accepted.

The authoritative schema is
[`rpe-top-set-backoff-state-v1.schema.json`](../../schemas/methodologies/rpe-top-set-backoff-state-v1.schema.json).

## Top-set recommendation

The recommendation selects an estimated 1RM in this order:

1. The newest completed exercise's first completed `top` set with compatible
   load, repetitions, and exertion evidence.
2. The matching exercise's estimated 1RM from methodology state.
3. `initialEstimatedOneRepMax` from configuration.

History evidence must contain a positive integer `repetitions` metric and
exactly one `rpe` or `rir` metric. RPE is valid from 1 through 10; RIR is valid
from 0 through 9. The two scales are equivalent under `RPE = 10 - RIR`.
Conflicting or out-of-range evidence is rejected. A history load using a
different mass unit from configuration is rejected rather than converted
implicitly. Missing compatible evidence uses the next fallback and returns the
`history.insufficient_evidence` warning.

The Epley v1 calculation is:

```text
effective repetitions = completed repetitions + (10 - completed RPE)
estimated 1RM = completed load × (1 + effective repetitions / 30)

target effective repetitions = topSetRepetitions + (10 - targetRpe)
top-set load = estimated 1RM ÷ (1 + target effective repetitions / 30)
```

RIR evidence substitutes directly for `(10 - completed RPE)`. Intermediate
estimated 1RM and load values use exact decimal arithmetic at 0.001 mass-unit
precision, with ties rounded away from zero. The final load follows the
configured quantum and `nearest`, `up`, or `down` mode.

The result reports the estimated 1RM, evidence source, formula identity, target
repetitions and RPE, final load, and a stable explanation code identifying
whether history, state, or initial configuration determined the estimate.
