---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/content-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.886703+00:00
---

# core/protocol-types/src/__tests__/content-store.test.ts

```ts
/**
 * Content-store types + helpers.
 *
 * Red-phase spec: the helpers don't exist yet. These tests pin the
 * shape we want before any implementation lands.
 */

import { describe, test, expect } from "bun:test";
import { createHash } from "node:crypto";
import {
  hashBytes,
  verifyHash,
  makeHash,
  type Hash,
} from "../content-store";

function referenceSha256(bytes: Uint8Array): Uint8Array {
  const digest = createHash("sha256").update(bytes).digest();
  return new Uint8Array(digest.buffer, digest.byteOffset, digest.byteLength);
}

describe("content-store helpers", () => {
  test("hashBytes returns a 32-byte SHA-256 digest matching Node crypto", async () => {
    const input = new TextEncoder().encode("hello world");
    const got = await hashBytes(input);
    expect(got.length).toBe(32);
    const expected = referenceSha256(input);
    expect(Array.from(got)).toEqual(Array.from(expected));
  });

  test("hashBytes is deterministic", async () => {
    const input = new Uint8Array([1, 2, 3, 4, 5]);
    const a = await hashBytes(input);
    const b = await hashBytes(input);
    expect(Array.from(a)).toEqual(Array.from(b));
  });

  test("hashBytes differs for different inputs", async () => {
    const a = await hashBytes(new Uint8Array([1, 2, 3]));
    const b = await hashBytes(new Uint8Array([1, 2, 4]));
    expect(Array.from(a)).not.toEqual(Array.from(b));
  });

  test("makeHash accepts exactly 32 bytes", () => {
    const raw = new Uint8Array(32);
    for (let i = 0; i < 32; i++) raw[i] = i;
    const h = makeHash(raw);
    expect(h.length).toBe(32);
    expect(Array.from(h)).toEqual(Array.from(raw));
  });

  test("makeHash rejects wrong-length input", () => {
    expect(() => makeHash(new Uint8Array(31))).toThrow();
    expect(() => makeHash(new Uint8Array(33))).toThrow();
    expect(() => makeHash(new Uint8Array(0))).toThrow();
  });

  test("verifyHash returns true when bytes hash to claimed", async () => {
    const bytes = new TextEncoder().encode("payload");
    const claimed: Hash = await hashBytes(bytes);
    expect(await verifyHash(bytes, claimed)).toBe(true);
  });

  test("verifyHash returns false when bytes do not match", async () => {
    const bytes = new TextEncoder().encode("payload");
    const other = new TextEncoder().encode("different");
    const claimed: Hash = await hashBytes(other);
    expect(await verifyHash(bytes, claimed)).toBe(false);
  });

  test("verifyHash returns false for mis-shaped claimed hash", async () => {
    const bytes = new TextEncoder().encode("payload");
    const short = new Uint8Array(31) as unknown as Hash;
    expect(await verifyHash(bytes, short)).toBe(false);
  });
});

```
