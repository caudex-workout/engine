import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stripTypeScriptTypes } from "node:module";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../..");
await Promise.all(["dist", "data", "THIRD_PARTY_LICENSES"].map((path) => rm(resolve(packageRoot, path), { recursive: true, force: true })));
await Promise.all([mkdir(resolve(packageRoot, "dist"), { recursive: true }), mkdir(resolve(packageRoot, "data"), { recursive: true }), mkdir(resolve(packageRoot, "THIRD_PARTY_LICENSES"), { recursive: true })]);
const source = await readFile(resolve(packageRoot, "src/index.ts"), "utf8");
const javascript = stripTypeScriptTypes(source, { mode: "strip", sourceMap: false })
  .replace("../../../catalog/generated/catalog.json", "../data/catalog.json");
await writeFile(resolve(packageRoot, "dist/index.js"), javascript);
await cp(resolve(packageRoot, "types/index.d.ts"), resolve(packageRoot, "dist/index.d.ts"));
await cp(resolve(repositoryRoot, "catalog/generated/catalog.json"), resolve(packageRoot, "data/catalog.json"));
await cp(resolve(repositoryRoot, "catalog/source-manifest.json"), resolve(packageRoot, "data/source-manifest.json"));
await cp(resolve(repositoryRoot, "LICENSE"), resolve(packageRoot, "LICENSE"));
await cp(resolve(repositoryRoot, "catalog/THIRD_PARTY_NOTICES.md"), resolve(packageRoot, "NOTICE"));
await cp(resolve(repositoryRoot, "catalog/upstream/LICENSE.md"), resolve(packageRoot, "THIRD_PARTY_LICENSES/free-exercise-db-UNLICENSE.md"));
