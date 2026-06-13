---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/k4-failure-atomic/fuzz.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.356231+00:00
---

# proofs/fuzz/k4-failure-atomic/fuzz.test.ts

```ts
/**
 * K4 Failure Atomicity — L3 Differential Oracle Test
 *
 * K4 states: for ALL Plexus opcodes (0xC0-0xCF), error result precludes
 * any successful result on the same call (K4 master theorem in FailureAtomicK4.lean).
 *
 * The most testable K4 property is the **depth-underflow gate**: each opcode
 * has a structural minimum stack depth before it can do ANY mutation.  Below
 * that threshold it returns `.error (.stackError .stack_underflow)` with the
 * PDA completely unchanged — this is exactly the K4 atomic guarantee for this
 * error class.
 *
 * Oracle: proofs/lean/.lake/build/bin/K4FailureAtomicOracle
 *   Input:  {"op": "0xCX"}
 *   Output: {"minDepth": N}
 *
 * The oracle reads `plexusMinDepth` from the Lean4 opcode definitions, so
 * any edit to those definitions that changes the depth check will be caught
 * by a divergence here.
 *
 * WASM test strategy per test type:
 *
 *   underflow_at_zero: for each opcode, execute with depth=0 (empty stack).
 *     All 16 Plexus ops must return stack_underflow (error code 2).
 *     Oracle says minDepth ≥ 1 for all — so depth=0 < minDepth for all.
 *
 *   underflow_at_mindepth_minus_one: for opcodes with minDepth ≥ 2,
 *     push (minDepth-1) items, execute. Must still return stack_underflow (2).
 *
 *   no_underflow_at_mindepth: for each opcode, push exactly minDepth items,
 *     execute. Result must NOT be stack_underflow (2). It may be another error
 *     (wrong linearity, cell format, etc.) or even success, but the depth
 *     gate has been passed — proving that minDepth is the tight threshold.
 *
 * Test cell: 20-byte cell, linearity=DEBUG (4) at bytes 16-19.
 * Using DEBUG linearity avoids triggering linearity-type errors for the type-
 * checking opcodes at the initial speek, letting us focus purely on the depth
 * gate. At minDepth items, the opcode gets past the underflow check and may
 * fail for other reasons (wrong number of items for content-based checks) but
 * NOT stack_underflow.
 *
 * Error codes (errors.zig):
 *   stack_underflow = 2
 *   stack_overflow  = 1
 *   (all others are non-underflow errors)
 */

import { describe, it, expect, beforeAll } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join, resolve } from "path";
import { spawnSync } from "bun";

// ── Paths ─────────────────────────────────────────────────────────────────────

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const LEAN4_DIR = join(REPO_ROOT, "proofs/lean");
const ORACLE_BIN = join(LEAN4_DIR, ".lake/build/bin/K4FailureAtomicOracle");
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

const STACK_UNDERFLOW = 2;

// ── Oracle ────────────────────────────────────────────────────────────────────

/** Query the K4 oracle for the minimum stack depth of a Plexus opcode. */
function queryOracle(opHex: string): number {
  const input = JSON.stringify({ op: opHex }) + "\n";
  const result = spawnSync([ORACLE_BIN], {
    stdin: Buffer.from(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`K4FailureAtomicOracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  const out = JSON.parse(result.stdout.toString().trim());
  if ("error" in out) throw new Error(`Oracle error: ${out.error} (op: ${opHex})`);
  return out.minDepth as number;
}

// ── Script builder ────────────────────────────────────────────────────────────

/**
 * Build a 20-byte test cell with linearity=DEBUG (4).
 * Using DEBUG avoids linearity errors from type-check opcodes,
 * letting us isolate depth-gate behavior.
 */
function makeDebugCell(): Uint8Array {
  const cell = new Uint8Array(20);
  const view = new DataView(cell.buffer);
  view.setUint32(16, 4, true); // linearity=DEBUG, LE u32
  return cell;
}

/**
 * Build a script that pushes `depth` identical 20-byte cells and then
 * executes the given Plexus opcode byte.
 *
 * Push encoding: 0x14 (push 20 bytes) + 20 bytes per item.
 */
function buildScript(depth: number, opByte: number): Uint8Array {
  const cell = makeDebugCell();
  const pushSize = 1 + 20; // opcode + data
  const total = depth * pushSize + 1; // N pushes + 1 opcode
  const script = new Uint8Array(total);
  let pos = 0;
  for (let i = 0; i < depth; i++) {
    script[pos++] = 0x14; // push 20 bytes
    script.set(cell, pos);
    pos += 20;
  }
  script[pos] = opByte;
  return script;
}

// ── WASM query ────────────────────────────────────────────────────────────────

