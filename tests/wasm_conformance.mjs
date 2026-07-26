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
  "caudex_wasm_runtime_evaluate",
  "caudex_buffer_free",
  "caudex_wasm_alloc",
  "caudex_wasm_free",
  "caudex_wasm_runtime_create",
  "caudex_wasm_runtime_destroy",
];
for (const name of requiredExports) {
  if (!(name in exports)) throw new Error(`missing WASM export: ${name}`);
}
if (exports.caudex_abi_version() !== 1) {
  throw new Error("unexpected ABI version");
}

const request = new Uint8Array(await readFile(fixturePath));
const runtime = exports.caudex_wasm_runtime_create();
const requestPointer = exports.caudex_wasm_alloc(request.length);
const descriptorPointer = exports.caudex_wasm_alloc(12);
if (!runtime || !requestPointer || !descriptorPointer) {
  throw new Error("WASM allocation or runtime creation failed");
}

const expectedFingerprint =
  "83481330a812bb41384d958c104038d230bf93ceee163fd47b7c62a41361fd6f";

new Uint8Array(exports.memory.buffer, requestPointer, 1)[0] = "{".charCodeAt(0);
if (
  exports.caudex_runtime_execute(
    runtime,
    requestPointer,
    1,
    descriptorPointer,
  ) !== 3
) {
  throw new Error("malformed JSON did not become INVALID_REQUEST");
}
if (
  exports.caudex_runtime_execute(
    0,
    requestPointer,
    request.length,
    descriptorPointer,
  ) !== 1
) {
  throw new Error("null runtime did not become INVALID_ARGUMENT");
}

function execute() {
  new Uint8Array(exports.memory.buffer, requestPointer, request.length).set(request);
  new Uint8Array(exports.memory.buffer, descriptorPointer, 12).fill(0);
  const status = exports.caudex_runtime_execute(
    runtime,
    requestPointer,
    request.length,
    descriptorPointer,
  );
  if (status !== 0) throw new Error(`WASM execution failed with status ${status}`);

  const descriptor = new DataView(exports.memory.buffer, descriptorPointer, 12);
  const resultPointer = descriptor.getUint32(0, true);
  const resultLength = descriptor.getUint32(4, true);
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
  exports.caudex_buffer_free(runtime, descriptorPointer);
  const cleared = new Uint8Array(exports.memory.buffer, descriptorPointer, 12);
  if (cleared.some((byte) => byte !== 0)) {
    throw new Error("result descriptor was not cleared by free");
  }
  return fingerprint;
}

try {
  const first = execute();
  const second = execute();
  if (first !== second || first !== expectedFingerprint) {
    throw new Error(`fingerprint mismatch: ${first} / ${second}`);
  }
  console.log(`caudex WASM conformance fingerprint: ${first}`);
} finally {
  exports.caudex_wasm_free(descriptorPointer, 12);
  exports.caudex_wasm_free(requestPointer, request.length);
  exports.caudex_wasm_runtime_destroy(runtime);
}
