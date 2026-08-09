# Development setup

## Supported tools

The checked-in source of truth is [`tools/support/versions.json`](../../tools/support/versions.json):

- Zig 0.16.0
- Node.js 22 or newer; CI tests Node 24
- SQLite 3.35 or newer and its development headers/library
- C11-capable compiler and linker

Nix is intentionally not required or provided. A devcontainer is optional;
the standard host toolchain is the supported baseline.

Clone the repository, verify the tools, and install the locked JavaScript test
tools:

```sh
git clone https://github.com/caudex-workout/engine.git
cd engine
./tools/dev/doctor
npm ci --ignore-scripts --no-audit --no-fund --prefix packages/npm/workout-engine
```

The IndexedDB package uses workspace links and is installed separately when
needed by the full suite:

```sh
npm install --ignore-scripts --no-audit --no-fund --prefix packages/persistence-indexeddb
```

Build the library with `zig build`. Build or run the CLI with `zig build
caudex-cli` or `zig build run-caudex-cli`.

The optional devcontainer is described in `.devcontainer/README.md`; its
post-create step is deliberately limited to diagnostics and does not publish,
commit, or rewrite repository files.