function executeWithDepth(opByte: number, depth: number): number {
  const k = getKernel();
  const script = buildScript(depth, opByte);
  const ptr = writeToWasm(k, script);
  k.kernel_reset();
  k.kernel_set_enforcement(1);
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult} (op=0x${opByte.toString(16).padStart(2,"0")}, depth=${depth})`);
  return k.kernel_execute();
}

// ── All 16 Plexus opcodes ─────────────────────────────────────────────────────

const PLEXUS_OPCODES = [
  { hex: "0xC0", byte: 0xC0, name: "OP_CHECKLINEARTYPE"  },
  { hex: "0xC1", byte: 0xC1, name: "OP_CHECKAFFINETYPE"  },
  { hex: "0xC2", byte: 0xC2, name: "OP_CHECKRELEVANTTYPE" },
  { hex: "0xC3", byte: 0xC3, name: "OP_CHECKCAPABILITY"  },
  { hex: "0xC4", byte: 0xC4, name: "OP_CHECKIDENTITY"    },
  { hex: "0xC5", byte: 0xC5, name: "OP_ASSERTLINEAR"     },
  { hex: "0xC6", byte: 0xC6, name: "OP_CHECKDOMAINFLAG"  },
  { hex: "0xC7", byte: 0xC7, name: "OP_CHECKTYPEHASH"    },
  { hex: "0xC8", byte: 0xC8, name: "OP_DEREF_POINTER"    },
  { hex: "0xC9", byte: 0xC9, name: "OP_READHEADER"       },
  { hex: "0xCA", byte: 0xCA, name: "OP_CELLCREATE"       },
  { hex: "0xCB", byte: 0xCB, name: "OP_DEMOTE"           },
  { hex: "0xCC", byte: 0xCC, name: "OP_READPAYLOAD"      },
  { hex: "0xCD", byte: 0xCD, name: "OP_SIGN"             },
  { hex: "0xCE", byte: 0xCE, name: "OP_DECREMENT_BUDGET" },
  { hex: "0xCF", byte: 0xCF, name: "OP_REFILL_BUDGET"    },
];

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  if (!existsSync(ORACLE_BIN)) {
    const build = spawnSync([LAKE_BIN, "build", "K4FailureAtomicOracle"], {
      cwd: LEAN4_DIR,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (build.exitCode !== 0) throw new Error("Failed to build K4FailureAtomicOracle");
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

describe("K4 Failure Atomicity — L3 Oracle vs WASM", () => {

  describe("oracle sanity — minDepth table matches K4 inversion lemmas", () => {
    it("0xC0 OP_CHECKLINEARTYPE: minDepth=1",   () => expect(queryOracle("0xC0")).toBe(1));
    it("0xC3 OP_CHECKCAPABILITY: minDepth=2",   () => expect(queryOracle("0xC3")).toBe(2));
    it("0xC9 OP_READHEADER: minDepth=3",         () => expect(queryOracle("0xC9")).toBe(3));
    it("0xCA OP_CELLCREATE: minDepth=4",         () => expect(queryOracle("0xCA")).toBe(4));
    it("0xCF OP_REFILL_BUDGET: minDepth=4",      () => expect(queryOracle("0xCF")).toBe(4));
    it("0xCD OP_SIGN: minDepth=3",               () => expect(queryOracle("0xCD")).toBe(3));
    it("0xCE OP_DECREMENT_BUDGET: minDepth=2",   () => expect(queryOracle("0xCE")).toBe(2));
  });

  describe("underflow_at_zero — all 16 Plexus ops return stack_underflow at depth=0", () => {
    for (const op of PLEXUS_OPCODES) {
      it(`${op.name} (${op.hex}) depth=0 → stack_underflow`, () => {
        const minDepth = queryOracle(op.hex);
        // Sanity: oracle says minDepth ≥ 1 for all Plexus ops
        expect(minDepth).toBeGreaterThanOrEqual(1);
        const result = executeWithDepth(op.byte, 0);
        expect(result).toBe(STACK_UNDERFLOW);
      });
    }
  });

  describe("underflow_at_mindepth_minus_one — ops requiring ≥2 still underflow at depth=minDepth-1", () => {
    for (const op of PLEXUS_OPCODES) {
      const minDepth = queryOracle(op.hex);
      if (minDepth <= 1) continue; // only test ops that require > 1 item
      it(`${op.name} (${op.hex}) depth=${minDepth - 1} → stack_underflow`, () => {
        const result = executeWithDepth(op.byte, minDepth - 1);
        expect(result).toBe(STACK_UNDERFLOW);
      });
    }
  });

  describe("no_underflow_at_mindepth — ops pass depth gate at depth=minDepth (result ≠ stack_underflow)", () => {
    for (const op of PLEXUS_OPCODES) {
      it(`${op.name} (${op.hex}) depth=minDepth → NOT stack_underflow`, () => {
        const minDepth = queryOracle(op.hex);
        const result = executeWithDepth(op.byte, minDepth);
        // Result may be another error (wrong linearity, invalid cell) or success,
        // but NOT stack_underflow — that gate has been cleared.
        expect(result).not.toBe(STACK_UNDERFLOW);
      });
    }
  });
});

```
