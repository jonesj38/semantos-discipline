---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/intent-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.584427+00:00
---

# tests/gates/intent-pipeline.test.ts

```ts
/**
 * Intent pipeline gate — end-to-end exercise of runtime/intent.
 *
 * Gates covered:
 *   G1  parseCommand → shell-to-intent maps `transition obj --capability 5`
 *       to a well-formed Intent with target + SIRConstraint
 *   G2  Full happy path: ShellCommand → Intent → buildSIR → lowerSIR →
 *       emit bytes → (stub) executeScript → (stub) writeCell; exactly
 *       7 forward stage events fire in order
 *   G3  All stage events on a turn share one correlationId
 *   G4  Kernel rejection short-circuits: emits intent_rejected{kernel},
 *       no cell_written; IntentResult.cell === null
 *   G5  SIR rejection short-circuits at lowerSIR: emits
 *       intent_rejected{sir}, no ir_emitted / script_executed /
 *       cell_written
 *   G6  Read-only verbs (inspect/list/whoami) return 'bypassed' —
 *       they do NOT run the pipeline
 *   G7  Emitted byte stream is a real non-empty Uint8Array — end-to-end
 *       with the real @semantos/semantos-ir emit() function, not a stub
 *
 * Gates NOT covered (Slice 3 scope):
 *   - Real cell-engine executeScript wiring
 *   - Real StorageAdapter writeCell wiring
 *   - Real BRC-42 signing for Receipt.resultSig
 *   These are stubbed here; the pipeline's handling of them is tested
 *   structurally via the PipelineDeps contract.
 */

import { describe, test, expect } from 'bun:test';
import { parseCommand } from '@semantos/shell/parser';
import {
  runShellIntent,
  defaultEmitBytes,
  type ShellIntentCtxLike,
  type RunShellIntentOptions,
} from '../../runtime/shell/src/intent-adapters/run-shell-intent';
import { shellCommandToIntent } from '../../runtime/shell/src/intent-adapters/shell-to-intent';
import {
  createInMemoryLogger,
  type PipelineDeps,
  type Cell,
  type CellId,
  type ScriptResult,
  type HatLike,
  type IdentityLike,
  type IdentityServiceLike,
} from '@semantos/intent';

// ── Fixtures ────────────────────────────────────────────────

const mkFacet = (over: Partial<HatLike> = {}): HatLike => ({
  id: 'hat-gate-test',
  certId: 'cert-gate-test',
  capabilities: [5],
  ...over,
});

const mkIdentityService = (facet: HatLike): IdentityServiceLike => {
  const identity: IdentityLike = {
    id: 'id-gate-test',
    activeHatId: facet.id,
    hats: [facet],
  };
  return {
    getIdentity: () => identity,
    getActiveHat: () => facet,
  };
};

const mkCtx = (over: Partial<ShellIntentCtxLike> = {}): ShellIntentCtxLike => ({
  identity: mkIdentityService(mkFacet()),
  extension: { extensionId: 'gate-test', domainFlag: 1 },
  ...over,
});

const okKernel: ScriptResult = { ok: true, stackDepth: 0, opcount: 3, gasUsed: 10 };
const failKernel: ScriptResult = {
  ok: false,
  stackDepth: 0,
  opcount: 0,
  gasUsed: 0,
  errorCode: 12,
  errorMessage: 'capability not held at runtime',
};

const mkDeps = (over: Partial<PipelineDeps> = {}): PipelineDeps => ({
  // Real IR → bytes using @semantos/semantos-ir emit().
  emitBytes: defaultEmitBytes,
  // Stub kernel. Slice 3 replaces with real cell-engine.executeScript.
  executeScript: async () => okKernel,
  buildCellFromBytes: (bytes): Cell => ({
    id: ('cell-' + Math.random().toString(16).slice(2, 8)) as CellId,
    bytes,
  }),
  writeCell: async () => {},
  sign: () => new Uint8Array([0xde, 0xad, 0xbe, 0xef]),
  now: () => Date.now(),
  uuid: () => 'gen-' + Math.random().toString(16).slice(2, 10),
  ...over,
});

const mkOpts = (over: Partial<RunShellIntentOptions> = {}): RunShellIntentOptions => ({
  generateId: () => 'intent-gate-test',
  deps: mkDeps(),
  logger: createInMemoryLogger(),
  ...over,
});

// ── G1: parseCommand → Intent shape ─────────────────────────

describe('G1 — parseCommand → shell-to-intent', () => {
  test('transition verb with objectId + --capability produces typed Intent', () => {
    const cmd = parseCommand(['transition', 'obj-42', '--capability', '5']);
    const intent = shellCommandToIntent(cmd, { generateId: () => 'i1' });

    expect(intent).not.toBeNull();
    expect(intent!.action).toBe('transition');
    expect(intent!.category).toEqual({ lexicon: 'jural', category: 'power' });
    expect(intent!.target).toEqual({ objectId: 'obj-42' });
    expect(intent!.source).toBe('shell');
    expect(intent!.confidence).toBe(1.0);
    expect(intent!.constraints).toEqual([
      { kind: 'capability', required: 5, name: 'cap-5' },
    ]);
  });
});

// ── G2 + G3 + G7: Full happy path ───────────────────────────

describe('G2+G3+G7 — happy path', () => {
  test('emits 7 forward stage events in order with one correlationId and real bytes', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-42', '--capability', '5']);
    const deps = mkDeps();

    const result = await runShellIntent(cmd, mkCtx(), { ...mkOpts(), logger, deps });

    expect(result.kind).toBe('ran');
    if (result.kind !== 'ran') return;
    expect(result.result.ok).toBe(true);

    // G2 — ordered forward events
    expect(logger.events.map(e => e.stage)).toEqual([
      'intent_extracted',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'cell_written',
      'intent_completed',
    ]);

    // G3 — single correlation ID across the turn
    const ids = new Set(logger.events.map(e => e.correlationId));
    expect(ids.size).toBe(1);
    expect(result.result.correlationId).toBe(logger.events[0]!.correlationId);

    // G7 — real ir_emitted byteLength > 0 (emit() produced actual opcodes)
    const irEmit = logger.events.find(e => e.stage === 'ir_emitted')!;
    const byteLength = irEmit.data.byteLength as number;
    expect(byteLength).toBeGreaterThan(0);
  });

  test('receipt signedBy matches active hat', async () => {
    const cmd = parseCommand(['transition', 'obj-42', '--capability', '5']);
    const result = await runShellIntent(cmd, mkCtx(), mkOpts());
    if (result.kind !== 'ran') throw new Error('expected ran');
    expect(result.result.receipt.signedBy).toBe('hat-gate-test');
  });
});

// ── G4: Kernel rejection short-circuit ──────────────────────

describe('G4 — kernel rejection', () => {
  test('intent_rejected{kernel} fires; no cell_written; cell === null', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-42', '--capability', '5']);
    const deps = mkDeps({ executeScript: async () => failKernel });

    const out = await runShellIntent(cmd, mkCtx(), { ...mkOpts(), logger, deps });
    if (out.kind !== 'ran') throw new Error('expected ran');

    const stages = logger.events.map(e => e.stage);
    expect(stages).toEqual([
      'intent_extracted',
      'sir_built',
      'sir_lowered',
      'ir_emitted',
      'script_executed',
      'intent_rejected',
    ]);
    expect(out.result.ok).toBe(false);
    expect(out.result.rejection?.stage).toBe('kernel');
    expect(out.result.cell).toBeNull();
  });
});

// ── G5: SIR rejection short-circuit ─────────────────────────

describe('G5 — SIR rejection', () => {
  test('intent_rejected{sir} fires at lowerSIR; no downstream events', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['transition', 'obj-42', '--capability', '5']);
    const deps = mkDeps({
      lowerSIR: () => ({
        ok: false,
        code: 'trust_tier_exceeded',
        message: 'authoritative requires formal proof',
      }),
    });

    const out = await runShellIntent(cmd, mkCtx(), { ...mkOpts(), logger, deps });
    if (out.kind !== 'ran') throw new Error('expected ran');

    expect(logger.events.map(e => e.stage)).toEqual([
      'intent_extracted',
      'sir_built',
      'intent_rejected',
    ]);
    expect(out.result.ok).toBe(false);
    expect(out.result.rejection?.stage).toBe('sir');
    expect(out.result.rejection?.code).toBe('trust_tier_exceeded');
    expect(out.result.cell).toBeNull();
  });
});

// ── G6: read-only verbs bypass the pipeline ─────────────────

describe('G6 — read-only verbs bypass', () => {
  test('inspect returns { kind: "bypassed" } without running pipeline', async () => {
    const logger = createInMemoryLogger();
    const cmd = parseCommand(['inspect', 'obj-42']);
    const out = await runShellIntent(cmd, mkCtx(), { ...mkOpts(), logger });
    expect(out.kind).toBe('bypassed');
    if (out.kind === 'bypassed') {
      expect(out.reason).toContain('inspect');
    }
    // No pipeline stage events should have fired.
    expect(logger.events).toHaveLength(0);
  });

  test('list bypasses too', async () => {
    const cmd = parseCommand(['list']);
    const out = await runShellIntent(cmd, mkCtx(), mkOpts());
    expect(out.kind).toBe('bypassed');
  });

  test('whoami bypasses', async () => {
    const cmd = parseCommand(['whoami']);
    const out = await runShellIntent(cmd, mkCtx(), mkOpts());
    expect(out.kind).toBe('bypassed');
  });
});

```
