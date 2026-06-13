---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.065519+00:00
---

# runtime/session-protocol/src/adapters/multicast/types.ts

```ts
/**
 * Shared multicast types — wire-adjacent, domain-neutral.
 *
 * Lifted from the legacy `multicast-adapter.ts` so peer-manager,
 * message-handler, outbound-queue, subscription-store and the
 * orchestrator can each import without dragging in the whole adapter.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — original definitions
 */

import type { NodeInfo } from "@semantos/protocol-types/network";

/** Information about a peer observed on the multicast group. */
export interface MulticastPeerInfo {
  /** Short 16-bit node identifier (from CoAP header). */
  nodeIdShort: number;
  /** IPv6 BCA — unique cryptographic identity. */
  bca: string;
  /** Source address on the underlying transport. */
  address: string;
  /** Most recent heartbeat timestamp. */
  lastSeen: number;
  /** Uptime reported by the peer in its heartbeat. */
  uptime: number;
  /** Arbitrary freeform metadata (consumer-defined fields). */
  metadata?: Record<string, unknown>;
}

/** Wire format for heartbeat CBOR bodies. */
export interface MulticastHeartbeat {
  nodeIdShort: number;
  bca: string;
  uptime: number;
  peersKnown: number;
  timestamp: number;
  metadata?: Record<string, unknown>;
}

/** Control message ride-along on the multicast group. */
export interface ControlMessage {
  type: string;
  from: number;
  payload: Record<string, unknown>;
}

/** Wire body emitted by `publish`. */
export interface CellWireBody {
  cellBytes: number[];
  semanticPath: string;
  contentHash: string;
  ownerCert: string;
  typeHash: string;
  parentPath?: string;
  topic: string;
}

/** Observer event fired when two owners publish to the same semantic path. */
export interface DuplicatePathEvent {
  type: "duplicate_path";
  semanticPath: string;
  existingOwner: string;
  newOwner: string;
  timestamp: number;
}

/**
 * Supplies the Plexus-style metadata previously faked in `resolveBCA`.
 * Callers (node, loom) inject the real provider; tests pass a stub.
 */
export interface NodeMetadataProvider {
  metadataFor(bca: string): Promise<Partial<NodeInfo>>;
}

export class PayloadTooLargeError extends Error {
  constructor(
    public readonly size: number,
    public readonly maxPayload: number,
  ) {
    super(`Payload size ${size} exceeds maxPayload ${maxPayload}`);
    this.name = "PayloadTooLargeError";
  }
}

```
