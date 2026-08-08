# `tests/` instructions

Tests are the executable evidence for observable behavior across Zig, tracking,
adapters, C/WASM, npm, CLI/TUI, schemas, fixtures, documentation, and release
artifacts. Prefer tests that exercise public boundaries and both positive and
negative space.

- Preserve deterministic seeds, bounded inputs, stable ordering, canonical
  fixtures, and useful failure reproducers. Fuzz cases must remain bounded and
  reproducible; retain generated reproducers under the documented cache path
  and minimize corpus additions.
- Historical compatibility fixtures under `tests/compat/` are released
  evidence, not ordinary golden files. Never update an expected result merely
  because an implementation changed. Change it only for an intentional,
  classified compatibility change with the required docs, snapshots, and
  migration/release rationale.
- Use reference-model/property tests, contract kits, failure injection,
  cross-language conformance, and benchmark tests where they own a real
  invariant. A refactor must not pass by weakening assertions or deleting
  negative cases.
- Treat surviving actionable mutation results as defects to investigate,
  usually with a regression test. Record an equivalent mutant with a checked-in
  reason only after proving equivalence; never classify it that way to improve a
  score.
- Add tests below, at, and above new product limits. Keep test helpers and
  fixtures explicit and bounded even when they construct intentionally invalid
  states.

Use `zig build check` for the full suite. For focused work, use the relevant
leaf target from `build.zig`; use `zig build fuzz-smoke`, a bounded `fuzz-*`
target, `zig build mutation-smoke`, or `zig build mutation-test` as described
in `docs/development/fuzzing.md` and `docs/development/mutation-testing.md`.
