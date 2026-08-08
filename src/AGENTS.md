# `src/` instructions

This subtree contains the deterministic programming core, canonical
representations, methodologies, diagnostics, and the public C/WASM facades.

- Keep recommendation, evaluation, methodology, canonicalization, ordering,
  and load calculations deterministic and effect-free. Do not read a clock,
  use hidden randomness, access global mutable state, perform I/O, parse files,
  touch a database, or call host/platform services from core decisions.
- Bound caller-controlled collections, strings, JSON, diagnostic output, and
  C/WASM buffers at the boundary that owns the contract. Reject before
  expensive work or allocation where practical. Pure decisions must not hide
  allocation; allocator-taking APIs must make ownership and lifetime clear.
- Malformed public input returns the established validation issue or boundary
  error. Assertions are for programmer-only invariants after validation:
  cursor/capacity agreement, canonical ordering, representation round-trips,
  and state-transition postconditions.
- Use exact decimal measurements and explicit units. Use checked arithmetic
  for scaling, conversion, rounding, counts, sizes, and revisions; make
  rounding policy explicit in code and tests. Stable domain and wire values
  use fixed-width integers; `usize` remains appropriate for slices, indices,
  lengths, capacities, and allocator APIs.
- Preserve stable ordering and tie-breaking. Methodology configuration/state
  validation, progression decisions, explanation codes, proposed state, and
  accepted state must remain distinct. Diagnostics and fingerprints are
  observational and must not change a recommendation.
- Keep public Zig representations deliberate. C and WASM boundaries define
  fixed-width values, null/length handling, ownership, insufficient-buffer
  behavior, runtime lifetime, and output limits explicitly. Do not expose
  private representations or duplicate core semantics in a facade.
- Keep validation/domain issues separate from engine/runtime failures. Do not
  turn a safe caller error into an assertion or a resource/serialization
  failure into a domain issue.

For style exceptions and bounds, use
[`docs/development/engineering-style.md`](../docs/development/engineering-style.md)
and [`docs/development/diagnostics-and-limits.md`](../docs/development/diagnostics-and-limits.md).
When changing methodology decision rules, run the relevant core tests and the
manual mutation target when appropriate.
