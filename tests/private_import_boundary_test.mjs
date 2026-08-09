import { spawnSync } from "node:child_process";
import { basename } from "node:path";

const probe = process.argv[2];
const contract = "Zig private-module boundary";
if (!probe) throw new Error(`${contract}: expected a generated probe path`);

const result = spawnSync("zig", ["build-exe", "-fno-emit-bin", probe], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
  timeout: 30_000,
});
if (result.error) {
  throw new Error(`${contract}: could not launch Zig for ${basename(probe)}: ${result.error.message}`);
}
if (result.signal) {
  throw new Error(`${contract}: Zig terminated with ${result.signal} while checking ${basename(probe)}`);
}
if (result.status === 0) {
  throw new Error(`${contract}: private import unexpectedly compiled successfully`);
}

const diagnostics = `${result.stdout}${result.stderr}`;
if (!/no module named ['\"]?caudex_private_root['\"]? available/.test(diagnostics)) {
  throw new Error(
    `${contract}: expected the external probe to be rejected because ` +
      "caudex_private_root is unavailable\n\n" +
      `actual diagnostic:\n${diagnostics}`,
  );
}
console.log(`${contract}: expected rejection occurred`);
