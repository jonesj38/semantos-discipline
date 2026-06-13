---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-pask-snapshot-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.817206+00:00
---

# archive/apps-world-client/src/sqlite-pask-snapshot-store.test.ts

```ts
// M2.8-T — SqlitePaskSnapshotStore conformance tests.
//
// Mirrors the vtable contract from:
//   runtime/semantos-brain/src/lmdb/pask_snapshot_store.zig
//
// Tests:
//   M2.8-T-commit-load         — commit snapshot → loadCurrent returns data + meta
//   M2.8-T-second-commit       — commit twice → loadCurrent returns second, version=2
//   M2.8-T-rollback            — commit twice → rollbackTo(v1) → loadCurrent returns first
//   M2.8-T-corrupt-magic       — commit with wrong magic bytes → throws error
//   M2.8-T-corrupt-length      — commit with wrong length field → throws error
//   M2.8-T-history             — commit 3 → snapshotHistory(limit=10) returns 3 descending
//   M2.8-T-history-limit       — commit 5 → snapshotHistory(limit=2) returns 2
//   M2.8-T-cert-isolation      — certA and certB are isolated
//   M2.8-T-rollback-to-nonexistent — rollbackTo(v99) on single-snapshot store → v1 intact
//   M2.8-T-load-empty          — loadCurrent on fresh store → returns null
//
// All tests run in Node via the in-memory SQLite fallback.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";
import {
  SqlitePaskSnapshotStore,
  type SnapshotMeta,
} from "./sqlite-pask-snapshot-store.js";

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

const MAGIC = [0x4b, 0x53, 0x41, 0x50]; // "PASK" big-endian

/**
 * Build a valid Pask snapshot blob of the given payload size.
 * Layout: [magic 4 bytes][length 4 bytes BE][payload]
 * Total size = 8 + payloadSize.
 */
function makeSnapshot(payloadSize: number = 16): Uint8Array {
  const total = 8 + payloadSize;
  const buf = new Uint8Array(total);
  // magic
  buf[0] = 0x4b;
  buf[1] = 0x53;
  buf[2] = 0x41;
  buf[3] = 0x50;
  // length field (big-endian u32) = total byte length
  const view = new DataView(buf.buffer);
  view.setUint32(4, total, false);
  // payload: fill with 0xab
  buf.fill(0xab, 8);
  return buf;
}

/**
 * Build a snapshot with wrong magic bytes.
 */
function makeSnapshotBadMagic(payloadSize: number = 16): Uint8Array {
  const buf = makeSnapshot(payloadSize);
  buf[0] = 0xde;
  buf[1] = 0xad;
  return buf;
}

/**
 * Build a snapshot with a correct magic but wrong length field.
 */
function makeSnapshotBadLength(payloadSize: number = 16): Uint8Array {
  const buf = makeSnapshot(payloadSize);
  const view = new DataView(buf.buffer);
  // Write a length that doesn't match actual size
  view.setUint32(4, buf.byteLength + 99, false);
  return buf;
}

/** Deterministic fake cert_id. */
function makeCertId(seed: number): Uint8Array {
  return new Uint8Array(32).fill(seed);
}

// ──────────────────────────────────────────────────────────────────────────────
// Suite
// ──────────────────────────────────────────────────────────────────────────────

describe("M2.8: SqlitePaskSnapshotStore", () => {
  let db: SqliteOpfsDb;
  let store: SqlitePaskSnapshotStore;
  let certId: Uint8Array;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-pask-${Math.random().toString(36).slice(2)}` });
    await db.open();
    store = new SqlitePaskSnapshotStore(db);
    await store.init();
    certId = makeCertId(1);
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.8-T-load-empty
  it("loadCurrent on fresh store returns null", async () => {
    const out = new Uint8Array(1024);
    const result = await store.loadCurrent(certId, out);
    expect(result).toBeNull();
  });

  // M2.8-T-commit-load
  it("commit snapshot → loadCurrent returns data + meta with magic_ok=true", async () => {
    const snap = makeSnapshot(32);
    const version = await store.commitSnapshot(certId, snap);
    expect(version).toBe(1n);

    const out = new Uint8Array(snap.byteLength);
    const meta = await store.loadCurrent(certId, out);

    expect(meta).not.toBeNull();
    expect(meta!.version).toBe(1n);
    expect(meta!.size).toBe(snap.byteLength);
    expect(meta!.magic_ok).toBe(true);
    expect(out).toEqual(snap);
  });

  // M2.8-T-second-commit
  it("commit twice → loadCurrent returns second snapshot, version=2", async () => {
    const snap1 = makeSnapshot(16);
    const snap2 = makeSnapshot(24);
    await store.commitSnapshot(certId, snap1);
    const v2 = await store.commitSnapshot(certId, snap2);
    expect(v2).toBe(2n);

    const out = new Uint8Array(snap2.byteLength);
    const meta = await store.loadCurrent(certId, out);

    expect(meta).not.toBeNull();
    expect(meta!.version).toBe(2n);
    expect(meta!.size).toBe(snap2.byteLength);
    expect(out).toEqual(snap2);
  });

  // M2.8-T-rollback
  it("commit twice → rollbackTo(v1) → loadCurrent returns first snapshot", async () => {
    const snap1 = makeSnapshot(16);
    const snap2 = makeSnapshot(24);
    await store.commitSnapshot(certId, snap1);
    await store.commitSnapshot(certId, snap2);

    await store.rollbackTo(certId, 1n);

    const out = new Uint8Array(snap1.byteLength);
    const meta = await store.loadCurrent(certId, out);

    expect(meta).not.toBeNull();
    expect(meta!.version).toBe(1n);
    expect(meta!.size).toBe(snap1.byteLength);
    expect(out).toEqual(snap1);
  });

  // M2.8-T-corrupt-magic
  it("commit with wrong magic bytes → throws error", async () => {
    const bad = makeSnapshotBadMagic();
    await expect(store.commitSnapshot(certId, bad)).rejects.toThrow("invalid_magic");
  });

  // M2.8-T-corrupt-length
  it("commit with wrong length field → throws error", async () => {
    const bad = makeSnapshotBadLength();
    await expect(store.commitSnapshot(certId, bad)).rejects.toThrow("invalid_length");
  });

  // M2.8-T-history
  it("commit 3 snapshots → snapshotHistory(limit=10) returns 3 in descending order", async () => {
    await store.commitSnapshot(certId, makeSnapshot(16));
    await store.commitSnapshot(certId, makeSnapshot(24));
    await store.commitSnapshot(certId, makeSnapshot(32));

    const history = await store.snapshotHistory(certId, 10);
    expect(history).toHaveLength(3);
    // Descending version order
    expect(history[0].version).toBe(3n);
    expect(history[1].version).toBe(2n);
    expect(history[2].version).toBe(1n);
    // All should have magic_ok=true
    for (const m of history) {
      expect(m.magic_ok).toBe(true);
    }
  });

  // M2.8-T-history-limit
  it("commit 5 snapshots → snapshotHistory(limit=2) returns 2 most recent", async () => {
    for (let i = 0; i < 5; i++) {
      await store.commitSnapshot(certId, makeSnapshot(16 + i * 4));
    }

    const history = await store.snapshotHistory(certId, 2);
    expect(history).toHaveLength(2);
    expect(history[0].version).toBe(5n);
    expect(history[1].version).toBe(4n);
  });

  // M2.8-T-cert-isolation
  it("certA and certB snapshots are isolated", async () => {
    const certA = makeCertId(0xaa);
    const certB = makeCertId(0xbb);
    const snapA = makeSnapshot(16);
    const snapB = makeSnapshot(32);

    await store.commitSnapshot(certA, snapA);
    await store.commitSnapshot(certB, snapB);

    const outA = new Uint8Array(snapA.byteLength);
    const metaA = await store.loadCurrent(certA, outA);
    expect(metaA).not.toBeNull();
    expect(metaA!.size).toBe(snapA.byteLength);
    expect(outA).toEqual(snapA);

    const outB = new Uint8Array(snapB.byteLength);
    const metaB = await store.loadCurrent(certB, outB);
    expect(metaB).not.toBeNull();
    expect(metaB!.size).toBe(snapB.byteLength);
    expect(outB).toEqual(snapB);
  });

  // M2.8-T-rollback-to-nonexistent
  it("rollbackTo(v99) on single-snapshot store leaves v1 intact", async () => {
    const snap = makeSnapshot(16);
    await store.commitSnapshot(certId, snap);

    // rollback to a version that doesn't exist (v99 > current v1)
    // should be a no-op / leave state consistent
    await store.rollbackTo(certId, 99n);

    const out = new Uint8Array(snap.byteLength);
    const meta = await store.loadCurrent(certId, out);
    expect(meta).not.toBeNull();
    expect(meta!.version).toBe(1n);
    expect(out).toEqual(snap);
  });
});

```
