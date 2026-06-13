---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/__tests__/typehash-parity.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.954333+00:00
---

# core/experience-cartridge/src/__tests__/typehash-parity.test.ts

```ts
/**
 * Q10-A + Q11-C parity tests.
 *
 * Q10-A (structural manifest ↔ TS-defineCellType parity for oddjobz):
 *   The manifest is the source of truth for cell-type IDENTITY (name +
 *   triple + linearity).  TS `defineCellType()` files retain ownership
 *   of validators / packers / payload types only.  After T2.a, the two
 *   sets of names must agree 1:1 modulo the `.v1` strip (and the
 *   intentionally-deleted attachment.v1 per D12 — see test below).
 *
 * Q11-C (legacy-ingest literal drift-detection):
 *   `runtime/legacy-ingest/src/cell-writer/brain-rpc.ts` hardcodes four
 *   `sha256(<colon-triple>)` literals for site/customer/job/attachment.
 *   These are the OLD-format hashes (v2 colon-triple), distinct by
 *   design from the new manifest-based hashes (wire-break per D8).
 *   This test pins the four literal hex values so any accidental edit
 *   to the literal strings surfaces immediately — protecting legacy
 *   data interop during the transition window.
 */

import { describe, expect, test } from 'bun:test';
import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { loadCartridgeFromManifest } from '../manifest-loader.js';

const REPO_ROOT = resolve(import.meta.dir, '../../../..');

// ─────────────────────────────────────────────────────────────────────
// Q10-A: structural parity between cartridge.json cellTypes[] and
// the cartridges/oddjobz/brain/src/cell-types/*.ts defineCellType files
// ─────────────────────────────────────────────────────────────────────

describe('Q10-A — oddjobz manifest ↔ TS defineCellType structural parity', () => {
  test('every manifest cellType has a matching TS defineCellType file', async () => {
    const loaded = await loadCartridgeFromManifest(join(REPO_ROOT, 'cartridges/oddjobz'));
    const manifestNames = new Set(loaded.cellTypes!.map((c) => c.manifest.name));
    expect(manifestNames.size).toBe(11);

    // Mapping: manifest `oddjobz.<X>` ↔ TS file `<X>.ts` (or `<X>.v2.ts`
    // for attachment per the transition window — D12 says strip .v1 from
    // manifest; the .v2 TS file still ships as the validator owner).
    const expectedTsFiles: Record<string, string> = {
      'oddjobz.site': 'site.ts',
      'oddjobz.customer': 'customer.ts',
      'oddjobz.job': 'job.ts',
      'oddjobz.attachment': 'attachment.v2.ts', // attachment is special — see below
      'oddjobz.estimate': 'estimate.ts',
      'oddjobz.invoice': 'invoice.ts',
      'oddjobz.lead': 'lead.ts',
      'oddjobz.message': 'message.ts',
      'oddjobz.pricing_policy': 'pricing-policy.ts',
      'oddjobz.quote': 'quote.ts',
      'oddjobz.visit': 'visit.ts',
    };

    for (const name of manifestNames) {
      const expectedFile = expectedTsFiles[name];
      expect(expectedFile).toBeDefined();
      const fullPath = join(
        REPO_ROOT,
        'cartridges/oddjobz/brain/src/cell-types',
        expectedFile!,
      );
      const contents = await readFile(fullPath, 'utf-8');
      expect(contents).toContain('defineCellType');
    }
  });

  test('manifest cellTypes have no .v1 / .v2 suffix per D12', async () => {
    const loaded = await loadCartridgeFromManifest(join(REPO_ROOT, 'cartridges/oddjobz'));
    for (const ct of loaded.cellTypes!) {
      expect(ct.manifest.name).not.toMatch(/\.v\d+$/);
      expect(ct.manifest.triple.segment4).toBe('');
    }
  });

  test('attachment.v1 TS file still exists (transition window — D12 retirement is incremental)', async () => {
    // This is a deliberate annotation: cartridges/oddjobz/brain/src/cell-types/attachment.ts
    // (the v1 cell type) was retired from the manifest per D12, but the
    // TS file still ships because state-machines may reference its payload
    // type until they migrate. Track this as follow-up cleanup.
    const v1Path = join(REPO_ROOT, 'cartridges/oddjobz/brain/src/cell-types/attachment.ts');
    const v1 = await readFile(v1Path, 'utf-8');
    expect(v1).toContain('defineCellType');
    // When this annotation reads "attachment.v1 TS file gone" instead of
    // "still exists," D12 cleanup is done — remove this test.
  });
});

// ─────────────────────────────────────────────────────────────────────
// Q11-C: drift-detection for runtime/legacy-ingest hardcoded literals
// ─────────────────────────────────────────────────────────────────────

describe('Q11-C — runtime/legacy-ingest hardcoded typeHash literals are pinned', () => {
  test('the four legacy literals compute to expected fixed hex (no accidental string edits)', async () => {
    // The literals at runtime/legacy-ingest/src/cell-writer/brain-rpc.ts:1638-1641.
    // These produce the OLD-format (v2 colon-triple) hashes used for legacy
    // cells minted before the manifest-driven path landed.  They are
    // intentionally DIFFERENT from the new manifest-driven hashes (wire
    // break per D8); this test exists to catch unintended literal edits.
    function legacyHash(s: string): string {
      return createHash('sha256').update(s, 'utf-8').digest('hex');
    }

    // Pinned 2026-05-25 — surface any change to the legacy literals.
    expect(legacyHash('oddjobz.site:locate:inst.location.work-site.v2')).toBe(
      '403aeb290b9b963209dfd0a3b48b99b2959604d2e998b1dc8002dc8c70724c8f',
    );
    expect(legacyHash('oddjobz.customer:identify:inst.identity.customer-record.v2')).toBe(
      'eef2434c3649e481f52764f936e249ea6f01d5060386cfdddd0fb82a05124682',
    );
    expect(legacyHash('oddjobz.job:worktrack:inst.work.job-record.v2')).toBe(
      'c0555cda42078d1e5a828baf2f1e94b0488de2e5311083b3ed4ab0d7aedb7389',
    );
    expect(legacyHash('oddjobz.attachment:capture:inst.evidence.site-artifact.v2')).toBe(
      'fb1a23a8172cd686deaa6acdee01a9726ea29dfc3c075b7ebe9f661bddb71b37',
    );
  });

  test('legacy hashes are DISTINCT from manifest-driven hashes (wire-break per D8)', async () => {
    function legacyHash(s: string): string {
      return createHash('sha256').update(s, 'utf-8').digest('hex');
    }
    const loaded = await loadCartridgeFromManifest(join(REPO_ROOT, 'cartridges/oddjobz'));
    const manifestSite = loaded.cellTypes!.find((c) => c.manifest.name === 'oddjobz.site')!;

    // The legacy hash MUST differ from the manifest hash — they encode
    // different identities (legacy = `whatPath:howSlug:instPath.v2`,
    // manifest = `s1:s2:s3:s4` with s4='').  If these ever match, either
    // (a) the wire break leaked back into the legacy literal, or
    // (b) buildTypeHash's flat algorithm changed shape in a way that
    //     accidentally aligned with the legacy format.
    expect(manifestSite.typeHashHex).not.toBe(
      legacyHash('oddjobz.site:locate:inst.location.work-site.v2'),
    );
  });
});

```
