---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/pipeline.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.344381+00:00
---

# runtime/intent/src/pipeline.ts

```ts
/**
 * processIntent — the pipeline orchestrator.
 *
 * Linear flow, no branching complexity:
 *
 *   generate/propagate correlationId
 *   emit intent_extracted
 *   buildHatContext (precondition — no stage event; throws if missing)
 *   buildSIR                     → emit sir_built
 *   lowerSIR                     → on reject: intent_rejected{stage:sir}
 *                                  on ok:     emit sir_lowered
 *   emit bytes                   → emit ir_emitted
 *   executeScript                → emit script_executed
 *                                  on reject: intent_rejected{stage:kernel}
 *   writeCell                    → emit cell_written
 *   buildReceipt + deriveUIHint  → emit intent_completed
 *
 * Every stage wrapped in a runStage() helper that measures durationMs.
 * Rejections short-circuit — no further happy-path events fire.
 *
 * Kernel/storage/emit/sign are injected through PipelineDeps so this
 * module stays pure and unit-testable. The concrete wiring lives at
 * the edge of the runtime (Slice 1.9 / 1.10 gate test).
 *
 * See docs/INTENT-PIPELINE.md §"The pipeline" and §"Observability".
 */

import type {
  SIRProgram,
  LoweringResult,
} from '@semantos/semantos-sir';
import { lowerSIR as defaultLowerSIR } from '@semantos/semantos-sir';
import type {
  Intent,
  IntentContext,
  IntentResult,
  IntentRejection,
  StageEvent,
  StageName,
  CorrelationId,
  IntentId,
  Cell,
  ScriptResult,
  Logger,
} from './types';
import { buildSIR } from './sir-builder';
import { buildReceipt } from './receipt';
import { deriveUIHint } from './ui-hint';
import type { NatsEmitter } from './outcome-emitter';

// Minimal IR program surface the pipeline needs — structural, not
// nominal, so we don't drag the whole IR type graph into this file.
// Real IRProgram type is in @semantos/semantos-sir's re-export chain.
type IRProgramLike = unknown;

export interface PipelineDeps {
  /** SIR → IR lowering. Defaults to the real lowerSIR from @semantos/semantos-sir. */
  lowerSIR?: (program: SIRProgram) => LoweringResult;
  /** IR → bytes. Injected; concrete impl lives in @semantos/semantos-ir. */
  emitBytes: (ir: IRProgramLike) => Uint8Array;
  /** Run bytes on the cell engine. */
  executeScript: (bytes: Uint8Array) => Promise<ScriptResult>;
  /**
   * Package kernel-produced bytes into a Cell. The kernel produces
   * the opcodes; the Cell is the header-wrapped durable artifact.
   */
  buildCellFromBytes: (bytes: Uint8Array, kernelResult: ScriptResult) => Cell;
  /** Persist cell via StorageAdapter (cloud / device / USB / octave — pipeline doesn't care). */
  writeCell: (cell: Cell) => Promise<void>;
  /**
   * Sign the receipt preimage. May be sync (stub/test signers) or
   * async (real BRC-42 signers — StubSigner, BsvSdkSigner, anything
   * that returns Promise<Uint8Array>). The pipeline awaits either way.
   */
  sign: (preimage: Uint8Array) => Uint8Array | Promise<Uint8Array>;
  /** Wall-clock ms for receipt timestamps. */
  now: () => number;
  /** UUID v7 generator for correlation IDs. */
  uuid: () => string;
  /**
   * WI-A2 — optional NATS emitter. When provided, fires an `intent_outcome`
   * event after the cell is written. Best-effort: the pipeline has already
   * committed to LMDB/Postgres before this fires.
   */
  outcomeEmitter?: NatsEmitter;
}

// ── Stage timing helper ─────────────────────────────────────

interface StageEventBase {
  correlationId: CorrelationId;
  intentId: IntentId | null;
  hatId: string | null;
  source: Intent['source'];
}

function mkEmit(logger: Logger, base: StageEventBase) {
  return (stage: StageName, durationMs: number, data: Record<string, unknown>): void => {
    const ev: StageEvent = {
      ts: new Date().toISOString(),
      correlationId: base.correlationId,
      intentId: base.intentId,
      stage,
      durationMs,
      hatId: base.hatId,
      source: base.source,
      data,
    };
    logger.emit(ev);
  };
}

async function runStage<T>(fn: () => Promise<T> | T): Promise<{ value: T; durationMs: number }> {
  const start = performance.now();
  const value = await fn();
  const durationMs = performance.now() - start;
  return { value, durationMs };
}

// ── processIntent ───────────────────────────────────────────

function asCorrelationId(s: string): CorrelationId {
  return s as CorrelationId;
}

export async function processIntent(
  intent: Intent,
  ctx: IntentContext,
  deps: PipelineDeps,
): Promise<IntentResult> {
  const correlationId: CorrelationId =
    intent.correlationId ?? ctx.correlationId ?? asCorrelationId(deps.uuid());

  const base: StageEventBase = {
    correlationId,
    intentId: intent.id,
    hatId: ctx.hat.hatId,
    source: intent.source,
  };
  const emit = mkEmit(ctx.logger, base);
  const lowerSIR = deps.lowerSIR ?? defaultLowerSIR;

  const issuedAt = deps.now();

  // 1. intent_extracted — the producer's work is done.
  emit('intent_extracted', 0, {
    confidence: intent.confidence,
    producerMeta: intent.producerMeta,
    companionOf: intent.companionOf,
  });

  // 2. sir_built
  const { value: sirProgram, durationMs: sirBuildMs } = await runStage(() =>
    buildSIR(intent, ctx.hat),
  );
  emit('sir_built', sirBuildMs, {
    trustClass: sirProgram.programGovernance.trustClass,
    domainBinding: sirProgram.programGovernance.domainBinding?.flag,
    constraintCount: intent.constraints.length,
  });

  // 3. sir_lowered (static check — may reject)
  const { value: lowered, durationMs: lowerMs } = await runStage(() => lowerSIR(sirProgram));
  if (!lowered.ok) {
    return reject(
      { stage: 'sir', code: lowered.code, message: lowered.message },
      intent,
      correlationId,
      ctx,
      deps,
      emit,
      issuedAt,
    );
  }
  emit('sir_lowered', lowerMs, {
    allowedEmitOps:
      sirProgram.programGovernance.allowedEmitOps?.slice() ?? [],
    identityCertId: ctx.hat.certId,
  });

  // 4. ir_emitted — IR → bytes
  const { value: bytes, durationMs: emitMs } = await runStage(() =>
    deps.emitBytes(lowered.program),
  );
  emit('ir_emitted', emitMs, {
    byteLength: bytes.byteLength,
  });

  // 5. script_executed (dynamic check — kernel may reject)
  const { value: kernelResult, durationMs: execMs } = await runStage(() =>
    deps.executeScript(bytes),
  );
  emit('script_executed', execMs, {
    kernelOk: kernelResult.ok,
    opcount: kernelResult.opcount,
    stackDepth: kernelResult.stackDepth,
    gasUsed: kernelResult.gasUsed,
  });
  if (!kernelResult.ok) {
    return reject(
      {
        stage: 'kernel',
        code: kernelResult.errorCode != null ? String(kernelResult.errorCode) : 'kernel_error',
        message: kernelResult.errorMessage ?? 'kernel rejected script',
      },
      intent,
      correlationId,
      ctx,
      deps,
      emit,
      issuedAt,
      kernelResult,
    );
  }

  // 6. cell_written — storage adapter is a black box (cloud/device/USB/octave)
  const cell = deps.buildCellFromBytes(bytes, kernelResult);
  const { durationMs: writeMs } = await runStage(() => deps.writeCell(cell));
  emit('cell_written', writeMs, {
    cellId: cell.id,
  });

  // WI-A2 — emit intent_outcome after cell lands, before receipt.
  if (deps.outcomeEmitter) {
    await deps.outcomeEmitter.emitIntentOutcome({
      intentId: String(intent.id),
      domainFlag: ctx.hat.domainFlag,
      lexicon: intent.category.lexicon,
      juralCategory: String(intent.category.category),
      anfBindingsJson: JSON.stringify(lowered.program.bindings),
      compositeConfidence: intent.confidence,
      cellOutcomeHash: String(cell.id),
      tsMs: deps.now(),
      hatId: ctx.hat.hatId,
    });
  }

  // 7. Receipt + UIHint + intent_completed
  const finishedAt = deps.now();
  const receipt = await buildReceipt({
    hat: ctx.hat,
    cell,
    kernelResult,
    correlationId,
    issuedAt,
    finishedAt,
    sign: deps.sign,
  });
  const uiHint = deriveUIHint({ intent, kernelResult });

  emit('intent_completed', finishedAt - issuedAt, {
    ok: true,
    presentation: uiHint.presentation,
    invalidateCount: uiHint.invalidate.length,
  });

  return {
    ok: true,
    correlationId,
    cell,
    kernelResult,
    receipt,
    uiHint,
  };
}

// ── Rejection helper ────────────────────────────────────────

async function reject(
  rejection: IntentRejection,
  intent: Intent,
  correlationId: CorrelationId,
  ctx: IntentContext,
  deps: PipelineDeps,
  emit: (stage: StageName, durationMs: number, data: Record<string, unknown>) => void,
  issuedAt: number,
  kernelResult?: ScriptResult,
): Promise<IntentResult> {
  emit('intent_rejected', 0, {
    stage: rejection.stage,
    code: rejection.code,
    message: rejection.message,
  });

  const finishedAt = deps.now();
  const kr: ScriptResult =
    kernelResult ?? { ok: false, stackDepth: 0, opcount: 0, gasUsed: 0 };

  // Rejected intents still get a receipt — it proves the rejection
  // happened and ties it to the hat + correlationId for audit.
  const receipt = await buildReceipt({
    hat: ctx.hat,
    cell: null,
    kernelResult: kr,
    correlationId,
    issuedAt,
    finishedAt,
    sign: deps.sign,
  });

  const uiHint = deriveUIHint({ intent, kernelResult: kr, rejection });

  return {
    ok: false,
    correlationId,
    cell: null,
    kernelResult: kr,
    receipt,
    uiHint,
    rejection,
  };
}

```
