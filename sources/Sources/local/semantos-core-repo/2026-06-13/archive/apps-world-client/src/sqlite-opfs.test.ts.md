---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/sqlite-opfs.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.825971+00:00
---

# archive/apps-world-client/src/sqlite-opfs.test.ts

```ts
// M2.1-T — SQLite-WASM-OPFS bring-up tests.
//
// Acceptance: SQLite-WASM loads in browser; OPFS handle resolved;
// one round-trip query returns.
//
// Tests:
//   M2.1-T-module-loads       — SqliteOpfsDb can be imported without error
//   M2.1-T-open-close         — open() resolves; close() cleans up
//   M2.1-T-create-table       — DDL executes without error
//   M2.1-T-insert-select      — one round-trip INSERT → SELECT returns correct row
//   M2.1-T-idempotent-schema  — CREATE TABLE IF NOT EXISTS is safe to call twice
//   M2.1-T-opfs-key-isolation — two stores with different dbNames are independent
//
// Note: OPFS is a browser-only API. These tests run under vitest with
// a browser environment (vitest --environment=jsdom); SqliteOpfsDb uses
// a MemoryVFS fallback when OPFS is unavailable so the tests are also
// runnable in Node CI. The M2.7 integration test (browser kernel end-to-end)
// uses a real Chromium via playwright.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { SqliteOpfsDb } from "./sqlite-opfs.js";

describe("M2.1: SQLite-WASM-OPFS bring-up", () => {
  let db: SqliteOpfsDb;

  beforeEach(async () => {
    db = new SqliteOpfsDb({ dbName: `test-${Math.random().toString(36).slice(2)}` });
    await db.open();
  });

  afterEach(async () => {
    await db.close();
  });

  // M2.1-T-module-loads
  it("module exports SqliteOpfsDb class", () => {
    expect(SqliteOpfsDb).toBeDefined();
    expect(typeof SqliteOpfsDb).toBe("function");
  });

  // M2.1-T-open-close
  it("open() resolves and reports isOpen", async () => {
    expect(db.isOpen).toBe(true);
  });

  // M2.1-T-create-table
  it("executes DDL without error", async () => {
    await expect(
      db.exec(`CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, val BLOB NOT NULL)`)
    ).resolves.not.toThrow();
  });

  // M2.1-T-insert-select
  it("INSERT then SELECT returns the inserted row", async () => {
    await db.exec(`CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, val BLOB NOT NULL)`);
    await db.exec(`INSERT INTO kv VALUES ('hello', X'776f726c64')`);

    const rows = await db.query<{ key: string; val: Uint8Array }>(
      `SELECT key, val FROM kv WHERE key = 'hello'`
    );

    expect(rows).toHaveLength(1);
    expect(rows[0].key).toBe("hello");
    // X'776f726c64' = "world" in UTF-8
    expect(Buffer.from(rows[0].val).toString()).toBe("world");
  });

  // M2.1-T-idempotent-schema
  it("CREATE TABLE IF NOT EXISTS is safe to call twice", async () => {
    const ddl = `CREATE TABLE IF NOT EXISTS cells (hash BLOB PRIMARY KEY, data BLOB NOT NULL)`;
    await db.exec(ddl);
    await expect(db.exec(ddl)).resolves.not.toThrow();
  });

  // M2.1-T-opfs-key-isolation
  it("two stores with different dbNames are independent", async () => {
    const db2 = new SqliteOpfsDb({ dbName: `test-b-${Math.random().toString(36).slice(2)}` });
    await db2.open();
    try {
      await db.exec(`CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, val TEXT)`);
      await db.exec(`INSERT INTO kv VALUES ('shared-key', 'from-db1')`);

      await db2.exec(`CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, val TEXT)`);

      const rows = await db2.query<{ val: string }>(`SELECT val FROM kv WHERE key = 'shared-key'`);
      expect(rows).toHaveLength(0); // db2 does not see db1's data
    } finally {
      await db2.close();
    }
  });
});

```
