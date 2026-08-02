import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const workflow = await readFile(
  resolve(".github/workflows/cli-release.yml"),
  "utf8",
);
const requiredTargets = [
  "x86_64-linux-gnu",
  "aarch64-linux-gnu",
  "x86_64-macos",
  "aarch64-macos",
  "x86_64-windows-gnu",
];
for (const target of requiredTargets) {
  if (!workflow.includes(target)) throw new Error(`release matrix omits ${target}`);
}
for (const phrase of [
  "ReleaseSafe",
  "package_cli.py",
  "verify_cli_release.py",
  "SHA256SUMS",
  "actions/attest-build-provenance@v3",
  "--draft",
  "gh release edit v0.1.0 --draft=false",
  "test-tui-lifecycle",
  "sqlite3.dll",
]) {
  if (!workflow.includes(phrase)) throw new Error(`release workflow is missing ${phrase}`);
}
if (workflow.includes("universal") || workflow.includes("musl") || workflow.includes("windows-arm64")) {
  throw new Error("release workflow contains an out-of-scope target");
}
for (const script of [
  "tools/release/package_cli.py",
  "tools/release/verify_cli_release.py",
]) {
  const source = await readFile(resolve(script), "utf8");
  if (!source.includes("0.1.0")) throw new Error(`${script} is not pinned to 0.1.0`);
}
console.log("caudex CLI release workflow coverage passed");
