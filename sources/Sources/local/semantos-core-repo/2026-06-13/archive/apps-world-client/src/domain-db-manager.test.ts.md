---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/domain-db-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.819659+00:00
---

# archive/apps-world-client/src/domain-db-manager.test.ts

```ts
// M2.6-T — DomainDbManager: per-domain ATTACH DATABASE round-trip tests.
//
// Spec: Recovery-payload ATTACH DATABASE per domain flag — one .sqlite file
// per governance domain; detach/encrypt/re-attach round-trip tested.
//
// Five governance domain types (from docs/textbook/06-domain-flags-sovereign-boundaries.md):
//   Trust (0x54), Estate (0x45), Realm (0x52), Corporate (0x43), Cooperative (0x4F)
//
// Tests:
//   M2.6-T-attach-detach       — attach Trust → isDomainAttached=true; detach → false
//   M2.6-T-put-get             — attach Trust, putCell → getCell returns same data
//   M2.6-T-detach-no-get       — attach Trust, detach → getCell returns null
//   M2.6-T-domain-isolation    — Trust + Estate; put in Trust → Estate returns null
//   M2.6-T-no-overwrite        — put twice same hash → second put throws
//   M2.6-T-serialize-reattach  — detachAndSerialize → bytes non-empty; reattachFromBytes → round-trip
//   M2.6-T-list-attached       — attach Trust + Realm → both in list; detach Trust → only Realm
//   M2.6-T-five-domains        — attach all five → all isDomainAttached; detach all → all false
//   M2.6-T-not-attached-put    — putCell without attach → throws descriptive error
//   M2.6-T-double-attach-idempotent — attach Trust twice → no error; isDomainAttached still true
//
// All tests run in Node via the in-memory SQLite fallback.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";
import { DomainDbManager, DOMAIN_FLAGS } from "./domain-db-manager.js";

// ──────────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────────

/** Build a fake 32-byte cell hash filled with the given byte value. */
function makeHash(fill: number): Uint8Array {
  return new Uint8Array(32).fill(fill);
}

/** Build a fake 1024-byte cell data blob. */
function makeCellData(fill: number): Uint8Array {
  const data = new Uint8Array(1024);
  data.fill(fill, 0, 1024);
  return data;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

// ──────────────────────────────────────────────────────────────────────────────
// Suite
// ──────────────────────────────────────────────────────────────────────────────

describe("M2.6: DomainDbManager", () => {
  let db: SqliteOpfsDb;
  let mgr: DomainDbManager;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-ddm-${Math.random().toString(36).slice(2)}` });
    await db.open();
    mgr = new DomainDbManager(db);
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.6-T-attach-detach
  it("M2.6-T-attach-detach: attach Trust → isDomainAttached=true; detach → false", async () => {
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(false);

    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(true);

    await mgr.detachDomain(DOMAIN_FLAGS.TRUST);
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(false);
  });

  // M2.6-T-put-get
  it("M2.6-T-put-get: attach Trust, putCell → getCell returns same data", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);

    const hash = makeHash(0x01);
    const data = makeCellData(0xAB);

    await mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data);

    const result = await mgr.getCell(DOMAIN_FLAGS.TRUST, hash);
    expect(result).not.toBeNull();
    expect(bytesEqual(result!, data)).toBe(true);
  });

  // M2.6-T-detach-no-get
  it("M2.6-T-detach-no-get: attach Trust, detach → getCell returns null", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);

    const hash = makeHash(0x02);
    const data = makeCellData(0xCC);
    await mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data);

    await mgr.detachDomain(DOMAIN_FLAGS.TRUST);

    const result = await mgr.getCell(DOMAIN_FLAGS.TRUST, hash);
    expect(result).toBeNull();
  });

  // M2.6-T-domain-isolation
  it("M2.6-T-domain-isolation: put in Trust → Estate getCell returns null", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);
    await mgr.attachDomain(DOMAIN_FLAGS.ESTATE);

    const hash = makeHash(0x03);
    const data = makeCellData(0xDD);

    await mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data);

    // Same hash not visible in Estate domain
    const result = await mgr.getCell(DOMAIN_FLAGS.ESTATE, hash);
    expect(result).toBeNull();
  });

  // M2.6-T-no-overwrite
  it("M2.6-T-no-overwrite: put same hash twice → second put throws", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);

    const hash = makeHash(0x04);
    const data1 = makeCellData(0x11);
    const data2 = makeCellData(0x22);

    await mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data1);

    await expect(mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data2)).rejects.toThrow();
  });

  // M2.6-T-serialize-reattach
  it("M2.6-T-serialize-reattach: detachAndSerialize → non-empty bytes; reattachFromBytes → round-trip", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);

    const hash = makeHash(0x05);
    const data = makeCellData(0x55);
    await mgr.putCell(DOMAIN_FLAGS.TRUST, hash, data);

    // Serialize and detach
    const serialized = await mgr.detachAndSerialize(DOMAIN_FLAGS.TRUST);
    expect(serialized.byteLength).toBeGreaterThan(0);
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(false);

    // Reattach from bytes
    await mgr.reattachFromBytes(DOMAIN_FLAGS.TRUST, serialized);
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(true);

    // Data should be recoverable
    const result = await mgr.getCell(DOMAIN_FLAGS.TRUST, hash);
    expect(result).not.toBeNull();
    expect(bytesEqual(result!, data)).toBe(true);
  });

  // M2.6-T-list-attached
  it("M2.6-T-list-attached: attach Trust + Realm → both in list; detach Trust → only Realm remains", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);
    await mgr.attachDomain(DOMAIN_FLAGS.REALM);

    const attached = mgr.listAttachedDomains();
    expect(attached).toContain(DOMAIN_FLAGS.TRUST);
    expect(attached).toContain(DOMAIN_FLAGS.REALM);
    expect(attached).toHaveLength(2);

    await mgr.detachDomain(DOMAIN_FLAGS.TRUST);

    const remaining = mgr.listAttachedDomains();
    expect(remaining).not.toContain(DOMAIN_FLAGS.TRUST);
    expect(remaining).toContain(DOMAIN_FLAGS.REALM);
    expect(remaining).toHaveLength(1);
  });

  // M2.6-T-five-domains
  it("M2.6-T-five-domains: attach all five domain types → all isDomainAttached; detach all → all false", async () => {
    const allFlags = [
      DOMAIN_FLAGS.TRUST,
      DOMAIN_FLAGS.ESTATE,
      DOMAIN_FLAGS.REALM,
      DOMAIN_FLAGS.CORPORATE,
      DOMAIN_FLAGS.COOPERATIVE,
    ];

    // Attach all
    for (const flag of allFlags) {
      await mgr.attachDomain(flag);
    }

    // All should be attached
    for (const flag of allFlags) {
      expect(mgr.isDomainAttached(flag)).toBe(true);
    }

    // Detach all
    for (const flag of allFlags) {
      await mgr.detachDomain(flag);
    }

    // All should be detached
    for (const flag of allFlags) {
      expect(mgr.isDomainAttached(flag)).toBe(false);
    }
  });

  // M2.6-T-not-attached-put
  it("M2.6-T-not-attached-put: putCell without attach → throws descriptive error", async () => {
    const hash = makeHash(0x07);
    const data = makeCellData(0x77);

    await expect(mgr.putCell(DOMAIN_FLAGS.ESTATE, hash, data)).rejects.toThrow(
      /not attached|domain.*not|attach/i,
    );
  });

  // M2.6-T-double-attach-idempotent
  it("M2.6-T-double-attach-idempotent: attach Trust twice → no error; isDomainAttached still true", async () => {
    await mgr.attachDomain(DOMAIN_FLAGS.TRUST);
    await expect(mgr.attachDomain(DOMAIN_FLAGS.TRUST)).resolves.not.toThrow();
    expect(mgr.isDomainAttached(DOMAIN_FLAGS.TRUST)).toBe(true);
  });
});

```
