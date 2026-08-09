# Caudex agent instructions

## Product and boundaries

Caudex is an embeddable workout programming and active-workout tracking engine
for developers. It is a stateless library with Zig, C, WebAssembly/npm, and
first-party reference-client surfaces. Hosts supply complete snapshots and
commands; Caudex returns deterministic recommendations, evaluations, tracking
transitions, explanations, diagnostics, and proposed state.

The engine does not own accounts, UI, synchronization, a hosted service,
medical coaching, or required persistence. Hosts decide whether proposals are
accepted and stored. The CLI/TUI and persistence adapters are optional outer
layers, not engine behavior.

## Architecture

Keep dependencies directed inward:

```text
host/reference client -> public facades and adapters -> tracking/workflows -> deterministic core
```

Use the actual module boundary being changed. `src/` contains the programming
core, canonical models, methodologies, diagnostics, and C/WASM facades;
`tracking/`, `workflows/`, and `portable/` contain persistence-independent
public protocols; `adapters/` contains optional persistence contracts and
SQLite; `apps/caudex-cli/` is a reference client; `packages/` contains
publishable ecosystem packages; `schemas/` and `fixtures/` are public contract
data; `tools/` and `.github/` validate, test, package, and release the system.

Outer layers may depend on inner layers. Core and protocol semantics must not
depend on databases, adapters, CLI/TUI code, host frameworks, filesystems,
network services, wall-clock reads, or hidden randomness.

## Engineering policy

[`docs/development/engineering-style.md`](docs/development/engineering-style.md)
is the detailed style standard. Its priorities are correctness/safety,
determinism/compatibility, developer experience, predictable performance, and
then terseness. Apply bounded work, checked arithmetic, explicit ownership,
simple control flow, explicit invariants, and no speculative abstraction.

Use the language and ecosystem idioms of the edited surface: `snake_case` and
explicit fixed-width domain values in Zig, idiomatic TypeScript/JavaScript in
npm packages, and restrained, justified, pinned dependencies. Do not weaken a
public contract or rewrite functioning Node.js tooling for style reasons.

## Public contracts

Treat documented Zig exports, C declarations/symbols, WASM behavior, npm
exports/declarations and artifact contents, schemas, fixtures, methodology
IDs/versions, issue and explanation codes, CLI commands/output/exit codes,
tracking/protocol versions, and released migrations as compatibility surfaces.
Classify intentional changes and update the relevant snapshots, schemas,
fixtures, tests, documentation, changelog, and migration/release metadata.
Never silently reinterpret existing fields, expected results, or released
migrations. Keep validation/domain issues distinct from runtime, adapter,
ABI, npm, and CLI failures.

## Dependencies and changes

Prefer Zig/std and existing repository tooling; then existing pinned
dependencies; add a production dependency only with a clear capability,
security/lifecycle/license, and maintenance rationale. Inspect surrounding
architecture and current tests before editing, preserve behavior unless the
change is intentional, and update tests/docs with behavior changes. Do not
modify unrelated files, hide failures by weakening tests or snapshots, or
commit, push, rewrite history, or publish unless explicitly requested.

## Canonical validation

Use the strongest applicable current build step:

- `zig build check-fast` for the short local loop;
- `zig build check` for the canonical pull-request/pre-merge suite;
- `zig build check-release` for release metadata, compatibility, artifact
  workflow, bounded fuzz smoke, and mutation smoke in addition to `check`.

Focused leaf steps are useful when developing in a subsystem. Full bounded
fuzz sessions and the curated mutation suite are manual targets; follow the
guides under `docs/development/` and preserve seeds/reproducer artifacts.
Report exact commands and failures honestly. `build.zig` is the source of
truth for the build graph; do not invent or duplicate a stale command list.

## Instruction hierarchy

Read this file and the closest applicable nested `AGENTS.md` before editing.
Child files add only rules specific to their subtree. A child rule may narrow
these instructions but must not contradict the current source, tests, accepted
architecture documents, or the engineering-style standard. The closest file
wins when a rule is genuinely more specific.

Accepted architectural decisions are in `docs/adr/`; public contracts are in
`docs/contracts/`; repository setup/testing/release guidance is under `docs/`.
When those sources conflict with historical notes, report the conflict and
follow the current code, tests, and accepted decisions.
