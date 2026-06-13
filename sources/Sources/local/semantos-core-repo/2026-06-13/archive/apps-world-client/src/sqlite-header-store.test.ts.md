---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-header-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.825144+00:00
---

# archive/apps-world-client/src/sqlite-header-store.test.ts

```ts
// M2.2-T — SqliteHeaderStore conformance tests.
//
// Mirrors the semantic contract from:
//   core/cell-engine/tests/header_store_conformance.zig
//   core/cell-engine/src/header_store.zig (LocalHeaderStore)
//
// Tests:
//   M2.2-T-put-get          — put/get round-trip by height and hash
//   M2.2-T-missing-key      — get of unknown height returns null
//   M2.2-T-tip              — tip() tracks the last appended height
//   M2.2-T-reorg-rollback   — write heights 1–10, rollback from 6, verify
//   M2.2-T-cursor-order     — allByHeight() returns records in height order
//   M2.2-T-snapshot-replay  — snapshot → replay reconstructs state
//   M2.2-T-prev-hash-check  — appendValidated rejects wrong prev_hash
//   M2.2-T-height-order     — appendValidated rejects out-of-order height
//
// All tests run in Node via the in-memory SQLite fallback.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";
import { SqliteHeaderStore, type HeaderRecord } from "./sqlite-header-store.js";

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/** Build a minimal fake HeaderRecord chain of length n starting at height 0. */
function makeChain(n: number): HeaderRecord[] {
  const chain: HeaderRecord[] = [];
  let prevHash = new Uint8Array(32).fill(0);
  for (let i = 0; i < n; i++) {
    // Hash is SHA-256-ish fakery: just fill with (i+1).
    const hash = new Uint8Array(32).fill(i + 1);
    const header = new Uint8Array(80).fill(i); // opaque blob
    chain.push({ height: i, hash, header, prevHash: new Uint8Array(prevHash) });
    prevHash = hash;
  }
  return chain;
}

// ──────────────────────────────────────────────────────────────────────────────
// Suite
// ──────────────────────────────────────────────────────────────────────────────

describe("M2.2: SqliteHeaderStore", () => {
  let db: SqliteOpfsDb;
  let store: SqliteHeaderStore;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-hs-${Math.random().toString(36).slice(2)}` });
    await db.open();
    store = new SqliteHeaderStore(db);
    await store.init();
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.2-T-put-get
  it("put/get round-trip by height and by hash", async () => {
    const chain = makeChain(3);
    for (const rec of chain) {
      await store.appendValidated(rec);
    }

    const got = await store.getByHeight(1);
    expect(got).not.toBeNull();
    expect(got!.height).toBe(1);
    expect(got!.hash).toEqual(chain[1].hash);

    const byHash = await store.getByHash(chain[2].hash);
    expect(byHash).not.toBeNull();
    expect(byHash!.height).toBe(2);
  });

  // M2.2-T-missing-key
  it("getByHeight returns null for unknown height", async () => {
    const result = await store.getByHeight(999);
    expect(result).toBeNull();
  });

  it("getByHash returns null for unknown hash", async () => {
    const result = await store.getByHash(new Uint8Array(32).fill(0xff));
    expect(result).toBeNull();
  });

  // M2.2-T-tip
  it("tip() returns the highest appended record", async () => {
    expect(await store.tip()).toBeNull();

    const chain = makeChain(5);
    for (const rec of chain) await store.appendValidated(rec);

    const tip = await store.tip();
    expect(tip).not.toBeNull();
    expect(tip!.height).toBe(4);
  });

  // M2.2-T-reorg-rollback
  it("rollbackFrom drops records at height >= from_height", async () => {
    const chain = makeChain(10);
    for (const rec of chain) await store.appendValidated(rec);

    const dropped = await store.rollbackFrom(5);
    // heights 5–9 removed → 5 records dropped
    expect(dropped).toBe(5);

    // height 5 gone
    expect(await store.getByHeight(5)).toBeNull();
    // height 4 still present
    expect(await store.getByHeight(4)).not.toBeNull();

    const tip = await store.tip();
    expect(tip!.height).toBe(4);
  });

  it("rollbackFrom returns 0 when nothing to drop", async () => {
    const chain = makeChain(3);
    for (const rec of chain) await store.appendValidated(rec);

    const dropped = await store.rollbackFrom(100);
    expect(dropped).toBe(0);
    expect((await store.tip())!.height).toBe(2);
  });

  // M2.2-T-cursor-order
  it("allByHeight() returns records in ascending height order", async () => {
    const chain = makeChain(5);
    // Insert in reverse to ensure ORDER BY height is respected
    for (let i = chain.length - 1; i >= 0; i--) {
      // We must build a fresh chain in forward order for prev_hash consistency,
      // so append in the correct order (store enforces it).
    }
    // Correct: must append forward to satisfy prev_hash constraint.
    for (const rec of chain) await store.appendValidated(rec);

    const all = await store.allByHeight();
    expect(all).toHaveLength(5);
    for (let i = 0; i < all.length - 1; i++) {
      expect(all[i].height).toBeLessThan(all[i + 1].height);
    }
  });

  // M2.2-T-snapshot-replay
  it("snapshot → replay reconstructs state exactly", async () => {
    const chain = makeChain(4);
    for (const rec of chain) await store.appendValidated(rec);

    const snap = await store.snapshot();
    expect(snap).toHaveLength(4);

    // Fresh store for replay
    const db2 = new SqliteOpfsDb({ dbName: `test-hs-dst-${Math.random().toString(36).slice(2)}` });
    await db2.open();
    const store2 = new SqliteHeaderStore(db2);
    await store2.init();

    await store2.replay(snap);
    const tip = await store2.tip();
    expect(tip!.height).toBe(3);

    const got = await store2.getByHeight(2);
    expect(got!.hash).toEqual(chain[2].hash);

    await db2.close();
  });

  // M2.2-T-prev-hash-check
  it("appendValidated rejects wrong prev_hash", async () => {
    const chain = makeChain(2);
    await store.appendValidated(chain[0]);

    // Tamper with prevHash
    const bad: HeaderRecord = {
      ...chain[1],
      prevHash: new Uint8Array(32).fill(0xff),
    };
    await expect(store.appendValidated(bad)).rejects.toThrow("prev_hash_mismatch");
  });

  // M2.2-T-height-order
  it("appendValidated rejects out-of-order height", async () => {
    const chain = makeChain(3);
    await store.appendValidated(chain[0]);

    // Skip height 1, try height 5
    const bad: HeaderRecord = { ...chain[2], height: 5 };
    await expect(store.appendValidated(bad)).rejects.toThrow("height_out_of_order");
  });

  // Idempotent init
  it("init() is safe to call twice (idempotent schema)", async () => {
    await expect(store.init()).resolves.not.toThrow();
  });
});

```
