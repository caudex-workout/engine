# Repository experience audit and implementation plan

Date: 2026-08-08

This plan covers the contributor experience, consumer integration guardrails,
compatibility protection, CI security, release validation, and diagnostics
audit requested for Caudex. The repository was clean at the start of the
audit. The existing v0.1.0 contracts, migrations, fixtures, and release
artifacts are treated as historical inputs; this work does not rewrite them.

## Initial classification

| Workstream | Initial state | Classification and decision |
| --- | --- | --- |
| 1. Canonical repository checks | Many useful leaf steps and a broad `test` step exist; no canonical hierarchy | Partially complete; add `check-fast`, `check`, and `check-release` around existing steps. |
| 2. Pull-request CI | Linux and native workflows exist but CI duplicates the build graph and has no stable intent-oriented jobs | Partially complete; make `zig build check` the source of truth and split stable CI jobs. |
| 3. Contributor onboarding | README and domain docs exist; no contributor setup/testing/repository-map guide | Partially complete; add focused human contributor docs and links. |
| 4. Ergonomics/version synchronization | `build.zig.zon` is authoritative for Zig/package version, but versions are repeated in workflows and release scripts; no doctor | Partially complete; add `tools/dev doctor`, version metadata, editor config, and drift checks. |
| 5. README/badges | Consumer README exists and records v0.1.0, but first-screen routing is dense and badges are absent | Partially complete; add restrained verified badges and a path selector without inflating claims. |
| 6. Social files/templates | No standard security, support, governance, conduct, CODEOWNERS, or structured issue forms | Missing; add the files that have clear maintainer/user value. |
| 7. Actions/dependency security | Permissions/concurrency are present; actions use tags and security automation is absent | Partially complete; pin actions, add Dependabot, actionlint/zizmor validation hooks, and settings guidance. |
| 8. Nix | No flake | Intentionally omitted at user direction; standard Zig/Node/C paths remain the supported baseline. |
| 9. Devcontainer/Codespaces | No configuration | Missing but appropriate as optional tooling; add a non-mutating container configuration. |
| 10. Public contract snapshots | Contracts, schemas, headers, and tests exist, but no generated semantic baseline | Partially complete; add a reproducible manifest and drift checker with explicit classifications. |
| 11. Previous-release compatibility | v0.1.0 release docs and fixtures exist, but no `tests/compat` suite | Partially complete; add immutable v0.1 compatibility metadata/consumer checks where feasible. |
| 12. Advanced correctness | Determinism, bounds, methodology, and reference-model tests exist; no organized property/fuzz/failure/mutation/metamorphic harness | Partially complete; add small repository-owned deterministic/metamorphic checks and document deferred fuzz/mutation execution. |
| 13. Release infrastructure | Release workflows and scripts exist, but CLI workflow and verifier repeat v0.1.0 data | Partially complete; add canonical release metadata and validation/staging commands without publishing. |
| 14. Performance/diagnostics | CLI benchmark and structured result diagnostics exist; no budgets or opt-in inspection contract | Partially complete; add baseline budget documentation and a non-invasive benchmark/diagnostic policy. |

## Implementation phases

1. **Canonical checks and CI:** add the build-step hierarchy, repository
   validation scripts, stable CI job boundaries, and security-tool validation.
2. **Contributor experience:** add the supported-tool manifest and doctor,
   contributor documentation, editor settings, README routing, and social
   files/templates.
3. **Environments and security:** add optional devcontainer support when its
   declared versions can be kept in sync, plus Dependabot and workflow
   hardening. Nix is intentionally out of scope for this change.
4. **Compatibility and release guardrails:** generate semantic public-surface
   and migration snapshots, add v0.1 compatibility records, and centralize
   release metadata validation/staging.
5. **Correctness and performance:** add deterministic metamorphic checks and
   document the measured benchmark baseline/budgets and diagnostics stability.
6. **Final integration:** run `zig build check`, attempt `check-release`, run
   available Nix/security checks, inspect the diff, and record limitations.

## Compatibility policy for this change

All changes are tooling, documentation, test, or additive repository metadata.
No released migration, stable schema, ABI layout, explanation/issue code,
methodology identifier, or public result field is changed. New snapshots are
generated from the current v0.1.0 contracts and are intended to make future
changes explicit rather than silently prohibiting intentional changes.

## Known practical limits

The audit cannot change GitHub branch protection, repository security settings,
release tags, package registries, or external credentials. Nix and GitHub
security tools may be unavailable in the current macOS environment; CI commands
for those tools will be documented and must not be represented as locally
passed. Full cross-platform compatibility and publication validation remain
release-only operations.

## Results after implementation

| Workstream | Result | Main files | Remaining limitation |
| --- | --- | --- | --- |
| 1 | Complete for current repository | `build.zig`, `docs/development/testing.md` | Release artifact matrix remains release-only. |
| 2 | Complete | `.github/workflows/ci.yml`, `security.yml` | Branch protection must be configured manually. |
| 3 | Complete | `CONTRIBUTING.md`, `docs/development/*` | No additional hosted contributor service. |
| 4 | Complete | `.editorconfig`, `tools/support/versions.json`, `tools/dev/*` | Doctor is read-only and cannot install tools. |
| 5 | Complete | `README.md` | npm badge omitted because the package is not publicly published. |
| 6 | Complete | root policy files and `.github/*` templates | CODEOWNERS team existence must be confirmed by maintainers. |
| 7 | Complete for repository guardrails | pinned workflows, Dependabot, `security.yml`, `SECURITY.md` | actionlint/zizmor are documented optional tools because they are absent locally/runner image. |
| 8 | Intentionally omitted | plan and setup docs | Nix was skipped at user direction. |
| 9 | Complete, optional | `.devcontainer/*` | Linux container is not a substitute for native platform validation. |
| 10 | Complete for a semantic baseline | `tools/repo/public-contract-snapshot.mjs`, `docs/contracts/public-surface-v0.json` | Snapshot review/classification is still a human compatibility decision. |
| 11 | Initial suite complete | `tests/compat/v0.1/*`, `tools/repo/compatibility-check.mjs` | Historical consumer binaries/databases are not bundled; current fixtures and clean consumers are the executable coverage. |
| 12 | Partial, targeted | existing deterministic/reference tests plus compatibility checks | Full fuzzing, failure injection, and mutation runs remain manual/release work. |
| 13 | Partial but validated | `tools/release/release-metadata.json`, `validate-release-metadata.mjs`, build release steps | SBOM, reproducible-build comparison, and publishing are not enabled. |
| 14 | Documented baseline/policy | `docs/development/diagnostics-and-limits.md`, existing CLI benchmark | Allocation/peak-memory and full npm/WASM benchmark matrix need a stable cross-platform harness. |

### Measured local baseline

The canonical suite reported: packed npm artifact 213,342 bytes, unpacked npm
artifact 687,770 bytes, WASM 521,488 bytes, TUI render benchmark about 26.8 ms,
and fresh CLI query about 17.3 ms on the local Apple-silicon macOS runner.
These are regression baselines only, not portability or marketing claims.
