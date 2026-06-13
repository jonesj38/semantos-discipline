---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/sir-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.354404+00:00
---

# runtime/intent/src/__tests__/sir-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { buildSIR } from '../sir-builder';
import type { Intent, HatContext, IntentId, IntentSource } from '../types';

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-1',
  hatId: 'hat-1',
  certId: 'cert-1',
  capabilities: [1, 2, 3],
  extensionId: 'ext-demo',
  domainFlag: 7,
  maxTrustClass: 'interpretive',
  ...over,
});

const mkIntent = (over: Partial<Intent> = {}): Intent => ({
  id: '01HQ-test' as IntentId,
  summary: 'publish core.Document',
  category: { lexicon: 'jural', category: 'declaration' },
  taxonomy: { what: 'core.Document', how: 'lifecycle.publish', why: 'audit' },
  action: 'transition',
  constraints: [{ kind: 'capability', required: 5, name: 'SIGNING' }],
  confidence: 0.95,
  source: 'shell',
  ...over,
});

describe('buildSIR', () => {
  test('produces a single-node SIRProgram with matching primaryNodeId', () => {
    const program = buildSIR(mkIntent(), mkHat());
    expect(program.nodes).toHaveLength(1);
    expect(program.primaryNodeId).toBe(program.nodes[0]!.id);
  });

  test('carries action, category, taxonomy, target from intent', () => {
    const intent = mkIntent({
      action: 'declare',
      category: { lexicon: 'jural', category: 'declaration' },
      target: { objectId: 'obj-42', typePath: 'core.Document' },
    });
    const program = buildSIR(intent, mkHat());
    const node = program.nodes[0]!;
    expect(node.action).toBe('declare');
    expect(node.category).toEqual({ lexicon: 'jural', category: 'declaration' });
    expect(node.target).toEqual({ objectId: 'obj-42', typePath: 'core.Document' });
  });

  test('threads hat identity into SIRIdentity', () => {
    const program = buildSIR(
      mkIntent(),
      mkHat({ hatId: 'hat-specific', hatId: 'hat-specific', certId: 'cert-abc' }),
    );
    const identity = program.nodes[0]!.identity;
    expect(identity.subject).toEqual({ type: 'role', name: 'hat-specific' });
    expect(identity.hatId).toBe('hat-specific');
    expect(identity.certId).toBe('cert-abc');
  });

  test('binds domainFlag from hat into governance.domainBinding', () => {
    const program = buildSIR(mkIntent(), mkHat({ domainFlag: 42 }));
    expect(program.programGovernance.domainBinding?.flag).toBe(42);
  });

  describe('trustClass capping', () => {
    test('high-confidence NL intent gets interpretive if hat allows', () => {
      const program = buildSIR(
        mkIntent({ source: 'nl', confidence: 0.95 }),
        mkHat({ maxTrustClass: 'interpretive' }),
      );
      expect(program.programGovernance.trustClass).toBe('interpretive');
    });

    test('high-confidence NL intent capped to cosmetic by unpublished hat', () => {
      const program = buildSIR(
        mkIntent({ source: 'nl', confidence: 0.95 }),
        mkHat({ maxTrustClass: 'cosmetic' }),
      );
      expect(program.programGovernance.trustClass).toBe('cosmetic');
    });

    test('mid-confidence NL intent gets cosmetic', () => {
      const program = buildSIR(
        mkIntent({ source: 'nl', confidence: 0.75 }),
        mkHat(),
      );
      expect(program.programGovernance.trustClass).toBe('cosmetic');
    });

    test('deterministic sources (shell) claim interpretive by default', () => {
      const program = buildSIR(
        mkIntent({ source: 'shell', confidence: 1 }),
        mkHat(),
      );
      expect(program.programGovernance.trustClass).toBe('interpretive');
    });
  });

  describe('constraint consolidation', () => {
    test('empty constraints → trivial always-true composite', () => {
      const program = buildSIR(mkIntent({ constraints: [] }), mkHat());
      expect(program.nodes[0]!.constraint).toEqual({
        kind: 'composite',
        op: 'and',
        children: [],
      });
    });

    test('single constraint passes through unchanged', () => {
      const c = { kind: 'capability', required: 5, name: 'SIGNING' } as const;
      const program = buildSIR(mkIntent({ constraints: [c] }), mkHat());
      expect(program.nodes[0]!.constraint).toEqual(c);
    });

    test('multiple constraints AND-composited', () => {
      const c1 = { kind: 'capability', required: 5, name: 'SIGNING' } as const;
      const c2 = { kind: 'domain', flag: 7 } as const;
      const program = buildSIR(mkIntent({ constraints: [c1, c2] }), mkHat());
      expect(program.nodes[0]!.constraint).toEqual({
        kind: 'composite',
        op: 'and',
        children: [c1, c2],
      });
    });
  });

  describe('provenance source mapping', () => {
    const cases: Array<[IntentSource, string]> = [
      ['nl', 'manual'],
      ['voice', 'voice'],
      ['shell', 'api'],
      ['host-exec', 'api'],
      ['network', 'monitor'],
      ['governance', 'monitor'],
      ['scheduler', 'scheduler'],
      ['ui', 'manual'],
    ];
    for (const [source, expected] of cases) {
      test(`source=${source} → provenance.source=${expected}`, () => {
        const program = buildSIR(mkIntent({ source }), mkHat());
        expect(program.nodes[0]!.provenance.source).toBe(expected);
      });
    }
  });
});

```
