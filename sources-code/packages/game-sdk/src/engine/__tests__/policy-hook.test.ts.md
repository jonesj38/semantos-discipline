---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/policy-hook.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.530788+00:00
---

# packages/game-sdk/src/engine/__tests__/policy-hook.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  acceptAllPolicy,
  policyPort,
  resolvePolicy,
  type PolicyEvaluator,
} from '../policy-hook';

afterEach(() => policyPort.unbind());

describe('policy-hook', () => {
  test('1. resolvePolicy returns acceptAll when nothing bound', async () => {
    const result = await resolvePolicy().evaluate({ action: {}, state: {} });
    expect(result.decision).toBe('accept');
  });

  test('2. acceptAllPolicy never rejects', async () => {
    expect((await acceptAllPolicy.evaluate({ action: 'whatever', state: 'whatever' })).decision).toBe('accept');
  });

  test('3. resolvePolicy returns the bound evaluator', async () => {
    const stub: PolicyEvaluator = {
      evaluate: () => ({ decision: 'reject', reason: 'no' }),
    };
    policyPort.bind(stub);
    const r = await resolvePolicy().evaluate({ action: {}, state: {} });
    expect(r).toEqual({ decision: 'reject', reason: 'no' });
  });
});

```
