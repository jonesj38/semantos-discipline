---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/submit-lead-cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.526488+00:00
---

# cartridges/oddjobz/brain/src/conversation/submit-lead-cell.ts

```ts
/**
 * P3.5a — the chat-intake → standardised-store seam, wired for the
 * live bot (DECISION-P4C / Phase-3). Composes the shipped P3.x
 * pieces into one ADDITIVE, best-effort call the intake-handler
 * makes on completed intake (mirrors the de-blackbox `recordIntakeTurn`
 * try/catch — a failure here can NEVER regress the customer reply;
 * `persistLead` jsonl stays the transitional shadow).
 *
 *   agent cert  (P3.4 makeAgentCertProvider — option-2 device-pair)
 *   pipeline    (P3.1 createShellPipelineDeps pattern → real kernel)
 *   writeCell   (P3.2 makeBrainSubmitStorageAdapter → submit-intent-cell)
 *   envelope    (P3.4 assembleAcceptRomEnvelopeContext, accept_rom +
 *                the romBandCents money channel = the EXACT range the
 *                customer was shown)
 *
 * GATING (modeling fact, not a guess): AccumulatedJobState carries no
 * structured ROM range — only `estimatePresented`. So an accept_rom
 * cell is minted ONLY when an estimate was actually presented (the
 * one structured signal), with `{costMin,costMax}` reconstructed from
 * `romBandCents` (the same source the bot showed). Completed leads
 * with no estimate keep the jsonl shadow only — the plain
 * lead-propose cell modeling is explicitly deferred (post Slice-3b /
 * SD2), surfaced not guessed.
 *
 * Heavy env-gated deps (@semantos/intent processIntent, the
 * cell-engine bun kernel, @bsv via device-pair-client) are INJECTED
 * via `SubmitLeadDeps` so the orchestration is unit-tested with mocks
 * (ZERO live); the real wiring is the default impl, lazy-loaded,
 * code+rbs-verified, and only actuates at the P3.5c deploy.
 */

import type { AccumulatedJobState } from './accumulated-job-state.js';
import {
  assembleAcceptRomEnvelopeContext,
  type AgentCert,
} from './agent-cert-provider.js';
import {
  makeBrainSubmitStorageAdapter,
  type KernelResultClaim,
  type FetchLike,
} from './brain-submit-storage.js';
import { romBandCents } from './reply-generator.js';

/** Minimal Cell the pipeline hands to writeCell. */
interface PipelineCell {
  id: string;
  bytes: Uint8Array;
}

/**
 * Run the @semantos/intent pipeline for a P3.1-proven-emittable
 * Intent, with `writeCell` delegated to the caller's brain-submit
 * adapter. Injected so the unit test never loads the env-gated
 * kernel/@semantos; the default impl is the real edge pipeline.
 */
export type RunEdgePipeline = (args: {
  correlationId: string;
  /** writeCell(cell, kernelResult) — the adapter submits the
   *  assembled envelope; kernelResult is threaded from the kernel. */
  writeCell: (cell: PipelineCell, kr: KernelResultClaim) => Promise<void>;
}) => Promise<{ ok: boolean; cellId: string | null }>;

export interface SubmitLeadDeps {
  /** P3.4 agent cert (option-2 device-pair). Provisioned once. */
  getAgentCert: () => Promise<AgentCert>;
  /** Real edge pipeline (default) or a mock (tests). */
  runEdgePipeline: RunEdgePipeline;
  /** Brain REPL endpoint + bearer for submit-intent-cell. */
  brainReplUrl: string;
  brainBearer: string;
  /** Injected transport (tests mock; default global fetch). */
  fetchFn?: FetchLike;
  /** Wall clock (tests pin). */
  now?: () => number;
}

export interface SubmitLeadResult {
  readonly submitted: boolean;
  /** Why a cell was NOT minted (gating), for the best-effort log. */
  readonly skipped?: 'no_estimate_presented';
  readonly cellId?: string | null;
}

/**
 * Best-effort: on completed intake WITH an estimate presented, mint +
 * submit an `oddjobz.lead.v1` accept_rom cell to the standardised
 * store. Returns a result; THROWS only on genuine submit failure (the
 * intake-handler wraps this in try/catch like recordIntakeTurn, so a
 * throw is logged + the reply + jsonl shadow are unaffected).
 */
export async function submitLeadCell(
  state: AccumulatedJobState,
  correlationId: string,
  deps: SubmitLeadDeps,
): Promise<SubmitLeadResult> {
  if (state.estimatePresented !== true) {
    // No structured ROM signal ⇒ not an accept_rom. jsonl shadow
    // (persistLead) still captures it; structured plain-lead cell is
    // deferred (post Slice-3b / SD2).
    return { submitted: false, skipped: 'no_estimate_presented' };
  }

  const agentCert = await deps.getAgentCert();
  const { costMin, costMax } = romBandCents(state.jobType);
  // SD2 correlation: the brain `intent_action_router` matches this
  // cell to a job by substring-searching summary tokens (≥4 chars)
  // against job `customer_name`. The job is created (lead-on-contact,
  // ensure-lead-job.ts) with `customer_name = state.customerName`, so
  // the summary MUST lead with the name or the `lead→qualified` flip
  // can never match. Name first, then jobType/scope for human
  // readability.
  const namePart = state.customerName ? `${state.customerName} — ` : '';
  const summary =
    `${namePart}${state.jobType ?? 'job'} — ${state.scopeDescription ?? 'intake'}`.slice(
      0,
      240,
    );

  // The brain-submit adapter: writeCell builds + POSTs the
  // intent_cell.v1 envelope. envelopeFor closes over the agent cert +
  // the accept_rom originalIntent + the per-cell kernelResult.
  // (closure vars declared before the adapter; envelopeFor only runs
  // later during writeCell, by which point both are set.)
  let kr: KernelResultClaim | null = null;
  let lastCellId = '';
  const adapter = makeBrainSubmitStorageAdapter({
    replUrl: deps.brainReplUrl,
    bearerToken: deps.brainBearer,
    ...(deps.fetchFn ? { fetchFn: deps.fetchFn } : {}),
    envelopeFor: (_key, _bytes) => {
      const ctx = assembleAcceptRomEnvelopeContext({
        agentCert,
        correlationId,
        kernelResult: kr ?? {
          ok: true,
          opcount: 0,
          stackDepth: 0,
          gasUsed: 0,
          errorKind: null,
        },
        costMin,
        costMax,
        summary,
      });
      return { cellId: lastCellId, ...ctx };
    },
  });

  const result = await deps.runEdgePipeline({
    correlationId,
    writeCell: async (cell, kernelResult) => {
      lastCellId = cell.id;
      kr = kernelResult;
      await adapter.write(`cells/${cell.id}`, cell.bytes);
    },
  });

  return {
    submitted: result.ok,
    cellId: result.cellId,
  };
}

// ─────────────────────────────────────────────────────────────────────
// defaultRunEdgePipeline — the REAL edge pipeline, productionised
// verbatim from the proven-green P3.1 spike harness
// (tools/p3-spike-processintent.ts: ran intent_extracted → sir_built →
// sir_lowered → ir_emitted → script_executed → cell_written →
// intent_completed ok:true on rbs). @semantos/intent + the
// @semantos/cell-engine bun kernel are LAZY-imported so mock-injected
// unit tests never load them (worktree/zero-live); this default only
// actuates at the P3.5c deploy. writeCell + buildCellFromBytes thread
// the kernelResult out to the caller's brain-submit writeCell.
// ─────────────────────────────────────────────────────────────────────

const AUTHORING_FRAME = new Uint8Array([0x51]); // OP_1 → TRUE

function deriveCellId(bytes: Uint8Array, uuid: () => string): string {
  const sizeHex = bytes.byteLength.toString(16).padStart(6, '0');
  const bytePrefix = Array.from(bytes.slice(0, 4))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  return `cell-${sizeHex}-${bytePrefix}-${uuid().slice(0, 8)}`;
}

function mapKernelResult(r: {
  success: boolean;
  opcodeCount: number;
  error: string | null;
}): KernelResultClaim {
  return r.success
    ? { ok: true, opcount: r.opcodeCount, stackDepth: 0, gasUsed: 0, errorKind: null }
    : { ok: false, opcount: r.opcodeCount, stackDepth: 0, gasUsed: 0, errorKind: r.error ?? 'kernel_failed' };
}

/** The shipped real pipeline (default `SubmitLeadDeps.runEdgePipeline`). */
export const defaultRunEdgePipeline: RunEdgePipeline = async ({
  correlationId,
  writeCell,
}) => {
  const { loadCellEngine } = await import(
    '@semantos/cell-engine/bindings/bun/loader'
  );
  const { emit: emitIR } = await import('@semantos/semantos-ir');
  const intent = await import('@semantos/intent');
  // The loader resolves the kernel WASM from `import.meta.dir` of its
  // OWN source file. But the intake-handler ships as a Bun bundle, so
  // the loader is inlined and `import.meta.dir` becomes the *bundle*
  // dir (…/cartridges/oddjobz/brain), not the cell-engine package — its
  // `PACKAGE_ROOT/dist/cell-engine.wasm` fallback then ENOENTs and the
  // best-effort seam silently no-ops. `ODDJOBZ_CELL_ENGINE_WASM` is
  // the explicit deploy seam: an absolute path to the kernel WASM
  // (e.g. /opt/semantos-core/core/cell-engine/zig-out/bin/cell-engine.wasm).
  // Unset ⇒ loader self-resolution (correct for unbundled/dev/tests),
  // so this is additive and changes nothing where the bundle isn't
  // relocated. No hardcoded path in the cartridge — surfaced, not guessed.
  const wasmPath = process.env.ODDJOBZ_CELL_ENGINE_WASM;
  const engine = (await loadCellEngine(
    wasmPath ? { wasmPath } : undefined,
  )) as unknown as {
    executeScript(
      lock: Uint8Array,
      unlock?: Uint8Array,
    ): { success: boolean; opcodeCount: number; error: string | null };
  };
  const uuid = () => crypto.randomUUID();
  let kr: KernelResultClaim = {
    ok: true,
    opcount: 0,
    stackDepth: 0,
    gasUsed: 0,
    errorKind: null,
  };
  let cellId: string | null = null;

  const deps = {
    emitBytes: (ir: unknown) =>
      emitIR(ir as Parameters<typeof emitIR>[0]),
    async executeScript(_bytes: Uint8Array) {
      try {
        kr = mapKernelResult(engine.executeScript(AUTHORING_FRAME));
      } catch (e) {
        kr = {
          ok: false,
          opcount: 0,
          stackDepth: 0,
          gasUsed: 0,
          errorKind: e instanceof Error ? e.message : String(e),
        };
      }
      return kr;
    },
    buildCellFromBytes: (bytes: Uint8Array) => {
      cellId = deriveCellId(bytes, uuid);
      return { id: cellId, bytes };
    },
    writeCell: async (cell: { id: string; bytes: Uint8Array }) => {
      await writeCell({ id: cell.id, bytes: cell.bytes }, kr);
    },
    sign: async (_p: Uint8Array) => new Uint8Array(64),
    now: () => Date.now(),
    uuid,
  };

  const hat = intent.buildHatContext({
    identity: {
      getIdentity: () => ({
        id: 'oddjobz-agent',
        certId: 'cert-oddjobz-agent',
        activeHatId: 'oddjobz-agent',
        hats: [{ id: 'oddjobz-agent', certId: 'cert-oddjobz-agent', capabilities: [5] }],
      }),
      getActiveHat: () => ({ id: 'oddjobz-agent', certId: 'cert-oddjobz-agent', capabilities: [5] }),
    },
    extension: { extensionId: 'oddjobz', domainFlag: 0x0001_0101 },
    resolveMaxTrustClass: intent.defaultTrustCeiling,
    requireCert: false,
  });

  // The proven-emittable Intent (P3.1: jural/declaration + the G1
  // comparison constraint so real lowerSIR→emit is non-degenerate).
  // The brain-side accept_rom semantics ride on the ENVELOPE's
  // originalIntent (assembleAcceptRomEnvelopeContext), not this
  // SIR-lowering Intent.
  const theIntent = {
    id: uuid(),
    correlationId,
    summary: 'oddjobz lead intake → accept_rom cell',
    category: { lexicon: 'jural', category: 'declaration' },
    taxonomy: { what: 'oddjobz.lead.v1', how: 'oddjobz.accept_rom', why: 'chat-intake' },
    action: 'transition',
    constraints: [{ kind: 'comparison', op: '>', field: 'amount', value: 500 }],
    confidence: 1.0,
    source: 'shell',
  };

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const result = await intent.processIntent(theIntent as any, {
    hat,
    logger: intent.createJsonlStderrLogger(),
    correlationId: correlationId as never,
  }, deps as never);

  return { ok: (result as { ok?: boolean }).ok === true, cellId };
};

```
