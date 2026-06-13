---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/ui-hint.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.353817+00:00
---

# runtime/intent/src/__tests__/ui-hint.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { deriveUIHint } from '../ui-hint';
import type { Intent, IntentId, ScriptResult } from '../types';
import type { JuralCategory } from '@semantos/semantos-sir';

const mkIntent = (over: Partial<Intent> = {}): Intent => ({
  id: '01HQ' as IntentId,
  summary: '',
  category: { lexicon: 'jural', category: 'declaration' },
  taxonomy: { what: 'a', how: 'b', why: 'c' },
  action: 'noop',
  constraints: [],
  confidence: 1,
  source: 'shell',
  ...over,
});

/** Tiny helper for test fixtures — reads better than inline object literals. */
const jural = (c: JuralCategory): Intent['category'] => ({ lexicon: 'jural', category: c });

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 1, gasUsed: 1 };
const failKernel: ScriptResult = {
  ok: false,
  stackDepth: 0,
  opcount: 0,
  gasUsed: 0,
  errorCode: 42,
  errorMessage: 'boom',
};

describe('deriveUIHint', () => {
  test('SIR rejection → toast with clarify follow-up', () => {
    const hint = deriveUIHint({
      intent: mkIntent(),
      kernelResult: failKernel,
      rejection: { stage: 'sir', code: 'trust_tier', message: 'needs proof' },
    });
    expect(hint.presentation).toBe('toast');
    expect(hint.followUp).toEqual({ kind: 'clarify', prompt: 'needs proof' });
  });

  test('kernel rejection → toast with NO follow-up (not producer-retryable)', () => {
    const hint = deriveUIHint({
      intent: mkIntent(),
      kernelResult: failKernel,
      rejection: { stage: 'kernel', code: 'cap_missing', message: 'no SIGNING' },
    });
    expect(hint.presentation).toBe('toast');
    expect(hint.followUp).toBeUndefined();
  });

  test('kernel failure without structured rejection → toast, no invalidation', () => {
    const hint = deriveUIHint({ intent: mkIntent(), kernelResult: failKernel });
    expect(hint.presentation).toBe('toast');
    expect(hint.invalidate).toEqual([]);
  });

  test('success on target invalidates that object', () => {
    const hint = deriveUIHint({
      intent: mkIntent({ target: { objectId: 'obj-9' } }),
      kernelResult: okKernel,
    });
    expect(hint.invalidate).toEqual(['obj-9']);
  });

  test('jural/transfer → inspector presentation', () => {
    const hint = deriveUIHint({
      intent: mkIntent({ category: jural('transfer') }),
      kernelResult: okKernel,
    });
    expect(hint.presentation).toBe('inspector');
  });

  test('jural/power → inspector presentation', () => {
    const hint = deriveUIHint({
      intent: mkIntent({ category: jural('power') }),
      kernelResult: okKernel,
    });
    expect(hint.presentation).toBe('inspector');
  });

  test('jural obligation/permission/prohibition → inline', () => {
    for (const category of ['obligation', 'permission', 'prohibition'] as const) {
      const hint = deriveUIHint({
        intent: mkIntent({ category: jural(category) }),
        kernelResult: okKernel,
      });
      expect(hint.presentation).toBe('inline');
    }
  });

  test('jural declaration/condition → silent', () => {
    for (const category of ['declaration', 'condition'] as const) {
      const hint = deriveUIHint({
        intent: mkIntent({ category: jural(category) }),
        kernelResult: okKernel,
      });
      expect(hint.presentation).toBe('silent');
    }
  });

  test('non-jural lexicons fall back to inline', () => {
    const hint = deriveUIHint({
      intent: mkIntent({
        category: { lexicon: 'control-systems', category: 'setpoint' },
      }),
      kernelResult: okKernel,
    });
    expect(hint.presentation).toBe('inline');
  });
});

```
