# Native C releases

Caudex publishes the stable [`caudex.h`](../../include/caudex.h) header with
prebuilt `ReleaseSmall` static and shared libraries. Each target bundle also
contains `LICENSE`, `NOTICE`, `build-metadata.json`, and `SHA256SUMS`.

## Target matrix

| Target | Static library | Shared library |
| --- | --- | --- |
| `x86_64-linux-gnu` | `libcaudex.a` | `libcaudex.so` |
| `aarch64-linux-gnu` | `libcaudex.a` | `libcaudex.so` |
| `x86_64-macos` | `libcaudex.a` | `libcaudex.dylib` |
| `aarch64-macos` | `libcaudex.a` | `libcaudex.dylib` |
| `x86_64-windows-gnu` | `caudex.lib` | `caudex.dll` and `caudex.import.lib` |
| `aarch64-windows-gnu` | `caudex.lib` | `caudex.dll` and `caudex.import.lib` |

The GNU Windows ABI is the v0.1 Windows distribution contract. MSVC-flavored
libraries, universal macOS binaries, iOS, Android, and other targets are not
claimed by this release matrix.

## Artifact-size baseline

Zig 0.16.0 `ReleaseSmall` produced this CWE-081 baseline:

| Target | Static | Shared | Import library | Combined |
| --- | ---: | ---: | ---: | ---: |
| `x86_64-linux-gnu` | 397,064 B | 327,360 B | — | 724,424 B |
| `aarch64-linux-gnu` | 390,264 B | 307,096 B | — | 697,360 B |
| `x86_64-macos` | 374,924 B | 293,029 B | — | 667,953 B |
| `aarch64-macos` | 436,172 B | 326,784 B | — | 762,956 B |
| `x86_64-windows-gnu` | 650,308 B | 603,648 B | 3,346 B | 1,257,302 B |
| `aarch64-windows-gnu` | 622,280 B | 541,184 B | 3,346 B | 1,166,810 B |

This is a tracking baseline rather than a release-size budget. The generated
`artifact-sizes.json` remains authoritative for each build.

## Build from source

Install Zig 0.16.0, check out the intended immutable tag, and run:

```bash
zig build package-c
```

Bundles are written below `zig-out/c-release/<target>`. To build and execute
only the current host's static and shared C link tests:

```bash
zig build test-c-release
```

The example executable is [`examples/c/conformance.c`](../../examples/c/conformance.c).
It checks ABI versioning, runtime ownership, deterministic execution, and
result fingerprints using only the installed header and produced library.
Every matrix target is cross-linked in both modes; CI additionally executes
both binaries on native Linux, macOS, and Windows runners.

## Integrity and provenance

Verify a bundle from its root:

```bash
sha256sum --check SHA256SUMS
```

On macOS, use `shasum -a 256 -c SHA256SUMS`.

`build-metadata.json` records the package, engine, and ABI versions; exact Zig
version; optimization mode; target; artifact sizes; and library SHA-256
digests. `artifact-sizes.json` at the matrix root provides the release-wide
size report. Metadata intentionally omits timestamps and machine paths so the
same source and compiler inputs remain reproducible.

Shared-library hosts must arrange normal platform loader discovery: rpath or
`LD_LIBRARY_PATH` on Linux, rpath or `DYLD_LIBRARY_PATH` on macOS, and the DLL
beside the executable or on `PATH` on Windows. Static linking avoids that
runtime loader requirement.
