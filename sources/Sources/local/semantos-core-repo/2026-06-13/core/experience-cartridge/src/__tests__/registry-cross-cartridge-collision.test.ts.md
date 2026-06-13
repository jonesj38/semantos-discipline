---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/registry-cross-cartridge-collision.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.952322+00:00
---

# core/experience-cartridge/src/__tests__/registry-cross-cartridge-collision.test.ts

```ts
/**
 * T2.c — cross-cartridge typeHash collision tests + cellTypeByHash lookup.
 *
 * Within-cartridge collisions are guarded by `loadCartridgeFromManifest`
 * (separately tested in `manifest-loader.test.ts`).  This file covers
 * the registry-level guard for collisions ACROSS cartridges.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomBytes } from 'node:crypto';
import {
  cartridgeRegistry,
  loadCartridgeFromManifest,
  CartridgeRegistrationError,
} from '../index.js';

const tmpDirs: string[] = [];

async function writeManifestDir(contents: unknown): Promise<string> {
  const dir = join(tmpdir(), `cross-cart-${randomBytes(8).toString('hex')}`);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, 'cartridge.json'), JSON.stringify(contents, null, 2));
  tmpDirs.push(dir);
  return dir;
}

afterEach(async () => {
  cartridgeRegistry.clear();
  while (tmpDirs.length) {
    const dir = tmpDirs.pop()!;
    await rm(dir, { recursive: true, force: true });
  }
});

describe('T2.c — cross-cartridge typeHash collision', () => {
  test('two cartridges declaring identical triples → second register throws DUPLICATE_TYPE_HASH', async () => {
    const sharedTriple = {
      segment1: 'shared',
      segment2: 'collide',
      segment3: 'now',
      segment4: 'v0',
    };

    const dirA = await writeManifestDir({
      id: 'cart-a',
      version: '0.1.0',
      description: 'A',
      cellTypes: [{ name: 'a.thing', triple: sharedTriple, linearity: 'LINEAR' }],
    });
    const dirB = await writeManifestDir({
      id: 'cart-b',
      version: '0.1.0',
      description: 'B',
      cellTypes: [{ name: 'b.thing', triple: sharedTriple, linearity: 'AFFINE' }],
    });

    cartridgeRegistry.register(await loadCartridgeFromManifest(dirA));

    let err: unknown;
    try {
      cartridgeRegistry.register(await loadCartridgeFromManifest(dirB));
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(CartridgeRegistrationError);
    const cre = err as CartridgeRegistrationError;
    expect(cre.code).toBe('DUPLICATE_TYPE_HASH');
    expect(cre.cartridgeId).toBe('cart-b');
    expect(cre.existing).toBe('cart-a:a.thing');
    expect(cre.attempted).toBe('cart-b:b.thing');
    expect(cre.message).toContain('globally unique');
  });

  test('in-process upgrade (same id, higher version) does NOT collision-check against itself', async () => {
    const triple = { segment1: 'x', segment2: 'y', segment3: 'z', segment4: 'v0' };

    const dirOld = await writeManifestDir({
      id: 'upgrader',
      version: '0.1.0',
      description: 'old',
      cellTypes: [{ name: 'x.y', triple, linearity: 'LINEAR' }],
    });
    const dirNew = await writeManifestDir({
      id: 'upgrader',
      version: '0.2.0',
      description: 'new',
      cellTypes: [{ name: 'x.y', triple, linearity: 'LINEAR' }],
    });

    cartridgeRegistry.register(await loadCartridgeFromManifest(dirOld));

    // Upgrade — same id, new version, same typeHash. MUST NOT trip the
    // cross-cartridge collision guard (would otherwise block upgrades).
    expect(() => {
      // Re-load to get fresh CellTypeRegistryEntry instances
    }).not.toThrow();
    cartridgeRegistry.register(await loadCartridgeFromManifest(dirNew));
    expect(cartridgeRegistry.byName('upgrader')?.manifest.version).toBe('0.2.0');
  });

  test('cartridges with no cellTypes skip the collision check entirely', () => {
    // A legacy/test cartridge with no manifest-driven cell types must
    // not interact with the collision logic.
    expect(() => {
      cartridgeRegistry.register({
        manifest: { id: 'legacy-a', version: '0.1.0', description: '' },
      });
      cartridgeRegistry.register({
        manifest: { id: 'legacy-b', version: '0.1.0', description: '' },
      });
    }).not.toThrow();
  });
});

describe('T2.c — cellTypeByHash lookup across all registered cartridges', () => {
  test('returns the owning cartridge + entry for a known hash', async () => {
    const dir = await writeManifestDir({
      id: 'lookup-cart',
      version: '0.1.0',
      description: 'L',
      cellTypes: [
        { name: 'l.alpha', triple: { segment1: 'l', segment2: 'a', segment3: '', segment4: '' }, linearity: 'LINEAR' },
        { name: 'l.beta',  triple: { segment1: 'l', segment2: 'b', segment3: '', segment4: '' }, linearity: 'AFFINE' },
      ],
    });
    const loaded = await loadCartridgeFromManifest(dir);
    cartridgeRegistry.register(loaded);

    const alpha = loaded.cellTypes!.find((c) => c.manifest.name === 'l.alpha')!;
    const result = cartridgeRegistry.cellTypeByHash(alpha.typeHashHex);
    expect(result).toBeDefined();
    expect(result!.cartridgeId).toBe('lookup-cart');
    expect(result!.entry.manifest.name).toBe('l.alpha');
  });

  test('returns undefined for an unknown hash', () => {
    expect(cartridgeRegistry.cellTypeByHash('00'.repeat(32))).toBeUndefined();
  });

  test('finds the right cartridge when multiple are registered', async () => {
    const dirA = await writeManifestDir({
      id: 'multi-a',
      version: '0.1.0',
      description: 'A',
      cellTypes: [{ name: 'a.thing', triple: { segment1: 'a', segment2: 'a', segment3: '', segment4: '' }, linearity: 'LINEAR' }],
    });
    const dirB = await writeManifestDir({
      id: 'multi-b',
      version: '0.1.0',
      description: 'B',
      cellTypes: [{ name: 'b.thing', triple: { segment1: 'b', segment2: 'b', segment3: '', segment4: '' }, linearity: 'AFFINE' }],
    });
    const loadedA = await loadCartridgeFromManifest(dirA);
    const loadedB = await loadCartridgeFromManifest(dirB);
    cartridgeRegistry.register(loadedA);
    cartridgeRegistry.register(loadedB);

    const aHash = loadedA.cellTypes![0]!.typeHashHex;
    const bHash = loadedB.cellTypes![0]!.typeHashHex;
    expect(cartridgeRegistry.cellTypeByHash(aHash)?.cartridgeId).toBe('multi-a');
    expect(cartridgeRegistry.cellTypeByHash(bHash)?.cartridgeId).toBe('multi-b');
  });
});

```
