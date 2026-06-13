---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/peer-locator/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.165864+00:00
---

# runtime/peer-locator/src/types.ts

```ts
/**
 * PeerLocator — common contract for resolving BCAs to WSS endpoints.
 *
 * Implementations shipped in Phase 35B.1:
 *   - StaticPeerLocator  (map-backed, for tests + bootstrap)
 *   - DnsPeerLocator     (DNS TXT queries, injectable resolver)
 *
 * Future (35B.3): `FederatedPeerLocator` — operator-run HTTP registry
 * implementing the same interface.
 */

/**
 * Everything a dialer needs to open a WSS connection to a peer node.
 *
 * `pubkey` and `licenseCertId` are optional and let the dialer pin the
 * identity without trusting the claimed BCA alone. When present, a
 * dialer should reject handshakes that don't match.
 */
export interface NodeEndpoint {
  /** IPv6 BCA of the node, e.g. `"2602:f9f8::b0b"`. */
  bca: string;
  /** WebSocket URL to dial, e.g. `"wss://bob.example.com:443/session"`. */
  wssUrl: string;
  /** Optional 33-byte compressed secp256k1 pubkey for identity pinning. */
  pubkey?: Uint8Array;
  /** Optional license cert id (`"sha256:<hex>"`) — see protocol-types/license. */
  licenseCertId?: string;
}

/**
 * Common contract every PeerLocator implements.
 */
export interface PeerLocator {
  /** Resolve a BCA to its endpoint, or null if not reachable. */
  resolve(bca: string): Promise<NodeEndpoint | null>;
  /**
   * Register an endpoint. Implementations may or may not persist the
   * registration — DNS-backed locators are a no-op here because they
   * read from external DNS, not local state.
   */
  register(endpoint: NodeEndpoint): Promise<void>;
}

/**
 * Injectable TXT-resolver seam. Production wires this to `node:dns` /
 * `dns/promises`; tests inject a fake that returns canned records.
 */
export interface TxtResolver {
  resolveTxt(hostname: string): Promise<string[]>;
}

```
