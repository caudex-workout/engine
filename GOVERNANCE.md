# Governance

Caudex is maintainer-led. Maintainers review code, contracts, releases, and
security reports; contributors are encouraged to propose changes through
issues and pull requests. Public contract, dependency-direction, persistence,
or release-policy changes require an ADR or an explicit update to the relevant
accepted ADR.

Repository settings such as branch protection, required CI checks, secret
scanning, push protection, and dependency review are configured manually by
maintainers. The intended required checks are `Canonical pull-request check`,
`Quality and fast checks`, and the platform-native compatibility checks once
their runner coverage is stable.
