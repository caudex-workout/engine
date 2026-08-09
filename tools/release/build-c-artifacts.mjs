import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import {
  chmod,
  cp,
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rename,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { basename, dirname, join, resolve } from "node:path";

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
console.log(`[c-release-compatibility] running${hostOnly ? " host-only" : " full matrix"}`);
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
  if (entry.os === "macos") await normalizeDarwinArchive(staticPath);
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
    // Static Unix libraries are consumed by ordinary host compilers, whose
    // Linux defaults commonly produce PIE executables. Keep the reusable
    // library PIC instead of requiring consumers to disable PIE.
    ...(linkage === "static" && (target.endsWith("-linux-gnu") || target.endsWith("-macos"))
      ? ["-fPIC"]
      : []),
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

async function normalizeDarwinArchive(archive) {
  // Zig embeds compiler-rt so the published static C library is self-contained.
  // Apple ld64 also requires 64-bit Mach-O archive members to use Darwin alignment,
  // so rebuild macOS archives before checksums, packaging, and native-link tests.
  const originalMembers = archiveMemberNames(
    run("zig", ["ar", "t", archive], undefined, true).stdout,
  );
  const objectMembers = originalMembers.filter(
    (member) => !member.startsWith("__.SYMDEF"),
  );
  if (!objectMembers.includes("compiler_rt.o")) {
    throw new Error(`macOS static archive is missing compiler_rt.o: ${archive}`);
  }
  if (new Set(objectMembers).size !== objectMembers.length) {
    throw new Error(`macOS static archive contains duplicate members: ${archive}`);
  }

  // Keep the temporary directory beside the artifact so rename() can replace
  // the original on the same filesystem without exposing a partial archive.
  const temporary = await mkdtemp(join(dirname(archive), ".caudex-darwin-ar-"));
  const membersDirectory = join(temporary, "members");
  const replacement = join(temporary, basename(archive));
  try {
    await mkdir(membersDirectory);
    run("zig", ["ar", "--output", membersDirectory, "x", archive]);
    const extractedMembers = (await readdir(membersDirectory)).sort();
    const expectedMembers = [...objectMembers].sort();
    if (
      extractedMembers.length !== expectedMembers.length ||
      extractedMembers.some((member, index) => member !== expectedMembers[index])
    ) {
      throw new Error(
        `macOS static archive extraction changed its members: ${archive}\n` +
          `expected: ${expectedMembers.join(", ")}\n` +
          `actual: ${extractedMembers.join(", ")}`,
      );
    }
    for (const member of extractedMembers) {
      if (member.includes("/") || member.includes("\\") || member === "." || member === "..") {
        throw new Error(`unsafe macOS archive member name: ${member}`);
      }
      // Zig ar preserves archive member modes; its extracted object files can
      // be mode 000, so make the isolated inputs readable by the archive tool.
      await chmod(join(membersDirectory, member), 0o644);
    }
    run("zig", [
      "ar",
      "--format=darwin",
      "-rcD",
      replacement,
      ...expectedMembers.map((member) => join(membersDirectory, member)),
    ]);
    const normalizedMembers = archiveMemberNames(
      run("zig", ["ar", "t", replacement], undefined, true).stdout,
    ).filter((member) => !member.startsWith("__.SYMDEF"));
    if (
      normalizedMembers.length !== expectedMembers.length ||
      normalizedMembers.some((member, index) => member !== expectedMembers[index])
    ) {
      throw new Error(`Darwin archive normalization changed member ordering or contents: ${archive}`);
    }
    await assertDarwinArchiveLayout(replacement);
    await rename(replacement, archive);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

function archiveMemberNames(output) {
  const names = output.split(/\r?\n/).map((name) => name.trim()).filter(Boolean);
  if (names.some((name) => name.includes("/") || name.includes("\\") || name === "." || name === "..")) {
    throw new Error(`unsafe archive member name in ar output: ${names.join(", ")}`);
  }
  return names;
}

async function assertDarwinArchiveLayout(archive) {
  const data = await readFile(archive);
  if (data.subarray(0, 8).toString() !== "!<arch>\n") {
    throw new Error(`normalized archive is not an ar archive: ${archive}`);
  }
  let offset = 8;
  let compilerRuntimeOffset;
  while (offset + 60 <= data.length) {
    if (data.subarray(offset + 58, offset + 60).toString() !== "`\n") {
      throw new Error(`malformed ar header in normalized archive: ${archive}`);
    }
    const headerName = data.subarray(offset, offset + 16).toString().trim();
    const memberSize = Number(data.subarray(offset + 48, offset + 58).toString().trim());
    if (!Number.isSafeInteger(memberSize) || memberSize < 0) {
      throw new Error(`invalid ar member size in normalized archive: ${archive}`);
    }
    const extendedNameLength = headerName.startsWith("#1/")
      ? Number(headerName.slice(3))
      : 0;
    const memberOffset = offset + 60 + extendedNameLength;
    const memberEnd = offset + 60 + memberSize;
    if (
      !Number.isSafeInteger(extendedNameLength) ||
      extendedNameLength < 0 ||
      memberOffset > memberEnd ||
      memberEnd > data.length
    ) {
      throw new Error(`invalid ar member bounds in normalized archive: ${archive}`);
    }
    const memberName = extendedNameLength > 0
      ? data.subarray(offset + 60, memberOffset).toString().replaceAll("\0", "")
      : headerName.replace(/\/$/, "");
    if (memberName === "compiler_rt.o") compilerRuntimeOffset = memberOffset;
    if (!memberName.startsWith("__.SYMDEF") && memberOffset % 8 !== 0) {
      throw new Error(`unaligned Mach-O member ${memberName} in normalized archive: ${archive}`);
    }
    offset = memberEnd + (memberSize % 2);
  }
  if (offset !== data.length || compilerRuntimeOffset === undefined || compilerRuntimeOffset % 8 !== 0) {
    throw new Error(`normalized archive has invalid compiler-rt alignment or trailing data: ${archive}`);
  }
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
    ];
    // Linux keeps libm separate from libc; the static and shared artifacts
    // use round/roundq, so ordinary native consumers must link the normal
    // platform math library after libcaudex.
    if (entry.os === "linux") args.push("-lm");
    args.push("-O2", "-o", executable);
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
      `C release compatibility: ${basename(command)} ${args.join(" ")} failed (${result.status})\n` +
        `${result.stdout ?? ""}${result.stderr ?? ""}`,
    );
  }
  return result;
}
