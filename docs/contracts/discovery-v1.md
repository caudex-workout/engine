# Methodology discovery protocol v1

Discovery v1 is generated from `caudex.discovery` and is shared by direct Zig,
the canonical C/WASM executor, and `@caudex-workout/engine`. It provides:

- `listMethodologies` and `describeMethodology`;
- `validateMethodologyConfig` and `validateMethodologyState`;
- `listCapabilities` for the operations compiled into the runtime.

Descriptors contain stable IDs, display text, methodology/config/state
versions, UI-neutral field types, required flags, exact-decimal markers,
numeric bounds, unit dimensions, enum choices, deprecation flags, and schema
references. They intentionally contain no HTML, CSS, framework components, or
layout instructions.

Schema version 1 rejects unknown versions and unsupported methodology IDs
through distinct boundary statuses. A well-formed validation request returns a
`MethodologyValidationResult`; invalid configuration or state is structured
public issue data rather than a transport failure.

The JSON schema is
[`schemas/discovery/v1/discovery.schema.json`](../../schemas/discovery/v1/discovery.schema.json).
The npm declarations describe the wire values but do not duplicate descriptor
content; runtime metadata always comes from the Zig/WASM registry.
