#!/usr/bin/env node
import fs from "node:fs/promises";
import path from "node:path";
import { writeTarGz } from "./archive-utils.mjs";

const args = parseArgs(process.argv.slice(2));
for (const name of ["version", "kind", "source", "output"]) if (!args[name]) throw new Error(`missing required argument --${name}`);
if (!new Set(["c", "zig"]).has(args.kind)) throw new Error(`unsupported source package kind: ${args.kind}`);

const source = path.resolve(args.source);
const output = path.resolve(args.output);
const entries = (await fs.readdir(source, { withFileTypes: true })).filter((entry) => entry.isDirectory()).sort((a, b) => a.name.localeCompare(b.name));
if (!entries.length) throw new Error(`no release source directories were found: ${source}`);
for (const entry of entries) {
  const stem = `caudex-${args.kind}-${args.version}-${entry.name}`;
  await writeTarGz(path.join(source, entry.name), path.join(output, `${stem}.tar.gz`), stem);
}

function parseArgs(values) {
  const parsed = {};
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index];
    if (!value.startsWith("--") || index + 1 >= values.length || values[index + 1].startsWith("--")) throw new Error(`invalid argument: ${value}`);
    parsed[value.slice(2)] = values[++index];
  }
  return parsed;
}
