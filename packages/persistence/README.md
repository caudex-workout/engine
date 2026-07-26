# `@caudex/persistence`

Optional, database-independent persistence capability contracts for Caudex
hosts. This package does not contain a database driver or change workout-engine
semantics.

The authoritative in-repository contract is the Zig module
[`adapters/persistence.zig`](../../adapters/persistence.zig). This TypeScript
package mirrors it for npm hosts.

The required capabilities are independently implementable:

- `CatalogSource` loads a canonical exercise snapshot.
- `HistorySource` loads canonical completed-workout history.
- `MethodologyStateStore` loads and compare-and-sets opaque, versioned
  methodology state.

`RecommendationJournal` and `CompletedWorkoutSink` are separate optional
capabilities. Calculating a recommendation never invokes either capability.
The host must explicitly accept a result before writing it.

Direct snapshot mode remains the fundamental integration:

```ts
const result = caudex.recommendSession(request);
```

No persistence package is required to construct that request or execute the
engine. See the
[custom-repository guide](../../docs/persistence/custom-repositories.md) for
implementation guidance.
