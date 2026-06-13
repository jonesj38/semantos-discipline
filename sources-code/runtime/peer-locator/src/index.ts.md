---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.165597+00:00
---

# runtime/peer-locator/src/index.ts

```ts
/**
 * @semantos/peer-locator — BCA → wss endpoint resolution.
 *
 * Phase 35B.1 ships two implementations:
 *
 *   - StaticPeerLocator  — map-backed, tests + bootstrap entries
 *   - DnsPeerLocator     — DNS TXT at `_semantos-node.<hostname>`, with
 *                          injectable resolver + TTL cache
 *
 * Phase 35B.3 adds `FederatedPeerLocator` (operator-run HTTP registry)
 * on the same `PeerLocator` interface.
 */

export type { NodeEndpoint, PeerLocator, TxtResolver } from "./types.js";

export { StaticPeerLocator } from "./static-peer-locator.js";
export type { StaticPeerLocatorConfig } from "./static-peer-locator.js";

export {
  DnsPeerLocator,
  NodeDnsTxtResolver,
  parseNodeEndpointTxt,
} from "./dns-peer-locator.js";
export type { DnsPeerLocatorConfig } from "./dns-peer-locator.js";

```
