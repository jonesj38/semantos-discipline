---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/lifecycle-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.497897+00:00
---

# packages/cdm/cdm/src/lifecycle/lifecycle-facade.ts

```ts
/**
 * `CDMLifecycleEngine` — public facade.
 *
 * Glue layer that:
 *   1. Validates the trade event via `event-reducer`.
 *   2. Runs the kernel policy gate (`policy-gate.ts`).
 *   3. Builds the event cell (`cell-builder.ts`).
 *   4. Emits the resulting `LifecycleEffectEvent` onto the persistence
 *      bus (`persistence.ts`).
 *   5. Optionally emits an anchor tx for terminal events.
 *
 * The shape of the public API is preserved byte-identical with the
 * pre-refactor `lifecycle.ts` so existing call sites
 * (`shell-handler.ts`, demos, gate tests) continue to work without a
 * single import change.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import type {
  AnchorEmitter,
  PolicyResult,
  PolicyRuntime,
} from '@semantos/policy-runtime';

import type {
  CDMEventType,
  CDMLifecycleEvent,
  CDMLifecycleState,
  CDMPartyRole,
  CDMProduct,
  CloseOutResult,
  Result,
} from '../types';

import { buildEventCell } from './cell-builder';
import { reduceTradeEvent } from './event-reducer';
import {
  closeOutNetPortfolio,
  partialTerminateProduct,
} from './termination';
import { novateProduct } from './novation';
import { runPolicyGate } from './policy-gate';
import { emitLifecycleEvent } from './persistence';
import {
  canTransition as canTransitionFn,
  isTerminalEvent,
  validEventsFor,
  type TradeEvent,
  type TradeEventPayload,
} from './trade-events';

export interface CDMLifecycleOptions {
  /** PolicyRuntime for kernel-level policy enforcement. If omitted, policies are not enforced. */
  runtime?: PolicyRuntime;
  /** AnchorEmitter for terminal event anchoring. If omitted, no anchor tx is emitted. */
  anchorEmitter?: AnchorEmitter;
}

export interface ExecuteEventOk {
  product: CDMProduct;
  event: CDMLifecycleEvent;
  cell: Uint8Array;
  policyResults?: PolicyResult[];
  anchorTxId?: string;
}

export interface NovateOk {
  product: CDMProduct;
  transferRecord: import('@semantos/core/types/transfer.js').TransferRecord;
  event: CDMLifecycleEvent;
}

export interface PartialTerminateOk {
  product: CDMProduct;
  event: CDMLifecycleEvent;
}

export class CDMLifecycleEngine {
  private readonly runtime?: PolicyRuntime;
  private readonly anchorEmitter?: AnchorEmitter;

  constructor(options?: CDMLifecycleOptions) {
    this.runtime = options?.runtime;
    this.anchorEmitter = options?.anchorEmitter;
  }

  // ── Read-only queries ───────────────────────────────────────

  /** Check if a transition is valid from the given state. */
  canTransition(state: CDMLifecycleState, eventType: CDMEventType): boolean {
    return canTransitionFn(state, eventType);
  }

  /** Get the list of valid event types for a given state. */
  getValidEvents(state: CDMLifecycleState): CDMEventType[] {
    return validEventsFor(state);
  }

  // ── Mutating operations ─────────────────────────────────────

  /**
   * Execute a lifecycle event — validates transition, enforces policy
   * through kernel, builds a new cell, emits anchor tx for terminal
   * events, returns updated product.
   *
   * Public API preserved byte-identical with the pre-refactor signature.
   */
  async executeEvent(
    product: CDMProduct,
    eventType: CDMEventType,
    effectiveDate: string,
    payload: TradeEventPayload,
    actorCertId: string,
  ): Promise<Result<ExecuteEventOk>> {
    // 1. Pure reducer step — validates + computes next state + event record.
    const tradeEvent: TradeEvent = {
      type: eventType,
      effectiveDate,
      payload,
    } as TradeEvent;
    const reduced = reduceTradeEvent(product, tradeEvent, actorCertId);
    if (!reduced.ok) return reduced;

    const beforeState = product.lifecycleState;
    const { product: updatedProduct, event } = reduced.value;

    // 2. Phase 29.5 kernel policy enforcement (skipped when no runtime).
    const gate = await runPolicyGate(this.runtime, eventType, payload, actorCertId);
    if (!gate.ok) {
      return { ok: false, error: gate.error };
    }
    const policyResults = gate.results;

    // 3. Build the event cell.
    const { cell, cellHash } = buildEventCell({
      product,
      event,
      eventType,
      before: beforeState,
      after: updatedProduct.lifecycleState,
      effectiveDate,
      actorCertId,
      extra: payload,
    });
    event.newStateHash = cellHash;
    event.prevStateHash = product.previousEventCell;

    // 4. Anchor emission for terminal events.
    let anchorTxId: string | undefined;
    if (this.anchorEmitter && isTerminalEvent(eventType)) {
      try {
        const anchorResult = await this.anchorEmitter.emit(cell, {
          linearity: 'LINEAR',
          anchorPolicy: 'terminal-only',
          idempotencyKey: event.eventId,
        });
        anchorTxId = anchorResult.txid;
      } catch {
        // Anchor failure is non-fatal — log but don't block the event.
      }
    }

    // 5. Persistence/observability bus emission. Subscribers may persist,
    //    log, or anchor — failures must not affect the transition result.
    emitLifecycleEvent({
      productCellId: updatedProduct.cellId,
      event,
      cell,
      anchorTxId,
    });

    return {
      ok: true,
      value: { product: updatedProduct, event, cell, policyResults, anchorTxId },
    };
  }

  /**
   * Novation — transfer trade from one counterparty to another.
   * Wraps Phase 17 createTransferRecord().
   */
  novate(
    product: CDMProduct,
    oldParty: CDMPartyRole,
    newParty: CDMPartyRole,
    actorCertId: string,
  ): Result<NovateOk> {
    return novateProduct(product, oldParty, newParty, actorCertId);
  }

  /**
   * Partial termination — reduce notional (AFFINE partial consumption).
   */
  partialTerminate(
    product: CDMProduct,
    reductionAmount: number,
    actorCertId: string,
  ): Result<PartialTerminateOk> {
    return partialTerminateProduct(product, reductionAmount, actorCertId);
  }

  /**
   * Close-out netting — compute net obligations across a portfolio.
   * All products must be in 'defaulted' state and share the same currency.
   */
  closeOutNet(
    products: CDMProduct[],
    defaultingParty: CDMPartyRole,
    actorCertId: string,
  ): Result<CloseOutResult> {
    return closeOutNetPortfolio(products, defaultingParty, actorCertId);
  }

  /**
   * Reconstruct event history from a list of events for a given product.
   * Returns events sorted by timestamp (oldest first).
   */
  eventHistory(
    product: CDMProduct,
    events: CDMLifecycleEvent[],
  ): CDMLifecycleEvent[] {
    return events
      .filter((e) => e.productCellId === product.cellId)
      .sort((a, b) => a.timestamp - b.timestamp);
  }
}

```
