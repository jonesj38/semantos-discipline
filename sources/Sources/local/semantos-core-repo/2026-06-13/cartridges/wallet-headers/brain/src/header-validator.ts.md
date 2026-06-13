---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.653986+00:00
---

# cartridges/wallet-headers/brain/src/header-validator.ts

```ts
// Phase WH3 — Trustless SPV: header validator (browser side).
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH3) and §11.
//
// Validates 80-byte BSV block headers via PoW + chain rules. Two
// implementations:
//
//   1. WasmHeaderValidator — calls into kernel_header_* exports. The browser
//      bundle loads cell-engine-embedded.wasm (containing headers.zig) and
//      forwards each candidate header to the WASM verifier. This is the
//      "WASM-resident PoW verifier" property the spec emphasizes — the
//      validation code is bit-identical to the sovereign-node binary thanks
//      to WASM-MANIFEST.
//
//   2. JsHeaderValidator — pure-TS reimplementation using @noble/hashes for
//      SHA256d. Used as a fallback when WASM isn't available (e.g., bun test
//      without the cell-engine artifact built) and as a differential check
//      against the WASM impl. They MUST agree on every input.
//
// This module is imported by:
//   • header-fetcher.ts (WH3) — validates each header in a batch fetch
//   • header-tip.ts     (WH4) — validates each pushed tip header
//   • header-store.ts   (WH3) — invariant: nothing reaches the store unverified

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

export const HEADER_BYTES = 80;
export const POW_LIMIT_BITS = 0x1d00ffff; // BSV mainnet powLimit
export const REGTEST_BITS = 0x207fffff; // test/regtest target — entire 256-bit space minus epsilon

/// Decoded view of a BSV block header. Hashes are stored in *internal byte
/// order* (the same byte order SHA256 produces). Display order is reversed.
export interface DecodedHeader {
  version: number;
  prevHash: Uint8Array; // 32 bytes, internal byte order
  merkleRoot: Uint8Array; // 32 bytes, internal byte order
  timestamp: number;
  bits: number;
  nonce: number;
  /** Convenience: SHA256d of the serialized header (internal byte order). */
  hash: Uint8Array;
}

export interface ValidateContext {
  parent: Uint8Array; // 80 bytes
  parentHeight: number;
  /** Up to 11 prior timestamps for MTP. Order doesn't matter. */
  prevTimestamps: number[];
  /** Defaults to mainnet powLimit; tests pass REGTEST_BITS. */
  powLimitBits?: number;
  /** Optional clock cap (≤ 2 hours future). 0 disables. */
  nowSeconds?: number;
}

export type ValidateError =
  | 'too_short'
  | 'too_long'
  | 'invalid_bits'
  | 'insufficient_pow'
  | 'prev_hash_mismatch'
  | 'timestamp_too_early'
  | 'timestamp_too_far_future'
  | 'wrong_difficulty';

export interface HeaderValidator {
  /** Decode an 80-byte raw header (no validation). */
  decode(raw: Uint8Array): DecodedHeader;
  /** Hash an 80-byte raw header — sha256d(raw), internal byte order. */
  hash(raw: Uint8Array): Uint8Array;
  /** Returns true iff sha256d(raw) < target_from(bits). */
  satisfiesPoW(raw: Uint8Array): boolean;
  /** Validate `candidate` against `parent` + chain context. Returns
   *  null on success, or an error tag. */
  validate(candidate: Uint8Array, ctx: ValidateContext): ValidateError | null;
}

// ───────────────────────────────────────────────────────────────────────
// Pure-JS implementation
// ───────────────────────────────────────────────────────────────────────

function sha256d(data: Uint8Array): Uint8Array {
  return nobleSha256(nobleSha256(data));
}

function readU32LE(buf: Uint8Array, off: number): number {
  return (
    buf[off] |
    (buf[off + 1] << 8) |
    (buf[off + 2] << 16) |
    (buf[off + 3] * 0x01000000)
  );
}

function decodeHeader(raw: Uint8Array): DecodedHeader {
  if (raw.length !== HEADER_BYTES) throw new Error(`header: bad len ${raw.length}`);
  return {
    version: readU32LE(raw, 0),
    prevHash: raw.slice(4, 36),
    merkleRoot: raw.slice(36, 68),
    timestamp: readU32LE(raw, 68),
    bits: readU32LE(raw, 72),
    nonce: readU32LE(raw, 76),
    hash: sha256d(raw),
  };
}

/**
 * Decode `bits` (compact-form) into a 32-byte big-endian target.
 * Returns null on malformed encoding (negative bit set, or mantissa overflow).
 */
export function targetFromBits(bits: number): Uint8Array | null {
  const exponent = (bits >>> 24) & 0xff;
  const mantissa = bits & 0x007fffff;
  const negative = (bits & 0x00800000) !== 0;
  if (negative && mantissa !== 0) return null;
  const out = new Uint8Array(32);
  if (mantissa === 0) return out;
  if (exponent <= 3) {
    const shift = (3 - exponent) * 8;
    const small = mantissa >>> shift;
    out[29] = (small >>> 16) & 0xff;
    out[30] = (small >>> 8) & 0xff;
    out[31] = small & 0xff;
    return out;
  }
  if (exponent > 32) return null;
  const start = 32 - exponent;
  if (start + 3 > 32) return null;
  out[start + 0] = (mantissa >>> 16) & 0xff;
  out[start + 1] = (mantissa >>> 8) & 0xff;
  out[start + 2] = mantissa & 0xff;
  return out;
}

/** 256-bit unsigned compare on big-endian byte arrays. */
function cmp32(a: Uint8Array, b: Uint8Array): number {
  for (let i = 0; i < 32; i++) {
    if (a[i] < b[i]) return -1;
    if (a[i] > b[i]) return 1;
  }
  return 0;
}

function reverseBytes(b: Uint8Array): Uint8Array {
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b[b.length - 1 - i];
  return out;
}

/** Median of up to 11 timestamps (BIP-113-style MTP). */
export function medianTimePast(prevTimestamps: number[]): number {
  if (prevTimestamps.length === 0) return 0;
  const slice = prevTimestamps.slice(0, 11).sort((a, b) => a - b);
  return slice[Math.floor(slice.length / 2)];
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export class JsHeaderValidator implements HeaderValidator {
  decode(raw: Uint8Array): DecodedHeader {
    return decodeHeader(raw);
  }

  hash(raw: Uint8Array): Uint8Array {
    if (raw.length !== HEADER_BYTES) throw new Error(`header: bad len ${raw.length}`);
    return sha256d(raw);
  }

  satisfiesPoW(raw: Uint8Array): boolean {
    const dec = decodeHeader(raw);
    const target = targetFromBits(dec.bits);
    if (!target) return false;
    // dec.hash is internal byte order (LE). Compare against BE target by
    // reversing the hash.
    const hashBe = reverseBytes(dec.hash);
    return cmp32(hashBe, target) < 0;
  }

  validate(candidate: Uint8Array, ctx: ValidateContext): ValidateError | null {
    if (candidate.length < HEADER_BYTES) return 'too_short';
    if (candidate.length > HEADER_BYTES) return 'too_long';
    if (ctx.parent.length !== HEADER_BYTES) return 'too_short';

    const cand = decodeHeader(candidate);
    const parent = decodeHeader(ctx.parent);

    // 1. Chain linkage
    if (!bytesEqual(cand.prevHash, parent.hash)) return 'prev_hash_mismatch';

    // 2. Difficulty (pre-DAA only — for v0.1 we only check vs powLimit; the
    //    full cw-144 DAA is in the WASM verifier and runs there for mainnet
    //    sync. The JS validator is a fallback differential, so it doesn't
    //    re-implement DAA.)
    const powLimitBits = ctx.powLimitBits ?? POW_LIMIT_BITS;
    const candidateHeight = ctx.parentHeight + 1;
    const DAA_MIN_HEIGHT = 147;
    if (candidateHeight < DAA_MIN_HEIGHT) {
      if (cand.bits !== powLimitBits) return 'wrong_difficulty';
    }
    // For candidateHeight ≥ DAA_MIN_HEIGHT, JS validator currently accepts
    // any valid-form bits with sufficient PoW. Mainnet sync MUST go through
    // WasmHeaderValidator. (Documented; tests pin this contract.)

    // 3. PoW
    if (!this.satisfiesPoW(candidate)) return 'insufficient_pow';

    // 4. MTP
    const mtp = medianTimePast(ctx.prevTimestamps);
    if (cand.timestamp <= mtp) return 'timestamp_too_early';

    // 5. Clock cap (optional)
    if (ctx.nowSeconds && ctx.nowSeconds !== 0) {
      const futureLimit = ctx.nowSeconds + 2 * 60 * 60;
      if (cand.timestamp > futureLimit) return 'timestamp_too_far_future';
    }

    return null;
  }
}

// ───────────────────────────────────────────────────────────────────────
// WASM-backed implementation
// ───────────────────────────────────────────────────────────────────────

interface KernelExports {
  memory: WebAssembly.Memory;
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
  /** Optional WASM-side scratch allocator. If absent, we use a fixed
   *  scratch region at offset 0 — for v0.1 we ship a small stack buffer. */
}

const ERR_MAP: Record<number, ValidateError> = {
  [-101]: 'too_short',
  [-102]: 'too_long',
  [-103]: 'invalid_bits',
  [-104]: 'insufficient_pow',
  [-105]: 'prev_hash_mismatch',
  [-106]: 'timestamp_too_early',
  [-107]: 'timestamp_too_far_future',
  [-108]: 'wrong_difficulty',
};

/**
 * Validator backed by the cell-engine WASM kernel's `kernel_header_*` exports
 * (defined in `core/cell-engine/src/main.zig`).
 *
 * The kernel doesn't expose a malloc-style allocator for scratch, so we
 * carve out a small region at the top of WASM memory for the validate-call
 * inputs. Each call writes parent / candidate / prev_ts contiguously, then
 * issues the kernel call, then ignores the buffer.
 *
 * NOTE: this region must not collide with the kernel's own globals. The
 * kernel reserves linear memory for its arena (`g_arena_buf`, 64KB) and
 * stack; WASM linear memory is at minimum 128 pages = 8MB, so we use the
 * last 1KB. Kernel globals are placed at low addresses by the linker — well
 * separated.
 */
export class WasmHeaderValidator implements HeaderValidator {
  private readonly exports: KernelExports;
  private readonly scratchBase: number;
  private readonly fallback: JsHeaderValidator;

  constructor(exports: KernelExports, opts: { scratchBase?: number } = {}) {
    this.exports = exports;
    // Default: top of the first MB minus 1KB. Kernel arena is at module-level
    // .bss; linker places it well below this in practice.
    this.scratchBase = opts.scratchBase ?? 1024 * 1024 - 1024;
    this.fallback = new JsHeaderValidator();
  }

  decode(raw: Uint8Array): DecodedHeader {
    // Hash via WASM, decode fields in JS (cheap).
    if (raw.length !== HEADER_BYTES) throw new Error('header: bad len');
    const mem = new Uint8Array(this.exports.memory.buffer);
    mem.set(raw, this.scratchBase);
    const out = this.scratchBase + HEADER_BYTES;
    this.exports.kernel_header_compute_hash(this.scratchBase, out);
    const hash = mem.slice(out, out + 32);
    return {
      version: readU32LE(raw, 0),
      prevHash: raw.slice(4, 36),
      merkleRoot: raw.slice(36, 68),
      timestamp: readU32LE(raw, 68),
      bits: readU32LE(raw, 72),
      nonce: readU32LE(raw, 76),
      hash,
    };
  }

  hash(raw: Uint8Array): Uint8Array {
    if (raw.length !== HEADER_BYTES) throw new Error('header: bad len');
    const mem = new Uint8Array(this.exports.memory.buffer);
    mem.set(raw, this.scratchBase);
    const out = this.scratchBase + HEADER_BYTES;
    this.exports.kernel_header_compute_hash(this.scratchBase, out);
    return mem.slice(out, out + 32);
  }

  satisfiesPoW(raw: Uint8Array): boolean {
    if (raw.length !== HEADER_BYTES) return false;
    const mem = new Uint8Array(this.exports.memory.buffer);
    mem.set(raw, this.scratchBase);
    return this.exports.kernel_header_verify_pow(this.scratchBase) === 1;
  }

  validate(candidate: Uint8Array, ctx: ValidateContext): ValidateError | null {
    if (candidate.length < HEADER_BYTES) return 'too_short';
    if (candidate.length > HEADER_BYTES) return 'too_long';
    if (ctx.parent.length !== HEADER_BYTES) return 'too_short';

    const mem = new Uint8Array(this.exports.memory.buffer);
    const dv = new DataView(this.exports.memory.buffer);
    let off = this.scratchBase;
    mem.set(ctx.parent, off);
    const parentPtr = off;
    off += HEADER_BYTES;
    mem.set(candidate, off);
    const candidatePtr = off;
    off += HEADER_BYTES;
    const tsCount = Math.min(ctx.prevTimestamps.length, 11);
    const prevTsPtr = off;
    for (let i = 0; i < tsCount; i++) {
      dv.setUint32(off, ctx.prevTimestamps[i], true);
      off += 4;
    }

    const rc = this.exports.kernel_header_validate(
      parentPtr,
      candidatePtr,
      ctx.parentHeight,
      prevTsPtr,
      tsCount,
      ctx.powLimitBits ?? POW_LIMIT_BITS,
      ctx.nowSeconds ?? 0,
    );
    if (rc === 0) return null;
    return ERR_MAP[rc] ?? 'invalid_bits';
  }
}

```
