---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/bun/cell-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.003206+00:00
---

# core/cell-engine/bindings/bun/cell-engine.ts

```ts
/**
 * CellEngine — typed API wrapper over raw WASM exports.
 *
 * Hides ALL pointer arithmetic. Every public method accepts and returns
 * typed objects or Uint8Array. Raw WASM pointers never leak.
 */

import type { PlexusKernelWasm } from '@semantos/protocol-types';
import { KernelError, TypeClassification, serializeCellHeader } from '@semantos/protocol-types';
import type {
  CellHeader,
  BCAInput,
  BCAOutput,
  ScriptResult,
  ContinuationInput,
  StepResult,
  VerifyResult,
  BeefVersion,
  PointerPayload,
} from './types';

// Constants from protocol
const CELL_SIZE = 1024;
const HEADER_SIZE = 256;
const PAYLOAD_SIZE = 768;
const CONTINUATION_HEADER_SIZE = 8;
const POINTER_PAYLOAD_SIZE = 90;
const POINTER_CELL_TYPE = 0x06;

// Opcode constants (Bitcoin Script)
const OP_0 = 0x00;
const OP_1 = 0x51;
const OP_PUSHDATA2 = 0x4D;
const OP_DROP = 0x75;
const OP_CHECKSIG = 0xAC;
const OP_DEREF_POINTER = 0xC8;

// Fixed memory regions for I/O (well above stack memory).
// Layout designed with generous spacing to avoid clobbering:
//   IO_HEADER/IO_PAYLOAD/IO_OUT: cell pack/unpack (3KB)
//   IO_SCRIPT/IO_UNLOCK: script loading (64KB each)
//   IO_BCA: BCA derivation (256 bytes)
//   IO_SPV: SPV verification (128KB for large BEEF envelopes)
//   IO_TX: transaction context (64KB)
//   IO_MULTICELL_OUT: multi-cell pack output (up to 256KB for 256 continuations)
const IO_BASE = 0x300000;
const IO_HEADER = IO_BASE;                          // +0x000000, 256 bytes
const IO_PAYLOAD = IO_BASE + HEADER_SIZE;            // +0x000100, 768 bytes
const IO_OUT = IO_BASE + CELL_SIZE;                  // +0x000400, 1024 bytes
const IO_SCRIPT = IO_BASE + 0x1000;                  // +0x001000, 64KB available
const IO_UNLOCK = IO_BASE + 0x11000;                 // +0x011000, 64KB available
const IO_BCA = IO_BASE + 0x21000;                    // +0x021000, 256 bytes
const IO_SPV = IO_BASE + 0x22000;                    // +0x022000, 128KB available (BUG-4 fix)
const IO_TX = IO_BASE + 0x42000;                     // +0x042000, 64KB available
const IO_MULTICELL_OUT = IO_BASE + 0x80000;          // +0x080000, 256KB available (BUG-1 fix)

function kernelErrorMessage(code: number): string {
  const name = KernelError[Math.abs(code)] ?? `UNKNOWN(${code})`;
  return `Kernel error ${code}: ${name}`;
}

export class CellEngine {
  private readonly wasm: PlexusKernelWasm & Record<string, Function>;
  readonly profile: 'full' | 'embedded';
  readonly memory: WebAssembly.Memory;

  constructor(exports: PlexusKernelWasm, profile: 'full' | 'embedded') {
    this.wasm = exports as PlexusKernelWasm & Record<string, Function>;
    this.profile = profile;
    this.memory = exports.memory;

    // Initialize kernel on construction
    const rc = exports.kernel_init();
    if (rc !== 0) {
      throw new Error(`kernel_init failed: ${kernelErrorMessage(rc)}`);
    }
  }

  // ── Private helpers ──

  private mem(): Uint8Array {
    return new Uint8Array(this.memory.buffer);
  }

  private writeBytes(ptr: number, data: Uint8Array): void {
    if (ptr + data.length > this.memory.buffer.byteLength) {
      throw new Error(
        `writeBytes out of bounds: ptr=0x${ptr.toString(16)}, len=${data.length}, ` +
        `memSize=${this.memory.buffer.byteLength}`
      );
    }
    new Uint8Array(this.memory.buffer, ptr, data.length).set(data);
  }

  private readBytes(ptr: number, len: number): Uint8Array {
    return new Uint8Array(this.memory.buffer, ptr, len).slice();
  }

  private requireFullProfile(method: string): void {
    if (this.profile === 'embedded') {
      throw new Error(`SPV not available in embedded profile: ${method}()`);
    }
  }

  // ── Cell operations (Phase 1) ──

  packCell(header: Uint8Array | CellHeader, payload: Uint8Array): Uint8Array {
    const headerBytes = header instanceof Uint8Array ? header : serializeCellHeader(header);
    if (headerBytes.length !== HEADER_SIZE) {
      throw new Error(`Header must be ${HEADER_SIZE} bytes, got ${headerBytes.length}`);
    }
    this.writeBytes(IO_HEADER, headerBytes);
    this.writeBytes(IO_PAYLOAD, payload);
    const rc = this.wasm.cell_pack(IO_HEADER, IO_PAYLOAD, payload.length, IO_OUT);
    if (rc !== 0) throw new Error(kernelErrorMessage(rc));
    return this.readBytes(IO_OUT, CELL_SIZE);
  }

  unpackCell(cell: Uint8Array): { header: Uint8Array; payload: Uint8Array; payloadLen: number } {
    if (cell.length !== CELL_SIZE) {
      throw new Error(`Cell must be ${CELL_SIZE} bytes, got ${cell.length}`);
    }
    this.writeBytes(IO_OUT, cell);
    const rc = this.wasm.cell_unpack(IO_OUT, IO_HEADER, IO_PAYLOAD);
    if (rc < 0) throw new Error(kernelErrorMessage(rc));
    return {
      header: this.readBytes(IO_HEADER, HEADER_SIZE),
      payload: this.readBytes(IO_PAYLOAD, PAYLOAD_SIZE),
      payloadLen: rc,
    };
  }

  validateMagic(cell: Uint8Array): boolean {
    if (cell.length !== CELL_SIZE) return false;
    this.writeBytes(IO_OUT, cell);
    return this.wasm.cell_validate_magic(IO_OUT) === 1;
  }

  // ── Multi-cell operations (Phase 1) ──

  packMultiCell(header: Uint8Array, payload: Uint8Array, continuations: ContinuationInput[]): Uint8Array {
    this.writeBytes(IO_HEADER, header);
    this.writeBytes(IO_PAYLOAD, payload);

    const count = continuations.length;
    // Use IO_TX region for continuation metadata (well separated from output)
    const typesPtr = IO_TX;
    const offsetsPtr = IO_TX + count;
    const sizesPtr = IO_TX + count + count * 4;
    const dataPtr = IO_TX + count + count * 8;

    const dv = new DataView(this.memory.buffer);
    let dataOffset = 0;
    for (let i = 0; i < count; i++) {
      const c = continuations[i];
      new Uint8Array(this.memory.buffer)[typesPtr + i] = c.cellType;
      dv.setUint32(offsetsPtr + i * 4, dataOffset, true);
      dv.setUint32(sizesPtr + i * 4, c.data.length, true);
      new Uint8Array(this.memory.buffer, dataPtr + dataOffset, c.data.length).set(c.data);
      dataOffset += c.data.length;
    }

    const totalOutSize = (1 + count) * CELL_SIZE;
    // Write output to dedicated multicell region (BUG-1 fix: avoids clobbering IO_SCRIPT)
    const rc = this.wasm.multicell_pack(
      IO_HEADER, IO_PAYLOAD, payload.length,
      typesPtr, offsetsPtr, sizesPtr, dataPtr, count, IO_MULTICELL_OUT
    );
    if (rc < 0) throw new Error(kernelErrorMessage(rc));
    return this.readBytes(IO_MULTICELL_OUT, totalOutSize);
  }

  unpackMultiCell(buffer: Uint8Array): number {
    this.writeBytes(IO_OUT, buffer);
    const rc = this.wasm.multicell_unpack(IO_OUT, buffer.length);
    if (rc < 0) throw new Error(kernelErrorMessage(rc));
    return rc;
  }

  // ── BCA operations (Phase 2) ──

  deriveBCA(input: BCAInput): BCAOutput {
    const sec = Math.min(input.sec ?? 2, 7);
    this.writeBytes(IO_BCA, input.publicKey);
    this.writeBytes(IO_BCA + 33, input.subnetPrefix);
    this.writeBytes(IO_BCA + 33 + 8, input.modifier);
    const outPtr = IO_BCA + 128;
    const rc = this.wasm.bca_derive(IO_BCA, IO_BCA + 33, IO_BCA + 33 + 8, sec, outPtr);
    if (rc < 0) throw new Error(kernelErrorMessage(rc));
    return {
      ipv6Address: this.readBytes(outPtr, 16),
      collisionCount: rc,
    };
  }

  verifyBCA(address: Uint8Array, input: BCAInput): boolean {
    this.writeBytes(IO_BCA, address);
    this.writeBytes(IO_BCA + 16, input.publicKey);
    this.writeBytes(IO_BCA + 16 + 33, input.subnetPrefix);
    this.writeBytes(IO_BCA + 16 + 33 + 8, input.modifier);
    return this.wasm.bca_verify(IO_BCA, IO_BCA + 16, IO_BCA + 16 + 33, IO_BCA + 16 + 33 + 8) === 1;
  }

  // ── Script execution (Phase 3) ──

  executeScript(
    lockScript: Uint8Array,
    unlockScript?: Uint8Array,
    options?: { outputIndex?: number },
  ): ScriptResult {
    this.wasm.kernel_reset();

    // OP_BRANCHONOUTPUT (0xE0): if the caller provided an outputIndex, bind it
    // to the active TxContext AFTER reset and BEFORE execute.  Spec: §3.
    if (options?.outputIndex !== undefined) {
      const rc = this.wasm.kernel_set_output_index(options.outputIndex);
      if (rc !== 0) throw new Error(kernelErrorMessage(rc));
    }

    if (unlockScript && unlockScript.length > 0) {
      this.writeBytes(IO_UNLOCK, unlockScript);
      const rc = this.wasm.kernel_load_unlock(IO_UNLOCK, unlockScript.length);
      if (rc !== 0) throw new Error(kernelErrorMessage(rc));
    }

    this.writeBytes(IO_SCRIPT, lockScript);
    const loadRc = this.wasm.kernel_load_script(IO_SCRIPT, lockScript.length);
    if (loadRc !== 0) throw new Error(kernelErrorMessage(loadRc));

    const rc = this.wasm.kernel_execute();
    return {
      success: rc === 0,
      typeClassification: this.wasm.kernel_get_type_class(),
      opcodeCount: this.wasm.kernel_get_opcount(),
      error: rc !== 0 ? kernelErrorMessage(rc) : null,
    };
  }

  step(): StepResult {
    const rc = this.wasm.kernel_step();
    return {
      status: rc,
      pc: this.wasm.kernel_get_pc(),
      currentOp: this.wasm.kernel_get_current_op(),
    };
  }

  getPC(): number {
    return this.wasm.kernel_get_pc();
  }

  getCurrentOp(): number {
    return this.wasm.kernel_get_current_op();
  }

  checkLinearity(): number {
    return this.wasm.kernel_get_type_class();
  }

  setEnforcement(enabled: boolean): void {
    this.wasm.kernel_set_enforcement(enabled ? 1 : 0);
  }

  // ── Stack inspection (Phase 3) ──

  stackDepth(): number {
    return this.wasm.kernel_stack_depth();
  }

  stackPeek(index: number): Uint8Array {
    const length = this.wasm.kernel_stack_value_length(index);
    if (length === 0) return new Uint8Array(0);
    const ptr = this.wasm.kernel_stack_peek(index);
    if (ptr === 0) return new Uint8Array(0);
    return this.readBytes(ptr, length);
  }

  altStackDepth(): number {
    return this.wasm.kernel_alt_stack_depth();
  }

  altStackPeek(index: number): Uint8Array {
    const length = this.wasm.kernel_alt_stack_value_length(index);
    if (length === 0) return new Uint8Array(0);
    const ptr = this.wasm.kernel_alt_stack_peek(index);
    if (ptr === 0) return new Uint8Array(0);
    return this.readBytes(ptr, length);
  }

  // ── Transaction context (Phase 3) ──

  loadTxContext(rawTx: Uint8Array, inputIndex: number, inputValue: bigint): void {
    this.writeBytes(IO_TX, rawTx);
    const rc = this.wasm.kernel_load_tx_context(IO_TX, rawTx.length, inputIndex, inputValue);
    if (rc !== 0) throw new Error(kernelErrorMessage(rc));
  }

  /**
   * Set the current output index exposed to scripts via OP_BRANCHONOUTPUT (0xE0).
   * Runtime-injected per script invocation.  See
   * docs/design/OP-BRANCHONOUTPUT-SPEC.md §3.
   *
   * If no TxContext has been loaded, a default one is initialized first.
   */
  setOutputIndex(outputIndex: number): void {
    const rc = this.wasm.kernel_set_output_index(outputIndex);
    if (rc !== 0) throw new Error(kernelErrorMessage(rc));
  }

  // ── SPV verification (Phase 5 — full profile only) ──

  verifyBEEF(beefBytes: Uint8Array, txid: Uint8Array): VerifyResult {
    this.requireFullProfile('verifyBEEF');
    this.writeBytes(IO_SPV, beefBytes);
    this.writeBytes(IO_SPV + beefBytes.length, txid);
    const rc = this.wasm.kernel_verify_beef!(IO_SPV, beefBytes.length, IO_SPV + beefBytes.length);
    return { valid: rc === 0, errorCode: rc };
  }

  verifyBEEFWithSPV(beefBytes: Uint8Array, txid: Uint8Array, trustedRoots: Uint8Array[]): VerifyResult {
    this.requireFullProfile('verifyBEEFWithSPV');
    this.writeBytes(IO_SPV, beefBytes);
    const txidPtr = IO_SPV + beefBytes.length;
    this.writeBytes(txidPtr, txid);
    const rootsPtr = txidPtr + 32;
    for (let i = 0; i < trustedRoots.length; i++) {
      this.writeBytes(rootsPtr + i * 32, trustedRoots[i]);
    }
    const fn = this.wasm.kernel_verify_beef_spv;
    if (!fn) throw new Error('kernel_verify_beef_spv not available');
    const rc = fn(IO_SPV, beefBytes.length, txidPtr, rootsPtr, trustedRoots.length);
    return { valid: rc === 0, errorCode: rc };
  }

  verifyBUMP(proofBytes: Uint8Array, txid: Uint8Array, merkleRoot: Uint8Array): VerifyResult {
    this.requireFullProfile('verifyBUMP');
    this.writeBytes(IO_SPV, proofBytes);
    this.writeBytes(IO_SPV + proofBytes.length, txid);
    this.writeBytes(IO_SPV + proofBytes.length + 32, merkleRoot);
    const rc = this.wasm.kernel_verify_bump!(IO_SPV, proofBytes.length, IO_SPV + proofBytes.length, IO_SPV + proofBytes.length + 32);
    return { valid: rc === 0, errorCode: rc };
  }

  beefVersion(data: Uint8Array): BeefVersion {
    this.requireFullProfile('beefVersion');
    this.writeBytes(IO_SPV, data);
    const rc = this.wasm.kernel_beef_version!(IO_SPV, data.length);
    return { version: rc };
  }

  // ── Capability tokens (Phase 5 — both profiles) ──

  verifyCapability(
    lockScript: Uint8Array,
    ownerPubkey: Uint8Array,
    capType: number,
    domainFlag: number,
    currentTime: number,
  ): VerifyResult {
    this.writeBytes(IO_SCRIPT, lockScript);
    this.writeBytes(IO_SCRIPT + lockScript.length, ownerPubkey);
    const rc = this.wasm.kernel_verify_capability(
      IO_SCRIPT, lockScript.length,
      IO_SCRIPT + lockScript.length,
      capType, domainFlag, currentTime,
    );
    return { valid: rc === 0, errorCode: rc };
  }

  // ── Kernel interface (low-level) ──

  kernelInit(): void {
    const rc = this.wasm.kernel_init();
    if (rc !== 0) throw new Error(kernelErrorMessage(rc));
  }

  kernelReset(): void {
    this.wasm.kernel_reset();
  }

  kernelGetOpcount(): number {
    return this.wasm.kernel_get_opcount();
  }

  kernelGetError(): string {
    const ptr = this.wasm.kernel_get_error();
    if (ptr === 0) return '';
    const mem = new Uint8Array(this.memory.buffer);
    let end = ptr;
    while (end < mem.length && mem[end] !== 0) end++;
    return new TextDecoder().decode(mem.slice(ptr, end));
  }

  // ── Octave memory (Phase 6 — Tier B) ──

  createPointerCell(payload: PointerPayload): Uint8Array {
    const cell = new Uint8Array(CELL_SIZE);

    // Continuation header (8 bytes)
    cell[0] = POINTER_CELL_TYPE;
    // cell_index = 1 (LE u16)
    cell[1] = 1;
    cell[2] = 0;
    // total_cells = 1 (LE u16)
    cell[3] = 1;
    cell[4] = 0;
    // payload_size = 90 (LE u16)
    cell[5] = POINTER_PAYLOAD_SIZE;
    cell[6] = 0;
    // reserved = 0
    cell[7] = 0;

    // Pointer payload (90 bytes starting at offset 8)
    const p = 8;
    cell[p] = payload.octave;
    // slot (LE u16)
    cell[p + 1] = payload.slot & 0xFF;
    cell[p + 2] = (payload.slot >> 8) & 0xFF;
    // offset (LE u32)
    cell[p + 3] = payload.offset & 0xFF;
    cell[p + 4] = (payload.offset >> 8) & 0xFF;
    cell[p + 5] = (payload.offset >> 16) & 0xFF;
    cell[p + 6] = (payload.offset >> 24) & 0xFF;
    // pad byte at p+7 = 0
    // content_hash (32 bytes)
    if (payload.contentHash.length === 32) {
      cell.set(payload.contentHash, p + 8);
    }
    // type_hash (32 bytes)
    if (payload.typeHash.length === 32) {
      cell.set(payload.typeHash, p + 40);
    }
    // total_size (LE u64)
    const dv = new DataView(cell.buffer);
    dv.setBigUint64(p + 72, payload.totalSize, true);
    // flags
    cell[p + 80] = payload.flags;
    // fragment_count (LE u16)
    cell[p + 81] = payload.fragmentCount & 0xFF;
    cell[p + 82] = (payload.fragmentCount >> 8) & 0xFF;
    // reserved 7 bytes = 0

    return cell;
  }

  parsePointerCell(cell: Uint8Array): PointerPayload {
    if (cell.length !== CELL_SIZE) {
      throw new Error(`Cell must be ${CELL_SIZE} bytes`);
    }
    if (cell[0] !== POINTER_CELL_TYPE) {
      throw new Error(`Not a pointer cell: type byte is 0x${cell[0].toString(16)}`);
    }

    const p = 8;
    const dv = new DataView(cell.buffer, cell.byteOffset, cell.byteLength);
    return {
      octave: cell[p],
      slot: cell[p + 1] | (cell[p + 2] << 8),
      offset: cell[p + 3] | (cell[p + 4] << 8) | (cell[p + 5] << 16) | (cell[p + 6] << 24),
      contentHash: cell.slice(p + 8, p + 40),
      typeHash: cell.slice(p + 40, p + 72),
      totalSize: dv.getBigUint64(p + 72, true),
      flags: cell[p + 80],
      fragmentCount: cell[p + 81] | (cell[p + 82] << 8),
    };
  }

  isPointerCell(cell: Uint8Array): boolean {
    return cell.length === CELL_SIZE && cell[0] === POINTER_CELL_TYPE;
  }

  derefPointer(pointerCell: Uint8Array): Uint8Array {
    if (!this.isPointerCell(pointerCell)) {
      throw new Error('Not a pointer cell');
    }

    // Push the pointer cell onto the stack via unlock script,
    // then execute OP_DEREF_POINTER + OP_1 as lock script.
    // Build unlock: PUSHDATA2 + 1024 bytes
    const unlock = new Uint8Array(3 + CELL_SIZE);
    unlock[0] = OP_PUSHDATA2;
    unlock[1] = 0x00; // 1024 & 0xFF
    unlock[2] = 0x04; // 1024 >> 8
    unlock.set(pointerCell, 3);

    // Lock: OP_DEREF_POINTER (fetches cell onto stack) + OP_1 (truthy top)
    const lock = new Uint8Array([OP_DEREF_POINTER, OP_1]);

    this.wasm.kernel_reset();

    this.writeBytes(IO_UNLOCK, unlock);
    const ulRc = this.wasm.kernel_load_unlock(IO_UNLOCK, unlock.length);
    if (ulRc !== 0) throw new Error(kernelErrorMessage(ulRc));

    this.writeBytes(IO_SCRIPT, lock);
    const lRc = this.wasm.kernel_load_script(IO_SCRIPT, lock.length);
    if (lRc !== 0) throw new Error(kernelErrorMessage(lRc));

    const rc = this.wasm.kernel_execute();
    if (rc !== 0) throw new Error(kernelErrorMessage(rc));

    // The fetched cell should be on the stack (under OP_TRUE's result).
    // Stack: [fetched_cell, TRUE]. Index 1 = fetched cell.
    const depth = this.wasm.kernel_stack_depth();
    if (depth < 2) throw new Error('derefPointer: expected 2 items on stack after execution');
    const ptr = this.wasm.kernel_stack_peek(1);
    if (ptr === 0) throw new Error('derefPointer: stack peek returned null');
    return this.readBytes(ptr, CELL_SIZE);
  }
}

```
