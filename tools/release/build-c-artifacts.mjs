import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { basename, join, resolve } from "node:path";

const matrix = [
  { target: "x86_64-linux-gnu", os: "linux", arch: "x86_64" },
  { target: "aarch64-linux-gnu", os: "linux", arch: "aarch64" },
  { target: "x86_64-macos", os: "macos", arch: "x86_64" },
  { target: "aarch64-macos", os: "macos", arch: "aarch64" },
  { target: "x86_64-windows-gnu", os: "windows", arch: "x86_64" },
  { target: "aarch64-windows-gnu", os: "windows", arch: "aarch64" },
];

const outputRoot = resolve(process.argv[2] ?? "zig-out/c-release");
const hostOnly = process.argv.includes("--host-only");
const linkTest = process.argv.includes("--test");
const selected = hostOnly ? matrix.filter(isHostTarget) : matrix;
if (selected.length !== 1 && hostOnly) {
  throw new Error(`unsupported release host: ${process.platform}/${process.arch}`);
}

await rm(outputRoot, { recursive: true, force: true });
await mkdir(outputRoot, { recursive: true });

const zigVersion = run("zig", ["version"], undefined, true).stdout.trim();
const packageManifest = await readFile(resolve("build.zig.zon"), "utf8");
const packageVersion = packageManifest.match(/\.version = "([^"]+)"/)?.[1];
const engineSource = await readFile(resolve("src/engine.zig"), "utf8");
const engineVersion = engineSource.match(
  /pub const engine_version = "([^"]+)"/,
)?.[1];
const headerSource = await readFile(resolve("include/caudex.h"), "utf8");
const abiVersion = Number(
  headerSource.match(/#define CAUDEX_ABI_VERSION (\d+)u/)?.[1],
);
if (!packageVersion || !engineVersion || !abiVersion) {
  throw new Error("could not resolve package, engine, or ABI version");
}

const report = [];
for (const entry of selected) {
  const directory = join(outputRoot, entry.target);
  const includeDirectory = join(directory, "include");
  const libraryDirectory = join(directory, "lib");
  await mkdir(includeDirectory, { recursive: true });
  await mkdir(libraryDirectory, { recursive: true });
  await cp(resolve("include/caudex.h"), join(includeDirectory, "caudex.h"));
  await cp(resolve("LICENSE"), join(directory, "LICENSE"));
  await cp(resolve("NOTICE"), join(directory, "NOTICE"));

  const names = libraryNames(entry.os);
  const staticPath = join(libraryDirectory, names.static);
  const sharedPath = join(libraryDirectory, names.shared);
  buildLibrary(entry.target, "static", staticPath);
  buildLibrary(
    entry.target,
    "dynamic",
    sharedPath,
    entry.os === "windows" ? join(libraryDirectory, names.import) : undefined,
  );

  const libraryFiles = await readdir(libraryDirectory);
  const libraries = [];
  for (const file of libraryFiles.sort()) {
    const path = join(libraryDirectory, file);
    libraries.push({
      file: `lib/${file}`,
      bytes: (await stat(path)).size,
      sha256: await sha256(path),
    });
  }
  const metadata = {
    packageVersion,
    engineVersion,
    abiVersion,
    zigVersion,
    optimize: "ReleaseSmall",
    target: entry.target,
    architecture: entry.arch,
    operatingSystem: entry.os,
    libraries,
  };
  await writeFile(
    join(directory, "build-metadata.json"),
    `${JSON.stringify(metadata, null, 2)}\n`,
  );
  await writeChecksums(directory);
  await verifyChecksums(directory);
  await testLinks(entry, directory, names, linkTest && isHostTarget(entry));
  report.push({
    target: entry.target,
    bytes: libraries.reduce((sum, library) => sum + library.bytes, 0),
    libraries,
  });
}

await writeFile(
  join(outputRoot, "artifact-sizes.json"),
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(
  `caudex C release artifacts passed: ${selected.map((entry) => entry.target).join(", ")}`,
);

function buildLibrary(target, linkage, output, importLibrary) {
  const args = [
    "build-lib",
    "-target",
    target,
    "-OReleaseSmall",
    "--dep",
    "caudex",
    "--dep",
    "caudex_tracking",
    "--dep",
    "caudex_tracking_protocol",
    "--dep",
    "caudex_workflows",
    "--dep",
    "caudex_portable",
    `-Mroot=${resolve("src/c_api.zig")}`,
    "-OReleaseSmall",
    `-Mcaudex=${resolve("src/root.zig")}`,
    "-OReleaseSmall",
    "--dep",
    "caudex",
    `-Mcaudex_tracking=${resolve("tracking/root.zig")}`,
    "-OReleaseSmall",
    "--dep",
    "caudex",
    "--dep",
    "caudex_tracking",
    `-Mcaudex_tracking_protocol=${resolve("tracking/protocol.zig")}`,
    "-OReleaseSmall",
    "--dep",
    "caudex",
    "--dep",
    "caudex_tracking",
    "--dep",
    "caudex_tracking_protocol",
    `-Mcaudex_workflows=${resolve("workflows/root.zig")}`,
    "-OReleaseSmall",
    "--dep",
    "caudex",
    "--dep",
    "caudex_tracking",
    "--dep",
    "caudex_tracking_protocol",
    `-Mcaudex_portable=${resolve("portable/protocol.zig")}`,
    linkage === "static" ? "-static" : "-dynamic",
    `-femit-bin=${output}`,
    "--name",
    "caudex",
  ];
  // Keep compiler-rt symbols inside the static archive so ordinary C
  // toolchains can link it without knowing that the library was built by Zig.
  args.push("-fcompiler-rt");
  if (linkage === "dynamic" && target.endsWith("-macos")) {
    // A release bundle must be relocatable. The default install name embeds
    // the build machine's absolute output path.
    args.push("-install_name", "@rpath/libcaudex.dylib");
  }
  if (importLibrary) args.push(`-femit-implib=${importLibrary}`);
  run("zig", args);
}

async function testLinks(entry, directory, names, execute) {
  const fixture = resolve("fixtures/operations/recommendation-v1.json");
  const include = join(directory, "include");
  const library = join(directory, "lib");
  for (const linkage of ["static", "shared"]) {
    const executable = join(
      directory,
      entry.os === "windows"
        ? `conformance-${linkage}.exe`
        : `conformance-${linkage}`,
    );
    const artifact = join(
      library,
      linkage === "static"
        ? names.static
        : entry.os === "windows"
          ? names.import
          : names.shared,
    );
    const args = [
      "cc",
      "examples/c/conformance.c",
      `-I${include}`,
      artifact,
      "-target",
      entry.target,
      "-O2",
      "-o",
      executable,
    ];
    if (linkage === "shared" && entry.os !== "windows") {
      args.push(`-Wl,-rpath,${library}`);
    }
    run("zig", args);
    if (execute) {
      const environment = { ...process.env };
      if (entry.os === "linux") environment.LD_LIBRARY_PATH = library;
      if (entry.os === "macos") environment.DYLD_LIBRARY_PATH = library;
      if (entry.os === "windows") {
        environment.PATH = `${library};${environment.PATH ?? ""}`;
      }
      run(executable, [fixture], undefined, false, environment);
    }
    await rm(executable, { force: true });
  }
  if (execute && entry.os !== "windows") {
    await testNativeCompiler(entry, directory, names);
  }
}

async function testNativeCompiler(entry, directory, names) {
  const fixture = resolve("fixtures/operations/recommendation-v1.json");
  const include = join(directory, "include");
  const library = join(directory, "lib");
  const compiler = process.env.CC ?? "cc";
  for (const linkage of ["static", "shared"]) {
    const executable = join(directory, `conformance-native-${linkage}`);
    const artifact = join(
      library,
      linkage === "static" ? names.static : names.shared,
    );
    const args = [
      "examples/c/conformance.c",
      `-I${include}`,
      artifact,
      "-O2",
      "-o",
      executable,
    ];
    if (linkage === "shared") args.push(`-Wl,-rpath,${library}`);
    run(compiler, args);
    const environment = { ...process.env };
    if (entry.os === "linux") environment.LD_LIBRARY_PATH = library;
    if (entry.os === "macos") environment.DYLD_LIBRARY_PATH = library;
    run(executable, [fixture], undefined, false, environment);
    await rm(executable, { force: true });
  }
}

function libraryNames(os) {
  if (os === "windows") {
    return {
      static: "caudex.lib",
      shared: "caudex.dll",
      import: "caudex.import.lib",
    };
  }
  return {
    static: "libcaudex.a",
    shared: os === "macos" ? "libcaudex.dylib" : "libcaudex.so",
  };
}

function isHostTarget(entry) {
  const hostOs = { darwin: "macos", linux: "linux", win32: "windows" }[
    process.platform
  ];
  const hostArch = { arm64: "aarch64", x64: "x86_64" }[process.arch];
  return entry.os === hostOs && entry.arch === hostArch;
}

async function writeChecksums(directory) {
  const files = [
    "LICENSE",
    "NOTICE",
    "build-metadata.json",
    "include/caudex.h",
    ...(await readdir(join(directory, "lib"))).sort().map((file) => `lib/${file}`),
  ];
  const lines = [];
  for (const file of files) {
    lines.push(`${await sha256(join(directory, file))}  ${file}`);
  }
  await writeFile(join(directory, "SHA256SUMS"), `${lines.join("\n")}\n`);
}

async function verifyChecksums(directory) {
  const manifest = await readFile(join(directory, "SHA256SUMS"), "utf8");
  for (const line of manifest.trim().split("\n")) {
    const match = line.match(/^([0-9a-f]{64})  (.+)$/);
    if (!match || await sha256(join(directory, match[2])) !== match[1]) {
      throw new Error(`checksum verification failed: ${line}`);
    }
  }
}

async function sha256(path) {
  return createHash("sha256").update(await readFile(path)).digest("hex");
}

function run(command, args, cwd, capture = false, env = process.env) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
    timeout: 120_000,
  });
  if (result.status !== 0) {
    throw new Error(
      `${basename(command)} ${args.join(" ")} failed (${result.status})\n` +
        `${result.stdout ?? ""}${result.stderr ?? ""}`,
    );
  }
  return result;
}
