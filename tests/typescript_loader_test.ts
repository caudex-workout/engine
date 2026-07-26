import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  CaudexInitializationError,
  CaudexRuntimeError,
  createCaudex,
  type RecommendationRequest,
} from "../packages/npm/workout-engine/src/index.ts";

const [wasmPath, fixturePath] = process.argv.slice(2);
if (!wasmPath || !fixturePath) throw new Error("missing test artifact paths");

const wasm = await readFile(wasmPath);
const request = JSON.parse(
  await readFile(fixturePath, "utf8"),
) as RecommendationRequest;

const caudex = await createCaudex({ wasm });
const result = caudex.recommendSession(request);
if (!result.ok || !result.recommendation) {
  throw new Error("ordinary object request did not produce a recommendation");
}
if (
  result.metadata.resultFingerprint !==
  "83481330a812bb41384d958c104038d230bf93ceee163fd47b7c62a41361fd6f"
) {
  throw new Error("TypeScript facade fingerprint differs from core fixtures");
}
if ("memory" in caudex || "alloc" in caudex || "execute" in caudex) {
  throw new Error("the public facade exposes raw WebAssembly ownership");
}

const invalid = caudex.recommendSession({
  ...request,
  schemaVersion: 2,
} as unknown as RecommendationRequest);
if (invalid.ok || invalid.issues?.[0]?.code !== "protocol.unsupported_version") {
  throw new Error("validation failure was not returned as an issue value");
}
caudex.dispose();
caudex.dispose();
try {
  caudex.recommendSession(request);
  throw new Error("disposed runtime remained callable");
} catch (error) {
  if (!(error instanceof CaudexRuntimeError)) throw error;
}

const dataUrl = `data:application/wasm;base64,${wasm.toString("base64")}`;
const browserStyle = await createCaudex({ wasmUrl: dataUrl });
const browserResult = browserStyle.recommendSession(request);
browserStyle.dispose();
if (
  browserResult.metadata.resultFingerprint !== result.metadata.resultFingerprint
) {
  throw new Error("fetch loader and byte loader produced different results");
}

const nodeStyle = await createCaudex({ wasmUrl: pathToFileURL(wasmPath) });
const nodeResult = nodeStyle.recommendSession(request);
nodeStyle.dispose();
if (nodeResult.metadata.resultFingerprint !== result.metadata.resultFingerprint) {
  throw new Error("Node file loader and byte loader produced different results");
}

try {
  await createCaudex({ wasm: new Uint8Array([0, 1, 2, 3]) });
  throw new Error("invalid WASM unexpectedly initialized");
} catch (error) {
  if (
    !(error instanceof CaudexInitializationError) ||
    error.code !== "wasm_compile_failed"
  ) {
    throw error;
  }
}

console.log(
  `caudex TypeScript facade fingerprint: ${result.metadata.resultFingerprint}`,
);
