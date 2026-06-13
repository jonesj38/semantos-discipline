---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/cell-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.760191+00:00
---

# archive/apps-demo-wasm-threejs/src/cell-engine.ts

```ts
/**
 * Minimal browser binding for the Semantos cell engine.
 *
 * Copy this file + cell-engine.wasm into any project and you have a working
 * 2-PDA script executor with substructural linearity enforcement. No
 * dependencies (except DOM fetch/WebAssembly). No transitive @semantos/*
 * imports, no Node crypto, no BSV SDK.
 *
 * For the full-featured binding (cell pack/unpack, SPV, BCA, type-hash
 * registry, anchor scheduling), use @semantos/cell-engine/bindings/browser.
 *
 * The 13 required WASM exports are documented in
 *   core/protocol-types/src/wasm-contract.ts
 *
 * This binding adds a handful more so the demo can craft linearity-typed
 * cells from JS (cell_pack) and toggle the K1 enforcement gate
 * (kernel_set_enforcement).
 */

// ── kernel exports ───────────────────────────────────────────────────
export interface CellEngineExports {
  memory: WebAssembly.Memory;
  kernel_init(): number;
  kernel_reset(): number;
  kernel_load_script(ptr: number, len: number): number;
  kernel_load_unlock(ptr: number, len: number): number;
  kernel_execute(): number;
  kernel_get_type_class(): number;
  kernel_get_opcount(): number;
  kernel_get_error(): number;
  kernel_stack_depth(): number;
  kernel_stack_peek(idx: number): number;
  kernel_stack_value_length(idx: number): number;
  kernel_alt_stack_value_length(idx: number): number;
  // Phase-4 additions used by the linearity demo:
  kernel_set_enforcement(enabled: number): void;
  cell_pack(headerPtr: number, payloadPtr: number, payloadLen: number, outPtr: number): number;
}

// ── substructural linearity ──────────────────────────────────────────

/**
 * Linearity classes — match LinearityType in core/cell-engine/src/linearity.zig:10.
 *
 * Sourced from `@semantos/cube-object/linearity` (the cross-app single
 * source of truth). Re-exported here so existing demo internals keep
 * working without touching every import site.
 */
export type { LinearityClass } from '@semantos/cube-object/linearity';
import type { LinearityClass } from '@semantos/cube-object/linearity';

/** Kernel error codes interesting to a linearity-aware caller. */
export type LinearityError =
  | 'none'
  | 'cannot_duplicate_linear'     // K1a, LINEAR
  | 'cannot_discard_linear'       // K1b, LINEAR
  | 'cannot_duplicate_affine'     // AFFINE
  | 'cannot_discard_relevant'     // RELEVANT
  | 'invalid_linearity_type'
  | 'linearity_check_failed';

// Kernel error codes — see core/cell-engine/src/errors.zig.
const ERR_CANNOT_DUPLICATE_LINEAR = 22;
const ERR_CANNOT_DISCARD_LINEAR = 23;
const ERR_CANNOT_DUPLICATE_AFFINE = 24;
const ERR_CANNOT_DISCARD_RELEVANT = 25;
const ERR_INVALID_LINEARITY_TYPE = 26;
const ERR_LINEARITY_CHECK_FAILED = 27;

/**
 * Map a kernel error code to a LinearityError. Non-linearity error codes
 * (including verify_failed=6, stack_underflow=2, etc.) return 'none' — they
 * mean the K1 gate didn't reject anything; any failure was at a different
 * layer (script verdict, stack underflow, …). The caller can inspect
 * `errorCode` directly if they need the raw kernel response.
 */
function mapLinearityError(code: number): LinearityError {
  switch (code) {
    case ERR_CANNOT_DUPLICATE_LINEAR:   return 'cannot_duplicate_linear';
    case ERR_CANNOT_DISCARD_LINEAR:     return 'cannot_discard_linear';
    case ERR_CANNOT_DUPLICATE_AFFINE:   return 'cannot_duplicate_affine';
    case ERR_CANNOT_DISCARD_RELEVANT:   return 'cannot_discard_relevant';
    case ERR_INVALID_LINEARITY_TYPE:    return 'invalid_linearity_type';
    case ERR_LINEARITY_CHECK_FAILED:    return 'linearity_check_failed';
    default:                             return 'none';
  }
}

// Cell layout — see core/cell-engine/src/{constants,cell}.zig.
const CELL_SIZE = 1024;
const HEADER_SIZE = 256;
const HEADER_OFFSET_MAGIC = 0;
const HEADER_OFFSET_LINEARITY = 16;
const HEADER_OFFSET_VERSION = 20;
const VERSION = 1;
/** MAGIC_BYTES from cell.zig:11 — DEADBEEF CAFEBABE 13371337 42424242 */
const MAGIC_BYTES = new Uint8Array([
  0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe,
  0x13, 0x37, 0x13, 0x37, 0x42, 0x42, 0x42, 0x42,
]);

const LINEARITY_CODE: Record<LinearityClass, number> = {
  linear: 1,
  affine: 2,
  relevant: 3,
};

// ── script opcodes used by the demo ──────────────────────────────────
export const OP_DROP = 0x75;
export const OP_DUP = 0x76;
export const OP_PUSHDATA2 = 0x4d;
export const OP_CALLHOST = 0xd0;

// ── result shape ─────────────────────────────────────────────────────

export interface ScriptResult {
  success: boolean;
  opcodeCount: number;
  typeClassification: number;
  errorCode: number;
  linearityError: LinearityError;
}

export interface MinimalCellEngine {
  /** Execute a lock script. Resets the kernel before loading. */
  executeScript(lockScript: Uint8Array, unlockScript?: Uint8Array): ScriptResult;
  /** Stack depth after the most recent execute. */
  stackDepth(): number;
  /** Bytes at the top of the stack (index 0 = TOS). Empty if depth === 0. */
  stackPeek(index: number): Uint8Array;
  /** Enable/disable the kernel's substructural linearity gate (K1). */
  setEnforcement(enabled: boolean): void;
  /** Pack a linearity-typed cell from JS. Payload defaults to empty. */
  packCell(linearity: LinearityClass, payload?: Uint8Array): Uint8Array;
  /** Raw exports — for callers who want the full surface. */
  readonly exports: CellEngineExports;
}

// ── wasm memory layout ───────────────────────────────────────────────
// Matches the layout expected by the Zig/WASM kernel —
// see core/cell-engine/bindings/bun/cell-engine.ts.
const IO_BASE = 0x300000;
const IO_SCRIPT = IO_BASE + 0x1000;       // 64 KB script buffer
const IO_UNLOCK = IO_BASE + 0x11000;      // 64 KB unlock buffer
const IO_PACK_HEADER = IO_BASE + 0x21000; // scratch: pack inputs (256 B)
const IO_PACK_PAYLOAD = IO_BASE + 0x21400;// scratch: payload bytes (64 KB max)
const IO_PACK_OUT = IO_BASE + 0x31400;    // scratch: pack output (1024 B)

// ── host imports ─────────────────────────────────────────────────────
/**
 * OP_CALLHOST dispatcher. The kernel pops a name string off the top of
 * the main stack, then invokes `host_call_by_name(ptr, len)`. We decode
 * the name from wasm memory and delegate to this callback.
 *
 * Return 0xFFFFFFFF to report "unknown host function" (the kernel turns
 * this into error.unknown_host_function). Any other u32 is pushed as a
 * script integer onto the stack.
 */
export type HostCallDispatch = (name: string) => number;

/**
 * Full host-imports table if you want to control every extern. The wasm
 * linker requires all `host_*` symbols to exist; unknown names get a
 * noop via the Proxy wrapper, which keeps the embed portable.
 */
export type HostImports = Record<string, (...args: unknown[]) => number>;

export async function loadCellEngine(
  wasmUrl: string,
  dispatch?: HostCallDispatch,
): Promise<MinimalCellEngine> {
  // Populate lazily — we need exports.memory but only have it after instantiate.
  let memory: WebAssembly.Memory | null = null;
  const textDecoder = new TextDecoder();

  const host_call_by_name = ((namePtr: number, nameLen: number): number => {
    if (!memory || !dispatch) return 0xffffffff;
    const bytes = new Uint8Array(memory.buffer, namePtr, nameLen);
    const name = textDecoder.decode(bytes);
    return dispatch(name);
  }) as (...args: unknown[]) => number;

  const hostTable: HostImports = { host_call_by_name };
  const importObject = {
    host: new Proxy(hostTable, {
      get(target, prop: string) {
        return prop in target ? target[prop] : (): number => 0;
      },
    }),
  };
  let instance: WebAssembly.Instance;
  try {
    const response = await fetch(wasmUrl);
    const result = await WebAssembly.instantiateStreaming(Promise.resolve(response.clone()), importObject);
    instance = result.instance;
  } catch {
    // Fallback for environments without streaming or wrong MIME type
    const response = await fetch(wasmUrl);
    const bytes = await response.arrayBuffer();
    const result = await WebAssembly.instantiate(bytes, importObject);
    instance = result.instance;
  }

  const exports = instance.exports as unknown as CellEngineExports;
  memory = exports.memory; // now reachable from host_call_by_name
  const initRc = exports.kernel_init();
  if (initRc !== 0) {
    throw new Error(`kernel_init failed with code ${initRc}`);
  }

  function writeBytes(ptr: number, bytes: Uint8Array): void {
    new Uint8Array(exports.memory.buffer, ptr, bytes.length).set(bytes);
  }

  function readBytes(ptr: number, length: number): Uint8Array {
    return new Uint8Array(exports.memory.buffer, ptr, length).slice();
  }

  // Cache the enforcement setting JS-side. The kernel's reset() zeroes
  // enforcement_enabled (pda.zig:89), so we must re-apply after every reset
  // — easiest to do that inside executeScript.
  let enforcementEnabled = false;

  return {
    exports,

    executeScript(lockScript, unlockScript) {
      exports.kernel_reset();
      exports.kernel_set_enforcement(enforcementEnabled ? 1 : 0);

      if (unlockScript && unlockScript.length > 0) {
        writeBytes(IO_UNLOCK, unlockScript);
        const rc = exports.kernel_load_unlock(IO_UNLOCK, unlockScript.length);
        if (rc !== 0) throw new Error(`kernel_load_unlock failed with code ${rc}`);
      }

      writeBytes(IO_SCRIPT, lockScript);
      const loadRc = exports.kernel_load_script(IO_SCRIPT, lockScript.length);
      if (loadRc !== 0) throw new Error(`kernel_load_script failed with code ${loadRc}`);

      const rc = exports.kernel_execute();
      return {
        success: rc === 0,
        opcodeCount: exports.kernel_get_opcount(),
        typeClassification: exports.kernel_get_type_class(),
        errorCode: rc,
        linearityError: mapLinearityError(rc),
      };
    },

    stackDepth() {
      return exports.kernel_stack_depth();
    },

    stackPeek(index) {
      const length = exports.kernel_stack_value_length(index);
      if (length === 0) return new Uint8Array(0);
      const ptr = exports.kernel_stack_peek(index);
      if (ptr === 0) return new Uint8Array(0);
      return readBytes(ptr, length);
    },

    setEnforcement(enabled) {
      enforcementEnabled = enabled;
      exports.kernel_set_enforcement(enabled ? 1 : 0);
    },

    packCell(linearity, payload) {
      const header = new Uint8Array(HEADER_SIZE);
      header.set(MAGIC_BYTES, HEADER_OFFSET_MAGIC);
      const dv = new DataView(header.buffer);
      dv.setUint32(HEADER_OFFSET_LINEARITY, LINEARITY_CODE[linearity], true);
      dv.setUint32(HEADER_OFFSET_VERSION, VERSION, true);

      writeBytes(IO_PACK_HEADER, header);
      const payloadBytes = payload ?? new Uint8Array(0);
      if (payloadBytes.length > 0) writeBytes(IO_PACK_PAYLOAD, payloadBytes);

      const rc = exports.cell_pack(IO_PACK_HEADER, IO_PACK_PAYLOAD, payloadBytes.length, IO_PACK_OUT);
      if (rc !== 0) throw new Error(`cell_pack failed with code ${rc}`);
      return readBytes(IO_PACK_OUT, CELL_SIZE);
    },
  };
}

// ── script builder helpers ───────────────────────────────────────────

/** Script: OP_PUSHDATA2 <u16 LE len> <cell bytes>. */
export function pushCellScript(cellBytes: Uint8Array): Uint8Array {
  const len = cellBytes.length;
  const out = new Uint8Array(1 + 2 + len);
  out[0] = OP_PUSHDATA2;
  out[1] = len & 0xff;
  out[2] = (len >> 8) & 0xff;
  out.set(cellBytes, 3);
  return out;
}

/**
 * Script: push a short byte sequence using direct-push opcodes (0x01..0x4B).
 * For strings up to 75 bytes — exactly right for OP_CALLHOST name cells.
 */
export function pushBytesScript(data: Uint8Array): Uint8Array {
  const n = data.length;
  if (n === 0 || n > 0x4b) {
    throw new Error(`pushBytesScript: length must be 1..75, got ${n}`);
  }
  const out = new Uint8Array(1 + n);
  out[0] = n;
  out.set(data, 1);
  return out;
}

/** Concatenate a list of byte buffers into a single script. */
export function concatScript(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

```
