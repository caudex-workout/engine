# Repository map

- `src/`: deterministic programming core, canonical models, methodologies,
  diagnostics, C/WASM facades.
- `tracking/`, `workflows/`, `portable/`: public tracking, orchestration, and
  persistence-independent protocol modules.
- `adapters/`: optional persistence contracts and SQLite implementation/migrations.
- `apps/caudex-cli/`: first-party reference client and TUI; not core behavior.
- `include/`: public C header; `c_api_test.zig` and `tests/c_header_smoke.c` guard it.
- `packages/npm/`: npm/WebAssembly facade and TypeScript declarations.
- `packages/zig/`: clean distributable Zig package boundaries.
- `schemas/`: versioned JSON schemas; `fixtures/`: canonical examples/conformance data.
- `catalog/`: pinned external catalog and reproducible generator.
- `examples/`: Node/TypeScript, browser, C, and Zig consumer examples.
- `tests/`: cross-language, CLI, docs, package, and adapter integration tests.
- `tools/dev/`: read-only developer diagnostics.
- `tools/repo/`: repository-owned validation and contract tooling.
- `tools/release/`: release validation, staging/package, and artifact verification.
- `docs/adr/`: accepted architectural decisions; `docs/contracts/`: public contracts.

The public API is any intentionally documented Zig module/export, C declaration
or symbol, npm export/declaration, CLI command/option/output/exit code, JSON
schema/fixture format, methodology identifier/version, issue/explanation code,
or released migration. Private implementation files may change without a
contract classification when behavior is unchanged.
