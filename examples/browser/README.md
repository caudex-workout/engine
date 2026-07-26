# Browser example

This static example imports only `@caudex/workout-engine`, builds a
recommendation, evaluates a completed workout, and renders both results. It
requires no application backend or runtime network service.

The repository test installs the packed npm artifact, bundles `app.js` with
Rollup and its official node-resolution plugin, and places `caudex.wasm` beside
the static output. Serve the resulting directory over HTTP; WebAssembly loading
generally does not work from a `file:` URL.
