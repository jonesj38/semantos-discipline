---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/identity-registrar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.916545+00:00
---

# core/protocol-types/src/identity-adapters/local/identity-registrar.ts

```ts
/**
 * Identity registration + child derivation — the deterministic
 * key-derivation pipeline lifted out of the monolith.
 *
 * Behaviour preserved 1:1: same inputs → same certId / publicKey /
 * capability token bytes as the pre-split LocalIdentityAdapter. The
 * golden derivation snapshot test in __tests__/ pins this.
 */

import type { CapabilityTokenValidator } from '../CapabilityTokenValidator';
import type { KeyDerivationService } from '../KeyDerivationService';
import type { CertChainStore, CertData } from './cert-chain-store-facade';
import { cacheKey } from './private-key-resolver';

/** Default capability-token TTL: one year. */
export const DEFAULT_TOKEN_TTL = 365 * 24 * 60 * 60 * 1000;

/** All standard domain flags granted to root certs. */
export const ALL_DOMAIN_FLAGS = [
  0x00010001, 0x00010002, 0x00010003, 0x00010004, 0x00010005,
  0x00010006, 0x00010007, 0x00010008, 0x00010009, 0x0001000a,
];

export interface RegistrarDeps {
  certStore: CertChainStore;
  validator: CapabilityTokenValidator;
  keyDerivation: KeyDerivationService;
}

/**
 * Register a fresh root identity for `email`. Idempotent: if a cert
 * for the deterministic certId already exists, returns the existing
 * `{certId, publicKey}` without rewriting the store.
 */
export async function registerRootIdentity(
  deps: RegistrarDeps,
  email: string,
): Promise<{ certId: string; publicKey: string }> {
  const rootKey = deps.keyDerivation.generateRootKey(email);
  const certId = deps.keyDerivation.generateCertId(rootKey);
  const publicKey = deps.keyDerivation.generatePublicKey(rootKey);

  const existing = await deps.certStore.get(certId);
  if (existing) return { certId: existing.certId, publicKey: existing.publicKey };

  // Wave Cap-Substrate Phase 2 (Todd 2026-05-17, "Decouple + delete"):
  // the per-cert bearer capabilityToken was vestigial — authority is
  // proven via the BRC-108 capability-UTXO path (checkCapability/SW4),
  // never this token. No longer minted or stored.
  const cert: CertData = {
    certId,
    email,
    publicKey,
    domainFlags: ALL_DOMAIN_FLAGS,
    created: Date.now(),
    revoked: false,
  };
  await deps.certStore.put(certId, cert);
  cacheKey(certId, rootKey);

  return { certId, publicKey };
}

/**
 * Derive a child identity (hat) under an existing parent. Claims a
 * monotonic child index from the cert store, then derives the child
 * key + cert deterministically.
 */
export async function deriveChildIdentity(
  deps: RegistrarDeps,
  parentCertId: string,
  resourceId: string,
  domainFlag: number,
): Promise<{ certId: string; publicKey: string; childIndex: number }> {
  const parent = await deps.certStore.getOrThrow(parentCertId);

  const { resolvePrivateKey } = await import('./private-key-resolver');
  const parentKey = await resolvePrivateKey(deps.certStore, deps.keyDerivation, parentCertId);

  const childIndex = await deps.certStore.claimNextChildIndex(parentCertId);

  const childKey = deps.keyDerivation.deriveChildKey(parentKey, childIndex, domainFlag);
  const childCertId = deps.keyDerivation.generateCertId(childKey);
  const childPublicKey = deps.keyDerivation.generatePublicKey(childKey);

  const childFlags = [domainFlag];
  // Phase 2: no bearer capabilityToken (see registerRootIdentity).
  const childCert: CertData = {
    certId: childCertId,
    email: parent.email,
    publicKey: childPublicKey,
    parentCertId,
    childIndex,
    resourceId,
    domainFlags: childFlags,
    created: Date.now(),
    revoked: false,
  };
  await deps.certStore.put(childCertId, childCert);
  cacheKey(childCertId, childKey);

  return { certId: childCertId, publicKey: childPublicKey, childIndex };
}

```
