# npm release

The package is currently staged but unpublished. Local packaging and dry-run
checks do not make it available to external consumers; do not run the publish
workflow as part of ordinary development.

The canonical release workflow publishes `@caudex-workout/engine` from a Git
tag named for the package version, such as `vX.Y.Z`. It does not publish from a
branch push or a standalone npm workflow.

## Prepare a release

Before creating the tag:

1. Set the same version in `package.json`, the lockfile root, and the lockfile's
   root package entry.
2. Move the relevant changelog entries from `Unreleased` to a dated
   `## [version] - YYYY-MM-DD` section.
3. Run `zig build test`.
4. Dispatch the **Caudex release** workflow with the proposed tag. Manual runs
   execute the complete build, pack, version check, clean-consumer install, and
   `npm publish --dry-run` path, but cannot publish.

After the first package exists, configure the canonical `release.yml` workflow
as npm Trusted Publishing. The normal path receives an OpenID Connect identity
and does not require a long-lived npm token. The first publication may use the
explicit, temporary `NPM_BOOTSTRAP_TOKEN` path described in
[`docs/releasing.md`](../releasing.md).

## Publish

Push the matching `v<version>` tag. The workflow:

1. Validates the tag, package and lockfile versions, and changelog entry.
2. Runs formatting, build, and the complete test suite.
3. Builds and packs once, then verifies and dry-runs that tarball.
4. Uploads the exact tarball as a workflow artifact.
5. Creates a draft GitHub release containing the same tarball and changelog
   notes.
6. Publishes that tarball to npm with provenance.
7. Makes the already-staged GitHub release public.

Publishing is a single serialized job with concurrency cancellation disabled.
No matrix job can publish a second platform-specific npm artifact. Failures
before the npm step leave at most a draft GitHub release, while failures after
npm publication leave the exact published tarball attached to that draft for
maintainer recovery.
