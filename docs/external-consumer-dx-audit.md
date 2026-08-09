# External Consumer Developer-Experience Audit

Date: 2026-08-08
Repository state: 5c3bfaf53bc6b33bea7ff8a727285a7c48059ab0
Platform: macOS Darwin 25.0.0, arm64

## 1. Executive summary

Today, a competent external developer does not reach a useful Caudex
operation through any of the three advertised distribution paths.

- The documented Zig v0.1.0 archive URL returns HTTP 404.
- The documented C release page returns HTTP 404, the public repository has no
  advertised v0.1.0 tag, and the C workflow uploads a short-lived Actions
  artifact rather than publishing a GitHub release asset.
- npm install @caudex-workout/engine returns registry E404; the package is not
  published.

These are P0 adoption blockers, not merely unfamiliar ecosystem conventions.
The npm README does acknowledge that the package is unpublished, but the
top-level installation instructions still present npm install as the first
step. The Zig and C documentation describes release artifacts that an external
developer cannot obtain.

The requested local-build fallback was useful but does not change that result.
Locally generated artifacts produced a meaningful recommendation in all three
languages and exposed additional friction:

- Zig has no copyable minimum end-to-end example for constructing the typed
  request. The developer must discover primitives types, canonical string
  configuration, methodology versions, and caller-owned Output storage.
- Ordinary Apple Clang cannot link the generated C static archive because
  compiler-runtime symbols are unresolved; the repository release test uses
  zig cc instead.
- The generated macOS shared library has an absolute install name pointing
  into the repository build directory, so a copied external bundle is not
  self-contained.
- TypeScript is comparatively ergonomic once a local tarball exists, but the
  ESM-only package requires a normal npm init project to add type: module. The
  quickstart does not show that host configuration.

### Scores

| Ecosystem | Score | Evidence |
|---|---:|---|
| Zig | 2/10 | The advertised release cannot be fetched. A local package can run only after source-level request construction and a manifest retry. |
| C | 1/10 | No external artifact can be obtained. The local static artifact needs zig cc and the macOS shared artifact is not relocatable. |
| TypeScript/Node.js | 2/10 | The advertised npm package is absent. A local tarball works after ESM setup, but ordinary discovery and installation stop at E404. |
| Overall | 1/10 | Every first-use path fails before an external consumer can compile and execute Caudex. |

The smallest high-leverage correction is to make one immutable release real and
machine-discoverable: publish the npm tarball, tag and expose the Zig source
archive, attach C bundles to that same GitHub release, and test the public URLs
from a clean machine. Next, add one minimal copyable workflow per language
producing the same initial double-progression recommendation.

## 2. Test environment and methodology

### Material used before source inspection

The black-box phase used only the consumer-facing README, quickstart,
integrator/package guides, C release/ABI/WASM contract pages, and explicitly
linked consumer examples:

- README.md
- docs/quickstart-and-concepts.md
- docs/zig-package.md
- docs/zig-integrator-guide.md
- docs/release/c.md
- packages/npm/workout-engine/README.md
- docs/contracts/c-abi-v2.md
- docs/contracts/wasm-v2.md

Implementation files, tests, fixtures, generated bindings, and agent-only
instructions were not used to get the black-box install paths working. Only
after all three external attempts were preserved were source, build scripts,
release workflows, generated manifests, and examples inspected for diagnosis.

### Counting rule

Each shell command issued from a temporary project is counted. Read-only
inspection and editor/file-patch actions are not adoption commands. A shell line
containing several operations counts as one issued command.

The clean-room projects remain at:

    /tmp/caudex-external-dx-audit-XGBcfs/
    ├── zig-clean/
    ├── c-clean/
    └── node-clean/

The local fallback copied generated artifacts into those projects. Disposable
node_modules, npm cache, Zig cache, binaries, and build output stayed under
/tmp and were not added to the repository.

## 3. Zig clean-room diary

Starting directory: /tmp/caudex-external-dx-audit-XGBcfs/zig-clean.

