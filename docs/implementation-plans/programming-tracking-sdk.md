# Programming and Active-Workout Tracking SDK Implementation Plan

- **Status:** Active
- **Date:** 2026-08-04
- **Baseline commit:** `7d8c237a37b14c33a2405d503e194564c61115be`
- **Branch inspected:** `main`
- **Architecture:** [ADR-0006](../adr/ADR-0006-programming-and-active-tracking-sdk.md)

## Baseline

The repository already has typed pure tracking contract version 6, lifecycle
tests, SQLite migrations 001–007, persistence contracts and a contract kit, an
IndexedDB npm adapter, CLI/TUI tracking, canonical recommendation/evaluation
JSON, C ABI v1, WASM entry points, and npm programming APIs. Extend these; do
not reimplement them.

Missing are canonical cross-language tracking, a workflow bridge with full
provenance, templates, tracking through C/WASM/npm, reusable orchestration,
structured discovery, the pinned exercise catalog, portable import/export, and
final publishable package separation.

## Compatibility decisions before implementation

- Replace C ABI v1's forgeable `data/len/capacity` result and increment ABI to 2.
- Give tracking, workflow, template, discovery, and portable schemas independent
  versions and explicit operation discriminators.
- Add provenance/prescription data without overwriting execution values; use
  forward-only persistence migrations.
- Use `@caudex-workout/engine` for the umbrella SDK. Decide the persistence,
  IndexedDB, and catalog names together and update their consumers atomically;
  promise no unpublished aliases.
- Separate Zig packages so core excludes CLI/TUI, Vaxis, SQLite, and app assets.

Every breaking phase must add changelog migration guidance and must not silently
reinterpret old canonical data.

## Phases and acceptance criteria

### 1. Architecture and release gating

- ADR-0006, baseline SHA, compatibility decisions, and corrected product text
  are present.
- Pull requests retain host-native C link coverage; the full C matrix runs only
  for version tags/manual dispatch; no workflow has `schedule`.

### 2. Canonical tracking

**Status:** Completed at `HEAD` after baseline commits

- Bounded versioned schemas and Zig boundary types cover snapshots, all public
  commands, atomic batches, replay, revisions, issues, and warnings.
- Malformed transport differs from domain rejection; independent enums have
  exhaustive conversions; deterministic direct-Zig fixtures pass.

Implemented as the `caudex_tracking_protocol` boundary over the allocation-free
typed reducer. It includes bounded atomic batches, replay-bearing snapshots,
bidirectional exact-decimal conversions, accepted/rejected result conversion,
standalone versioned snapshot documents, JSON Schemas, and deterministic
fixtures. C/WASM/npm exposure remains in their later phases.

### 3. Workflow bridge and provenance

**Status:** Completed for the pure Zig workflow bridge

- Pure recommendation/template instantiation and completion conversion preserve
  original prescriptions and validate catalog, units, ordering, IDs, completion,
  provenance, and capacity with structured issues.
- Manual, template, and recommendation origins round-trip deterministically.

Implemented with explicit host IDs/timestamps, immutable prescriptions,
structured modification derivation, completion validation/conversion, and
explicit methodology-state compare-and-set proposals. Cross-language execution
is scheduled in Phases 5–6.

### 4. Minimal templates

**Status:** Completed for the pure model, canonical document, and persistence contract

- A bounded versioned model supports identity, description, ordered exercises,
  optional set kinds/targets, notes/tags, and revision; canonical serialization,
  pure instantiation, and adapter contracts pass without scheduling features.

First-party SQLite and IndexedDB storage remains part of Phase 8 rather than
introducing persistence into this pure phase.

### 5. C ABI v2 and WASM

**Status:** In progress; safe caller-owned output is implemented

- One registry-backed executor covers programming, tracking, workflows,
  discovery, and portable data with safe output ownership.
- Lifetime, synchronization, pointers, capacity, UTF-8, versions, disposal, and
  independent runtimes are tested; C/WASM/Zig fixtures agree.

ABI v2 removed caller-mutable allocator metadata and result disposal. Native C,
WASM, and npm now use required-size discovery plus exact caller-owned output.
Recommendation and evaluation share one versioned operation dispatcher;
tracking, workflow, discovery, and portable-data operations remain to complete
this phase.

### 6. npm APIs

- Deterministic APIs require explicit snapshots, IDs, revisions, and timestamps.
- Convenience APIs inject/default secure IDs and clocks, support reload/retry,
  expose conflicts, and never accept methodology state implicitly.
- Node, browser, declaration, docs, and clean-consumer tests pass without an
  unexplained runtime dependency.

### 7. Optional orchestration

- Narrow capabilities compose catalog/history/state/recommendation/tracking and
  recovery outside the core, with honest atomicity and explicit idempotency keys.

### 8. Persistence expansion

- Contracts and contract kit cover replay, templates, provenance, acceptance,
  completion, state, recovery, and portable data.
- SQLite migration/transaction/rollback/reopen tests and IndexedDB connection,
  upgrade, abort, conflict, delete, reopen, scope, and round-trip tests pass.

### 9. Methodology discovery

- Zig/C/WASM/npm expose list, describe, config/state validation, and capabilities
  with UI-neutral field metadata and cross-representation conformance.

### 10. Optional exercise catalog

- A manifest pins free-exercise-db commit/license/schema/tool/fingerprint.
- Checked-in text is deterministic and requires no fetch; images and unverified
  URLs are excluded; mapping, projection, overrides, notices, drift, and clean
  Zig/npm consumer tests pass.

### 11. Portable import/export

- A bounded adapter-independent format supports validation, dry-run, merge and
  replace, structured conflicts, excludes secrets, and round-trips semantically
  between SQLite and IndexedDB.

### 12. Package boundaries and names

- Clean-copy Zig packages separate core, SQLite, catalog, and CLI/TUI.
- npm names, dependencies, release metadata, docs, and examples change atomically.

### 13. CI, docs, and verification

- Linux PR CI covers architecture/core/tracking/workflow/persistence/SQLite/
  IndexedDB/npm/WASM/catalog/docs/packages/native C; macOS/Windows cover focused
  native compatibility.
- Packaged Zig/C/Node/browser examples show the full workflow.
- Conformance, model-based, fuzz/mutation, failure-injection, and property tests
  cover every new boundary, and all existing required commands pass.

## Sequencing

Phases are independently reviewable and follow dependency order. No phase
invents unresolved public schemas as incidental scaffolding. This change starts
Phase 1; later phases remain incomplete until their criteria and focused tests
land.
