---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/k8-demotion/fuzz.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.355884+00:00
---

# proofs/fuzz/k8-demotion/fuzz.test.ts

```ts
/**
 * K8 Demotion Safety — L3 Differential Oracle Test
 *
 * Asserts that the Zig WASM cell-engine agrees with the Lean4 demotion
 * model (Semantos.Opcodes.validDemotion) on every (from, to) pair in
 * the 4×4 = 16-cell demotion validity table.
 *
 * Only two transitions are valid:
 *   LINEAR → AFFINE   (K8a)
 *   LINEAR → RELEVANT (K8b)
 * All 14 other transitions are invalid (K8c–K8i + symmetric cases).
 *
 * Oracle: proofs/lean/.lake/build/bin/K8DemotionOracle
 *   Input:  {"from": "<linearity>", "to": "<linearity>"}
 *   Output: {"valid": true|false}
 *
 * WASM test strategy:
 *   OP_DEMOTE (0xCB) is a Plexus opcode. It:
 *     1. Peeks the top cell to read its linearity type
 *     2. Peeks the second item (the target linearity byte)
 *     3. Validates via validDemotion(src, tgt)
 *     4. On success: pops both, pushes a new cell with tgt linearity
 *     5. On failure: returns error (.linearity_check_failed = code 22 area)
 *
 *   To exercise OP_DEMOTE via the BSV execution layer, we need two items
 *   on the (main) stack:
 *     - Top: the "target linearity" as a 1-byte value [1|2|3|4]
 *     - Second: the cell to demote (20-byte test cell with from-linearity)
 *
 *   Script:
 *     PUSH <20-byte cell with from-linearity>  (pushed second)
 *     PUSH <1-byte target linearity value>     (pushed first = top)
 *     0xCB (OP_DEMOTE)
 *
 *   If validDemotion returns true → OP_DEMOTE succeeds (kernel_execute = 0
 *   or verify_failed = 6 if top is falsy after demotion).
 *   If validDemotion returns false → OP_DEMOTE returns error.
 *
 * NOTE on OP_DEMOTE Plexus semantics:
 *   plexus.zig opDemote reads the top item as the target linearity *byte*
 *   and the second item as the cell. See the Lean4 Plexus.lean model for
 *   the exact stack layout. If the Zig implementation differs from the
 *   Lean4 model on the stack order, a divergence here would reveal it.
 *
 * Demotion error code: the Zig executor maps error.linearity_check_failed
 * to KernelError code 26 (from errors.zig). Any non-demotion error (e.g.,
 * stack_underflow = 2) is also a "not valid" signal.
 * A result of 0 (done_true) or 6 (done_false/verify_failed) = "valid".
 */

import { describe, it, expect, beforeAll } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join, resolve } from "path";
import { spawnSync } from "bun";

// ── Paths ─────────────────────────────────────────────────────────────────────

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const LEAN4_DIR = join(REPO_ROOT, "proofs/lean");
const ORACLE_BIN = join(LEAN4_DIR, ".lake/build/bin/K8DemotionOracle");
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
  const offset = 64 * 1024; // safe scratch area
  const mem = new Uint8Array(k.memory.buffer);
  mem.set(bytes, offset);
  return offset;
}

// ── "Valid demotion" detection from WASM result ───────────────────────────────

/** Success codes: 0 (done_true) or 6 (verify_failed / done_false). */
function isValidByWasm(result: number): boolean {
  return result === 0 || result === 6;
}

// ── Oracle ────────────────────────────────────────────────────────────────────

function queryOracle(from: string, to: string): boolean {
  const input = JSON.stringify({ from, to }) + "\n";
  const result = spawnSync([ORACLE_BIN], {
    stdin: Buffer.from(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`K8DemotionOracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  const out = JSON.parse(result.stdout.toString().trim());
  if ("error" in out) throw new Error(`Oracle parse error: ${out.error} (input: ${input.trim()})`);
  return out.valid as boolean;
}

// ── Script builder ────────────────────────────────────────────────────────────

const LINEARITY_VALUE: Record<string, number> = {
  linear: 1,
  affine: 2,
  relevant: 3,
  debug: 4,
};

/**
 * Build a 20-byte test cell with `from` linearity at bytes 16-19.
 * No magic required — plexus.zig reads linearity via getLinearity()
 * which only checks bytes 16-19.
 */
function makeTestCell(linearity: string): Uint8Array {
  const cell = new Uint8Array(20);
  const view = new DataView(cell.buffer);
  view.setUint32(16, LINEARITY_VALUE[linearity], true);
  return cell;
}

