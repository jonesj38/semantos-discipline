---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/manifest-loader-real-cartridges.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.952888+00:00
---

# core/experience-cartridge/src/__tests__/manifest-loader-real-cartridges.test.ts

```ts
/**
 * T2.a golden-path test — exercises `loadCartridgeFromManifest` against
 * the real `cartridges/oddjobz/cartridge.json` and
 * `cartridges/tessera/cartridge.json` after the migration.
 *
 * Pins:
 *   - oddjobz exposes 11 cellTypes (all v1 suffixes dropped)
 *   - tessera exposes 10 cellTypes (linearity unchanged, triples added)
 *   - linearity-drift fixes landed correctly in oddjobz (site=PERSISTENT,
 *     customer=PERSISTENT, job=LINEAR — TS authority wins over old
 *     cartridge.json's AFFINE)
 *   - the dead `objectTypesDir` field is gone from both
 *   - the dead `objectTypes` field is gone from oddjobz
 *   - typeHash hex for a few known triples matches the T1 parity vectors
 *
 * Drift detection: if a cartridge.json triple changes after this lands,
 * the corresponding typeHash assertion fails — surfaces unintended
 * wire-format changes early.
 */

import { describe, expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { loadCartridgeFromManifest } from '../manifest-loader.js';

// Repo-root absolute path (this file lives at
//   <repo>/core/experience-cartridge/src/__tests__/...
// so walk up four levels).
const REPO_ROOT = resolve(import.meta.dir, '../../../..');

describe('T2.a — real oddjobz cartridge.json', () => {
  const oddjobzPath = join(REPO_ROOT, 'cartridges/oddjobz');

  test('loads with 11 cellTypes after v1 strip + fold of objectTypes', async () => {
    const loaded = await loadCartridgeFromManifest(oddjobzPath);
    expect(loaded.manifest.id).toBe('oddjobz');
    expect(loaded.cellTypes).toBeDefined();
    expect(loaded.cellTypes!.length).toBe(11);

    const names = loaded.cellTypes!.map((c) => c.manifest.name).sort();
    expect(names).toEqual([
      'oddjobz.attachment',
      'oddjobz.customer',
      'oddjobz.estimate',
      'oddjobz.invoice',
      'oddjobz.job',
      'oddjobz.lead',
      'oddjobz.message',
      'oddjobz.pricing_policy',
      'oddjobz.quote',
      'oddjobz.site',
      'oddjobz.visit',
    ]);

    // Sanity check: no `.v1` suffix anywhere per D12
    for (const name of names) {
      expect(name).not.toMatch(/\.v\d+$/);
    }
  });

  test('linearity drift fixed — site=PERSISTENT, customer=PERSISTENT, job=LINEAR', async () => {
    const loaded = await loadCartridgeFromManifest(oddjobzPath);
    const byName = new Map(loaded.cellTypes!.map((c) => [c.manifest.name, c.manifest]));
    expect(byName.get('oddjobz.site')!.linearity).toBe('PERSISTENT');
    expect(byName.get('oddjobz.customer')!.linearity).toBe('PERSISTENT');
    expect(byName.get('oddjobz.job')!.linearity).toBe('LINEAR');
  });

  test('Site preserves payloadSchema + UI fields from old objectTypes entry', async () => {
    const loaded = await loadCartridgeFromManifest(oddjobzPath);
    const site = loaded.cellTypes!.find((c) => c.manifest.name === 'oddjobz.site')!;
    expect(site.manifest.displayName).toBe('Site');
    expect(site.manifest.primaryAnchor).toBe(true);
    expect(site.manifest.payloadSchema).toBeDefined();
    expect(Object.keys(site.manifest.payloadSchema!)).toContain('normalisedAddress');
    expect(site.manifest.phases).toEqual(['active']);
    expect(site.manifest.initialPhase).toBe('active');
  });

  test('oddjobz.job typeHash matches the canonical hash for its triple', async () => {
    const loaded = await loadCartridgeFromManifest(oddjobzPath);
    const job = loaded.cellTypes!.find((c) => c.manifest.name === 'oddjobz.job')!;
    expect(job.manifest.triple).toEqual({
      segment1: 'oddjobz',
      segment2: 'job',
      segment3: 'worktrack',
      segment4: '',
    });
    // T5.a structured hex for ("oddjobz","job","worktrack",""):
    //   sha256("oddjobz")[0:8] = c4cf2fd44009863e
    //   sha256("job")[0:8]     = 5e8c9902207afaeb
    //   sha256("worktrack")[0:8] = 822965fc3debc30d
    //   sha256("")[0:8]        = e3b0c44298fc1c14
    expect(job.typeHashHex).toBe(
      'c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30de3b0c44298fc1c14',
    );
  });

  test('dead fields removed: objectTypes and objectTypesDir', async () => {
    // We don't go through the loader for this — read the raw JSON.
    const raw = await readFile(join(oddjobzPath, 'cartridge.json'), 'utf-8');
    const json = JSON.parse(raw);
    expect(json.objectTypes).toBeUndefined();
    expect(json.objectTypesDir).toBeUndefined();
    expect(Array.isArray(json.cellTypes)).toBe(true);
  });
});

describe('T2.a — real tessera cartridge.json', () => {
  const tesseraPath = join(REPO_ROOT, 'cartridges/tessera');

  test('loads with 10 cellTypes — linearity preserved (no drift)', async () => {
    const loaded = await loadCartridgeFromManifest(tesseraPath);
    expect(loaded.manifest.id).toBe('tessera');
    expect(loaded.cellTypes!.length).toBe(10);

    const byName = new Map(loaded.cellTypes!.map((c) => [c.manifest.name, c.manifest]));
    expect(byName.get('tessera.grape-lot')!.linearity).toBe('AFFINE');
    expect(byName.get('tessera.barrel')!.linearity).toBe('LINEAR');
    expect(byName.get('tessera.scan-event')!.linearity).toBe('RELEVANT');
    expect(byName.get('tessera.tasting-note')!.linearity).toBe('DEBUG');
  });

  test('tessera.grape-lot typeHash matches the canonical hash for its triple', async () => {
    const loaded = await loadCartridgeFromManifest(tesseraPath);
    const lot = loaded.cellTypes!.find((c) => c.manifest.name === 'tessera.grape-lot')!;
    expect(lot.manifest.triple).toEqual({
      segment1: 'tessera',
      segment2: 'grape-lot',
      segment3: 'harvest',
      segment4: '',
    });
    // T5.a structured hex for ("tessera","grape-lot","harvest",""):
    //   sha256("tessera")[0:8] = 2f1e83d30fff12f1
    //   plus sha256(grape-lot)/(harvest)/("") prefixes.
    expect(lot.typeHashHex).toBe(
      '2f1e83d30fff12f1d0c46e6bc767169ed087ee8196afa2ffe3b0c44298fc1c14',
    );
  });

  test('dead objectTypesDir removed', async () => {
    const raw = await readFile(join(tesseraPath, 'cartridge.json'), 'utf-8');
    const json = JSON.parse(raw);
    expect(json.objectTypesDir).toBeUndefined();
    expect(Array.isArray(json.cellTypes)).toBe(true);
  });

  test('all 10 cellTypes have triple + linearity + name', async () => {
    const loaded = await loadCartridgeFromManifest(tesseraPath);
    for (const ct of loaded.cellTypes!) {
      expect(ct.manifest.name).toMatch(/^tessera\./);
      expect(ct.manifest.triple.segment1).toBe('tessera');
      expect(ct.manifest.triple.segment4).toBe(''); // no version per D12
      expect(typeof ct.manifest.linearity).toBe('string');
      expect(ct.typeHash.length).toBe(32);
      expect(ct.typeHashHex.length).toBe(64);
    }
  });
});

describe('T2.a — no duplicate typeHashes across either cartridge', () => {
  test('oddjobz: all 11 typeHashes distinct', async () => {
    const loaded = await loadCartridgeFromManifest(join(REPO_ROOT, 'cartridges/oddjobz'));
    const hexes = loaded.cellTypes!.map((c) => c.typeHashHex);
    expect(new Set(hexes).size).toBe(11);
  });

  test('tessera: all 10 typeHashes distinct', async () => {
    const loaded = await loadCartridgeFromManifest(join(REPO_ROOT, 'cartridges/tessera'));
    const hexes = loaded.cellTypes!.map((c) => c.typeHashHex);
    expect(new Set(hexes).size).toBe(10);
  });
});

```
