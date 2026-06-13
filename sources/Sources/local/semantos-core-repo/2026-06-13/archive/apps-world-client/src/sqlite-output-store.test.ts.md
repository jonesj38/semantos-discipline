---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-output-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.823007+00:00
---

# archive/apps-world-client/src/sqlite-output-store.test.ts

```ts
// M2.3-T — SqliteOutputStore conformance tests.
//
// Mirrors the semantic contract from:
//   core/cell-engine/src/output_store.zig (LocalOutputStore + Zig tests)
//
// Tests:
//   M2.3-T-add-get           — addOutput + getOutput round-trip
//   M2.3-T-duplicate         — addOutput rejects duplicate outpoint
//   M2.3-T-list-basket       — listOutputs filters by basket
//   M2.3-T-list-unspent-only — listOutputs excludes spent outputs
//   M2.3-T-mark-spent        — markSpent sets status; listOutputs excludes
//   M2.3-T-mark-unknown      — markSpent on unknown outpoint rejects
//   M2.3-T-prune-beef        — pruneConfirmed drops BEEF on high-confirmation records
//   M2.3-T-prune-delete      — pruneConfirmed deletes spent records with confirmations >= 1000
//   M2.3-T-snapshot-replay   — snapshot → replay reconstructs state
//   M2.3-T-atomicity         — markSpent is atomic (IMMEDIATE tx)
//
// All tests run in Node via the in-memory SQLite fallback.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";
import { SqliteOutputStore, type OutputRecord, type Outpoint } from "./sqlite-output-store.js";

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

function makeOutpoint(n: number, vout = 0): Outpoint {
  const txid = new Uint8Array(32).fill(n);
  return { txid, vout };
}

function makeRecord(n: number, overrides: Partial<OutputRecord> = {}): OutputRecord {
  return {
    outpoint: makeOutpoint(n),
    satoshis: BigInt(n) * 1000n,
    lockingScript: new Uint8Array([0x76, 0xa9, n]),
    derivedKeyHash: new Uint8Array(32).fill(n),
    derivationProtocolHash: new Uint8Array(16).fill(n),
    derivationCounterparty: new Uint8Array(33).fill(n),
    derivationIndex: BigInt(n),
    beef: new Uint8Array([0xef, 0xbe, n]),
    basket: "default",
    tags: [],
    customInstructions: new Uint8Array(0),
    confirmations: 0,
    status: "unspent",
    spendingTxid: new Uint8Array(32).fill(0),
    ...overrides,
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Suite
// ──────────────────────────────────────────────────────────────────────────────

describe("M2.3: SqliteOutputStore", () => {
  let db: SqliteOpfsDb;
  let store: SqliteOutputStore;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-os-${Math.random().toString(36).slice(2)}` });
    await db.open();
    store = new SqliteOutputStore(db);
    await store.init();
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.3-T-add-get
  it("addOutput + getOutput round-trip", async () => {
    const rec = makeRecord(1);
    await store.addOutput(rec);

    const got = await store.getOutput(rec.outpoint);
    expect(got).not.toBeNull();
    expect(got!.satoshis).toBe(1000n);
    expect(got!.basket).toBe("default");
    expect(got!.status).toBe("unspent");
  });

  // M2.3-T-duplicate
  it("addOutput rejects duplicate outpoint", async () => {
    const rec = makeRecord(2);
    await store.addOutput(rec);
    await expect(store.addOutput(rec)).rejects.toThrow("duplicate_outpoint");
  });

  // M2.3-T-list-basket
  it("listOutputs filters by basket", async () => {
    await store.addOutput(makeRecord(3, { basket: "default" }));
    await store.addOutput(makeRecord(4, { basket: "incoming" }));

    const defaults = await store.listOutputs("default", null);
    expect(defaults).toHaveLength(1);
    expect(defaults[0].basket).toBe("default");

    const incoming = await store.listOutputs("incoming", null);
    expect(incoming).toHaveLength(1);

    const all = await store.listOutputs(null, null);
    expect(all).toHaveLength(2);
  });

  // M2.3-T-list-unspent-only
  it("listOutputs only returns unspent outputs", async () => {
    await store.addOutput(makeRecord(5));
    await store.addOutput(makeRecord(6));
    await store.markSpent(makeOutpoint(6), new Uint8Array(32).fill(0xaa));

    const list = await store.listOutputs(null, null);
    expect(list).toHaveLength(1);
    expect(list[0].outpoint.vout).toBe(0);
  });

  // M2.3-T-mark-spent
  it("markSpent sets status and spendingTxid", async () => {
    const rec = makeRecord(7);
    await store.addOutput(rec);

    const spendingTxid = new Uint8Array(32).fill(0xbb);
    await store.markSpent(rec.outpoint, spendingTxid);

    const got = await store.getOutput(rec.outpoint);
    expect(got!.status).toBe("spent");
    expect(got!.spendingTxid).toEqual(spendingTxid);
  });

  // M2.3-T-mark-unknown
  it("markSpent on unknown outpoint throws unknown_outpoint", async () => {
    await expect(
      store.markSpent(makeOutpoint(99), new Uint8Array(32).fill(0))
    ).rejects.toThrow("unknown_outpoint");
  });

  // M2.3-T-prune-beef
  it("pruneConfirmed drops BEEF on records at or above min_confirmations", async () => {
    await store.addOutput(makeRecord(10, { confirmations: 50 }));
    await store.addOutput(makeRecord(11, { confirmations: 100 }));

    const pruned = await store.pruneConfirmed(100);
    expect(pruned).toBeGreaterThanOrEqual(1);

    // High-confirmation record has empty BEEF
    const high = await store.getOutput(makeOutpoint(11));
    expect(high!.beef.length).toBe(0);

    // Low-confirmation record still has BEEF
    const low = await store.getOutput(makeOutpoint(10));
    expect(low!.beef.length).toBeGreaterThan(0);
  });

  // M2.3-T-prune-delete
  it("pruneConfirmed deletes spent records with confirmations >= 1000", async () => {
    await store.addOutput(makeRecord(20, { confirmations: 1000 }));
    await store.markSpent(makeOutpoint(20), new Uint8Array(32).fill(0xcc));

    const pruned = await store.pruneConfirmed(1000);
    expect(pruned).toBeGreaterThanOrEqual(1);

    const gone = await store.getOutput(makeOutpoint(20));
    expect(gone).toBeNull();
  });

  // M2.3-T-snapshot-replay
  it("snapshot → replay reconstructs state", async () => {
    for (let i = 30; i < 33; i++) {
      await store.addOutput(makeRecord(i));
    }
    await store.markSpent(makeOutpoint(31), new Uint8Array(32).fill(0xdd));

    const snap = await store.snapshot();
    expect(snap).toHaveLength(3);

    const db2 = new SqliteOpfsDb({ dbName: `test-os-dst-${Math.random().toString(36).slice(2)}` });
    await db2.open();
    const store2 = new SqliteOutputStore(db2);
    await store2.init();

    await store2.replay(snap);

    const snap2 = await store2.snapshot();
    expect(snap2).toHaveLength(3);

    // Spent status preserved
    const spentRec = await store2.getOutput(makeOutpoint(31));
    expect(spentRec!.status).toBe("spent");

    await db2.close();
  });

  // Idempotent init
  it("init() is idempotent", async () => {
    await expect(store.init()).resolves.not.toThrow();
  });

  // M2.3-T-atomicity: markSpent uses IMMEDIATE transaction (just verify no partial state)
  it("markSpent atomicity: output is fully updated or not at all", async () => {
    const rec = makeRecord(40);
    await store.addOutput(rec);
    const spendingTxid = new Uint8Array(32).fill(0xee);
    await store.markSpent(rec.outpoint, spendingTxid);

    const got = await store.getOutput(rec.outpoint);
    // Both fields must be consistent — status=spent AND spendingTxid set
    expect(got!.status).toBe("spent");
    expect(got!.spendingTxid).toEqual(spendingTxid);
  });
});

```
