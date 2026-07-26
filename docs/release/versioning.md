# Versioning and migration policy

Official Zig, npm/WebAssembly, and C artifacts use lockstep versions through
v0.x. Canonical schema, C ABI, methodology implementation, configuration, and
state versions remain independent and are recorded in contracts or results.

Before 1.0, breaking API changes occur only in minor releases. Patch releases
must not intentionally change recommendation semantics for an unchanged
methodology version. Algorithm changes increment that methodology version.

Breaking releases include changelog migration notes identifying renamed or
removed APIs, schema changes, state migration requirements, and replacement
paths. Released tags, schemas, C ABI versions, and migration fixtures are
immutable. Deprecations state their replacement and intended removal release.

Version 0.1.0 is the initial contract, so no prior-version migration is needed.
Hosts own methodology state and choose whether to accept proposed next state;
Caudex never migrates or persists host data implicitly.
