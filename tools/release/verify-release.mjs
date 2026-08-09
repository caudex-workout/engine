import fs from "node:fs/promises";
import path from "node:path";
import { releaseAssetManifest } from "./artifact-manifest.mjs";
import { archiveEntries, readArchiveEntry, sha256 } from "./archive-utils.mjs";
import { verifyCliRelease } from "./verify-cli-release.mjs";

const version = process.argv[2] === "--version" ? process.argv[3] : undefined;
const directory = path.resolve(process.argv[4] ?? "release/assets");
if (!version || !directory) throw new Error("usage: node tools/release/verify-release.mjs --version VERSION DIRECTORY");

const expected = await releaseAssetManifest(version);
const expectedNames = new Set(expected.map((asset) => asset.name).filter((name) => !["SHA256SUMS", "release-manifest.json"].includes(name)));
const actualNames = new Set((await fs.readdir(directory)).filter((name) => name !== "SHA256SUMS" && name !== "release-manifest.json"));
if (actualNames.size !== expectedNames.size || [...expectedNames].some((name) => !actualNames.has(name))) {
  throw new Error(`release asset set mismatch:\nexpected: ${[...expectedNames].sort().join("\n")}\nactual: ${[...actualNames].sort().join("\n")}`);
}

for (const asset of expected.filter((entry) => entry.kind === "npm")) {
  const packageJson = JSON.parse((await readArchiveEntry(path.join(directory, asset.name), "package/package.json")).toString("utf8"));
  if (packageJson.version !== version) throw new Error(`npm tarball version mismatch: ${asset.name}`);
}

const cliNames = expected.filter((asset) => asset.kind === "cli").map((asset) => asset.name);
for (const name of cliNames) await verifyArchive(path.join(directory, name), version, "cli");
for (const asset of expected.filter((entry) => entry.kind === "c" || entry.kind === "zig")) {
  await verifyArchive(path.join(directory, asset.name), version, asset.kind);
}

const hashes = {};
for (const name of [...expectedNames].sort()) hashes[name] = await sha256(path.join(directory, name));
await verifyCliRelease(directory, version);
const manifest = {
  schemaVersion: 1,
  version,
  checksumAlgorithm: "sha256",
  assets: expected.map((asset) => ({ ...asset, sha256: asset.name === "SHA256SUMS" || asset.name === "release-manifest.json" ? null : hashes[asset.name] })),
};
await fs.writeFile(path.join(directory, "release-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
const checksumLines = [...expectedNames].sort().map((name) => `${hashes[name]}  ${name}`);
await fs.writeFile(path.join(directory, "SHA256SUMS"), `${checksumLines.join("\n")}\n`);
console.log(`verified ${expectedNames.size} release assets for ${version}`);

async function verifyArchive(archive, version, kind) {
  const entries = (await archiveEntries(archive)).map(({ name }) => name);
  const stem = path.basename(archive).replace(/\.tar\.gz$|\.zip$/, "");
  if (!entries.length || entries.some((entry) => !entry.startsWith(`${stem}/`) || entry.includes("\\") || entry.split("/").includes(".."))) {
    throw new Error(`unsafe or malformed archive paths in ${archive}`);
  }
  if (kind === "cli") {
    const metadata = JSON.parse((await readArchiveEntry(archive, `${stem}/build-metadata.json`)).toString("utf8"));
    if (metadata.version !== version || metadata.archiveStem !== stem || metadata.platformCodeSigned !== false) {
      throw new Error(`CLI metadata mismatch in ${archive}`);
    }
  } else if (kind === "c") {
    const metadata = JSON.parse((await readArchiveEntry(archive, `${stem}/build-metadata.json`)).toString("utf8"));
    if (metadata.packageVersion !== version || metadata.engineVersion !== version) {
      throw new Error(`C metadata mismatch in ${archive}`);
    }
  } else {
    const zon = (await readArchiveEntry(archive, `${stem}/build.zig.zon`)).toString("utf8");
    if (!zon.includes(`.version = "${version}"`)) throw new Error(`Zig package version mismatch in ${archive}`);
  }
}
