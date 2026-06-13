---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/__tests__/render.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.551163+00:00
---

# tools/intent-trace/src/__tests__/render.test.ts

```ts
/**
 * RM-093 — Cascade renderer golden-output tests.
 *
 * Uses a hand-built fixture trace so the test stays independent of the
 * reducer's runtime behaviour. A second test generates a trace from
 * the live reducer to confirm the renderer accepts real-world output.
 */
import { describe, expect, test } from 'bun:test';
import { parseTrace, groupByCorrelation, parseLine } from '../parse';
import { renderCascade, renderAll } from '../render';

const FIXTURE_JSONL = [
  JSON.stringify({
    ts: '2026-05-14T00:00:00.000Z',
    correlationId: 'corr-aaaa',
    intentId: null,
    stage: 'intent_produced',
    durationMs: 0,
    hatId: null,
    source: 'nl',
    data: { rawInputDigest: 'deadbeefdeadbeefdeadbeefdeadbeef', rawInputLength: 27 },
  }),
  JSON.stringify({
    ts: '2026-05-14T00:00:00.001Z',
    correlationId: 'corr-aaaa',
    intentId: null,
    stage: 'reducer_pass_completed',
    durationMs: 1.2,
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
  }),
  JSON.stringify({
    ts: '2026-05-14T00:00:00.002Z',
    correlationId: 'corr-aaaa',
    intentId: null,
    stage: 'reducer_pass_completed',
    durationMs: 2.4,
    hatId: null,
    source: 'nl',
    data: {
      pass: 'rhetoric',
      confidence: 0.95,
      flags: ['rhetoric: low confidence action foo'],
      contributionKeys: ['action', 'category'],
      skipInComposite: false,
      alternativesCount: 2,
    },
  }),
  '',
  '# a non-event line that the parser should skip',
  JSON.stringify({
    ts: '2026-05-14T00:00:00.003Z',
    correlationId: 'corr-aaaa',
    intentId: null,
    stage: 'reducer_pass_completed',
    durationMs: 0.3,
    hatId: null,
    source: 'nl',
    data: {
      pass: 'relation',
      confidence: 1,
      flags: [],
      contributionKeys: [],
      skipInComposite: true,
      alternativesCount: 0,
    },
  }),
].join('\n');

const FIXTURE_REJECTION = [
  JSON.stringify({
    ts: '2026-05-14T00:00:00.000Z',
    correlationId: 'corr-bbbb',
    intentId: 'intent-2',
    stage: 'intent_produced',
    durationMs: 0,
    hatId: null,
    source: 'nl',
    data: { rawInputDigest: 'cafebabecafebabecafebabecafebabe', rawInputLength: 42 },
  }),
  JSON.stringify({
    ts: '2026-05-14T00:00:01.000Z',
    correlationId: 'corr-bbbb',
    intentId: 'intent-2',
    stage: 'intent_rejected',
    durationMs: 1.0,
    hatId: null,
    source: 'nl',
    data: { reason: 'trust_tier_violation' },
  }),
].join('\n');

describe('intent-trace parser', () => {
  test('P1 parses a 3-pass fixture trace into typed events', () => {
    const events = parseTrace(FIXTURE_JSONL);
    expect(events.length).toBe(4); // 1 produced + 3 reducer
    expect(events[0].stage).toBe('intent_produced');
    expect(events[1].data.pass).toBe('grammar');
  });

  test('P2 skips blank lines and non-event lines', () => {
    const events = parseTrace(FIXTURE_JSONL);
    expect(events.every((e) => typeof e.stage === 'string')).toBe(true);
  });

  test('P3 parseLine returns null for malformed input', () => {
    expect(parseLine('')).toBeNull();
    expect(parseLine('not json')).toBeNull();
    expect(parseLine('{"missing": "fields"}')).toBeNull();
  });

  test('P4 groupByCorrelation buckets events per turn', () => {
    const events = parseTrace([FIXTURE_JSONL, FIXTURE_REJECTION].join('\n'));
    const groups = groupByCorrelation(events);
    expect(groups.size).toBe(2);
    expect(groups.get('corr-aaaa')!.length).toBe(4);
    expect(groups.get('corr-bbbb')!.length).toBe(2);
  });
});

describe('intent-trace cascade renderer (RM-093)', () => {
  test('R1 happy-path trace renders as an indented tree with the expected lines', () => {
    const events = parseTrace(FIXTURE_JSONL);
    const out = renderCascade(events);
    const lines = out.split('\n');

    expect(lines[0]).toBe('[corr-aaaa] 4 events · 3.9ms total · source=nl');
    expect(lines[1]).toBe('├── intent_produced  rawInputDigest=deadbeefdeadbeef  len=27');
    expect(lines[2]).toBe('└── reducer (3 passes)');
    expect(lines[3]).toContain('grammar');
    expect(lines[3]).toContain('conf=0.85');
    expect(lines[4]).toContain('rhetoric');
    expect(lines[4]).toContain('alt=2');
    expect(lines[4]).toContain('flags=1');
    expect(lines[5]).toContain('relation');
    expect(lines[5]).toContain('skip');
  });

  test('R2 rejection trace renders the short-circuit event with reason', () => {
    const events = parseTrace(FIXTURE_REJECTION);
    const out = renderCascade(events);
    expect(out).toContain('intent_rejected');
    expect(out).toContain('reason=trust_tier_violation');
  });

  test('R3 --flags renders each pass\'s flag list as bulleted children', () => {
    const events = parseTrace(FIXTURE_JSONL);
    const out = renderCascade(events, { includeFlags: true });
    expect(out).toContain('⚑ rhetoric: low confidence action foo');
  });

  test('R4 renderAll separates correlation groups with a blank line', () => {
    const events = parseTrace([FIXTURE_JSONL, FIXTURE_REJECTION].join('\n'));
    const groups = groupByCorrelation(events);
    const out = renderAll(groups);
    expect(out).toContain('corr-aaaa');
    expect(out).toContain('corr-bbbb');
    expect(out).toContain('\n\n');
  });

  test('R5 empty event list renders empty string', () => {
    expect(renderCascade([])).toBe('');
  });
});

describe('renderer accepts live reducer output', () => {
  test('L1 captures a real reducer run + renders without error', async () => {
    const { reduceToIntent } = await import('../../../../runtime/intent/src/reducer/index');
    const { createInMemoryLogger } = await import('../../../../runtime/intent/src/logger');
    const { T1_REPORT_DRIPPING_TAP } = await import(
      '../../../../runtime/intent/src/reducer/__fixtures__/trades-fixtures'
    );
    const logger = createInMemoryLogger();
    await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar, {
      logger,
      correlationId: 'corr-live-test' as never,
    });
    const jsonl = logger.events.map((e) => JSON.stringify(e)).join('\n');
    const events = parseTrace(jsonl);
    expect(events.length).toBe(10);
    const out = renderCascade(events);
    expect(out).toContain('corr-live-test');
    expect(out).toContain('reducer (10 passes)');
    expect(out).toContain('grammar');
    expect(out).toContain('analogical_rank');
  });
});

```
