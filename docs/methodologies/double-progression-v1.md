# Double progression methodology v1

Methodology ID: `caudex.double-progression`

Configuration version: `1`

State schema version: `1`

Double progression advances repetitions within a configured range, then
advances load after the configured successful-set threshold is met. CWE-030
defines and validates the contract only; recommendation and evaluation behavior
is implemented by later issues.

## Configuration

- `repRange` is inclusive. Both values are positive and `min <= max`.
- `workingSets` is the prescribed number of working sets.
- `advancementCriteria.minimumSuccessfulSets` cannot exceed `workingSets`.
- `advancementCriteria.minimumRepetitions` must be inside `repRange`.
- `loadIncrement` is the exact load added after advancement criteria are met.
- `failurePolicy.onPartial` and `onFailure` explicitly choose `hold` or
  `regress`. `regressionAmount` is the exact load removed by regression.
- `rounding.mode` is `nearest`, `up`, or `down`. `rounding.quantum` is the
  smallest representable load step.
- Load increment, regression amount, and rounding quantum must be positive mass
  measurements using one unit within each resolved configuration.
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
