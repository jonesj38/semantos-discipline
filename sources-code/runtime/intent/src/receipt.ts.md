---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/receipt.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.342238+00:00
---

# runtime/intent/src/receipt.ts

```ts
/**
 * buildReceipt — canonical evidence-chain entry for an executed intent.
 *
 * The Receipt is the cryptographic artifact that proves a specific
 * hat authored a specific cell at a specific time with a specific
 * kernel result. It travels alongside the cell into storage and out
 * to downstream consumers (governance UI, network peers, audit).
 *
 * Slice 1: this is the converger surface. host.exec's existing
 * receipt format (see runtime/shell/src/host-exec/) adopts this type
 * in Slice 3, producing a single `Receipt` type across host.exec and
 * the intent pipeline. See docs/INTENT-PIPELINE.md open-question #1.
 */

import type {
  Receipt,
  HatContext,
  Cell,
  ScriptResult,
  CorrelationId,
} from './types';

export interface BuildReceiptInput {
  hat: HatContext;
  cell: Cell | null;
  kernelResult: ScriptResult;
  correlationId: CorrelationId;
  /** When processIntent received the intent. */
  issuedAt: number;
  /** When execution completed. */
  finishedAt: number;
  /**
   * Signature producer. Injected so this module stays decoupled from
   * any specific signing stack. May be sync (stub) or async (real
   * BRC-42 signers — StubSigner, BsvSdkSigner — return Promise).
   */
  sign: (preimage: Uint8Array) => Uint8Array | Promise<Uint8Array>;
}

/**
 * Canonical preimage over the executed intent. Order matters —
 * changing it breaks signature compatibility across the evidence
 * chain. Keep this stable.
 */
function preimage(input: BuildReceiptInput): Uint8Array {
  const parts = [
    input.correlationId,
    input.hat.hatId,
    input.cell?.id ?? '',
    String(input.kernelResult.ok),
    String(input.kernelResult.opcount),
    String(input.issuedAt),
    String(input.finishedAt),
  ];
  return new TextEncoder().encode(parts.join('\x1f'));
}

export async function buildReceipt(input: BuildReceiptInput): Promise<Receipt> {
  const resultSig = await Promise.resolve(input.sign(preimage(input)));
  return {
    correlationId: input.correlationId,
    signedBy: input.hat.hatId,
    resultSig,
    issuedAt: input.issuedAt,
    finishedAt: input.finishedAt,
  };
}

```