| # | Command | Expected and observed result | Docs/inference |
|---:|---|---|---|
| 1 | mkdir -p .../zig-clean/src | Created an empty consumer project. | Ordinary setup; not documented. |
| 2 | zig init | Created build.zig, build.zig.zon, and src/main.zig. | Reasonable Zig setup; not documented. |
| 3 | zig fetch --save https://github.com/caudex-workout/engine/archive/refs/tags/v0.1.0.tar.gz | Sandbox attempt failed with error: unable to connect to server: UnknownHostName. | Exact documented command, retried unchanged with network access. |
| 4 | Same zig fetch command with network access | error: bad HTTP response code: 404 Not Found. | Definitive distribution failure; no local source was substituted. |

The guide uses OWNER in the URL, so the repository owner had to be inferred from
the README badge/public repository. The public repository was reachable, but
the release URL remained 404. The tag lookup also produced no v0.1.0 tag:

    git ls-remote --tags https://github.com/caudex-workout/engine.git refs/tags/v0.1.0
    # no output

No import, build, or useful workflow could be attempted externally. The next
guide code sample accepts a RecommendationRequest but does not construct one.

### Local-build fallback

After preserving the external result, zig build package-zig generated a source
package and it was copied into the temporary project as caudex-core. The first
local build failed:

    error: missing top-level 'fingerprint' field; suggested value: 0xb7a910819bc3129f
    error: missing top-level 'paths' field

Adding Zig 0.16 manifest fields made the project build. This is not counted as
an external release failure, but it shows that a hand-authored local package
recipe needs Zig-specific manifest knowledge.

The first import-only program printed:

    Caudex module imported

The useful program then required discovering and writing all of these:
primitives.Id.parse, primitives.Timestamp.parse, the
double_progression.Config shape, canonical string measurements, methodology
Version, methodology ID caudex.double-progression, a one-exercise
training.ExerciseCatalog, available equipment IDs, and caller-owned
engine.Output storage. It printed:

    incline-dumbbell-press: 8 reps x 45.0 lb, explanation=exercise.selected.available_equipment

### Zig metrics

| Metric | External | Local fallback |
|---|---:|---:|
| Commands to useful run | 4, blocked | 6 additional |
| Setup/install commands | 3 | 5 additional |
| Build/run commands | 0 | 4, including one failure |
| Failed commands | 2: network error and 404 | 1 manifest failure |
| Trial-and-error commands | 1 network retry | 1 manifest correction |
| Undocumented assumptions | 3 | 8 including typed API knowledge |
| Awkward API interactions reached | 0 | 4 |
| Confusing errors reached | 0 | 1 |
| Workarounds | None available externally | Local package copy, manifest edit, source inspection |

External assumptions were that OWNER could be resolved, that a v0.1.0 archive
actually existed, and that the tagged archive was the supported package rather
than a workspace-only source tree.

### Zig time-to-concept and API findings

Before the useful operation, the developer needed package/module wiring,
host-owned borrowed data, validated IDs, explicit RFC 3339 time, exact decimal
measurements and units, methodology ID/version/configuration, catalog and
equipment snapshots, and caller-owned bounded output storage.

The first seven are legitimate domain concepts. The split between primitive
types and canonical string configuration, the exact one-exercise vertical
slice, direct registry version lookup, and the absence of a runnable request
example are accidental onboarding concepts.

| Interaction | Natural expectation | Required behavior | Severity/improvement |
|---|---|---|---|
| Constructing RecommendationRequest | A builder or complete typed example. | Manually parse IDs/time, assemble nested arrays, choose ID/version, and supply Output. | P1: publish a minimum typed example. |
| Output lifetime | A result object with obvious ownership. | Caller retains output storage and all input backing slices. | P2: document lifetime adjacent to recommendSession. |
| Configuration shape | One consistent domain representation. | Config uses canonical amount/unit strings while request/catalog use parsed primitives. | P2: add conversion helpers or explain the split. |
| Catalog size | A session recommendation over supplied catalog. | v0.1 typed path rejects catalog lengths other than exactly one. | P2: document the limit and return a named/structured reason. |

## 4. C clean-room diary

Starting directory: /tmp/caudex-external-dx-audit-XGBcfs/c-clean.

| # | Command | Expected and observed result | Docs/inference |
|---:|---|---|---|
| 1 | mkdir -p .../c-clean/src | Created a standalone C project. | Ordinary setup; not documented. |
| 2 | curl -L -I https://github.com/caudex-workout/engine/releases/tag/v0.1.0 | GitHub responded HTTP/2 404. | The C guide links a release matrix but gives no artifact URL. |
| 3 | git ls-remote --tags https://github.com/caudex-workout/engine.git refs/tags/v0.1.0 | No tag output. | The source-build fallback also cannot start. |

