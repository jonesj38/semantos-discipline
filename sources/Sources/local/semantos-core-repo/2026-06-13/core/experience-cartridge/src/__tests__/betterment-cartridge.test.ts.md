---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/betterment-cartridge.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.953203+00:00
---

# core/experience-cartridge/src/__tests__/betterment-cartridge.test.ts

```ts
/**
 * T6 golden-path test — `loadCartridgeFromManifest` over the real
 * `cartridges/betterment/cartridge.json`.
 *
 * Pins:
 *   - betterment exposes 23 cellTypes (5 sub-namespaces)
 *   - all share bytes 0:7 (sha256("betterment")[0:8] = 06d0a049e88a982b)
 *   - paskian.graph.* share bytes 0:23
 *   - practice.* share bytes 0:15
 *   - practice cells get displayName + payloadSchema per SQ3
 *   - paskian + state cells are identity-only per SQ3
 *
 * Drift detection: if any triple in cartridge.json changes, the
 * corresponding hex assertion fails — surfaces unintended wire-format
 * changes early.
 *
 * RENAME (2026-05-29): cartridge previously `self` with cell-type
 * prefix `self.*` and namespace bytes `06c604b332b386b6`. Renamed to
 * `betterment` (prefix bytes `06d0a049e88a982b`) so the word "self" is
 * free for the shell-level identity primitive. Test file moved from
 * self-cartridge.test.ts.
 */

import { describe, expect, test } from 'bun:test';
import { join, resolve } from 'node:path';
import { loadCartridgeFromManifest } from '../manifest-loader.js';

const REPO_ROOT = resolve(import.meta.dir, '../../../..');
const BETTERMENT_PATH = join(REPO_ROOT, 'cartridges/betterment');

describe('T6 — real betterment cartridge.json', () => {
  test('loads with 23 cellTypes', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    expect(loaded.manifest.id).toBe('betterment');
    expect(loaded.cellTypes).toBeDefined();
    expect(loaded.cellTypes!.length).toBe(23);
  });

  test('every cellType starts with sha256("betterment")[0:8] = 06d0a049e88a982b', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    for (const ct of loaded.cellTypes!) {
      expect(ct.typeHashHex.slice(0, 16)).toBe('06d0a049e88a982b');
    }
  });

  test('paskian.graph.* (4 cells) share bytes 0:24 — sub-sub-namespace prefix', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const paskGraph = loaded.cellTypes!.filter((c) =>
      c.manifest.name.startsWith('betterment.paskian.graph.'),
    );
    expect(paskGraph.length).toBe(4);
    const prefix = paskGraph[0]!.typeHashHex.slice(0, 48);
    for (const ct of paskGraph) {
      expect(ct.typeHashHex.slice(0, 48)).toBe(prefix);
    }
  });

  test('practice.* (8 cells) share bytes 0:16 — sub-namespace prefix', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const practice = loaded.cellTypes!.filter((c) =>
      c.manifest.name.startsWith('betterment.practice.'),
    );
    expect(practice.length).toBe(8);
    const prefix = practice[0]!.typeHashHex.slice(0, 32);
    for (const ct of practice) {
      expect(ct.typeHashHex.slice(0, 32)).toBe(prefix);
    }
  });

  test('SQ3 — practice cells carry displayName + payloadSchema', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const practice = loaded.cellTypes!.filter((c) =>
      c.manifest.name.startsWith('betterment.practice.'),
    );
    for (const ct of practice) {
      expect(ct.manifest.displayName).toBeDefined();
      expect(typeof ct.manifest.displayName).toBe('string');
      expect(ct.manifest.payloadSchema).toBeDefined();
    }
  });

  test('SQ3 — paskian + state + story cells are identity-only (no displayName)', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const derived = loaded.cellTypes!.filter((c) =>
      c.manifest.name.startsWith('betterment.paskian.') ||
      c.manifest.name.startsWith('betterment.state.') ||
      c.manifest.name.startsWith('betterment.story.'),
    );
    for (const ct of derived) {
      expect(ct.manifest.displayName).toBeUndefined();
      expect(ct.manifest.payloadSchema).toBeUndefined();
    }
  });

  test('all 23 typeHashes are distinct', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const hexes = loaded.cellTypes!.map((c) => c.typeHashHex);
    expect(new Set(hexes).size).toBe(23);
  });

  test('Release cell — pinned hex for routing-prefix demo', async () => {
    const loaded = await loadCartridgeFromManifest(BETTERMENT_PATH);
    const release = loaded.cellTypes!.find((c) => c.manifest.name === 'betterment.practice.release')!;
    // Recomputed by Node sha256 over (betterment, practice, release, "").
    // The hex matches cartridges/betterment/brain/zig/betterment_cell_specs.zig EXPECTED.
    expect(release.typeHashHex).toBe(
      '06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14',
    );
  });
});

```
