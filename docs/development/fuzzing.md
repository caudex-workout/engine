# Bounded fuzzing

Caudex uses repository-owned boundary drivers in `tests/fuzz/`. They exercise
the canonical JSON decoder, exact decimal parser/arithmetic, the public C ABI,
the CLI global-option parser, persisted SQLite JSON decoding, and methodology
configuration decoding. Inputs are capped at 64 KiB; generated CLI arguments
are capped at 32 arguments of 256 bytes each; collection and JSON string
limits are applied before production parsing.

Zig 0.16.0's native fuzz protocol is not usable reliably with this repository's
pinned toolchain on all supported hosts, so the checked-in runner uses a small,
deterministic, seedable bounded input generator with the same driver functions.
This keeps release validation portable and reproducible without a dependency.
The runner is intentionally separate from the fast PR path. If the pinned Zig
toolchain's native `--fuzz` support becomes portable, it can wrap these same
drivers without changing their invariants.

```sh
zig build fuzz-smoke
zig build fuzz-json
zig build fuzz-json -- --iterations=100000 --seed=0x1234
zig build fuzz-json -- --repro=.zig-cache/fuzz/json-0xca0de5f00d-12.input
```

The six explicit targets are `fuzz-json`, `fuzz-decimal`, `fuzz-c-abi`,
`fuzz-cli-args`, `fuzz-sqlite`, and `fuzz-methodology-config`. Normal runs use
10,000 cases and reject values above 100,000. Smoke mode uses a fixed seed and
804 driver invocations. A failed generated case is written under
`.zig-cache/fuzz/` and the command prints its seed, case number, and path;
`--repro` reruns that exact input. Corpus seed examples live under
`tests/fuzz/corpus/` and should remain small and minimized.

The C driver only passes pointers into harness-owned buffers; it never creates
fabricated pointers. The SQLite driver fuzzes Caudex row decoding, not SQLite.
Sanitizer runs can be made with the normal Zig target options where supported,
for example `zig build fuzz-c-abi -Doptimize=Debug`; platform-specific native
sanitizer setup remains a maintainer concern.

To add a target, add a bounded driver to `drivers.zig`, a deterministic smoke
call, a corpus seed if useful, and a build step in `build.zig`. State the
production boundary and invariant in this document. Do not turn the target
into an unbounded collection or allocation generator.
