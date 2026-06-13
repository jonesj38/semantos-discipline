---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/produce-intent.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.358066+00:00
---

# runtime/intent/src/__tests__/produce-intent.test.ts

```ts
/**
 * RM-091 — producer boundary mints one correlationId, emits
 * `intent_produced`, threads the same id through reducer events, and
 * stamps it onto the returned Intent.
 *
 * Acceptance per the roadmap:
 *   "all events on the JSONL stream share a single correlationId.
 *    No orphan events."
 */
import { describe, expect, test } from 'bun:test';
import { produceIntent } from '../produce-intent';
import { createInMemoryLogger } from '../logger';
import { T1_REPORT_DRIPPING_TAP } from '../reducer/__fixtures__/trades-fixtures';
import type { CorrelationId } from '../types';

describe('produceIntent (RM-091)', () => {
  test('P1 emits intent_produced first, then 10 reducer_pass_completed events', async () => {
    const logger = createInMemoryLogger();
    await produceIntent({
      rawInput: 'tenant: the kitchen tap is dripping',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
    });

    const stages = logger.events.map((e) => e.stage);
    expect(stages[0]).toBe('intent_produced');
    expect(stages.slice(1)).toEqual(Array(10).fill('reducer_pass_completed'));
  });

  test('P2 every emitted event shares the same correlationId', async () => {
    const logger = createInMemoryLogger();
    const { correlationId } = await produceIntent({
      rawInput: 'tenant: the kitchen tap is dripping',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
    });

    expect(logger.events.length).toBeGreaterThan(0);
    for (const e of logger.events) {
      expect(e.correlationId).toBe(correlationId);
    }
  });

  test('P3 returned Intent carries the same correlationId', async () => {
    const logger = createInMemoryLogger();
    const result = await produceIntent({
      rawInput: 'tenant: dripping tap',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
    });

    expect(result.intent.correlationId).toBe(result.correlationId);
  });

  test('P4 caller-supplied correlationId is threaded through unchanged', async () => {
    const logger = createInMemoryLogger();
    const supplied = 'corr-parent-turn-42' as CorrelationId;
    const { correlationId } = await produceIntent({
      rawInput: 'follow-up',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      correlationId: supplied,
      logger,
    });

    expect(correlationId).toBe(supplied);
    for (const e of logger.events) {
      expect(e.correlationId).toBe(supplied);
    }
  });

  test('P5 intent_produced event carries rawInputDigest + length, not the raw text', async () => {
    const logger = createInMemoryLogger();
    const raw = 'tenant: dripping tap in kitchen';
    await produceIntent({
      rawInput: raw,
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
    });

    const produced = logger.events.find((e) => e.stage === 'intent_produced');
    expect(produced).toBeDefined();
    const data = produced!.data as Record<string, unknown>;
    expect(typeof data.rawInputDigest).toBe('string');
    expect((data.rawInputDigest as string).length).toBe(32);
    expect(data.rawInputLength).toBe(raw.length);
    // Raw text MUST NOT appear in the trace.
    expect(JSON.stringify(produced)).not.toContain('dripping');
    expect(JSON.stringify(produced)).not.toContain('kitchen');
  });

  test('P6 omitting the logger keeps the producer silent (no orphan events)', async () => {
    const logger = createInMemoryLogger();
    await produceIntent({
      rawInput: 'silent path',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
    });
    expect(logger.events.length).toBe(0);
  });

  test('P7 returned intent.source matches the producer source tag', async () => {
    const logger = createInMemoryLogger();
    const result = await produceIntent({
      rawInput: 'shell: cdm.confirm trade-42',
      source: 'shell',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
    });
    expect(result.intent.source).toBe('shell');
  });

  test('P8 deterministic uuid injection produces a deterministic correlationId', async () => {
    const logger = createInMemoryLogger();
    const r = await produceIntent({
      rawInput: 'deterministic',
      source: 'nl',
      reducerInput: T1_REPORT_DRIPPING_TAP.input,
      grammar: T1_REPORT_DRIPPING_TAP.grammar,
      logger,
      deps: {
        uuid: () => 'pinned-uuid-0000',
        now: () => new Date('2026-05-14T00:00:00Z'),
      },
    });
    expect(r.correlationId).toBe('pinned-uuid-0000' as CorrelationId);
  });
});

```
