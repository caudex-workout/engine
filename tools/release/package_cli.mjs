#!/usr/bin/env node
import fs from "node:fs/promises";
import { chmodSync, existsSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { archiveEntries, sha256, writeTarGz, writeZip } from "./archive-utils.mjs";

const args = parseArgs(process.argv.slice(2));
const required = ["version", "target", "archive", "binary", "output", "sqlite-version", "sqlite-linkage", "sqlite-source"];
for (const name of required) if (!args[name]) throw new Error(`missing required argument --${name}`);
if (!["tar.gz", "zip"].includes(args.archive)) throw new Error(`unsupported archive format: ${args.archive}`);

const repository = path.resolve(import.meta.dirname, "../..");
const binary = path.resolve(args.binary);
const output = path.resolve(args.output);
const stem = path.basename(output).replace(/\.tar\.gz$|\.zip$/, "");
const windows = args.target.endsWith("windows-gnu");
const executableName = windows ? "caudex.exe" : "caudex";
const sqliteFile = args["sqlite-library"] ?? args["sqlite-dll"];
if (!sqliteFile || !existsSync(path.resolve(sqliteFile))) throw new Error("a SQLite library or DLL is required to record a checksum");

const temporary = await fs.mkdtemp(path.join(os.tmpdir(), "caudex-cli-package-"));
try {
  const stage = path.join(temporary, stem);
  await fs.mkdir(stage, { recursive: true });
  await fs.copyFile(binary, path.join(stage, executableName));
  await fs.copyFile(path.join(repository, "LICENSE"), path.join(stage, "LICENSE"));
  await fs.copyFile(path.join(repository, "NOTICE"), path.join(stage, "NOTICE"));
  await fs.copyFile(path.join(repository, "apps/caudex-cli/README.md"), path.join(stage, "README.md"));
  if (args["sqlite-dll"]) await fs.copyFile(path.resolve(args["sqlite-dll"]), path.join(stage, "sqlite3.dll"));

  const metadata = {
    schemaVersion: 1,
    version: args.version,
    target: args.target,
    optimize: "ReleaseSafe",
    archiveStem: stem,
    platformCodeSigned: false,
    sqlite: {
      version: args["sqlite-version"],
      linkage: args["sqlite-linkage"],
      source: args["sqlite-source"],
      checksum: { algorithm: "sha256", value: args["sqlite-checksum"] ?? await sha256(path.resolve(sqliteFile)) },
    },
  };
  await fs.writeFile(path.join(stage, "build-metadata.json"), `${JSON.stringify(metadata, null, 2)}\n`);

  if (args.archive === "zip") await writeZip(stage, output, stem);
  else await writeTarGz(stage, output, stem);
  verifyArchive(await archiveEntries(output), stem, windows);
  smoke(stage, args.target, args.version);
} finally {
  await fs.rm(temporary, { recursive: true, force: true });
}

console.log(`packaged and smoke-tested ${output}`);

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--")) throw new Error(`unexpected argument: ${value}`);
    const key = value.slice(2);
    if (index + 1 >= values.length || values[index + 1].startsWith("--")) throw new Error(`missing value for --${key}`);
    parsed[key] = values[++index];
  }
  return parsed;
}

function verifyArchive(entries, stem, windows) {
  const prefix = `${stem}/`;
  if (entries.some(({ name }) => !name.startsWith(prefix) || name.includes("\\") || name.split("/").includes(".."))) {
    throw new Error(`unsafe archive path in ${stem}`);
  }
  const files = new Set(entries.filter(({ name }) => !name.endsWith("/")).map(({ name }) => name.slice(prefix.length)));
  const required = new Set(["LICENSE", "NOTICE", "README.md", "build-metadata.json", windows ? "caudex.exe" : "caudex"]);
  if (windows) required.add("sqlite3.dll");
  if (files.size !== required.size || [...required].some((name) => !files.has(name))) {
    throw new Error(`unexpected files in ${stem}: ${[...files].sort().join(", ")}`);
  }
  const metadata = JSON.parse(readArchiveEntryFromEntries(entries, `${stem}/build-metadata.json`));
  if (metadata.archiveStem !== stem || metadata.platformCodeSigned !== false) throw new Error(`invalid archive metadata in ${stem}`);
}

function readArchiveEntryFromEntries(entries, wanted) {
  const entry = entries.find(({ name }) => name === wanted);
  if (!entry) throw new Error(`archive entry not found: ${wanted}`);
  return entry.data.toString("utf8");
}

function smoke(root, target, version) {
  const executable = path.join(root, target.endsWith("windows-gnu") ? "caudex.exe" : "caudex");
  if (target.endsWith("windows-gnu") && process.platform !== "win32") {
    chmodSync(executable, 0o755);
  }
  if (target.endsWith("windows-gnu") && !existsSync(path.join(root, "sqlite3.dll"))) throw new Error("Windows archive is missing sqlite3.dll");
  const environment = { ...process.env };
  if (target.endsWith("windows-gnu")) environment.PATH = root;
  const versionOutput = run(executable, ["version"], environment);
  if (!versionOutput.startsWith(`caudex ${version}\n`)) throw new Error(`unexpected CLI version output: ${versionOutput}`);
  const help = run(executable, ["--help"], environment);
  if (!help.includes("database backup") || !help.includes("history last")) throw new Error("extracted executable returned incomplete help");
  const database = path.join(root, "smoke.sqlite");
  const check = run(executable, ["--database", database, "--format", "json", "database", "check"], environment);
  if (!check.includes('"integrity":"ok"')) throw new Error(`SQLite smoke check failed: ${check}`);
  const started = run(executable, ["--database", database, "--format", "json", "workout", "start", "--command-id", "release-smoke-start", "--workout", "release-smoke-workout", "--started-at", "2026-01-01T00:00:00Z", "--occurred-at", "2026-01-01T00:00:00Z"], environment);
  if (!started.includes('"workoutId":"release-smoke-workout"')) throw new Error(`workout smoke start failed: ${started}`);
  const shown = run(executable, ["--database", database, "--format", "json", "workout", "show", "--workout", "release-smoke-workout"], environment);
  if (!shown.includes('"workoutId":"release-smoke-workout"')) throw new Error(`workout smoke read failed: ${shown}`);
}

function run(command, arguments_, environment) {
  const result = spawnSync(command, arguments_, { cwd: path.dirname(command), env: environment, encoding: "utf8" });
  if (result.status !== 0) throw new Error(`command failed (${result.status}): ${command} ${arguments_.join(" ")}\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
  return result.stdout;
}
