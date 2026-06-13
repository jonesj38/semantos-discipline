---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/k7-cell-immutability/fuzz.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.354867+00:00
---

# proofs/fuzz/k7-cell-immutability/fuzz.test.ts

```ts
/**
 * K7 Cell Immutability — L3 Differential Oracle Test
 *
 * K7 proves that no opcode modifies cell header fields. The key sub-theorems
 * testable via this oracle are:
 *
 *   K7d: classifyOp OP_READHEADER    = .inspect  (0xC9)
 *   K7e: classifyOp OP_READPAYLOAD   = .inspect  (0xCC)
 *   K7f: classifyOp OP_CODESEPARATOR = .inspect  (0xAB)
 *
 * An "inspect" classification means the opcode is read-only from a linearity
 * perspective: it is permitted on LINEAR cells (unlike duplicate/discard ops
 * which are blocked by the linearity enforcer).
 *
 * Oracle: proofs/lean/.lake/build/bin/K7ClassifyOpOracle
 *   Input:  {"op": "0xXX"}
 *   Output: {"classification": "duplicate"|"discard"|"consume"|"swap"|"inspect"}
 *           {"error": "bad_input"}
 *
 * WASM test strategy:
 *
 *   inspect_permits_linear: for each "inspect" opcode (K7d/K7e/K7f), push
 *     LINEAR cells to the required minimum depth and execute. The result must
 *     NOT be error 22 (cannot_duplicate_linear) or error 23
 *     (cannot_discard_linear). Linearity enforcement must allow inspect ops
 *     on LINEAR cells — any other error (depth, cell format, success) is fine.
 *
 *   duplicate_blocks_linear: execute OP_DUP (0x76, classified "duplicate")
 *     with a LINEAR cell on top. Must return error 22 (cannot_duplicate_linear).
 *     This is the contrast case: K1 proves this, K7 contrasts it.
 *
 *   discard_blocks_linear: execute OP_DROP (0x75, classified "discard") with a
 *     LINEAR cell on top. Must return error 23 (cannot_discard_linear).
 *
 * Minimum depth reference (from K4 oracle):
 *   0xC9 OP_READHEADER  → minDepth = 3
 *   0xCC OP_READPAYLOAD → minDepth = 3
 *   0xAB OP_CODESEPARATOR → minDepth = 0 (does not pop the stack)
 *   0x76 OP_DUP         → minDepth = 1
 *   0x75 OP_DROP        → minDepth = 1
 *
 * For inspect tests, the top-of-stack cell is LINEAR (linearity = 1).
 * Padding cells beneath it use DEBUG linearity (4) to avoid triggering
 * linearity errors on those slots, keeping the focus on the top cell.
 *
 * Error codes (errors.zig):
 *   0  = success
 *   22 = cannot_duplicate_linear
 *   23 = cannot_discard_linear
 */

import { describe, it, expect, beforeAll } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join, resolve } from "path";
import { spawnSync } from "bun";

// ── Paths ─────────────────────────────────────────────────────────────────────

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const LEAN4_DIR = join(REPO_ROOT, "proofs/lean");
const ORACLE_BIN = join(LEAN4_DIR, ".lake/build/bin/K7ClassifyOpOracle");
const LAKE_BIN = join(process.env.HOME ?? "/root", ".elan/bin/lake");
const WASM_PATH = join(REPO_ROOT, "core/cell-engine/zig-out/bin/cell-engine.wasm");

// ── WASM kernel setup ─────────────────────────────────────────────────────────

interface KernelExports {
  memory: WebAssembly.Memory;
  kernel_init: () => number;
  kernel_reset: () => void;
  kernel_load_script: (ptr: number, len: number) => number;
  kernel_set_enforcement: (enabled: number) => void;
  kernel_execute: () => number;
}

let kernel: KernelExports | null = null;

function getKernel(): KernelExports {
  if (!kernel) throw new Error("WASM kernel not initialised");
  return kernel;
}

function writeToWasm(k: KernelExports, bytes: Uint8Array): number {
  const offset = 64 * 1024;
  const mem = new Uint8Array(k.memory.buffer);
  mem.set(bytes, offset);
  return offset;
}

// ── Error code constants ──────────────────────────────────────────────────────

const CANNOT_DUPLICATE_LINEAR = 22;
const CANNOT_DISCARD_LINEAR   = 23;

// ── Oracle ────────────────────────────────────────────────────────────────────

/** Query the K7 oracle for the stack classification of any opcode byte. */
function queryOracle(opHex: string): string {
  const input = JSON.stringify({ op: opHex }) + "\n";
  const result = spawnSync([ORACLE_BIN], {
    stdin: Buffer.from(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`K7ClassifyOpOracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  const out = JSON.parse(result.stdout.toString().trim());
  if ("error" in out) throw new Error(`Oracle error: ${out.error} (op: ${opHex})`);
  return out.classification as string;
}

