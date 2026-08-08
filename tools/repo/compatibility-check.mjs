import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const manifest = JSON.parse(fs.readFileSync(path.join(root, "tests/compat/v0.1/manifest.json"), "utf8"));
if (manifest.release !== "0.1.0" || manifest.tag !== "v0.1.0" || manifest.status !== "historical") throw new Error("v0.1 compatibility record metadata is invalid");
for (const relative of manifest.fixtureSources) {
  if (!fs.existsSync(path.join(root, relative))) throw new Error(`compatibility fixture source is missing: ${relative}`);
}
for (const relative of ["docs/contracts/c-abi-v2.md", "docs/contracts/wasm-v2.md", "docs/contracts/canonical-v0.md", "include/caudex.h"]) {
  if (!fs.existsSync(path.join(root, relative))) throw new Error(`compatibility contract is missing: ${relative}`);
}
console.log("v0.1 compatibility record and fixture sources passed");
