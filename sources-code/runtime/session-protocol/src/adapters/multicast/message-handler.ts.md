---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/message-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.067757+00:00
---

# runtime/session-protocol/src/adapters/multicast/message-handler.ts

```ts
/**
 * message-handler — inbound envelope dispatch, pure.
 *
 * Per the prompt-38 spec: "pure function `handleIncoming(envelope, ctx)
 * → HandlerEffect[]`." The orchestrator decodes the wire header, hands
 * us the typed payload + a small `HandlerCtx`, and applies the returned
 * effects (peer upserts, subscriber notifications, control callbacks).
 *
 * Splitting dispatch this way means tests can drive cell/heartbeat/
 * control flows without spinning up a transport — they construct
 * payloads, call `handleIncoming`, and assert against the effect
 * stream.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./types.ts — payload shapes
 *   ./wire-header.ts — `WireHeader` + msg-type constants
 */

import type {
  NetworkEvent,
  NetworkResult,
} from "@semantos/protocol-types/network";
import type { RemoteInfo } from "@semantos/protocol-types/adapters/udp-transport";

import type { CodecPort } from "./ports/codec-port.js";
import type {
  CellWireBody,
  ControlMessage,
  MulticastHeartbeat,
  MulticastPeerInfo,
} from "./types.js";
import {
  COAP_VERSION,
  HEADER_SIZE,
  MSG_CELL,
  MSG_CONTROL,
  MSG_HEARTBEAT,
  decodeHeader,
  type WireHeader,
} from "./wire-header.js";

/**
 * Effects emitted by `handleIncoming`. The orchestrator fold these into
 * peer-store / subscription-store / observer-callback updates.
 */
export type HandlerEffect =
  | { kind: "peer-heartbeat"; peer: MulticastPeerInfo }
  | {
      kind: "cell-received";
      topic: string;
      result: NetworkResult;
      event: NetworkEvent;
    }
  | { kind: "control-received"; msg: ControlMessage; rinfo: RemoteInfo }
  | { kind: "drop"; reason: "own-message" | "bad-version" | "too-short" | "decode-error" };

/** Snapshot context the handler needs to dispatch correctly. */
export interface HandlerCtx {
  /** Our own short id; used to drop our own multicast echoes. */
  ownNodeIdShort: number;
  /** Codec for body decoding. */
  codec: CodecPort;
  /** Wall-clock at the moment of receipt (test-injectable). */
  now: number;
}

/**
 * Dispatch a single inbound packet. The function never mutates any
 * external state — it returns the list of effects that should be
 * applied. Decode failures collapse to a `drop` effect rather than
 * raising, matching the legacy "malformed → ignore" semantics.
 */
export function handleIncoming(
  packet: Uint8Array,
  rinfo: RemoteInfo,
  ctx: HandlerCtx,
): HandlerEffect[] {
  if (packet.length < HEADER_SIZE) {
    return [{ kind: "drop", reason: "too-short" }];
  }

  const header = decodeHeader(packet.subarray(0, HEADER_SIZE));
  if (header.version !== COAP_VERSION) {
    return [{ kind: "drop", reason: "bad-version" }];
  }
  if (header.nodeIdShort === ctx.ownNodeIdShort) {
    return [{ kind: "drop", reason: "own-message" }];
  }

  const payload = packet.subarray(
    HEADER_SIZE,
    HEADER_SIZE + header.payloadLen,
  );

  switch (header.msgType) {
    case MSG_HEARTBEAT:
      return decodeHeartbeat(payload, rinfo, ctx);
    case MSG_CELL:
      return decodeCell(payload, header, ctx);
    case MSG_CONTROL:
      return decodeControl(payload, rinfo, ctx);
    default:
      return [{ kind: "drop", reason: "decode-error" }];
  }
}

function decodeHeartbeat(
  payload: Uint8Array,
  rinfo: RemoteInfo,
  ctx: HandlerCtx,
): HandlerEffect[] {
  try {
    const hb = ctx.codec.decode(payload) as MulticastHeartbeat;
    const peer: MulticastPeerInfo = {
      nodeIdShort: hb.nodeIdShort,
      bca: hb.bca,
      address: rinfo.address,
      lastSeen: ctx.now,
      uptime: hb.uptime,
      metadata: hb.metadata,
    };
    return [{ kind: "peer-heartbeat", peer }];
  } catch {
    return [{ kind: "drop", reason: "decode-error" }];
  }
}

function decodeCell(
  payload: Uint8Array,
  header: WireHeader,
  ctx: HandlerCtx,
): HandlerEffect[] {
  try {
    const wire = ctx.codec.decode(payload) as CellWireBody;

    const txid = `mc${header.nodeIdShort
      .toString(16)
      .padStart(4, "0")}${header.msgId.toString(16).padStart(8, "0")}`.padEnd(
      64,
      "0",
    );

    const result: NetworkResult = {
      txid,
      vout: 0,
      cellBytes: new Uint8Array(wire.cellBytes),
      semanticPath: wire.semanticPath,
      contentHash: wire.contentHash,
      ownerCert: wire.ownerCert,
      typeHash: wire.typeHash,
      parentPath: wire.parentPath,
      publishedAt: header.timestamp,
      multicastGroup: wire.topic,
    };

    const event: NetworkEvent = {
      type: "object_published",
      result,
      timestamp: ctx.now,
    };

    return [
      { kind: "cell-received", topic: wire.topic, result, event },
    ];
  } catch {
    return [{ kind: "drop", reason: "decode-error" }];
  }
}

function decodeControl(
  payload: Uint8Array,
  rinfo: RemoteInfo,
  ctx: HandlerCtx,
): HandlerEffect[] {
  try {
    const msg = ctx.codec.decode(payload) as ControlMessage;
    return [{ kind: "control-received", msg, rinfo }];
  } catch {
    return [{ kind: "drop", reason: "decode-error" }];
  }
}

```
