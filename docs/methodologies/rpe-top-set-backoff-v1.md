# RPE top-set/backoff methodology v1

Methodology ID: `caudex.rpe-top-set-backoff`

Configuration version: `1`

State schema version: `1`

CWE-040 defines and validates this methodology contract. CWE-041 defines the
top-set recommendation below. CWE-042 defines backoff prescription and
evaluation behavior.

## When to use it

Choose RPE top-set/backoff when the host records a primary top set with RPE or
RIR and wants backoff work derived from either that top-set load or an estimated
1RM. It fits integrations that intentionally use subjective exertion evidence
and want an explicit tolerance policy for updating the next estimate.

Use double progression instead when the desired rule is to advance repetitions
through a range before adding load and the host does not collect dependable RPE
or RIR evidence.

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

## Backoff prescription

`backoff.calculation` determines the only calculation base:

- `percentage_of_top_set` applies `backoff.percentage` to the rounded
  recommended top-set load.
- `percentage_of_estimated_one_rep_max` applies the percentage to the
  recommendation's estimated 1RM.

The percentage product uses 0.001 mass-unit precision with ties rounded away
from zero. The resulting load then follows the configured load-rounding mode
and quantum. Every backoff set receives that load, `backoff.repetitions`, and
the configured `backoff.setCount`. The explanation code identifies which base
was used.

## Performance evaluation and proposed state

Evaluation considers each exercise's completed `top` set. It first derives an
observed estimated 1RM from the completed load, repetitions, and RPE/RIR using
the same Epley evidence calculation as recommendation. It then independently
applies exertion policy:

- Actual RPE inside the inclusive
  `[targetRpe - tolerance, targetRpe + tolerance]` band holds the observed
  estimate.
- RPE above the band follows `onOvershoot`: hold, or reduce the observed
  estimate by `estimateAdjustmentPercentage`.
- RPE below the band follows `onUndershoot`: hold, or increase the observed
  estimate by `estimateAdjustmentPercentage`.

Adjustment uses 0.001 mass-unit precision with ties rounded away from zero.
Evaluation reports separate stable explanations for the evidence estimate and
the policy decision. Its versioned next state is a proposal written into
caller-provided buffers; input state is borrowed, remains unchanged, and is
never implicitly accepted or persisted.

## Explanation and warning codes

| Code | Meaning |
| --- | --- |
| `load.selected.history_estimated_one_rep_max` | Compatible completed top-set evidence supplied the estimate. |
| `load.selected.state_estimated_one_rep_max` | Existing methodology state supplied the estimate. |
| `load.selected.initial_estimated_one_rep_max` | Configuration supplied the fallback estimate. |
| `backoff.selected.percentage_of_top_set` | Backoff load used the rounded recommended top-set load. |
| `backoff.selected.percentage_of_estimated_one_rep_max` | Backoff load used the estimated 1RM. |
| `estimate.observed.completed_top_set` | Evaluation derived an observed estimate from a completed top set. |
| `estimate.decreased.rpe_overshoot` | RPE above the tolerance band decreased the estimate. |
| `estimate.increased.rpe_undershoot` | RPE below the tolerance band increased the estimate. |
| `estimate.held.rpe_overshoot` | RPE above the tolerance band followed a hold policy. |
| `estimate.held.rpe_undershoot` | RPE below the tolerance band followed a hold policy. |
| `estimate.held.rpe_within_tolerance` | RPE inside the inclusive tolerance band held the estimate. |
| `history.insufficient_evidence` | No compatible completed top-set evidence was available. |

Configuration and state rejection use the shared issue codes
`methodology.config_invalid`, `methodology.state_invalid`, and
`methodology.state_unsupported_version`.

## Limitations

- Version 1 supports only the Epley formula. It does not compare or dynamically
  select estimation formulas.
- Recommendation uses only the newest compatible first completed `top` set for
  an exercise; it does not aggregate multiple sets or model statistical
  confidence.
- RPE and RIR are accepted as explicit host observations. The methodology does
  not judge their accuracy or infer them from bar speed, sensors, or free text.
- It does not prescribe warmups, fatigue management, deloads, training blocks,
  or long-term calendars.
- It does not convert load units or infer missing load, repetition, or exertion
  evidence.
- The percentage and exertion policies are deterministic configuration rules,
  not individualized medical or recovery advice.

RPE top-set/backoff is not universally better than double progression. It
represents a different evidence and prescription model; the host should choose
the model that matches the data it can supply and the progression behavior it
wants to expose.
