# Caudex C ABI v2

C ABI v2 replaces v1's caller-visible allocation metadata with caller-owned
output.

## Lifetime and synchronization

`caudex_runtime_create` creates an independent opaque runtime and
`caudex_runtime_destroy` destroys it. A runtime must outlive calls made with it.
Runtimes share no mutable state, but one runtime is not internally synchronized;
hosts must externally serialize calls using the same runtime. Different
runtimes may be used concurrently.

There is no result-disposal API. The host owns output memory before, during, and
after execution, so runtime destruction cannot invalidate a result. Destroying
the same runtime twice or using it after destruction is invalid host behavior.

## Execution and ownership

```c
caudex_status caudex_runtime_execute(
    caudex_runtime *runtime,
    const uint8_t *request_data,
    size_t request_len,
    uint8_t *output_data,
    size_t output_capacity,
    size_t *out_required);
```

Call with null output and zero capacity. A valid request returns
`CAUDEX_STATUS_INSUFFICIENT_OUTPUT` and the exact required byte count. Allocate
that many bytes and call again. Exact capacity succeeds. Insufficient capacity
reports the size and writes no partial output.

`out_required` and `runtime` must be non-null. A null request is allowed only
with zero length; a null output is allowed only with zero capacity. Buffers are
length-delimited and need no NUL terminator. Malformed UTF-8/JSON returns
`CAUDEX_STATUS_INVALID_REQUEST`. Output is bounded to 1 MiB.

## Migration from v1

- Change ABI checks from 1 to 2.
- Remove `caudex_buffer` and `caudex_buffer_free` usage.
- Query size, allocate host-owned bytes, execute again, then use the host
  allocator to release the result.
- Results no longer depend on runtime lifetime.

