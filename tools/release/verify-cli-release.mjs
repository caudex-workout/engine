#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { archiveEntries, sha256 } from "./archive-utils.mjs";

export async function verifyCliRelease(directory, version, options = {}) {
  const assets = [
    "x86_64-linux-gnu", "aarch64-linux-gnu", "aarch64-macos", "x86_64-windows-gnu",
  ].map((target) => `caudex-workout-cli-${version}-${target}${target.endsWith("windows-gnu") ? ".zip" : ".tar.gz"}`);
  const suppliedChecksums = options.checksums;
  const expected = suppliedChecksums ?? parseChecksums(
    await fs.readFile(path.join(directory, "SHA256SUMS"), "utf8"),
  );
  if (
    (!(suppliedChecksums instanceof Map) && expected.size !== assets.length) ||
    assets.some((name) => !expected.has(name))
  ) {
    throw new Error("SHA256SUMS does not cover exactly the release CLI archives");
  }
  for (const name of assets) {
    const archive = path.join(directory, name);
    if (await sha256(archive) !== expected.get(name)) throw new Error(`checksum mismatch: ${name}`);
    verifyArchive(await archiveEntries(archive), name, version);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const directory = path.resolve(process.argv[2] ?? "");
  const versionIndex = process.argv.indexOf("--version");
  const version = versionIndex >= 0 ? process.argv[versionIndex + 1] : undefined;
  if (!directory || !version) throw new Error("usage: node tools/release/verify-cli-release.mjs DIRECTORY --version VERSION");
  await verifyCliRelease(directory, version);
  console.log("verified CLI release archives, metadata, and SHA256SUMS");
}

function parseChecksums(contents) {
  const checksums = new Map();
  for (const line of contents.split(/\r?\n/).filter(Boolean)) {
    const match = line.match(/^([0-9a-f]{64})\s+\*?([^\s]+)$/i);
    if (!match || path.basename(match[2]) !== match[2]) throw new Error(`unsafe checksum path: ${line}`);
    checksums.set(match[2], match[1]);
  }
  return checksums;
}

function verifyArchive(entries, name, version) {
  const stem = name.replace(/\.tar\.gz$|\.zip$/, "");
  const prefix = `${stem}/`;
  if (entries.some(({ name: entry }) => !entry.startsWith(prefix) || entry.includes("\\") || entry.split("/").includes(".."))) throw new Error(`unsafe archive path in ${name}`);
  const files = new Set(entries.filter(({ name: entry }) => !entry.endsWith("/")).map(({ name: entry }) => entry.slice(prefix.length)));
  const required = new Set(["LICENSE", "NOTICE", "README.md", "build-metadata.json", name.endsWith(".zip") ? "caudex.exe" : "caudex"]);
  if (files.size !== required.size || [...required].some((entry) => !files.has(entry))) throw new Error(`unexpected files in ${name}: ${[...files].sort().join(", ")}`);
  const metadataEntry = entries.find(({ name: entry }) => entry === `${stem}/build-metadata.json`);
  const metadata = JSON.parse(metadataEntry.data.toString("utf8"));
  const target = stem.slice(`caudex-workout-cli-${version}-`.length);
  if (metadata.version !== version || metadata.target !== target || metadata.optimize !== "ReleaseSafe" || metadata.archiveStem !== stem || metadata.platformCodeSigned !== false) throw new Error(`invalid build metadata in ${name}`);
  const sqlite = metadata.sqlite ?? {};
  if (!["version", "linkage", "source"].every((key) => sqlite[key]) || sqlite.checksum?.algorithm !== "sha256" || !/^[0-9a-f]{64}$/i.test(sqlite.checksum?.value ?? "")) throw new Error(`incomplete SQLite metadata in ${name}`);
}
