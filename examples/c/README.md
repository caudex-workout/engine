# C conformance example

`conformance.c` is a dependency-free C11 consumer of `caudex.h`. It:

1. Checks the C ABI version.
2. Creates an opaque runtime.
3. Loads a canonical request containing the double-progression methodology.
4. Executes the same request twice.
5. Confirms both results identify the resolved methodology.
6. Extracts and compares both result fingerprints.
7. Prints the stable fingerprint.
8. Frees both result buffers, destroys the runtime, and frees the request.

Run it from the repository root:

```bash
zig build example-c
```

`zig build test` also compiles and runs the example. Debug and test builds use
Zig's debug allocator inside the C runtime, so leaked engine-owned allocations
are reported with allocation diagnostics. The example's cleanup path releases
all resources after both success and failure.
