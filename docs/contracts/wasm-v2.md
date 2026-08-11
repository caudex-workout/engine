# Caudex WebAssembly runtime v2

WebAssembly uses C ABI v2 semantics in linear memory. The single
`caudex_runtime_execute` function receives request pointer/length, output
pointer/capacity, and a pointer to a
32-bit required-size value. Callers make a sizing call followed by an
exact-capacity call.

It consumes the same versioned execution envelope and operation discriminators
as the native C boundary. There is no separate evaluation export.
This includes program-definition validation, instantiation, planned-session
resolution, and proposal-only advancement operations.

Request and result bytes are allocated with `caudex_wasm_alloc` and released
with `caudex_wasm_free`. There is no runtime-owned result or disposal export.
The npm facade handles this ownership automatically. A single allocation is
bounded to 4 MiB plus 1 KiB, matching the largest portable payload and its
execution envelope. Zero-length or larger requests return zero without
allocating.

One runtime requires external serialization. Independent runtimes share no
mutable state. Runtime destruction does not invalidate caller-owned results.
