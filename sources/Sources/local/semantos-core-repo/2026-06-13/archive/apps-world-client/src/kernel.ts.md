---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/kernel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.821598+00:00
---

# archive/apps-world-client/src/kernel.ts

```ts
// M2.7 — Cell-engine WASM loader + typed wrapper.
//
// Wraps the kernel_* / cell_* / bca_* / multicell_* exports produced by
// core/cell-engine/src/main.zig into a typed TypeScript API.  All reads and
// writes go through the module's linear memory so callers never touch raw
// WebAssembly.Memory offsets directly.
//
// The WASM binary imports a "host" module with crypto and runtime functions
// (host_sha256, host_checksig, etc.).  `buildHostImports` constructs stubs or
// real implementations depending on the environment.
//
// Usage (browser):
//   const kernel = await loadKernel('/cell-engine.wasm');
//   kernel.init();
//   const snap = kernel.snapshotState();
//
// Usage (Node / vitest):
//   import { readFileSync } from 'node:fs';
//   const wasm = readFileSync('/abs/path/to/cell-engine.wasm');
//   const kernel = await loadKernelFromBuffer(wasm);

import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

// ── Snapshot magic ──────────────────────────────────────────────────────────

export const SNAPSHOT_HEADER_SIZE = 12;

// ── Step result codes (kernel_step return values) ────────────────────────────

export const StepResult = {
  Continue: 0,
  DoneOk: 1,
  DoneError: 2,
} as const;
export type StepResult = (typeof StepResult)[keyof typeof StepResult];

// ── WASM export surface ─────────────────────────────────────────────────────

export interface KernelExports extends WebAssembly.Exports {
  memory: WebAssembly.Memory;

  // Phase 3: lifecycle
  kernel_init: () => number;
  kernel_reset: () => void;

  // Phase 3: script loading + execution
  kernel_load_script: (ptr: number, len: number) => number;
  kernel_load_unlock: (ptr: number, len: number) => number;
  kernel_execute: () => number;

  // Phase 3: introspection
  kernel_get_type_class: () => number;
  kernel_set_enforcement: (enabled: number) => void;
  kernel_get_opcount: () => number;
  kernel_get_error: () => number;
  kernel_stack_depth: () => number;
  kernel_stack_peek: (index: number) => number;
  kernel_alt_stack_depth: () => number;
  kernel_alt_stack_peek: (index: number) => number;
  kernel_stack_value_length: (index: number) => number;
  kernel_alt_stack_value_length: (index: number) => number;

  // Phase 3: debug stepping
  kernel_step: () => number;
  kernel_get_pc: () => number;
  kernel_get_current_op: () => number;

  // Snapshot / restore
  kernel_snapshot_state: () => number;
  kernel_restore_state: (ptr: number) => number;

  // Phase 3: tx context
  kernel_load_tx_context: (
    txPtr: number,
    txLen: number,
    inputIndex: number,
    inputValue: bigint,
  ) => number;

  // Phase WH1: header verifier
  kernel_header_compute_hash: (headerPtr: number, outPtr: number) => number;
  kernel_header_verify_pow: (headerPtr: number) => number;
  kernel_header_validate: (
    parentPtr: number,
    candidatePtr: number,
    parentHeight: number,
    prevTsPtr: number,
    prevTsCount: number,
    powLimitBits: number,
    nowSeconds: number,
  ) => number;

  // Phase 5: BEEF/BUMP
  kernel_beef_version: (dataPtr: number, dataLen: number) => number;
  kernel_verify_beef: (
    beefPtr: number,
    beefLen: number,
    txidPtr: number,
  ) => number;
  kernel_verify_beef_spv: (
    beefPtr: number,
    beefLen: number,
    txidPtr: number,
    rootsPtr: number,
    rootsCount: number,
  ) => number;
  kernel_verify_bump: (
    bumpPtr: number,
    bumpLen: number,
    txidPtr: number,
    merkleRootPtr: number,
  ) => number;

  // Phase 5: capability
  kernel_verify_capability: (
    lockScriptPtr: number,
    lockScriptLen: number,
    ownerPubkeyPtr: number,
    capType: number,
    domainFlag: number,
    currentTime: number,
  ) => number;

  // Phase 1: cell packing
  cell_pack: (
    headerPtr: number,
    payloadPtr: number,
    payloadLen: number,
    outPtr: number,
  ) => number;
  cell_unpack: (
    cellPtr: number,
    headerOutPtr: number,
    payloadOutPtr: number,
  ) => number;
  cell_validate_magic: (cellPtr: number) => number;

  // Phase 1: multicell
  multicell_pack: (
    headerPtr: number,
    payloadPtr: number,
    payloadLen: number,
    contTypesPtr: number,
    contOffsetsPtr: number,
    contSizesPtr: number,
    contDataPtr: number,
    contCount: number,
    outPtr: number,
  ) => number;
  multicell_unpack: (bufferPtr: number, bufferLen: number) => number;

  // Phase 2: BCA
  bca_derive: (
    pubkeyPtr: number,
    prefixPtr: number,
    modifierPtr: number,
    sec: number,
    outPtr: number,
  ) => number;
  bca_verify: (
    addrPtr: number,
    pubkeyPtr: number,
    prefixPtr: number,
    modifierPtr: number,
  ) => number;
}

// ── Memory helpers ──────────────────────────────────────────────────────────

/**
 * Copy `data` into WASM linear memory starting at `offset`, then return the
 * offset so callers can chain: `const p = write(data, alloc(data.length))`.
 */
function writeBytes(
  mem: WebAssembly.Memory,
  offset: number,
  data: Uint8Array,
): number {
  new Uint8Array(mem.buffer, offset, data.length).set(data);
  return offset;
}

/**
 * Copy `length` bytes out of WASM linear memory starting at `offset`.
 */
function readBytes(
  mem: WebAssembly.Memory,
  offset: number,
  length: number,
): Uint8Array {
  return new Uint8Array(mem.buffer.slice(offset, offset + length));
}

// ── Kernel class ────────────────────────────────────────────────────────────

/**
 * Typed wrapper around the cell-engine WASM module.  All methods that pass
 * data into WASM write into a 64 KiB scratch region at offset 0 in the
 * module's linear memory.  The scratch area is only used during the call so
 * re-entrancy is not a concern in a single-threaded JS environment.
 *
 * The kernel must be initialised exactly once before any other method is
 * called:
 *
 *   const k = await loadKernel('/cell-engine.wasm');
 *   k.init();
 */
export class Kernel {
  /** Underlying WebAssembly instance (for advanced / test use). */
  readonly instance: WebAssembly.Instance;
  private readonly exp: KernelExports;

  // Base offset of the scratch area used for argument marshalling.
  // We start at 65536 (page 1) to stay away from Zig's data segment at page 0.
  private static readonly SCRATCH_BASE = 65536;
  private static readonly SCRATCH_SIZE = 65536;

  constructor(instance: WebAssembly.Instance) {
    this.instance = instance;
    this.exp = instance.exports as KernelExports;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /**
   * Initialise global kernel state.  Must be called once before any
   * script-loading or snapshot methods.  Returns 0 on success.
   */
  init(): number {
    return this.exp.kernel_init();
  }

  /** Reset PDA + arena without re-initialising. */
  reset(): void {
    this.exp.kernel_reset();
  }

  // ── Script execution ───────────────────────────────────────────────────────

  /** Load a locking script into the kernel. Returns 0 on success. */
  loadScript(script: Uint8Array): number {
    this.beginAlloc();
    const ptr = this.bump(script.length || 1);
    writeBytes(this.exp.memory, ptr, script);
    return this.exp.kernel_load_script(ptr, script.length);
  }

  /** Load an unlocking script into the kernel. Returns 0 on success. */
  loadUnlock(unlock: Uint8Array): number {
    this.beginAlloc();
    const ptr = this.bump(unlock.length || 1);
    writeBytes(this.exp.memory, ptr, unlock);
    return this.exp.kernel_load_unlock(ptr, unlock.length);
  }

  /**
   * Execute the loaded unlock + lock scripts.
   * Returns 0 if the stack top is truthy after execution, or a negative error code.
   */
  execute(): number {
    return this.exp.kernel_execute();
  }

  // ── Introspection ──────────────────────────────────────────────────────────

  getTypeClass(): number {
    return this.exp.kernel_get_type_class();
  }

  setEnforcement(enabled: boolean): void {
    this.exp.kernel_set_enforcement(enabled ? 1 : 0);
  }

  getOpcount(): number {
    return this.exp.kernel_get_opcount();
  }

  stackDepth(): number {
    return this.exp.kernel_stack_depth();
  }

  stackValueLength(index: number): number {
    return this.exp.kernel_stack_value_length(index);
  }

  // ── Snapshot / restore ────────────────────────────────────────────────────

  /**
   * Capture the current PDA state and return a copy of the snapshot blob.
   *
   * Layout: [u32 magic "CESN"][u32 version][u32 pda_size][pda_bytes…]
   *
   * The returned buffer is owned by the caller — the underlying WASM
   * snapshot buffer is a static reservation that will be overwritten by the
   * next call to snapshotState().
   */
  snapshotState(): Uint8Array {
    const ptr = this.exp.kernel_snapshot_state();
    if (ptr === 0) {
      throw new Error("kernel_snapshot_state: kernel not initialised");
    }
    // Read the header to find the total blob size.
    const headerView = new DataView(this.exp.memory.buffer, ptr, SNAPSHOT_HEADER_SIZE);
    const pdaSize = headerView.getUint32(8, /* littleEndian */ true);
    const totalSize = SNAPSHOT_HEADER_SIZE + pdaSize;
    return readBytes(this.exp.memory, ptr, totalSize);
  }

  /**
   * Restore PDA state from a snapshot blob previously returned by
   * `snapshotState()`.  Writes the blob into the scratch area and passes the
   * pointer to the kernel.
   *
   * Throws on any validation failure (magic, version, or size mismatch).
   */
  restoreState(snapshot: Uint8Array): void {
    // PDA snapshots are ~1.25 MB — too large for the 192 KB small-scratch zone.
    // Strategy: call kernel_snapshot_state() to obtain the WASM address of the
    // internal g_snapshot_buffer, then overwrite that buffer with our JS copy
    // before passing the same pointer to kernel_restore_state().
    //
    // This is safe because g_snapshot_buffer is a reserved static region
    // exactly large enough to hold one snapshot.  Writing our copy there does
    // not conflict with any other WASM state.
    const bufPtr = this.exp.kernel_snapshot_state();
    if (bufPtr === 0) {
      throw new Error("restoreState: kernel not initialised (kernel_snapshot_state returned 0)");
    }
    // Overwrite the snapshot buffer with our JS-side copy.
    new Uint8Array(this.exp.memory.buffer, bufPtr, snapshot.length).set(snapshot);
    const rc = this.exp.kernel_restore_state(bufPtr);
    if (rc !== 0) {
      const reason = {
        "-1": "kernel not initialised",
        "-2": "magic mismatch",
        "-3": "unsupported version",
        "-4": "PDA size mismatch",
      }[rc.toString()] ?? `unknown error (${rc})`;
      throw new Error(`kernel_restore_state failed: ${reason}`);
    }
  }

  // ── Cell packing ──────────────────────────────────────────────────────────

  /** Constants matching core/cell-engine/src/constants.zig */
  static readonly CELL_SIZE = 1024;
  static readonly HEADER_SIZE = 256;
  static readonly PAYLOAD_SIZE = 768;

  /**
   * Pack a header (256 bytes) + payload into a 1024-byte cell blob.
   * Returns the packed cell on success, throws on error.
   */
  cellPack(header: Uint8Array, payload: Uint8Array): Uint8Array {
    if (header.length !== Kernel.HEADER_SIZE) {
      throw new Error(`header must be ${Kernel.HEADER_SIZE} bytes, got ${header.length}`);
    }
    this.beginAlloc();
    const headerPtr = this.bump(Kernel.HEADER_SIZE);
    const payloadPtr = this.bump(payload.length || 1);
    const outPtr = this.bump(Kernel.CELL_SIZE);
    writeBytes(this.exp.memory, headerPtr, header);
    if (payload.length > 0) writeBytes(this.exp.memory, payloadPtr, payload);
    const rc = this.exp.cell_pack(headerPtr, payloadPtr, payload.length, outPtr);
    if (rc !== 0) throw new Error(`cell_pack failed: ${rc}`);
    return readBytes(this.exp.memory, outPtr, Kernel.CELL_SIZE);
  }

  /**
   * Unpack a 1024-byte cell blob into { header, payload, payloadLen }.
   */
  cellUnpack(cellBlob: Uint8Array): {
    header: Uint8Array;
    payload: Uint8Array;
    payloadLen: number;
  } {
    if (cellBlob.length !== Kernel.CELL_SIZE) {
      throw new Error(`cell must be ${Kernel.CELL_SIZE} bytes, got ${cellBlob.length}`);
    }
    this.beginAlloc();
    const cellPtr = this.bump(Kernel.CELL_SIZE);
    const headerOutPtr = this.bump(Kernel.HEADER_SIZE);
    const payloadOutPtr = this.bump(Kernel.PAYLOAD_SIZE);
    writeBytes(this.exp.memory, cellPtr, cellBlob);
    const payloadLen = this.exp.cell_unpack(cellPtr, headerOutPtr, payloadOutPtr);
    if (payloadLen < 0) throw new Error(`cell_unpack failed: ${payloadLen}`);
    return {
      header: readBytes(this.exp.memory, headerOutPtr, Kernel.HEADER_SIZE),
      payload: readBytes(this.exp.memory, payloadOutPtr, payloadLen),
      payloadLen,
    };
  }

  /** Returns true if the 1024-byte cell blob has the correct magic bytes. */
  cellValidateMagic(cellBlob: Uint8Array): boolean {
    this.beginAlloc();
    const ptr = this.bump(Kernel.CELL_SIZE);
    writeBytes(this.exp.memory, ptr, cellBlob);
    return this.exp.cell_validate_magic(ptr) === 1;
  }

  // ── BCA derivation ────────────────────────────────────────────────────────

  /**
   * Derive a BCA address.
   * @param pubkey 33-byte compressed public key
   * @param subnetPrefix 8-byte subnet prefix
   * @param modifier 16-byte modifier
   * @param sec security level (0–255)
   * @returns { address: Uint8Array(16), collisionCount: number }
   */
  bcaDerive(
    pubkey: Uint8Array,
    subnetPrefix: Uint8Array,
    modifier: Uint8Array,
    sec: number,
  ): { address: Uint8Array; collisionCount: number } {
    this.beginAlloc();
    const pubkeyPtr = this.bump(33);
    const prefixPtr = this.bump(8);
    const modifierPtr = this.bump(16);
    const outPtr = this.bump(16);
    writeBytes(this.exp.memory, pubkeyPtr, pubkey);
    writeBytes(this.exp.memory, prefixPtr, subnetPrefix);
    writeBytes(this.exp.memory, modifierPtr, modifier);
    const collisionCount = this.exp.bca_derive(pubkeyPtr, prefixPtr, modifierPtr, sec, outPtr);
    if (collisionCount < 0) throw new Error(`bca_derive failed: ${collisionCount}`);
    return {
      address: readBytes(this.exp.memory, outPtr, 16),
      collisionCount,
    };
  }

  // ── Header verification ───────────────────────────────────────────────────

  /**
   * Compute SHA256d of an 80-byte block header.
   * @returns 32-byte hash in internal byte order (reverse to get display order)
   */
  headerComputeHash(header: Uint8Array): Uint8Array {
    this.beginAlloc();
    const base = this.bump(80);
    const outBase = this.bump(32);
    writeBytes(this.exp.memory, base, header);
    const rc = this.exp.kernel_header_compute_hash(base, outBase);
    if (rc !== 0) throw new Error(`kernel_header_compute_hash failed: ${rc}`);
    return readBytes(this.exp.memory, outBase, 32);
  }

  /** Returns true if SHA256d(header) < compact target from header.bits. */
  headerVerifyPow(header: Uint8Array): boolean {
    this.beginAlloc();
    const ptr = this.bump(80);
    writeBytes(this.exp.memory, ptr, header);
    return this.exp.kernel_header_verify_pow(ptr) === 1;
  }

  // ── Memory scratch allocator ────────────────────────────────────────────────
  //
  // The WASM module starts with 128 pages (8 MB) of linear memory.
  //
  // Memory layout (discovered at runtime):
  //   0x00000 – 0x0FFFF  (pages 0–1)   : zero, safe for small scratch
  //   0x40000 – 0x3FFFF  (pages 2–3)   : may contain non-zero Zig data
  //   ~0x40C750           (page ~65)    : g_snapshot_buffer (1.25 MB PDA blob)
  //   after snapshot buffer             : safe for large blob writes
  //
  // SCRATCH_BASE (page 1, 65536) is used for small per-call marshalling.
  // For large blobs (PDA snapshots), we write directly into the WASM's own
  // g_snapshot_buffer by calling kernel_snapshot_state() to get its address,
  // then overwriting the contents with our JS copy before calling restore.

  /** Start of the 64-KiB small-data scratch area (page 1). */
  private static readonly SCRATCH_BASE = 65536;
  /** Upper bound of the small scratch zone. Must not conflict with Zig statics. */
  private static readonly SCRATCH_LIMIT = 262144; // 256 KB — Zig data starts here

  private _scratchTop = Kernel.SCRATCH_BASE;

  /** Reset the small scratch area. Call once at the start of each method. */
  private beginAlloc(): void {
    this._scratchTop = Kernel.SCRATCH_BASE;
  }

  /**
   * Allocate `size` bytes from the small scratch area (8-byte aligned).
   * Always call `beginAlloc()` first.
   */
  private bump(size: number): number {
    const ptr = this._scratchTop;
    this._scratchTop += Math.ceil(Math.max(size, 1) / 8) * 8;
    if (this._scratchTop > Kernel.SCRATCH_LIMIT) {
      throw new Error(
        `Kernel scratch overflow: ${this._scratchTop - Kernel.SCRATCH_BASE} B used, ` +
        `limit is ${Kernel.SCRATCH_LIMIT - Kernel.SCRATCH_BASE} B. ` +
        `Use restoreState / snapshotState for large blobs.`,
      );
    }
    const mem = this.exp.memory;
    while (mem.buffer.byteLength < this._scratchTop) mem.grow(1);
    return ptr;
  }

}

// ── Host import stubs ───────────────────────────────────────────────────────
//
// The cell-engine WASM imports a "host" module with crypto primitives and
// runtime callbacks.  In a browser the host is wired to WebCrypto / BSV SDK.
// In Node tests we use the built-in `node:crypto` module for hashing and
// return sensible stubs for the sig/cell-storage functions.
//
// The stub set is complete: every `pub extern "host" fn` in host.zig has an
// entry here so WebAssembly.instantiate never throws "missing import".

type WasmMemoryGetter = () => WebAssembly.Memory;

function buildHostImports(getMemory: WasmMemoryGetter): WebAssembly.ModuleImports {
  // Lazy-load node:crypto only in Node environments.
  // In browsers, these stubs will still satisfy the import table; real crypto
  // should be wired via a custom `hostOverrides` parameter (future work).
  const nodeCrypto = (() => {
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      return require("node:crypto") as typeof import("node:crypto");
    } catch {
      return null;
    }
  })();

  function mem(): WebAssembly.Memory { return getMemory(); }

  function readSlice(ptr: number, len: number): Uint8Array {
    return new Uint8Array(mem().buffer, ptr, len);
  }

  function writeSlice(ptr: number, data: Uint8Array): void {
    new Uint8Array(mem().buffer, ptr, data.length).set(data);
  }

  return {
    // ── Hash functions ──────────────────────────────────────────────────────

    host_sha256(dataPtr: number, dataLen: number, outPtr: number): void {
      if (!nodeCrypto) return;
      const input = readSlice(dataPtr, dataLen);
      const hash = nodeCrypto.createHash("sha256").update(input).digest();
      writeSlice(outPtr, new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength));
    },

    host_hash256(dataPtr: number, dataLen: number, outPtr: number): void {
      // SHA256d = SHA256(SHA256(data))
      if (!nodeCrypto) return;
      const input = readSlice(dataPtr, dataLen);
      const h1 = nodeCrypto.createHash("sha256").update(input).digest();
      const h2 = nodeCrypto.createHash("sha256").update(h1).digest();
      writeSlice(outPtr, new Uint8Array(h2.buffer, h2.byteOffset, h2.byteLength));
    },

    host_hash160(dataPtr: number, dataLen: number, outPtr: number): void {
      // HASH160 = RIPEMD160(SHA256(data))
      if (!nodeCrypto) return;
      const input = readSlice(dataPtr, dataLen);
      const sha = nodeCrypto.createHash("sha256").update(input).digest();
      const ripe = nodeCrypto.createHash("ripemd160").update(sha).digest();
      writeSlice(outPtr, new Uint8Array(ripe.buffer, ripe.byteOffset, ripe.byteLength));
    },

    host_ripemd160(dataPtr: number, dataLen: number, outPtr: number): void {
      if (!nodeCrypto) return;
      const input = readSlice(dataPtr, dataLen);
      const hash = nodeCrypto.createHash("ripemd160").update(input).digest();
      writeSlice(outPtr, new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength));
    },

    host_sha1(dataPtr: number, dataLen: number, outPtr: number): void {
      if (!nodeCrypto) return;
      const input = readSlice(dataPtr, dataLen);
      const hash = nodeCrypto.createHash("sha1").update(input).digest();
      writeSlice(outPtr, new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength));
    },

    // ── Signature verification (stubs — not needed for M2.7 T0 tests) ──────

    host_checksig(
      _pkPtr: number, _pkLen: number,
      _msgPtr: number, _msgLen: number,
      _sigPtr: number, _sigLen: number,
    ): number {
      // Stub: always returns 1 (valid) for tests that don't involve checksig
      return 1;
    },

    host_checkmultisig(
      _pksPtr: number, _pksCount: number,
      _sigsPtr: number, _sigsCount: number,
      _msgPtr: number, _msgLen: number,
      _threshold: number,
    ): number {
      return 1;
    },

    host_sign(
      _skPtr: number, _skLen: number,
      _msgPtr: number, _msgLen: number,
      _outPtr: number, _outBufLen: number,
      _outLenPtr: number,
    ): number {
      return 0; // stub: signing not used in M2.7 tests
    },

    // ── Runtime / time functions ────────────────────────────────────────────

    host_get_blocktime(): number {
      return Math.floor(Date.now() / 1000);
    },

    host_get_sequence(): number {
      return 0xffffffff; // default: final sequence
    },

    host_log(msgPtr: number, msgLen: number): void {
      try {
        const bytes = readSlice(msgPtr, msgLen);
        console.log("[kernel]", new TextDecoder().decode(bytes));
      } catch { /* ignore */ }
    },

    // ── Dynamic dispatch (stub) ─────────────────────────────────────────────

    host_call_by_name(_namePtr: number, _nameLen: number): number {
      return 0; // not implemented in Node test environment
    },

    // ── Cell / octave storage (stubs) ───────────────────────────────────────

    host_fetch_cell(
      _octave: number, _slot: number, _offset: number, _outPtr: number,
    ): number {
      return 0; // not implemented in Node test environment
    },

    host_derive_leaf(
      _baseSKPtr: number, _baseSKLen: number,
      _protocolHashPtr: number,
      _counterpartyPtr: number,
      _index: bigint,
      _outPtr: number, _outBufLen: number, _outLenPtr: number,
    ): number {
      return 0;
    },

    host_state_next_index(
      _protocolHashPtr: number,
      _counterpartyPtr: number,
      _outIndexPtr: number,
    ): number {
      return 0;
    },

    host_unlock_tier(
      _tier: number,
      _factorHandlePtr: number, _factorLen: number,
      _slotId: number,
      _outCellPtr: number,
    ): number {
      return 0;
    },

    host_persist_cell(
      _slotId: number, _cellPtr: number, _len: number,
    ): number {
      return 1; // stub: pretend success
    },

    host_load_cell(
      _slotId: number, _outPtr: number,
    ): number {
      return 0; // stub: not found
    },
  };
}

// ── Factory functions ───────────────────────────────────────────────────────

/**
 * Load the cell-engine WASM from a URL (browser) or an absolute file path
 * (Node / vitest).
 */
export async function loadKernel(wasmUrlOrPath: string): Promise<Kernel> {
  let bytes: BufferSource;

  // Node: treat as file path
  if (
    typeof process !== "undefined" &&
    process.versions?.node &&
    !wasmUrlOrPath.startsWith("http")
  ) {
    const { readFileSync } = await import("node:fs");
    bytes = readFileSync(wasmUrlOrPath);
  } else {
    // Browser or http URL
    const response = await fetch(wasmUrlOrPath);
    if (!response.ok) {
      throw new Error(`Failed to fetch WASM: ${response.status} ${wasmUrlOrPath}`);
    }
    bytes = await response.arrayBuffer();
  }

  return loadKernelFromBuffer(new Uint8Array(bytes as ArrayBuffer));
}

/**
 * Instantiate the kernel from a pre-loaded byte buffer.  Useful for Node
 * tests where the WASM is read with `fs.readFileSync`.
 */
export async function loadKernelFromBuffer(
  wasmBytes: Uint8Array,
): Promise<Kernel> {
  // We need a two-phase init: first compile the module to inspect its imports,
  // then build host stubs that close over the instance memory, then instantiate.
  // WebAssembly.Module.imports() lets us do this without a full compile.
  //
  // In practice we always provide the full host stub table regardless of what
  // the module actually imports — extra keys in the import object are silently
  // ignored by the WebAssembly spec.

  let memory: WebAssembly.Memory | null = null;

  const hostStubs = buildHostImports(() => {
    if (!memory) throw new Error("WASM memory not yet available");
    return memory;
  });

  const importObject: WebAssembly.Imports = {
    host: hostStubs,
    env: {},
  };

  const result = await WebAssembly.instantiate(wasmBytes, importObject);
  const instance = result.instance;

  // Wire memory reference now that the instance is live.
  memory = (instance.exports as KernelExports).memory;

  return new Kernel(instance);
}

// ── Convenience: resolve canonical WASM path for Node tests ─────────────────

/**
 * Returns the absolute path to the cell-engine WASM binary, searching:
 *   1. $CELL_ENGINE_WASM env var
 *   2. <repo-root>/core/cell-engine/zig-out/bin/cell-engine.wasm
 *   3. <repo-root>/esp32-hackkit/components/semantos/wasm/cell-engine-embedded.wasm
 *
 * Throws if none are found.
 */
export function resolveWasmPath(): string {
  const envPath = process.env["CELL_ENGINE_WASM"];
  if (envPath && existsSync(envPath)) return envPath;

  // Walk up from this file to find the repo root (contains pnpm-workspace.yaml)
  let dir = dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 8; i++) {
    const candidate = resolve(dir, "core/cell-engine/zig-out/bin/cell-engine.wasm");
    if (existsSync(candidate)) return candidate;
    const embedded = resolve(
      dir,
      "esp32-hackkit/components/semantos/wasm/cell-engine-embedded.wasm",
    );
    if (existsSync(embedded)) return embedded;
    const parent = resolve(dir, "..");
    if (parent === dir) break;
    dir = parent;
  }

  throw new Error(
    "cell-engine.wasm not found. Build it with:\n  cd core/cell-engine && zig build",
  );
}

```
