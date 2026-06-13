---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.497154+00:00
---

# packages/cdm/cdm/src/lifecycle.d.ts

```ts
/**
 * CDM Lifecycle Event Engine — state machine for derivative lifecycle events.
 *
 * Follows the metering channel-fsm.ts pattern: transition table, Result<T>
 * returns, immutable state updates.
 *
 * Every lifecycle event:
 * 1. Validates the state transition via the transition table
 * 2. Builds a new cell with prevStateHash linking to prior state
 * 3. Creates a lifecycle event record
 * 4. Returns the updated product with new state
 *
 * Novation wraps Phase 17 createTransferRecord().
 * Partial termination is AFFINE partial consumption of notional.
 * Close-out netting computes net obligations across a portfolio.
 *
 * Phase 28 / D28.2
 */
import { type TransferRecord } from '../../../src/types/transfer';
import { type CDMProduct, type CDMLifecycleEvent, type CDMLifecycleState, type CDMEventType, type CDMPartyRole, type CloseOutResult, type Result } from './types';
export declare class CDMLifecycleEngine {
    /** Check if a transition is valid from the given state. */
    canTransition(state: CDMLifecycleState, eventType: CDMEventType): boolean;
    /** Get the list of valid event types for a given state. */
    getValidEvents(state: CDMLifecycleState): CDMEventType[];
    /**
     * Execute a lifecycle event — validates transition, creates new cell, returns updated product.
     */
    executeEvent(product: CDMProduct, eventType: CDMEventType, effectiveDate: string, payload: Record<string, unknown>, actorCertId: string): Result<{
        product: CDMProduct;
        event: CDMLifecycleEvent;
        cell: Uint8Array;
    }>;
    /**
     * Novation — transfer trade from one counterparty to another.
     * Wraps Phase 17 createTransferRecord().
     */
    novate(product: CDMProduct, oldParty: CDMPartyRole, newParty: CDMPartyRole, actorCertId: string): Result<{
        product: CDMProduct;
        transferRecord: TransferRecord;
        event: CDMLifecycleEvent;
    }>;
    /**
     * Partial termination — reduce notional (AFFINE partial consumption).
     */
    partialTerminate(product: CDMProduct, reductionAmount: number, actorCertId: string): Result<{
        product: CDMProduct;
        event: CDMLifecycleEvent;
    }>;
    /**
     * Close-out netting — compute net obligations across a portfolio.
     * All products must be in 'defaulted' state and share the same currency.
     */
    closeOutNet(products: CDMProduct[], defaultingParty: CDMPartyRole, actorCertId: string): Result<CloseOutResult>;
    /**
     * Reconstruct event history from a list of events for a given product.
     * Returns events sorted by timestamp (oldest first).
     */
    eventHistory(product: CDMProduct, events: CDMLifecycleEvent[]): CDMLifecycleEvent[];
}
//# sourceMappingURL=lifecycle.d.ts.map
```
