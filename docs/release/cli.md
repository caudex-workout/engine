# CLI v0.1.0 release

GitHub Releases are the only binary channel. Supported native smoke-tested
targets are x86_64/aarch64 Linux GNU, x86_64/aarch64 macOS, and x86_64 Windows
GNU. Archives contain the CLI, README, LICENSE, NOTICE, and build metadata;
Windows also contains the pinned official SQLite DLL. Linux and macOS use the
documented system SQLite runtime. Initial binaries are not platform-code-signed.

The `CLI release` workflow creates deterministic Unix archives where supported,
checksums, provenance attestations, and a draft release. Publishing requires an
annotated SSH-signed `v0.1.0` tag and review of every native smoke-test result.
