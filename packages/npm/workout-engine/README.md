# TypeScript loader and facade

The v0.1 facade is initialized once and accepts ordinary canonical request
objects:

```ts
import {
  createCaudex,
  type RecommendationRequest,
} from "@caudex/workout-engine";

const caudex = await createCaudex();
const result = caudex.recommendSession(request satisfies RecommendationRequest);

if (!result.ok) {
  console.error(result.issues);
}

caudex.dispose();
```

`createCaudex()` hides Node filesystem loading and browser fetch/streaming behind
one asynchronous API. Callers may explicitly supply a `WebAssembly.Module`,
WASM bytes, or a URL when embedding or testing. After initialization,
recommendation calls are synchronous and deterministic.

Canonical validation and unsupported methodology/version failures are returned
as `ok: false` results with structured issues. WASM loading, ABI mismatch,
missing exports, and runtime creation failures throw
`CaudexInitializationError` with a typed `code`. Failures after successful
initialization that prevent safe execution throw `CaudexRuntimeError`.

The public `Caudex` value exposes only `recommendSession()` and `dispose()`.
Linear-memory addresses, allocation functions, result descriptors, and runtime
handles remain private to the loader.

The default WASM URL is `../wasm/caudex.wasm` relative to the distributed
JavaScript module. Packaging and final asset placement belong to CWE-063.
