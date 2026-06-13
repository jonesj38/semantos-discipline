---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/outcome-emitter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.355854+00:00
---

# runtime/intent/src/__tests__/outcome-emitter.test.ts

```ts
/**
 * WI-A2 — outcome emitter tests.
 *
 * WI-A2-T-emit-on-success     — successful Intent commit calls emitter exactly once
 * WI-A2-T-no-emit-on-rejection — SIR rejection produces no emit
 * WI-A2-T-anf-bindings-passthrough — IRProgram bindings reach the emitter payload unchanged
 */

import { describe, expect, test } from 'bun:test';
import { processIntent, type PipelineDeps } from '../pipeline';
import { RecordingNatsEmitter } from '../outcome-emitter';
import { createInMemoryLogger } from '../logger';
import type {
  Intent,
  HatContext,
  IntentContext,
  IntentId,
  Cell,
  CellId,
  ScriptResult,
} from '../types';
import type { LoweringResult, SIRProgram } from '@semantos/semantos-sir';
import type { IRBinding } from '@semantos/semantos-ir';

// ── Fixture helpers ────────────────────────────────────────────────────────

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-trades',
  certId: 'cert-1',
  capabilities: [1],
  extensionId: 'ext-trades',
  domainFlag: 2,
  maxTrustClass: 'interpretive',
  ...over,
});

const mkIntent = (over: Partial<Intent> = {}): Intent => ({
  id: '01HQ-intent-oc' as IntentId,
  summary: 'create obligation',
  category: { lexicon: 'trades', category: 'obligation' },
  taxonomy: { what: 'Trade', how: 'lifecycle.create', why: 'settlement' },
  action: 'create',
  constraints: [{ kind: 'capability', required: 1, name: 'TRADE' }],
  confidence: 0.95,
  source: 'shell',
  ...over,
});

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 2, gasUsed: 5 };

const twoBindings: IRBinding[] = [
  { name: '$0', kind: 'comparison', op: '>', field: 'amount', value: 0 },
  { name: '$1', kind: 'timeConstraint', timeOp: 'timeAfter', timestamp: 1_700_000_000 },
];

const mkLowerOk = (bindings: IRBinding[] = []): LoweringResult =>
  ({ ok: true, program: { bindings, result: '$0' } } as LoweringResult);

const mkDeps = (over: Partial<PipelineDeps> = {}): PipelineDeps => ({
  lowerSIR: (_: SIRProgram): LoweringResult => mkLowerOk(),
  emitBytes: () => new Uint8Array([0xc3, 0x01]),
  executeScript: async () => okKernel,
  buildCellFromBytes: (bytes, _): Cell => ({ id: 'cell-oc-1' as CellId, bytes }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0xde]),
  now: () => 1_700_000_100_000,
  uuid: () => '01HQ-uuid',
  ...over,
});

const mkCtx = (over: Partial<IntentContext> = {}): IntentContext => ({
  hat: mkHat(),
  logger: createInMemoryLogger(),
  ...over,
});

// ── Tests ──────────────────────────────────────────────────────────────────

describe('WI-A2: outcome emitter', () => {
  test('WI-A2-T-emit-on-success — emitter called exactly once on happy path', async () => {
    const emitter = new RecordingNatsEmitter();
    await processIntent(mkIntent(), mkCtx(), mkDeps({ outcomeEmitter: emitter }));
    expect(emitter.calls).toHaveLength(1);
  });

  test('WI-A2-T-emit-on-success — payload fields match intent + hat', async () => {
    const emitter = new RecordingNatsEmitter();
    const intent = mkIntent();
    const hat = mkHat({ hatId: 'hat-trades', domainFlag: 2 });
    await processIntent(intent, mkCtx({ hat }), mkDeps({ outcomeEmitter: emitter }));

    const p = emitter.calls[0];
    expect(p.intentId).toBe(String(intent.id));
    expect(p.domainFlag).toBe(2);
    expect(p.lexicon).toBe('trades');
    expect(p.juralCategory).toBe('obligation');
    expect(p.compositeConfidence).toBe(0.95);
    expect(p.hatId).toBe('hat-trades');
    expect(p.cellOutcomeHash).toBe('cell-oc-1');
  });

  test('WI-A2-T-no-emit-on-rejection — SIR rejection suppresses emit', async () => {
    const emitter = new RecordingNatsEmitter();
    const deps = mkDeps({
      lowerSIR: (): LoweringResult => ({ ok: false, code: 'trust_tier', message: 'denied' }),
      outcomeEmitter: emitter,
    });
    const result = await processIntent(mkIntent(), mkCtx(), deps);
    expect(result.ok).toBe(false);
    expect(emitter.calls).toHaveLength(0);
  });

  test('WI-A2-T-no-emit-on-rejection — kernel rejection suppresses emit', async () => {
    const emitter = new RecordingNatsEmitter();
    const failKernel: ScriptResult = {
      ok: false, stackDepth: 0, opcount: 0, gasUsed: 0,
      errorCode: 12, errorMessage: 'cap not held',
    };
    const deps = mkDeps({
      executeScript: async () => failKernel,
      outcomeEmitter: emitter,
    });
    const result = await processIntent(mkIntent(), mkCtx(), deps);
    expect(result.ok).toBe(false);
    expect(emitter.calls).toHaveLength(0);
  });

  test('WI-A2-T-anf-bindings-passthrough — bindings reach payload as JSON array', async () => {
    const emitter = new RecordingNatsEmitter();
    const deps = mkDeps({
      lowerSIR: (): LoweringResult => mkLowerOk(twoBindings),
      outcomeEmitter: emitter,
    });
    await processIntent(mkIntent(), mkCtx(), deps);

    const parsed: IRBinding[] = JSON.parse(emitter.calls[0].anfBindingsJson);
    expect(parsed).toHaveLength(2);
    expect(parsed[0].name).toBe('$0');
    expect(parsed[0].kind).toBe('comparison');
    expect(parsed[1].kind).toBe('timeConstraint');
    expect(parsed[1].timestamp).toBe(1_700_000_000);
  });

  test('WI-A2-T-anf-bindings-passthrough — empty bindings produce empty JSON array', async () => {
    const emitter = new RecordingNatsEmitter();
    await processIntent(mkIntent(), mkCtx(), mkDeps({ outcomeEmitter: emitter }));
    expect(emitter.calls[0].anfBindingsJson).toBe('[]');
  });

  test('no emitter — pipeline succeeds without one (backwards compat)', async () => {
    const result = await processIntent(mkIntent(), mkCtx(), mkDeps());
    expect(result.ok).toBe(true);
  });
});

```
