# `apps/caudex-cli/` instructions

The CLI/TUI is a first-party reference client, not part of the deterministic
engine. Consume only the intended public engine, tracking, persistence, and
SQLite package interfaces. Do not import private core modules, access raw
adapter tables, or couple commands directly to SQL.

- Treat command names, options, line-oriented output, JSON records, exit codes,
  stdout/stderr routing, help text where tested, and completion behavior as
  compatibility surfaces. Machine-readable output must remain stable and
  scriptable; diagnostics belong on the defined stream.
- Bound arguments, paths, batch requests, decoded input, output, and temporary
  resources. Validate paths and database selection safely, handle broken pipes
  and interruption explicitly, and do not leave partial accepted operations.
- Keep human formatting separate from machine contracts. Update CLI shell,
  documentation, and end-to-end tests together when a deliberate contract
  change is made.
- Keep the TUI event loop and model as an explicit state machine. Route actions
  through the model/use-case boundary, keep terminal lifecycle and fake
  terminal behavior testable, and preserve compatibility/accessibility rules
  documented in `TUI-COMPATIBILITY.md`.
- Run the focused CLI/TUI tests, shell smoke scenarios, documentation checks,
  and release-workflow checks relevant to the change; use the canonical root
  checks before handoff.
