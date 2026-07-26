# npm release

The npm release workflow publishes `@caudex/workout-engine` from a Git tag named
for the package version, such as `v0.1.0`.

## Prepare a release

Before creating the tag:

1. Set the same version in `package.json`, the lockfile root, and the lockfile's
   root package entry.
2. Move the relevant changelog entries from `Unreleased` to a dated
   `## [version] - YYYY-MM-DD` section.
3. Run `zig build test`.
4. Run the `npm release` workflow manually with the proposed tag. Manual runs
   execute the complete build, pack, version check, and `npm publish --dry-run`
   path, but cannot publish.

The public npm package must configure this repository's `npm release` workflow
as a trusted publisher. The workflow receives an OpenID Connect identity and
does not require a long-lived npm token.

## Publish

Push the matching `v<version>` tag. The workflow:

1. Validates the tag, package and lockfile versions, and changelog entry.
2. Runs formatting, build, and the complete test suite.
3. Adds the actual GitHub repository URL to the isolated package manifest for
   npm provenance.
4. Builds and packs once, then verifies and dry-runs that tarball.
5. Uploads the exact tarball as a workflow artifact.
6. Creates a draft GitHub release containing the same tarball and changelog
   notes.
7. Publishes that tarball to npm with provenance.
8. Makes the already-staged GitHub release public.

Publishing is a single serialized job with concurrency cancellation disabled.
No matrix job can publish a second platform-specific npm artifact. Failures
before the npm step leave at most a draft GitHub release, while failures after
npm publication leave the exact published tarball attached to that draft for
maintainer recovery.

