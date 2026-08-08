import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const write = process.argv.includes("--write");
const snapshotPath = path.join(root, "docs/contracts/public-surface-v0.json");

function read(relative) {
  return fs.readFileSync(path.join(root, relative), "utf8");
}

function files(directory, suffix) {
  const result = [];
  function visit(current) {
    for (const entry of fs.readdirSync(current, {withFileTypes: true})) {
      const target = path.join(current, entry.name);
      if (entry.isDirectory()) visit(target);
      else if (entry.name.endsWith(suffix)) result.push(path.relative(root, target));
    }
  }
  visit(path.join(root, directory));
  return result.sort();
}

const zon = read("build.zig.zon");
const version = zon.match(/\.version\s*=\s*"([^"]+)"/)?.[1];
const rootZig = read("src/root.zig");
const header = read("include/caudex.h");
const commands = read("apps/caudex-cli/src/commands.zig");
const packageJson = JSON.parse(read("packages/npm/workout-engine/package.json"));
const docsCodes = read("docs/contracts/issues-and-explanations.md");
const methodology = read("src/discovery.zig");

const snapshot = {
  format: "caudex.public-surface.v0",
  packageVersion: version,
  zig: {
    module: "caudex",
    exports: [...rootZig.matchAll(/pub const ([A-Za-z0-9_]+)\s*=\s*@import/g)].map((match) => match[1]).sort(),
  },
  cAbi: {
    version: header.match(/CAUDEX_ABI_VERSION\s+(\d+)/)?.[1],
    constants: [...header.matchAll(/^#define\s+(CAUDEX_[A-Z0-9_]+)\s+([^\s/]+)/gm)].map((match) => `${match[1]}=${match[2]}`).filter((value) => !value.startsWith("CAUDEX_H=")).sort(),
    statusValues: [...header.matchAll(/^\s*(CAUDEX_STATUS_[A-Z0-9_]+)\s*=\s*([^,\n]+)/gm)].map((match) => `${match[1]}=${match[2].trim()}`).sort(),
    symbols: [...header.matchAll(/^\s*(?:uint32_t|caudex_status|void)\s+(caudex_[a-z0-9_]+)\s*\(/gm)].map((match) => match[1]).sort(),
  },
  npm: {name: packageJson.name, version: packageJson.version, exports: Object.keys(packageJson.exports).sort()},
  cli: [...commands.matchAll(/\.name\s*=\s*"([^"]+)"/g)].map((match) => match[1]).sort(),
  schemas: files("schemas", ".schema.json"),
  migrations: files("adapters/sqlite/migrations", ".sql"),
  methodologyIds: [...files("src", ".zig").flatMap((file) => [...read(file).matchAll(/pub const methodology_id\s*=\s*"([^"]+)"/g)].map((match) => match[1]))].sort(),
  issueAndExplanationCodes: [...docsCodes.matchAll(/`([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)`/g)].map((match) => match[1]).filter((value, index, values) => values.indexOf(value) === index).sort(),
};

const rendered = `${JSON.stringify(snapshot, null, 2)}\n`;
if (write) {
  fs.writeFileSync(snapshotPath, rendered);
  console.log(`wrote ${path.relative(root, snapshotPath)}`);
} else {
  const existing = fs.existsSync(snapshotPath) ? fs.readFileSync(snapshotPath, "utf8") : "";
  if (existing !== rendered) {
    console.error(`public contract snapshot is stale; run node tools/repo/public-contract-snapshot.mjs --write`);
    process.exit(1);
  }
  console.log("public contract snapshot is current");
}
