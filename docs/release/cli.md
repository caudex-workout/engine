# CLI release artifacts

GitHub Releases are the only binary channel. Supported native smoke-tested
targets are x86_64/aarch64 Linux GNU, x86_64/aarch64 macOS, and x86_64 Windows
GNU. Archives contain the CLI, README, LICENSE, NOTICE, and build metadata;
the CLI statically includes the pinned official SQLite amalgamation on every
target. Initial binaries are not platform-code-signed.

The support claim is limited to this native release smoke-test baseline:

| Target | GitHub-hosted runner | SQLite/runtime baseline |
| --- | --- | --- |
| `x86_64-linux-gnu` | `ubuntu-latest` (x86_64) | GNU libc; bundled official SQLite `3.49.1` |
| `aarch64-linux-gnu` | `ubuntu-24.04-arm` | GNU libc; bundled official SQLite `3.49.1` |
| `x86_64-macos` | `macos-13` (Intel) | bundled official SQLite `3.49.1` |
| `aarch64-macos` | `macos-14` (Apple silicon) | bundled official SQLite `3.49.1` |
| `x86_64-windows-gnu` | `windows-latest` (x86_64) | bundled official SQLite `3.49.1` |

Other operating systems, libc variants, architectures, and runtime versions
are not claimed to be supported by the initial binary release.

The canonical `Caudex release` workflow creates deterministic Unix archives,
checksums, provenance attestations, and the coordinated draft release.
Publishing requires an intentionally pushed signed `vX.Y.Z` tag and review of
every native smoke-test result.

For installation, first-workout, scripting, backup, exit-code, TUI, and
troubleshooting instructions, see the [reference-client user guide](../../apps/caudex-cli/README.md).
