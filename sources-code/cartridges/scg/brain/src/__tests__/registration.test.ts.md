---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/brain/src/__tests__/registration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.557748+00:00
---

# cartridges/scg/brain/src/__tests__/registration.test.ts

```ts
/**
 * RM-021 acceptance — SCG manifest loads + registers as a cartridge
 * (alongside Oddjobz), and the grammar exposes the expected entity
 * mappings + capability requirements.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { ClientDomainFlags } from '@plexus/contracts';
import { cartridgeRegistry, loadCartridge } from '@semantos/experience-cartridge';
import { scgGrammar } from '../grammar.js';
import { scgManifest } from '../manifest.js';

afterEach(() => cartridgeRegistry.clear());

describe('SCG grammar', () => {
  test('G1 declares the two canonical entity mappings', () => {
    const entityIds = scgGrammar.entityMappings.map((e) => e.entityId);
    expect(entityIds).toEqual(['scg.cell', 'scg.relation']);
  });

  test('G2 binds RELATION_MINT and RELATION_REVOKE capabilities', () => {
    const names = scgGrammar.capabilities.map((c) => c.name);
    expect(names).toEqual(['RELATION_MINT', 'RELATION_REVOKE']);
    const flags = scgGrammar.capabilities.map((c) => c.capability);
    expect(flags).toEqual([
      ClientDomainFlags.RELATION_MINT,
      ClientDomainFlags.RELATION_REVOKE,
    ]);
  });

  test('G3 uses the scg taxonomy namespace', () => {
    expect(scgGrammar.taxonomyNamespace).toBe('scg');
    expect(scgGrammar.grammarId).toBe('com.semantos.scg');
  });

  test('G4 RELATION_MINT capability is required; REVOKE is optional', () => {
    const mint = scgGrammar.capabilities.find((c) => c.name === 'RELATION_MINT');
    const revoke = scgGrammar.capabilities.find((c) => c.name === 'RELATION_REVOKE');
    expect(mint?.required).toBe(true);
    expect(revoke?.required).toBe(false);
  });
});

describe('SCG manifest registration', () => {
  test('M1 scgManifest loads as a cartridge', () => {
    const c = loadCartridge({ manifest: scgManifest });
    expect(c.manifest.id).toBe('scg');
    expect(c.manifest.version).toBe('0.1.0');
  });

  test('M2 registry registers scg cartridge alongside other extensions', () => {
    cartridgeRegistry.register(loadCartridge({ manifest: scgManifest }));
    cartridgeRegistry.register(
      loadCartridge({
        manifest: { id: 'other', version: '0.1.0', description: 'sibling' },
      }),
    );
    const list = cartridgeRegistry.list();
    expect(list.map((c) => c.manifest.id).sort()).toEqual(['other', 'scg']);
    expect(cartridgeRegistry.byName('scg')?.manifest.grammarId).toBe(
      'com.semantos.scg',
    );
  });

  test('M3 conversationHooks slot declares the RM-031 auto-emit helper', () => {
    expect(scgManifest.conversationHooks).toBe('auto-emit-reply-relation');
  });
});

```
