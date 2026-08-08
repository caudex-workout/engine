# Diagnostics, limits, and performance policy

Caudex’s stable recommendation/evaluation results already contain structured
issues, warnings, explanations, evidence, proposed state, schema metadata, and
deterministic input/result fingerprints. This is the opt-in inspection surface
for v0.1: hosts may serialize or display it, but enabling inspection must not
alter the recommendation. It is structured data, not uncontrolled logging.

Diagnostic fields are versioned with their enclosing contract. Human messages
may improve; issue/explanation codes, severity, structured parameters, and
methodology identifiers follow the compatibility rules in
`docs/contracts/issues-and-explanations.md`.

## Resource and concurrency guarantees

- Core calculations are synchronous, reentrant, and safe to run concurrently
  when each call owns its input/output storage.
- The core does not read clocks, use hidden randomness, access global mutable
  state, persist, or perform network I/O. It has no cancellation API in v0.1.
- Domain decisions use caller-owned bounded storage; serialization and adapter
  layers own their explicit allocations and must release them on all paths.
- Diagnostics and result buffers have explicit bounded capacities; overflow is
  an execution/limit error, never a partial accepted result.
- Practical limits are the documented request/catalog/history bounds in the
  canonical schemas and the `max_*` constants in `src/diagnostics.zig` and
  related modules. Inputs over those limits are rejected with structured issues.
- Zig and C callers own their buffers and runtime lifetime; npm/WASM callers
  own the facade handle and must call `dispose()`; the CLI owns temporary
  adapter resources for one invocation.

## Initial benchmark budgets

The CLI benchmark is a regression guardrail, not a marketing claim. Initial
budgets are intentionally generous and should be recalibrated from CI runner
baselines before becoming required gates:

| Scenario | Initial budget |
| --- | ---: |
| CLI startup/help | 500 ms |
| small recommendation | 50 ms |
| medium recommendation | 250 ms |
| large recommendation | 1 s |
| packed npm artifact | 5 MiB |
| WASM artifact | 2 MiB |

Ordinary noise should be reported, not failed. A future release check may fail
only for a sustained 2x runtime regression, an explicit upper-bound breach, or
an unexpected artifact-size increase. Allocation/peak-memory budgets require a
stable cross-platform measurement harness and are therefore deferred.
