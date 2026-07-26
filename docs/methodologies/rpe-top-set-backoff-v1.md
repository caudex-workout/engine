# RPE top-set/backoff methodology v1

Methodology ID: `caudex.rpe-top-set-backoff`

Configuration version: `1`

State schema version: `1`

CWE-040 defines and validates this methodology contract. Recommendation,
backoff prescription, and evaluation behavior belong to CWE-041 and CWE-042.

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
