import { cp, mkdir, rm } from "node:fs/promises";
import { basename, join, resolve } from "node:path";

const root = resolve(new URL("../..", import.meta.url).pathname);
const output = resolve(process.argv[2] ?? join(root, "zig-out", "zig-packages"));

const packages = {
  core: ["src", "tracking", "workflows", "portable", "fixtures", "adapters/persistence.zig"],
  sqlite: ["adapters/sqlite.zig", "adapters/sqlite"],
  "exercise-catalog": ["catalog/root.zig", "catalog/generated", "catalog/source-manifest.json", "catalog/THIRD_PARTY_NOTICES.md", "catalog/upstream/LICENSE.md"],
  cli: ["apps/caudex-cli"],
};

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });

for (const [name, sourcePaths] of Object.entries(packages)) {
  const destination = join(output, name);
  await mkdir(destination, { recursive: true });
  await cp(join(root, "packages", "zig", name, "build.zig"), join(destination, "build.zig"));
  await cp(join(root, "packages", "zig", name, "build.zig.zon"), join(destination, "build.zig.zon"));
  for (const shared of ["LICENSE", "NOTICE"]) {
    await cp(join(root, shared), join(destination, shared));
  }
  await cp(join(root, name === "cli" ? "apps/caudex-cli/README.md" : "docs/zig-package.md"), join(destination, "README.md"));
  for (const sourcePath of sourcePaths) {
    const destinationPath = sourcePath.includes("/")
      ? join(destination, sourcePath)
      : join(destination, basename(sourcePath));
    await mkdir(join(destinationPath, ".."), { recursive: true });
    await cp(join(root, sourcePath), destinationPath, { recursive: true });
  }
}

console.log(`generated Zig source packages in ${output}`);
