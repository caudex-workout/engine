import { readFile } from "node:fs/promises";

const [wasmPath, fixturePath] = process.argv.slice(2);
if (!wasmPath || !fixturePath) {
  throw new Error("usage: node wasm_conformance.mjs MODULE.wasm REQUEST.json");
}

const wasmBytes = await readFile(wasmPath);
const module = await WebAssembly.compile(wasmBytes);
const imports = WebAssembly.Module.imports(module);
if (imports.length !== 0) {
  throw new Error(`freestanding module unexpectedly imports ${imports.length} values`);
}

const { exports } = await WebAssembly.instantiate(module, {});
const requiredExports = [
  "memory",
  "caudex_abi_version",
  "caudex_runtime_execute",
  "caudex_wasm_alloc",
  "caudex_wasm_free",
  "caudex_wasm_runtime_create",
  "caudex_wasm_runtime_destroy",
];
for (const name of requiredExports) {
  if (!(name in exports)) throw new Error(`missing WASM export: ${name}`);
}
if (exports.caudex_abi_version() !== 2) {
  throw new Error("unexpected ABI version");
}

const request = new Uint8Array(await readFile(fixturePath));
const runtime = exports.caudex_wasm_runtime_create();
const requestPointer = exports.caudex_wasm_alloc(request.length);
const requiredPointer = exports.caudex_wasm_alloc(4);
const maximumPointer = exports.caudex_wasm_alloc(4 * 1024 * 1024 + 1024);
if (maximumPointer === 0) {
  throw new Error("WASM allocation rejected the execution-envelope limit");
}
exports.caudex_wasm_free(maximumPointer, 4 * 1024 * 1024 + 1024);
if (exports.caudex_wasm_alloc(4 * 1024 * 1024 + 1025) !== 0) {
  throw new Error("WASM allocation exceeded the execution-envelope limit");
}
if (!runtime || !requestPointer || !requiredPointer) {
  throw new Error("WASM allocation or runtime creation failed");
}

const expectedFingerprint =
  "acc27989785258bff14df982a222e277e9b51bfed565c363d1f3300277fabe47";

new Uint8Array(exports.memory.buffer, requestPointer, 1)[0] = "{".charCodeAt(0);
if (
  exports.caudex_runtime_execute(
    runtime,
    requestPointer,
    1,
    0,
    0,
    requiredPointer,
  ) !== 3
) {
  throw new Error("malformed JSON did not become INVALID_REQUEST");
}
if (
  exports.caudex_runtime_execute(
    0,
    requestPointer,
    request.length,
    0,
    0,
    requiredPointer,
  ) !== 1
) {
  throw new Error("null runtime did not become INVALID_ARGUMENT");
}

function execute() {
  new Uint8Array(exports.memory.buffer, requestPointer, request.length).set(request);
  new Uint8Array(exports.memory.buffer, requiredPointer, 4).fill(0);
  const sizingStatus = exports.caudex_runtime_execute(
    runtime,
    requestPointer,
    request.length,
    0,
    0,
    requiredPointer,
  );
  if (sizingStatus !== 7) throw new Error(`WASM sizing failed with status ${sizingStatus}`);
  const resultLength = new DataView(exports.memory.buffer).getUint32(requiredPointer, true);
  const resultPointer = exports.caudex_wasm_alloc(resultLength);
  if (!resultPointer) throw new Error("WASM result allocation failed");
  const status = exports.caudex_runtime_execute(runtime, requestPointer, request.length, resultPointer, resultLength, requiredPointer);
  if (status !== 0) throw new Error(`WASM execution failed with status ${status}`);
  const resultBytes = new Uint8Array(
    exports.memory.buffer,
    resultPointer,
    resultLength,
  );
  const result = JSON.parse(new TextDecoder().decode(resultBytes));
  if (result.metadata.methodology.id !== "caudex.double-progression") {
    throw new Error("unexpected resolved methodology");
  }
  const fingerprint = result.metadata.resultFingerprint;
  exports.caudex_wasm_free(resultPointer, resultLength);
  return fingerprint;
}

function executeDocument(document) {
  const bytes = new TextEncoder().encode(JSON.stringify(document));
  const inputPointer = exports.caudex_wasm_alloc(bytes.length);
  if (!inputPointer) throw new Error("WASM planning-request allocation failed");
  try {
    new Uint8Array(exports.memory.buffer, inputPointer, bytes.length).set(bytes);
    new Uint8Array(exports.memory.buffer, requiredPointer, 4).fill(0);
    const sizingStatus = exports.caudex_runtime_execute(
      runtime,
      inputPointer,
      bytes.length,
      0,
      0,
      requiredPointer,
    );
    if (sizingStatus !== 7) throw new Error(`WASM planning sizing failed with status ${sizingStatus}`);
    const resultLength = new DataView(exports.memory.buffer).getUint32(requiredPointer, true);
    const resultPointer = exports.caudex_wasm_alloc(resultLength);
    if (!resultPointer) throw new Error("WASM planning-result allocation failed");
    try {
      const status = exports.caudex_runtime_execute(
        runtime,
        inputPointer,
        bytes.length,
        resultPointer,
        resultLength,
        requiredPointer,
      );
      if (status !== 0) throw new Error(`WASM planning execution failed with status ${status}`);
      return JSON.parse(new TextDecoder().decode(
        new Uint8Array(exports.memory.buffer, resultPointer, resultLength),
      ));
    } finally {
      exports.caudex_wasm_free(resultPointer, resultLength);
    }
  } finally {
    exports.caudex_wasm_free(inputPointer, bytes.length);
  }
}

try {
  const first = execute();
  const second = execute();
  if (first !== second || first !== expectedFingerprint) {
    throw new Error(`fingerprint mismatch: ${first} / ${second}`);
  }
  const planning = executeDocument({
    schemaVersion: 1,
    operation: "validateProgramDefinition",
    payload: {
      schemaVersion: 1,
      definition: {
        schemaVersion: 1,
        id: "program",
        version: "1",
        displayName: "Program",
        strategy: { id: "caudex.fixed-session", configVersion: 1, config: {} },
        configurationFingerprint: "fixture-v1",
        blocks: [{
          id: "block",
          microcycleCount: 1,
          schedule: { rotation: { roleIds: ["day"] } },
          sessionRoles: [{ id: "day", items: [] }],
        }],
      },
    },
  });
  if (!planning.valid || planning.issues.length !== 0) {
    throw new Error("WASM program-definition validation was not deterministic");
  }
  console.log(`caudex WASM conformance fingerprint: ${first}`);
} finally {
  exports.caudex_wasm_free(requiredPointer, 4);
  exports.caudex_wasm_free(requestPointer, request.length);
  exports.caudex_wasm_runtime_destroy(runtime);
}
