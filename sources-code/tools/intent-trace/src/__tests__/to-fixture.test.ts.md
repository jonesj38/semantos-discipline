---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/__tests__/to-fixture.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.550852+00:00
---

# tools/intent-trace/src/__tests__/to-fixture.test.ts

```ts
/**
 * RM-094 — trace-to-fixture transform acceptance.
 *
 * Tests in three layers:
 *   - F1-F3: pure structural fingerprint shape.
 *   - F4: jsonlToFixtureTest emits a valid TS test file string.
 *   - F5: end-to-end — generate a fixture from a live reducer run,
 *     re-run the reducer, and confirm fingerprints match. This is
 *     the regression-loop the cartridge author lives in.
 *   - F6: tampering with the captured fingerprint produces a failing
 *     comparison (negative test — the regression catches drift).
 */
import { describe, expect, test } from 'bun:test';
import { reduceToIntent } from '../../../../runtime/intent/src/reducer/index';
import { createInMemoryLogger } from '../../../../runtime/intent/src/logger';
import { T1_REPORT_DRIPPING_TAP } from '../../../../runtime/intent/src/reducer/__fixtures__/trades-fixtures';
import type { CorrelationId } from '../../../../runtime/intent/src/types';
import { parseTrace } from '../parse';
import {
  fingerprintEvent,
  fingerprintTrace,
  emitFixtureTest,
  jsonlToFixtureTest,
  type FixtureEvent,
} from '../to-fixture';

describe('fingerprintEvent (RM-094)', () => {
  test('F1 strips volatile fields (ts, durationMs, correlationId, intentId)', () => {
    const fp = fingerprintEvent({
      ts: '2026-05-14T00:00:00Z',
      correlationId: 'corr-x',
      intentId: null,
      stage: 'reducer_pass_completed',
      durationMs: 12.7,
      hatId: null,
      source: 'nl',
      data: {
        pass: 'grammar',
        confidence: 0.85,
        flags: [],
        contributionKeys: ['taxonomy'],
        skipInComposite: false,
        alternativesCount: 0,
      },
    });
    expect(fp.stage).toBe('reducer_pass_completed');
    expect(fp.data.pass).toBe('grammar');
    expect(fp.data.skipInComposite).toBe(false);
    expect(fp.data.contributionKeys).toEqual(['taxonomy']);
    // No timing or correlation fields make it into the fingerprint.
    expect(JSON.stringify(fp)).not.toContain('corr-x');
    expect(JSON.stringify(fp)).not.toContain('durationMs');
  });

  test('F2 retains rejection reason for short-circuit traces', () => {
    const fp = fingerprintEvent({
      ts: '2026-05-14T00:00:00Z',
      correlationId: 'corr-x',
      intentId: null,
      stage: 'intent_rejected',
      durationMs: 0,
      hatId: null,
      source: 'nl',
      data: { reason: 'trust_tier_violation' },
    });
    expect(fp.data.reason).toBe('trust_tier_violation');
  });

  test('F3 fingerprintTrace preserves event order', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: 'corr-trace' as CorrelationId,
    });
    const fp = fingerprintTrace(logger.events as any);
    expect(fp.length).toBe(10);
    expect(fp[0].data.pass).toBe('grammar');
    expect(fp[fp.length - 1].data.pass).toBe('analogical_rank');
  });
});

describe('emitFixtureTest (RM-094)', () => {
  const events = [
    {
      ts: '0',
      correlationId: 'c',
      intentId: null,
      stage: 'reducer_pass_completed',
      durationMs: 1,
      hatId: null,
      source: 'nl',
      data: {
        pass: 'grammar',
        confidence: 0.85,
        flags: [],
        contributionKeys: ['taxonomy'],
        skipInComposite: false,
        alternativesCount: 0,
      },
    },
  ];

  test('F4 emits a TS test file string that imports the named fixture', () => {
    const out = emitFixtureTest(events as any, {
      inputFixtureName: 'T1_REPORT_DRIPPING_TAP',
    });
    expect(out).toContain("import { T1_REPORT_DRIPPING_TAP }");
    expect(out).toContain("describe('regression: T1_REPORT_DRIPPING_TAP");
    expect(out).toContain('reducer run reproduces the captured event sequence');
    expect(out).toContain('"pass": "grammar"');
  });
});

describe('end-to-end fixture round-trip (RM-094)', () => {
  test('F5 capture → fingerprint → re-run reproduces fingerprint', async () => {
    // Step 1: capture a live trace.
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: 'corr-cap' as CorrelationId,
    });
    const captured = fingerprintTrace(logger.events as any);

    // Step 2: re-run the reducer with the same input.
    const logger2 = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger: logger2,
      correlationId: 'corr-replay' as CorrelationId,
    });
    const replay = fingerprintTrace(logger2.events as any);

    // Step 3: structural fingerprints must match.
    expect(replay).toEqual(captured);
  });

  test('F6 tampering with the fingerprint breaks the comparison (regression gate)', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: 'corr-cap' as CorrelationId,
    });
    const captured = fingerprintTrace(logger.events as any);

    // Mutate: flip rhetoric to claim it's the wrong pass.
    const tampered: FixtureEvent[] = JSON.parse(JSON.stringify(captured));
    const rhetoric = tampered.find((e) => e.data.pass === 'rhetoric');
    expect(rhetoric).toBeDefined();
    rhetoric!.data.pass = 'NOT_RHETORIC';

    const logger2 = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger: logger2,
      correlationId: 'corr-replay' as CorrelationId,
    });
    const live = fingerprintTrace(logger2.events as any);

    // The bun expect().not.toEqual(tampered) — drift is caught.
    expect(live).not.toEqual(tampered);
  });
});

describe('jsonlToFixtureTest (RM-094)', () => {
  test('F7 end-to-end via JSONL → emitted test source', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: 'corr-e2e' as CorrelationId,
    });
    const jsonl = logger.events.map((e) => JSON.stringify(e)).join('\n');
    const ts = jsonlToFixtureTest(jsonl, {
      inputFixtureName: 'T1_REPORT_DRIPPING_TAP',
    });
    expect(ts).toContain('T1_REPORT_DRIPPING_TAP');
    expect(ts).toContain('"pass": "grammar"');
    expect(ts).toContain('"pass": "analogical_rank"');
    expect(ts).not.toContain('corr-e2e'); // correlationIds excluded
  });

  test('F8 throws on empty trace', () => {
    expect(() => jsonlToFixtureTest('', { inputFixtureName: 'X' })).toThrow(/empty/);
  });

  test('F9 unknown correlationId throws', () => {
    expect(() =>
      jsonlToFixtureTest(
        '{"ts":"0","correlationId":"a","intentId":null,"stage":"x","durationMs":0,"hatId":null,"source":"nl","data":{}}',
        { inputFixtureName: 'X', correlationId: 'missing' },
      ),
    ).toThrow(/no events found for correlationId/);
  });
});

```
