---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/codec-port.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.071403+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/codec-port.test.ts

```ts
/**
 * codec-port unit tests.
 */

import { describe, expect, test } from "bun:test";
import {
  createDefaultCodec,
  createJsonCodec,
} from "../ports/codec-port";

describe("CodecPort", () => {
  test("JSON codec round-trips arbitrary values", () => {
    const codec = createJsonCodec();
    const v = { foo: 1, bar: [1, 2, "three"], nested: { ok: true } };
    expect(codec.decode(codec.encode(v))).toEqual(v);
  });

  test("JSON codec produces deterministic bytes", () => {
    const codec = createJsonCodec();
    const a = codec.encode({ a: 1, b: 2 });
    const b = codec.encode({ a: 1, b: 2 });
    expect(a).toEqual(b);
  });

  test("default codec round-trips a heartbeat-shaped value", () => {
    const codec = createDefaultCodec();
    const v = {
      nodeIdShort: 0xabcd,
      bca: "fe80::1",
      uptime: 1234,
      peersKnown: 3,
      timestamp: Date.now(),
    };
    expect(codec.decode(codec.encode(v))).toEqual(v);
  });

  test("custom codec is duck-typed (encode/decode pair only)", () => {
    const calls: string[] = [];
    const codec = {
      encode: (v: unknown) => {
        calls.push("encode");
        return new TextEncoder().encode(JSON.stringify(v));
      },
      decode: (b: Uint8Array) => {
        calls.push("decode");
        return JSON.parse(new TextDecoder().decode(b));
      },
    };
    expect(codec.decode(codec.encode({ a: 1 }))).toEqual({ a: 1 });
    expect(calls).toEqual(["encode", "decode"]);
  });
});

```