No header, library, include path, linker command, or executable could be used
externally. The C page documents target names and the two-call sizing protocol,
but not how to download the corresponding bundle.

### Local-build fallback

zig build package-c generated a local host bundle and six-target matrix. A
minimal consumer used caudex.h and a hand-written canonical recommendation
envelope.

The ordinary compiler attempt:

    cc -std=c11 -Icaudex/include main.c caudex/lib/libcaudex.a -o caudex-c

failed with unresolved Apple arm64 compiler-runtime symbols including
___divtf3, ___fixtfti, ___floatuntitf, ___gttf2, ___lttf2, ___multf3, ___netf2,
and _roundq.

Using zig cc, matching the repository release test, succeeded after setting a
writable temporary Zig cache. The program printed a 2054-byte JSON result with
incline-dumbbell-press, three working sets, a 45 lb initial load, and the
exercise.selected.available_equipment explanation.

The shared-library experiment compiled with Apple Clang, but:

    otool -D zig-out/c-release-host/aarch64-macos/lib/libcaudex.dylib
    /Users/julian/Documents/GitHub/caudex/zig-out/c-release-host/aarch64-macos/lib/libcaudex.dylib

The absolute repository path is embedded as the dylib install name. The local
process ran only because that original path existed; a copied release bundle
would not be self-contained.

### C metrics

| Metric | External | Local fallback |
|---|---:|---:|
| Commands to useful run | 3, blocked | 8 additional |
| Setup/install commands | 3 | 4 additional |
| Build/link commands | 0 | 4 attempts before successful zig cc |
| Failed commands | 1 semantic 404 | 2: Apple Clang link and first zig cc cache permission |
| Trial-and-error commands | 0 | 2 |
| Undocumented assumptions | 3 | 7 including local linking |
| Awkward API interactions reached | 0 | 3 |
| Confusing errors reached | 0 | 1 linker failure |
| Workarounds | None available externally | zig cc, hand-written JSON, local absolute-path dylib |

External assumptions were the missing artifact URL/name, bundle extraction
layout, and a valid canonical request fixture. The C README points to
examples/c/conformance.c but only tells a maintainer to run zig build example-c
from the repository root; the example requires a request-file argument.

### C time-to-concept and API findings

The first useful operation requires target/linkage selection, the ABI version,
opaque runtime lifecycle, a versioned JSON envelope, the null-output sizing
call, caller allocation and the second call, JSON result interpretation, and
numeric status mapping.

The ABI concepts are reasonable. Knowing that the archive also needs Zig
compiler-runtime support, that the repository test uses zig cc, and that a
release dylib must be relocatable are accidental distribution concepts.

| Interaction | Natural expectation | Required behavior | Severity/improvement |
|---|---|---|---|
| Generic execute ABI | A typed C recommendation call or request builder. | Hand-author JSON and parse JSON manually. | P2: ship a complete inline C11 example. |
| Two-call sizing | Conventional but easy to misuse. | Null-output sizing, exact malloc, second call, host free. | P2: add an inline helper and status guarantees. |
| Static archive link | Ordinary C toolchain consumes it. | Apple Clang fails; zig cc succeeds. | P1: make it self-contained or document supported link flags/driver. |
| Shared macOS library | rpath selects copied library. | Absolute build-directory install name. | P1: use @rpath and test from a copied bundle. |

## 5. TypeScript/Node.js clean-room diary

Starting directory: /tmp/caudex-external-dx-audit-XGBcfs/node-clean.

| # | Command | Expected and observed result | Docs/inference |
|---:|---|---|---|
| 1 | mkdir -p .../node-clean | Created an empty Node project. | Ordinary setup; not documented. |
| 2 | npm init -y | Created package.json. | Ordinary setup; not documented. |
| 3 | npm install @caudex-workout/engine | npm error code E404; package is not in the public registry. | Exact documented install command. |
| 4 | npm search caudex-workout --json | No result output. | Natural discovery test; no alternative was suggested. |

No TypeScript configuration or workflow could be reached through the external
package path. The README note that the package is unpublished is honest, but it
means the first quickstart command is known to fail today.

### Local-build fallback

zig build package-npm built local package contents. npm pack initially failed
because the host npm cache had root-owned files; a temporary cache produced
caudex-workout-engine-0.1.0.tgz. The tarball was installed into the clean
project without workspace linking.

