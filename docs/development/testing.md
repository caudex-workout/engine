# Testing and checks

The build graph is the source of truth. Do not duplicate its subsystem list in
scripts or workflows.

| Command | Purpose |
| --- | --- |
| `zig build check-fast` | Formatting, Git hygiene, repository metadata/schema checks, and core tests. |
| `zig build check` | Canonical pull-request/pre-merge suite, including adapters, methodologies, schemas/fixtures, C/WASM/npm consumers, CLI, catalog, and executable docs. |
| `zig build check-release` | Canonical suite plus release metadata and release-workflow validation. Cross-target packaging and publication remain release-only. |
| `zig build clean` | Remove `.zig-cache` and `zig-out`. |
| `zig build clean-all` | Also remove generated package `dist/` directories. |
| `./tools/dev/doctor --strict` | Require the declared CI tool versions where applicable. |

Run focused leaf steps while developing (`test-core`, `test-workflows`,
`test-persistence-sqlite`, `test-c-api`, `test-typescript`, `test-npm-clean`,
`test-zig-package`, or `test-caudex-cli`). New guardrails belong in `build.zig`
and should have a failing test or fixture where practical.

The test suite covers direct Zig use, the clean Zig consumer, C header and
linkage smoke tests, WASM and TypeScript loaders, npm examples, browser-facing
fixtures, SQLite adapters, CLI output/exit codes, and documentation
quickstarts. The release check also validates the v0.1.0 metadata contract.
