---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.356918+00:00
---

# runtime/intent/src/__tests__/pipeline.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { processIntent, type PipelineDeps } from '../pipeline';
import { createInMemoryLogger } from '../logger';
import type {
  Intent,
  HatContext,
  IntentContext,
  IntentId,
  Cell,
  CellId,
  CorrelationId,
  ScriptResult,
  StageName,
} from '../types';
import type { LoweringResult, SIRProgram } from '@semantos/semantos-sir';

// ── Fixture helpers ──────────────────────────────────────────

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-1',
  hatId: 'hat-1',
  certId: 'cert-1',
  capabilities: [5],
  extensionId: 'ext-demo',
  domainFlag: 7,
  maxTrustClass: 'interpretive',
  ...over,
});

const mkIntent = (over: Partial<Intent> = {}): Intent => ({
  id: '01HQ-intent' as IntentId,
  summary: 'publish core.Document with SIGNING capability',
  category: { lexicon: 'jural', category: 'declaration' },
  taxonomy: { what: 'core.Document', how: 'lifecycle.publish', why: 'audit' },
  action: 'transition',
  constraints: [{ kind: 'capability', required: 5, name: 'SIGNING' }],
  confidence: 1,
  source: 'shell',
  ...over,
});

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 3, gasUsed: 10 };
const failKernel: ScriptResult = {
  ok: false,
  stackDepth: 0,
  opcount: 0,
  gasUsed: 0,
  errorCode: 12,
  errorMessage: 'capability not held',
};

const mkDeps = (over: Partial<PipelineDeps> = {}): PipelineDeps => ({
  lowerSIR: (_: SIRProgram): LoweringResult => ({
    ok: true,
    program: { nodes: [], metadata: {} } as unknown as LoweringResult extends {
      ok: true;
      program: infer P;
    }
      ? P
      : never,
  }),
  emitBytes: () => new Uint8Array([0xc3, 0x05]), // OP_CHECKCAPABILITY 5
  executeScript: async () => okKernel,
  buildCellFromBytes: (bytes, _kr): Cell => ({
    id: 'cell-stub' as CellId,
    bytes,
  }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0xde, 0xad]),
  now: () => 1000,
  uuid: () => '01HQ-generated',
  ...over,
});

const mkCtx = (over: Partial<IntentContext> = {}): IntentContext => ({
  hat: mkHat(),
  logger: createInMemoryLogger(),
  ...over,
});

// ── Tests ────────────────────────────────────────────────────

describe('processIntent — happy path', () => {
  test('emits exactly the 7 forward stage events in order', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    await processIntent(mkIntent(), ctx, mkDeps());

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual([
      'intent_extracted',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'cell_written',
      'intent_completed',
    ] as StageName[]);
  });

  test('all events share the same correlationId', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    await processIntent(mkIntent(), ctx, mkDeps());

    const ids = new Set(logger.events.map(e => e.correlationId));
    expect(ids.size).toBe(1);
  });

  test('generates correlationId from deps.uuid() when intent omits one', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    const result = await processIntent(mkIntent(), ctx, mkDeps());

    expect(result.correlationId).toBe('01HQ-generated' as CorrelationId);
    expect(logger.events[0]!.correlationId).toBe('01HQ-generated' as CorrelationId);
  });

  test('propagates caller-provided correlationId unchanged', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({
      logger,
      correlationId: '01HQ-caller' as CorrelationId,
    });
    const result = await processIntent(mkIntent(), ctx, mkDeps());

    expect(result.correlationId).toBe('01HQ-caller' as CorrelationId);
  });

  test('IntentResult.ok=true with cell and receipt on success', async () => {
    const result = await processIntent(mkIntent(), mkCtx(), mkDeps());
    expect(result.ok).toBe(true);
    expect(result.cell).not.toBeNull();
    expect(result.cell!.id).toBe('cell-stub' as CellId);
    expect(result.receipt.signedBy).toBe('hat-1');
    expect(result.rejection).toBeUndefined();
  });
});

describe('processIntent — SIR rejection', () => {
  test('stops after sir_built; emits intent_rejected; no kernel events', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    const deps = mkDeps({
      lowerSIR: () => ({
        ok: false,
        code: 'trust_tier_exceeded',
        message: 'authoritative requires formal proof',
      }),
    });

    const result = await processIntent(mkIntent(), ctx, deps);

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual(['intent_extracted', 'sir_built', 'intent_rejected']);

    expect(result.ok).toBe(false);
    expect(result.rejection).toEqual({
      stage: 'sir',
      code: 'trust_tier_exceeded',
      message: 'authoritative requires formal proof',
    });
    expect(result.cell).toBeNull();
  });
});

describe('processIntent — kernel rejection', () => {
  test('stops after script_executed; emits intent_rejected{kernel}; no cell_written', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    const deps = mkDeps({ executeScript: async () => failKernel });

    const result = await processIntent(mkIntent(), ctx, deps);

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual([
      'intent_extracted',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'intent_rejected',
    ]);

    expect(result.ok).toBe(false);
    expect(result.rejection?.stage).toBe('kernel');
    expect(result.rejection?.code).toBe('12');
    expect(result.cell).toBeNull();
  });
});

describe('processIntent — stage event shape', () => {
  test('every event carries hatId, source, and intentId', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger, hat: mkHat({ hatId: 'hat-X' }) });
    await processIntent(mkIntent({ source: 'shell' }), ctx, mkDeps());

    for (const ev of logger.events) {
      expect(ev.hatId).toBe('hat-X');
      expect(ev.source).toBe('shell');
      expect(ev.intentId).toBe('01HQ-intent' as IntentId);
      expect(typeof ev.durationMs).toBe('number');
      expect(ev.durationMs).toBeGreaterThanOrEqual(0);
    }
  });

  test('sir_built carries trustClass and constraintCount', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    await processIntent(mkIntent(), ctx, mkDeps());

    const ev = logger.events.find(e => e.stage === 'sir_built')!;
    expect(ev.data.trustClass).toBe('interpretive');
    expect(ev.data.constraintCount).toBe(1);
  });

  test('script_executed carries kernelOk + opcount', async () => {
    const logger = createInMemoryLogger();
    const ctx = mkCtx({ logger });
    await processIntent(mkIntent(), ctx, mkDeps());

    const ev = logger.events.find(e => e.stage === 'script_executed')!;
    expect(ev.data.kernelOk).toBe(true);
    expect(ev.data.opcount).toBe(3);
  });
});

```
