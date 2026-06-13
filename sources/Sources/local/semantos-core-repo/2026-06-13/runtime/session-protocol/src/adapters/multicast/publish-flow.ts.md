---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/publish-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.064384+00:00
---

# runtime/session-protocol/src/adapters/multicast/publish-flow.ts

```ts
/**
 * publish-flow — pure helpers that build the wire packet for an
 * outbound `publish()` call.
 *
 * Splitting these out keeps the orchestrator focused on coordination
 * (txid mint, group join, observer fan-out) and lets tests assert on
 * the wire shape without instantiating a full adapter.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes these helpers
 */

import type {
  NetworkResult,
  PublishableObject,
} from "@semantos/protocol-types/network";

import type { CodecPort } from "./ports/codec-port.js";
import { PayloadTooLargeError, type CellWireBody } from "./types.js";
import {
  MSG_CELL,
  encodeHeader,
  framePacket,
} from "./wire-header.js";

/**
 * Build the local `NetworkResult` that publish() will record into the
 * object-store and emit to subscribers.
 */
export function buildLocalResult(
  object: PublishableObject,
  txid: string,
  topic: string,
  now: number,
): NetworkResult {
  return {
    txid,
    vout: 0,
    cellBytes: object.cellBytes,
    semanticPath: object.semanticPath,
    contentHash: object.contentHash,
    ownerCert: object.ownerCert,
    typeHash: object.typeHash,
    parentPath: object.parentPath,
    publishedAt: now,
    multicastGroup: topic,
  };
}

/**
 * Build the wire-format CBOR/JSON body for an outbound cell publish.
 * The shape matches what `message-handler.decodeCell` expects on the
 * receive side.
 */
export function buildWireBody(
  object: PublishableObject,
  topic: string,
): CellWireBody {
  return {
    cellBytes: Array.from(object.cellBytes),
    semanticPath: object.semanticPath,
    contentHash: object.contentHash,
    ownerCert: object.ownerCert,
    typeHash: object.typeHash,
    parentPath: object.parentPath,
    topic,
  };
}

export interface FrameCellArgs {
  body: CellWireBody;
  codec: CodecPort;
  msgId: number;
  nodeIdShort: number;
  timestamp: number;
  maxPayload: number;
}

/**
 * Encode + frame an outbound cell packet. Throws `PayloadTooLargeError`
 * when the encoded body exceeds `maxPayload` (UDP fragmentation guard).
 */
export function frameCellPacket(args: FrameCellArgs): Uint8Array {
  const payload = args.codec.encode(args.body);
  if (payload.length > args.maxPayload) {
    throw new PayloadTooLargeError(payload.length, args.maxPayload);
  }
  const header = encodeHeader(
    MSG_CELL,
    args.msgId,
    args.nodeIdShort,
    args.timestamp >>> 0,
    payload.length,
  );
  return framePacket(header, payload);
}

```
