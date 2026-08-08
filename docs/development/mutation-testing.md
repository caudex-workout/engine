# Mutation testing

The mutation harness asks whether methodology tests detect plausible changes
to deterministic decision rules. The initial scope is the double-progression
and RPE top-set/backoff modules. It covers comparison, boolean, boundary,
rounding, arithmetic-direction, progression, and threshold mutations. The
explicit descriptor format in `tests/mutation/mutations.json` contains an ID,
file, category, exact expected source expression, replacement, and test file.

```sh
zig build mutation-smoke
zig build mutation-test
zig build mutation-test -- --id dp_success_threshold
```

Every mutant runs in a fresh temporary copy of `src/`; the real working tree
and uncommitted changes are never modified. The runner requires exactly one
source match, runs the real module test suite, enforces a 10-second per-mutant
timeout, and writes `.zig-cache/mutation/report.json`.

Results are `killed`, `survived-actionable`, `equivalent`, `invalid`,
`compile-error`, or `timeout`. The score is killed divided by killed plus
survived-actionable. Equivalent mutants must be explicitly checked into
`tests/mutation/equivalents.json` with a reason; they are never silently
ignored. A surviving actionable mutant requires investigation and usually a
regression test. Do not lower a threshold merely to make the report pass.

Add a mutation only when it represents a plausible domain defect, use a narrow
exact expression, and confirm the relevant test target kills it. If the
mutation is truly equivalent over the validated input domain, document the
proof in `equivalents.json` for review.