The documented TypeScript code was copied with an inline catalog. Strict
compilation first failed:

    index.ts(7,16): error TS1309: The current file is a CommonJS module and cannot use 'await' at the top level.

Adding type: module to package.json and compiling with TypeScript 5.9.2 under
NodeNext made the program typecheck and run:

    incline-dumbbell-press
    exercise.selected.available_equipment

A natural CommonJS probe produced:

    Error [ERR_PACKAGE_PATH_NOT_EXPORTED]: No "exports" main defined in .../node_modules/@caudex-workout/engine/package.json

CommonJS is documented as unsupported, so this is not a compatibility bug, but
the error does not teach the developer that the package is intentionally
ESM-only.

### TypeScript metrics

| Metric | External | Local fallback |
|---|---:|---:|
| Commands to useful run | 4, blocked | 10 additional |
| Setup/install commands | 3 | 6 additional |
| Build/typecheck/run commands | 0 | 3 |
| Failed commands | 1 E404 | TS setup produced no compiler, then TS1309; expected CJS probe also failed |
| Trial-and-error commands | 1 npm search | 2 |
| Undocumented assumptions | 2 | 5 including host ESM/TypeScript configuration |
| Awkward API interactions reached | 0 | 2 |
| Confusing errors reached | 0 | 2 |
| Workarounds | None available externally | Local tarball, temporary cache, copied TypeScript compiler |

### TypeScript time-to-concept and API findings

The first useful operation requires ESM host configuration, asynchronous
createCaudex initialization and disposal, a complete canonical snapshot,
methodology factory and exact decimal/unit shapes, and result.ok/explanation
handling. The snapshot and proposal semantics are legitimate; host type:
module, NodeNext configuration, and local WASM asset details should be handled
by a copyable quickstart.

## 6. Quantitative comparison

The primary table describes the actual public path. Blocked means no useful
operation was possible without leaving the documented consumer workflow.

| Metric | Zig | C | TypeScript |
|---|---:|---:|---:|
| Commands to first useful run | 4, blocked | 3, blocked | 4, blocked |
| Failed commands | 2 | 1 semantic 404 | 1 |
| Undocumented assumptions | 3 | 3 | 2 |
| Awkward API interactions reached | 0 | 0 | 0 |
| Confusing errors reached | 0 | 0 | 0 |
| Package/distribution issues | 2 | 3 | 2 |
| Documentation defects | 3 | 3 | 3 |
| Workarounds for external use | None available | None available | None available |
| Local fallback commands after artifact existed | 6 | 8 | 10 |

Zero awkward/confusing API counts in the external columns are not positive
signals; distribution failed before the APIs were reachable.

## 7. Cross-language consistency

All three bindings should teach one model:

    host snapshot + explicit methodology + explicit time/equipment
        -> deterministic recommendation proposal
        -> inspect explanations and issues
        -> host accepts/discards proposal and persists proposed state

TypeScript expresses this most naturally. C exposes the same operation as a
versioned JSON envelope and caller-owned output. Zig exposes the typed
equivalent, but the public guide does not show the mapping.

Observed inconsistencies:

- Zig uses parsed Id, Timestamp, and primitive catalog values; C/TypeScript use
  canonical JSON-shaped strings and camelCase fields.
- C/WASM require a generic operation envelope; TypeScript hides it; Zig
  bypasses it with a typed direct call. No first-use page shows these are the
  same operation.
- TypeScript has methodology factories and typed runtime errors; C has numeric
  statuses plus JSON issues; Zig has a small direct-call error set without a
  structured first example.
- TypeScript owns WASM transport resources, C owns output buffers, and Zig owns
  fixed output storage. Each model is reasonable, but the ownership sentence
  should be shared: the host owns the proposal; the binding owns transport
  resources.
- The generated Zig source package says 0.2.0-dev while root/npm/release docs
  say 0.1.0.

## 8. Prioritized findings

