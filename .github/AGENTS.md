# `.github/` instructions

Workflows are repository security and compatibility code.

- Pin every third-party action to a full commit SHA and retain the version
  comment. Keep `permissions` at the minimum job scope; use read-only defaults
  and grant write, attestation, or OIDC permissions only to the publishing job
  that needs them.
- Do not execute untrusted pull-request code with privileged credentials or
  expose secrets to it. Keep checkout credentials disabled where appropriate,
  quote/validate workflow inputs, and use safe shell failure handling.
- Preserve stable required-check/job names, explicit timeouts, and concurrency
  cancellation where appropriate. Manual fuzzing and mutation workflows must
  remain bounded, reproducible, and artifact-producing; do not add nightly
  execution without an explicit policy decision.
- Release workflows must validate before staging or publishing, publish only
  the exact verified artifact, and preserve checksums, manifests, provenance,
  and target-matrix checks. They must not bypass canonical validation.
- Keep dependency update policy and workflow changes reviewable. Run
  `node tools/repo/validate-repository.mjs`; run `actionlint` and `zizmor` when
  available, and keep workflow security findings explicit rather than ignored.
