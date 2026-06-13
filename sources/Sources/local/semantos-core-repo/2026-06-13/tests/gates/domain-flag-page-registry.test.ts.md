---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/domain-flag-page-registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.569525+00:00
---

# tests/gates/domain-flag-page-registry.test.ts

```ts
/**
 * R-3 Gate: enforced cross-extension domain-flag page registry.
 *
 * Per audit docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md
 * §4a R-3 + B-1: the Tier-3 (operator-sovereignty, >= 0x00010000)
 * domain-flag space is partitioned into canonical pages. A flag F
 * belongs to page P iff (F & 0xFFFFFF00) === P.
 *
 *   0x00010000  LOOM_SHELL        — brain identity / workbench flags
 *   0x00010100  ODDJOBZ           — cap.oddjobz.* capability page
 *   0x00010200  BSV_ANCHOR        — cap.bsv-anchor.* capability page
 *   0x00010400  TESSERA           — cap.tessera.* (lands with tessera)
 *   0x0001FE00  SUBSTRATE_SCHEMA  — RM-004 SemantosDomainFlags schema IDs
 *   >= 0x00020000                 — per-tenant escape hatch (non-canonical)
 *
 * This gate makes the page map machine-enforced (was prose-only, the
 * D-3 defect) and proves the B-1 collision is resolved: the historical
 * 0x000101xx schema-identifier values are gone from SemantosDomainFlags
 * and no longer alias the oddjobz capability page.
 *
 * Fails if ANY domain flag collides across modules, or sits outside its
 * registered page, or if SemantosDomainFlags drifts off the
 * SUBSTRATE_SCHEMA page.
 */

import { describe, test, expect } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';

import {
  ClientDomainFlags,
  SemantosDomainFlags,
} from '../../core/plexus-contracts/src/domain-flags';
import { ODDJOBZ_CAPABILITIES } from '../../cartridges/oddjobz/brain/src/capabilities';
import { BSV_ANCHOR_CAPABILITIES } from '../../cartridges/bsv-anchor-bundle/brain/src/capabilities';

const ROOT = join(import.meta.dir, '../..');

const LOOM_SHELL_PAGE = 0x00010000;
const ODDJOBZ_PAGE = 0x00010100;
const BSV_ANCHOR_PAGE = 0x00010200;
const SUBSTRATE_SCHEMA_PAGE = 0x0001fe00;
const ESCAPE_HATCH_MIN = 0x00020000;

const pageOf = (flag: number) => flag & 0xffffff00;

// Capability arrays use different field-name conventions: oddjobz =
// `domainFlag` (camelCase), bsv-anchor/tessera = `domain_flag` (snake).
// Normalize so the registry gate is convention-agnostic.
const capFlag = (c: { domain_flag?: number; domainFlag?: number }): number =>
  (c.domain_flag ?? c.domainFlag) as number;

describe('R-3 — domain-flag page registry (enforced)', () => {
  test('constants.json extensionPages declares the canonical page bases', () => {
    const constants = JSON.parse(
      readFileSync(join(ROOT, 'core/constants/constants.json'), 'utf-8'),
    );
    const ep = constants.extensionPages as Record<string, string>;
    expect(parseInt(ep.LOOM_SHELL_PAGE, 16)).toBe(LOOM_SHELL_PAGE);
    expect(parseInt(ep.ODDJOBZ_PAGE, 16)).toBe(ODDJOBZ_PAGE);
    expect(parseInt(ep.BSV_ANCHOR_PAGE, 16)).toBe(BSV_ANCHOR_PAGE);
    expect(parseInt(ep.TESSERA_PAGE, 16)).toBe(0x00010400);
    // SUBSTRATE_SCHEMA is not an extension page; it lives only as the
    // SemantosDomainFlags reservation, asserted below.
  });

  test('B-1 RESOLVED — SemantosDomainFlags relocated off the oddjobz page', () => {
    const vals = Object.values(SemantosDomainFlags);
    for (const v of vals) {
      // Must be on the SUBSTRATE_SCHEMA page, NOT 0x000101xx (oddjobz).
      expect(pageOf(v)).toBe(SUBSTRATE_SCHEMA_PAGE);
      expect(pageOf(v)).not.toBe(ODDJOBZ_PAGE);
    }
    // The exact historical collision triplet is gone.
    expect(vals).not.toContain(0x00010101);
    expect(vals).not.toContain(0x00010102);
    expect(vals).not.toContain(0x00010103);
  });

  test('ClientDomainFlags all live on the LOOM_SHELL page', () => {
    for (const v of Object.values(ClientDomainFlags)) {
      expect(pageOf(v)).toBe(LOOM_SHELL_PAGE);
    }
  });

  test('oddjobz capabilities all live on the ODDJOBZ page', () => {
    for (const c of ODDJOBZ_CAPABILITIES) {
      expect(pageOf(capFlag(c))).toBe(ODDJOBZ_PAGE);
    }
  });

  test('bsv-anchor capabilities all live on the BSV_ANCHOR page', () => {
    for (const c of BSV_ANCHOR_CAPABILITIES) {
      expect(pageOf(capFlag(c))).toBe(BSV_ANCHOR_PAGE);
    }
  });

  test('GLOBAL UNIQUENESS — no domain flag collides across modules', () => {
    const all: { flag: number; src: string }[] = [
      ...Object.entries(ClientDomainFlags).map(([k, v]) => ({
        flag: v as number,
        src: `ClientDomainFlags.${k}`,
      })),
      ...Object.entries(SemantosDomainFlags).map(([k, v]) => ({
        flag: v as number,
        src: `SemantosDomainFlags.${k}`,
      })),
      ...ODDJOBZ_CAPABILITIES.map((c) => ({
        flag: capFlag(c),
        src: `oddjobz.${c.name}`,
      })),
      ...BSV_ANCHOR_CAPABILITIES.map((c) => ({
        flag: capFlag(c),
        src: `bsv-anchor.${c.name}`,
      })),
    ];
    const seen = new Map<number, string>();
    const collisions: string[] = [];
    for (const { flag, src } of all) {
      const prior = seen.get(flag);
      if (prior !== undefined) {
        collisions.push(`0x${flag.toString(16)}: ${prior} ⟷ ${src}`);
      } else {
        seen.set(flag, src);
      }
    }
    if (collisions.length > 0) {
      console.error('Domain-flag collisions:\n' + collisions.join('\n'));
    }
    expect(collisions).toEqual([]);
  });

  test('every canonical flag sits in a registered page (or escape hatch)', () => {
    const registered = new Set([
      LOOM_SHELL_PAGE,
      ODDJOBZ_PAGE,
      BSV_ANCHOR_PAGE,
      0x00010400, // TESSERA
      SUBSTRATE_SCHEMA_PAGE,
    ]);
    const everyFlag = [
      ...Object.values(ClientDomainFlags),
      ...Object.values(SemantosDomainFlags),
      ...ODDJOBZ_CAPABILITIES.map((c) => capFlag(c)),
      ...BSV_ANCHOR_CAPABILITIES.map((c) => capFlag(c)),
    ] as number[];
    for (const f of everyFlag) {
      const ok = registered.has(pageOf(f)) || f >= ESCAPE_HATCH_MIN;
      expect(ok).toBe(true);
    }
  });
});

```