/**
 * Build the script for testing OP_DEMOTE with (from, to).
 *
 * Stack layout for opDemote (from plexus.zig):
 *   Top:    target linearity byte (1 byte)
 *   Second: cell to demote (20-byte test cell)
 *
 * Script:
 *   0x14 <20 bytes: from-linearity cell>
 *   0x01 <1 byte:  to-linearity value>
 *   0xCB (OP_DEMOTE)
 */
function buildDemoteScript(from: string, to: string): Uint8Array {
  const cell = makeTestCell(from);
  const toVal = LINEARITY_VALUE[to];
  // Script: push cell (20 bytes), push target byte (1 byte), OP_DEMOTE
  const script = new Uint8Array(1 + 20 + 1 + 1 + 1);
  script[0] = 0x14;          // push 20 bytes
  script.set(cell, 1);
  script[21] = 0x01;         // push 1 byte
  script[22] = toVal;
  script[23] = 0xCB;         // OP_DEMOTE
  return script;
}

// ── WASM query ────────────────────────────────────────────────────────────────

function queryWasm(from: string, to: string): boolean {
  const k = getKernel();
  const script = buildDemoteScript(from, to);
  const ptr = writeToWasm(k, script);

  k.kernel_reset();
  k.kernel_set_enforcement(1);
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult}`);
  const result = k.kernel_execute();
  return isValidByWasm(result);
}

// ── Test matrix ───────────────────────────────────────────────────────────────

const LINEARITIES = ["linear", "affine", "relevant", "debug"];

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  if (!existsSync(ORACLE_BIN)) {
    const build = spawnSync([LAKE_BIN, "build", "K8DemotionOracle"], {
      cwd: LEAN4_DIR,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (build.exitCode !== 0) throw new Error("Failed to build K8DemotionOracle");
  }

  const wasmBytes = readFileSync(WASM_PATH);
  const hostStubs = {
    host_fetch_cell:  () => 0,
    host_call_by_name: () => 0,
    hostDbOpenCursor: () => 0,
    hostDbCursorPull: () => 0,
    hostDbCursorClose: () => 0,
    host_sha256:      () => {},
    host_hash160:     () => {},
    host_hash256:     () => {},
    host_ripemd160:   () => {},
    host_sha1:        () => {},
    host_checksig:    () => 0,
    host_checkmultisig: () => 0,
    host_sign:        () => 0,
    host_get_blocktime: () => 0,
    host_get_sequence:  () => 0,
    host_log:         () => {},
    host_derive_leaf: () => 0,
    host_state_next_index: () => 0,
    host_unlock_tier: () => 0,
    host_persist_cell: () => 0,
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { host: hostStubs });
  const e = instance.exports as unknown as KernelExports;
  const initResult = e.kernel_init();
  if (initResult !== 0) throw new Error(`kernel_init failed: ${initResult}`);
  kernel = e;
}, 120_000);

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("K8 Demotion Safety — L3 Oracle vs WASM (exhaustive 4×4)", () => {
  describe("oracle sanity — valid transitions (K8a, K8b)", () => {
    it("linear → affine is valid (K8a)", () => {
      expect(queryOracle("linear", "affine")).toBe(true);
    });
    it("linear → relevant is valid (K8b)", () => {
      expect(queryOracle("linear", "relevant")).toBe(true);
    });
  });

  describe("oracle sanity — invalid transitions (K8c–K8i)", () => {
    it("affine → linear is invalid (no promotion, K8c)", () => {
      expect(queryOracle("affine", "linear")).toBe(false);
    });
    it("relevant → linear is invalid (no promotion, K8d)", () => {
      expect(queryOracle("relevant", "linear")).toBe(false);
    });
    it("affine → affine is invalid (identity, K8e)", () => {
      expect(queryOracle("affine", "affine")).toBe(false);
    });
    it("relevant → relevant is invalid (identity, K8f)", () => {
      expect(queryOracle("relevant", "relevant")).toBe(false);
    });
    it("relevant → affine is invalid (cross-branch, K8g)", () => {
      expect(queryOracle("relevant", "affine")).toBe(false);
    });
    it("affine → relevant is invalid (cross-branch, K8h)", () => {
      expect(queryOracle("affine", "relevant")).toBe(false);
    });
    it("debug → linear is invalid (K8i)", () => {
      expect(queryOracle("debug", "linear")).toBe(false);
    });
  });

  describe("oracle vs WASM — full 4×4 table (16 differential assertions)", () => {
    for (const from of LINEARITIES) {
      for (const to of LINEARITIES) {
        it(`${from} → ${to}`, () => {
          const oracleResult = queryOracle(from, to);
          const wasmResult   = queryWasm(from, to);
          expect(wasmResult).toBe(oracleResult);
        });
      }
    }
  });
});

```
