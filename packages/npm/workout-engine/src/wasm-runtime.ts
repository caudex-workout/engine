import type { CreateCaudexOptions, InitializationErrorCode } from "./index.ts";

type InitializationErrorFactory = (code: InitializationErrorCode, message: string, cause?: unknown) => Error;

export interface WasmExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;
  caudex_abi_version(): number;
  caudex_runtime_execute(runtime: number, requestPointer: number, requestLength: number, outputPointer: number, outputCapacity: number, requiredPointer: number): number;
  caudex_wasm_alloc(length: number): number;
  caudex_wasm_free(pointer: number, length: number): void;
  caudex_wasm_runtime_create(): number;
  caudex_wasm_runtime_destroy(runtime: number): void;
}

const requiredExports = [
  "memory", "caudex_abi_version", "caudex_runtime_execute", "caudex_wasm_alloc",
  "caudex_wasm_free", "caudex_wasm_runtime_create", "caudex_wasm_runtime_destroy",
] as const;

export async function initializeWasm(
  options: CreateCaudexOptions,
  error: InitializationErrorFactory,
): Promise<{ exports: WasmExports; runtime: number }> {
  const instance = await instantiate(options, error);
  const exports = requireExports(instance.exports, error);
  if (exports.caudex_abi_version() !== 2) {
    throw error("abi_mismatch", "The WebAssembly runtime does not implement Caudex ABI version 2.");
  }
  const runtime = exports.caudex_wasm_runtime_create();
  if (runtime === 0) {
    throw error("runtime_create_failed", "The WebAssembly runtime could not be created.");
  }
  return { exports, runtime };
}

async function instantiate(options: CreateCaudexOptions, error: InitializationErrorFactory): Promise<WebAssembly.Instance> {
  if (options.wasm) {
    try {
      const module = options.wasm instanceof WebAssembly.Module
        ? options.wasm
        : await WebAssembly.compile(options.wasm as BufferSource);
      return await WebAssembly.instantiate(module, {});
    } catch (cause) {
      throw error("wasm_compile_failed", "The supplied Caudex WebAssembly module could not be instantiated.", cause);
    }
  }
  const url = options.wasmUrl ? new URL(options.wasmUrl, import.meta.url) : new URL("../wasm/caudex.wasm", import.meta.url);
  if (url.protocol === "file:" && isNode()) {
    try {
      const dynamicImport = new Function("specifier", "return import(specifier)") as (specifier: string) => Promise<{ readFile(url: URL): Promise<Uint8Array> }>;
      const { readFile } = await dynamicImport("node:fs/promises");
      const module = await WebAssembly.compile(await readFile(url) as BufferSource);
      return await WebAssembly.instantiate(module, {});
    } catch (cause) {
      throw error("wasm_load_failed", `The Caudex WebAssembly module could not be loaded from ${url}.`, cause);
    }
  }
  const fetchImplementation = options.fetch ?? globalThis.fetch;
  if (!fetchImplementation) {
    throw error("wasm_load_failed", "No fetch implementation is available to load the Caudex WebAssembly module.");
  }
  try {
    const response = await fetchImplementation(url);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        return (await WebAssembly.instantiateStreaming(response.clone(), {})).instance;
      } catch {
        // Incorrect development-server MIME types use the ArrayBuffer fallback.
      }
    }
    return await WebAssembly.instantiate(await WebAssembly.compile(await response.arrayBuffer()), {});
  } catch (cause) {
    throw error("wasm_load_failed", `The Caudex WebAssembly module could not be loaded from ${url}.`, cause);
  }
}

function requireExports(raw: WebAssembly.Exports, error: InitializationErrorFactory): WasmExports {
  for (const name of requiredExports) {
    if (!(name in raw)) {
      throw error("missing_export", `The WebAssembly runtime is missing the required export "${name}".`);
    }
  }
  return raw as WasmExports;
}

function isNode(): boolean {
  return Boolean((globalThis as { process?: { versions?: { node?: string } } }).process?.versions?.node);
}
