---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/cc4-jambox-golden-path.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.885341+00:00
---

# core/protocol-types/src/__tests__/cc4-jambox-golden-path.test.ts

```ts
/**
 * CC4-2 — jambox golden path (the C7 verb-walkers cartridge, both
 * shells, real seams).
 *
 * Proves the SECOND collapsed cartridge end-to-end against the SHIPPED
 * artifacts — and specifically that C7 (CC4-M) makes a brain-less-cell
 * (verb-walkers) experience cartridge first-class:
 *   - cartridges/jambox/cartridge.json validates with role=experience
 *     AND brain.surface='walkers' AND NO taxonomy/flows/prompts
 *     (the exemption that did not exist before C7).
 *   - the Brain resolver orders it (infra → experience) alongside the
 *     wallet-headers infra cartridge and oddjobz.
 *   - the cross-shell id contract: cartridge.json id === the PWA
 *     CartridgeRegistry id self-registered by packages/jam_experience.
 */
import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { ExtensionLoader } from '../extension-loader';
import { validateExtensionManifest } from '../extension-manifest';

const REPO = join(import.meta.dir, '..', '..', '..', '..');

function readManifest(p: string): Record<string, unknown> {
  return JSON.parse(readFileSync(join(REPO, p), 'utf-8'));
}

describe('CC4-2 — jambox golden path (C7 verb-walkers, both shells)', () => {
  const jambox = readManifest('cartridges/jambox/cartridge.json');
  const oddjobz = readManifest('cartridges/oddjobz/cartridge.json');
  const walletHeaders = readManifest('cartridges/wallet-headers/cartridge.json');

  test('1. C7 binding: jambox validates as experience + brain.surface=walkers WITHOUT taxonomy/flows/prompts', () => {
    expect(() => validateExtensionManifest(jambox)).not.toThrow();
    expect(jambox.role).toBe('experience');
    expect((jambox.brain as { surface: string }).surface).toBe('walkers');
    expect((jambox.brain as { verbsModule: string }).verbsModule).toBe('jambox_walkers');
    // The whole point of C7: NO cell discourse surface declared.
    expect(jambox.taxonomyPath).toBeUndefined();
    expect(jambox.flowsDir).toBeUndefined();
    expect(jambox.promptsDir).toBeUndefined();
    // And it still binds a PWA experience.
    expect((jambox.experience as { flutterPackage: string }).flutterPackage).toBe(
      'packages/jam_experience',
    );
  });

  test('2. pre-C7 shape would have been rejected (regression guard for the amendment)', () => {
    // Same cartridge MINUS the brain field ⇒ defaults to cells ⇒ the
    // old rule (taxonomy/flows/prompts required) rejects it. This is
    // exactly the gap C7 closed; assert the gap still exists without C7.
    const { brain: _omit, ...noBrain } = jambox as Record<string, unknown>;
    expect(() => validateExtensionManifest(noBrain)).toThrow(/taxonomyPath/);
  });

  test('3. Brain-shell resolver orders infra(wallet-headers) → experience(jambox, oddjobz)', () => {
    const { order } = ExtensionLoader.resolveCartridgeOrder([
      { id: jambox.id as string, role: jambox.role as 'experience' },
      {
        id: oddjobz.id as string,
        role: oddjobz.role as 'experience',
        consumes: oddjobz.consumes as Record<string, unknown>,
      },
      {
        id: walletHeaders.id as string,
        role: walletHeaders.role as 'infra',
        provides: walletHeaders.provides as string[],
      },
    ]);
    expect(order[0]).toBe('wallet-headers'); // infra first
    expect(order).toContain('jambox');
    expect(order).toContain('oddjobz');
  });

  test('4. verbs declared match the jambox_walkers brain surface', () => {
    const names = (jambox.verbs as { name: string }[]).map((v) => v.name).sort();
    expect(names).toEqual(['launch_clip', 'record_take']);
  });

  test('5. cross-shell contract: Brain manifest id == PWA registry id (jambox)', () => {
    // archive/packages-jam_experience/lib/src/cartridge.dart self-registers
    // id:'jambox' / route:'/jambox' into CartridgeRegistry; the Brain
    // serves the same id. The shared id is the seam.
    expect(jambox.id).toBe('jambox');
    const dart = readFileSync(
      join(REPO, 'archive/packages-jam_experience/lib/src/cartridge.dart'),
      'utf-8',
    );
    expect(dart).toMatch(/id:\s*'jambox'/);
  });
});

```
