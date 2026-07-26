# v0.1.0 security review

Reviewed 2026-07-26 against the release threat model.

- Core calculations perform no filesystem, environment, network, clock, or
  hidden-randomness access.
- npm has no runtime dependencies or install scripts; development dependencies
  are locked and excluded from the artifact.
- Canonical JSON enforces byte, nesting, collection, string, and output limits.
- Domain arithmetic uses checked exact-decimal operations.
- C and WASM expose bounded length-delimited buffers with explicit ownership;
  malformed requests return status/result values rather than crossing the ABI.
- Native artifacts include SHA-256 manifests; npm publication uses provenance.
- Methodologies are compiled in. No dynamic native plugins or untrusted code
  loading are supported.
- Full tests cover malformed protocols, deterministic replay, ownership, clean
  consumers, and cross-language fixtures.

No known high-severity security defect remains. Recommendations are programming
suggestions, not medical assessments.
