# Release validation and staging

Release policy is recorded in
[`tools/release/release-metadata.json`](../../tools/release/release-metadata.json).
The tag-driven validator and asset manifest are
[`tools/release/validate-release.mjs`](../../tools/release/validate-release.mjs)
and [`tools/release/artifact-manifest.mjs`](../../tools/release/artifact-manifest.mjs).

Run the non-publishing phases locally:

```sh
zig build check-release
zig build release-check
node tools/release/validate-release.mjs vX.Y.Z
node tools/repo/compatibility-check.mjs
```

The release workflow performs target-specific staging, checksums, artifact
inventory, source/build metadata, SQLite linkage metadata, and provenance
attestation. Manual dispatch is a complete rehearsal and never publishes.
Candidate/prerelease tags use the same metadata validation with the candidate
version and changelog section.

The current release line records the selected target triples and ReleaseSafe
mode. SBOM files and code signatures are not currently part of the public
artifact manifest; adding either requires a policy change and corresponding
verification before publication.
