# Issue and explanation conventions

Status: authoritative v0 contract for CWE-004.

Caudex returns expected validation and methodology rejections as
`ValidationIssue` values. It returns material recommendation reasoning as
`Explanation` values. These records are deterministic public data, not logs or
exceptions.

Engine failures such as allocation failure, corrupt artifacts, serialization
failure, or an internal invariant violation are execution errors and are not
canonical issues. Persistence conflicts and adapter failures belong to the host
or optional adapter and must not use core issue namespaces.

## Code syntax and namespaces

Codes contain two or more lowercase dot-separated segments:

```text
namespace.reason
namespace.action.reason
```

Each segment begins with `a-z` and continues with `a-z`, `0-9`, or `_`. Codes do
not contain versions, IDs, display text, or array positions. The canonical
pattern is:

```regex
^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$
```

Issue namespaces describe the input or contract area:

- `schema` — canonical message version or shape
- `request` — cross-field request consistency
- `catalog` — exercise catalog integrity
- `athlete` — preferences, restrictions, or capabilities
- `history` — supplied completed-training evidence
- `session` — constraints for the requested session
- `measurement` — exact decimals, dimensions, or units
- `methodology` — selection, configuration, or state

Explanation namespaces describe the decision being explained:

- `exercise` — candidate selection or exclusion
- `load` — load prescription or change
- `repetitions` — repetition prescription
- `sets` — set prescription
- `session` — whole-session composition
- `progression` — performance/progression outcome
- `methodology` — methodology state or policy
- `alternative` — alternative ranking

First-party methodology-specific codes use a shared decision namespace when the
meaning is genuinely common. Otherwise, they begin with the methodology's
stable short namespace, such as `double_progression`. Third-party methodology
codes begin with a vendor-controlled namespace. A methodology must document
every code and parameter it emits.

## Paths and evidence references

`ValidationIssue.path` is an RFC 6901 JSON Pointer into the canonical request:

- The empty string identifies the complete request.
- `/catalog/0/id` identifies a concrete field.
- `/history/workouts/2/exercises/0/exerciseId` identifies nested array data.
- `~` is escaped as `~0`; `/` inside a token is escaped as `~1`.

Paths use canonical lower-camel-case JSON field names, not Zig symbols or
host-language aliases. A missing field points to the location where it would
appear, such as `/methodology/config/repRange`.

Each `Explanation.evidence[].path` follows the same pointer rules. Evidence
derived by the engine rather than copied from one input location uses the
reserved virtual root `/@derived`. For example,
`/@derived/history/lastCompletedExercise` identifies a deterministic summary.
The explanation's parameters carry the relevant value; the virtual path is not
an instruction to mutate the request.

Paths are diagnostic locations, not durable entity identifiers. Consumers must
not store them as database keys.

## Severity

The three stable severity values are:

- `error` — the condition prevents a valid requested calculation. A result with
  any error issue has `ok: false` and no accepted recommendation/evaluation.
- `warning` — calculation can succeed, but the host should surface an important
  limitation, assumption, or degraded input condition.
- `info` — non-problematic context useful for inspection or explanation.

An issue's severity is part of its semantic contract. Changing a code from
`warning` to `error`, or the reverse, changes control flow and is breaking.
Explanations normally use `info`; `warning` highlights an assumption or
tradeoff. Execution failures do not become `error` issues.

## Fields and compatibility

For issues:

- `code`, `path`, `message`, and `severity` are required.
- `parameters` contains structured canonical values needed to understand or
  localize the condition.
- `suggestion` is optional actionable fallback text.

For explanations:

- `id` is unique within one result and is referenced by recommendation items.
- `code`, `category`, `summary`, and `severity` are required.
- `subject` identifies the affected recommendation item when useful.
- `evidence` points to request data or deterministic derived summaries.
- `parameters` contains stable structured interpolation values.
- `ruleId` identifies a documented methodology rule when applicable.

Compatibility rules:

- A code's meaning, severity, and required parameter names are stable within a
  canonical schema major version.
- Removing a code, reusing it for a different condition, changing its severity,
  or changing the meaning/type of a parameter is breaking.
