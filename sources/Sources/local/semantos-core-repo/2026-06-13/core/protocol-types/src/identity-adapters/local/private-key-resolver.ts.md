---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/private-key-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.915675+00:00
---

# core/protocol-types/src/identity-adapters/local/private-key-resolver.ts

```ts
/**
 * Private-key resolver — atom-backed cache mapping certId → 32-byte
 * private key. The cache is session-only and never persisted to
 * storage. Replaces the pre-split monolith's `Map` field.
 *
 * The atom is exported so tests / observability tooling can subscribe;
 * production code calls the imperative `getKey` / `cacheKey` /
 * `resolvePrivateKey` helpers instead of touching the atom directly.
 */

import { atom, get, set, type Atom } from '@semantos/state';

import { makeIdentityError } from '../../identity';
import type { CertChainStore } from './cert-chain-store-facade';
import type { CertData } from './cert-chain-store-facade';
import type { KeyDerivationService } from '../KeyDerivationService';

export type CertId = string;

export const privateKeyCacheAtom: Atom<Map<CertId, Uint8Array>> = atom(
  new Map<CertId, Uint8Array>(),
);

/** Read a cached key. Returns undefined if absent. */
export function getKey(certId: CertId): Uint8Array | undefined {
  return get(privateKeyCacheAtom).get(certId);
}

/** Write `key` for `certId`. Replaces any prior value. */
export function cacheKey(certId: CertId, key: Uint8Array): void {
  const next = new Map(get(privateKeyCacheAtom));
  next.set(certId, key);
  set(privateKeyCacheAtom, next);
}

/** Test-only: clear the cache. */
export function clearKeyCache(): void {
  set(privateKeyCacheAtom, new Map());
}

/**
 * Resolve a cert's private key. First consults the atom-backed cache;
 * on miss, walks the parent chain back to a root and re-derives every
 * intermediate key, caching as it goes.
 */
export async function resolvePrivateKey(
  certStore: CertChainStore,
  keyDerivation: KeyDerivationService,
  certId: CertId,
): Promise<Uint8Array> {
  const cached = getKey(certId);
  if (cached) return cached;

  const chain: CertData[] = [];
  let current = await certStore.get(certId);
  while (current) {
    chain.unshift(current);
    if (!current.parentCertId) break;
    current = await certStore.get(current.parentCertId);
  }

  if (chain.length === 0) {
    throw makeIdentityError('CERT_NOT_FOUND', `Cannot resolve key for ${certId}`, true);
  }

  const root = chain[0]!;
  if (!root.email) {
    throw makeIdentityError(
      'CERT_NOT_FOUND',
      `Root cert ${root.certId} has no email for key derivation`,
      false,
    );
  }

  let key = keyDerivation.generateRootKey(root.email);
  cacheKey(root.certId, key);

  for (let i = 1; i < chain.length; i++) {
    const child = chain[i]!;
    key = keyDerivation.deriveChildKey(
      key,
      child.childIndex ?? 0,
      child.domainFlags[0] ?? 0,
    );
    cacheKey(child.certId, key);
  }

  return key;
}

```
