# Native C releases

No native C bundle is currently published. The commands below describe the
staged local artifact and the future release layout; they do not download from
GitHub or publish anything.

The future Caudex release will publish the stable [`caudex.h`](../../include/caudex.h) header with
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

Zig 0.16.0 `ReleaseSmall` produced this v0.1.0 baseline:

| Target | Static | Shared | Import library | Combined |
| --- | ---: | ---: | ---: | ---: |
| `x86_64-linux-gnu` | 433,744 B | 357,800 B | — | 791,544 B |
| `aarch64-linux-gnu` | 430,056 B | 332,272 B | — | 762,328 B |
| `x86_64-macos` | 412,668 B | 317,621 B | — | 730,289 B |
| `aarch64-macos` | 481,140 B | 346,176 B | — | 827,316 B |
| `x86_64-windows-gnu` | 691,084 B | 634,880 B | 3,346 B | 1,329,310 B |
| `aarch64-windows-gnu` | 659,106 B | 566,272 B | 3,346 B | 1,228,724 B |

This is a tracking baseline rather than a release-size budget. The generated
`artifact-sizes.json` remains authoritative for each build.

## Build from source

For local validation, install Zig 0.16.0 from the repository's supported
toolchain and run:

```bash
zig build package-c
```

Bundles are written below `zig-out/c-release/<target>`. To build and execute
only the current host's static and shared C link tests:

```bash
zig build test-c-release
```

The host bundle is the convenient path for an ordinary C developer testing a
local checkout:

```bash
zig build package-c
cc -std=c11 \
  -Izig-out/c-release-host/aarch64-macos/include \
  examples/c/conformance.c \
  zig-out/c-release-host/aarch64-macos/lib/libcaudex.a \
  -o /tmp/caudex-c-conformance
/tmp/caudex-c-conformance
```

Replace `aarch64-macos` with the host target. The static archive is linkable
with the platform C compiler; shared consumers must arrange an rpath or the
platform loader path described below. Until a public release exists, there is
no supported network URL or versioned download to substitute for this local
staging command.

For macOS targets, the builder preserves Zig's embedded `compiler_rt.o` and
rebuilds the static archive with Zig 0.16.0's Darwin archive mode before it
writes checksums or runs the native Apple Clang compatibility check. This keeps
the distributed `libcaudex.a` self-contained and acceptable to `ld64`.

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
