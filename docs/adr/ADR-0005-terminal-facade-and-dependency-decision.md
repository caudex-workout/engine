# ADR-0005: Terminal Facade and Dependency Decision

- Status: Accepted
- Date: 2026-08-01

## Decision

The first Caudex TUI will use **libvaxis**, pinned to a reviewed source revision,
behind a small application-owned terminal facade. The facade lives under
`apps/caudex-cli`; it will be the only code allowed to own raw mode,
alternate-screen control, resize/signal handling, input bytes, terminal writes,
and libvaxis types. Engine, persistence, tracking, and public adapter APIs
remain terminal-free.

## Review

| Candidate | Maintenance/pinning | Platforms/license | Unicode, resize, signals | Testability/size |
| --- | --- | --- | --- | --- |
| Direct Zig + platform calls | Maintained with this repository; no external pin | Required release targets; project license | Small, explicit subset; width policy stays app-owned | Fake facade is deterministic; smallest binary cost |
| Zig standard library alone | Zig 0.16.0 pin | Same supported targets; MIT | Useful I/O support but no complete TUI lifecycle/widget layer | Testable I/O, but still needs facade and platform glue |
| vaxis | External revision/API pin and maintenance review required | Broad terminal support; MIT | Strong terminal and Unicode features | Larger dependency surface; must be isolated |
| notcurses/curses bindings | Native-library/version pin and system packaging burden | Platform-specific native deployment; permissive licenses vary by binding | Mature terminal handling | Harder clean-runner and fake-terminal testing |

libvaxis is selected for its terminal capability handling, Unicode support, and
testable rendering model. The direct facade remains necessary to prevent its
types and lifecycle concerns from leaking into client use cases or public APIs.
libvaxis must be revision-pinned and license-reviewed when it is added to the
build graph; its integration must remain confined to the facade and be covered
by fake-terminal tests.

## Consequences

The initial TUI supports the verified release platforms and ordinary ANSI/VT
terminals through libvaxis. Unicode-width, resize, signal, and alternate-screen
behavior require dedicated fake-terminal fixtures in CWE-161 and CWE-162.
