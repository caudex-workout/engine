# `packages/npm/workout-engine/` instructions

This package is the TypeScript/WebAssembly facade for the Zig engine. Core
recommendation, evaluation, methodology, tracking, canonical, and validation
semantics live in Zig; TypeScript validates the crossing, manages the WASM
runtime, and provides an ergonomic host API.

- Keep public TypeScript and JavaScript idiomatic (`camelCase`, discriminated
  unions, clear object shapes). Do not copy Zig naming or reimplement domain
  decisions in the facade.
- Separate initialization failures, request/runtime failures, and disposal or
  buffer errors. Define handle lifetime, `dispose()`, safe-integer conversion,
  request/output bounds, and browser/Node behavior explicitly.
- Keep package exports and declarations controlled. Update `package.json`,
  generated/checked declarations, schema exports, compatibility snapshots, and
  consumer tests together. Do not expose implementation files accidentally.
- Keep the WASM artifact and package contents within the tested allowlist and
  preserve the artifact build path. Do not add runtime dependencies without a
  strong, documented justification.
- Test the packed artifact in clean Node/browser-style consumers, not only the
  repository source tree. Run the package, TypeScript, WASM conformance, clean
  smoke, example, and documentation quickstart checks relevant to the change.

Use the package README, `docs/contracts/wasm-v*.md`, and `build.zig` package
steps as the current distribution contract.
