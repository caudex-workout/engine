# Browser playground

This static playground imports only `@caudex-workout/engine`. It provides an
editable canonical request, switches between the double-progression and RPE
top-set/backoff methodology factories, and also composes a four-exercise
session using fixed and mixed-progression slots. It renders the recommendation,
structured explanation trace, duration estimate, and selected alternatives, and copies or downloads the current fixture. It
requires no application backend or runtime network service.

Both selectors execute their first-party methodology in the packaged runtime.
The session composer uses the same public `caudex.composeSession` operation as
other consumers: changing its temporary equipment or time constraints changes
the composed plan while leaving the intent snapshot untouched. Its output can
be passed to the existing recommendation/active-workout lifecycle after the
host accepts it.

The result panel also calls the public `caudex.findSubstitutes()` operation for
the composed primary exercise. Ranked swaps and their reason codes come from
the engine, while today's temporary equipment and exclusions change the viable
choices without embedding equivalence rules in the browser.

The program-planning lab below the recommendation workspace uses the package's
actual `programs` presets, `instantiateProgram`, `resolveNextSession`,
`proposeProgramAdvancement`, and `acceptProgramAdvancement` exports. It contrasts
an asynchronous upper/lower rotation, fixed weekdays supplied as explicit host
facts, and a structured accumulation/deload block. Restarting creates a fresh
versioned instance and state; previewing is pure; clicking **Accept completion**
is the separate host decision that advances the accepted state.

The default request also demonstrates the separation between a persistent
athlete profile and today's training context. The profile holds durable intent
such as hypertrophy, experience, usual duration, preferences, priorities, and
reusable home/gym equipment profiles. Today's context selects the gym, limits
the session to 35 minutes, removes the cable stack, and adds a temporary overhead
restriction. The resulting recommendation carries an inspectable resolved
context snapshot, so editing the profile for a later workout does not rewrite
the earlier request. See
[athlete profiles and training context](../../docs/athlete-profiles-and-training-context.md)
for the resolution rules and non-goals.

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
