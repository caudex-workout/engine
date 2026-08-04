import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const temporary = await mkdtemp(join(tmpdir(), "caudex-catalog-generator-"));
try {
  const schema = Buffer.from("{}\n");
  const base = exercise("Stable_Id", null);
  const valid = Buffer.from(JSON.stringify([base]));
  const output = join(temporary, "catalog.json");
  await writeFile(join(temporary, "schema.json"), schema);
  await writeFixture(valid);
  run(output);
  const generated = JSON.parse(await readFile(output, "utf8"));
  if (generated.records[0].equipment !== null || generated.records[0].force !== null) throw new Error("null upstream fields were not preserved");

  await writeFixture(Buffer.from(JSON.stringify([base, base])));
  expectFailure(output, "duplicate upstream ID");
  await writeFixture(Buffer.from(JSON.stringify([exercise("Collision_A", null), exercise("collision-a", null)])));
  expectFailure(output, "normalized upstream ID collision");
  console.log("caudex exercise catalog generator edge cases passed");

  async function writeFixture(data) {
    await writeFile(join(temporary, "source.json"), data);
    await writeFile(join(temporary, "manifest.json"), JSON.stringify({
      upstreamRepository: "https://example.invalid/catalog",
      upstreamCommit: "0000000000000000000000000000000000000000",
      license: "Unlicense",
      transformationToolVersion: "caudex-exercise-catalog/1",
      upstreamDataSha256: sha256(data),
      upstreamSchemaSha256: sha256(schema),
      normalizedOutputFingerprint: "pending",
    }));
  }

  function run(destination) {
    const result = spawn(destination);
    if (result.status !== 0) throw new Error(result.stderr || result.stdout);
  }
  function expectFailure(destination, message) {
    const result = spawn(destination);
    if (result.status === 0 || !result.stderr.includes(message)) throw new Error(`expected generator failure: ${message}`);
  }
  function spawn(destination) {
    return spawnSync(process.execPath, [
      resolve("catalog/tools/generate.mjs"),
      "--source", join(temporary, "source.json"),
      "--schema", join(temporary, "schema.json"),
      "--manifest", join(temporary, "manifest.json"),
      "--output", destination,
    ], { encoding: "utf8" });
  }
} finally {
  await rm(temporary, { recursive: true, force: true });
}

function exercise(id, equipment) {
  return { id, name: id, force: null, level: "beginner", mechanic: null, equipment, primaryMuscles: ["biceps"], secondaryMuscles: [], instructions: [""], category: "strength", images: ["excluded.jpg"] };
}
function sha256(value) { return createHash("sha256").update(value).digest("hex"); }
