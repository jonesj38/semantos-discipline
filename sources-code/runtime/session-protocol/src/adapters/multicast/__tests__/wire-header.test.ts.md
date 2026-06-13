---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/__tests__/wire-header.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.069900+00:00
---

# runtime/session-protocol/src/adapters/multicast/__tests__/wire-header.test.ts

```ts
/**
 * wire-header unit tests — encode/decode/derive/frame round-trips.
 */

import { describe, expect, test } from "bun:test";
import {
  HEADER_SIZE,
  MSG_CELL,
  MSG_HEARTBEAT,
  decodeHeader,
  deriveNodeIdShort,
  encodeHeader,
  framePacket,
} from "../wire-header";

describe("wire-header", () => {
  test("encodeHeader / decodeHeader round-trip", () => {
    const h = encodeHeader(MSG_CELL, 0x1234, 0xabcd, 0xdeadbeef, 0x0042);
    expect(h.length).toBe(HEADER_SIZE);
    const out = decodeHeader(h);
    expect(out).toMatchObject({
      version: 0x01,
      msgType: MSG_CELL,
      msgId: 0x1234,
      nodeIdShort: 0xabcd,
      timestamp: 0xdeadbeef,
      payloadLen: 0x0042,
    });
  });

  test("encodeHeader fits exactly in 12 bytes (CoAP-style)", () => {
    const h = encodeHeader(MSG_HEARTBEAT, 1, 1, 0, 0);
    expect(h.length).toBe(12);
  });

  test("deriveNodeIdShort xor-folds the trailing pubkey bytes", () => {
    const pk = new Uint8Array([0x00, 0x00, 0x12, 0x34]);
    expect(deriveNodeIdShort(pk)).toBe(0x1234);
    expect(deriveNodeIdShort(new Uint8Array([0xab, 0xcd]))).toBe(0xabcd);
    expect(deriveNodeIdShort(new Uint8Array([0x99]))).toBe(0);
  });

  test("framePacket prepends the header bytes to the payload", () => {
    const header = encodeHeader(MSG_CELL, 1, 0xff, 0, 4);
    const payload = new Uint8Array([1, 2, 3, 4]);
    const packet = framePacket(header, payload);
    expect(packet.length).toBe(HEADER_SIZE + 4);
    expect(packet.subarray(HEADER_SIZE)).toEqual(payload);
    expect(decodeHeader(packet.subarray(0, HEADER_SIZE)).msgType).toBe(MSG_CELL);
  });
});

```
