---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-derivation-state-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.818319+00:00
---

# archive/apps-world-client/src/sqlite-derivation-state-store.test.ts

```ts
// M2.4-T — SqliteDerivationStateStore conformance tests.
//
// Mirrors the semantic contract from:
//   core/cell-engine/src/derivation_state.zig (LocalStateStore)
//
// Tests:
//   M2.4-T-get-missing       — getIndex returns null for unknown path
//   M2.4-T-next-index        — nextIndex increments monotonically from 0
//   M2.4-T-next-index-mono   — successive calls return 0, 1, 2, …
//   M2.4-T-ceiling-enforce   — nextIndex throws ceiling_exceeded when next >= ceiling
//   M2.4-T-ceiling-null      — null ceiling means no upper bound
//   M2.4-T-snapshot-replay   — snapshot → replay reconstructs state
//   M2.4-T-multi-path        — independent counters per path
//   M2.4-T-idempotent-init   — init() is safe to call twice
//
// All tests run in Node via the in-memory SQLite fallback.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";
import {
  SqliteDerivationStateStore,
  type DerivationRecord,
} from "./sqlite-derivation-state-store.js";

// ──────────────────────────────────────────────────────────────────────────────
// Suite
// ──────────────────────────────────────────────────────────────────────────────

describe("M2.4: SqliteDerivationStateStore", () => {
  let db: SqliteOpfsDb;
  let store: SqliteDerivationStateStore;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-ds-${Math.random().toString(36).slice(2)}` });
    await db.open();
    store = new SqliteDerivationStateStore(db);
    await store.init();
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.4-T-get-missing
  it("getIndex returns null for unknown path", async () => {
    const result = await store.getIndex("m/44'/0'/0'");
    expect(result).toBeNull();
  });

  // M2.4-T-next-index
  it("nextIndex starts at 0 for a fresh path", async () => {
    const idx = await store.nextIndex("m/44'/0'/0'");
    expect(idx).toBe(0n);
  });

  // M2.4-T-next-index-mono
  it("successive nextIndex calls return 0, 1, 2, …", async () => {
    const path = "m/44'/0'/1'";
    const i0 = await store.nextIndex(path);
    const i1 = await store.nextIndex(path);
    const i2 = await store.nextIndex(path);
    expect(i0).toBe(0n);
    expect(i1).toBe(1n);
    expect(i2).toBe(2n);
  });

  // M2.4-T-ceiling-enforce
  it("nextIndex throws ceiling_exceeded when next index would reach ceiling", async () => {
    const path = "m/44'/0'/2'";
    // ceiling = 3 → indices 0, 1, 2 are valid; 3 must be rejected
    await store.setCeiling(path, 3n);

    await store.nextIndex(path); // 0
    await store.nextIndex(path); // 1
    await store.nextIndex(path); // 2

    // Next call would return 3 which equals ceiling — must throw
    await expect(store.nextIndex(path)).rejects.toThrow("ceiling_exceeded");
  });

  it("nextIndex with ceiling=1 allows only index 0", async () => {
    const path = "m/44'/0'/3'";
    await store.setCeiling(path, 1n);

    const idx = await store.nextIndex(path); // 0 — ok
    expect(idx).toBe(0n);

    await expect(store.nextIndex(path)).rejects.toThrow("ceiling_exceeded");
  });

  // M2.4-T-ceiling-null
  it("null ceiling imposes no upper bound", async () => {
    const path = "m/44'/0'/4'";
    // No ceiling set → unlimited
    for (let i = 0; i < 10; i++) {
      const idx = await store.nextIndex(path);
      expect(idx).toBe(BigInt(i));
    }
  });

  // M2.4-T-snapshot-replay
  it("snapshot → replay reconstructs state", async () => {
    const pathA = "m/44'/0'/10'";
    const pathB = "m/44'/0'/11'";

    await store.nextIndex(pathA); // 0
    await store.nextIndex(pathA); // 1
    await store.nextIndex(pathB); // 0
    await store.setCeiling(pathB, 5n);

    const snap = await store.snapshot();
    expect(snap.length).toBe(2);

    const db2 = new SqliteOpfsDb({ dbName: `test-ds-dst-${Math.random().toString(36).slice(2)}` });
    await db2.open();
    const store2 = new SqliteDerivationStateStore(db2);
    await store2.init();

    await store2.replay(snap);

    // Indices restored: pathA next call returns 2, pathB returns 1
    const nextA = await store2.nextIndex(pathA);
    expect(nextA).toBe(2n);

    const nextB = await store2.nextIndex(pathB);
    expect(nextB).toBe(1n);

    // Ceiling preserved on pathB
    await store2.nextIndex(pathB); // 2
    await store2.nextIndex(pathB); // 3
    await store2.nextIndex(pathB); // 4
    await expect(store2.nextIndex(pathB)).rejects.toThrow("ceiling_exceeded");

    await db2.close();
  });

  // M2.4-T-multi-path
  it("each path has an independent counter", async () => {
    const paths = ["m/44'/0'/5'", "m/44'/0'/6'", "m/44'/0'/7'"];
    for (const p of paths) {
      const idx = await store.nextIndex(p);
      expect(idx).toBe(0n);
    }
    // Advance only the first path
    await store.nextIndex(paths[0]);
    await store.nextIndex(paths[0]);

    expect(await store.getIndex(paths[0])).toBe(2n);
    expect(await store.getIndex(paths[1])).toBe(0n);
    expect(await store.getIndex(paths[2])).toBe(0n);
  });

  // M2.4-T-idempotent-init
  it("init() is idempotent", async () => {
    await expect(store.init()).resolves.not.toThrow();
  });
});

```
