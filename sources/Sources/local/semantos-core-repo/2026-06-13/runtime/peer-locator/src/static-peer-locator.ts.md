---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/src/static-peer-locator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.166411+00:00
---

# runtime/peer-locator/src/static-peer-locator.ts

```ts
/**
 * StaticPeerLocator — map-backed, synchronous, test- and bootstrap-friendly.
 *
 * Holds a `bca → NodeEndpoint` map. Useful for:
 *   - Unit tests that want deterministic peer resolution with no DNS.
 *   - The initial bootstrap entries in a node's config
 *     (`locator.bootstrap_peers`), so a fresh node can reach known-good
 *     peers before falling back to DNS.
 */

import type { NodeEndpoint, PeerLocator } from "./types.js";

export interface StaticPeerLocatorConfig {
  /** Initial set of endpoints. `register` will extend this map at runtime. */
  endpoints?: readonly NodeEndpoint[];
}

export class StaticPeerLocator implements PeerLocator {
  private readonly endpoints = new Map<string, NodeEndpoint>();

  constructor(cfg: StaticPeerLocatorConfig = {}) {
    for (const ep of cfg.endpoints ?? []) {
      this.endpoints.set(ep.bca, ep);
    }
  }

  async resolve(bca: string): Promise<NodeEndpoint | null> {
    return this.endpoints.get(bca) ?? null;
  }

  async register(endpoint: NodeEndpoint): Promise<void> {
    this.endpoints.set(endpoint.bca, endpoint);
  }

  /** Non-interface: list everything currently known. Handy for tests. */
  all(): NodeEndpoint[] {
    return Array.from(this.endpoints.values());
  }
}

```
