import { mkdir, mkdtemp, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const temporary = await mkdtemp(join(tmpdir(), "caudex-exercise-catalog-clean-"));
const pack = join(temporary, "pack");
const project = join(temporary, "project");
try {
  await mkdir(pack);
  await mkdir(project);
  run("npm", ["pack", "--json", "--ignore-scripts", "--pack-destination", pack, resolve("packages/exercise-catalog")]);
  const [tarball] = await readdir(pack);
  await writeFile(join(project, "package.json"), JSON.stringify({ private: true, type: "module" }));
  run("npm", ["install", "--ignore-scripts", "--no-audit", "--no-fund", join(pack, tarball)], project);
  await writeFile(join(project, "smoke.mjs"), `
import { readFile } from "node:fs/promises";
import { catalog, project, search } from "@caudex-workout/exercise-catalog";
import asset from "@caudex-workout/exercise-catalog/catalog.json" with { type: "json" };
import manifest from "@caudex-workout/exercise-catalog/source-manifest.json" with { type: "json" };
const [record] = search({ text: "air bike", limit: 1 });
if (!record || project(record).id !== record.id || asset.fingerprint !== catalog.fingerprint || catalog.mediaIncluded) throw new Error("clean catalog package failed");
if (manifest.license !== "Unlicense" || manifest.normalizedOutputFingerprint !== catalog.fingerprint) throw new Error("catalog source manifest mismatch");
const entry = import.meta.resolve("@caudex-workout/exercise-catalog");
const notice = await readFile(new URL("../NOTICE", entry), "utf8");
if (!notice.includes("Unlicense") || !notice.includes("No upstream images")) throw new Error("catalog third-party notice missing");
const upstreamLicense = await readFile(new URL("../THIRD_PARTY_LICENSES/free-exercise-db-UNLICENSE.md", entry), "utf8");
if (!upstreamLicense.includes("free and unencumbered software released into the public domain")) throw new Error("upstream Unlicense text missing");
`);
  run(process.execPath, ["smoke.mjs"], project);
  await writeFile(join(project, "smoke.ts"), `
import { search, type ExerciseCatalogRecord } from "@caudex-workout/exercise-catalog";
const result: ExerciseCatalogRecord[] = search({ category: "strength", limit: 2 });
void result;
`);
  await writeFile(join(project, "tsconfig.json"), JSON.stringify({ compilerOptions: { strict: true, noEmit: true, target: "ES2022", module: "NodeNext", moduleResolution: "NodeNext" }, files: ["smoke.ts"] }));
  run(process.execPath, [resolve("packages/npm/workout-engine/node_modules/typescript/bin/tsc"), "--project", "tsconfig.json"], project);
  console.log("caudex clean exercise catalog package passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function run(command, args, cwd = process.cwd()) {
  const result = spawnSync(command, args, { cwd, encoding: "utf8", stdio: "pipe" });
  if (result.status !== 0) throw new Error(`${command} ${args.join(" ")} failed\n${result.stdout}\n${result.stderr}`);
}
