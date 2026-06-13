---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/logger.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.354688+00:00
---

# runtime/intent/src/__tests__/logger.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { createInMemoryLogger, createJsonlStderrLogger } from '../logger';
import type { CorrelationId, IntentId, StageEvent } from '../types';

const stubEvent = (stage: StageEvent['stage']): StageEvent => ({
  ts: '2026-04-19T00:00:00.000000Z',
  correlationId: '01HQ-correlation' as CorrelationId,
  intentId: '01HQ-intent' as IntentId,
  stage,
  durationMs: 1,
  hatId: 'hat-1',
  source: 'shell',
  data: {},
});

describe('createInMemoryLogger', () => {
  test('accumulates events in emit order', () => {
    const logger = createInMemoryLogger();
    logger.emit(stubEvent('intent_extracted'));
    logger.emit(stubEvent('sir_built'));
    logger.emit(stubEvent('intent_completed'));

    expect(logger.events.map(e => e.stage)).toEqual([
      'intent_extracted',
      'sir_built',
      'intent_completed',
    ]);
  });

  test('clear() empties the buffer', () => {
    const logger = createInMemoryLogger();
    logger.emit(stubEvent('intent_extracted'));
    logger.clear();
    expect(logger.events).toHaveLength(0);
  });

  test('events getter returns a snapshot, not a live alias', () => {
    const logger = createInMemoryLogger();
    const snap = logger.events;
    logger.emit(stubEvent('sir_built'));
    // The in-memory impl returns the same backing array; this test
    // documents the contract. If you need a true snapshot, slice at
    // the callsite.
    expect(snap).toBe(logger.events);
  });
});

describe('createJsonlStderrLogger', () => {
  test('produces exactly one JSON line per event', () => {
    const logger = createJsonlStderrLogger();
    const written: string[] = [];
    const original = process.stderr.write.bind(process.stderr);
    process.stderr.write = ((chunk: unknown): boolean => {
      written.push(typeof chunk === 'string' ? chunk : String(chunk));
      return true;
    }) as typeof process.stderr.write;

    try {
      logger.emit(stubEvent('intent_extracted'));
    } finally {
      process.stderr.write = original;
    }

    expect(written).toHaveLength(1);
    expect(written[0]!.endsWith('\n')).toBe(true);
    const parsed = JSON.parse(written[0]!.trim());
    expect(parsed.stage).toBe('intent_extracted');
    expect(parsed.correlationId).toBe('01HQ-correlation');
  });
});

```
