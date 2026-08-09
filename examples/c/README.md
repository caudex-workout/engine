# C conformance example

This is a repository validation example and documents the public v0.1.0 C
bundle. The consumer bundle contains `caudex.h`, a static or shared library,
checksums, and build metadata.

`conformance.c` is a dependency-free C11 consumer of `caudex.h`. It:

1. Checks the C ABI version.
2. Creates an opaque runtime.
3. Loads a canonical request containing the double-progression methodology.
4. Executes the same request twice.
5. Confirms both results identify the resolved methodology.
6. Extracts and compares both result fingerprints.
7. Prints the stable fingerprint.
8. Frees both caller-owned result buffers, destroys the runtime, and frees the
   request.

Run it from the repository root:

```bash
zig build example-c
```

To exercise the same consumer path from a local staged bundle, build the host
artifacts and compile with an ordinary C compiler:

```bash
zig build package-c
cc -std=c11 \
  -Izig-out/c-release-host/aarch64-macos/include \
  examples/c/conformance.c \
  zig-out/c-release-host/aarch64-macos/lib/libcaudex.a \
  -o /tmp/caudex-c-conformance
/tmp/caudex-c-conformance
```

The static archive includes the compiler runtime needed by the public C
interface. For a shared build, link `libcaudex.dylib` with an rpath such as
`-Wl,-rpath,@loader_path/caudex/lib`; Linux uses the corresponding `.so` and
`LD_LIBRARY_PATH`/rpath convention. The target directory must match the host
platform and architecture.

`zig build test` also compiles and runs the example. Debug and test builds use
Zig's debug allocator inside the C runtime, so leaked engine-owned allocations
are reported with allocation diagnostics. The example's cleanup path releases
all resources after both success and failure.
