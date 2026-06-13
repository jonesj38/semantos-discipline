---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/heartbeat-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.063519+00:00
---

# runtime/session-protocol/src/adapters/multicast/heartbeat-flow.ts

```ts
/**
 * heartbeat-flow — pure helpers for emitting our own heartbeat.
 *
 * The orchestrator owns the timer; this module owns the framing and
 * payload-shape guarantees so tests can pin them without a real
 * adapter spinning up.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes these helpers
 */

import type { CodecPort } from "./ports/codec-port.js";
import type { MulticastHeartbeat } from "./types.js";
import {
  MSG_HEARTBEAT,
  encodeHeader,
  framePacket,
} from "./wire-header.js";

export interface BuildHeartbeatArgs {
  nodeIdShort: number;
  bca: string;
  startedAt: number;
  peersKnown: number;
  now: number;
}

export function buildHeartbeat(
  args: BuildHeartbeatArgs,
): MulticastHeartbeat {
  return {
    nodeIdShort: args.nodeIdShort,
    bca: args.bca,
    uptime: args.startedAt ? args.now - args.startedAt : 0,
    peersKnown: args.peersKnown,
    timestamp: args.now,
  };
}

export interface FrameHeartbeatArgs {
  hb: MulticastHeartbeat;
  codec: CodecPort;
  msgId: number;
  nodeIdShort: number;
  now: number;
  maxPayload: number;
}

/**
 * Returns the framed packet, or `null` when the encoded heartbeat
 * exceeds `maxPayload` (heartbeats are best-effort and must stay small;
 * dropping silently matches legacy behaviour).
 */
export function frameHeartbeatPacket(
  args: FrameHeartbeatArgs,
): Uint8Array | null {
  const payload = args.codec.encode(args.hb);
  if (payload.length > args.maxPayload) return null;
  const header = encodeHeader(
    MSG_HEARTBEAT,
    args.msgId,
    args.nodeIdShort,
    args.now >>> 0,
    payload.length,
  );
  return framePacket(header, payload);
}

```
