---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/control-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.065811+00:00
---

# runtime/session-protocol/src/adapters/multicast/control-flow.ts

```ts
/**
 * control-flow — pure helpers for outbound `MSG_CONTROL` framing.
 *
 * Lifted out of the orchestrator so the file stays under the prompt-38
 * LOC budget. Mirrors `publish-flow.ts` and `heartbeat-flow.ts` in
 * shape: the helpers know nothing about transport, queue, or
 * lifecycle — they just build the wire packet.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes these helpers
 */

import type { CodecPort } from "./ports/codec-port.js";
import { PayloadTooLargeError, type ControlMessage } from "./types.js";
import {
  MSG_CONTROL,
  encodeHeader,
  framePacket,
} from "./wire-header.js";

export interface FrameControlArgs {
  msg: ControlMessage;
  codec: CodecPort;
  msgId: number;
  nodeIdShort: number;
  now: number;
  maxPayload: number;
}

/**
 * Encode + frame an outbound MSG_CONTROL packet. Throws
 * `PayloadTooLargeError` when the encoded body exceeds `maxPayload`.
 */
export function frameControlPacket(args: FrameControlArgs): Uint8Array {
  const payload = args.codec.encode(args.msg);
  if (payload.length > args.maxPayload) {
    throw new PayloadTooLargeError(payload.length, args.maxPayload);
  }
  const header = encodeHeader(
    MSG_CONTROL,
    args.msgId,
    args.nodeIdShort,
    args.now >>> 0,
    payload.length,
  );
  return framePacket(header, payload);
}

```
