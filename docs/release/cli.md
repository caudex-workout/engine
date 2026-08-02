# CLI v0.1.0 release

GitHub Releases are the only binary channel. Supported native smoke-tested
targets are x86_64/aarch64 Linux GNU, x86_64/aarch64 macOS, and x86_64 Windows
GNU. Archives contain the CLI, README, LICENSE, NOTICE, and build metadata;
Windows also contains the pinned official SQLite DLL. Linux and macOS use the
documented system SQLite runtime. Initial binaries are not platform-code-signed.

The support claim is limited to this native release smoke-test baseline:

| Target | GitHub-hosted runner | SQLite/runtime baseline |
| --- | --- | --- |
| `x86_64-linux-gnu` | `ubuntu-latest` (x86_64) | GNU libc and the runner's dynamically linked system SQLite |
| `aarch64-linux-gnu` | `ubuntu-24.04-arm` | GNU libc and the runner's dynamically linked system SQLite |
| `x86_64-macos` | `macos-13` (Intel) | macOS system SQLite |
| `aarch64-macos` | `macos-14` (Apple silicon) | macOS system SQLite |
| `x86_64-windows-gnu` | `windows-latest` (x86_64) | bundled official SQLite `3.49.1` `sqlite3.dll` |

Other operating systems, libc variants, architectures, and runtime versions
are not claimed to be supported by the initial binary release.

The `CLI release` workflow creates deterministic Unix archives where supported,
checksums, provenance attestations, and a draft release. Publishing requires an
annotated SSH-signed `v0.1.0` tag and review of every native smoke-test result.

For installation, first-workout, scripting, backup, exit-code, TUI, and
troubleshooting instructions, see the [reference-client user guide](../../apps/caudex-cli/README.md).