// ── Cell builders ─────────────────────────────────────────────────────────────

/** 20-byte cell with linearity = LINEAR (1). */
function makeLinearCell(): Uint8Array {
  const cell = new Uint8Array(20);
  new DataView(cell.buffer).setUint32(16, 1, true); // linearity=LINEAR, LE u32
  return cell;
}

/** 20-byte cell with linearity = DEBUG (4). Used as neutral padding. */
function makeDebugCell(): Uint8Array {
  const cell = new Uint8Array(20);
  new DataView(cell.buffer).setUint32(16, 4, true); // linearity=DEBUG, LE u32
  return cell;
}

// ── Script builder ────────────────────────────────────────────────────────────

/**
 * Build a script that:
 *   1. Pushes `prefixDepth` DEBUG cells (neutral padding)
 *   2. Pushes `topCell` (the cell under test)
 *   3. Appends `opByte`
 *
 * Push encoding: 0x14 (push 20 bytes) + 20 bytes per cell.
 */
function buildScript(
  prefixDepth: number,
  topCell: Uint8Array,
  opByte: number,
): Uint8Array {
  const debugCell = makeDebugCell();
  const pushSize = 1 + 20; // opcode + data
  const total = (prefixDepth + 1) * pushSize + 1;
  const script = new Uint8Array(total);
  let pos = 0;
  for (let i = 0; i < prefixDepth; i++) {
    script[pos++] = 0x14;
    script.set(debugCell, pos);
    pos += 20;
  }
  script[pos++] = 0x14;
  script.set(topCell, pos);
  pos += 20;
  script[pos] = opByte;
  return script;
}

// ── WASM query ────────────────────────────────────────────────────────────────

