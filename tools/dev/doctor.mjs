#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "../..");
const versions = JSON.parse(fs.readFileSync(path.join(root, "tools/support/versions.json"), "utf8"));
const strict = process.argv.slice(2).includes("--strict");
const checks = [];

const zig = run("zig", ["version"]);
checks.push(["Zig", zig === versions.zig, `found ${zig ?? "missing"}; install Zig ${versions.zig}`]);

const node = run("node", ["--version"]);
const nodeMajor = major(node);
const nodeOk = strict ? nodeMajor === Number(versions.node_ci) : nodeMajor !== null && nodeMajor >= Number(versions.node_min);
checks.push(["Node.js", nodeOk, `found ${node ?? "missing"}; use Node ${versions.node_min}+ (CI: ${versions.node_ci})`]);

const sqlite = run("sqlite3", ["--version"]);
checks.push(["SQLite", sqlite !== null, `found ${sqlite?.split(/\s+/)[0] ?? "missing"}; install SQLite ${versions.sqlite}`]);

const compiler = ["cc", "clang", "gcc"].find((candidate) => run(candidate, ["--version"]));
checks.push(["C compiler", compiler !== undefined, "install a C11 compiler and linker"]);

console.log("Caudex development environment");
let failed = false;
for (const [name, ok, guidance] of checks) {
  const status = ok ? "ok" : name === "Node.js" && !strict ? "warning" : "missing/incompatible";
  console.log(`- ${name}: ${status} (${ok ? "ready" : guidance})`);
  if (!ok && (strict || name !== "Node.js")) failed = true;
}
if (failed) {
  console.log("\nAction: install or select the versions above, then rerun ./tools/dev/doctor.");
  process.exitCode = 1;
} else {
  console.log("\nEnvironment is suitable for the available local checks.");
}

function run(command, args) {
  const result = spawnSync(command, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
  return result.status === 0 ? result.stdout.trim() : null;
}

function major(value) {
  const match = value?.match(/(\d+)/);
  return match ? Number(match[1]) : null;
}
