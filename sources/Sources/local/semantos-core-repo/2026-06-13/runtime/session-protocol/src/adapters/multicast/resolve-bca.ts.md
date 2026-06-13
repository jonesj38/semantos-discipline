---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/resolve-bca.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.066096+00:00
---

# runtime/session-protocol/src/adapters/multicast/resolve-bca.ts

```ts
/**
 * resolve-bca — pure helper that builds a `NodeInfo` response from the
 * peer-store record for `address`, optionally augmented by injected
 * metadata.
 *
 * Lifted from the legacy `MulticastAdapter.resolveBCA` so the
 * orchestrator file can stay under the prompt-38 LOC budget.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes this helper
 */

import type { NodeInfo } from "@semantos/protocol-types/network";

import { getPeerByAddress, type PeerStore } from "./peer-manager.js";
import type { NodeMetadataProvider } from "./types.js";

export async function resolveNodeInfo(
  peers: PeerStore,
  address: string,
  metadataProvider: NodeMetadataProvider | undefined,
): Promise<NodeInfo | null> {
  const peer = getPeerByAddress(peers, address);
  if (!peer) return null;
  const injected = metadataProvider
    ? await metadataProvider.metadataFor(peer.bca)
    : {};
  return {
    bca: peer.bca,
    nodeCert: injected.nodeCert ?? "",
    name: injected.name ?? peer.bca,
    extensions: injected.extensions ?? [],
    adapters:
      injected.adapters ??
      { storage: "memory", identity: "", anchor: "", network: "multicast" },
    version: injected.version ?? "0.0.1",
    uptime: peer.uptime,
    lastAnchorProof: injected.lastAnchorProof,
  };
}

```
