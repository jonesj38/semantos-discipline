---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/brain-sync.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.054137+00:00
---

# runtime/session-protocol/src/swarm/brain-sync.ts

```ts
/**
 * brain-sync — the SECOND consumer of the transfer primitive (the proof that
 * this is a protocol, not a torrent client).
 *
 * One brain reconciles the cells it holds against a peer's by moving the delta
 * over MeteredTransfer: the missing cells are packed into a single batch blob,
 * shared (one manifest, chunked, merkle-verified, metered), fetched by the peer,
 * then split back into 1024-byte cells and put into the peer's cell store. The
 * exact same engine the torrent client uses — different consumer, same paid
 * data plane. This is the [[bridget_federation_ready]] brain-to-brain test.
 *
 * The cell store is abstracted as CellSource (enumerate + fetch) and CellSink
 * (has + put) so this unit-tests without booting a brain; the production adapter
 * wraps GET /api/v1/cell/<hash> + /api/v1/cell/since (cell_raw_http.zig) and the
 * brain's cell_store.put.
 */

import { sha256, toHex } from '@semantos/protocol-types';
import type { MeteredTransfer } from './metered-transfer';

/** Cells are the fixed 1024-byte wire unit (256B header + 768B payload). */
export const CELL_BYTES = 1024;

/** A brain's cells, enumerable + fetchable by content hash. */
export interface CellSource {
  /** Content hashes (hex) of cells available, optionally since a cursor. */
  listHashes(sinceCursor?: string): Promise<string[]>;
  /** The raw 1024-byte cell for a hash, or null if gone. */
  getCell(hash: string): Promise<Uint8Array | null>;
}

/** A brain's cell store, idempotent on content hash. */
export interface CellSink {
  has(hash: string): Promise<boolean>;
  /** Store a cell; returns its content hash (hex). */
  putCell(bytes: Uint8Array): Promise<string>;
}

/** Content hash of a cell (hex) — sha256 of the 1024 bytes. */
export function cellHash(bytes: Uint8Array): string {
  return toHex(sha256(bytes));
}

/** Pack uniform 1024-byte cells into one contiguous blob. */
export function packCellBatch(cells: Uint8Array[]): Uint8Array {
  const blob = new Uint8Array(cells.length * CELL_BYTES);
  cells.forEach((c, i) => blob.set(c.subarray(0, CELL_BYTES), i * CELL_BYTES));
  return blob;
}

/** Split a batch blob back into 1024-byte cells. */
export function unpackCellBatch(blob: Uint8Array): Uint8Array[] {
  const n = Math.floor(blob.length / CELL_BYTES);
  const out: Uint8Array[] = [];
  for (let i = 0; i < n; i++) out.push(blob.slice(i * CELL_BYTES, (i + 1) * CELL_BYTES));
  return out;
}

export interface SyncResult {
  /** The magnet the batch was transferred under (absent when nothing to sync). */
  magnet?: string;
  /** Number of cells delivered to the sink. */
  transferred: number;
  /** Content hashes the sink now holds from this sync. */
  hashes: string[];
}

export interface SyncOptions {
  /** The cells to reconcile FROM (the authority for this sync). */
  from: CellSource;
  /** The store to reconcile INTO. */
  to: CellSink;
  /** Shares the batch (the source brain's transfer engine). */
  seeder: MeteredTransfer;
  /** Fetches the batch (the sink brain's transfer engine). */
  leecher: MeteredTransfer;
  /** Only consider source cells newer than this cursor. */
  sinceCursor?: string;
  /** Label for the transferred batch. */
  name?: string;
  /** Fetch timeout. */
  timeoutMs?: number;
}

/**
 * Reconcile the cells `from` holds that `to` lacks, moving the delta over the
 * metered transfer primitive. Returns what was delivered.
 */
export async function syncCells(opts: SyncOptions): Promise<SyncResult> {
  const srcHashes = await opts.from.listHashes(opts.sinceCursor);

  // Compute the delta the sink is missing.
  const missing: string[] = [];
  for (const h of srcHashes) {
    if (!(await opts.to.has(h))) missing.push(h);
  }
  if (missing.length === 0) return { transferred: 0, hashes: [] };

  // Gather the missing cells from the source.
  const cells: Uint8Array[] = [];
  for (const h of missing) {
    const c = await opts.from.getCell(h);
    if (c && c.length >= CELL_BYTES) cells.push(c);
  }
  if (cells.length === 0) return { transferred: 0, hashes: [] };

  // Move them as one batch over the transfer primitive (metered + verified).
  const blob = packCellBatch(cells);
  const magnet = await opts.seeder.share(blob, opts.name ?? 'cell-sync');
  const got = await opts.leecher.fetch(magnet, { timeoutMs: opts.timeoutMs ?? 30_000 });

  // Split back into cells and persist into the sink.
  const recovered = unpackCellBatch(got);
  const hashes: string[] = [];
  for (const cell of recovered) hashes.push(await opts.to.putCell(cell));

  return { magnet, transferred: recovered.length, hashes };
}

/**
 * In-memory cell store implementing both CellSource and CellSink — a test
 * double + a usable default for non-persistent peers. Content-addressed by
 * sha256, matching the brain's cell hashing.
 */
export class MemoryCellStore implements CellSource, CellSink {
  private readonly cells = new Map<string, Uint8Array>();

  put(bytes: Uint8Array): string {
    const h = cellHash(bytes);
    if (!this.cells.has(h)) this.cells.set(h, bytes.slice(0, CELL_BYTES));
    return h;
  }
  async putCell(bytes: Uint8Array): Promise<string> {
    return this.put(bytes);
  }
  async has(hash: string): Promise<boolean> {
    return this.cells.has(hash);
  }
  async getCell(hash: string): Promise<Uint8Array | null> {
    const c = this.cells.get(hash);
    return c ? c.slice() : null;
  }
  async listHashes(_sinceCursor?: string): Promise<string[]> {
    return [...this.cells.keys()];
  }
  get size(): number {
    return this.cells.size;
  }
}

```
