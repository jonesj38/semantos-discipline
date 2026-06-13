---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/__tests__/cartridge-manifest.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.886434+00:00
---

# core/protocol-types/src/__tests__/cartridge-manifest.test.ts

```ts
/**
 * CC0a conformance — canonical cartridge manifest superset.
 *
 * Ref: docs/design/CANONICAL-CARTRIDGE-MODEL.md (RATIFIED C1/C3),
 * docs/canon/commissions/wave-canonical-cartridge.md CC0.
 *
 * Asserts the manifest IS the canonical `cartridge.json`: role
 * classification (C1, death of app/extension), the Brain↔PWA
 * `experience.flutterPackage` binding (C3), the lexicon section (C2),
 * AND that every existing manifest still validates (non-breaking —
 * the new fields are optional; CC4 backfills them per cartridge).
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { validateExtensionManifest } from '../extension-manifest';

const BASE = {
  id: 'oddjobz',
  name: 'Oddjobz',
  version: '0.1.0',
  taxonomyPath: 'src/cell-types/index.ts',
  flowsDir: 'src/state-machines',
  promptsDir: 'src/prompts',
};

describe('CC0a — canonical cartridge manifest', () => {
  test('back-compat: a legacy manifest (no role/experience/lexicon) still validates', () => {
    expect(() => validateExtensionManifest({ ...BASE })).not.toThrow();
    // The real oddjobz shape (consumes, verbs, capabilitiesPath) too.
    expect(() =>
      validateExtensionManifest({
        ...BASE,
        consumes: { StorageAdapter: 'required' },
        verbs: [{ name: 'jobs.transition', capability_required: 'cap.oddjobz.dispatch' }],
      }),
    ).not.toThrow();
  });

  test('C1 role: enum enforced; valid roles accepted', () => {
    expect(() => validateExtensionManifest({ ...BASE, role: 'experience' })).not.toThrow();
    expect(() => validateExtensionManifest({ ...BASE, role: 'grammar-lexicon' })).not.toThrow();
    expect(() => validateExtensionManifest({ ...BASE, role: 'app' })).toThrow(/role must be/);
    expect(() => validateExtensionManifest({ ...BASE, role: 'extension' })).toThrow(/role must be/);
  });

  test('Decision-B: role=infra REQUIRES provides', () => {
    expect(() => validateExtensionManifest({ ...BASE, role: 'infra' })).toThrow(
      /role='infra' requires `provides`/,
    );
    expect(() =>
      validateExtensionManifest({
        ...BASE,
        role: 'infra',
        provides: ['@semantos/protocol-types/spv'],
      }),
    ).not.toThrow();
  });

  test('C3 experience: must be { flutterPackage: string }', () => {
    expect(() =>
      validateExtensionManifest({
        ...BASE,
        role: 'experience',
        experience: { flutterPackage: 'packages/oddjobz_experience' },
      }),
    ).not.toThrow();
    expect(() => validateExtensionManifest({ ...BASE, experience: {} })).toThrow(
      /experience must be/,
    );
    expect(() =>
      validateExtensionManifest({ ...BASE, experience: { flutterPackage: '' } }),
    ).toThrow(/experience must be/);
  });

  test('C2 lexicon: { id: string; sourcePath?: string }', () => {
    expect(() =>
      validateExtensionManifest({
        ...BASE,
        lexicon: { id: 'trades', sourcePath: 'src/lexicon.ts' },
      }),
    ).not.toThrow();
    expect(() => validateExtensionManifest({ ...BASE, lexicon: { id: 'trades' } })).not.toThrow();
    expect(() => validateExtensionManifest({ ...BASE, lexicon: {} })).toThrow(/lexicon must be/);
    expect(() =>
      validateExtensionManifest({ ...BASE, lexicon: { id: 'x', sourcePath: 5 } }),
    ).toThrow(/lexicon.sourcePath/);
  });

  test('CC1: role=infra is EXEMPT from taxonomy/flows/prompts (real wallet-headers shape)', () => {
    // An infra cartridge provides adapters, not a discourse surface.
    expect(() =>
      validateExtensionManifest({
        id: 'wallet-headers',
        name: 'Wallet & Headers',
        version: '0.1.0',
        role: 'infra',
        provides: ['@semantos/protocol-types/ports#SpvVerifier'],
        // NO taxonomyPath / flowsDir / promptsDir
      }),
    ).not.toThrow();
    // Legacy (no role) STILL requires them — back-compat preserved.
    expect(() =>
      validateExtensionManifest({ id: 'x', name: 'X', version: '1' }),
    ).toThrow(/taxonomyPath/);
  });

  test('the shipped cartridges/wallet-headers/cartridge.json validates', () => {
    const mani = JSON.parse(
      readFileSync(join(import.meta.dir, '../../../../cartridges/wallet-headers/cartridge.json'), 'utf-8'),
    );
    expect(() => validateExtensionManifest(mani)).not.toThrow();
    expect(mani.role).toBe('infra');
    expect(Array.isArray(mani.provides)).toBe(true);
  });

  test('a fully-canonical cartridge.json (infra) validates', () => {
    expect(() =>
      validateExtensionManifest({
        ...BASE,
        id: 'wallet',
        name: 'Wallet',
        role: 'infra',
        provides: ['@semantos/protocol-types/spv', '@semantos/protocol-types/wallet'],
        consumes: { StorageAdapter: 'required' },
        licenseOutpointRef: 'a'.repeat(64) + ':0',
        licenseLinearity: 'AFFINE',
      }),
    ).not.toThrow();
  });

  // ── C7 (CC4-M): brain-surface kind ──────────────────────────────
  test('C7: brain.surface=walkers EXEMPT from taxonomy/flows/prompts (jambox shape)', () => {
    // jambox — a real experience cartridge whose Brain part is an
    // imperative verb-walkers module, NOT a cell discourse surface.
    expect(() =>
      validateExtensionManifest({
        id: 'jambox',
        name: 'Jam Room',
        version: '0.1.0',
        role: 'experience',
        experience: { flutterPackage: 'packages/jam_experience' },
        brain: { surface: 'walkers', verbsModule: 'jambox_walkers' },
        verbs: [{ name: 'launch_clip' }, { name: 'record_take' }],
        // NO taxonomyPath / flowsDir / promptsDir — that's the point
      }),
    ).not.toThrow();
  });

  test('C7: brain.surface=walkers REQUIRES verbsModule', () => {
    expect(() =>
      validateExtensionManifest({
        id: 'jambox',
        name: 'Jam Room',
        version: '0.1.0',
        role: 'experience',
        brain: { surface: 'walkers' },
      }),
    ).toThrow(/surface='walkers' requires `verbsModule`/);
  });

  test('C7: brain.surface=none (PWA-only) EXEMPT; cells/absent still require the dirs', () => {
    expect(() =>
      validateExtensionManifest({
        id: 'pwa-only',
        name: 'PWA Only',
        version: '0.1.0',
        role: 'experience',
        experience: { flutterPackage: 'packages/x_experience' },
        brain: { surface: 'none' },
      }),
    ).not.toThrow();
    // brain.surface=cells is the back-compat default ⇒ still required.
    expect(() =>
      validateExtensionManifest({
        id: 'c',
        name: 'C',
        version: '1',
        role: 'experience',
        brain: { surface: 'cells' },
      }),
    ).toThrow(/taxonomyPath/);
    // No brain field at all ⇒ defaults to cells ⇒ still required.
    expect(() =>
      validateExtensionManifest({ id: 'd', name: 'D', version: '1', role: 'experience' }),
    ).toThrow(/taxonomyPath/);
  });

  test('C7: brain shape + surface enum validated', () => {
    expect(() =>
      validateExtensionManifest({ ...BASE, brain: { surface: 'bogus' } }),
    ).toThrow(/brain.surface must be/);
    expect(() =>
      validateExtensionManifest({ ...BASE, brain: 'walkers' }),
    ).toThrow(/brain must be an object/);
  });
});

```