function executeScript(script: Uint8Array): number {
  const k = getKernel();
  const ptr = writeToWasm(k, script);
  k.kernel_reset();
  k.kernel_set_enforcement(1);
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult}`);
  return k.kernel_execute();
}

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  if (!existsSync(ORACLE_BIN)) {
    const build = spawnSync([LAKE_BIN, "build", "K7ClassifyOpOracle"], {
      cwd: LEAN4_DIR,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (build.exitCode !== 0) throw new Error("Failed to build K7ClassifyOpOracle");
  }

  const wasmBytes = readFileSync(WASM_PATH);
  const hostStubs = {
    host_fetch_cell:       () => 0,
    host_call_by_name:     () => 0,
    hostDbOpenCursor:      () => 0,
    hostDbCursorPull:      () => 0,
    hostDbCursorClose:     () => 0,
    host_sha256:           () => {},
    host_hash160:          () => {},
    host_hash256:          () => {},
    host_ripemd160:        () => {},
    host_sha1:             () => {},
    host_checksig:         () => 0,
    host_checkmultisig:    () => 0,
    host_sign:             () => 0,
    host_get_blocktime:    () => 0,
    host_get_sequence:     () => 0,
    host_log:              () => {},
    host_derive_leaf:      () => 0,
    host_state_next_index: () => 0,
    host_unlock_tier:      () => 0,
    host_persist_cell:     () => 0,
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { host: hostStubs });
  const e = instance.exports as unknown as KernelExports;
  const initResult = e.kernel_init();
  if (initResult !== 0) throw new Error(`kernel_init failed: ${initResult}`);
  kernel = e;
}, 120_000);

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("K7 Cell Immutability — L3 Oracle vs WASM", () => {

  // ── Oracle sanity: K7d, K7e, K7f + contrast cases ────────────────────────

  describe("oracle_sanity — classifyOp matches K7d/K7e/K7f and contrast theorems", () => {
    it("K7d: 0xC9 OP_READHEADER    → inspect",   () => expect(queryOracle("0xC9")).toBe("inspect"));
    it("K7e: 0xCC OP_READPAYLOAD   → inspect",   () => expect(queryOracle("0xCC")).toBe("inspect"));
    it("K7f: 0xAB OP_CODESEPARATOR → inspect",   () => expect(queryOracle("0xAB")).toBe("inspect"));
    it("contrast: 0x76 OP_DUP      → duplicate", () => expect(queryOracle("0x76")).toBe("duplicate"));
    it("contrast: 0x75 OP_DROP     → discard",   () => expect(queryOracle("0x75")).toBe("discard"));
    it("contrast: 0x00 OP_0        → consume",   () => expect(queryOracle("0x00")).toBe("consume"));
  });

  // ── WASM linearity agreement: inspect ops must not be blocked on LINEAR cells

  describe("inspect_permits_linear — inspect ops do NOT trigger linearity errors on LINEAR cells", () => {
    it("K7d: 0xC9 OP_READHEADER (prefix=2 DEBUG + LINEAR top) → NOT 22/23", () => {
      // Oracle: inspect. minDepth=3 from K4. Push 2 DEBUG + 1 LINEAR top.
      const script = buildScript(2, makeLinearCell(), 0xC9);
      const result = executeScript(script);
      expect(result).not.toBe(CANNOT_DUPLICATE_LINEAR);
      expect(result).not.toBe(CANNOT_DISCARD_LINEAR);
    });

    it("K7e: 0xCC OP_READPAYLOAD (prefix=2 DEBUG + LINEAR top) → NOT 22/23", () => {
      // Oracle: inspect. minDepth=3 from K4. Push 2 DEBUG + 1 LINEAR top.
      const script = buildScript(2, makeLinearCell(), 0xCC);
      const result = executeScript(script);
      expect(result).not.toBe(CANNOT_DUPLICATE_LINEAR);
      expect(result).not.toBe(CANNOT_DISCARD_LINEAR);
    });

    it("K7f: 0xAB OP_CODESEPARATOR (LINEAR top) → NOT 22/23", () => {
      // Oracle: inspect. minDepth=0 (doesn't pop stack). Push 1 LINEAR cell.
      const script = buildScript(0, makeLinearCell(), 0xAB);
      const result = executeScript(script);
      expect(result).not.toBe(CANNOT_DUPLICATE_LINEAR);
      expect(result).not.toBe(CANNOT_DISCARD_LINEAR);
    });
  });

  // ── WASM linearity agreement: duplicate/discard ops ARE blocked on LINEAR cells

  describe("duplicate_discard_block_linear — contrast: non-inspect ops block LINEAR cells", () => {
    it("0x76 OP_DUP (duplicate, LINEAR cell) → error 22 (cannot_duplicate_linear)", () => {
      // Oracle: duplicate. minDepth=1. LINEAR cell on top. Enforcement blocks.
      const script = buildScript(0, makeLinearCell(), 0x76);
      const result = executeScript(script);
      expect(result).toBe(CANNOT_DUPLICATE_LINEAR);
    });

    it("0x75 OP_DROP (discard, LINEAR cell) → error 23 (cannot_discard_linear)", () => {
      // Oracle: discard. minDepth=1. LINEAR cell on top. Enforcement blocks.
      const script = buildScript(0, makeLinearCell(), 0x75);
      const result = executeScript(script);
      expect(result).toBe(CANNOT_DISCARD_LINEAR);
    });
  });

  // ── Full differential: oracle classification predicts WASM enforcement ──────

  describe("full_differential — oracle classification agrees with WASM enforcement for all test opcodes", () => {
    const TEST_CASES = [
      { hex: "0xC9", byte: 0xC9, name: "OP_READHEADER",    prefixDepth: 2 },
      { hex: "0xCC", byte: 0xCC, name: "OP_READPAYLOAD",   prefixDepth: 2 },
      { hex: "0xAB", byte: 0xAB, name: "OP_CODESEPARATOR", prefixDepth: 0 },
      { hex: "0x76", byte: 0x76, name: "OP_DUP",           prefixDepth: 0 },
      { hex: "0x75", byte: 0x75, name: "OP_DROP",          prefixDepth: 0 },
    ] as const;

    for (const tc of TEST_CASES) {
      it(`${tc.name} (${tc.hex}): oracle classification predicts linearity enforcement`, () => {
        const classification = queryOracle(tc.hex);
        const script = buildScript(tc.prefixDepth, makeLinearCell(), tc.byte);
        const result = executeScript(script);

        if (classification === "inspect" || classification === "consume" || classification === "swap") {
          // inspect/consume/swap: LINEAR cell is not blocked by linearity rules
          expect(result).not.toBe(CANNOT_DUPLICATE_LINEAR);
          expect(result).not.toBe(CANNOT_DISCARD_LINEAR);
        } else if (classification === "duplicate") {
          // duplicate: LINEAR cell MUST be blocked
          expect(result).toBe(CANNOT_DUPLICATE_LINEAR);
        } else if (classification === "discard") {
          // discard: LINEAR cell MUST be blocked
          expect(result).toBe(CANNOT_DISCARD_LINEAR);
        } else {
          throw new Error(`Unexpected classification from oracle: ${classification}`);
        }
      });
    }
  });
});

```
