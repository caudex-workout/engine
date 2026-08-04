# Changelog

All notable changes to Caudex Workout Engine will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and releases use [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Versioned canonical active-workout tracking protocol with bounded atomic
  batches, standalone snapshots, replay receipts, deterministic fixtures, and
  structured results.
- Pure recommendation/template-to-tracking workflows, immutable prescription
  provenance, completed-workout evaluation conversion, explicit methodology
  state acceptance proposals, and structured modification reporting.
- Minimal versioned workout-template model, canonical JSON schema, optional
  persistence capability, and deterministic template fixture.

### Changed

- C and WebAssembly ABI version 2 uses caller-owned output with exact required
  size reporting; the pre-release v1 `caudex_buffer` disposal API was removed.
- Recommendation and evaluation now use one versioned, explicitly
  discriminated C/WASM execution envelope.
- Canonical tracking snapshots now carry their explicit catalog projection and
  single-command results carry the resulting replay-bearing snapshot.
- Recommendation/template instantiation and tracked-workout completion
  conversion are available through Zig, C, WASM, and npm workflow operations.
- The npm package provides an injected/default clock and secure-ID workflow
  facade with active-workout reload, revision-aware optional persistence,
  idempotent low-level retries, and explicit methodology-state acceptance.

## [0.1.0] - 2026-07-26

### Added

- Initial stateless Zig workout engine, C ABI, and npm/WebAssembly package.
- Direct Zig source package, public module guide, and custom-methodology
  consumer.
- Native C static/shared release matrix with checksums, build metadata, size
  reports, and artifact-first link tests.
- Double-progression and RPE top-set/backoff recommendation support in the
  official npm/WebAssembly runtime.
