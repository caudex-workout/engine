import { cp, mkdir, mkdtemp, readFile, rm } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const root = resolve(".");
const temporary = await mkdtemp(join(tmpdir(), "caudex-zig-consumer-"));
const packaged = join(temporary, "caudex");
const cache = join(temporary, "cache");
const globalCache = join(temporary, "global-cache");

try {
  await mkdir(packaged);
  const manifest = await readFile(join(root, "build.zig.zon"), "utf8");
  const paths = [...manifest.matchAll(/^        "([^"]+)",$/gm)]
    .map((match) => match[1]);
  if (
    !paths.includes("src") ||
    !paths.includes("adapters/persistence.zig") ||
    !paths.includes("tracking") ||
    !paths.includes("include") ||
    !paths.includes("examples/zig") ||
    !paths.includes("LICENSE") ||
    !paths.includes("NOTICE")
  ) {
    throw new Error("Zig package paths omit required source or release files");
  }
  for (const path of paths) {
    await cp(join(root, path), join(packaged, path), { recursive: true });
  }

  runZigBuild(packaged, ["build"], cache, globalCache);

  const consumer = join(packaged, "examples/zig/consumer");
  const result = runZigBuild(
    consumer,
    ["build", "run"],
    cache,
    globalCache,
  );
  if (!result.stderr.includes("vendor.simple-progression registered")) {
    throw new Error(`unexpected Zig consumer output: ${result.stderr}`);
  }
  if (!result.stderr.includes("persistence contract v1")) {
    throw new Error(`persistence package was not imported: ${result.stderr}`);
  }
  if (!result.stderr.includes("tracking contract v1")) {
    throw new Error(`tracking package was not imported: ${result.stderr}`);
  }
  console.log("caudex clean Zig package consumer passed");
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function runZigBuild(cwd, args, cacheDirectory, globalCacheDirectory) {
  const result = spawnSync(
    "zig",
    [
      ...args,
      "--cache-dir",
      cacheDirectory,
      "--global-cache-dir",
      globalCacheDirectory,
    ],
    {
      cwd,
      encoding: "utf8",
      stdio: "pipe",
      timeout: 30_000,
    },
  );
  if (result.status !== 0) {
    throw new Error(
      `clean Zig build failed (${result.status})\n${result.stdout}${result.stderr}`,
    );
  }
  return result;
}
