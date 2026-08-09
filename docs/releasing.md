# Releasing Caudex

The single release owner is `.github/workflows/release.yml`. It is triggered
by an intentional `vX.Y.Z` or `vX.Y.Z-prerelease` tag. A manual dispatch takes
an existing tag and always runs rehearsal mode; it cannot publish.

## First release

Before merging the release-preparation change:

1. Confirm the npm organization owns `@caudex-workout` and that the intended
   package name is available.
2. Set the repository variable `CAUDEX_NPM_AUTH_MODE=bootstrap` and add a
   short-lived granular `NPM_BOOTSTRAP_TOKEN` Actions secret with permission
   only to publish `@caudex-workout/engine`. Do not put the token in the
   repository or an environment visible to build jobs.
3. Run `zig build release-check` locally and dispatch **Caudex release** with
   `release_tag=v0.1.0`. Review the complete asset manifest and workflow logs.
4. Configure npm Trusted Publishing for this repository and the `release.yml`
   workflow after the package exists. Set `CAUDEX_NPM_AUTH_MODE` to
   `trusted-publishing`, then remove and revoke the bootstrap token.
5. Configure protected tag/release permissions and require the existing pinned
   CI checks. Use local Git signing for the tag if signed tags are part of the
   repository policy.

After the checks are green, the deliberate publication command is:

```sh
git switch main
git pull --ff-only
git tag -s v0.1.0 -m "Caudex v0.1.0"
git push origin v0.1.0
```

Do not use a normal branch push to publish a release.

## Normal future release

Prepare the version, lockfile, generated metadata, and dated changelog entry
through the normal review process. Then the maintainer only needs to create and
push the matching signed tag:

```sh
git switch main
git pull --ff-only
git tag -s vX.Y.Z -m "Caudex vX.Y.Z"
git push origin vX.Y.Z
```

The workflow derives the version from the tag, validates every public version
surface, runs the full release test gate, builds the npm/C/Zig/CLI artifacts,
verifies their contents and hashes, and publishes the exact staged bytes.
Prereleases use npm's `next` dist-tag and are marked prerelease on GitHub.

## Rehearsal and failure handling

`zig build release-check` runs the host-runnable release checks locally,
including npm packing, clean-consumer installation, `npm publish --dry-run`,
host C packaging, Zig source packaging, and host CLI smoke tests. It reports the
cross-platform matrix and provenance work that only GitHub-hosted jobs can run.
The workflow dispatch path exercises the complete matrix and asset manifest but
does not create a tag, publish npm, create a GitHub Release, or push anything.

The workflow refuses malformed tags, metadata mismatches, an existing npm
version, or an existing GitHub Release. A failed run before the external
publication phase leaves no release state. The real run creates one draft
GitHub Release only after all artifacts pass verification. If npm succeeds but
final GitHub promotion fails, leave the exact draft and published npm version
in place; inspect the draft, confirm its asset hashes, and promote that same
draft through an explicitly reviewed maintainer recovery action. Never rebuild
or republish a different tarball and never overwrite a public release.

## Verifying published artifacts

Download the GitHub Release assets, confirm `SHA256SUMS`, and compare the
`release-manifest.json` entries before installing anything. For npm, inspect the
resolved version and run the package's clean-consumer smoke flow. For CLI and C
archives, extract into a new directory, confirm the target and
`build-metadata.json`, verify `SHA256SUMS`, and run the documented version or C
linking smoke test. The release does not currently provide code signatures or
SBOM files; provenance is supplied by npm for the package and GitHub Actions
build attestations for CLI archives.

## What not to do

Do not run `npm publish`, `gh release create`, `gh release edit --draft=false`,
or create a release tag from an ordinary development checkout. Do not rerun a
failed release blindly when a draft or npm version already exists. Resolve the
external state deliberately and record the recovery in the release notes.
