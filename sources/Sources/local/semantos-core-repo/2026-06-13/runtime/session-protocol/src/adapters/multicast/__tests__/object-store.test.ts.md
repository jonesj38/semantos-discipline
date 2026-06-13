---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/object-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.070519+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/object-store.test.ts

```ts
/**
 * object-store unit tests — record / conflict-detect / query / clear.
 */

import { describe, expect, test } from "bun:test";
import {
  clearObjects,
  createObjectStore,
  objectCount,
  queryObjects,
  recordObject,
} from "../object-store";
import type { NetworkResult } from "@semantos/protocol-types/network";

const r = (overrides: Partial<NetworkResult> = {}): NetworkResult => ({
  txid: "tx",
  vout: 0,
  cellBytes: new Uint8Array(),
  semanticPath: "/p",
  contentHash: "ch",
  ownerCert: "owner-a",
  typeHash: "th",
  publishedAt: 1,
  ...overrides,
});

describe("object-store", () => {
  test("recordObject stores and is queryable by path", () => {
    const store = createObjectStore();
    expect(recordObject(store, r({ semanticPath: "/x" }), 0)).toBeNull();
    expect(queryObjects(store, { path: "/x" })).toHaveLength(1);
  });

  test("same (path, owner) overwrites silently", () => {
    const store = createObjectStore();
    recordObject(store, r({ semanticPath: "/x", txid: "1" }), 0);
    recordObject(store, r({ semanticPath: "/x", txid: "2" }), 0);
    expect(objectCount(store)).toBe(1);
    expect(queryObjects(store, { path: "/x" })[0]?.txid).toBe("2");
  });

  test("same path, different owner emits a duplicate-path event", () => {
    const store = createObjectStore();
    expect(recordObject(store, r({ semanticPath: "/x", ownerCert: "a" }), 0)).toBeNull();
    const conflict = recordObject(store, r({ semanticPath: "/x", ownerCert: "b" }), 5);
    expect(conflict).toEqual({
      type: "duplicate_path",
      semanticPath: "/x",
      existingOwner: "a",
      newOwner: "b",
      timestamp: 5,
    });
    expect(objectCount(store)).toBe(2);
  });

  test("queryObjects filters on every query field", () => {
    const store = createObjectStore();
    recordObject(store, r({ semanticPath: "/a", ownerCert: "x", typeHash: "T1" }), 0);
    recordObject(store, r({ semanticPath: "/a", ownerCert: "y", typeHash: "T1" }), 0);
    recordObject(store, r({ semanticPath: "/b", ownerCert: "x", typeHash: "T2" }), 0);
    expect(queryObjects(store, { path: "/a" })).toHaveLength(2);
    expect(queryObjects(store, { ownerCert: "x" })).toHaveLength(2);
    expect(queryObjects(store, { typeHash: "T2" })).toHaveLength(1);
    expect(queryObjects(store, { path: "/a", ownerCert: "y" })).toHaveLength(1);
  });

  test("queryObjects respects limit", () => {
    const store = createObjectStore();
    for (let i = 0; i < 5; i++) {
      recordObject(store, r({ semanticPath: `/p${i}` }), 0);
    }
    expect(queryObjects(store, { limit: 3 })).toHaveLength(3);
  });

  test("clearObjects wipes the cache", () => {
    const store = createObjectStore();
    recordObject(store, r(), 0);
    clearObjects(store);
    expect(objectCount(store)).toBe(0);
  });
});

```
