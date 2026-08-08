# Release validation and staging

Release metadata is recorded in
[`tools/release/release-metadata.json`](../../tools/release/release-metadata.json)
and validated against `build.zig.zon`, npm metadata, the lockfile, the
changelog, and the supported CLI target list.

Run the non-publishing phases locally:

```sh
zig build check-release
node tools/release/validate-release-metadata.mjs
node tools/release/validate-npm-release.mjs v0.1.0
node tools/repo/compatibility-check.mjs
```

The release workflows perform target-specific staging, checksums, artifact
inventory, source/build metadata, SQLite linkage metadata, and provenance
attestation. Publishing and release promotion require maintainers and are not
performed by repository checks. Candidate/prerelease tags must first pass the
same metadata validation with the candidate version and a changelog section.

The current release line records the selected target triples and ReleaseSafe
mode. SBOM generation and reproducible-build comparison are release validation
follow-ups; they are not silently claimed as complete until their selected
artifacts have stable, verified output.
