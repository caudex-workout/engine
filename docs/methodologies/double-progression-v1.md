# Double progression methodology v1

Methodology ID: `caudex.double-progression`

Configuration version: `1`

State schema version: `1`

Double progression advances repetitions within a configured range, then
advances load after the configured successful-set threshold is met.

## When to use it

Choose double progression when the host wants a fixed number of working sets,
an explicit repetition range, and a predictable rule that increases
repetitions before load. It fits integrations whose completed sets reliably
record load, repetitions, and completion status but do not require subjective
RPE or RIR observations.

It is also useful when exercise-specific rep ranges, increments, or failure
policies must be configured through `exerciseOverrides`.

## Configuration

- `repRange` is inclusive. Both values are positive and `min <= max`.
- `workingSets` is the prescribed number of working sets.
- `advancementCriteria.minimumSuccessfulSets` cannot exceed `workingSets`.
- `advancementCriteria.minimumRepetitions` must be inside `repRange`.
- `initialLoad` is the explicit first-exposure load when neither usable state
  nor completed exercise history exists.
- `loadIncrement` is the exact load added after advancement criteria are met.
- `failurePolicy.onPartial` and `onFailure` explicitly choose `hold` or
  `regress`. `regressionAmount` is the exact load removed by regression.
- `rounding.mode` is `nearest`, `up`, or `down`. `rounding.quantum` is the
  smallest representable load step.
- Initial load is non-negative. Load increment, regression amount, and rounding
  quantum are positive mass measurements. All four values use one unit within
  each resolved configuration.
- `exerciseOverrides` selectively replaces fields for a host exercise ID.
  Override IDs are unique. Omitted fields inherit the top-level value, and the
  fully resolved override must satisfy the same validation rules.

The authoritative schema is
[`double-progression-config-v1.schema.json`](../../schemas/methodologies/double-progression-config-v1.schema.json).

## State

State is a proposal owned by the host. Calculating or evaluating a session does
not persist or accept it.

Each exercise state contains:

- `exerciseId`
- Exact current `load`
- `targetRepetitions`, constrained by the resolved exercise rep range

Exercise IDs are unique. Loads are non-negative mass measurements. The state
envelope has `schemaVersion: 1`; unsupported versions produce
`methodology.state_unsupported_version`.

The authoritative schema is
[`double-progression-state-v1.schema.json`](../../schemas/methodologies/double-progression-state-v1.schema.json).

## Recommendation behavior

- With neither usable state nor completed exercise history, the methodology
  prescribes `initialLoad`, `repRange.min`, and `workingSets`, and returns
  `history.insufficient_evidence`.
- State supplies the current load and repetition target when present. Without a
  matching completed performance, those values are held with the same warning.
- Meeting `minimumSuccessfulSets` at the current target advances repetitions by
  one. Meeting the threshold at `minimumRepetitions` adds `loadIncrement` and
  resets repetitions to `repRange.min`.
- Partial and failed sets use their respective configured `hold` or `regress`
  action. Regression subtracts `regressionAmount`, never below zero, resets
  repetitions to the range minimum, and applies configured rounding.
- Rounding is applied to initial, advanced, and regressed loads. Held loads are
  preserved exactly.
- An explicit positive session working-set cap may reduce `workingSets`. The
  recommendation returns `sets.reduced.available_time`; the methodology never
  silently applies a cap.
- Completed set load units must match state/config units. Unit mismatches are
  rejected rather than converted implicitly.
- Each decision returns a stable explanation code and methodology rule ID.

## Performance evaluation and proposed state

Evaluation applies the same advancement, hold, regression, exact-unit, and
rounding rules as recommendation to a host-supplied completed workout.

- Each completed exercise receives an `advanced`, `held`, `regressed`, or
  `insufficient_evidence` outcome and the explanation for the decision.
- Evaluated exercise entries are inserted or replaced in a proposed state.
- State entries for exercises absent from the completed workout are preserved.
- The proposal always uses state schema version `1`.
- Evaluation borrows and never mutates the supplied state or workout. The host
  may discard the proposal without any persistence or other side effect.
- Re-evaluating identical config, state, and completed performance returns the
  same outcomes and state JSON.

## Explanation and warning codes

| Code | Meaning |
| --- | --- |
| `double_progression.prescribed.initial` | Initial configuration supplied the first prescription. |
| `double_progression.prescribed.state_without_history` | Existing state was held because no matching completed performance was available. |
| `repetitions.increased.completed_target` | Successful performance advanced the repetition target within the configured range. |
| `load.increased.rep_range_completed` | Successful performance at the advancement threshold increased load and reset repetitions. |
| `load.held.partial_completion` | Partial completion followed a configured hold policy. |
| `load.regressed.partial_completion` | Partial completion followed a configured regression policy. |
| `load.held.failed_completion` | Failed completion followed a configured hold policy. |
| `load.regressed.failed_completion` | Failed completion followed a configured regression policy. |
| `load.held.insufficient_successful_sets` | Completed evidence did not meet the configured successful-set threshold. |
| `sets.reduced.available_time` | An explicit session set cap reduced the working-set prescription. |
| `history.insufficient_evidence` | No compatible completed performance was available for progression. |

Configuration and state rejection use the shared issue codes
`methodology.config_invalid`, `methodology.state_invalid`, and
`methodology.state_unsupported_version`. Issue codes describe rejected inputs;
the decision codes above describe a completed calculation.

## Limitations

- Version 1 progresses one exercise independently from its compatible completed
  performance. It does not coordinate blocks, phases, or long-term calendars.
- It does not infer fatigue, readiness, recovery, deload timing, or medical
  restrictions. A host must supply any relevant session constraints.
- It does not convert load units or infer missing loads and repetitions.
- The failure policy is deliberately limited to hold or subtract a configured
  amount. It is not a generalized progression language.
- Exercise overrides are exact host-ID matches; the methodology does not infer
  equivalent exercises.

Double progression is not universally better than RPE top-set/backoff. It is
the more direct choice when progression should follow rep-range completion;
RPE top-set/backoff models a different workflow based on exertion evidence and
an estimated 1RM.

## Conformance suite

The checked-in
[`double-progression-conformance-v1.json`](../../fixtures/methodologies/double-progression-conformance-v1.json)
fixture covers first exposure, bottom and top of the rep range, load
advancement, load hold, regression, a missed set, changed units, a short
session, and an exercise override. Contract tests decode and execute every case
through the public methodology API.