| ID | Priority/category | Finding | Classification |
|---|---|---|---|
| DX-001 | P0 Release/distribution | No usable v0.1.0 external release: Zig archive and GitHub release are 404; tag is absent. | Broken/unfinished release gate |
| DX-002 | P0 Packaging | npm package returns E404. | Acknowledged unfinished state, still an adoption blocker |
| DX-003 | P0 Release/distribution | C workflow uploads a 14-day Actions artifact but does not attach C bundles to a public release. | Broken/documentation mismatch |
| DX-004 | P1 Build integration | Ordinary Apple Clang cannot link the static archive; repository tests use zig cc. | Broken for implied C toolchain/undocumented workaround |
| DX-005 | P1 Packaging | macOS dylib embeds an absolute build-directory install name. | Broken release artifact |
| DX-006 | P1 Documentation/API | Zig guide has no minimum runnable typed recommendation. | Missing onboarding |
| DX-007 | P1 Documentation | C docs lack external download, extraction, compile, link, run, and valid request instructions. | Missing consumer guidance |
| DX-008 | P2 Documentation | Zig URL contains OWNER placeholder. | Unnecessarily difficult |
| DX-009 | P2 Documentation | Node example requires a companion sample-catalog file; packed README links to repository-relative docs. | Misleading/incomplete example |
| DX-010 | P2 API/Error UX | One-exercise typed limitation returns only InvalidRequest. | Unnecessarily difficult |
| DX-011 | P2 Cross-language consistency | No shared first-use mapping across Zig, C, and TypeScript. | Documentation boundary |
| DX-012 | P2 Packaging/versioning | Zig package metadata is 0.2.0-dev while docs/npm/release are 0.1.0. | Version inconsistency |
| DX-013 | P2 Error UX | CJS receives ERR_PACKAGE_PATH_NOT_EXPORTED instead of a useful ESM-only explanation. | Confusing though documented |
| DX-014 | P3 Documentation | C wording about freeing result buffers can be read as engine-owned under ABI v2. | Ambiguous wording |

Classification notes: CommonJS being unsupported is an intentional/documented
limitation, while its poor error recovery is a P2 error-UX issue. Explicit
caller-owned buffers and asynchronous WASM initialization are legitimate
ecosystem/API choices, not defects by themselves. Missing public artifacts are
unfinished but acknowledged in the npm README and accidental/mismatched in the
Zig/C release claims. The ESM setup is partly merely unfamiliar; it becomes a
DX issue because the first TypeScript quickstart omits the required host
configuration. The absolute dylib path, missing C release assets, and absent
public package are accidental release/distribution failures.

## 9. Recommended fixes

### Immediate adoption blockers

1. Create and verify immutable v0.1.0, make the Zig archive URL resolve, and
   replace OWNER with the actual repository URL.
2. Publish @caudex-workout/engine@0.1.0, or remove the public npm install
   quickstart until publication is complete. Make local-only status prominent.
3. Attach C target bundles to the same GitHub release with stable names,
   checksums, extraction instructions, and one-line download examples.
4. Add a release smoke test starting from public URLs and the public registry;
   local package tests cannot detect absent releases or npm publication.

### High-leverage DX improvements

1. Publish a complete Zig example constructing RecommendationRequest, invoking
   recommendSession, printing result data, and explaining lifetimes.
2. Publish a complete C11 example with inline request, status checks, sizing,
   malloc, second execution, JSON output, and cleanup.
3. Add type: module and minimal tsconfig to the TypeScript quickstart, or use an
   async main function that does not require top-level await.
4. Add a “same recommendation, three bindings” page mapping shared concepts and
   field names.
5. Replace the bounded one-exercise InvalidRequest behavior with a named or
   structured limitation.

### API improvements

1. Keep the deterministic host-owned architecture, but add a small optional Zig
   request builder/conversion helper or a canonical first-use example.
2. Add a C helper snippet for the two-call execute pattern.
3. Document exactly when out_required is written and when output is untouched.
4. Set a relocatable @rpath/libcaudex.dylib install name and run copied-bundle
   tests.
5. Synchronize package, engine, Zig, npm, ABI, and schema versions from one
   release source of truth.

### Documentation/examples

- Use the actual repository owner and tag in every archive command.
- Make the C request fixture public or inline it in the example.
- Make the Node example self-contained, including sample-catalog data.
- Replace packed npm README repository-relative links with stable public URLs.
- Mark package/test commands as maintainer validation, not consumer install.
- Document the v0.1 typed Zig catalog-size limitation.

### Packaging/release

- Publish one C archive per target with include, lib, metadata, notices, and
  checksums.
- Validate public release URLs from a disposable machine before calling a
  release current.
