---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/__tests__/wasm-build.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.983848+00:00
---

# core/cell-engine/__tests__/wasm-build.test.ts

```ts
/**
 * WASM build validation — updated through Phase 6.
 *
 * Phase 0 stub expectations (< 20KB, kernel_init returns 255) are superseded
 * by working implementations from Phases 1-6.
 */

import { describe, test, expect } from "bun:test";
import { readFileSync, existsSync, statSync } from "fs";
import { join } from "path";
import { execSync } from "child_process";

const CELL_ENGINE_DIR = join(import.meta.dir, "..");
const WASM_PATH = join(CELL_ENGINE_DIR, "zig-out/bin/cell-engine.wasm");

const hostStubs: Record<string, Function> = {
  host_sha256: () => {},
  host_hash160: () => {},
  host_hash256: () => {},
  host_checksig: () => 0,
  host_checkmultisig: () => 0,
  host_get_blocktime: () => 0,
  host_get_sequence: () => 0,
  host_log: () => {},
  host_fetch_cell: () => 0,
};

describe("WASM binary build and size", () => {
  test("zig build produces WASM binary", () => {
    execSync("zig build", { cwd: CELL_ENGINE_DIR });
    expect(existsSync(WASM_PATH)).toBe(true);
  });

  test("WASM binary is under 500KB (full profile with BSVZ)", () => {
    const size = statSync(WASM_PATH).size;
    expect(size).toBeGreaterThan(0);
    expect(size).toBeLessThan(512000); // 500KB max for full profile
  });
});

describe("WASM exports match CORE:WASM PlexusKernelWasm", () => {
  test("exports all 11 required functions + memory", async () => {
    const wasmBytes = readFileSync(WASM_PATH);
    const module = await WebAssembly.compile(wasmBytes);
    const exports = WebAssembly.Module.exports(module);
    const names = exports.map(e => e.name);

    for (const name of [
      "kernel_init", "kernel_reset", "kernel_load_script", "kernel_load_unlock",
      "kernel_execute", "kernel_get_type_class", "kernel_get_opcount",
      "kernel_get_error", "kernel_stack_depth", "kernel_stack_peek", "memory",
    ]) {
      expect(names).toContain(name);
    }
  });

  test("kernel_init returns SUCCESS (0)", async () => {
    const wasmBytes = readFileSync(WASM_PATH);
    const module = await WebAssembly.compile(wasmBytes);
    const instance = await WebAssembly.instantiate(module, { host: hostStubs });
    const exports = instance.exports as any;
    expect(exports.kernel_init()).toBe(0);
  });

  test("kernel_get_type_class returns -1 (UNCLASSIFIED) before classification", async () => {
    const wasmBytes = readFileSync(WASM_PATH);
    const module = await WebAssembly.compile(wasmBytes);
    const instance = await WebAssembly.instantiate(module, { host: hostStubs });
    const exports = instance.exports as any;
    expect(exports.kernel_get_type_class()).toBe(-1);
  });
});

```
