import { readFile } from "node:fs/promises";
import path from "node:path";
import { repositoryRoot } from "./validate-release.mjs";

export async function releasePolicy() {
  return JSON.parse(
    await readFile(path.join(repositoryRoot, "tools/release/release-metadata.json"), "utf8"),
  );
}

export async function releaseAssetManifest(version) {
  const policy = await releasePolicy();
  const cli = policy.cliTargets.map((target) => ({
    name: `caudex-workout-cli-${version}-${target}${target.endsWith("windows-gnu") ? ".zip" : ".tar.gz"}`,
    kind: "cli",
    target,
  }));
  const c = policy.cTargets.map((target) => ({
    name: `caudex-c-${version}-${target}.tar.gz`,
    kind: "c",
    target,
  }));
  const zig = ["core", "sqlite", "exercise-catalog", "cli"].map((name) => ({
    name: `caudex-zig-${version}-${name}.tar.gz`,
    kind: "zig",
    target: name,
  }));
  return [
    { name: `caudex-workout-engine-${version}.tgz`, kind: "npm" },
    ...cli,
    ...c,
    ...zig,
    { name: "SHA256SUMS", kind: "checksums" },
    { name: "release-manifest.json", kind: "metadata" },
  ];
}

export async function writeReleaseManifest(directory, version, hashes = {}) {
  const assets = await releaseAssetManifest(version);
  const manifest = {
    schemaVersion: 1,
    version,
    checksumAlgorithm: "sha256",
    assets: assets.map((asset) => ({ ...asset, sha256: hashes[asset.name] ?? null })),
  };
  return manifest;
}

if (process.argv[1]?.endsWith("artifact-manifest.mjs")) {
  const version = process.argv[2];
  if (!version) throw new Error("usage: node tools/release/artifact-manifest.mjs VERSION");
  console.log(JSON.stringify(await writeReleaseManifest(undefined, version), null, 2));
}
