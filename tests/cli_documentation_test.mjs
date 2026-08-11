import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const cli = await readFile(resolve("apps/caudex-cli/README.md"), "utf8");
const integrator = await readFile(
  resolve("docs/zig-integrator-guide.md"),
  "utf8",
);
const root = await readFile(resolve("README.md"), "utf8");

const requiredCliSections = [
  "## Installation and runtime baseline",
  "## First workout",
  "## Shell scripting, JSON, and exit codes",
  "## Database, backup, and restore",
  "## TUI and accessibility",
  "## Troubleshooting",
];
for (const section of requiredCliSections) {
  if (!cli.includes(section)) {
    throw new Error(`CLI documentation is missing ${section}`);
  }
}
for (const phrase of [
  "GitHub Release",
  "caudex batch FILE",
  "caudex command-reference",
  "database backup",
  "database restore",
  "program advance",
  "nextState",
  "NO_COLOR",
  "130",
]) {
  if (!cli.includes(phrase)) {
    throw new Error(`CLI documentation is missing ${phrase}`);
  }
}

for (const phrase of [
  "third-party Zig application",
  '@import("caudex")',
  '@import("caudex_persistence")',
  "public modules",
  "Do not copy CLI table formatting",
  "zig build test-zig-package",
]) {
  if (!integrator.includes(phrase)) {
    throw new Error(`Zig integrator guide is missing ${phrase}`);
  }
}
if (integrator.includes("@import(\"../")) {
  throw new Error("Zig integrator guide contains a private relative import");
}

for (const link of [
  "apps/caudex-cli/README.md",
  "docs/zig-integrator-guide.md",
]) {
  if (!root.includes(link)) throw new Error(`root README is missing ${link}`);
}

console.log("caudex CLI and Zig integrator documentation passed");
