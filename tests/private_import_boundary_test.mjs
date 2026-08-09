import { spawnSync } from "node:child_process";
import { basename } from "node:path";

const probe = process.argv[2];
const contract = "Zig private-module boundary";
if (!probe) throw new Error(`${contract}: expected a generated probe path`);
const command = `zig build-exe -fno-emit-bin ${JSON.stringify(probe)}`;

const result = spawnSync("zig", ["build-exe", "-fno-emit-bin", probe], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
  timeout: 30_000,
});
if (result.error) {
  throw new Error(
    `${contract}: could not launch Zig for ${basename(probe)}\n` +
      `command:\n  ${command}\n` +
      `launcher error:\n  ${result.error.message}`,
  );
}
if (result.signal) {
  throw new Error(
    `${contract}: Zig terminated unexpectedly while checking ${basename(probe)}\n` +
      `command:\n  ${command}\n` +
      `signal:\n  ${result.signal}\n` +
      `stdout:\n${result.stdout || "  <empty>"}\n` +
      `stderr:\n${result.stderr || "  <empty>"}`,
  );
}
if (result.status === 0) {
  throw new Error(`${contract}: private import unexpectedly compiled successfully\ncommand:\n  ${command}`);
}

const diagnostics = `${result.stdout}${result.stderr}`;
if (!/no module named ['\"]?caudex_private_root['\"]? available/.test(diagnostics)) {
  throw new Error(
    `${contract}: probe rejected for an unexpected reason\n` +
      `command:\n  ${command}\n` +
      `expected diagnostic:\n  no module named 'caudex_private_root' available\n` +
      `actual stdout:\n${result.stdout || "  <empty>"}\n` +
      `actual stderr:\n${result.stderr || "  <empty>"}`,
  );
}
console.log(`${contract}: expected rejection occurred`);
