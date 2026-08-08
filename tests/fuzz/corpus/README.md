# Fuzz corpus

The smoke corpus is kept inline in `smoke.zig` so the release check has no
filesystem dependency. Maintainers may add minimized real fixtures here for
coverage-guided runs; large canonical fixtures should be referenced or copied
by a small seed-generation script rather than duplicated.
