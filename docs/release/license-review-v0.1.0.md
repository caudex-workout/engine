# v0.1.0 license review

Reviewed 2026-07-26.

Caudex source and official artifacts are MIT licensed. Zig core and native C
libraries have no third-party runtime dependencies. The npm package likewise
has no runtime dependencies.

Development-only npm tools are TypeScript (Apache-2.0), Rollup (MIT), and
`@rollup/plugin-node-resolve` plus its locked transitive dependencies under
permissive licenses. They are used only to compile or test artifacts and are
not bundled. GitHub Actions and the Zig compiler are build infrastructure, not
redistributed runtime components.

Every Zig/C release includes `LICENSE` and `NOTICE`; the npm allowlist includes
its matching license and notice. No copyleft, proprietary, or attribution-only
runtime component is distributed in v0.1.0.
