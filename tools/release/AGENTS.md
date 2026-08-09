# `tools/release/` instructions

Release tooling is compatibility- and security-sensitive. Keep validation,
staging, and publication separate: ordinary development and pull-request
commands validate or stage artifacts and must never publish.

- Derive versions and tags from canonical repository metadata and validate
  `build.zig.zon`, npm manifests/lockfiles, changelog, compatibility records,
  and target matrices together. Avoid unnecessary hardcoded release numbers;
  when a release-specific workflow is intentionally pinned, keep its checks
  explicit and synchronized.
- Fail explicitly on missing tools, failed subprocesses, corrupt metadata,
  unsafe archive paths, unexpected archive contents, dirty/ambiguous inputs,
  checksum mismatches, or unsupported targets. Never silently fall back.
- Preserve deterministic staging where supported: sorted archive manifests,
  stable metadata/timestamps, exact artifact inventories, SHA-256 checksums,
  target/linkage metadata, and smoke/link tests. Preserve documented SBOM,
  provenance/attestation, and reproducibility validation rather than treating
  them as optional presentation.
- Keep cross-platform target matrices and package allowlists synchronized with
  the public contract. A staged artifact must be the exact artifact verified
  before publication; release promotion must not rebuild or bypass validation.
- Node.js is the repository release-tooling runtime. Do not rewrite
  functioning release scripts into Zig merely to match core style.

Use `docs/release/validation.md`, `docs/release/versioning.md`, and the release
workflow tests before changing this subtree.
