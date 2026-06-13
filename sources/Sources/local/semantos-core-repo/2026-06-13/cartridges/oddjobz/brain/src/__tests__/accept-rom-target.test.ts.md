---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/accept-rom-target.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.512872+00:00
---

# cartridges/oddjobz/brain/src/__tests__/accept-rom-target.test.ts

```ts
/**
 * U1 accept_rom targetJson money-channel conformance.
 *
 * Pins the wire contract intent_action_router.parseTargetCost (shipped
 * ae9eabb) consumes: explicit costMin/costMax range, ids omitted when
 * unresolved, deterministic key order, 1 KiB cap, malformed-range
 * rejection (no fabricated price downstream). Pure/intra-package.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildAcceptRomTarget,
  serialiseAcceptRomTarget,
  acceptRomTargetJson,
  TARGET_JSON_MAX_BYTES,
} from '../conversation/accept-rom-target.js';

describe('buildAcceptRomTarget', () => {
  test('explicit range + default AUD; ids omitted when absent/blank', () => {
    const t = buildAcceptRomTarget({ costMin: 40000, costMax: 60000 });
    expect(t).toEqual({ costMin: 40000, costMax: 60000, currency: 'AUD' });
    expect('jobId' in t).toBe(false);
    expect(buildAcceptRomTarget({ costMin: 1, costMax: 1, jobId: '  ', customerId: '' }))
      .toEqual({ costMin: 1, costMax: 1, currency: 'AUD' });
  });

  test('resolved ids trimmed + included; currency honoured', () => {
    const t = buildAcceptRomTarget({
      costMin: 15000, costMax: 35000,
      jobId: ' job-1 ', customerId: 'cust-1', currency: 'USD',
    });
    expect(t).toEqual({
      jobId: 'job-1', customerId: 'cust-1',
      costMin: 15000, costMax: 35000, currency: 'USD',
    });
  });

  test('point ROM allowed (costMin == costMax)', () => {
    expect(buildAcceptRomTarget({ costMin: 25000, costMax: 25000 }).costMax).toBe(25000);
  });

  test('rejects malformed range — never a fabricated price downstream', () => {
    expect(() => buildAcceptRomTarget({ costMin: 60000, costMax: 40000 })).toThrow(/costMax < costMin/);
    expect(() => buildAcceptRomTarget({ costMin: 1.5, costMax: 2 } as never)).toThrow(/non-negative integers/);
    expect(() => buildAcceptRomTarget({ costMin: -1, costMax: 2 })).toThrow(/non-negative integers/);
    expect(() => buildAcceptRomTarget({ costMin: 1, costMax: NaN })).toThrow(/non-negative integers/);
  });
});

describe('serialiseAcceptRomTarget', () => {
  test('deterministic key order jobId,customerId,costMin,costMax,currency', () => {
    const s = serialiseAcceptRomTarget(
      buildAcceptRomTarget({ costMin: 40000, costMax: 60000, jobId: 'j', customerId: 'c' }),
    );
    expect(s).toBe('{"jobId":"j","customerId":"c","costMin":40000,"costMax":60000,"currency":"AUD"}');
  });

  test('id-less range still parseable by the spec contract', () => {
    expect(acceptRomTargetJson({ costMin: 12000, costMax: 18000 }))
      .toBe('{"costMin":12000,"costMax":18000,"currency":"AUD"}');
  });

  test('enforces the 1 KiB spec cap', () => {
    const big = 'x'.repeat(TARGET_JSON_MAX_BYTES);
    expect(() =>
      serialiseAcceptRomTarget(buildAcceptRomTarget({ costMin: 1, costMax: 2, jobId: big })),
    ).toThrow(/exceeds 1024B spec cap/);
  });

  test('round-trips back to a valid {costMin,costMax} the brain honours', () => {
    const json = acceptRomTargetJson({ costMin: 40000, costMax: 60000, jobId: 'j' });
    const parsed = JSON.parse(json) as Record<string, unknown>;
    expect(parsed.costMin).toBe(40000);
    expect(parsed.costMax).toBe(60000);
    expect(parsed.jobId).toBe('j');
  });
});

```