- Adding a new code is non-breaking. Consumers must implement an unknown-code
  fallback.
- Adding an optional parameter is non-breaking when existing parameters retain
  their meanings.
- Paths may become more specific without changing the underlying code meaning;
  consumers must not branch solely on exact array indexes.
- Human `message`, `summary`, and `suggestion` text may improve in patch
  releases. Their exact wording, punctuation, and capitalization are not stable.
- Tests should assert codes and structured parameters. They should assert human
  text only when testing a translation or documentation example.

## Localization

The engine emits English fallback text in `message`, `summary`, and
`suggestion`. v0 does not accept a locale and does not perform locale-sensitive
formatting.

Hosts localize by mapping `code` to their own message template and interpolating
documented `parameters`. They must fall back to the engine-provided text for an
unknown code. Hosts must not parse English text to determine behavior.

Parameters contain raw canonical values, including decimal strings and explicit
unit codes. They do not contain locale-formatted numbers or preassembled
sentences. This allows the host to apply its own number, unit, plural, and
grammar rules.

## Representative issue codes

These codes reserve representative v0 meanings; individual implementation
issues decide when they are emitted.

| Code | Severity | Meaning |
| --- | --- | --- |
| `schema.unsupported_version` | error | The canonical schema version is unsupported. |
| `request.missing_required_input` | error | A calculation-required input is absent. |
| `request.conflicting_constraints` | error | Two explicit request constraints cannot both be satisfied. |
| `catalog.duplicate_exercise_id` | error | The catalog repeats an exercise ID. |
| `catalog.exercise_reference_missing` | error | A request reference is absent from the catalog. |
| `athlete.restriction_invalid` | error | A host restriction has an invalid shape or reference. |
| `history.exercise_reference_missing` | error | Completed history references an absent catalog exercise. |
| `history.insufficient_evidence` | warning | The calculation has less history than the methodology prefers. |
| `session.required_exercise_unavailable` | error | A required exercise violates another hard constraint. |
| `session.time_budget_unsatisfied` | error | Required work cannot fit the explicit time budget. |
| `measurement.invalid_decimal` | error | An authoritative decimal string is invalid. |
| `measurement.unsupported_unit` | error | A metric uses an unsupported unit. |
| `measurement.incompatible_units` | error | Values requiring comparison have incompatible dimensions. |
| `methodology.unknown` | error | No installed methodology matches the requested ID. |
| `methodology.config_invalid` | error | Methodology configuration is invalid. |
| `methodology.state_unsupported_version` | error | Methodology state cannot be read or migrated. |

## Representative explanation codes

| Code | Typical severity | Meaning |
| --- | --- | --- |
| `exercise.selected.required` | info | A host constraint required the exercise. |
| `exercise.selected.preference` | info | Athlete preference favored the exercise. |
| `exercise.selected.available_equipment` | info | Available equipment supported the selection. |
| `exercise.excluded.user_disliked` | info | Athlete preference excluded or deprioritized the exercise. |
| `exercise.excluded.host_restriction` | info | An explicit host restriction excluded the exercise. |
| `exercise.excluded.equipment_unavailable` | info | Required equipment was unavailable. |
| `load.increased.rep_range_completed` | info | Completed performance satisfied the configured advancement rule. |
| `load.held.partial_completion` | info | Partial completion caused load to remain unchanged. |
| `repetitions.selected.methodology_target` | info | The methodology selected the repetition target. |
| `sets.reduced.available_time` | warning | A time constraint reduced optional sets. |
| `session.shortened.minimum_viable_policy` | warning | The methodology used its minimum viable session policy. |
| `progression.held.insufficient_evidence` | warning | Evidence was insufficient to advance progression. |
| `methodology.state.initialized` | info | No prior state was supplied, so initial state was proposed. |
| `methodology.state.advanced` | info | Completed performance advanced proposed state. |
| `alternative.ranked.stable_tiebreak` | info | Stable deterministic ordering resolved equal candidates. |

The catalog contains 31 representative codes in total. It is not an exhaustive
enumeration and does not imply that CWE-004 implements any emitting behavior.
