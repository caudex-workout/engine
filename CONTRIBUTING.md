# Contributing to Caudex

Caudex is a deterministic, explainable library. The core owns calculation;
hosts own persistence, lifecycle, and acceptance of proposals. Read
`AGENTS.md` and the accepted ADRs before making architectural or public-contract
changes.

## Start here

1. Install Zig 0.16.0, Node.js 22+, Python 3.9+, SQLite 3.35+, and a C11
   compiler/linker. CI uses Node 24.
2. Run `./tools/dev/doctor` (use `--strict` to require the CI Node major).
3. Run `zig build check-fast` for the short loop.
4. Run `zig build check` before opening a pull request.

The full setup, test matrix, and repository map are in
[`docs/development/setup.md`](docs/development/setup.md),
[`docs/development/testing.md`](docs/development/testing.md), and
[`docs/development/repository-map.md`](docs/development/repository-map.md).

## Change boundaries

Public Zig modules, `include/caudex.h`, npm exports and declarations, schemas,
fixtures, CLI commands/output, explanation and issue codes, methodology IDs and
versions, and released SQLite migrations are public contracts. Check the
compatibility documentation and run `zig build check-release` when changing
one. Never edit a released migration in place.

Adding a methodology requires documented configuration/state/progression and
failure rules, deterministic tie-breaks, validation and explanation codes, and
representative fixtures/tests. Adding an adapter must keep persistence and
transaction errors outside the core domain.

An ADR is required for a new architectural boundary, dependency direction,
public contract policy, persistence behavior, or other decision that would be
hard to reverse. Ordinary implementation changes do not need an ADR.

## Pull requests

Keep changes focused. Describe affected public contracts, compatibility
classification, tests, documentation, generated files, migrations/schemas,
and release-note impact. The pull-request template is a checklist, not a
substitute for explaining the design. CI is authoritative; optional local hooks
must never rewrite unrelated files or replace the canonical checks.

## Common failures

- Wrong Zig version: install/select 0.16.0 and rerun `./tools/dev/doctor`.
- Missing npm tools: run `npm ci --ignore-scripts --no-audit --no-fund` in
  `packages/npm/workout-engine`; the IndexedDB package has its own documented
  install step.
- SQLite link failure: install the platform development library and verify
  `sqlite3` plus a C compiler are on `PATH`.
- Generated catalog drift: run the documented catalog generator update flow;
  do not hand-edit `catalog/generated`.
- CI-only platform failure: reproduce the canonical command on the matching
  host and include the target triple and tool versions in the issue or PR.
