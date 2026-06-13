---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/local-edge-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.650480+00:00
---

# cartridges/wallet-headers/brain/src/local-edge-store.ts

```ts
// local-edge-store.ts — Phase C: local storage of edge envelopes (no Plexus dispatch)

// An edge recipe stored locally in localStorage
// (dispatched to Plexus when backend is live)
export interface LocalEdgeEnvelope {
  edgeId: string;
  myCertId: string;
  theirCertId: string;
  theirPublicKey: string;   // 33-byte hex
  signingKeyIndex: number;  // BKDS monotonic index
  edgeType: string;         // 'MESSAGING' etc
  // BRC-69 revelation recipe: hex-encoded HMAC that proves the edge
  // existed without revealing the shared secret
  backupRecipe: string;
  createdAt: number;        // unix ms
}

export const EDGE_STORE_KEY = 'wallet:edge-envelopes';

export function loadEdgeEnvelopes(): LocalEdgeEnvelope[] {
  try {
    const raw = localStorage.getItem(EDGE_STORE_KEY);
    if (!raw) return [];
    return JSON.parse(raw) as LocalEdgeEnvelope[];
  } catch {
    return [];
  }
}

export function saveEdgeEnvelope(env: LocalEdgeEnvelope): void {
  const envelopes = loadEdgeEnvelopes();
  // Replace existing entry with same edgeId, or append
  const idx = envelopes.findIndex(e => e.edgeId === env.edgeId);
  if (idx >= 0) {
    envelopes[idx] = env;
  } else {
    envelopes.push(env);
  }
  localStorage.setItem(EDGE_STORE_KEY, JSON.stringify(envelopes));
}

export function getEdgeEnvelope(edgeId: string): LocalEdgeEnvelope | null {
  const envelopes = loadEdgeEnvelopes();
  return envelopes.find(e => e.edgeId === edgeId) ?? null;
}

/**
 * Increment signingKeyIndex for an edge after a successful rotated payment.
 * No-op if the edge is not found.
 */
export function advanceEdgeIndex(edgeId: string): void {
  const env = getEdgeEnvelope(edgeId);
  if (!env) return;
  saveEdgeEnvelope({ ...env, signingKeyIndex: env.signingKeyIndex + 1 });
}

/**
 * Find active edge to a given theirCertId (returns most recent non-null).
 */
export function findEdgeTo(theirCertId: string): LocalEdgeEnvelope | null {
  const envelopes = loadEdgeEnvelopes();
  const matching = envelopes.filter(e => e.theirCertId === theirCertId);
  if (matching.length === 0) return null;
  // Return the most recent (highest createdAt)
  return matching.reduce((best, cur) => cur.createdAt > best.createdAt ? cur : best);
}

```
