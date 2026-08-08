# Security policy

Please do not disclose vulnerabilities in public issues. Report them privately
through the repository’s GitHub security advisory mechanism (preferred) or by
contacting the maintainers listed in the repository metadata. Include a minimal
reproduction, affected version/commit, consumption surface, platform/tool
versions, and whether persistence or release tooling is involved.

Maintainers should enable secret scanning and push protection, dependency
review, and private vulnerability reporting in GitHub repository settings.
Workflows use least-privilege permissions and should never expose release
secrets to pull-request code. Releases require maintainer review, checksums,
and provenance validation.

Supported security fixes follow the currently supported release line. The v0.1
security review is recorded in `docs/release/security-review-v0.1.0.md`.
