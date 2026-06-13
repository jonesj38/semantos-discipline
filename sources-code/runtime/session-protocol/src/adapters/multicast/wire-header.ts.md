---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/wire-header.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.066381+00:00
---

# runtime/session-protocol/src/adapters/multicast/wire-header.ts

```ts
/**
 * CoAP-like 12-byte header — wire-format helpers preserved from the
 * hackathon `DockerMulticastAdapter` so existing peers stay compatible.
 *
 * Layout (big-endian):
 *   version(1B) + msgType(1B) + msgId(2B) + nodeIdShort(2B) +
 *   timestamp(4B) + payloadLen(2B)
 *
 * This module is pure — no I/O, no network, no codec. The orchestrator
 * sandwiches the encoded payload between this header and writes the
 * resulting packet to the transport.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — the source these were lifted from
 */

export const HEADER_SIZE = 12;
export const MSG_HEARTBEAT = 0x01;
export const MSG_CELL = 0x02;
export const MSG_CONTROL = 0x03;
export const COAP_VERSION = 0x01;

export interface WireHeader {
  version: number;
  msgType: number;
  msgId: number;
  nodeIdShort: number;
  timestamp: number;
  payloadLen: number;
}

export function encodeHeader(
  msgType: number,
  msgId: number,
  nodeIdShort: number,
  timestamp: number,
  payloadLen: number,
): Uint8Array {
  const buf = new Uint8Array(HEADER_SIZE);
  const dv = new DataView(buf.buffer);
  buf[0] = COAP_VERSION;
  buf[1] = msgType;
  dv.setUint16(2, msgId, false);
  dv.setUint16(4, nodeIdShort, false);
  dv.setUint32(6, timestamp >>> 0, false);
  dv.setUint16(10, payloadLen, false);
  return buf;
}

export function decodeHeader(buf: Uint8Array): WireHeader {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  return {
    version: buf[0]!,
    msgType: buf[1]!,
    msgId: dv.getUint16(2, false),
    nodeIdShort: dv.getUint16(4, false),
    timestamp: dv.getUint32(6, false),
    payloadLen: dv.getUint16(10, false),
  };
}

/** Derive a 16-bit short node id from a pubkey (xor-fold last 2 bytes). */
export function deriveNodeIdShort(pubkey: Uint8Array): number {
  if (pubkey.length < 2) return 0;
  return ((pubkey[pubkey.length - 2]! << 8) | pubkey[pubkey.length - 1]!) &
    0xffff;
}

/** Build a complete packet: 12-byte header followed by the payload. */
export function framePacket(
  header: Uint8Array,
  payload: Uint8Array,
): Uint8Array {
  const packet = new Uint8Array(HEADER_SIZE + payload.length);
  packet.set(header);
  packet.set(payload, HEADER_SIZE);
  return packet;
}

```
