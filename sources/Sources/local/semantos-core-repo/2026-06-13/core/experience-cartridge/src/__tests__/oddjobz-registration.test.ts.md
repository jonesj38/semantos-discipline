---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/oddjobz-registration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.952611+00:00
---

# core/experience-cartridge/src/__tests__/oddjobz-registration.test.ts

```ts
/**
 * RM-011 acceptance — Oddjobz manifest registers cleanly as a cartridge.
 *
 * The roadmap's "Oddjobz still boots" gate is Zig-side and outside this
 * package's test surface. The TS-side gate is: `oddjobzManifest`
 * loads + registers without errors, and shows up in `list()`.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { oddjobzManifest } from '@semantos/oddjobz';
import { cartridgeRegistry } from '../registry.js';
import { loadCartridge } from '../loader.js';

afterEach(() => cartridgeRegistry.clear());

describe('Oddjobz cartridge registration (RM-011 acceptance)', () => {
  test('O1 oddjobzManifest loads as a cartridge', () => {
    const c = loadCartridge({ manifest: oddjobzManifest });
    expect(c.manifest.id).toBe('oddjobz');
    expect(c.manifest.version).toBe('0.1.0');
  });

  test('O2 registry registers oddjobz and lists it', () => {
    cartridgeRegistry.register(loadCartridge({ manifest: oddjobzManifest }));
    const list = cartridgeRegistry.list();
    expect(list).toHaveLength(1);
    expect(list[0]?.manifest.id).toBe('oddjobz');
    expect(cartridgeRegistry.byName('oddjobz')?.manifest.id).toBe('oddjobz');
  });
});

```
