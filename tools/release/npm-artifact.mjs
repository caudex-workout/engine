import { createHash } from "node:crypto";
import { readFile, stat } from "node:fs/promises";
import { basename, resolve } from "node:path";
import { pathToFileURL } from "node:url";

export async function canonicalNpmArtifact(
  inputPath,
  expectedFilename = undefined,
  expectedIntegrity = undefined,
) {
  if (typeof inputPath !== "string" || inputPath.length === 0) {
    throw new Error(
      "npm clean-consumer packaging: exact release artifact path is missing",
    );
  }
  const artifactPath = resolve(inputPath);
  let metadata;
  try {
    metadata = await stat(artifactPath);
  } catch (error) {
    throw new Error(
      `npm clean-consumer packaging: exact release artifact is not accessible: ${artifactPath}\n` +
        `cause: ${error.message}`,
    );
  }
  if (!metadata.isFile()) {
    throw new Error(
      `npm clean-consumer packaging: exact release artifact is not a regular file: ${artifactPath}`,
    );
  }
  if (!artifactPath.endsWith(".tgz")) {
    throw new Error(
      `npm clean-consumer packaging: exact release artifact must end in .tgz: ${artifactPath}`,
    );
  }
  if (expectedFilename !== undefined && basename(artifactPath) !== expectedFilename) {
    throw new Error(
      `npm clean-consumer packaging: exact release artifact filename mismatch\n` +
        `expected: ${expectedFilename}\n` +
        `actual: ${basename(artifactPath)}`,
    );
  }
  if (expectedIntegrity !== undefined) {
    const actualIntegrity = `sha512-${createHash("sha512")
      .update(await readFile(artifactPath))
      .digest("base64")}`;
    if (actualIntegrity !== expectedIntegrity) {
      throw new Error(
        `npm clean-consumer packaging: exact release artifact integrity mismatch\n` +
          `expected: ${expectedIntegrity}\n` +
          `actual: ${actualIntegrity}`,
      );
    }
  }
  const artifactFileUrl = pathToFileURL(artifactPath).href;
  return {
    artifactPath,
    artifactFileUrl,
    npmDependencySpec: decodeURI(artifactFileUrl),
  };
}
