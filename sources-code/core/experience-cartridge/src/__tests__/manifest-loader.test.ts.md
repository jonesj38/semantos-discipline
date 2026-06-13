---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/manifest-loader.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.953760+00:00
---

# core/experience-cartridge/src/__tests__/manifest-loader.test.ts

```ts
/**
 * Tests for the manifest-driven cartridge loader (T2.a).
 *
 * Exercises:
 *   - happy path: minimal valid manifest with one cellTypes entry
 *   - happy path: oddjobz-shaped manifest (UI + identity fields)
 *   - happy path: tessera-shaped manifest (linearity values RELEVANT, DEBUG)
 *   - typeHash is computed (not read) from the triple — drift-proof
 *   - DUPLICATE_TYPE_HASH error when two entries collide
 *   - INVALID_MANIFEST errors for missing/bad fields
 *   - empty cellTypes[] (or absent) loads cleanly
 *   - segments containing unicode + hyphens both work
 *
 * Hashes asserted match the T1 parity vectors in
 * `core/protocol-types/__tests__/type-hash-parity.test.ts`.
 */

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { randomBytes } from 'node:crypto';
import {
  loadCartridgeFromManifest,
  CartridgeRegistrationError,
} from '../index.js';

let tmpRoot: string;

async function writeManifest(contents: unknown): Promise<string> {
  const dir = join(tmpdir(), `cartridge-test-${randomBytes(8).toString('hex')}`);
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, 'cartridge.json'), JSON.stringify(contents, null, 2));
  return dir;
}

beforeEach(() => {
  tmpRoot = '';
});

afterEach(async () => {
  if (tmpRoot) {
    await rm(tmpRoot, { recursive: true, force: true });
  }
});

describe('loadCartridgeFromManifest — happy path', () => {
  test('minimal valid manifest with no cellTypes', async () => {
    tmpRoot = await writeManifest({
      id: 'test.minimal',
      version: '0.1.0',
      description: 'Test cartridge with no cell types.',
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    expect(loaded.manifest.id).toBe('test.minimal');
    expect(loaded.manifest.version).toBe('0.1.0');
    expect(loaded.cellTypes).toEqual([]);
  });

  test('manifest with one cellTypes entry computes typeHash', async () => {
    tmpRoot = await writeManifest({
      id: 'oddjobz',
      version: '0.1.0',
      description: 'Oddjobz test',
      cellTypes: [
        {
          name: 'oddjobz.job',
          triple: {
            segment1: 'oddjobz',
            segment2: 'job',
            segment3: 'worktrack',
            segment4: 'v2',
          },
          linearity: 'LINEAR',
        },
      ],
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    expect(loaded.cellTypes).toBeDefined();
    expect(loaded.cellTypes!.length).toBe(1);
    const job = loaded.cellTypes![0]!;
    expect(job.manifest.name).toBe('oddjobz.job');
    expect(job.typeHashHex).toBe(
      // Structured parity vector for ("oddjobz","job","worktrack","v2") under T5.a
      'c4cf2fd44009863e5e8c9902207afaeb822965fc3debc30dfb04dcb6970e4c3d',
    );
    expect(job.typeHash.length).toBe(32);
  });

  test('oddjobz-shaped entry carries UI fields through to LoadedCartridge', async () => {
    tmpRoot = await writeManifest({
      id: 'oddjobz',
      version: '0.1.0',
      description: 'Oddjobz test',
      cellTypes: [
        {
          name: 'oddjobz.site',
          triple: { segment1: 'oddjobz', segment2: 'site', segment3: 'locate', segment4: '' },
          linearity: 'PERSISTENT',
          displayName: 'Site',
          primaryAnchor: true,
          description: 'A physical location.',
          payloadSchema: { normalisedAddress: { type: 'string' } },
          phases: ['active'],
          initialPhase: 'active',
        },
      ],
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    const site = loaded.cellTypes![0]!;
    expect(site.manifest.displayName).toBe('Site');
    expect(site.manifest.primaryAnchor).toBe(true);
    expect(site.manifest.payloadSchema).toEqual({ normalisedAddress: { type: 'string' } });
    expect(site.manifest.phases).toEqual(['active']);
  });

  test('tessera-shaped entries with RELEVANT and DEBUG linearities load', async () => {
    tmpRoot = await writeManifest({
      id: 'tessera',
      version: '0.1.0',
      description: 'Tessera test',
      cellTypes: [
        {
          name: 'tessera.scan-event',
          triple: { segment1: 'tessera', segment2: 'scan-event', segment3: 'scan', segment4: '' },
          linearity: 'RELEVANT',
        },
        {
          name: 'tessera.tasting-note',
          triple: { segment1: 'tessera', segment2: 'tasting-note', segment3: 'taste', segment4: '' },
          linearity: 'DEBUG',
        },
      ],
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    expect(loaded.cellTypes!.length).toBe(2);
    expect(loaded.cellTypes![0]!.manifest.linearity).toBe('RELEVANT');
    expect(loaded.cellTypes![1]!.manifest.linearity).toBe('DEBUG');
  });

  test('typeHash is computed not read — hash field in manifest is ignored', async () => {
    tmpRoot = await writeManifest({
      id: 'driftcheck',
      version: '0.1.0',
      description: 'Drift check',
      cellTypes: [
        {
          name: 'a.b',
          triple: { segment1: 'a', segment2: 'b', segment3: 'c', segment4: 'd' },
          linearity: 'LINEAR',
          // A bogus 'typeHash' field should be silently ignored — the
          // loader always derives from the triple.
          typeHash: 'deadbeef'.repeat(8),
        },
      ],
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    expect(loaded.cellTypes![0]!.typeHashHex).toBe(
      // Structured parity vector for ("a","b","c","d") under T5.a
      'ca978112ca1bbdca3e23e8160039594a2e7d2c03a9507ae218ac3e7343f01689',
    );
  });

  test('unicode segments hash correctly', async () => {
    tmpRoot = await writeManifest({
      id: 'unicode',
      version: '0.1.0',
      description: 'Unicode',
      cellTypes: [
        {
          name: 'café.naïve',
          triple: { segment1: 'café', segment2: 'naïve', segment3: '日本', segment4: '🦀' },
          linearity: 'AFFINE',
        },
      ],
    });
    const loaded = await loadCartridgeFromManifest(tmpRoot);
    expect(loaded.cellTypes![0]!.typeHashHex).toBe(
      // Structured parity vector for unicode segments under T5.a
      '850f7dc43910ff89f86fd89de87a848acf2abf0c5be326cb7224c588fa988754',
    );
  });
});

describe('loadCartridgeFromManifest — collisions and validation', () => {
  test('throws DUPLICATE_TYPE_HASH when two entries produce the same hash', async () => {
    tmpRoot = await writeManifest({
      id: 'collide',
      version: '0.1.0',
      description: 'Collision',
      cellTypes: [
        {
          name: 'one',
          triple: { segment1: 'x', segment2: 'y', segment3: 'z', segment4: 'w' },
          linearity: 'LINEAR',
        },
        {
          name: 'two',
          triple: { segment1: 'x', segment2: 'y', segment3: 'z', segment4: 'w' },
          linearity: 'AFFINE',
        },
      ],
    });
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(CartridgeRegistrationError);
    const cre = err as CartridgeRegistrationError;
    expect(cre.code).toBe('DUPLICATE_TYPE_HASH');
    expect(cre.existing).toBe('one');
    expect(cre.attempted).toBe('two');
  });

  test('throws INVALID_MANIFEST when triple missing', async () => {
    tmpRoot = await writeManifest({
      id: 'badtriple',
      version: '0.1.0',
      description: 'Bad',
      cellTypes: [{ name: 'a', linearity: 'LINEAR' }],
    });
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(CartridgeRegistrationError);
    expect((err as CartridgeRegistrationError).code).toBe('INVALID_MANIFEST');
  });

  test('throws INVALID_MANIFEST when triple segment is not a string', async () => {
    tmpRoot = await writeManifest({
      id: 'badseg',
      version: '0.1.0',
      description: 'Bad',
      cellTypes: [
        {
          name: 'a',
          triple: { segment1: 'x', segment2: 'y', segment3: 'z', segment4: 42 },
          linearity: 'LINEAR',
        },
      ],
    });
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect((err as CartridgeRegistrationError).code).toBe('INVALID_MANIFEST');
  });

  test('throws INVALID_MANIFEST for unknown linearity value', async () => {
    tmpRoot = await writeManifest({
      id: 'badlin',
      version: '0.1.0',
      description: 'Bad',
      cellTypes: [
        {
          name: 'a',
          triple: { segment1: 'x', segment2: 'y', segment3: 'z', segment4: 'w' },
          linearity: 'AFFFINE', // typo
        },
      ],
    });
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect((err as CartridgeRegistrationError).code).toBe('INVALID_MANIFEST');
  });

  test('throws INVALID_MANIFEST for missing id', async () => {
    tmpRoot = await writeManifest({ version: '0.1.0', description: 'no id' });
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect((err as CartridgeRegistrationError).code).toBe('INVALID_MANIFEST');
  });

  test('throws INVALID_MANIFEST for non-JSON content', async () => {
    tmpRoot = join(tmpdir(), `cartridge-test-${randomBytes(8).toString('hex')}`);
    await mkdir(tmpRoot, { recursive: true });
    await writeFile(join(tmpRoot, 'cartridge.json'), 'this is not json {{{');
    let err: unknown;
    try {
      await loadCartridgeFromManifest(tmpRoot);
    } catch (e) {
      err = e;
    }
    expect((err as CartridgeRegistrationError).code).toBe('INVALID_MANIFEST');
  });
});

```
