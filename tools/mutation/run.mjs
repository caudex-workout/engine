#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {spawnSync} from "node:child_process";

const root = process.cwd();
const descriptors = JSON.parse(fs.readFileSync(path.join(root, "tests/mutation/mutations.json"), "utf8"));
const equivalents = new Map(Object.entries(JSON.parse(fs.readFileSync(path.join(root, "tests/mutation/equivalents.json"), "utf8"))));
const args = process.argv.slice(2);
const smoke = args.includes("--smoke");
const requested = args.includes("--id") ? args[args.indexOf("--id") + 1] : null;
const selected = descriptors.filter((m, i) => (!smoke || i < 6) && (!requested || m.id === requested));
if (selected.length === 0) throw new Error("No mutation matched the requested selection");

const report = [];
for (const mutation of selected) {
  if (equivalents.has(mutation.id)) {
    report.push({...mutation, status: "equivalent", reason: equivalents.get(mutation.id)});
    continue;
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "caudex-mutant-"));
  try {
    fs.cpSync(path.join(root, "src"), path.join(temp, "src"), {recursive: true});
    const file = path.join(temp, mutation.file.replace(/^src\//, "src/"));
    let source = fs.readFileSync(file, "utf8");
    const occurrences = source.split(mutation.original).length - 1;
    if (occurrences !== 1) {
      report.push({...mutation, status: "invalid", reason: `expected one source match, found ${occurrences}`});
      continue;
    }
    fs.writeFileSync(file, source.replace(mutation.original, mutation.replacement));
    const result = spawnSync("zig", ["test", file], {cwd: temp, encoding: "utf8", timeout: 10000, maxBuffer: 1024 * 1024});
    const detail = `${result.stdout ?? ""}${result.stderr ?? ""}`;
    const compileError = /error: (expected|no field|use of undeclared|redeclaration|type .* cannot|unable to resolve)/.test(detail);
    const status = result.error?.code === "ETIMEDOUT" ? "timeout" : result.status === 0 ? "survived-actionable" : compileError ? "compile-error" : "killed";
    report.push({...mutation, status, detail: detail.slice(-1200)});
  } finally {
    fs.rmSync(temp, {recursive: true, force: true});
  }
}

const counts = Object.fromEntries(["killed", "survived-actionable", "equivalent", "compile-error", "timeout", "invalid"].map((s) => [s, report.filter((m) => m.status === s).length]));
const valid = report.filter((m) => !["equivalent", "invalid", "compile-error", "timeout"].includes(m.status));
const score = valid.length === 0 ? 1 : counts.killed / (counts.killed + counts["survived-actionable"]);
const outputDir = path.join(root, ".zig-cache", "mutation");
fs.mkdirSync(outputDir, {recursive: true});
fs.writeFileSync(path.join(outputDir, "report.json"), JSON.stringify({counts, mutation_score: score, mutations: report}, null, 2) + "\n");
console.log(JSON.stringify({counts, mutation_score: score, report: path.relative(root, path.join(outputDir, "report.json"))}, null, 2));
for (const mutation of report.filter((m) => m.status === "survived-actionable")) console.log(`SURVIVED ${mutation.id}: ${mutation.category}`);
if (report.some((m) => m.status === "survived-actionable") && !smoke && !requested) process.exitCode = 1;
