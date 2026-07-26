# Map host data to Caudex

Caudex consumes request snapshots; it does not require a canonical database.
Map existing application records at the boundary, call the engine, and decide
explicitly what—if anything—to store afterward.

The checked-in [TypeScript mapping example](../examples/typescript-node/data-mapping.ts)
contains compile-tested versions of the catalog, history, ID, and acceptance
functions used below.

## Keep host IDs stable

Canonical IDs are host-supplied strings. They are correlation values, not
Caudex database keys. Define one deterministic mapping and use it everywhere:

```ts
export function exerciseId(key: number): string {
  return `host-exercise:${key}`;
}
```

The same mapped ID must appear in:

- `catalog[].id`;
- `history.workouts[].exercises[].exerciseId`;
- athlete preferences and restrictions;
- session required or excluded exercise IDs;
- methodology state exercise entries;
- returned recommendations and explanations.

Do not use a mutable display name as an ID. Prefixing IDs can prevent collisions
when a host combines records from several tables or providers. Caudex preserves
IDs but does not interpret their internal format.

## Map an exercise catalog

Only send exercises relevant to the request. Host-only fields do not need to
cross the boundary:

```ts
function mapCatalog(records: HostExercise[]): Exercise[] {
  return records
    .filter((record) => !record.archived)
    .map((record) => ({
      id: exerciseId(record.key),
      name: record.displayName,
      ...(record.equipmentCodes
        ? { equipmentIds: record.equipmentCodes }
        : {}),
    }));
}
```

Map equipment, movements, and muscles to stable host taxonomy codes. Optional
application metadata that materially affects selection may go in the documented
catalog fields or `attributes`; database revisions, ORM objects, authorization
data, and UI state should remain outside the request.

## Map workout history

An existing workout record becomes a `CompletedWorkout`. Exact measurements use
decimal strings and explicit units:

```ts
{
  id: "host-workout:103",
  startedAt: "2026-07-22T13:00:00Z",
  completedAt: "2026-07-22T13:40:00Z",
  exercises: [{
    exerciseId: "host-exercise:42",
    sets: [{
      id: "host-set:1",
      kind: "working",
      actualMetrics: [
        { code: "load", value: { amount: "65", unit: "lb" } },
        { code: "repetitions", value: { amount: "12", unit: "count" } },
      ],
      status: "completed",
    }],
  }],
}
```

Preserve the real completion status rather than dropping incomplete sets.
Double progression uses working-set load, repetitions, and status. RPE
top-set/backoff expects `kind: "top"` plus load, repetitions, and exactly one
`rpe` or `rir` metric when that record should provide exertion evidence.

The host chooses the relevant history window and supplies explicit RFC 3339
timestamps. Caudex does not query older records or fill in the current time.

## Handle optional and missing fields

Required recommendation fields are `schemaVersion`, `asOf`, `methodology`, and
a non-empty `catalog`. Other fields are optional only when their absence
faithfully represents the host data and the selected methodology can operate
without them.

Use these mapping rules:

- Omit an optional field when its value is unknown.
- Use an empty array only when the host knows the collection is empty.
- Do not substitute `"0"` for an unknown load, repetition count, RPE, or RIR.
- Do not send `null` for optional canonical fields; v0 optional fields are
  omitted rather than nullable.
- Preserve exact decimal text and the source unit. The engine rejects
  incompatible units instead of converting implicitly.
- Put custom JSON only in explicitly open fields such as `attributes`;
  unknown canonical object fields are rejected.

Missing evidence may produce `history.insufficient_evidence`, another structured
issue, or initial-state behavior depending on the methodology. That is safer
than inventing authoritative training data during mapping.

## Load and persist methodology state

Methodology state is a versioned opaque value at the storage boundary. A host
record can wrap it with application concurrency metadata:

```ts
interface StoredMethodologyState {
  methodologyId: string;
  methodologyVersion: string;
  state: MethodologyState;
  revision: number;
}
```

Load the record before building the request and pass only `record.state` as
`methodologyState`. Keep the methodology ID and version beside it so the host
does not attach state to the wrong methodology.

Treat `result.nextMethodologyState` as a proposal. On explicit acceptance,
compare-and-set it using the revision read with the request:

```ts
if (
  decision.kind === "accept" &&
  result.ok &&
  result.nextMethodologyState
) {
  await stateStore.compareAndSet(scope, current?.revision ?? 0, {
    methodologyId: result.metadata.methodology.id,
    methodologyVersion: result.metadata.methodology.version,
    state: result.nextMethodologyState,
    revision: (current?.revision ?? 0) + 1,
  });
}
```

A compare-and-set conflict belongs to the host or adapter. Rebuild, discard, or
reconcile the proposal according to application policy; do not convert a
persistence conflict into a core validation issue.

## Accept or reject a recommendation

`result.ok` means the engine completed the calculation successfully. It does
not mean the user or host accepted the proposal.

An accept flow may store the proposed methodology state, a copy of the
recommendation, and any host acceptance metadata in one host transaction. A
reject flow stores none of those changes unless the application independently
wants an audit record. Preview, comparison, and simulation flows can discard
the result entirely.

The engine never:

- changes the supplied history or state;
- marks a recommendation accepted;
- writes a workout or acceptance event;
- begins a transaction;
- resolves a storage revision conflict.

This boundary keeps calculation semantics identical for applications using
SQLite, PostgreSQL, IndexedDB, remote APIs, custom repositories, or no
persistence at all.

