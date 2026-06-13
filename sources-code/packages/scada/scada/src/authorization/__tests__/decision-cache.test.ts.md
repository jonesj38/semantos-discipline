---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/__tests__/decision-cache.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.476770+00:00
---

# packages/scada/scada/src/authorization/__tests__/decision-cache.test.ts

```ts
/**
 * Unit tests — decision-cache.
 */

import { afterEach, describe, expect, test } from 'bun:test';

import {
  decisionKey,
  getDecisionCacheAtoms,
  invalidateForToken,
  lookupDecision,
  recordDecision,
  resetDecisionCache,
} from '../decision-cache';

afterEach(() => {
  resetDecisionCache();
});

describe('decisionKey', () => {
  test('packs the four-tuple into a deterministic string', () => {
    expect(decisionKey('op-1', 'valve.open', 'eq-1', 'tkn-1')).toBe(
      'op-1::valve.open::eq-1::tkn-1',
    );
  });
});

describe('getDecisionCacheAtoms', () => {
  test('idempotent — same scope returns same bundle', () => {
    const a = getDecisionCacheAtoms('s');
    const b = getDecisionCacheAtoms('s');
    expect(a).toBe(b);
  });
  test('distinct scopes get distinct bundles', () => {
    const a = getDecisionCacheAtoms('a');
    const b = getDecisionCacheAtoms('b');
    expect(a).not.toBe(b);
  });
});

describe('lookup / record / invalidate', () => {
  test('record + lookup within ttl returns the decision', () => {
    const scope = getDecisionCacheAtoms('s');
    const key = decisionKey('op', 'valve.open', 'eq', 'tkn');
    recordDecision(scope, key, {
      cachedAtMs: 1_000,
      ttlMs: 500,
      verdict: 'pass',
      required: 3,
    });
    expect(lookupDecision(scope, key, 1_400)).toBeDefined();
  });

  test('lookup after ttl expiry returns undefined and evicts', () => {
    const scope = getDecisionCacheAtoms('s');
    const key = decisionKey('op', 'valve.open', 'eq', 'tkn');
    recordDecision(scope, key, {
      cachedAtMs: 1_000,
      ttlMs: 500,
      verdict: 'pass',
      required: 3,
    });
    expect(lookupDecision(scope, key, 2_000)).toBeUndefined();
    // Lazy eviction — second lookup also undefined.
    expect(lookupDecision(scope, key, 1_400)).toBeUndefined();
  });

  test('invalidateForToken drops only the matching tokenId', () => {
    const scope = getDecisionCacheAtoms('s');
    const k1 = decisionKey('op', 'valve.open', 'eq', 'tkn-A');
    const k2 = decisionKey('op', 'valve.open', 'eq', 'tkn-B');
    const decision = {
      cachedAtMs: 0,
      ttlMs: 1_000,
      verdict: 'pass' as const,
      required: 3,
    };
    recordDecision(scope, k1, decision);
    recordDecision(scope, k2, decision);
    invalidateForToken(scope, 'tkn-A');
    expect(lookupDecision(scope, k1, 100)).toBeUndefined();
    expect(lookupDecision(scope, k2, 100)).toBeDefined();
  });
});

```
