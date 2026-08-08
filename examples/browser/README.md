# Browser playground

This static playground imports only `@caudex-workout/engine`. It provides an
editable canonical request, switches between the double-progression and RPE
top-set/backoff methodology factories, renders the recommendation and its
structured explanation trace, and copies or downloads the current fixture. It
requires no application backend or runtime network service.

Both selectors execute their first-party methodology in the packaged runtime.

The repository test installs the packed npm artifact, bundles `app.js` with
Rollup and its official node-resolution plugin, and places `caudex.wasm` beside
the static output. Serve the resulting directory over HTTP; WebAssembly loading
generally does not work from a `file:` URL.

For an IndexedDB-backed active-workout flow, see
[`indexeddb-workout.js`](indexeddb-workout.js). It loads the optional
first-party catalog projection, starts a recommendation, persists tracking
revisions, reloads the active workout after a page-style restart, converts
completion for evaluation, and accepts proposed methodology state only through
an explicit compare-and-set call. The engine package remains database-free; the
adapter is an optional browser dependency.
