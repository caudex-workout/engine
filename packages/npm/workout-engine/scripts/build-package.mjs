import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { stripTypeScriptTypes } from "node:module";

const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const repositoryRoot = resolve(packageRoot, "../../..");
const wasmSource = resolve(
  process.argv[2] ?? resolve(repositoryRoot, "zig-out/bin/caudex.wasm"),
);

await Promise.all(
  ["dist", "wasm", "schemas", "fixtures"].map((directory) =>
    rm(resolve(packageRoot, directory), { recursive: true, force: true }),
  ),
);
await Promise.all([
  mkdir(resolve(packageRoot, "dist/methodologies"), { recursive: true }),
  mkdir(resolve(packageRoot, "wasm"), { recursive: true }),
]);

for (const name of ["index", "active-workout", "application", "canonical", "measurements", "methodologies", "programs", "runtime", "testing", "wasm-runtime"]) {
  const source = await readFile(resolve(packageRoot, `src/${name}.ts`), "utf8");
  const javascript = stripTypeScriptTypes(source, {
    mode: "strip",
    sourceMap: false,
  })
    .replaceAll("./methodologies.ts", "./methodologies.js")
    .replaceAll("./application.ts", "./application.js")
    .replaceAll("./active-workout.ts", "./active-workout.js")
    .replaceAll("./wasm-runtime.ts", "./wasm-runtime.js")
    .replaceAll("./measurements.ts", "./measurements.js")
    .replaceAll("./programs.ts", "./programs.js")
    .replaceAll("./index.ts", "./index.js");
  await writeFile(resolve(packageRoot, `dist/${name}.js`), javascript);
}
await cp(
  resolve(packageRoot, "types/canonical.d.ts"),
  resolve(packageRoot, "dist/canonical.d.ts"),
);
await cp(
  resolve(packageRoot, "types/measurements.d.ts"),
  resolve(packageRoot, "dist/measurements.d.ts"),
);
await cp(
  resolve(packageRoot, "types/runtime.d.ts"),
  resolve(packageRoot, "dist/runtime.d.ts"),
);
await cp(
  resolve(packageRoot, "types/programs.d.ts"),
  resolve(packageRoot, "dist/programs.d.ts"),
);
await cp(
  resolve(packageRoot, "types/index.d.ts"),
  resolve(packageRoot, "dist/index.d.ts"),
);
await cp(
  resolve(packageRoot, "types/methodologies.d.ts"),
  resolve(packageRoot, "dist/methodologies.d.ts"),
);
await cp(
  resolve(packageRoot, "types/testing.d.ts"),
  resolve(packageRoot, "dist/testing.d.ts"),
);
await writeFile(
  resolve(packageRoot, "dist/methodologies/index.js"),
  'export * from "../methodologies.js";\n',
);
await writeFile(
  resolve(packageRoot, "dist/methodologies/index.d.ts"),
  'export * from "../methodologies.js";\n',
);
await cp(wasmSource, resolve(packageRoot, "wasm/caudex.wasm"));
await cp(resolve(repositoryRoot, "schemas"), resolve(packageRoot, "schemas"), {
  recursive: true,
});
await cp(resolve(repositoryRoot, "fixtures/requests"), resolve(
  packageRoot,
  "fixtures/requests",
), {
  recursive: true,
});
await cp(resolve(repositoryRoot, "fixtures/results"), resolve(
  packageRoot,
  "fixtures/results",
), {
  recursive: true,
});
await cp(resolve(repositoryRoot, "LICENSE"), resolve(packageRoot, "LICENSE"));
