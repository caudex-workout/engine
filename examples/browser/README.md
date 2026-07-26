# Browser playground

This static playground imports only `@caudex/workout-engine`. It provides an
editable canonical request, switches between the double-progression and RPE
top-set/backoff methodology factories, renders the recommendation and its
structured explanation trace, and copies or downloads the current fixture. It
requires no application backend or runtime network service.

The current npm runtime recommends with double progression. Selecting RPE
demonstrates the same structured `methodology.unsupported` result hosts receive
when a methodology is not compiled into a boundary.

The repository test installs the packed npm artifact, bundles `app.js` with
Rollup and its official node-resolution plugin, and places `caudex.wasm` beside
the static output. Serve the resulting directory over HTTP; WebAssembly loading
generally does not work from a `file:` URL.
