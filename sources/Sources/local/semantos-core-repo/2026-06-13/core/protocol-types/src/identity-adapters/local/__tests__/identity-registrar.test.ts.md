---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/identity-registrar.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.917220+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/identity-registrar.test.ts

```ts
/**
 * Identity registrar tests — registerRootIdentity + deriveChildIdentity.
 *
 * Pin determinism: same inputs must always produce the same certId /
 * publicKey / capabilityToken. This is the snapshot the prompt-07
 * test plan asks for.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { CertChainStore } from '../cert-chain-store-facade';
import { CapabilityTokenValidator } from '../../CapabilityTokenValidator';
import { KeyDerivationService } from '../../KeyDerivationService';
import { MemoryAdapter } from '../../../adapters/memory-adapter';
import {
  ALL_DOMAIN_FLAGS,
  deriveChildIdentity,
  registerRootIdentity,
} from '../identity-registrar';
import { clearKeyCache } from '../private-key-resolver';

afterEach(() => clearKeyCache());

function makeDeps() {
  const adapter = new MemoryAdapter();
  const certStore = new CertChainStore(adapter);
  const validator = new CapabilityTokenValidator(certStore);
  const keyDerivation = new KeyDerivationService();
  return { adapter, certStore, validator, keyDerivation };
}

describe('registerRootIdentity', () => {
  test('1. assigns a deterministic certId + publicKey for a fresh email', async () => {
    const a = makeDeps();
    const out = await registerRootIdentity(a, 'alice@example.com');

    const b = makeDeps();
    const out2 = await registerRootIdentity(b, 'alice@example.com');
    expect(out2).toEqual(out);
  });

  test('2. is idempotent on a second call with the same email', async () => {
    const deps = makeDeps();
    const first = await registerRootIdentity(deps, 'alice@example.com');
    const second = await registerRootIdentity(deps, 'alice@example.com');
    expect(second).toEqual(first);
  });

  test('3. stores a cert with all standard domain flags', async () => {
    const deps = makeDeps();
    const { certId } = await registerRootIdentity(deps, 'alice@example.com');
    const cert = await deps.certStore.getOrThrow(certId);
    expect(cert.domainFlags).toEqual(ALL_DOMAIN_FLAGS);
    expect(cert.revoked).toBe(false);
    // Wave Cap-Substrate Phase 2 (Todd 2026-05-17 "Decouple + delete"):
    // the vestigial per-cert bearer capabilityToken is no longer minted
    // or stored — authority is the BRC-108 capability-UTXO path.
    expect(cert.capabilityToken).toBeUndefined();
  });

  test('4. different emails yield different certIds', async () => {
    const deps = makeDeps();
    const a = await registerRootIdentity(deps, 'alice@example.com');
    const b = await registerRootIdentity(deps, 'bob@example.com');
    expect(a.certId).not.toBe(b.certId);
  });
});

describe('deriveChildIdentity', () => {
  test('5. assigns monotonic child indices', async () => {
    const deps = makeDeps();
    const root = await registerRootIdentity(deps, 'alice@example.com');
    const c1 = await deriveChildIdentity(deps, root.certId, 'res-1', 0x00010003);
    const c2 = await deriveChildIdentity(deps, root.certId, 'res-2', 0x00010004);
    expect(c1.childIndex).toBe(0);
    expect(c2.childIndex).toBe(1);
  });

  test('6. is deterministic for fixed (parent, index, domain) tuples', async () => {
    const a = makeDeps();
    await registerRootIdentity(a, 'bob@example.com');
    const rootA = (await a.certStore.getChildren('')).length === 0;
    expect(rootA).toBe(true); // sanity: no orphan children
    const root = await registerRootIdentity(a, 'bob@example.com');
    const childA = await deriveChildIdentity(a, root.certId, 'r', 0x00010003);

    const b = makeDeps();
    const rootB = await registerRootIdentity(b, 'bob@example.com');
    const childB = await deriveChildIdentity(b, rootB.certId, 'r', 0x00010003);

    expect(childA.certId).toBe(childB.certId);
    expect(childA.publicKey).toBe(childB.publicKey);
  });

  test('7. child cert carries the requested domain flag only', async () => {
    const deps = makeDeps();
    const root = await registerRootIdentity(deps, 'eve@example.com');
    const child = await deriveChildIdentity(deps, root.certId, 'r', 0x00010005);
    const stored = await deps.certStore.getOrThrow(child.certId);
    expect(stored.domainFlags).toEqual([0x00010005]);
    expect(stored.parentCertId).toBe(root.certId);
  });
});

```