- Publish the exact npm tarball already tested by the workflow.
- Make the Zig package manifest version match the release record; do not ship a
  0.2.0-dev package with a v0.1 README.

### Nice-to-have polish

- Improve the CommonJS failure path or provide a compatibility wrapper.
- Add pnpm/yarn coverage after the canonical npm path is reliable.
- Add a first-use “time to recommendation” example to release notes.

## 10. Before/after impact estimates

| Change | Observed today | Expected after fix |
|---|---|---|
| Publish npm and fix quickstart | 4 commands to E404 | About 5–6 commands, zero package failure |
| Publish Zig tag/archive and typed example | 4 commands to 404; 6 local fallback commands | About 6–8 commands, no source inspection |
| Attach C bundles and add C11 quickstart | 3 commands to 404 | About 6–8 commands, zero artifact uncertainty |
| Fix C artifacts | Apple Clang static failure; dylib points to repository | Supported C compiler works; copied shared bundle runs |
| Add ESM/TS setup | TS1309 retry after local install | Zero expected configuration retry |
| Align versions | v0.1 docs/npm vs 0.2.0-dev Zig package | One release version across bindings |

## 11. Reproduction information

### Versions

    OS: macOS Darwin 25.0.0, arm64
    Zig: 0.16.0
    Node: v23.2.0
    npm: 10.9.0
    TypeScript: 5.9.2 in local fallback; not globally installed
    C compiler: Apple clang 16.0.0 (clang-1600.0.26.4)
    Claimed Caudex compatibility: v0.1.0, Zig 0.16.x, Node >=22

### Temporary project layouts

    zig-clean/
    ├── build.zig
    ├── build.zig.zon
    ├── src/main.zig
    └── caudex-core/                 # local fallback only

    c-clean/
    ├── main.c
    ├── request.json
    └── caudex/
        ├── include/caudex.h
        └── lib/{libcaudex.a,libcaudex.dylib}

    node-clean/
    ├── package.json
    ├── tsconfig.json
    ├── index.ts
    ├── node_modules/                # disposable local fallback
    └── caudex-workout-engine-0.1.0.tgz

### Exact public-path evidence

    Zig:
    error: bad HTTP response code: '404 Not Found'

    C release:
    HTTP/2 404 for https://github.com/caudex-workout/engine/releases/tag/v0.1.0

    npm:
    npm error code E404
    npm error 404  '@caudex-workout/engine@*' is not in this registry.

Public links checked:

- https://github.com/caudex-workout/engine
- https://github.com/caudex-workout/engine/releases/tag/v0.1.0
- https://www.npmjs.com/package/@caudex-workout/engine

The temporary projects should be retained for follow-up debugging. If they are
eventually removed, the source needed to reproduce the successful local flows
is preserved in this report; disposable dependency directories and compiler
output should not be copied into the Caudex repository.

### Exact adoption command transcript

The following is the non-inspection command transcript. The external commands
are listed first; local-build commands are explicitly labeled as fallback
commands and were not used to reinterpret the external result.

Zig external:

    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/zig-clean/src
    zig init
    zig fetch --save https://github.com/caudex-workout/engine/archive/refs/tags/v0.1.0.tar.gz
    zig fetch --save https://github.com/caudex-workout/engine/archive/refs/tags/v0.1.0.tar.gz

Zig local fallback:

    zig build package-zig
    cp -R /Users/julian/Documents/GitHub/caudex/zig-out/zig-packages/core /tmp/caudex-external-dx-audit-XGBcfs/zig-clean/caudex-core
    zig build
    zig build
    zig build run
    zig build run

C external:

    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/c-clean/src
    curl -L -I https://github.com/caudex-workout/engine/releases/tag/v0.1.0
    git ls-remote --tags https://github.com/caudex-workout/engine.git refs/tags/v0.1.0

