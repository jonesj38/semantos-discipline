---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/src/anchor-history-chain.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.443795+00:00
---

# cartridges/bsv-anchor-bundle/brain/src/anchor-history-chain.ts

```ts
/**
 * AnchorHistoryChain — first cartridge consumer of L12
 * (cw-lift-matrix.yml L12 axis F).
 *
 * Composes:
 *   - L5 IdempotentBatchAnchorer (#836, idempotent batch anchoring) +
 *   - L12 audit-chain primitive (#848, append-only tamper-evident chain)
 *
 * What this does:
 *   Each *fresh* successful anchor (cache miss → broadcast/confirmed)
 *   produces ONE new audit-chain entry whose canonical bytes are a
 *   deterministic packing of the batch identity + on-chain result +
 *   committed cell roots. Subsequent cache hits do NOT append a
 *   duplicate entry — the chain reflects the *actual* on-chain action,
 *   not the caller's request count.
 *
 *   Once a chain is built, any verifier holding the master pub can
 *   walk it via `verifyAuditChain` and prove:
 *     - no anchors have been added or removed from the history,
 *     - every recorded anchor's batchId is what the producer signed,
 *     - the sortedCellRoots committed in each anchor are recoverable
 *       byte-for-byte (no silent re-ordering / loss).
 *
 *   Walking the chain replaces "walk the brain's SQLite anchor-history
 *   table" with "walk the L12 chain and reconstruct each anchor from
 *   the canonical bytes" — recomputable + tamper-evident, no per-store
 *   trust required.
 *
 * What this does NOT do:
 *   - Re-verify the on-chain anchor itself (that's L4
 *     `verifyAnchorAttestationInclusion`, #835).
 *   - Decide canonical entityId scoping (per cartridge? per operator?
 *     per hat?) — caller supplies it. Default convention is one chain
 *     per (operator, scope) which the caller controls via the
 *     constructor `entityId`.
 *
 * Layered shape:
 *
 *     ┌─ caller (brain mint walker, scheduled batch loop, …) ──────┐
 *     │ history.anchorAndRecord({                                   │
 *     │   cellRoots, items, window?,                                │
 *     │ })                                                          │
 *     └────────────────────────────────────────────────────────────┘
 *                                ↓
 *     ┌─ IdempotentBatchAnchorer (L5) ─────────────────────────────┐
 *     │  cache miss → inner.batchAnchor → manifest                  │
 *     │  cache hit  → return cached manifest (no on-chain action)   │
 *     └────────────────────────────────────────────────────────────┘
 *                                ↓
 *     ┌─ AnchorHistoryChain — appends iff fresh + broadcast/conf. ┐
 *     │  store.loadLatest(entityId) → prev (or null)                │
 *     │  canonical = encodeAnchorHistoryCanonical(manifest)         │
 *     │  next = appendEntry(prev, canonical) | genesisEntry(...)    │
 *     │  signed = signEntry(next, masterPriv, segmenter)            │
 *     │  store.append(signed)                                       │
 *     └────────────────────────────────────────────────────────────┘
 */

import PrivateKey from '@bsv/sdk/primitives/PrivateKey';
import {
  appendEntry,
  genesisEntry,
  signEntry,
  verifyAuditChain,
  type ChainVerifyResult,
  type LinkSegmentDeriver,
  type SignedAuditChainEntry,
} from '@semantos/anchor-attestation/audit-chain';
import type { BatchManifest } from '@semantos/anchor-attestation';
import {
  IdempotentBatchAnchorer,
  type IdempotentBatchAnchorInput,
  type IdempotentBatchAnchorResult,
} from './idempotent-batch-anchorer.js';

// ── Canonical encoding ───────────────────────────────────────────

/** 'AHX1' = AnchorHistory v1 magic — 4 ASCII bytes. */
export const ANCHOR_HISTORY_MAGIC = new Uint8Array([0x41, 0x48, 0x58, 0x31]);
export const ANCHOR_HISTORY_VERSION = 1;

/**
 * Status code in the canonical entry. We chain only successful anchors,
 * so the status here is always 'broadcast' or 'confirmed'; 'pending' /
 * 'failed' cannot appear in a chain entry (the caller is required to
 * filter them out before recording).
 */
export const STATUS_CODE = {
  broadcast: 1 as const,
  confirmed: 2 as const,
};

/** Decoded view of an anchor-history canonical entry. */
export interface AnchorHistoryRecord {
  readonly batchId: Uint8Array;            // 32B
  readonly statusCode: 1 | 2;              // broadcast|confirmed
  readonly txid: Uint8Array;               // 32B (always present for broadcast+)
  readonly vout: number;
  readonly anchorHeight: bigint;           // 0n if not yet confirmed
  readonly window: Uint8Array;
  readonly sortedCellRoots: readonly Uint8Array[];
}

/**
 * Deterministic canonical encoding of an anchor-history entry. Frozen
 * wire format:
 *
 *   ANCHOR_HISTORY_MAGIC    (4)
 *   u8 version              (1)
 *   batchId                 (32)
 *   u8 statusCode           (1)  // 1=broadcast, 2=confirmed
 *   txid                    (32)
 *   u32be vout              (4)
 *   u64be anchorHeight      (8)  // 0 when not yet confirmed
 *   u32be windowLen         (4)
 *   window                  (windowLen)
 *   u32be rootCount         (4)
 *   sortedCellRoots         (32 * rootCount)
 *
 * batchId is the L5 idempotency key; sortedCellRoots is the canonical
 * lex-ascending order the manifest carries (NOT the caller's input
 * order). Together they make the entry recomputable: a verifier
 * holding (batchId, sortedCellRoots) can re-derive batchId via
 * computeBatchId(sortedCellRoots, window) and check it matches.
 */
export function encodeAnchorHistoryCanonical(record: AnchorHistoryRecord): Uint8Array {
  if (record.batchId.byteLength !== 32) {
    throw new RangeError(`anchor-history: batchId must be 32 bytes`);
  }
  if (record.txid.byteLength !== 32) {
    throw new RangeError(`anchor-history: txid must be 32 bytes`);
  }
  if (record.statusCode !== 1 && record.statusCode !== 2) {
    throw new RangeError(`anchor-history: statusCode must be 1|2, got ${record.statusCode}`);
  }
  for (const r of record.sortedCellRoots) {
    if (r.byteLength !== 32) {
      throw new RangeError(`anchor-history: each cell root must be 32 bytes`);
    }
  }

  const windowLen = record.window.byteLength;
  const rootCount = record.sortedCellRoots.length;
  const totalLen =
    ANCHOR_HISTORY_MAGIC.byteLength + 1 + 32 + 1 + 32 + 4 + 8 + 4 + windowLen + 4 + 32 * rootCount;
  const out = new Uint8Array(totalLen);
  let off = 0;

  out.set(ANCHOR_HISTORY_MAGIC, off); off += ANCHOR_HISTORY_MAGIC.byteLength;
  out[off++] = ANCHOR_HISTORY_VERSION & 0xff;
  out.set(record.batchId, off); off += 32;
  out[off++] = record.statusCode;
  out.set(record.txid, off); off += 32;
  writeU32BE(out, off, record.vout); off += 4;
  writeU64BE(out, off, record.anchorHeight); off += 8;
  writeU32BE(out, off, windowLen); off += 4;
  out.set(record.window, off); off += windowLen;
  writeU32BE(out, off, rootCount); off += 4;
  for (const r of record.sortedCellRoots) {
    out.set(r, off);
    off += 32;
  }
  if (off !== totalLen) {
    throw new Error(`encodeAnchorHistoryCanonical: wrote ${off}, expected ${totalLen}`);
  }
  return out;
}

/** Inverse of encodeAnchorHistoryCanonical — useful for chain walkers. */
export function decodeAnchorHistoryCanonical(bytes: Uint8Array): AnchorHistoryRecord {
  let off = 0;
  if (bytes.byteLength < ANCHOR_HISTORY_MAGIC.byteLength + 1 + 32 + 1 + 32 + 4 + 8 + 4 + 4) {
    throw new Error(`decodeAnchorHistoryCanonical: input too short (${bytes.byteLength})`);
  }
  for (let i = 0; i < ANCHOR_HISTORY_MAGIC.byteLength; i++) {
    if (bytes[off + i] !== ANCHOR_HISTORY_MAGIC[i]) {
      throw new Error(`decodeAnchorHistoryCanonical: magic mismatch`);
    }
  }
  off += ANCHOR_HISTORY_MAGIC.byteLength;
  const version = bytes[off++];
  if (version !== ANCHOR_HISTORY_VERSION) {
    throw new Error(`decodeAnchorHistoryCanonical: unsupported version ${version}`);
  }
  const batchId = bytes.slice(off, off + 32); off += 32;
  const statusCodeByte = bytes[off++];
  if (statusCodeByte !== 1 && statusCodeByte !== 2) {
    throw new Error(`decodeAnchorHistoryCanonical: bad statusCode ${statusCodeByte}`);
  }
  const txid = bytes.slice(off, off + 32); off += 32;
  const vout = readU32BE(bytes, off); off += 4;
  const anchorHeight = readU64BE(bytes, off); off += 8;
  const windowLen = readU32BE(bytes, off); off += 4;
  const window = bytes.slice(off, off + windowLen); off += windowLen;
  const rootCount = readU32BE(bytes, off); off += 4;
  if (bytes.byteLength !== off + rootCount * 32) {
    throw new Error(
      `decodeAnchorHistoryCanonical: trailing-bytes mismatch (have ${bytes.byteLength - off}, need ${rootCount * 32})`,
    );
  }
  const sortedCellRoots: Uint8Array[] = [];
  for (let i = 0; i < rootCount; i++) {
    sortedCellRoots.push(bytes.slice(off, off + 32));
    off += 32;
  }
  return Object.freeze({
    batchId,
    statusCode: statusCodeByte as 1 | 2,
    txid,
    vout,
    anchorHeight,
    window,
    sortedCellRoots: Object.freeze(sortedCellRoots) as readonly Uint8Array[],
  });
}

/** Build an AnchorHistoryRecord from a successful BatchManifest. */
export function anchorHistoryRecordFromManifest(
  manifest: BatchManifest,
): AnchorHistoryRecord {
  if (manifest.status !== 'broadcast' && manifest.status !== 'confirmed') {
    throw new Error(
      `anchorHistoryRecordFromManifest: manifest status is '${manifest.status}' — only 'broadcast'|'confirmed' are recordable`,
    );
  }
  if (!manifest.txid) {
    throw new Error(`anchorHistoryRecordFromManifest: manifest missing txid`);
  }
  return Object.freeze({
    batchId: Uint8Array.from(manifest.batchId),
    statusCode: manifest.status === 'confirmed' ? STATUS_CODE.confirmed : STATUS_CODE.broadcast,
    txid: Uint8Array.from(manifest.txid),
    vout: manifest.vout ?? 0,
    anchorHeight: manifest.anchorHeight ?? 0n,
    window: Uint8Array.from(manifest.window),
    sortedCellRoots: manifest.cellRoots.map(r => Uint8Array.from(r)),
  });
}

// ── Store interface + in-memory reference impl ──────────────────

export interface AnchorHistoryStore {
  /** Most-recent appended entry, or null when chain is empty. */
  loadLatest(entityId: string): Promise<SignedAuditChainEntry | null> | SignedAuditChainEntry | null;
  /** Append a new signed entry. */
  append(entry: SignedAuditChainEntry): Promise<void> | void;
  /** Full chain in seq order. */
  list(entityId: string): Promise<readonly SignedAuditChainEntry[]> | readonly SignedAuditChainEntry[];
}

export class InMemoryAnchorHistoryStore implements AnchorHistoryStore {
  private chains = new Map<string, SignedAuditChainEntry[]>();
  loadLatest(entityId: string): SignedAuditChainEntry | null {
    const chain = this.chains.get(entityId);
    return chain && chain.length > 0 ? chain[chain.length - 1] : null;
  }
  append(entry: SignedAuditChainEntry): void {
    const existing = this.chains.get(entry.entry.entityId);
    if (existing) {
      existing.push(entry);
    } else {
      this.chains.set(entry.entry.entityId, [entry]);
    }
  }
  list(entityId: string): readonly SignedAuditChainEntry[] {
    return this.chains.get(entityId) ?? [];
  }
}

// ── The consumer ─────────────────────────────────────────────────

export interface AnchorAndRecordResult {
  /** Result from the underlying IdempotentBatchAnchorer. */
  readonly anchor: IdempotentBatchAnchorResult;
  /** The new chain entry, or null if no new entry was appended.
   *  Returns null when:
   *    - the anchor result came from cache (no fresh on-chain action), or
   *    - the manifest status is not 'broadcast'|'confirmed'. */
  readonly chainEntry: SignedAuditChainEntry | null;
}

export class AnchorHistoryChain {
  constructor(
    private readonly inner: IdempotentBatchAnchorer,
    private readonly masterPriv: PrivateKey,
    private readonly store: AnchorHistoryStore,
    public readonly entityId: string,
    private readonly segmenter?: LinkSegmentDeriver,
  ) {}

  /**
   * Anchor the batch via the inner L5 idempotent anchorer. If the
   * anchor is FRESH (cache miss) AND broadcast/confirmed, append a new
   * L12 chain entry; otherwise return chainEntry: null.
   */
  async anchorAndRecord(
    input: IdempotentBatchAnchorInput,
  ): Promise<AnchorAndRecordResult> {
    const anchor = await this.inner.anchorBatchIdempotent(input);

    // Cache hit → no new on-chain action → no chain entry.
    if (anchor.fromCache) {
      return { anchor, chainEntry: null };
    }

    // Only chain broadcast/confirmed anchors. The IdempotentBatchAnchorer
    // throws on 'failed', so reaching here implies status is broadcast or
    // confirmed (defensive recheck preserved).
    const { status } = anchor.manifest;
    if (status !== 'broadcast' && status !== 'confirmed') {
      return { anchor, chainEntry: null };
    }

    const record = anchorHistoryRecordFromManifest(anchor.manifest);
    const canonical = encodeAnchorHistoryCanonical(record);

    const prev = await this.store.loadLatest(this.entityId);
    const entry = prev
      ? appendEntry(prev.entry, canonical)
      : genesisEntry(this.entityId, canonical);

    const signed = signEntry(entry, this.masterPriv, this.segmenter);
    await this.store.append(signed);
    return { anchor, chainEntry: signed };
  }

  /** Full chain in seq order. */
  async loadHistory(): Promise<readonly SignedAuditChainEntry[]> {
    return await this.store.list(this.entityId);
  }

  /** Walk the chain end-to-end against this anchorer's master pub. */
  async verifyHistory(): Promise<ChainVerifyResult> {
    const entries = await this.store.list(this.entityId);
    const masterPubKeyHex = this.masterPriv.toPublicKey().toDER('hex') as string;
    return verifyAuditChain({
      entries,
      masterPubKeyHex,
      segmenter: this.segmenter,
    });
  }
}

// ── Helpers ──────────────────────────────────────────────────────

function writeU32BE(out: Uint8Array, off: number, n: number): void {
  if (!Number.isInteger(n) || n < 0 || n > 0xFFFFFFFF) {
    throw new RangeError(`writeU32BE: out of range: ${n}`);
  }
  out[off + 0] = (n >>> 24) & 0xff;
  out[off + 1] = (n >>> 16) & 0xff;
  out[off + 2] = (n >>> 8) & 0xff;
  out[off + 3] = n & 0xff;
}

function readU32BE(b: Uint8Array, off: number): number {
  return ((b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3]) >>> 0;
}

function writeU64BE(out: Uint8Array, off: number, n: bigint): void {
  if (n < 0n || n > 0xFFFFFFFFFFFFFFFFn) {
    throw new RangeError(`writeU64BE: out of range: ${n}`);
  }
  let v = n;
  for (let i = 7; i >= 0; i--) {
    out[off + i] = Number(v & 0xffn);
    v >>= 8n;
  }
}

function readU64BE(b: Uint8Array, off: number): bigint {
  let v = 0n;
  for (let i = 0; i < 8; i++) {
    v = (v << 8n) | BigInt(b[off + i]);
  }
  return v;
}

```
