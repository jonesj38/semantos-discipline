---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/beef-codec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.656824+00:00
---

# cartridges/wallet-headers/brain/src/beef-codec.ts

```ts
// BEEF (BRC-62 / BRC-95) codec — parser, BUMP verifier, Atomic BEEF builder.
//
// All hashes and txids use "internal byte order" (the raw little-endian form
// as stored in block headers and transaction wire format). Callers that need
// display txids (reversed hex) must flip them themselves.
//
// References:
//   BRC-62 https://bsv.brc.dev/transactions/0062
//   BRC-74 https://bsv.brc.dev/transactions/0074 (BUMP)
//   BRC-95 https://bsv.brc.dev/transactions/0095 (Atomic BEEF)

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

// BEEF magic constants — stored as 32-bit LE integers so setUint32(..., true) produces
// the correct wire bytes. Go SDK (used by ARC) defines V1=0xEFBE0001 → wire [01 00 BE EF],
// V2=0xEFBE0002 → wire [02 00 BE EF]. ARC's format check requires bytes[2..3] = BE EF.
export const BEEF_V1_MAGIC = 0xefbe0001; // wire: 01 00 BE EF
export const BEEF_V2_MAGIC = 0xefbe0002; // wire: 02 00 BE EF
// Keep SDK alias for backward compat with existing callers
export const BEEF_V2_MAGIC_SDK = 0xefbe0002;
export const ATOMIC_BEEF_MAGIC = 0x01010101;

// ── Varint ────────────────────────────────────────────────────────────

export function readVarInt(buf: Uint8Array, off: number): [value: number, next: number] {
  const b = buf[off]!;
  if (b < 0xfd) return [b, off + 1];
  if (b === 0xfd) return [dv(buf, off + 1, 2).getUint16(0, true), off + 3];
  if (b === 0xfe) return [dv(buf, off + 1, 4).getUint32(0, true), off + 5];
  const lo = dv(buf, off + 1, 4).getUint32(0, true);
  const hi = dv(buf, off + 5, 4).getUint32(0, true);
  return [hi * 0x100000000 + lo, off + 9];
}

export function writeVarInt(n: number): Uint8Array {
  if (n < 0xfd) return new Uint8Array([n]);
  if (n <= 0xffff) { const b = new Uint8Array(3); b[0] = 0xfd; dv(b, 1, 2).setUint16(0, n, true); return b; }
  if (n <= 0xffffffff) { const b = new Uint8Array(5); b[0] = 0xfe; dv(b, 1, 4).setUint32(0, n, true); return b; }
  const b = new Uint8Array(9); b[0] = 0xff; dv(b, 1, 8).setBigUint64(0, BigInt(n), true); return b;
}

function dv(buf: Uint8Array, off: number, len: number): DataView {
  return new DataView(buf.buffer, buf.byteOffset + off, len);
}

// ── Hash256 ───────────────────────────────────────────────────────────

export function hash256(data: Uint8Array): Uint8Array {
  return nobleSha256(nobleSha256(data));
}

export function computeTxid(rawTx: Uint8Array): Uint8Array {
  return hash256(rawTx);
}

export function hexFromBytes(b: Uint8Array): string {
  let s = ''; for (const x of b) s += x.toString(16).padStart(2, '0'); return s;
}

export function bytesFromHex(hex: string): Uint8Array {
  if (hex.length % 2) throw new Error('hex: odd length');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/** Reverse a 32-byte hash for display (internal ↔ display). */
export function reverseTxid(b: Uint8Array): Uint8Array { return b.slice().reverse(); }

// ── BUMP types ────────────────────────────────────────────────────────

export interface BumpLeaf {
  offset: number;
  flags: number;    // bit0=duplicate, bit1=txid-flag
  hash: Uint8Array | null;  // null when duplicate flag set
}

export interface ParsedBump {
  blockHeight: number;
  treeHeight: number;
  levels: BumpLeaf[][];
}

export interface ParsedTx {
  rawTx: Uint8Array;
  txid: Uint8Array;
  bumpIndex: number | null;
}

export interface ParsedBeef {
  version: 'v1' | 'v2' | 'atomic';
  subjectTxid: Uint8Array | null;
  bumps: ParsedBump[];
  txs: ParsedTx[];
}

// ── BUMP parser ───────────────────────────────────────────────────────

export function parseBump(buf: Uint8Array, start: number): [ParsedBump, number] {
  let off = start;
  let blockHeight: number;
  [blockHeight, off] = readVarInt(buf, off);
  const treeHeight = buf[off++]!;
  const levels: BumpLeaf[][] = [];
  for (let lv = 0; lv < treeHeight; lv++) {
    let nLeaves: number;
    [nLeaves, off] = readVarInt(buf, off);
    const leaves: BumpLeaf[] = [];
    for (let j = 0; j < nLeaves; j++) {
      let offset: number;
      [offset, off] = readVarInt(buf, off);
      const flags = buf[off++]!;
      let hash: Uint8Array | null = null;
      if (!(flags & 0x01)) { hash = buf.slice(off, off + 32); off += 32; }
      leaves.push({ offset, flags, hash });
    }
    levels.push(leaves);
  }
  return [{ blockHeight, treeHeight, levels }, off];
}

// ── Raw-tx length scanner (no full parse needed for BEEF) ─────────────

function scanRawTxLength(buf: Uint8Array, start: number): number {
  let off = start + 4; // skip version
  let n: number;
  [n, off] = readVarInt(buf, off);
  for (let i = 0; i < n; i++) {
    off += 36; // outpoint
    let slen: number; [slen, off] = readVarInt(buf, off);
    off += slen + 4; // script + sequence
  }
  [n, off] = readVarInt(buf, off);
  for (let i = 0; i < n; i++) {
    off += 8; // value
    let slen: number; [slen, off] = readVarInt(buf, off);
    off += slen;
  }
  off += 4; // locktime
  return off - start;
}

// ── BEEF parser ───────────────────────────────────────────────────────

export function parseBeef(bytes: Uint8Array): ParsedBeef {
  if (bytes.length < 8) throw new Error('BEEF too short');
  let off = 0;
  const magic = dv(bytes, 0, 4).getUint32(0, true);
  off += 4;

  let version: ParsedBeef['version'];
  let subjectTxid: Uint8Array | null = null;

  if (magic === ATOMIC_BEEF_MAGIC) {
    // Atomic BEEF (BRC-95): 4-byte outer magic + 32-byte subject txid + inner BEEF.
    // Set version from the inner magic so the tx-entry parser uses the right format.
    subjectTxid = bytes.slice(off, off + 32); off += 32;
    const inner = dv(bytes, off, 4).getUint32(0, true); off += 4;
    if (inner === BEEF_V1_MAGIC) {
      version = 'v1';
    } else if (inner === BEEF_V2_MAGIC || inner === BEEF_V2_MAGIC_SDK) {
      version = 'v2';
    } else {
      throw new Error(`Atomic BEEF inner magic: 0x${inner.toString(16)}`);
    }
  } else if (magic === BEEF_V1_MAGIC) {
    version = 'v1';
  } else if (magic === BEEF_V2_MAGIC || magic === BEEF_V2_MAGIC_SDK) {
    version = 'v2';
  } else {
    throw new Error(`Unknown BEEF magic: 0x${magic.toString(16)}`);
  }

  let nBumps: number; [nBumps, off] = readVarInt(bytes, off);
  const bumps: ParsedBump[] = [];
  for (let i = 0; i < nBumps; i++) {
    let b: ParsedBump; [b, off] = parseBump(bytes, off); bumps.push(b);
  }

  let nTxs: number; [nTxs, off] = readVarInt(bytes, off);
  const txs: ParsedTx[] = [];
  for (let i = 0; i < nTxs; i++) {
    let rawTx: Uint8Array;
    let txid: Uint8Array;
    let bumpIndex: number | null = null;

    if (version === 'v2') {
      // BEEF V2 (BRC-96 / @bsv/sdk): format byte first, then optional bumpIndex, then tx or txid.
      // TX_DATA_FORMAT: 0=RAWTX, 1=RAWTX_AND_BUMP_INDEX, 2=TXID_ONLY
      const fmt = bytes[off++]!;
      if (fmt === 2 /* TXID_ONLY */) {
        // 32 bytes in internal byte order (written with writeReverse from display hex)
        txid = bytes.slice(off, off + 32);
        off += 32;
        rawTx = new Uint8Array(0);
      } else {
        if (fmt === 1 /* RAWTX_AND_BUMP_INDEX */) {
          [bumpIndex, off] = readVarInt(bytes, off);
        }
        const txStart = off;
        const txLen = scanRawTxLength(bytes, txStart);
        rawTx = bytes.slice(txStart, txStart + txLen);
        txid = computeTxid(rawTx);
        off = txStart + txLen;
      }
    } else {
      // BEEF V1 (BRC-62): rawTx first, then hasBump byte, then optional bumpIndex.
      const txStart = off;
      const txLen = scanRawTxLength(bytes, txStart);
      rawTx = bytes.slice(txStart, txStart + txLen);
      txid = computeTxid(rawTx);
      off = txStart + txLen;
      const hasBump = bytes[off++]!;
      if (hasBump === 1) { [bumpIndex, off] = readVarInt(bytes, off); }
    }

    txs.push({ rawTx, txid, bumpIndex });
  }
  return { version, subjectTxid, bumps, txs };
}

// ── BUMP merkle-path verifier ─────────────────────────────────────────

/**
 * Walk the BUMP path for `txid` and return the computed merkle root.
 * All bytes in internal order. Compare against `header.slice(36, 68)`.
 */
export function computeMerkleRoot(bump: ParsedBump, txid: Uint8Array): Uint8Array {
  if (bump.levels.length === 0) return hash256(concat([txid, txid]));

  let currentOffset = -1;
  for (const leaf of bump.levels[0]!) {
    if (leaf.flags & 0x02) { currentOffset = leaf.offset; break; }
  }
  if (currentOffset === -1) throw new Error('txid leaf not found in BUMP level 0');

  let current: Uint8Array = new Uint8Array(txid);

  for (let lv = 0; lv < bump.treeHeight; lv++) {
    const siblingOff = currentOffset ^ 1;
    let sibling: Uint8Array | null = null;
    for (const leaf of bump.levels[lv]!) {
      if (leaf.offset === siblingOff) {
        sibling = leaf.flags & 0x01 ? current : leaf.hash!;
        break;
      }
    }
    if (!sibling) sibling = current; // lone node — self-pair
    const left = (currentOffset & 1) === 0 ? current : sibling;
    const right = (currentOffset & 1) === 0 ? sibling : current;
    current = hash256(concat([left, right]));
    currentOffset >>= 1;
  }
  return current;
}

// ── BUMP serializer (round-trip for embedding in new BEEFs) ──────────

export function serializeBump(bump: ParsedBump): Uint8Array {
  const parts: Uint8Array[] = [];
  parts.push(writeVarInt(bump.blockHeight));
  parts.push(new Uint8Array([bump.treeHeight]));
  for (const level of bump.levels) {
    parts.push(writeVarInt(level.length));
    for (const leaf of level) {
      parts.push(writeVarInt(leaf.offset));
      parts.push(new Uint8Array([leaf.flags]));
      if (!(leaf.flags & 0x01) && leaf.hash) parts.push(leaf.hash);
    }
  }
  return concat(parts);
}

// ── Atomic BEEF builders ──────────────────────────────────────────────

/** Atomic BEEF for hop-1: mined sourceTx (with BUMP) + unconfirmed spendTx. */
// Standard BEEF_V1 for ARC broadcast (no Atomic prefix — ARC detects by 0x0100beef magic).
export function buildBeefV1(
  sourceTxBeef: Uint8Array,
  spendTxRaw: Uint8Array,
  spendTxid: Uint8Array,
): Uint8Array {
  return buildAtomicBeef(sourceTxBeef, spendTxRaw, spendTxid).subarray(36);
}

// Standard BEEF_V1 for an arbitrary-depth unconfirmed chain — strips the Atomic prefix.
export function buildBeefV1ChainedN(
  minedSourceBeef: Uint8Array,
  unconfirmedRaws: Uint8Array[],
  subjectTxid: Uint8Array,
): Uint8Array {
  return buildAtomicBeefChainedN(minedSourceBeef, unconfirmedRaws, subjectTxid).subarray(36);
}

export function buildAtomicBeef(
  sourceTxBeef: Uint8Array,
  spendTxRaw: Uint8Array,
  spendTxid: Uint8Array,
): Uint8Array {
  const parsed = parseBeef(sourceTxBeef);
  return assembleBeef(
    spendTxid,
    parsed.bumps.map((bump, i) => ({ bump, bumpIdx: i })),
    [
      ...parsed.txs.map(tx => ({ raw: tx.rawTx, bumpIndex: tx.bumpIndex })),
      { raw: spendTxRaw, bumpIndex: null },
    ],
  );
}

/**
 * Atomic BEEF for an arbitrary-depth unconfirmed chain rooted at a single
 * mined transaction.  `unconfirmedRaws` are in spend order (oldest first).
 * The last entry is the subject transaction.
 */
export function buildAtomicBeefChainedN(
  minedSourceBeef: Uint8Array,
  unconfirmedRaws: Uint8Array[],
  subjectTxid: Uint8Array,
): Uint8Array {
  if (unconfirmedRaws.length === 0) throw new Error('buildAtomicBeefChainedN: need at least one unconfirmed tx');
  const parsed = parseBeef(minedSourceBeef);
  return assembleBeef(
    subjectTxid,
    parsed.bumps.map((bump, i) => ({ bump, bumpIdx: i })),
    [
      ...parsed.txs.map(tx => ({ raw: tx.rawTx, bumpIndex: tx.bumpIndex })),
      ...unconfirmedRaws.map(raw => ({ raw, bumpIndex: null as null })),
    ],
  );
}

/**
 * Atomic BEEF for hop-2: mined hop-0 (BUMP) + unconfirmed hop-1 + hop-2.
 */
export function buildAtomicBeefChained(
  hop0Beef: Uint8Array,
  hop1Raw: Uint8Array,
  _hop1Txid: Uint8Array,
  hop2Raw: Uint8Array,
  hop2Txid: Uint8Array,
): Uint8Array {
  const parsed = parseBeef(hop0Beef);
  return assembleBeef(
    hop2Txid,
    parsed.bumps.map((bump, i) => ({ bump, bumpIdx: i })),
    [
      ...parsed.txs.map(tx => ({ raw: tx.rawTx, bumpIndex: tx.bumpIndex })),
      { raw: hop1Raw, bumpIndex: null },
      { raw: hop2Raw, bumpIndex: null },
    ],
  );
}

function assembleBeef(
  subjectTxid: Uint8Array,
  bumpEntries: Array<{ bump: ParsedBump; bumpIdx: number }>,
  txEntries: Array<{ raw: Uint8Array; bumpIndex: number | null }>,
): Uint8Array {
  const parts: Uint8Array[] = [];

  const prefix = new Uint8Array(4 + 32);
  dv(prefix, 0, 4).setUint32(0, ATOMIC_BEEF_MAGIC, true);
  prefix.set(subjectTxid, 4);
  parts.push(prefix);

  const innerMagic = new Uint8Array(4);
  dv(innerMagic, 0, 4).setUint32(0, BEEF_V1_MAGIC, true);
  parts.push(innerMagic);

  parts.push(writeVarInt(bumpEntries.length));
  for (const { bump } of bumpEntries) parts.push(serializeBump(bump));

  parts.push(writeVarInt(txEntries.length));
  for (const { raw, bumpIndex } of txEntries) {
    parts.push(raw);
    if (bumpIndex !== null) {
      parts.push(new Uint8Array([1]));
      parts.push(writeVarInt(bumpIndex));
    } else {
      parts.push(new Uint8Array([0]));
    }
  }

  return concat(parts);
}

/**
 * Re-serialize any BEEF (Atomic / V1 / V2) into a clean BEEF V1. ARC's /v1/tx
 * accepts V1, but wallets (Metanet createAction) may return Atomic or V2, which
 * ARC misparses ("unexpected EOF"). Normalizes to V1, preserving all txs +
 * BUMPs in order (the last tx is the subject). `subjectTxid` only labels the
 * (stripped) Atomic prefix, so any value works.
 */
export function toBeefV1(beef: Uint8Array): Uint8Array {
  const parsed = parseBeef(beef);
  const subject = parsed.subjectTxid ?? parsed.txs.at(-1)?.txid ?? new Uint8Array(32);
  return assembleBeef(
    subject,
    parsed.bumps.map((bump, i) => ({ bump, bumpIdx: i })),
    parsed.txs.map((tx) => ({ raw: tx.rawTx, bumpIndex: tx.bumpIndex })),
  ).subarray(36);
}

// ── Concat helper ─────────────────────────────────────────────────────

export function concat(parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out = new Uint8Array(total);
  let pos = 0;
  for (const p of parts) { out.set(p, pos); pos += p.length; }
  return out;
}

```
