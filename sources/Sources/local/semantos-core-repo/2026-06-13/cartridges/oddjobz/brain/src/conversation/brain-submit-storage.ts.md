---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/brain-submit-storage.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.519306+00:00
---

# cartridges/oddjobz/brain/src/conversation/brain-submit-storage.ts

```ts
/**
 * P3.2 — brain-submit StorageAdapter (DECISION-P4C / Phase-3).
 *
 * The `createShellPipelineDeps` `writeCell(cell)` seam normally hands
 * raw kernel bytes to a key/value `StorageAdapter`. The standardised
 * substrate store is reached differently: the edge assembles a full
 * `oddjobz.intent_cell.v1` envelope and POSTs the brain REPL verb
 * `submit-intent-cell --envelope <base64-json>` over `/api/v1/repl`
 * → `intent_cells.submit` (cap `cap.oddjobz.write_customer`) →
 * `intent_action_router` → `IntentCellLmdbStore`. The brain stays
 * generic (DECISION-A3 Option C: it never learns anything
 * oddjobz-specific — it just validates + re-runs the kernel over a
 * finished envelope).
 *
 * Grounded contracts (origin/main):
 *  - `repl_http.zig`: `POST /api/v1/repl`,
 *    `Authorization: Bearer <hex64>`, body `{"cmd":"<repl line>"}`.
 *  - `repl.zig`: `submit-intent-cell --envelope <base64-json>`.
 *  - `intent_cells_handler.zig` parseEnvelope: `kind` must equal
 *    `"oddjobz.intent_cell.v1"`, `version` must equal `1`, `cellId`
 *    required, + the `docs/spec/oddjobz-intent-cell-v1.md` fields.
 *
 * Dependency-light + transport-injected on purpose: NO
 * `@semantos/intent` import (env-gated), so the envelope-assembly +
 * request contract is unit-testable with a mock transport in any
 * context. The real live POST is P3.5 (operator-approved); writing a
 * cell to a running brain's IntentCellLmdbStore is a live substrate
 * change and is deliberately NOT exercised here.
 *
 * The signing identity in the envelope (`hatId`/`certId`) is supplied
 * by the caller's `EnvelopeContext` — its real provenance is the
 * P3.3 operator sub-decision (brain sign-callback vs edge child-cert),
 * deliberately parameterised so P3.2 stays decision-independent.
 */

export const ENVELOPE_KIND = 'oddjobz.intent_cell.v1' as const;
export const ENVELOPE_VERSION = 1 as const;

/** Phone/edge-claimed kernel result (the brain re-runs + reconciles). */
export interface KernelResultClaim {
  readonly ok: boolean;
  readonly opcount: number;
  readonly stackDepth: number;
  readonly gasUsed: number;
  readonly errorKind: string | null;
}

/** The non-byte context the pipeline has at submit time but does NOT
 *  pass through `writeCell(cell)` — the caller (which holds the Intent
 *  + hat) closes over it and supplies it per cell. */
export interface EnvelopeContext {
  /** Operator root-cert id (32 lowercase hex). P3.3 decides its real
   *  provenance; P3.2 takes it as given. */
  readonly hatId: string;
  /** Child cert id under the operator chain (hex). */
  readonly certId: string;
  readonly correlationId: string;
  readonly kernelResult: KernelResultClaim;
  readonly originalIntent: {
    readonly summary: string;
    /** One of ExtensionGrammar.oddjobz.actionVerbs (e.g. accept_rom). */
    readonly action: string;
    /** Stringified {what,how,why}. */
    readonly taxonomyJson: string;
    /** Stringified {jobId?,customerId?,costMin,costMax,currency} —
     *  the U1 acceptRomTargetJson money channel. Optional per spec. */
    readonly targetJson?: string;
  };
}

export interface IntentCellEnvelope {
  readonly kind: typeof ENVELOPE_KIND;
  readonly version: typeof ENVELOPE_VERSION;
  readonly cellId: string;
  /** base64 of the OIR opcode stream. */
  readonly opcodeBytes: string;
  readonly hatId: string;
  readonly certId: string;
  readonly correlationId: string;
  readonly kernelResult: KernelResultClaim;
  readonly originalIntent: EnvelopeContext['originalIntent'];
}

function toBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}

/**
 * Assemble the `oddjobz.intent_cell.v1` envelope the brain's
 * `parseEnvelope` accepts. `cellId`/`opcodeBytes` come from the
 * kernel-produced Cell; everything else from the caller's context.
 */
export function buildIntentCellEnvelope(
  cellId: string,
  opcode: Uint8Array,
  ctx: EnvelopeContext,
): IntentCellEnvelope {
  if (!cellId) throw new Error('intent-cell envelope: cellId required');
  return {
    kind: ENVELOPE_KIND,
    version: ENVELOPE_VERSION,
    cellId,
    opcodeBytes: toBase64(opcode),
    hatId: ctx.hatId,
    certId: ctx.certId,
    correlationId: ctx.correlationId,
    kernelResult: ctx.kernelResult,
    originalIntent: ctx.originalIntent,
  };
}

/** Injected transport — the global `fetch` shape, mockable in tests. */
export type FetchLike = (
  url: string,
  init: {
    method: string;
    headers: Record<string, string>;
    body: string;
  },
) => Promise<{ status: number; text: () => Promise<string> }>;

/** Minimal StorageAdapter slice the pipeline's `writeCell` uses. */
export interface WriteOnlyStorageAdapter {
  write(key: string, data: Uint8Array): Promise<void>;
}

export interface BrainSubmitStorageInput {
  /** Brain REPL endpoint, e.g. https://oddjobtodd.info/api/v1/repl */
  readonly replUrl: string;
  /** Bearer token (hex64) issued by the brain at boot. */
  readonly bearerToken: string;
  /** Per-cell envelope context (the caller closes over Intent+hat). */
  readonly envelopeFor: (key: string, bytes: Uint8Array) => EnvelopeContext & {
    cellId: string;
  };
  /** Injected transport; defaults to global fetch. */
  readonly fetchFn?: FetchLike;
}

/** Compose the `{"cmd": "..."}` REPL request body for an envelope. */
export function submitCellReplBody(env: IntentCellEnvelope): string {
  const b64 = Buffer.from(JSON.stringify(env), 'utf8').toString('base64');
  return JSON.stringify({ cmd: `submit-intent-cell --envelope ${b64}` });
}

/**
 * A `StorageAdapter.write`-shaped function that, instead of a local
 * key/value put, assembles the envelope and submits it to the brain
 * via the cap-gated REPL path. `read`/`exists`/`list` are intentionally
 * absent — the pipeline's `writeCell` only calls `write`, and a
 * brain-submit sink has no local readback (the store is the brain's).
 */
export function makeBrainSubmitStorageAdapter(
  input: BrainSubmitStorageInput,
): WriteOnlyStorageAdapter {
  const fetchFn =
    input.fetchFn ??
    ((url, init) =>
      (globalThis.fetch as unknown as FetchLike)(url, init));
  return {
    async write(key: string, data: Uint8Array): Promise<void> {
      const { cellId, ...ctx } = input.envelopeFor(key, data);
      const env = buildIntentCellEnvelope(cellId, data, ctx);
      const res = await fetchFn(input.replUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${input.bearerToken}`,
        },
        body: submitCellReplBody(env),
      });
      if (res.status < 200 || res.status >= 300) {
        const body = await res.text().catch(() => '');
        throw new Error(
          `submit-intent-cell HTTP ${res.status}: ${body.slice(0, 300)}`,
        );
      }
      // The brain returns a typed result/failure envelope in the REPL
      // body; surface a non-ok submit so the pipeline routes it as a
      // write failure rather than a silent drop.
      const text = await res.text();
      if (/"error_kind"|"ok"\s*:\s*false|envelope_invalid|cap_/i.test(text)) {
        throw new Error(`submit-intent-cell rejected: ${text.slice(0, 300)}`);
      }
    },
  };
}

```
