---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/idempotency.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.938198+00:00
---

# core/anchor-attestation/src/idempotency.ts

```ts
/**
 * Per-batchId idempotent anchoring primitive.
 *
 * CW Lift L5 (docs/canon/cw-lift-matrix.yml).
 *
 * Semantos's MNCA anchoring is per-cell today: each cell mint asks the
 * anchor adapter for its own transaction. At Skyminer / federation
 * scale this is wasteful (one BSV tx per cell) and unsafe on retry
 * (network hiccup → caller re-submits → two on-chain txes for the
 * same intent).
 *
 * This primitive adds a deterministic batch identity so:
 *   - many cell roots can ride one anchor transaction (cheaper),
 *   - retrying the same batchId returns the existing manifest rather
 *     than emitting a duplicate transaction (idempotent).
 *
 * Layered cleanly above any underlying anchor surface. Pure module —
 * no network, no clock, no random. Storage backend is an interface
 * (`IdempotentAnchorStore`) so callers pick LMDB / SQLite / file /
 * in-memory per their context. An `InMemoryAnchorStore` ships for
 * tests + ephemeral use.
 *
 * Anchorchain analogue: `Anchorer.anchorBatch()` in
 * prof-faustus/anchorchain (MIT) — second call with the same batchId
 * returns the existing manifest. This is the same idea, semantos-shaped
 * (per-cell-root array + caller-supplied logical window + caller-
 * supplied submitter).
 */

import { createHash } from 'crypto';

// ── Types ───────────────────────────────────────────────────────────

/**
 * Window identity that scopes a batch in logical time. Two anchor
 * requests with identical cell roots but different windows produce
 * different batchIds (and therefore distinct manifests / on-chain
 * txes). Callers choose what a "window" means — e.g. a 10-minute
 * epoch, a session id, a hat scope. Empty bytes are valid (= no
 * window, all batches in one bucket).
 */
export type BatchWindow = Uint8Array;

/** 32-byte deterministic batch identity. */
export type BatchId = Uint8Array;

/**
 * Manifest returned when a batch has been (or is being) anchored.
 * Same shape on first submit and on idempotent retry.
 */
export interface BatchManifest {
  /** 32B deterministic id derived from sortedCellRoots + window. */
  readonly batchId: BatchId;
  /** The cell roots committed in this batch, in CANONICAL ORDER
   *  (lexicographic ascending — see `sortCellRoots`). The caller may
   *  have submitted them in any order; the batch sorts them so two
   *  callers with the same set of roots produce the same batchId. */
  readonly cellRoots: readonly Uint8Array[];
  /** Window the batch was scoped to. */
  readonly window: BatchWindow;
  /** Lifecycle status. */
  readonly status: BatchStatus;
  /** Anchor txid (set when status >= 'broadcast'). */
  readonly txid?: Uint8Array;
  /** Anchor block height (set when status === 'confirmed'). */
  readonly anchorHeight?: bigint;
  /** Anchor vout (set when status >= 'broadcast'). */
  readonly vout?: number;
  /** Optional opaque payload from the submitter (e.g. the encoded
   *  attestation bytes from `createAnchorAttestation`). */
  readonly attestationPayload?: Uint8Array;
}

/** Lifecycle states of a batch manifest. Mirrors the typical anchor
 *  flow without coupling to a specific adapter implementation. */
export type BatchStatus = 'pending' | 'broadcast' | 'confirmed' | 'failed';

/** What a batch submitter returns when called by the idempotent
 *  wrapper. */
export interface BatchSubmitResult {
  status: BatchStatus;
  txid?: Uint8Array;
  anchorHeight?: bigint;
  vout?: number;
  attestationPayload?: Uint8Array;
  /** Optional reason when status === 'failed'. */
  reason?: string;
}

/**
 * Storage interface for batch manifests. Implementations must be
 * crash-consistent (persist atomically before returning from `put`)
 * and provide point lookup by batchId. List-by-status is optional but
 * useful for operational scans.
 */
export interface IdempotentAnchorStore {
  /** Return the manifest for batchId, or null if not present. */
  get(batchId: BatchId): Promise<BatchManifest | null> | BatchManifest | null;
  /** Persist (insert or replace) the manifest. */
  put(manifest: BatchManifest): Promise<void> | void;
  /** Optional: list manifests by status (for retry / reconciliation
   *  loops). Implementations that don't care may throw. */
  listByStatus?(status: BatchStatus): Promise<BatchManifest[]> | BatchManifest[];
}

/** Caller-supplied submitter: builds + broadcasts the anchor tx and
 *  returns the post-submit state. Called at most once per batchId. */
export type BatchSubmitter = (req: {
  batchId: BatchId;
  sortedCellRoots: readonly Uint8Array[];
  window: BatchWindow;
}) => Promise<BatchSubmitResult> | BatchSubmitResult;

// ── Pure helpers ────────────────────────────────────────────────────

/**
 * Sort cell roots lexicographically ascending. This is the canonical
 * order: any two callers with the same set of roots compute the same
 * batchId regardless of submission order.
 *
 * Throws if any root is not exactly 32 bytes.
 */
export function sortCellRoots(roots: readonly Uint8Array[]): Uint8Array[] {
  for (const r of roots) {
    if (r.byteLength !== 32) {
      throw new Error(
        `sortCellRoots: each root must be 32 bytes, got ${r.byteLength}`,
      );
    }
  }
  const copies = roots.map(r => Uint8Array.from(r));
  copies.sort(compareBytes);
  return copies;
}

/**
 * Compute a deterministic 32-byte batch id:
 *
 *   batchId = SHA-256(
 *     "semantos.anchor.batch/v1" ‖
 *     varint(window.length) ‖ window ‖
 *     varint(cellRoots.length) ‖ root_0 ‖ root_1 ‖ ... ‖ root_{n-1}
 *   )
 *
 * where cellRoots are sorted lexicographically (see `sortCellRoots`).
 *
 * Two callers with the same set of roots + window produce identical
 * batchIds (idempotency). Distinct windows separate the batches.
 */
export function computeBatchId(
  cellRoots: readonly Uint8Array[],
  window: BatchWindow = new Uint8Array(0),
): BatchId {
  if (cellRoots.length === 0) {
    throw new Error('computeBatchId: cellRoots must be non-empty');
  }
  const sorted = sortCellRoots(cellRoots);
  const h = createHash('sha256');
  h.update('semantos.anchor.batch/v1');
  h.update(varint(window.byteLength));
  h.update(Buffer.from(window));
  h.update(varint(sorted.length));
  for (const r of sorted) {
    h.update(Buffer.from(r));
  }
  return new Uint8Array(h.digest());
}

// ── Idempotent submit ──────────────────────────────────────────────

/** Result of `requestAnchor`. `fromCache: true` means the batch was
 *  already submitted previously and we returned the existing manifest
 *  without calling the submitter. */
export interface RequestAnchorResult {
  manifest: BatchManifest;
  fromCache: boolean;
}

/**
 * Idempotent anchor request. Computes batchId from cellRoots + window,
 * checks the store, and either returns the existing manifest or calls
 * the submitter and persists a new one.
 *
 * Caller contract: same (cellRoots, window) → same batchId → same
 * manifest forever (until the store is wiped). If a previous submit
 * failed (`status === 'failed'`), a fresh call re-submits — failure
 * is not cached. If a previous submit reached `'broadcast'` or
 * `'confirmed'`, the cached manifest is returned without re-broadcast.
 */
export async function requestAnchor(input: {
  cellRoots: readonly Uint8Array[];
  window?: BatchWindow;
  store: IdempotentAnchorStore;
  submit: BatchSubmitter;
}): Promise<RequestAnchorResult> {
  const window = input.window ?? new Uint8Array(0);
  const batchId = computeBatchId(input.cellRoots, window);

  const existing = await input.store.get(batchId);
  if (existing && existing.status !== 'failed') {
    return { manifest: existing, fromCache: true };
  }

  const sortedCellRoots = sortCellRoots(input.cellRoots);
  const submitResult = await input.submit({
    batchId,
    sortedCellRoots,
    window,
  });

  const manifest: BatchManifest = {
    batchId,
    cellRoots: sortedCellRoots,
    window,
    status: submitResult.status,
    txid: submitResult.txid,
    anchorHeight: submitResult.anchorHeight,
    vout: submitResult.vout,
    attestationPayload: submitResult.attestationPayload,
  };
  await input.store.put(manifest);
  return { manifest, fromCache: false };
}

// ── In-memory store (for tests + ephemeral use) ────────────────────

/**
 * Simple Map-backed `IdempotentAnchorStore`. Not persistent; not
 * crash-consistent. Use for tests, in-process caches, and ephemeral
 * deployments. Production code should back this with LMDB / SQLite /
 * the brain's existing storage tier.
 */
export class InMemoryAnchorStore implements IdempotentAnchorStore {
  private readonly byBatchId = new Map<string, BatchManifest>();

  get(batchId: BatchId): BatchManifest | null {
    return this.byBatchId.get(bytesKey(batchId)) ?? null;
  }

  put(manifest: BatchManifest): void {
    this.byBatchId.set(bytesKey(manifest.batchId), manifest);
  }

  listByStatus(status: BatchStatus): BatchManifest[] {
    const out: BatchManifest[] = [];
    for (const m of this.byBatchId.values()) {
      if (m.status === status) out.push(m);
    }
    return out;
  }

  /** Convenience: number of stored manifests (mostly for tests). */
  size(): number {
    return this.byBatchId.size;
  }
}

// ── Internal helpers ───────────────────────────────────────────────

function compareBytes(a: Uint8Array, b: Uint8Array): number {
  const min = Math.min(a.byteLength, b.byteLength);
  for (let i = 0; i < min; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.byteLength - b.byteLength;
}

function bytesKey(b: Uint8Array): string {
  return Buffer.from(b).toString('hex');
}

/**
 * Bitcoin-style varint (compact size). Fits the encoded length of
 * the window + the cellRoots count without ambiguity across byte
 * lengths.
 */
function varint(n: number): Buffer {
  if (n < 0 || !Number.isInteger(n)) {
    throw new Error(`varint: must be non-negative integer, got ${n}`);
  }
  if (n < 0xfd) {
    const b = Buffer.alloc(1);
    b.writeUInt8(n, 0);
    return b;
  }
  if (n <= 0xffff) {
    const b = Buffer.alloc(3);
    b.writeUInt8(0xfd, 0);
    b.writeUInt16LE(n, 1);
    return b;
  }
  if (n <= 0xffffffff) {
    const b = Buffer.alloc(5);
    b.writeUInt8(0xfe, 0);
    b.writeUInt32LE(n, 1);
    return b;
  }
  // > u32 — Bitcoin varint goes to u64 here, but a batch with > 4B
  // cell roots is not a realistic scenario; throw rather than wire up
  // BigUInt64 just for it.
  throw new Error(`varint: value ${n} exceeds u32; not supported`);
}

```
