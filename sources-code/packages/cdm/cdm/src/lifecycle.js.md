---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.494852+00:00
---

# packages/cdm/cdm/src/lifecycle.js

```js
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
import { computeTypeHash, buildCellHeader, packCell, contentHash, LINEARITY } from '../../cell-ops/src/typeHashRegistry';
import { createTransferRecord } from '../../../src/types/transfer';
import { createLifecycleEvent, } from './types';
// ── Transition Table ──────────────────────────────────────────
/**
 * Maps (currentState, eventType) → nextState.
 * If the event is not listed for a state, the transition is rejected.
 */
const transitionTable = {
    'proposed': {
        'execution': 'executed',
    },
    'executed': {
        'confirmation': 'confirmed',
        'novation': 'novated',
        'default': 'defaulted',
        'full-termination': 'terminated',
    },
    'confirmed': {
        'clearing': 'cleared',
        'novation': 'novated',
        'partial-termination': 'partially-terminated',
        'full-termination': 'terminated',
        'rate-reset': 'confirmed',
        'payment': 'confirmed',
        'margin-call': 'confirmed',
        'default': 'defaulted',
    },
    'cleared': {
        'settlement': 'settled',
        'novation': 'novated',
        'partial-termination': 'partially-terminated',
        'full-termination': 'terminated',
        'rate-reset': 'cleared',
        'payment': 'cleared',
        'margin-call': 'cleared',
        'default': 'defaulted',
    },
    'settled': {
        'full-termination': 'terminated',
    },
    'novated': {},
    'partially-terminated': {
        'partial-termination': 'partially-terminated',
        'full-termination': 'terminated',
        'rate-reset': 'partially-terminated',
        'payment': 'partially-terminated',
        'margin-call': 'partially-terminated',
        'default': 'defaulted',
    },
    'terminated': {},
    'defaulted': {
        'close-out-netting': 'close-out',
    },
    'close-out': {},
};
// ── CDMLifecycleEngine ────────────────────────────────────────
export class CDMLifecycleEngine {
    /** Check if a transition is valid from the given state. */
    canTransition(state, eventType) {
        const validEvents = transitionTable[state];
        return validEvents !== undefined && eventType in validEvents;
    }
    /** Get the list of valid event types for a given state. */
    getValidEvents(state) {
        const validEvents = transitionTable[state];
        return validEvents ? Object.keys(validEvents) : [];
    }
    /**
     * Execute a lifecycle event — validates transition, creates new cell, returns updated product.
     */
    executeEvent(product, eventType, effectiveDate, payload, actorCertId) {
        const nextState = transitionTable[product.lifecycleState]?.[eventType];
        if (nextState === undefined) {
            return {
                ok: false,
                error: `Cannot apply '${eventType}' to product in state '${product.lifecycleState}'. ` +
                    `Valid events: [${this.getValidEvents(product.lifecycleState).join(', ')}]`,
            };
        }
        // Build economic effect from payload
        const economicEffect = payload.notionalChange
            ? { notionalChange: payload.notionalChange }
            : payload.rateReset
                ? { rateReset: payload.rateReset }
                : undefined;
        // Create lifecycle event record
        const event = createLifecycleEvent(eventType, product, effectiveDate, product.lifecycleState, nextState, actorCertId, economicEffect);
        // Build cell for this event
        const payloadJson = JSON.stringify({
            eventId: event.eventId,
            eventType,
            productCellId: product.cellId,
            before: product.lifecycleState,
            after: nextState,
            effectiveDate,
            timestamp: event.timestamp,
            actorCertId,
            ...payload,
        });
        const payloadBuf = Buffer.from(payloadJson, 'utf-8');
        const prevHash = product.previousEventCell
            ? Buffer.from(product.previousEventCell.padEnd(64, '0').slice(0, 64), 'hex')
            : Buffer.alloc(32, 0);
        const typeHash = computeTypeHash(`cdm.event.${eventType}`, 'lifecycle', 'inst.derivative.otc');
        const header = buildCellHeader({
            typeHash,
            linearity: LINEARITY.LINEAR,
            ownerId: Buffer.alloc(16, 0),
            phase: 'action',
            dimension: 'composite',
            prevStateHash: prevHash,
            payloadSize: payloadBuf.length,
        });
        const cell = packCell(header, payloadBuf);
        // Compute content hash for chaining
        const cellHash = contentHash(payloadBuf).toString('hex');
        event.newStateHash = cellHash;
        event.prevStateHash = product.previousEventCell;
        // Update product — immutable update
        const updatedProduct = {
            ...product,
            lifecycleState: nextState,
            previousEventCell: event.eventId,
            economicTerms: applyEconomicEffect(product.economicTerms, economicEffect),
        };
        return { ok: true, value: { product: updatedProduct, event, cell } };
    }
    /**
     * Novation — transfer trade from one counterparty to another.
     * Wraps Phase 17 createTransferRecord().
     */
    novate(product, oldParty, newParty, actorCertId) {
        if (!this.canTransition(product.lifecycleState, 'novation')) {
            return {
                ok: false,
                error: `Cannot novate product in state '${product.lifecycleState}'. ` +
                    `Valid events: [${this.getValidEvents(product.lifecycleState).join(', ')}]`,
            };
        }
        // Verify oldParty is actually on the trade
        const partyIndex = product.parties.findIndex(p => p.partyId === oldParty.partyId);
        if (partyIndex === -1) {
            return { ok: false, error: `Party '${oldParty.partyId}' is not a counterparty on this trade` };
        }
        // Create Phase 17 transfer record
        const transferRecord = createTransferRecord(product.cellId, oldParty.facetCertId ?? oldParty.partyId, newParty.facetCertId ?? newParty.partyId, `novation-tx-${Date.now().toString(16)}`, `${product.cellId}.0`, `${product.cellId}.1`, {
            capTransferOutpoint: null,
            edgeVerified: false,
            previousChildIndex: 0,
            newChildIndex: 0,
        });
        // Create lifecycle event
        const event = createLifecycleEvent('novation', product, new Date().toISOString().split('T')[0], product.lifecycleState, 'novated', actorCertId);
        // Update product — replace old party with new party
        const updatedParties = [...product.parties];
        updatedParties[partyIndex] = newParty;
        const updatedProduct = {
            ...product,
            lifecycleState: 'novated',
            parties: updatedParties,
            previousEventCell: event.eventId,
        };
        return { ok: true, value: { product: updatedProduct, transferRecord, event } };
    }
    /**
     * Partial termination — reduce notional (AFFINE partial consumption).
     */
    partialTerminate(product, reductionAmount, actorCertId) {
        if (!this.canTransition(product.lifecycleState, 'partial-termination')) {
            return {
                ok: false,
                error: `Cannot partially terminate product in state '${product.lifecycleState}'`,
            };
        }
        if (reductionAmount <= 0) {
            return { ok: false, error: 'Reduction amount must be positive' };
        }
        if (reductionAmount >= product.economicTerms.notional.amount) {
            return {
                ok: false,
                error: `Reduction amount (${reductionAmount}) must be less than notional (${product.economicTerms.notional.amount}). Use full termination instead.`,
            };
        }
        const newNotional = product.economicTerms.notional.amount - reductionAmount;
        const event = createLifecycleEvent('partial-termination', product, new Date().toISOString().split('T')[0], product.lifecycleState, 'partially-terminated', actorCertId, { notionalChange: -reductionAmount });
        const updatedProduct = {
            ...product,
            lifecycleState: 'partially-terminated',
            previousEventCell: event.eventId,
            economicTerms: {
                ...product.economicTerms,
                notional: {
                    ...product.economicTerms.notional,
                    amount: newNotional,
                },
            },
        };
        return { ok: true, value: { product: updatedProduct, event } };
    }
    /**
     * Close-out netting — compute net obligations across a portfolio.
     * All products must be in 'defaulted' state and share the same currency.
     */
    closeOutNet(products, defaultingParty, actorCertId) {
        if (products.length === 0) {
            return { ok: false, error: 'Portfolio is empty' };
        }
        // All must be defaulted
        const nonDefaulted = products.filter(p => p.lifecycleState !== 'defaulted');
        if (nonDefaulted.length > 0) {
            return {
                ok: false,
                error: `Cannot net — ${nonDefaulted.length} product(s) not in 'defaulted' state: [${nonDefaulted.map(p => p.cellId).join(', ')}]`,
            };
        }
        // All must share the same currency (single-currency netting only)
        const currencies = new Set(products.map(p => p.economicTerms.notional.currency));
        if (currencies.size > 1) {
            return {
                ok: false,
                error: `Multi-currency netting not supported. Found currencies: [${[...currencies].join(', ')}]`,
            };
        }
        const currency = products[0].economicTerms.notional.currency;
        // Compute net: sum notionals, signed by whether defaulting party is buyer (+) or seller (-)
        let netAmount = 0;
        const events = [];
        const updatedProducts = [];
        for (const product of products) {
            const isBuyer = product.parties.some(p => p.partyId === defaultingParty.partyId && p.role === 'buyer');
            const sign = isBuyer ? 1 : -1;
            netAmount += sign * product.economicTerms.notional.amount;
            const event = createLifecycleEvent('close-out-netting', product, new Date().toISOString().split('T')[0], 'defaulted', 'close-out', actorCertId);
            events.push(event);
            updatedProducts.push({
                ...product,
                lifecycleState: 'close-out',
                previousEventCell: event.eventId,
            });
        }
        return {
            ok: true,
            value: {
                netAmount,
                currency,
                events,
                products: updatedProducts,
            },
        };
    }
    /**
     * Reconstruct event history from a list of events for a given product.
     * Returns events sorted by timestamp (oldest first).
     */
    eventHistory(product, events) {
        return events
            .filter(e => e.productCellId === product.cellId)
            .sort((a, b) => a.timestamp - b.timestamp);
    }
}
// ── Helpers ───────────────────────────────────────────────────
function applyEconomicEffect(terms, effect) {
    if (!effect)
        return terms;
    let updated = { ...terms };
    if (effect.notionalChange !== undefined) {
        updated = {
            ...updated,
            notional: {
                ...updated.notional,
                amount: updated.notional.amount + effect.notionalChange,
            },
        };
    }
    if (effect.rateReset) {
        updated = {
            ...updated,
            fixedRate: effect.rateReset.newRate,
        };
    }
    return updated;
}
//# sourceMappingURL=lifecycle.js.map
```
