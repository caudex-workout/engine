# `fixtures/` instructions

Fixtures are executable contract data. Keep canonical examples, conformance
cases, and historical compatibility evidence distinct.

- Do not rewrite historical compatibility fixtures to accommodate a new
  implementation. Add a new versioned record and compatibility rationale for
  an intentional contract change.
- Change canonical or conformance fixtures only when the behavior/schema change
  is intentional, classified, and covered by the owning tests and documents.
  Preserve stable IDs, ordering, units, timestamps, seeds, and exact decimal
  representations.
- Keep fixtures small, deterministic, and bounded. Prefer a minimized fuzz seed
  or a referenced generator over duplicating large payloads. Update schemas,
  examples, and cross-language assertions when fixture shape changes.

See `tests/compat/`, `tests/fuzz/corpus/README.md`, and the contract documents
for the distinction between historical evidence and current examples.
