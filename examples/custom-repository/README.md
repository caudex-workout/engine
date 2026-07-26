# Custom repository example

This example adapts a deliberately non-reference, legacy-shaped repository to
Caudex's narrow TypeScript persistence capabilities. Its table-like records use
numeric primary keys, snake_case fields, comma-separated equipment, and separate
workout/set collections; none matches the canonical Caudex model.

Run the repository smoke test from the project root:

```bash
zig build test-custom-repository
```

[`index.ts`](index.ts) demonstrates:

- mapping existing exercise and workout records into a canonical request
  snapshot;
- sorting mapped history deterministically;
- loading and compare-and-setting only opaque methodology state;
- keeping calculation in direct snapshot mode; and
- leaving the host's exercise and workout records in place.

The example intentionally does not implement `RecommendationJournal` or
`CompletedWorkoutSink`. A recommendation calculation performs no writes, and
the single demonstrated write occurs only after the host's explicit acceptance
boundary.
