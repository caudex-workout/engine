# Caudex WebAssembly runtime v1

> Superseded by [WebAssembly runtime v2](wasm-v2.md). v1 is retained as
> migration history and is no longer implemented.

CWE-060 produces `zig-out/bin/caudex.wasm` as a `wasm32-freestanding`
`ReleaseSmall` artifact. It uses the same canonical JSON execution adapter and
status codes as the C ABI.

## Environment

The module exports its own linear memory and has no imported functions,
filesystem access, WASI dependency, clock, network, or environment access.
Node is used only by the repository conformance harness; the artifact itself is
host-neutral WebAssembly.

## Exports

The v1 module exports:

- `memory`
- `caudex_abi_version`
- `caudex_runtime_execute`
- `caudex_wasm_runtime_evaluate`
- `caudex_buffer_free`
- `caudex_wasm_alloc`
- `caudex_wasm_free`
- `caudex_wasm_runtime_create`
- `caudex_wasm_runtime_destroy`

These are an internal wrapper boundary for the TypeScript loader. They are not
the intended JavaScript user API, and raw pointers must not escape the facade
implemented by CWE-061.

`caudex_runtime_execute` accepts canonical recommendation requests.
`caudex_wasm_runtime_evaluate` accepts canonical evaluation requests. Both use
the same request, result-descriptor, status, and ownership conventions.

## Ownership

The host copies canonical request bytes into memory returned by
`caudex_wasm_alloc` and releases them with `caudex_wasm_free`. Result
descriptors have the wasm32 layout `{ data: u32, len: u32, capacity: u32 }`.
Successful result data is engine-owned and must be released with
`caudex_buffer_free`; that operation zeroes the descriptor. Runtime-owned
buffers must be freed before runtime destruction.

The conformance harness executes the same recommendation fixture twice,
compares its result fingerprint with the direct Zig/C value, frees both result
buffers, verifies descriptor clearing, and releases request, descriptor, and
runtime allocations.

## Boundary failures

Malformed canonical JSON, null runtime handles, unsupported versions, output
limits, and allocation failures return numeric statuses where the adapter can
validate them. WebAssembly itself cannot safely validate an arbitrary nonzero
linear-memory address before the host dereferences it; the TypeScript loader
must expose no raw pointer inputs and must use only addresses returned by the
module.

## Size baseline

With Zig 0.16.0 on 2026-07-26:

```text
mode: ReleaseSmall
target: wasm32-freestanding
artifact: caudex.wasm
size: 252,190 bytes
imports: 0
```

This is a tracking baseline, not yet a release-size budget. Changes should
record and explain material growth rather than optimizing away validation,
determinism, or safe ownership.

The increase from the original 201,481-byte baseline adds canonical evaluation
translation, deterministic evaluation result construction, and proposed-state
encoding to the npm/WebAssembly boundary.
