---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/lib/__tests__/legal-cards.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.386030+00:00
---

# scripts/lib/__tests__/legal-cards.test.ts

```ts
/**
 * legal-cards.test.ts — unit tests for the renderer and patch-layer
 * primitives in legal-cards.ts.
 *
 * Coverage map:
 *   §rendering    — one test per JuralCategory (7 categories)
 *   §determinism  — same patch, same bytes, across 100 re-renders
 *   §companions   — Obligation → Permission + Transfer materialisation
 *   §conditions   — terminal Declaration gate blocks then unblocks
 *   §bundles      — exportBundle / diffPatches / mergePatches round-trip
 *   §roundtrip    — LegalPatch ↔ ObjectPatchCompat preserves information
 *
 * Run with:   bun test scripts/lib/__tests__/legal-cards.test.ts
 */

import { describe, test, expect } from 'bun:test';
import {
  renderCard,
  materialiseCompanions,
  evaluateCondition,
  exportBundle,
  diffPatches,
  mergePatches,
  toObjectPatch,
  fromObjectPatch,
  type LegalPatch,
  type ChainState,
} from '../legal-cards';
import type { SIRNode, JuralCategory, GovernanceContext } from '../../../packages/semantos-sir/src/types';

// ── Fixture helpers ─────────────────────────────────────────────────────

const T0 = Date.parse('2026-04-18T12:00:00Z');

const gov = (overrides: Partial<GovernanceContext> = {}): GovernanceContext => ({
  trustClass: 'interpretive',
  proofRequirement: 'attestation',
  executionAuthority: 'hat_scoped',
  linearity: 'LINEAR',
  ...overrides,
});

const prov = (source: 'manual' | 'inferred' = 'manual', confidence?: number) => ({
  source,
  expressedAt: '2026-04-18T12:00:00Z',
  trustAtExpression: 'interpretive' as const,
  ...(confidence != null ? { confidence } : {}),
});

const hatRef = (id: string) => ({ kind: 'hat' as const, id }) as unknown as SIRNode['identity']['subject'];

const baseNode = (category: JuralCategory, over: Partial<SIRNode> = {}): SIRNode => ({
  id: '$s0',
  category,
  taxonomy: {
    what: 'test.what',
    how: 'test.how',
    why: 'test.why',
    where: 'AU.NSW.sydney.2099',
  },
  identity: { subject: hatRef('hat-owner') },
  governance: gov(),
  action: 'test_action',
  constraint: { kind: 'identity', ref: hatRef('hat-owner') as any },
  provenance: prov(),
  ...over,
});

const p = (category: JuralCategory, over: Partial<LegalPatch> = {}): LegalPatch => ({
  id: `patch-${category}-1`,
  kind: 'extraction',
  hatId: 'hat-owner',
  timestamp: T0,
  sir: baseNode(category),
  delta: {},
  ...over,
});

// ── §rendering: one test per category ───────────────────────────────────

describe('renderCard — one per JuralCategory', () => {
  test('declaration renders with enables/forecloses from delta', () => {
    const patch = p('declaration', {
      sir: baseNode('declaration', {
        action: 'declare_listing_intent',
        target: { objectId: '42-example-st' },
      }),
      delta: {
        statement: 'property going to market',
        enables: ['REA appointment'],
        forecloses: ['private-sale without disclosure'],
      },
    });
    const card = renderCard(patch);
    expect(card).toContain('DECLARATION · declare_listing_intent');
    expect(card).toContain('property going to market');
    expect(card).toContain('42-example-st');
    expect(card).toContain('REA appointment');
    expect(card).toContain('private-sale without disclosure');
  });

  test('power renders delegation restrictions as forecloses', () => {
    const patch = p('power', {
      sir: baseNode('power', {
        action: 'grant_agency',
        governance: gov({
          trustClass: 'authoritative',
          proofRequirement: 'formal',
          domainBinding: {
            flag: 0x0e57a7e,
            domainType: 'estate',
            delegation: {
              delegator: hatRef('hat-owner') as any,
              delegate: hatRef('hat-rea') as any,
              delegatedPowers: ['list the property', 'accept offers at reserve'],
              restrictions: ['cannot accept below $1.2M reserve', 'cannot sign transfer'],
              canSubDelegate: true,
              expiry: '2026-07-18T00:00:00Z',
            },
          },
        }),
      }),
    });
    const card = renderCard(patch);
    expect(card).toContain('POWER · grant_agency');
    expect(card).toContain('hat-rea may list the property');
    expect(card).toContain('hat-rea may accept offers at reserve');
    expect(card).toContain('hat-rea cannot accept below $1.2M reserve');
    expect(card).toContain('hat-rea cannot sign transfer');
    expect(card).toContain('authoritative → requires FORMAL attestation');
  });

  test('obligation renders deadline, amount, and subcontract foreclose', () => {
    const patch = p('obligation', {
      hatId: 'hat-painter',
      sir: baseNode('obligation', {
        identity: { subject: hatRef('hat-painter') },
        action: 'undertake_works',
        fulfillment: { fulfilledBy: 'hat-painter.done', deadline: '2026-05-15T17:00:00Z' },
      }),
      delta: { description: 'repaint interior, low-VOC', amount: 4200, currency: 'AUD' },
    });
    const card = renderCard(patch);
    expect(card).toContain('OBLIGATION · undertake_works');
    expect(card).toContain('repaint interior, low-VOC');
    expect(card).toContain('by 2026-05-15');
    expect(card).toContain('$4,200');
    expect(card).toContain('cannot subcontract without owner consent');
  });

  test('permission shows companionOf and scope/hours', () => {
    const patch = p('permission', {
      id: 'patch-obl-1--perm',
      kind: 'companion',
      companionOf: 'patch-obl-1',
      hatId: 'hat-painter',
      sir: baseNode('permission', {
        identity: { subject: hatRef('hat-painter') },
        action: 'enter_premises',
        target: { objectId: '42-example-st' },
      }),
      delta: { scope: '42-example-st', hours: 'weekdays 08:00–17:00' },
    });
    const card = renderCard(patch);
    expect(card).toContain('PERMISSION · enter_premises (companion to patch-obl-1)');
    expect(card).toContain('weekdays 08:00–17:00');
    expect(card).toContain('No entry outside specified hours');
  });

  test('prohibition lists primary and additional forecloses', () => {
    const patch = p('prohibition', {
      hatId: 'hat-ai',
      sir: baseNode('prohibition', {
        action: 'prohibit_scope_change',
        identity: { subject: hatRef('hat-owner') },
      }),
      delta: {
        subject: 'hat-owner',
        prohibitedAct: 'altering scope without REA consent',
        additionalForecloses: ['cannot substitute contractors', 'cannot terminate mid-works'],
      },
    });
    const card = renderCard(patch);
    expect(card).toContain('PROHIBITION · prohibit_scope_change');
    expect(card).toContain('hat-owner is prohibited from: altering scope without REA consent');
    expect(card).toContain('cannot substitute contractors');
    expect(card).toContain('cannot terminate mid-works');
  });

  test('condition lists requires and blocking message', () => {
    const patch = p('condition', {
      hatId: 'hat-rea',
      sir: baseNode('condition', { action: 'require_pre_listing_readiness' }),
      delta: {
        description: 'Auction listing authorisation',
        requires: ['works-complete', 'compliance-cert', 'photography-cert'],
      },
    });
    const card = renderCard(patch);
    expect(card).toContain('CONDITION · require_pre_listing_readiness');
    expect(card).toContain('works-complete; compliance-cert; photography-cert');
    expect(card).toContain('blocked while any prerequisite is unmet');
  });

  test('transfer renders from → to with amount and conditional', () => {
    const patch = p('transfer', {
      hatId: 'hat-owner',
      sir: baseNode('transfer', {
        action: 'pay_contractor',
        identity: { subject: hatRef('hat-owner') },
        transferTo: { subject: hatRef('hat-painter') },
      }),
      delta: {
        amount: 4200,
        currency: 'AUD',
        conditionalOn: 'patch-obl-1.fulfilled',
      },
    });
    const card = renderCard(patch);
    expect(card).toContain('TRANSFER · pay_contractor');
    expect(card).toContain('hat-owner transfers $4,200 to hat-painter');
    expect(card).toContain('conditional on patch-obl-1.fulfilled');
  });
});

// ── §determinism ─────────────────────────────────────────────────────────

describe('renderCard determinism', () => {
  test('same patch → same bytes across 100 renders', () => {
    const patch = p('obligation', {
      sir: baseNode('obligation', {
        action: 'undertake_works',
        fulfillment: { fulfilledBy: 'done', deadline: '2026-05-15T00:00:00Z' },
      }),
      delta: { description: 'test', amount: 1000, currency: 'AUD' },
    });
    const first = renderCard(patch);
    for (let i = 0; i < 100; i++) {
      expect(renderCard(patch)).toBe(first);
    }
  });

  test('all seven categories are deterministic', () => {
    const cats: JuralCategory[] = [
      'declaration', 'obligation', 'permission', 'prohibition',
      'power', 'condition', 'transfer',
    ];
    for (const c of cats) {
      const patch = p(c);
      expect(renderCard(patch)).toBe(renderCard(patch));
    }
  });

  test('taxonomy dispatch fails fast for unknown category', () => {
    const patch = {
      ...p('declaration'),
      sir: { ...baseNode('declaration'), category: 'unknown' as JuralCategory },
    };
    expect(() => renderCard(patch as LegalPatch)).toThrow(/no template for category/);
  });
});

// ── §companions ──────────────────────────────────────────────────────────

describe('materialiseCompanions', () => {
  test('obligation produces exactly 2 companions with expected shapes', () => {
    const obligation = p('obligation', {
      id: 'patch-O1',
      hatId: 'hat-painter',
      sir: baseNode('obligation', {
        id: '$sO1',
        action: 'undertake_works',
        identity: { subject: hatRef('hat-painter') },
        target: { objectId: '42-example-st' },
        fulfillment: { fulfilledBy: 'done', deadline: '2026-05-15T00:00:00Z' },
      }),
      delta: { description: 'paint', amount: 4200, currency: 'AUD' },
    });
    const companions = materialiseCompanions(obligation);
    expect(companions).toHaveLength(2);

    const [perm, xfer] = companions;
    expect(perm.sir.category).toBe('permission');
    expect(perm.kind).toBe('companion');
    expect(perm.companionOf).toBe('patch-O1');
    expect(perm.timestamp).toBe(obligation.timestamp + 1);

    expect(xfer.sir.category).toBe('transfer');
    expect(xfer.kind).toBe('companion');
    expect(xfer.companionOf).toBe('patch-O1');
    expect(xfer.timestamp).toBe(obligation.timestamp + 2);
    expect((xfer.delta as any).amount).toBe(4200);
    expect((xfer.delta as any).conditionalOn).toBe('patch-O1.fulfilled');
  });

  test('non-obligation returns empty companion set', () => {
    for (const cat of ['declaration', 'permission', 'transfer', 'power', 'condition', 'prohibition'] as const) {
      expect(materialiseCompanions(p(cat))).toEqual([]);
    }
  });

  test('companions render without error through the full renderer', () => {
    const obligation = p('obligation', {
      sir: baseNode('obligation', {
        action: 'paint',
        fulfillment: { fulfilledBy: 'done', deadline: '2026-05-15T00:00:00Z' },
        target: { objectId: '42-example-st' },
      }),
      delta: { amount: 4200 },
    });
    const companions = materialiseCompanions(obligation);
    for (const c of companions) {
      expect(() => renderCard(c)).not.toThrow();
    }
  });
});

// ── §conditions ──────────────────────────────────────────────────────────

describe('evaluateCondition', () => {
  const conditionPatch = p('condition', {
    delta: {
      requires: ['works.complete', 'compliance.cert', 'photography.cert'],
    },
  });

  test('empty state → all prerequisites unmet', () => {
    const state: ChainState = { satisfied: new Set() };
    const r = evaluateCondition(conditionPatch, state);
    expect(r.satisfied).toBe(false);
    expect(r.unmet).toEqual(['works.complete', 'compliance.cert', 'photography.cert']);
  });

  test('partial state → only missing prereqs are unmet', () => {
    const state: ChainState = { satisfied: new Set(['works.complete']) };
    const r = evaluateCondition(conditionPatch, state);
    expect(r.satisfied).toBe(false);
    expect(r.unmet).toEqual(['compliance.cert', 'photography.cert']);
  });

  test('full state → satisfied, no unmet', () => {
    const state: ChainState = {
      satisfied: new Set(['works.complete', 'compliance.cert', 'photography.cert']),
    };
    const r = evaluateCondition(conditionPatch, state);
    expect(r.satisfied).toBe(true);
    expect(r.unmet).toEqual([]);
  });

  test('condition with no requires is trivially satisfied', () => {
    const pc = p('condition', { delta: {} });
    expect(evaluateCondition(pc, { satisfied: new Set() }).satisfied).toBe(true);
  });
});

// ── §bundles ─────────────────────────────────────────────────────────────

describe('bundle primitives', () => {
  test('exportBundle deep-copies patches (mutating bundle does not touch source)', () => {
    const src = [p('declaration', { id: 'patch-a' })];
    const b = exportBundle('doc-1', src, 'hat-owner');
    (b.patches[0].delta as Record<string, unknown>).intruder = true;
    expect((src[0].delta as Record<string, unknown>).intruder).toBeUndefined();
  });

  test('diffPatches returns only patches not present in base (by id)', () => {
    const a = p('declaration', { id: 'patch-1' });
    const b = p('obligation', { id: 'patch-2' });
    const c = p('permission', { id: 'patch-3' });
    const base = [a];
    const incoming = [a, b, c];
    const diff = diffPatches(base, incoming);
    expect(diff.map((p) => p.id)).toEqual(['patch-2', 'patch-3']);
  });

  test('mergePatches is idempotent (same selected applied twice has no extra effect)', () => {
    const base = [p('declaration', { id: 'patch-1', timestamp: T0 })];
    const selected = [p('obligation', { id: 'patch-2', timestamp: T0 + 100 })];
    const first = mergePatches(base, selected);
    const second = mergePatches(first, selected);
    expect(first.length).toBe(2);
    expect(second.length).toBe(2);
    expect(second.map((p) => p.id)).toEqual(['patch-1', 'patch-2']);
  });

  test('mergePatches sorts by timestamp regardless of input order', () => {
    const base = [p('declaration', { id: 'old', timestamp: T0 })];
    const selected = [
      p('obligation', { id: 'newest', timestamp: T0 + 3000 }),
      p('permission', { id: 'middle', timestamp: T0 + 1000 }),
    ];
    const merged = mergePatches(base, selected);
    expect(merged.map((p) => p.id)).toEqual(['old', 'middle', 'newest']);
  });

  test('mergePatches preserves authorship at patch granularity', () => {
    const base = [p('declaration', { id: 'a', hatId: 'hat-owner', timestamp: T0 })];
    const selected = [
      p('obligation', { id: 'b', hatId: 'hat-painter', timestamp: T0 + 1 }),
      p('transfer', { id: 'c', hatId: 'hat-owner', timestamp: T0 + 2 }),
    ];
    const merged = mergePatches(base, selected);
    expect(merged.map((p) => p.hatId)).toEqual(['hat-owner', 'hat-painter', 'hat-owner']);
  });
});

// ── §roundtrip: LegalPatch ↔ ObjectPatchCompat ──────────────────────────

describe('LegalPatch ↔ ObjectPatchCompat round-trip', () => {
  test('extraction patch round-trips with identical sir and delta', () => {
    const original = p('obligation', {
      id: 'patch-O1',
      hatId: 'hat-painter',
      sir: baseNode('obligation', { action: 'paint' }),
      delta: { description: 'paint', amount: 4200 },
    });
    const op = toObjectPatch(original);
    const back = fromObjectPatch(op);
    expect(back.id).toBe(original.id);
    expect(back.hatId).toBe(original.hatId);
    expect(back.kind).toBe(original.kind);
    expect(back.timestamp).toBe(original.timestamp);
    expect(back.sir).toEqual(original.sir);
    expect(back.delta).toEqual(original.delta);
  });

  test('companion patch preserves companionOf across round-trip', () => {
    const c: LegalPatch = {
      id: 'patch-O1--perm',
      kind: 'companion',
      hatId: 'hat-painter',
      timestamp: T0 + 1,
      sir: baseNode('permission'),
      delta: { action: 'grant_permission' },
      companionOf: 'patch-O1',
    };
    const back = fromObjectPatch(toObjectPatch(c));
    expect(back.companionOf).toBe('patch-O1');
    expect(back.kind).toBe('companion');
  });

  test('rejection patch preserves reason and curatorSignature', () => {
    const r: LegalPatch = {
      id: 'patch-X1--rejection',
      kind: 'rejection',
      hatId: 'hat-owner',
      timestamp: T0 + 10,
      sir: baseNode('prohibition'),
      delta: {},
      targetPatchId: 'patch-X1',
      reason: 'over-delegation',
      curatorSignature: 'sig_abc',
    };
    const back = fromObjectPatch(toObjectPatch(r));
    expect(back.kind).toBe('rejection');
    expect(back.targetPatchId).toBe('patch-X1');
    expect(back.reason).toBe('over-delegation');
    expect(back.curatorSignature).toBe('sig_abc');
  });

  test('kind mapping is stable: every LegalPatchKind has a valid ObjectPatch kind', () => {
    const kinds: LegalPatch['kind'][] = [
      'extraction',
      'companion',
      'manual_override',
      'rejection',
      'state_transition',
    ];
    for (const k of kinds) {
      const patch: LegalPatch = {
        id: `patch-${k}`,
        kind: k,
        hatId: 'hat-x',
        timestamp: T0,
        sir: baseNode('declaration'),
        delta: {},
      };
      const op = toObjectPatch(patch);
      expect(typeof op.kind).toBe('string');
      expect(op.kind.length).toBeGreaterThan(0);
    }
  });

  test('facetId field receives hatId (transport compatibility)', () => {
    const patch = p('declaration', { hatId: 'hat-owner' });
    const op = toObjectPatch(patch);
    expect(op.facetId).toBe('hat-owner');
  });
});

```
