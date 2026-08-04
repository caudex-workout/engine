# Caudex C ABI v1

> Superseded by [C ABI v2](c-abi-v2.md). v1 is retained as migration history
> and is no longer implemented.

The public header is `include/caudex.h`. The ABI is a thin native adapter over
the canonical JSON protocol and typed engine; it does not expose Zig structs,
slices, allocators, or error unions.

## Version and runtime

`caudex_abi_version()` returns `CAUDEX_ABI_VERSION`, currently `1`.

`caudex_runtime_create()` writes an opaque runtime pointer supplied by the
engine. A successful runtime must eventually be passed to
`caudex_runtime_destroy()`. Destroy accepts null.

Runtime handles and their result buffers are not thread-safe. A host may create
one runtime per thread or externally serialize access.

## Request execution

`caudex_runtime_execute()` accepts a length-delimited canonical recommendation
request. The bytes do not need a trailing null. A null data pointer is valid
only when the length is zero.

On success, `out_result` contains compact canonical result JSON:

- `data` points to engine-owned bytes.
- `len` is the number of result bytes and excludes any terminator.
- `capacity` records the allocation that the engine must release.

The caller initializes the entire output buffer to zero before execution.
Reusing a nonempty buffer is rejected, preventing accidental loss of an owned
allocation.

Every successful result buffer must be passed once to `caudex_buffer_free()`
with the runtime that created it. Free resets all buffer fields to zero. Hosts
must free outstanding buffers before destroying their runtime.

## Status codes

All exported operations return stable `caudex_status` values or `void`. No Zig
panic payload, error union, allocator, or stack-owned slice crosses the ABI.

- `CAUDEX_STATUS_OK`: execution completed and returned a result.
- `CAUDEX_STATUS_INVALID_ARGUMENT`: pointer or buffer-state contract violation.
- `CAUDEX_STATUS_OUT_OF_MEMORY`: runtime or result allocation failed.
- `CAUDEX_STATUS_INVALID_REQUEST`: malformed, invalid, or over-limit canonical
  input.
- `CAUDEX_STATUS_UNSUPPORTED_VERSION`: ABI-adjacent protocol or methodology
  version is unsupported.
- `CAUDEX_STATUS_UNSUPPORTED_METHODOLOGY`: the compiled runtime does not contain
  the requested methodology.
- `CAUDEX_STATUS_OUTPUT_LIMIT_REACHED`: the bounded result buffer was
  insufficient.
- `CAUDEX_STATUS_INTERNAL_ERROR`: reserved for an execution failure that cannot
  be represented by another status.

Expected domain or methodology rejections should be canonical result values
when the typed engine can safely complete the calculation. Status codes report
failures to execute the request safely.

## v1 scope

The v1 runtime executes canonical recommendation requests for double
progression and RPE top-set/backoff. Canonical evaluation dispatch remains an
internal npm/WASM operation and can be added to the public C surface only with
an explicitly versioned ABI decision.
