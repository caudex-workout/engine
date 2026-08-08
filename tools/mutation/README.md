# Mutation harness

`mutations.json` is an explicit, reviewable list of token-checked mutations in
methodology decision code. The runner copies `src/` to a temporary directory,
requires exactly one match for the declared expression, runs that file's real
Zig tests, records the result, and removes the temporary directory. The
working tree is never mutated and uncommitted changes are supported.

```sh
zig build mutation-smoke
zig build mutation-test
zig build mutation-test -- --id dp_success_threshold
```

Statuses are `killed`, `survived-actionable`, `equivalent`, `invalid`,
`compile-error`, and `timeout`. The score is killed divided by killed plus
survived-actionable; equivalent, invalid, compile-error, and timeout mutants
are reported separately and do not improve the score. Equivalent mutants must
be recorded with a reason in `tests/mutation/equivalents.json`; survivors
require investigation, not automatic suppression.
