---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.045544+00:00
---

# runtime/session-protocol/src/adapters/multicast-adapter.ts

```ts
/**
 * @deprecated MulticastAdapter has moved to `./multicast/`.
 *
 * This file is now a re-export shim preserved so existing callers
 * (`runtime/node`, `apps/poker-agent/table-formation`,
 * `tests/gates/phase35a-gate`) keep compiling without source changes.
 *
 * The 793-LOC monolith was split per the prompt-38 spec:
 *
 *   - `./multicast/ports/codec-port.ts`      — CBOR/JSON codec port
 *   - `./multicast/peer-manager.ts`          — peer registry
 *   - `./multicast/message-handler.ts`       — pure dispatch
 *   - `./multicast/outbound-queue.ts`        — queue + retry policy
 *   - `./multicast/subscription-store.ts`    — `topic → Subscriber[]`
 *   - `./multicast/object-store.ts`          — local NetworkResult cache
 *   - `./multicast/group-membership.ts`      — multicast group lifecycle
 *   - `./multicast/publish-flow.ts`          — outbound cell framing
 *   - `./multicast/heartbeat-flow.ts`        — heartbeat framing
 *   - `./multicast/control-flow.ts`          — control-message framing
 *   - `./multicast/observers.ts`             — callback registries
 *   - `./multicast/operations.ts`            — NetworkAdapter method bodies
 *   - `./multicast/effect-applier.ts`        — fold HandlerEffects → state
 *   - `./multicast/lifecycle.ts`             — timer-tick helpers
 *   - `./multicast/resolve-bca.ts`           — `resolveBCA` body
 *   - `./multicast/wire-header.ts`           — CoAP-like 12-byte header
 *   - `./multicast/types.ts`                 — wire-adjacent types
 *   - `./multicast/multicast-adapter.ts`     — orchestrator (≤220 LOC)
 *
 * See docs/prd/refactor-monoliths/38-multicast-adapter-split.md.
 */

export {
  MulticastAdapter,
  type MulticastAdapterConfig,
} from "./multicast/multicast-adapter.js";

export {
  HEADER_SIZE,
  MSG_CELL,
  MSG_CONTROL,
  MSG_HEARTBEAT,
  decodeHeader,
  deriveNodeIdShort,
  encodeHeader,
} from "./multicast/wire-header.js";

export {
  PayloadTooLargeError,
  type ControlMessage,
  type DuplicatePathEvent,
  type MulticastHeartbeat,
  type MulticastPeerInfo,
  type NodeMetadataProvider,
} from "./multicast/types.js";

export {
  createDefaultCodec,
  createJsonCodec,
  type CodecPort,
} from "./multicast/ports/codec-port.js";

```
