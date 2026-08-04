import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const commit = process.argv[2];
if (!/^[0-9a-f]{40}$/.test(commit ?? "")) {
  throw new Error("usage: update.mjs <exact 40-character upstream commit SHA>");
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const base = `https://raw.githubusercontent.com/yuhonas/free-exercise-db/${commit}`;
const files = [
  ["dist/exercises.json", "catalog/upstream/exercises.json"],
  ["schema.json", "catalog/upstream/schema.json"],
  ["LICENSE.md", "catalog/upstream/LICENSE.md"],
];
const downloaded = new Map();
for (const [remote, local] of files) {
  const response = await fetch(`${base}/${remote}`);
  if (!response.ok) throw new Error(`upstream fetch failed for ${remote}: HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  downloaded.set(local, bytes);
}
const manifestPath = resolve(root, "catalog/source-manifest.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
manifest.upstreamCommit = commit;
manifest.importDate = new Date().toISOString().slice(0, 10);
manifest.upstreamDataSha256 = sha256(downloaded.get("catalog/upstream/exercises.json"));
manifest.upstreamSchemaSha256 = sha256(downloaded.get("catalog/upstream/schema.json"));
for (const [local, bytes] of downloaded) await writeFile(resolve(root, local), bytes);
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
const generated = spawnSync(process.execPath, [resolve(root, "catalog/tools/generate.mjs")], { cwd: root, stdio: "inherit" });
if (generated.status !== 0) process.exit(generated.status ?? 1);

function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
