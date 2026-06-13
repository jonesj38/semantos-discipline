---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/__tests__/relation-pass.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.359346+00:00
---

# runtime/intent/src/reducer/__tests__/relation-pass.test.ts

```ts
/**
 * RM-030 relation-pass tests.
 *
 * Acceptance: NL strings produce a relation constraint with the correct
 * `RelationKind`; pass ordering pinned (after rhetoric, before
 * analogical_prefilter).
 */

import { describe, expect, test } from 'bun:test';
import type { Intent } from '@semantos/semantos-sir';
import { relationPass } from '../relation-pass';
import type { GrammarSpec, PassContext, ReducerInputState } from '../types';

const GRAMMAR: GrammarSpec = {
  extensionId: 'scg-test',
  domainFlag: 7,
  lexicon: {
    name: 'jural',
    categories: ['declaration', 'obligation', 'permission'],
  },
  defaultTaxonomyWhat: 'scg.conversation',
  objectTypes: [{ name: 'scg.cell', description: '' }],
  actions: [
    { name: 'say', category: 'declaration', authoredBy: ['actor'], description: '' },
  ],
  trustClass: 'interpretive',
};

function inputState(over: Partial<ReducerInputState> = {}): ReducerInputState {
  return {
    conversationSummary: '',
    scopeDescription: '',
    taggedFacts: [],
    ...over,
  };
}

function ctx(state: ReducerInputState): PassContext {
  return { state, grammar: GRAMMAR };
}

async function run(text: string) {
  return relationPass({}, ctx(inputState({ conversationSummary: text })));
}

describe('RM-030 relation-pass — NL → SIRConstraint{ kind: relation }', () => {
  test('R1 "reply to that" → REPLIES_TO', async () => {
    const r = await run('reply to that');
    expect(r.pass).toBe('relation');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs).toHaveLength(1);
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'REPLIES_TO' });
    expect(r.confidence).toBeGreaterThan(0.8);
  });

  test('R2 "+1 on the previous" → SUPPORTS', async () => {
    const r = await run('+1 on the previous');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'SUPPORTS' });
  });

  test('R3 "this contradicts what Alice said" → DISPUTES', async () => {
    const r = await run('this contradicts what Alice said');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'DISPUTES' });
  });

  test('R4 "see also: previous proposal" → CITES', async () => {
    const r = await run('see also: previous proposal');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'CITES' });
  });

  test('R5 "that fulfills my request" → FULFILLS', async () => {
    const r = await run('that fulfills my request');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'FULFILLS' });
  });

  test('R6 "I approve this" → APPROVES', async () => {
    const r = await run('I approve this');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'APPROVES' });
  });

  test('R7 plain text with no relation phrase → vacuously satisfied', async () => {
    const r = await run('the weather is nice today');
    expect(r.contribution.constraints).toBeUndefined();
    expect(r.confidence).toBe(1);
    expect(r.skipInComposite).toBe(true);
  });

  test('R8 empty text → skipInComposite (no signal)', async () => {
    const r = await relationPass({}, ctx(inputState()));
    expect(r.contribution.constraints).toBeUndefined();
    expect(r.skipInComposite).toBe(true);
  });

  test('R9 multiple matches: highest-confidence wins', async () => {
    // "+1" (0.95) beats "agree" (0.80)
    const r = await run('+1, I agree with the proposal');
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'SUPPORTS' });
    expect(r.confidence).toBe(0.95);
    expect(r.flags.some((f) => f.includes('multiple matches'))).toBe(true);
  });

  test('R9a RM-092: losing candidates surface in alternatives, descending, below winner', async () => {
    // "in reply to" (REPLIES_TO 0.85) + "+1" (SUPPORTS 0.95) + "agree" (SUPPORTS 0.80)
    // Winner: +1 / SUPPORTS @ 0.95. Alternatives: REPLIES_TO 0.85, SUPPORTS 0.80.
    const r = await run('+1, in reply to that, I agree');
    expect(r.alternatives).toBeDefined();
    const alts = r.alternatives!;
    expect(alts.length).toBeGreaterThanOrEqual(2);

    // Ordered by descending confidence.
    for (let i = 0; i < alts.length - 1; i++) {
      expect(alts[i].confidence).toBeGreaterThanOrEqual(alts[i + 1].confidence);
    }

    // All strictly below the winner's confidence (0.95).
    for (const a of alts) {
      expect(a.confidence).toBeLessThan(0.95);
    }

    // Each alternative names the losing kind in its reason.
    for (const a of alts) {
      expect(a.reason).toMatch(/SUPPORTS.*0\.95.*ranked higher/);
    }
  });

  test('R9b RM-092: single match → no alternatives field', async () => {
    const r = await run('please fix the dripping tap');
    expect(r.alternatives).toBeUndefined();
  });

  test('R10 scans taggedFacts too, not just conversationSummary', async () => {
    const r = await relationPass(
      {},
      ctx(
        inputState({
          conversationSummary: 'work order',
          taggedFacts: [
            {
              lexicon: 'jural',
              category: 'declaration',
              confidence: 0.8,
              fact: 'I attest the work was done',
              source: 'llm',
            },
          ],
        }),
      ),
    );
    const cs = (r.contribution.constraints ?? []) as Intent['constraints'];
    expect(cs[0]).toEqual({ kind: 'relation', relationKind: 'ATTESTS' });
  });
});

describe('RM-030 pass-ordering snapshot', () => {
  test('relation lives between rhetoric and analogical_prefilter', async () => {
    // Lock the position via the exported PASSES list (re-export via
    // reducer/index would be cleaner but PASSES is internal; we
    // approximate by running reduceToIntent and checking the result
    // ordering).
    const { reduceToIntent } = await import('../index');
    const result = await reduceToIntent(
      inputState({ conversationSummary: 'reply to that' }),
      GRAMMAR,
    );
    const order = result.passResults.map((p) => p.pass);
    const rhetoricIdx = order.indexOf('rhetoric');
    const relationIdx = order.indexOf('relation');
    const analogicalIdx = order.indexOf('analogical_prefilter');
    expect(rhetoricIdx).toBeGreaterThan(-1);
    expect(relationIdx).toBeGreaterThan(rhetoricIdx);
    expect(analogicalIdx).toBeGreaterThan(relationIdx);
    // Full ordering snapshot.
    expect(order).toEqual([
      'grammar',
      'logic',
      'rhetoric',
      'relation',
      'analogical_prefilter',
      'arithmetic',
      'geometry',
      'music',
      'astronomy',
      'analogical_rank',
    ]);
  });
});

```
