---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/storage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.660265+00:00
---

# cartridges/wallet-headers/brain/src/storage.ts

```ts
// IndexedDB-backed persistence for the browser wallet bundle.
//
// Mirrors the vtable contracts of:
//   • core/cell-engine/src/slot_store.zig         (LocalSlotStore)
//   • core/cell-engine/src/derivation_state.zig   (LocalStateStore)
//
// Per WALLET-TIER-CUSTODY.md §10.1 the browser bundle backs both with
// IndexedDB at the wallet origin so a tab refresh / browser restart preserves
// tier blobs, the BRC-42 next-index counters, the POLICY cell, and the BRC-52
// cert. fake-indexeddb makes the same code work under bun test.
//
// Three object stores live under the same DB:
//   • "slots"     keyed by u32 slot_id      → encrypted cell envelope (Uint8Array)
//   • "state"     keyed by hex(protocol||cp) → { current_index: number }
//   • "kv"        keyed by string            → arbitrary value (POLICY, BRC-52)

const DB_NAME = 'semantos-wallet';
/** WA2 bumped DB_VERSION 1 → 2 to add the `outputs` object store. WH3 bumped
 *  2 → 3 to add the `headers` and `header_meta` stores. The `onupgradeneeded`
 *  handler is additive — fresh DBs get every store at the current version,
 *  existing DBs get the new ones added on upgrade. */
const DB_VERSION = 3;
const STORE_SLOTS = 'slots';
const STORE_STATE = 'state';
const STORE_KV = 'kv';
/** WA2 — UTXO database. Keyed by `txid:vout` string; values are the JSON-
 *  stringifiable shape of OutputRecord (BEEF kept hex-encoded). */
const STORE_OUTPUTS = 'outputs';
/** WH3 — verified-headers database. Keyed by u32 height; values are
 *  HeaderRecord ({ header, hash, height }). Secondary index on hash. */
const STORE_HEADERS = 'headers';
const STORE_HEADER_META = 'header_meta';

let dbPromise: Promise<IDBDatabase> | null = null;
let dbHandle: IDBDatabase | null = null;

/** Open (or create) the wallet IndexedDB. Idempotent — caches the handle. */
export function openWalletDb(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE_SLOTS)) db.createObjectStore(STORE_SLOTS);
      if (!db.objectStoreNames.contains(STORE_STATE)) db.createObjectStore(STORE_STATE);
      if (!db.objectStoreNames.contains(STORE_KV)) db.createObjectStore(STORE_KV);
      // WA2 — outputs store. Secondary indices speed up listOutputs(basket,
      // tags) and listOutputs(derivation_context) joins.
      if (!db.objectStoreNames.contains(STORE_OUTPUTS)) {
        const os = db.createObjectStore(STORE_OUTPUTS);
        os.createIndex('by_basket_status', ['basket', 'status'], { unique: false });
        os.createIndex('by_context_status', ['derivationKey', 'status'], { unique: false });
      }
      // WH3 — verified headers store. Keyed by height. We store the hash as
      // a hex string ("hashHex" property) so a secondary index works across
      // every IDB implementation (fake-indexeddb included). Raw bytes for
      // both the 80-byte header and the 32-byte hash are also stored
      // alongside for callers that need them without re-decoding.
      if (!db.objectStoreNames.contains(STORE_HEADERS)) {
        const hs = db.createObjectStore(STORE_HEADERS);
        hs.createIndex('hashHex', 'hashHex', { unique: true });
      }
      if (!db.objectStoreNames.contains(STORE_HEADER_META)) {
        db.createObjectStore(STORE_HEADER_META);
      }
    };
    req.onsuccess = () => {
      dbHandle = req.result;
      resolve(req.result);
    };
    req.onerror = () => reject(req.error);
  });
  return dbPromise;
}

/** Tests-only: close the cached connection and drop the handle so the next
 *  openWalletDb gets a fresh one. Closing the connection synchronously is
 *  required for `indexedDB.deleteDatabase` to actually delete data — an
 *  open connection blocks deletion in fake-indexeddb. */
export function _resetDbForTests(): void {
  if (dbHandle) {
    try {
      dbHandle.close();
    } catch {
      /* ignore */
    }
  }
  dbHandle = null;
  dbPromise = null;
}

function txStore(db: IDBDatabase, name: string, mode: IDBTransactionMode): IDBObjectStore {
  return db.transaction(name, mode).objectStore(name);
}

function asPromise<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

// ── slot_store.zig vtable equivalent ──

export async function slotGet(slotId: number): Promise<Uint8Array | null> {
  const db = await openWalletDb();
  const v = await asPromise<Uint8Array | undefined>(
    txStore(db, STORE_SLOTS, 'readonly').get(slotId),
  );
  return v ?? null;
}

export async function slotPut(slotId: number, bytes: Uint8Array): Promise<void> {
  const db = await openWalletDb();
  // Always copy — IndexedDB structured-clones, but a copy guards against the
  // caller mutating their buffer between Promise resolution and persistence.
  const copy = new Uint8Array(bytes);
  await asPromise(txStore(db, STORE_SLOTS, 'readwrite').put(copy, slotId));
}

export async function slotDelete(slotId: number): Promise<void> {
  const db = await openWalletDb();
  await asPromise(txStore(db, STORE_SLOTS, 'readwrite').delete(slotId));
}

// ── derivation_state.zig vtable equivalent ──

/** Compose (protocol_hash || counterparty) → 49-byte hex key. */
function deriveStateKey(protocolHash: Uint8Array, counterparty: Uint8Array): string {
  if (protocolHash.length !== 16 || counterparty.length !== 33) {
    throw new Error('state key: bad lengths');
  }
  let s = '';
  for (const b of protocolHash) s += b.toString(16).padStart(2, '0');
  for (const b of counterparty) s += b.toString(16).padStart(2, '0');
  return s;
}

/**
 * Atomically allocate the next BRC-42 derivation index for a (protocol,
 * counterparty) context. Uses a single readwrite transaction so concurrent
 * callers see linearizable increments — mirrors §6.4 / W3.5 atomic semantics.
 *
 * Note: in IndexedDB, two transactions opened in the same microtask serialize
 * — that's how we get atomicity without an explicit lock.
 */
export async function stateNextIndex(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
): Promise<bigint> {
  const db = await openWalletDb();
  const key = deriveStateKey(protocolHash, counterparty);
  return await new Promise<bigint>((resolve, reject) => {
    const tx = db.transaction(STORE_STATE, 'readwrite');
    const store = tx.objectStore(STORE_STATE);
    const getReq = store.get(key);
    getReq.onsuccess = () => {
      const cur = getReq.result as { current_index: string } | undefined;
      // Stored as a decimal string to avoid Number precision loss above 2^53.
      const next = cur ? BigInt(cur.current_index) + 1n : 0n;
      const putReq = store.put({ current_index: next.toString() }, key);
      putReq.onsuccess = () => resolve(next);
      putReq.onerror = () => reject(putReq.error);
    };
    getReq.onerror = () => reject(getReq.error);
  });
}

export async function stateGetIndex(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
): Promise<bigint | null> {
  const db = await openWalletDb();
  const key = deriveStateKey(protocolHash, counterparty);
  const v = await asPromise<{ current_index: string } | undefined>(
    txStore(db, STORE_STATE, 'readonly').get(key),
  );
  return v ? BigInt(v.current_index) : null;
}

/** WA3: enumerate every (protocol_hash, counterparty, current_index) row in
 *  the state store. Used by `snapshotDerivationContexts` to build the envelope
 *  records list at export time. Returns hex-encoded protocol_hash + counterparty
 *  to match `DerivationStateRecord` shape. */
export interface StateSnapshotRow {
  protocolHash: string;
  counterparty: string;
  currentIndex: bigint;
}

export async function stateSnapshot(): Promise<StateSnapshotRow[]> {
  const db = await openWalletDb();
  return await new Promise<StateSnapshotRow[]>((resolve, reject) => {
    const tx = db.transaction(STORE_STATE, 'readonly');
    const store = tx.objectStore(STORE_STATE);
    const out: StateSnapshotRow[] = [];
    const req = store.openCursor();
    req.onsuccess = () => {
      const cursor = req.result;
      if (cursor) {
        const key = cursor.key as string;
        // Composed in deriveStateKey: 16-byte protocol_hash || 33-byte counterparty
        // → 49 bytes → 98 hex chars. Skip rows that don't match.
        if (typeof key === 'string' && key.length === 98) {
          const value = cursor.value as { current_index: string } | undefined;
          if (value && typeof value.current_index === 'string') {
            out.push({
              protocolHash: key.slice(0, 32),
              counterparty: key.slice(32),
              currentIndex: BigInt(value.current_index),
            });
          }
        }
        cursor.continue();
      } else {
        resolve(out);
      }
    };
    req.onerror = () => reject(req.error);
  });
}

// ── KV store for misc artifacts (POLICY cell, BRC-52 cert, etc) ──

export async function kvGet<T = unknown>(key: string): Promise<T | null> {
  const db = await openWalletDb();
  const v = await asPromise<T | undefined>(txStore(db, STORE_KV, 'readonly').get(key));
  return v ?? null;
}

export async function kvPut(key: string, value: unknown): Promise<void> {
  const db = await openWalletDb();
  await asPromise(txStore(db, STORE_KV, 'readwrite').put(value, key));
}

// ── output_store.zig vtable equivalent ──

/** Persisted OutputRecord shape — mirrors the Zig OutputRecord struct in
 *  core/cell-engine/src/output_store.zig but uses string-encoded fields so
 *  the row JSON-roundtrips through structured-clone.
 *
 *  Variable-length byte fields (locking_script, beef, custom_instructions)
 *  are hex-encoded. Tags is a JSON array of strings. The `derivationKey`
 *  hex string is the same `${protocolHash}:${counterparty}` shape used by
 *  ContextRegistry, so the secondary index supports listOutputs by
 *  derivation context without re-deriving keys. */
export interface OutputRowV1 {
  /** Outpoint key — `<txid_hex>:<vout>`. Also the IndexedDB key. */
  outpoint: string;
  /** Decimal string to dodge JS Number precision (sats > 2^53 plausible). */
  satoshisDec: string;
  lockingScriptHex: string;
  derivedKeyHashHex: string;
  /** 16-byte hex protocol_hash. */
  protocolHashHex: string;
  /** 33-byte hex counterparty pubkey. */
  counterpartyHex: string;
  /** Hex composite for index lookups: `${protocolHashHex}:${counterpartyHex}`. */
  derivationKey: string;
  /** Decimal string. */
  derivationIndexDec: string;
  /** May be empty after pruneConfirmed drops it. */
  beefHex: string;
  /** Hex-encoded 32-byte type_hash for LINEAR cell anchor UTXOs.  Empty string
   *  for ordinary change/edge outputs.  Enables basket='cell-anchors' filter
   *  and recovery-scan reconstruction of anchor protocolHash. */
  typeHashHex: string;
  /** "default" / "incoming" / app-defined. Empty string normalized to "default". */
  basket: string;
  tags: string[];
  customInstructionsHex: string;
  confirmations: number;
  /** "unspent" | "spent" | "reorged". */
  status: 'unspent' | 'spent' | 'reorged';
  spendingTxidHex: string;
  /** Unix-seconds when first added — supports time-bounded pruning policies. */
  addedAt: number;
}

export async function outputPut(row: OutputRowV1): Promise<void> {
  const db = await openWalletDb();
  await asPromise(txStore(db, STORE_OUTPUTS, 'readwrite').put(row, row.outpoint));
}

export async function outputGet(outpoint: string): Promise<OutputRowV1 | null> {
  const db = await openWalletDb();
  const v = await asPromise<OutputRowV1 | undefined>(
    txStore(db, STORE_OUTPUTS, 'readonly').get(outpoint),
  );
  return v ?? null;
}

export async function outputDelete(outpoint: string): Promise<void> {
  const db = await openWalletDb();
  await asPromise(txStore(db, STORE_OUTPUTS, 'readwrite').delete(outpoint));
}

export async function outputAll(): Promise<OutputRowV1[]> {
  const db = await openWalletDb();
  return await new Promise<OutputRowV1[]>((resolve, reject) => {
    const tx = db.transaction(STORE_OUTPUTS, 'readonly');
    const store = tx.objectStore(STORE_OUTPUTS);
    const req = store.openCursor();
    const out: OutputRowV1[] = [];
    req.onsuccess = () => {
      const cursor = req.result;
      if (cursor) {
        out.push(cursor.value as OutputRowV1);
        cursor.continue();
      } else {
        resolve(out);
      }
    };
    req.onerror = () => reject(req.error);
  });
}

/** Filter by basket + tag set + status. `tags: null` = no tag filter; if
 *  given, the row must include every tag in the filter. */
export async function outputList(filter: {
  basket?: string;
  tags?: string[] | null;
  status?: OutputRowV1['status'];
}): Promise<OutputRowV1[]> {
  const all = await outputAll();
  return all.filter((r) => {
    if (filter.status && r.status !== filter.status) return false;
    if (filter.basket !== undefined && r.basket !== filter.basket) return false;
    if (filter.tags && filter.tags.length > 0) {
      for (const t of filter.tags) {
        if (!r.tags.includes(t)) return false;
      }
    }
    return true;
  });
}

```
