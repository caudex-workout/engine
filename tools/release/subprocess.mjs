import { spawnSync } from "node:child_process";

export const fastCommandTimeoutMs = 120_000;
export const compilerLinkerTimeoutMs = 5 * 60 * 1000;

export function run(
  command,
  args,
  {
    cwd,
    env = process.env,
    timeoutMs = fastCommandTimeoutMs,
    operation = "subprocess",
    platform = `${process.platform}-${process.arch}`,
    contract = "release validation",
    context = "",
  } = {},
) {
  const result = spawnSync(command, args, {
    cwd,
    env,
    encoding: "utf8",
    stdio: "pipe",
    timeout: timeoutMs,
  });
  const timedOut = result.error?.code === "ETIMEDOUT";
  if (result.error || result.signal || result.status !== 0) {
    const header = timedOut
      ? `${contract}: ${operation} timed out\n\n` +
        `platform:\n  ${platform}\n\n` +
        `command:\n  ${shellCommand(command, args)}\n\n` +
        `timeout:\n  ${formatTimeout(timeoutMs)}\n`
      : `${contract}: ${context ? `${context}\n` : ""}` +
        `failed command:\n  ${shellCommand(command, args)}\n`;
    throw new Error(
      header +
        `exit status:\n  ${result.status ?? "unknown"}${result.signal ? ` (${result.signal})` : ""}\n` +
        (result.error ? `launcher error:\n  ${result.error.message}\n` : "") +
        outputBlock("stdout", result.stdout) +
        outputBlock("stderr", result.stderr),
    );
  }
  return result;
}

function formatTimeout(timeoutMs) {
  return `${timeoutMs / 1000}s`;
}

function shellCommand(command, args) {
  return [command, ...args].map((value) => {
    if (/^[A-Za-z0-9_./:=+-]+$/.test(value)) return value;
    return `'${value.replaceAll("'", "'\\''")}'`;
  }).join(" ");
}

function outputBlock(label, value) {
  const text = value ?? "";
  if (text.length === 0) return `${label}:\n  <empty>\n`;
  const maximum = 12000;
  const bounded = text.length > maximum ? `${text.slice(0, maximum)}\n  [... output truncated at ${maximum} bytes]` : text;
  return `${label}:\n${bounded}\n`;
}
