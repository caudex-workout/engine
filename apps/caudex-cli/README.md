# Caudex CLI

`caudex` is the reference command-line client for Caudex Workout Engine. This
initial scaffold provides only command discovery and version reporting:

```text
caudex --help
caudex version
```

Build and run it from the repository root:

```sh
zig build caudex-cli
zig build run-caudex-cli -- --help
zig build test-caudex-cli
```

The client receives only the public `caudex`, `caudex_persistence`, and
`caudex_sqlite` packages from the root build graph. It must not import private
engine, adapter, or migration source paths. Workout and database commands are
introduced by later implementation issues.
