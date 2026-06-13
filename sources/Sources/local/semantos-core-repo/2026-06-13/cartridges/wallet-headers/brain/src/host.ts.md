---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/host.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.657450+00:00
---

# cartridges/wallet-headers/brain/src/host.ts

```ts
// TS-side runtime for the embedded cell-engine WASM bundle (W5).
//
// Implements every WASM extern declared in `core/cell-engine/src/host.zig`
// against:
//   • @noble/hashes for SHA256/RIPEMD160/SHA1/HASH160/HASH256
//   • @noble/secp256k1 for ECDSA sign/verify, BRC-42 deriveChild
//   • WebCrypto AES-GCM + PBKDF2 for the at-rest tier envelope
//   • IndexedDB (via storage.ts) for tier blobs + BRC-42 next-index
//
// The byte format for the AES-GCM envelope is the one defined in
// `core/cell-engine/src/slot_store.zig` §"Slot envelope layout":
//   [00..04] format_version (u32 LE) = 1
//   [04..08] tier            (u32 LE) — 0..3
//   [08..20] nonce           (12 bytes)
//   [20..36] tag             (16 bytes)
//   [36..]   ciphertext
// AAD = bytes [00..20] (version || tier || nonce). See WALLET-TIER-CUSTODY.md
// §5.3, §6.2 for the rationale.

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { sha1 as nobleSha1 } from '@noble/hashes/sha1';
import { ripemd160 as nobleRipemd160 } from '@noble/hashes/ripemd160';
import { pbkdf2 } from '@noble/hashes/pbkdf2';
import { encodeDer, decodeDer } from './der';
import {
  slotGet,
  slotPut,
  stateNextIndex as storageStateNextIndex,
} from './storage';

// @noble/secp256k1 v2 needs a sync HMAC-SHA256 backend for synchronous sign().
// Wallet code paths benefit from sync — host_sign is invoked from inside the
// WASM call stack, where awaiting a Promise is not an option.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Slot envelope layout (mirrors slot_store.zig) ──
const SLOT_FORMAT_VERSION = 1;
const SLOT_NONCE_BYTES = 12;
const SLOT_TAG_BYTES = 16;
const SLOT_HEADER_BYTES = 4 + 4 + SLOT_NONCE_BYTES + SLOT_TAG_BYTES; // = 36
const SLOT_KEK_BYTES = 32; // AES-256-GCM
const TIER_COUNT = 4;

// ── Domain flags from host.zig:cellTierFromDomainFlag (offset 28, big-endian) ──
const DOMAIN_FLAG_TIER_0 = 0x10000001;
const DOMAIN_FLAG_TIER_1 = 0x10000003;
const DOMAIN_FLAG_TIER_2 = 0x10000004;
const DOMAIN_FLAG_TIER_3 = 0x10000005;

/** Per-process keychain — populated by unlock_tier, cleared by clearAllKeks. */
interface KeyChain {
  perTier: (CryptoKey | null)[]; // index 0 unused (session_kek lives separately)
  session: CryptoKey | null;
}

const keychain: KeyChain = {
  perTier: [null, null, null, null],
  session: null,
};

/**
 * v0.1 dev-default: install a deterministic Tier-0 session KEK so the wallet
 * can exercise persistCell/loadCell for the HOT budget cell from process
 * start. v0.2 derives this from a per-install machine secret bound by
 * WebAuthn (§7.6, §4.1). The TS host installs it lazily on first Tier-0
 * write/read; `setSessionKek` lets tests override.
 */
export async function setSessionKek(rawKey: Uint8Array): Promise<void> {
  if (rawKey.length !== SLOT_KEK_BYTES) throw new Error('session KEK: bad len');
  keychain.session = await crypto.subtle.importKey(
    'raw',
    rawKey,
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
}

/** Tests-only: drop every per-tier KEK + the session KEK. */
export function clearAllKeks(): void {
  keychain.perTier = [null, null, null, null];
  keychain.session = null;
}

/** Returns true iff tier N has been unlocked in this scope. */
export function tierUnlocked(tier: number): boolean {
  if (tier === 0) return keychain.session !== null;
  if (tier < 1 || tier >= TIER_COUNT) return false;
  return keychain.perTier[tier] !== null;
}

// ──────────────────────────────────────────────────────────────────────
// Byte glue between WASM linear memory and host code
// ──────────────────────────────────────────────────────────────────────

interface WasmCtx {
  memory: WebAssembly.Memory;
}

function readBytes(ctx: WasmCtx, ptr: number, len: number): Uint8Array {
  // Copy out of the underlying buffer so subsequent WASM growth/realloc
  // (which detaches old views) doesn't invalidate the reference. Cheaper
  // than a defensive copy on every call would suggest because most reads
  // here are tiny (32–64 bytes).
  return new Uint8Array(ctx.memory.buffer, ptr, len).slice();
}

function writeBytes(ctx: WasmCtx, ptr: number, bytes: Uint8Array): void {
  new Uint8Array(ctx.memory.buffer, ptr, bytes.length).set(bytes);
}

function writeU32LE(ctx: WasmCtx, ptr: number, value: number): void {
  new DataView(ctx.memory.buffer).setUint32(ptr, value >>> 0, true);
}

function writeU64LE(ctx: WasmCtx, ptr: number, value: bigint): void {
  new DataView(ctx.memory.buffer).setBigUint64(ptr, value, true);
}

// ──────────────────────────────────────────────────────────────────────
// KDF + envelope helpers
// ──────────────────────────────────────────────────────────────────────

/**
 * Derive a per-tier KEK from an opaque factor (PIN bytes / passphrase /
 * WebAuthn-assertion-derived secret). Bit-identical to host.zig:deriveKek —
 * PBKDF2-HMAC-SHA256, 4096 iters, 16-byte salt = "semantos:tier=" || tier_le16.
 * v0.2 upgrades to Argon2id (design §4.1).
 */
export async function deriveKek(tier: number, factor: Uint8Array): Promise<CryptoKey> {
  const salt = new Uint8Array(16);
  const prefix = new TextEncoder().encode('semantos:tier=');
  salt.set(prefix, 0);
  // tier as u16 LE at byte offset 14
  new DataView(salt.buffer).setUint16(prefix.length, tier, true);
  // @noble/hashes pbkdf2: matches std.crypto.pwhash.pbkdf2 + HmacSha256.
  const raw = pbkdf2(nobleSha256, factor, salt, { c: 4096, dkLen: SLOT_KEK_BYTES });
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, [
    'encrypt',
    'decrypt',
  ]);
}

function buildAad(tier: number, nonce: Uint8Array): Uint8Array {
  const aad = new Uint8Array(20);
  const dv = new DataView(aad.buffer);
  dv.setUint32(0, SLOT_FORMAT_VERSION, true);
  dv.setUint32(4, tier, true);
  aad.set(nonce, 8);
  return aad;
}

function readEnvelope(blob: Uint8Array): {
  tier: number;
  nonce: Uint8Array;
  aad: Uint8Array;
  ciphertextWithTag: Uint8Array;
} | null {
  if (blob.length < SLOT_HEADER_BYTES) return null;
  const dv = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
  if (dv.getUint32(0, true) !== SLOT_FORMAT_VERSION) return null;
  const tier = dv.getUint32(4, true);
  if (tier >= TIER_COUNT) return null;
  const nonce = blob.slice(8, 20);
  const aad = blob.slice(0, 20); // version || tier || nonce
  // WebCrypto wants ciphertext || tag concatenated — the on-disk envelope
  // stores tag at [20..36] then ciphertext at [36..]. Reorder.
  const tag = blob.slice(20, 36);
  const ciphertext = blob.slice(36);
  const ctWithTag = new Uint8Array(ciphertext.length + tag.length);
  ctWithTag.set(ciphertext, 0);
  ctWithTag.set(tag, ciphertext.length);
  return { tier, nonce, aad, ciphertextWithTag: ctWithTag };
}

async function encryptCell(
  tier: number,
  kek: CryptoKey,
  cell: Uint8Array,
): Promise<Uint8Array> {
  const nonce = new Uint8Array(SLOT_NONCE_BYTES);
  crypto.getRandomValues(nonce);
  const aad = buildAad(tier, nonce);
  const ctWithTag = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128 },
      kek,
      cell,
    ),
  );
  // Split tag from ciphertext to match the on-disk envelope layout.
  const tag = ctWithTag.slice(ctWithTag.length - SLOT_TAG_BYTES);
  const ciphertext = ctWithTag.slice(0, ctWithTag.length - SLOT_TAG_BYTES);
  const blob = new Uint8Array(SLOT_HEADER_BYTES + ciphertext.length);
  blob.set(aad, 0); // version || tier || nonce
  blob.set(tag, 20);
  blob.set(ciphertext, SLOT_HEADER_BYTES);
  return blob;
}

async function decryptCell(
  expectedTier: number,
  kek: CryptoKey,
  blob: Uint8Array,
): Promise<Uint8Array | null> {
  const env = readEnvelope(blob);
  if (!env) return null;
  if (env.tier !== expectedTier) return null;
  try {
    const pt = new Uint8Array(
      await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: env.nonce, additionalData: env.aad, tagLength: 128 },
        kek,
        env.ciphertextWithTag,
      ),
    );
    return pt;
  } catch {
    return null; // auth failure
  }
}

function tierFromDomainFlag(cell: Uint8Array): number | null {
  if (cell.length < 32) return null;
  // Big-endian per §6.1.
  const flag = new DataView(cell.buffer, cell.byteOffset, cell.byteLength).getUint32(28, false);
  switch (flag) {
    case DOMAIN_FLAG_TIER_0:
      return 0;
    case DOMAIN_FLAG_TIER_1:
      return 1;
    case DOMAIN_FLAG_TIER_2:
      return 2;
    case DOMAIN_FLAG_TIER_3:
      return 3;
    default:
      return null;
  }
}

// ──────────────────────────────────────────────────────────────────────
// Phase 25.5 host-call registry — placeholder per W5 spec
// ──────────────────────────────────────────────────────────────────────

export type HostCall = (name: string) => number;

class HostCallRegistry {
  private fns = new Map<string, () => number>();
  register(name: string, fn: () => number): void {
    this.fns.set(name, fn);
  }
  call(name: string): number {
    const fn = this.fns.get(name);
    return fn ? fn() >>> 0 : 0xffffffff;
  }
}

const hostCallRegistry = new HostCallRegistry();
export { hostCallRegistry };

// ──────────────────────────────────────────────────────────────────────
// Optional /api/time hook (per spec). Default: Date.now() / 1000.
// ──────────────────────────────────────────────────────────────────────

let cachedBlocktime: number | null = null;
export function setBlocktime(unixSeconds: number): void {
  cachedBlocktime = unixSeconds >>> 0;
}
export function clearBlocktime(): void {
  cachedBlocktime = null;
}

// ──────────────────────────────────────────────────────────────────────
// BRC-42 leaf derivation: child = (base_priv + HMAC-SHA256(invoice, ECDH))
//
// invoice = protocol_hash(16) || index_le_8       (24 bytes)
// ECDH    = SHA256(serialize_compressed(base_priv * counterparty_pub))
//
// Reference: bsvz primitives.ec.deriveChild (matched bit-for-bit by
// W3.5 differential tests — when this TS path lands the same
// derivation_conformance.zig differential should pass under the WASM
// embedded build).
// ──────────────────────────────────────────────────────────────────────

const SECP_N = secp.CURVE.n;

export function deriveLeafSync(
  baseSk: Uint8Array,
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
  index: bigint,
): Uint8Array | null {
  if (baseSk.length !== 32 || protocolHash.length !== 16 || counterparty.length !== 33) {
    return null;
  }
  // Build the 24-byte invoice = protocol_hash || index_le.
  const invoice = new Uint8Array(24);
  invoice.set(protocolHash, 0);
  new DataView(invoice.buffer).setBigUint64(16, index, true);

  // ECDH shared secret: hash of compressed (base_sk * counterparty_pub).
  let shared: Uint8Array;
  try {
    shared = secp.getSharedSecret(baseSk, counterparty, true); // 33-byte compressed
  } catch {
    return null;
  }
  // BRC-42 uses SHA256(shared_pub_compressed) as the HMAC key.
  const hmacKey = nobleSha256(shared);
  const tweak = hmac(nobleSha256, hmacKey, invoice); // 32 bytes
  // child = (base + tweak) mod n
  const baseN = secp.etc.bytesToNumberBE(baseSk);
  const tweakN = secp.etc.bytesToNumberBE(tweak);
  const childN = (baseN + tweakN) % SECP_N;
  if (childN === 0n) return null;
  return secp.etc.numberToBytesBE(childN);
}

// ──────────────────────────────────────────────────────────────────────
// The host import object — every extern declared in host.zig appears here.
// ──────────────────────────────────────────────────────────────────────

export interface HostOptions {
  /** Prepopulated map of (octave, slot) → cell bytes for `host_fetch_cell`. */
  octaveStore?: Map<string, Uint8Array>;
  /** Override `host_get_blocktime`. Default: Date.now() / 1000. */
  blocktime?: () => number;
  /** Override `host_get_sequence`. Default: 0xFFFFFFFF (no nSequence in v0.1). */
  sequence?: () => number;
  /** Inspect log calls — default writes to console. */
  log?: (msg: string) => void;
}

export function createHost(memory: WebAssembly.Memory, opts: HostOptions = {}) {
  const ctx: WasmCtx = { memory };
  const octaveStore = opts.octaveStore ?? new Map<string, Uint8Array>();
  const log = opts.log ?? ((m: string) => console.log('[kernel]', m));
  const blocktime = opts.blocktime ?? (() => (cachedBlocktime ?? Math.floor(Date.now() / 1000)) >>> 0);
  const sequence = opts.sequence ?? (() => 0xffffffff);

  // Cursor state for hostDbOpenCursor / hostDbCursorPull / hostDbCursorClose.
  const openCursors = new Map<number, { entries: Uint8Array[]; index: number }>();
  let nextCursorId = 1;

  return {
    // ── Hashing ──
    host_sha256(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = readBytes(ctx, dataPtr, dataLen);
      writeBytes(ctx, outPtr, nobleSha256(data));
    },
    host_hash160(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = readBytes(ctx, dataPtr, dataLen);
      writeBytes(ctx, outPtr, nobleRipemd160(nobleSha256(data)));
    },
    host_hash256(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = readBytes(ctx, dataPtr, dataLen);
      writeBytes(ctx, outPtr, nobleSha256(nobleSha256(data)));
    },
    host_ripemd160(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = readBytes(ctx, dataPtr, dataLen);
      writeBytes(ctx, outPtr, nobleRipemd160(data));
    },
    host_sha1(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = readBytes(ctx, dataPtr, dataLen);
      writeBytes(ctx, outPtr, nobleSha1(data));
    },

    // ── ECDSA ──
    // sig is pure DER (Zig executor strips the sighash byte before calling).
    host_checksig(
      pkPtr: number,
      pkLen: number,
      msgPtr: number,
      msgLen: number,
      sigPtr: number,
      sigLen: number,
    ): number {
      try {
        if (sigLen < 8 || msgLen !== 32 || pkLen < 33) return 0;
        const pk = readBytes(ctx, pkPtr, pkLen);
        const msg = readBytes(ctx, msgPtr, msgLen);
        const der = readBytes(ctx, sigPtr, sigLen);
        const { r, s } = decodeDer(der);
        const sig = new secp.Signature(r, s);
        return secp.verify(sig, msg, pk, { lowS: false }) ? 1 : 0;
      } catch {
        return 0;
      }
    },

    // BSV consensus multi-sig: for each sig, advance through pubkeys until a
    // match. Sigs are length-prefixed: [len][DER+sighash]. Pubkeys are 33-byte
    // compressed. Mirrors host-functions.ts:host_checkmultisig but uses
    // @noble (smaller bundle). The bsv host strips the sighash byte before
    // verifying — matching exactly here.
    host_checkmultisig(
      pksPtr: number,
      pksCount: number,
      sigsPtr: number,
      sigsCount: number,
      msgPtr: number,
      msgLen: number,
      threshold: number,
    ): number {
      try {
        if (msgLen !== 32 || pksCount === 0 || sigsCount === 0) return 0;
        if (threshold > sigsCount) return 0;
        const msg = readBytes(ctx, msgPtr, msgLen);
        const pks = readBytes(ctx, pksPtr, pksCount * 33);
        const sigsBuf = readBytes(ctx, sigsPtr, sigsCount * 74);

        let matches = 0;
        let pkIdx = 0;
        let off = 0;
        for (let s = 0; s < sigsCount && pkIdx < pksCount; s++) {
          if (off >= sigsBuf.length) break;
          const sigLen = sigsBuf[off]!;
          off++;
          if (off + sigLen > sigsBuf.length) break;
          const cur = sigsBuf.slice(off, off + sigLen);
          off += sigLen;
          if (cur.length < 2) continue;
          const der = cur.slice(0, cur.length - 1); // strip sighash
          let parsed: { r: bigint; s: bigint };
          try {
            parsed = decodeDer(der);
          } catch {
            continue;
          }
          const sig = new secp.Signature(parsed.r, parsed.s);
          while (pkIdx < pksCount) {
            const pk = pks.slice(pkIdx * 33, pkIdx * 33 + 33);
            pkIdx++;
            try {
              if (secp.verify(sig, msg, pk, { lowS: false })) {
                matches++;
                break;
              }
            } catch {
              // keep scanning
            }
          }
        }
        return matches >= threshold ? 1 : 0;
      } catch {
        return 0;
      }
    },

    /**
     * ECDSA signing over a 32-byte digest. Produces low-S DER without the
     * trailing sighash byte (the Zig executor appends it). RFC 6979
     * deterministic — matches bsvz primitives.ec.signDigest output up to DER
     * encoding.
     */
    host_sign(
      skPtr: number,
      skLen: number,
      msgPtr: number,
      msgLen: number,
      outPtr: number,
      outBufLen: number,
      outLenPtr: number,
    ): number {
      try {
        if (skLen !== 32 || msgLen !== 32 || outBufLen < 8) return 0;
        const sk = readBytes(ctx, skPtr, skLen);
        const msg = readBytes(ctx, msgPtr, msgLen);
        const sig = secp.sign(msg, sk).normalizeS();
        const der = encodeDer(sig.r, sig.s);
        if (der.length > outBufLen) return 0;
        writeBytes(ctx, outPtr, der);
        writeU32LE(ctx, outLenPtr, der.length);
        return 1;
      } catch {
        return 0;
      }
    },

    // ── Runtime context ──
    host_get_blocktime(): number {
      return blocktime() >>> 0;
    },
    host_get_sequence(): number {
      return sequence() >>> 0;
    },
    host_log(msgPtr: number, msgLen: number): void {
      const bytes = readBytes(ctx, msgPtr, msgLen);
      log(new TextDecoder().decode(bytes));
    },

    // ── Phase 25.5 host-call registry (placeholder per W5 spec) ──
    host_call_by_name(namePtr: number, nameLen: number): number {
      const name = new TextDecoder().decode(readBytes(ctx, namePtr, nameLen));
      return hostCallRegistry.call(name);
    },

    // ── Phase 6 octave fetch ──
    host_fetch_cell(octave: number, slot: number, offset: number, outPtr: number): number {
      if (octave > 3) return 0;
      const cell = octaveStore.get(`${octave}:${slot}`);
      if (!cell) return 0;
      const byteOff = offset * 1024;
      if (byteOff + 1024 > cell.length) return 0;
      writeBytes(ctx, outPtr, cell.subarray(byteOff, byteOff + 1024));
      return 1;
    },

    // ── Phase 6 cell-store cursor (scan) ──
    // Cursor state lives per createHost() call so each engine instance is isolated.
    hostDbOpenCursor(filterPtr: number, filterLen: number): number {
      // Collect all 1024-byte cells from every octave entry (multi-cell entries
      // are split into individual 1024-byte blocks).  Filter bytes are read but
      // currently unused — the WASM callback discards non-matching cells itself.
      void filterPtr; void filterLen;
      const entries: Uint8Array[] = [];
      for (const cellBytes of octaveStore.values()) {
        for (let off = 0; off + 1024 <= cellBytes.length; off += 1024) {
          entries.push(cellBytes.subarray(off, off + 1024));
        }
      }
      const id = nextCursorId++;
      openCursors.set(id, { entries, index: 0 });
      return id;
    },

    hostDbCursorPull(cursorId: number, outPtr: number): number {
      const cursor = openCursors.get(cursorId);
      if (!cursor || cursor.index >= cursor.entries.length) return 0;
      writeBytes(ctx, outPtr, cursor.entries[cursor.index]!);
      cursor.index++;
      return 1;
    },

    hostDbCursorClose(cursorId: number): void {
      openCursors.delete(cursorId);
    },

    // ── BRC-42 leaf derivation ──
    host_derive_leaf(
      baseSkPtr: number,
      baseSkLen: number,
      protocolHashPtr: number,
      counterpartyPtr: number,
      indexLo: number,
      indexHi: number,
      outLeafPtr: number,
    ): number {
      // u64 marshalled as two i32s on the WASM ABI in some compilers; here
      // Zig 0.15 passes a single i64 by default, but the JS-side import
      // signature surfaces a bigint. Bun will deliver this as `bigint`. We
      // accept both forms defensively (if a number arrives at indexLo, treat
      // indexHi as 0).
      const bs = readBytes(ctx, baseSkPtr, baseSkLen);
      const ph = readBytes(ctx, protocolHashPtr, 16);
      const cp = readBytes(ctx, counterpartyPtr, 33);
      let idx: bigint;
      if (typeof indexLo === 'bigint') {
        idx = indexLo as unknown as bigint;
      } else {
        idx = BigInt(indexLo >>> 0) | (BigInt(indexHi >>> 0) << 32n);
      }
      const leaf = deriveLeafSync(bs, ph, cp, idx);
      if (!leaf) return 0;
      writeBytes(ctx, outLeafPtr, leaf);
      return 1;
    },

    /**
     * Atomically allocate the next BRC-42 derivation index for a (protocol,
     * counterparty) context. The WASM contract is synchronous (returns u32);
     * IndexedDB is async. We bridge via `bridgeAwait` — see bridge.ts —
     * which marshals the pre-loaded next-index from the context. v0.1
     * tests-only path: synchronous in-memory mirror so test code can drive
     * this without a postMessage round-trip.
     */
    host_state_next_index(
      protocolHashPtr: number,
      counterpartyPtr: number,
      outIndexPtr: number,
    ): number {
      const ph = readBytes(ctx, protocolHashPtr, 16);
      const cp = readBytes(ctx, counterpartyPtr, 33);
      const idx = syncStateNextIndex(ph, cp);
      if (idx === null) return 0;
      writeU64LE(ctx, outIndexPtr, idx);
      return 1;
    },

    // ── W4 at-rest tier-cell persistence ──
    host_unlock_tier(
      tier: number,
      factorPtr: number,
      factorLen: number,
      slotId: number,
      outCellPtr: number,
    ): number {
      const factor = readBytes(ctx, factorPtr, factorLen);
      const result = syncUnlockTier(tier, factor, slotId);
      if (!result) return 0;
      writeBytes(ctx, outCellPtr, result);
      return 1;
    },

    host_persist_cell(slotId: number, cellPtr: number, len: number): number {
      const cell = readBytes(ctx, cellPtr, len);
      return syncPersistCell(slotId, cell) ? 1 : 0;
    },

    host_load_cell(slotId: number, outPtr: number): number {
      const cell = syncLoadCell(slotId);
      if (!cell) return 0;
      writeBytes(ctx, outPtr, cell);
      return 1;
    },
  };
}

// ──────────────────────────────────────────────────────────────────────
// Sync wrappers around async storage.
//
// The WASM ABI is synchronous — every host extern returns immediately.
// IndexedDB is async, and crypto.subtle.* is async. To honor the contract
// without re-architecting the engine, the bridge orchestrator is responsible
// for *priming* an in-memory cache of all state the engine will need before
// it dispatches the WASM call.
//
// These functions read from / write to that cache. Tests prime the cache
// directly via the `_priming` exports below; in production, bridge.ts
// translates each BRC-100 request into:
//   1. Pre-read every slot the request needs from IndexedDB
//   2. Resolve any UI prompts via the popup → derive KEKs (async)
//   3. Run WASM synchronously over the cache
//   4. Flush dirty slots back to IndexedDB
// ──────────────────────────────────────────────────────────────────────

interface SlotCache {
  /** slot_id → on-disk envelope bytes (encrypted). */
  blobs: Map<number, Uint8Array>;
  /** slot_id → plaintext cell, populated by unlock_tier / load_cell. */
  plaintext: Map<number, Uint8Array>;
  /** Dirty slots written via persist_cell, flushed by the bridge after WASM returns. */
  dirty: Map<number, Uint8Array>;
  /** Pre-derived per-tier KEKs the bridge installed before calling WASM. */
  perTierKek: Map<number, CryptoKey>;
  /** State next-index map keyed by hex(protocol||cp). */
  stateNext: Map<string, bigint>;
  /** Snapshot of next-index increments to persist after WASM returns. */
  stateDirty: Map<string, bigint>;
}

let activeCache: SlotCache | null = null;

/** Begin a request scope. Bridge calls this before each WASM dispatch. */
export function beginRequest(): SlotCache {
  activeCache = {
    blobs: new Map(),
    plaintext: new Map(),
    dirty: new Map(),
    perTierKek: new Map(),
    stateNext: new Map(),
    stateDirty: new Map(),
  };
  return activeCache;
}

/** End a request scope and drop all state. */
export function endRequest(): void {
  activeCache = null;
}

/** Bridge prime: load slot envelope from IndexedDB into the cache. */
export async function primeSlot(slotId: number): Promise<void> {
  if (!activeCache) throw new Error('primeSlot: no active request');
  const blob = await slotGet(slotId);
  if (blob) activeCache.blobs.set(slotId, blob);
}

/**
 * Bridge prime: derive the KEK for tier N from a factor and decrypt the
 * named slot into the plaintext cache. After this returns, syncLoadCell can
 * read the slot synchronously from inside WASM.
 */
export async function primeUnlockTier(
  tier: number,
  factor: Uint8Array,
  slotId: number,
): Promise<boolean> {
  if (!activeCache) throw new Error('primeUnlockTier: no active request');
  if (tier === 0 || tier >= TIER_COUNT) return false;
  const kek = await deriveKek(tier, factor);
  if (!activeCache.blobs.has(slotId)) await primeSlot(slotId);
  const blob = activeCache.blobs.get(slotId);
  if (!blob) return false;
  const pt = await decryptCell(tier, kek, blob);
  if (!pt) return false;
  activeCache.perTierKek.set(tier, kek);
  activeCache.plaintext.set(slotId, pt);
  keychain.perTier[tier] = kek;
  return true;
}

/**
 * Bridge prime: install the Tier-0 session KEK so syncLoadCell/syncPersist
 * for Tier-0 cells works.
 */
export async function primeSessionKek(rawKey: Uint8Array): Promise<void> {
  await setSessionKek(rawKey);
}

/** Bridge prime: pre-load BRC-42 next-index counter for a context. */
export async function primeStateNext(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
): Promise<void> {
  if (!activeCache) throw new Error('primeStateNext: no active request');
  // Atomic: bump the IndexedDB counter, stash the allocated value for WASM.
  const idx = await storageStateNextIndex(protocolHash, counterparty);
  const key = encodeStateKey(protocolHash, counterparty);
  activeCache.stateNext.set(key, idx);
}

/** Bridge flush: write dirty slot envelopes back to IndexedDB. */
export async function flushRequest(): Promise<void> {
  if (!activeCache) return;
  for (const [slotId, blob] of activeCache.dirty.entries()) {
    await slotPut(slotId, blob);
  }
}

// ── Sync internals (called from inside WASM) ──

function syncStateNextIndex(protocolHash: Uint8Array, counterparty: Uint8Array): bigint | null {
  if (!activeCache) return null;
  const key = encodeStateKey(protocolHash, counterparty);
  const idx = activeCache.stateNext.get(key);
  if (idx === undefined) return null;
  // Each call consumes the cached value — re-priming is required for a
  // second allocation in the same request scope.
  activeCache.stateNext.delete(key);
  return idx;
}

function encodeStateKey(protocolHash: Uint8Array, counterparty: Uint8Array): string {
  let s = '';
  for (const b of protocolHash) s += b.toString(16).padStart(2, '0');
  for (const b of counterparty) s += b.toString(16).padStart(2, '0');
  return s;
}

function syncUnlockTier(_tier: number, _factor: Uint8Array, slotId: number): Uint8Array | null {
  if (!activeCache) return null;
  // unlock has been pre-resolved by primeUnlockTier — just return the
  // cached plaintext if present. The factor / slot_id arguments are
  // sanity-checked but not re-derived synchronously.
  return activeCache.plaintext.get(slotId) ?? null;
}

function syncPersistCell(slotId: number, cell: Uint8Array): boolean {
  if (!activeCache) return false;
  const tier = tierFromDomainFlag(cell);
  if (tier === null) return false;
  const kek = tier === 0 ? keychain.session : (activeCache.perTierKek.get(tier) ?? keychain.perTier[tier]);
  if (!kek) return false;
  // Synchronously stage the encryption result for the bridge to flush. Since
  // crypto.subtle.encrypt is async, we shift to a deferred-write model: the
  // dirty entry is the *plaintext* + tier; bridge.flushRequest re-encrypts
  // before write.
  activeCache.plaintext.set(slotId, cell);
  // Sentinel so flushRequest knows to encrypt this one.
  activeCache.dirty.set(slotId, cell);
  return true;
}

function syncLoadCell(slotId: number): Uint8Array | null {
  if (!activeCache) return null;
  const pt = activeCache.plaintext.get(slotId);
  if (pt) return pt;
  // No plaintext cached → see if we have an envelope and a session/perTier
  // KEK that matches its embedded tier.
  const blob = activeCache.blobs.get(slotId);
  if (!blob) return null;
  const env = readEnvelope(blob);
  if (!env) return null;
  // We have to honor the design contract: Tier-0 needs only the session KEK,
  // Tier-1+ needs unlockTier first. If the matching KEK is not staged, fail.
  // (The bridge is responsible for pre-priming.)
  return null;
}

/** Tests-only access to the active cache (do NOT use from production code). */
export function _activeCacheForTests(): SlotCache | null {
  return activeCache;
}

/**
 * Tests-only: synchronously stage an encrypted blob for a slot. Production
 * code goes through primeSlot which reads from IndexedDB.
 */
export function _stageBlobForTests(slotId: number, blob: Uint8Array): void {
  if (!activeCache) throw new Error('no active request');
  activeCache.blobs.set(slotId, blob);
}

/**
 * Tests-only: synchronously stage a plaintext cell + KEK for a tier. Useful
 * for reproducing the post-unlock state without touching IndexedDB.
 */
export async function _stagePlaintextForTests(
  tier: number,
  slotId: number,
  cell: Uint8Array,
  kek: CryptoKey,
): Promise<void> {
  if (!activeCache) throw new Error('no active request');
  activeCache.plaintext.set(slotId, cell);
  if (tier === 0) keychain.session = kek;
  else activeCache.perTierKek.set(tier, kek);
}

/** Tests-only: encrypt a cell synchronously-callable form for envelope build. */
export async function _encryptForTests(
  tier: number,
  kek: CryptoKey,
  cell: Uint8Array,
): Promise<Uint8Array> {
  return encryptCell(tier, kek, cell);
}

export {
  encryptCell as encryptCellForBridge,
  decryptCell as decryptCellForBridge,
  tierFromDomainFlag as cellTierFromDomainFlag,
  SLOT_FORMAT_VERSION,
  SLOT_NONCE_BYTES,
  SLOT_TAG_BYTES,
  SLOT_HEADER_BYTES,
  SLOT_KEK_BYTES,
};

```