C local fallback:

    zig build package-c
    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/c-clean/caudex/include /tmp/caudex-external-dx-audit-XGBcfs/c-clean/caudex/lib && cp /Users/julian/Documents/GitHub/caudex/zig-out/c-release-host/aarch64-macos/include/caudex.h /tmp/caudex-external-dx-audit-XGBcfs/c-clean/caudex/include/caudex.h && cp /Users/julian/Documents/GitHub/caudex/zig-out/c-release-host/aarch64-macos/lib/libcaudex.a /tmp/caudex-external-dx-audit-XGBcfs/c-clean/caudex/lib/libcaudex.a
    cc -std=c11 -Icaudex/include main.c caudex/lib/libcaudex.a -o caudex-c
    zig cc -std=c11 -Icaudex/include main.c caudex/lib/libcaudex.a -o caudex-c-zigcc
    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/c-clean/zig-cache && ZIG_GLOBAL_CACHE_DIR=/tmp/caudex-external-dx-audit-XGBcfs/c-clean/zig-cache zig cc -std=c11 -Icaudex/include main.c caudex/lib/libcaudex.a -o caudex-c-zigcc
    ./caudex-c-zigcc
    cp /Users/julian/Documents/GitHub/caudex/zig-out/c-release-host/aarch64-macos/lib/libcaudex.dylib caudex/lib/libcaudex.dylib && cc -std=c11 -Icaudex/include main.c -Lcaudex/lib -lcaudex -o caudex-c-shared
    ./caudex-c-shared

TypeScript external:

    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/node-clean
    npm init -y
    npm install @caudex-workout/engine
    npm search caudex-workout --json

TypeScript local fallback:

    zig build package-npm
    npm pack --ignore-scripts --pack-destination /tmp/caudex-external-dx-audit-XGBcfs/node-clean packages/npm/workout-engine
    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/node-clean/npm-cache && npm_config_cache=/tmp/caudex-external-dx-audit-XGBcfs/node-clean/npm-cache npm pack --ignore-scripts --pack-destination /tmp/caudex-external-dx-audit-XGBcfs/node-clean packages/npm/workout-engine
    npm_config_cache=/tmp/caudex-external-dx-audit-XGBcfs/node-clean/npm-cache npm install ./caudex-workout-engine-0.1.0.tgz
    npm_config_cache=/tmp/caudex-external-dx-audit-XGBcfs/node-clean/npm-cache npm install --save-dev typescript@5.9.2
    mkdir -p /tmp/caudex-external-dx-audit-XGBcfs/node-clean/node_modules && cp -R /Users/julian/Documents/GitHub/caudex/packages/npm/workout-engine/node_modules/typescript /tmp/caudex-external-dx-audit-XGBcfs/node-clean/node_modules/typescript
    node_modules/typescript/bin/tsc --project tsconfig.json
    node_modules/typescript/bin/tsc --project tsconfig.json
    node dist/index.js
    node -e 'require("@caudex-workout/engine")'

### Source files written in the temporary projects

- zig-clean/src/main.zig and its consumer build.zig/build.zig.zon
- c-clean/main.c and c-clean/request.json
- node-clean/index.ts, node-clean/tsconfig.json, and the edited
  node-clean/package.json

These files, including failed-attempt state, remain under the temporary audit
root for debugging.

## Post-audit remediation status

The black-box evidence above is preserved as observed; the following changes
were made only after those clean-room exercises completed:

- DX-004: C release builds now embed compiler runtime support in static
  archives, and the host release test compiles and runs both static and shared
  artifacts with the ordinary `CC` compiler when available.
- DX-005: macOS shared artifacts now use the relocatable
  `@rpath/libcaudex.dylib` install name.
- DX-006 and DX-008: the Zig integrator guide has a complete typed
  recommendation and uses the actual repository URL, while clearly marking
  local package staging as a maintainer/test path.
- DX-007 and DX-014: C consumer documentation now distinguishes local staging,
  target selection, static/shared linking, rpaths, and caller-owned buffers.
- DX-009: the Node quickstart and root README are self-contained; the packed
  package README no longer uses a repository-relative documentation link and
  states the ESM-only setup.
- DX-010: typed Zig recommendation now returns `error.CatalogLimitReached` for
  the documented one-exercise bound; the C ABI deliberately preserves its
  stable `invalid_request` status.
- DX-012: the publishable Zig manifests are aligned to the 0.1.0 contract line,
  and release/repository validation now checks all of them.

DX-001 through DX-003 remain intentionally deferred because this task was
explicitly not authorized to create a public tag, publish npm, or publish a
GitHub release/C download. The documentation now labels those artifacts as
staged and local-only instead of presenting the unavailable URLs as current
consumer installation paths. DX-013 remains an intentional ESM-only package
limitation with an explicit `require()` warning rather than a compatibility
wrapper.
