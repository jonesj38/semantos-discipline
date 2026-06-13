---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/tests/manifest.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.636870+00:00
---

# cartridges/tessera/brain/tests/manifest.test.ts

```ts
/**
 * V0.2 — Tessera manifest acceptance tests.
 *
 * Asserts:
 *   - manifest.json parses and matches the typed TESSERA_MANIFEST shape
 *   - 13 verbs declared per docs/prd/TESSERA-CARTRIDGE.md §3.1
 *   - four `consumes` entries (StorageAdapter, IdentityAdapter,
 *     AnchorAdapter, NetworkAdapter)
 *   - eight capabilities declared, all on the 0x000104xx page
 *   - capability domain flags are unique and ordered
 *   - capability names are 1:1 with non-null `capability_required`
 *     entries in manifest.json
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
  TESSERA_MANIFEST,
  TESSERA_CAPABILITIES,
  TESSERA_CAP_NAMES,
  TESSERA_DOMAIN_FLAG_RANGE,
} from '../src/manifest.js';

const HERE = new URL('.', import.meta.url).pathname;
const MANIFEST_JSON_PATH = join(HERE, '../../cartridge.json');
const manifestJson = JSON.parse(readFileSync(MANIFEST_JSON_PATH, 'utf8'));

describe('tessera manifest — V0.2 scaffold', () => {
  test('manifest.json id + version match the typed manifest', () => {
    expect(manifestJson.id).toBe('tessera');
    expect(manifestJson.id).toBe(TESSERA_MANIFEST.id);
    expect(manifestJson.version).toBe(TESSERA_MANIFEST.version);
  });

  test('declares 13 verbs per TESSERA-CARTRIDGE.md §3.1', () => {
    expect(manifestJson.verbs).toHaveLength(13);
    const verbNames = manifestJson.verbs.map((v: { name: string }) => v.name).sort();
    const expected = [
      'tessera.add-tasting-note',
      'tessera.assemble-case',
      'tessera.blend',
      'tessera.bottle',
      'tessera.confirm-receipt',
      'tessera.consumer-scan',
      'tessera.harvest',
      'tessera.rack',
      'tessera.record-care-event',
      'tessera.report-quality-issue',
      'tessera.tamper',
      'tessera.thermo-flag',
      'tessera.transfer-custody',
    ].sort();
    expect(verbNames).toEqual(expected);
  });

  test('declares four `consumes` adapter interfaces', () => {
    const consumedKeys = Object.keys(manifestJson.consumes).sort();
    expect(consumedKeys).toEqual([
      'AnchorAdapter',
      'IdentityAdapter',
      'NetworkAdapter',
      'StorageAdapter',
    ]);
  });

  test('provides no substrate interface (consuming cartridge)', () => {
    expect(manifestJson.provides).toEqual([]);
    expect(TESSERA_MANIFEST.provides).toEqual([]);
  });

  test('declares eight capabilities, all on the 0x000104xx page', () => {
    expect(TESSERA_CAPABILITIES).toHaveLength(8);
    for (const cap of TESSERA_CAPABILITIES) {
      expect(cap.domain_flag).toBeGreaterThanOrEqual(TESSERA_DOMAIN_FLAG_RANGE.low);
      expect(cap.domain_flag).toBeLessThanOrEqual(TESSERA_DOMAIN_FLAG_RANGE.high);
      expect(cap.domain_flag & 0xffffff00).toBe(0x00010400);
    }
  });

  test('capability domain flags are unique', () => {
    const flags = TESSERA_CAPABILITIES.map((c) => c.domain_flag);
    expect(new Set(flags).size).toBe(flags.length);
  });

  test('capability domain flags occupy 0x10..0x17 (above hat byte range)', () => {
    const hatBytes = TESSERA_CAPABILITIES.map((c) => c.domain_flag & 0xff).sort((a, b) => a - b);
    expect(hatBytes).toEqual([0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17]);
  });

  test('capability names match every non-null capability_required in manifest.json', () => {
    const requiredCaps = new Set<string>(
      manifestJson.verbs
        .filter((v: { capability_required: string | null }) => v.capability_required !== null)
        .map((v: { capability_required: string }) => v.capability_required),
    );
    const declaredCaps = new Set(TESSERA_CAP_NAMES);
    // Every required cap is declared.
    for (const cap of requiredCaps) {
      expect(declaredCaps.has(cap)).toBe(true);
    }
    // Every declared cap is required by at least one verb.
    for (const cap of declaredCaps) {
      expect(requiredCaps.has(cap)).toBe(true);
    }
  });

  test('TESSERA_PAGE base is 0x00010400 (range low bound)', () => {
    expect(TESSERA_DOMAIN_FLAG_RANGE.low).toBe(0x00010400);
    expect(TESSERA_DOMAIN_FLAG_RANGE.high).toBe(0x000104ff);
  });
});

```
