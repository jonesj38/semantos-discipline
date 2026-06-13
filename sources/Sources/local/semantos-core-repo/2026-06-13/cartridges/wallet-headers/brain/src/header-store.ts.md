---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/header-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.650190+00:00
---

# cartridges/wallet-headers/brain/src/header-store.ts

```ts
// Phase WH3 — Trustless SPV: IndexedDB-backed LocalHeaderStore.
//
// Reference: docs/design/WALLET-HEADERS-TRUSTLESS-SPV.md §2 (WH2 + WH3).
//
// Mirrors the vtable contract of `core/cell-engine/src/header_store.zig`:
// append-only over the verified chain, secondary index on hash, plus a
// snapshot/replay pair for sync and a rollback for WH4 reorgs.
//
// **Important invariant**: `appendValidated` only accepts headers that have
// already been validated by `header-validator.ts`. This module does NOT
// re-validate — the contract is "the WH3 fetcher / WH4 tip subscriber
// filter every byte through the verifier first." Misuse is a caller bug.
//
// Storage layout (one IndexedDB object store per concern):
//   • "headers"       keyed by u32 height → { header: Uint8Array, hash: Uint8Array }
//                     plus secondary index on hash → height
//   • "header_meta"   keyed by string → small metadata blobs (tip height,
//                     genesis_height for non-zero start, source-list config
//                     bookmark, etc.)

import { openWalletDb } from './storage';

const STORE_HEADERS = 'headers';
const STORE_HEADERS_HASH = 'hashHex'; // secondary index name (matches storage.ts)
const STORE_META = 'header_meta';

export interface HeaderRecord {
  header: Uint8Array; // 80 bytes raw
  hash: Uint8Array; // 32 bytes (internal byte order)
  height: number;
}

/** Internal IDB row layout — we store the hash as hex (string) to keep the
 *  secondary index portable across IDB implementations. The Uint8Array
 *  surface (`HeaderRecord`) is reconstructed in the get* methods. */
interface HeaderRow {
  height: number;
  header: Uint8Array;
  hash: Uint8Array;
  hashHex: string;
}

function hexFromBytes(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

function rowToRecord(row: HeaderRow): HeaderRecord {
  return { height: row.height, header: row.header, hash: row.hash };
}

export type HeaderStoreError =
  | 'prev_hash_mismatch'
  | 'height_out_of_order'
  | 'persistence_failed'
  | 'not_found';

/** The headers + header_meta object stores are created by storage.ts at DB
 *  open time (DB_VERSION includes them), so this is just a thin wrapper. */
async function openWithHeaders(): Promise<IDBDatabase> {
  return await openWalletDb();
}

function asPromise<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

/**
 * IndexedDB-backed local header store.
 *
 * Pluggable in the same shape as `core/cell-engine/src/header_store.zig`'s
 * `LocalHeaderStore`. Future v0.2/v0.3 mirror to Plexus / sovereign-node
 * federation slots in alongside.
 */
export class LocalHeaderStore {
  /** Returns the header at the given height, or null if not stored. */
  async getByHeight(height: number): Promise<HeaderRecord | null> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_HEADERS, 'readonly');
    const v = await asPromise<HeaderRow | undefined>(tx.objectStore(STORE_HEADERS).get(height));
    return v ? rowToRecord(v) : null;
  }

  /** Returns the header with the given (32-byte) hash, or null. */
  async getByHash(hash: Uint8Array): Promise<HeaderRecord | null> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_HEADERS, 'readonly');
    const idx = tx.objectStore(STORE_HEADERS).index(STORE_HEADERS_HASH);
    const v = await asPromise<HeaderRow | undefined>(idx.get(hexFromBytes(hash)));
    return v ? rowToRecord(v) : null;
  }

  /** Returns the tip record (highest height) or null if empty. */
  async tip(): Promise<HeaderRecord | null> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_HEADERS, 'readonly');
    const cursor = tx.objectStore(STORE_HEADERS).openCursor(null, 'prev');
    return await new Promise<HeaderRecord | null>((resolve, reject) => {
      cursor.onsuccess = () => {
        const c = cursor.result;
        resolve(c ? rowToRecord(c.value as HeaderRow) : null);
      };
      cursor.onerror = () => reject(cursor.error);
    });
  }

  /**
   * Append a validated header.
   *
   * Fails (`prev_hash_mismatch`) if the new header's `prev_hash` doesn't
   * match the current tip's hash. Fails (`height_out_of_order`) if the new
   * `height` isn't `tip.height + 1` (or 0 if empty + first record's
   * `prev_hash` is whatever — first record is accepted as a chain origin).
   *
   * Atomic: the index entry and the height entry are written in the same
   * IndexedDB transaction.
   */
  async appendValidated(record: HeaderRecord): Promise<HeaderStoreError | null> {
    const db = await openWithHeaders();
    const tip = await this.tip();
    if (tip) {
      if (record.height !== tip.height + 1) return 'height_out_of_order';
      // Validate prev_hash linkage. record.header[4..36] is the prev_hash field.
      const prevHashField = record.header.slice(4, 36);
      if (!bytesEqual(prevHashField, tip.hash)) return 'prev_hash_mismatch';
    }
    try {
      const tx = db.transaction(STORE_HEADERS, 'readwrite');
      const row: HeaderRow = {
        height: record.height,
        header: record.header,
        hash: record.hash,
        hashHex: hexFromBytes(record.hash),
      };
      tx.objectStore(STORE_HEADERS).put(row, record.height);
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
      return null;
    } catch {
      return 'persistence_failed';
    }
  }

  /** Snapshot all records in monotone height order. */
  async snapshot(): Promise<HeaderRecord[]> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_HEADERS, 'readonly');
    return await new Promise<HeaderRecord[]>((resolve, reject) => {
      const out: HeaderRecord[] = [];
      const cursor = tx.objectStore(STORE_HEADERS).openCursor();
      cursor.onsuccess = () => {
        const c = cursor.result;
        if (!c) return resolve(out);
        out.push(rowToRecord(c.value as HeaderRow));
        c.continue();
      };
      cursor.onerror = () => reject(cursor.error);
    });
  }

  /**
   * Replace local state with `records` (monotone height order, valid
   * prev_hash chain). Used for cross-device recovery sync. Replay does NOT
   * re-validate PoW — caller must have done so.
   */
  async replay(records: HeaderRecord[]): Promise<HeaderStoreError | null> {
    const db = await openWithHeaders();
    // Sanity check the chain before opening a write transaction.
    for (let i = 1; i < records.length; i++) {
      if (records[i].height !== records[i - 1].height + 1) return 'height_out_of_order';
      const prevField = records[i].header.slice(4, 36);
      if (!bytesEqual(prevField, records[i - 1].hash)) return 'prev_hash_mismatch';
    }
    try {
      const tx = db.transaction(STORE_HEADERS, 'readwrite');
      const store = tx.objectStore(STORE_HEADERS);
      store.clear();
      for (const r of records) {
        const row: HeaderRow = {
          height: r.height,
          header: r.header,
          hash: r.hash,
          hashHex: hexFromBytes(r.hash),
        };
        store.put(row, r.height);
      }
      await new Promise<void>((resolve, reject) => {
        tx.oncomplete = () => resolve();
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
      return null;
    } catch {
      return 'persistence_failed';
    }
  }

  /**
   * Drop every record at height >= `fromHeight`. Used by WH4 reorg
   * handling. Returns the count of dropped records.
   */
  async rollbackFrom(fromHeight: number): Promise<number> {
    const db = await openWithHeaders();
    // Two passes: collect keys, then delete. Avoids cursor-during-write
    // edge cases in fake-indexeddb / older Safari.
    const heights = await new Promise<number[]>((resolve, reject) => {
      const tx = db.transaction(STORE_HEADERS, 'readonly');
      const store = tx.objectStore(STORE_HEADERS);
      const out: number[] = [];
      // Walk from the start; collect heights >= fromHeight. Avoids
      // IDBKeyRange.lowerBound which fake-indexeddb errors on for some
      // store-key configurations.
      const cursor = store.openCursor();
      cursor.onsuccess = () => {
        const c = cursor.result;
        if (!c) return resolve(out);
        const k = c.key as number;
        if (k >= fromHeight) out.push(k);
        c.continue();
      };
      cursor.onerror = () => reject(cursor.error);
    });
    if (heights.length === 0) return 0;
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE_HEADERS, 'readwrite');
      const store = tx.objectStore(STORE_HEADERS);
      for (const k of heights) store.delete(k);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
    return heights.length;
  }

  // ── Misc metadata ──

  async metaGet<T = unknown>(key: string): Promise<T | null> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_META, 'readonly');
    const v = await asPromise<T | undefined>(tx.objectStore(STORE_META).get(key));
    return v ?? null;
  }

  async metaPut(key: string, value: unknown): Promise<void> {
    const db = await openWithHeaders();
    const tx = db.transaction(STORE_META, 'readwrite');
    tx.objectStore(STORE_META).put(value, key);
    await new Promise<void>((resolve, reject) => {
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }
}

/** Convenience: format a hash as the standard display-LE hex (reversed). */
export function hashToDisplayHex(hash: Uint8Array): string {
  const reversed = new Uint8Array(hash.length);
  for (let i = 0; i < hash.length; i++) reversed[i] = hash[hash.length - 1 - i];
  return bytesToHex(reversed);
}

```
