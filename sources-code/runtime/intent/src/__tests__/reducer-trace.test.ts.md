---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/reducer-trace.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.354110+00:00
---

# runtime/intent/src/__tests__/reducer-trace.test.ts

```ts
/**
 * RM-090 — Reducer emits per-pass trace events.
 *
 * Pins the contract:
 *   - When a logger + correlationId are supplied, `reduceToIntent` emits
 *     one `reducer_pass_completed` StageEvent per pass.
 *   - Events arrive in pass order matching the PASSES list.
 *   - Each event carries pass name, confidence, flags, contributionKeys,
 *     skipInComposite, durationMs, and the caller's correlationId.
 *   - Silent default: omit the logger and zero events are produced.
 */
import { describe, expect, test } from 'bun:test';
import { reduceToIntent } from '../reducer/index';
import { createInMemoryLogger } from '../logger';
import { T1_REPORT_DRIPPING_TAP } from '../reducer/__fixtures__/trades-fixtures';
import type { CorrelationId } from '../types';

const CORR = 'corr-rm090-test' as CorrelationId;

describe('reducer trace events (RM-090)', () => {
  test('A1 emits exactly one reducer_pass_completed per pass, in pass order', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: CORR,
    });

    const passEvents = logger.events.filter((e) => e.stage === 'reducer_pass_completed');
    expect(passEvents.length).toBe(10);

    const passNames = passEvents.map((e) => (e.data as { pass: string }).pass);
    expect(passNames).toEqual([
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

  test('A2 every event carries the supplied correlationId and intentId=null', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: CORR,
    });

    for (const e of logger.events) {
      expect(e.correlationId).toBe(CORR);
      expect(e.intentId).toBeNull();
    }
  });

  test('A3 each event carries pass shape: confidence, flags, contributionKeys, durationMs', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: CORR,
    });

    for (const e of logger.events) {
      expect(e.stage).toBe('reducer_pass_completed');
      const data = e.data as Record<string, unknown>;
      expect(typeof data.pass).toBe('string');
      expect(typeof data.confidence).toBe('number');
      expect(Array.isArray(data.flags)).toBe(true);
      expect(Array.isArray(data.contributionKeys)).toBe(true);
      expect(typeof data.skipInComposite).toBe('boolean');
      expect(typeof e.durationMs).toBe('number');
      expect(e.durationMs).toBeGreaterThanOrEqual(0);
    }
  });

  test('A4 omitting the logger keeps the reducer silent (no events)', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
    expect(logger.events.length).toBe(0);
  });

  test('A5 omitting the correlationId keeps the reducer silent (no orphan events)', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
    });
    expect(logger.events.length).toBe(0);
  });

  test('A6 confidence + flags match the returned PassResult shape', async () => {
    const logger = createInMemoryLogger();
    const { passResults } = await reduceToIntent(
      T1_REPORT_DRIPPING_TAP.input,
      T1_REPORT_DRIPPING_TAP.grammar,
      { logger, correlationId: CORR },
    );

    for (let i = 0; i < passResults.length; i++) {
      const event = logger.events[i];
      const data = event.data as { pass: string; confidence: number; flags: string[] };
      expect(data.pass).toBe(passResults[i].pass);
      expect(data.confidence).toBe(passResults[i].confidence);
      expect(data.flags).toEqual(passResults[i].flags);
    }
  });
});

```
