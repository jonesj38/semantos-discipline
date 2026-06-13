---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/output-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.653389+00:00
---

# cartridges/wallet-headers/brain/src/output-store.ts

```ts
// WA2 — LocalOutputStore (browser).
//
// Mirrors the vtable defined in `core/cell-engine/src/output_store.zig`.
// Backed by IndexedDB via `storage.ts`'s `outputs` object store. Same
// schema as the Zig native impl (round-tripped via `OutputRowV1`).
//
// Used by:
//   • wallet-ops.internalizeAction → addOutput
//   • wallet-ops.listOutputs       → list
//   • wallet-ops.signSpend         → markSpent (when spending tracking lands)
//   • recovery-scan.recoverySync   → addOutput per scanned UTXO (WA4)
//
// Three planned backings (per WALLET-ACTIVE-USE-ROADMAP §2 / WA2 deliv 1):
//   • LocalOutputStore (this file)            — v0.1 ships
//   • PlexusOutputStore                       — v0.2 paid mirror stub
//   • FederatedSemantosOutputStore            — v0.3 cross-node sync stub
// The interface below pins the surface so the next two slot in cleanly.

import {
  outputPut,
  outputGet,
  outputDelete,
  outputAll,
  outputList,
  type OutputRowV1,
} from './storage';

export type OutputStatus = 'unspent' | 'spent' | 'reorged';

/** WA2 OutputRecord — high-level shape that wallet-ops produces and consumes.
 *  Internally serialized into `OutputRowV1` for IndexedDB. */
export interface OutputRecord {
  outpoint: { txid: Uint8Array; vout: number };
  satoshis: bigint;
  lockingScript: Uint8Array;
  derivedKeyHash: Uint8Array;
  derivationContext: {
    protocolHash: Uint8Array; // 16
    counterparty: Uint8Array; // 33
    index: bigint;
  };
  beef: Uint8Array;
  basket: string;
  tags: string[];
  customInstructions: Uint8Array;
  confirmations: number;
  status: OutputStatus;
  spendingTxid: Uint8Array | null;
  /** 32-byte cell type_hash for LINEAR anchor UTXOs.  Absent for plain P2PKH
   *  (change, edge) outputs.  Present on basket='cell-anchors' records.
   *  On recovery: reconstruct protocolHash via anchorProtocolHash(typeHash). */
  typeHash?: Uint8Array;
}

/** WA2 LocalOutputStore — implements the vtable surface against the
 *  IndexedDB `outputs` object store. Methods are all idempotent at the
 *  outpoint-key level. */
export interface LocalOutputStore {
  addOutput(record: OutputRecord): Promise<{ inserted: boolean }>;
  listOutputs(filter?: ListFilter): Promise<OutputRecord[]>;
  getOutput(outpoint: { txid: Uint8Array; vout: number }): Promise<OutputRecord | null>;
  markSpent(
    outpoint: { txid: Uint8Array; vout: number },
    spendingTxid: Uint8Array,
  ): Promise<void>;
  pruneConfirmed(minConfirmations: number): Promise<number>;
  snapshot(): Promise<OutputRecord[]>;
  replay(records: OutputRecord[]): Promise<void>;
}

export interface ListFilter {
  basket?: string;
  tags?: string[];
  status?: OutputStatus;
}

// ──────────────────────────────────────────────────────────────────────
// Pruning thresholds (WA2 deliverable 2). v0.1 hard-coded; v0.2 wires
// these to the policy cell.
// ──────────────────────────────────────────────────────────────────────

export const PRUNE_BEEF_AFTER_CONFIRMATIONS = 100;
export const PRUNE_RECORD_AFTER_CONFIRMATIONS = 1000;

// ──────────────────────────────────────────────────────────────────────
// Implementation
// ──────────────────────────────────────────────────────────────────────

/** Process-wide shared instance — the OutputStore is stateless wrt
 *  in-memory caches (every method round-trips through IndexedDB), so a
 *  singleton handle is the cleanest abstraction. Callers should import
 *  this rather than calling `createLocalOutputStore()` directly. */
export let outputStore: LocalOutputStore;

export function createLocalOutputStore(): LocalOutputStore {
  return {
    async addOutput(record) {
      const key = outpointKey(record.outpoint);
      const existing = await outputGet(key);
      if (existing) {
        // Idempotent — the same UTXO arriving twice (e.g. two
        // internalizeAction calls for the same BEEF) is a no-op.
        return { inserted: false };
      }
      const row = recordToRow(record);
      await outputPut(row);
      return { inserted: true };
    },

    async listOutputs(filter = {}) {
      // Default: list only unspent UTXOs; callers pass status:'spent' or
      // 'reorged' if they want a wider view.
      const rows = await outputList({
        basket: filter.basket,
        tags: filter.tags ?? null,
        status: filter.status ?? 'unspent',
      });
      return rows.map(rowToRecord);
    },

    async getOutput(outpoint) {
      const row = await outputGet(outpointKey(outpoint));
      return row ? rowToRecord(row) : null;
    },

    async markSpent(outpoint, spendingTxid) {
      const key = outpointKey(outpoint);
      const row = await outputGet(key);
      if (!row) {
        throw new Error(`markSpent: unknown outpoint ${key}`);
      }
      row.status = 'spent';
      row.spendingTxidHex = bytesToHex(spendingTxid);
      await outputPut(row);
    },

    async pruneConfirmed(minConfirmations) {
      const all = await outputAll();
      let pruned = 0;
      for (const row of all) {
        let dirty = false;
        if (
          row.confirmations >= minConfirmations &&
          row.beefHex.length > 0
        ) {
          row.beefHex = '';
          dirty = true;
          pruned++;
        }
        if (
          row.status === 'spent' &&
          row.confirmations >= PRUNE_RECORD_AFTER_CONFIRMATIONS
        ) {
          await outputDelete(row.outpoint);
          pruned++;
          continue;
        }
        if (dirty) await outputPut(row);
      }
      return pruned;
    },

    async snapshot() {
      const rows = await outputAll();
      return rows.map(rowToRecord);
    },

    async replay(records) {
      // v0.1 ships a non-merging replay (matches Zig vtable contract):
      // delete every row, then insert the snapshot.
      const all = await outputAll();
      for (const row of all) await outputDelete(row.outpoint);
      for (const rec of records) {
        const row = recordToRow(rec);
        await outputPut(row);
      }
    },
  };
}

// Initialize the shared singleton at module load. IndexedDB connections
// are lazy in storage.ts so this doesn't open the DB until first use.
outputStore = createLocalOutputStore();

// ──────────────────────────────────────────────────────────────────────
// Row ↔ record conversion
// ──────────────────────────────────────────────────────────────────────

function recordToRow(record: OutputRecord): OutputRowV1 {
  return {
    outpoint: outpointKey(record.outpoint),
    satoshisDec: record.satoshis.toString(),
    lockingScriptHex: bytesToHex(record.lockingScript),
    derivedKeyHashHex: bytesToHex(record.derivedKeyHash),
    protocolHashHex: bytesToHex(record.derivationContext.protocolHash),
    counterpartyHex: bytesToHex(record.derivationContext.counterparty),
    derivationKey: `${bytesToHex(record.derivationContext.protocolHash)}:${bytesToHex(record.derivationContext.counterparty)}`,
    derivationIndexDec: record.derivationContext.index.toString(),
    beefHex: bytesToHex(record.beef),
    basket: record.basket || 'default',
    tags: record.tags.slice(),
    customInstructionsHex: bytesToHex(record.customInstructions),
    confirmations: record.confirmations,
    status: record.status,
    spendingTxidHex: record.spendingTxid ? bytesToHex(record.spendingTxid) : '',
    typeHashHex: record.typeHash ? bytesToHex(record.typeHash) : '',
    addedAt: Math.floor(Date.now() / 1000),
  };
}

function rowToRecord(row: OutputRowV1): OutputRecord {
  const [txidHex, voutStr] = row.outpoint.split(':');
  return {
    outpoint: {
      txid: hexToBytes(txidHex!),
      vout: Number(voutStr),
    },
    satoshis: BigInt(row.satoshisDec),
    lockingScript: hexToBytes(row.lockingScriptHex),
    derivedKeyHash: hexToBytes(row.derivedKeyHashHex),
    derivationContext: {
      protocolHash: hexToBytes(row.protocolHashHex),
      counterparty: hexToBytes(row.counterpartyHex),
      index: BigInt(row.derivationIndexDec),
    },
    beef: hexToBytes(row.beefHex),
    basket: row.basket,
    tags: row.tags.slice(),
    customInstructions: hexToBytes(row.customInstructionsHex),
    confirmations: row.confirmations,
    status: row.status,
    spendingTxid: row.spendingTxidHex ? hexToBytes(row.spendingTxidHex) : null,
    typeHash: row.typeHashHex ? hexToBytes(row.typeHashHex) : undefined,
  };
}

export function outpointKey(op: { txid: Uint8Array; vout: number }): string {
  return `${bytesToHex(op.txid)}:${op.vout}`;
}

// Local hex helpers — duplicated with wallet-ops to keep this module
// importable in isolation by tests.
function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

function hexToBytes(hex: string): Uint8Array {
  if (hex.length === 0) return new Uint8Array(0);
  if (hex.length % 2 !== 0) throw new Error('hex: odd length');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

```
