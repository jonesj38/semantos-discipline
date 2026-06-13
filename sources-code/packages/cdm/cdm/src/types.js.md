---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/types.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.496491+00:00
---

# packages/cdm/cdm/src/types.js

```js
/**
 * CDM Type Mapping — ISDA Common Domain Model types mapped to Semantos primitives.
 *
 * CDM Product → LINEAR semantic object with three-axis taxonomy
 * CDM Event → State transition on a cell
 * CDM Party → Identity hat with capability tokens
 * CDM Lineage → Cell DAG (prevStateHash chain)
 * CDM Qualification → Lisp policy compiled to capability cell
 *
 * Phase 28 / D28.1
 */
import { createHash } from 'crypto';
// ── Factory Functions ─────────────────────────────────────────
/** Generate a unique resource ID (hex string). */
function generateId() {
    return Math.random().toString(16).slice(2) + Date.now().toString(16);
}
/**
 * Compute the CDM type hash for a product type.
 * Format: SHA256("cdm." + productType + ":lifecycle:inst.derivative.otc")
 */
export function computeCDMTypeHash(productType) {
    const canonical = `cdm.${productType}:lifecycle:inst.derivative.otc`;
    return createHash('sha256').update(canonical, 'utf-8').digest('hex');
}
/**
 * Generate a Unique Transaction Identifier (UTI) per ISDA format.
 * Format: {LEI_PREFIX}_{tradeDate}_{hash8}
 */
export function generateUTI(lei, tradeDate, productId) {
    const prefix = lei.slice(0, 10) || 'NOENTITY00';
    const hash = createHash('sha256')
        .update(`${productId}:${tradeDate}:${lei}`)
        .digest('hex')
        .slice(0, 8);
    return `${prefix}_${tradeDate.replace(/-/g, '')}${hash}`;
}
/** Create a new CDM product in 'proposed' state. */
export function createCDMProduct(productType, economicTerms, parties, tradeDate, regulatoryObligations = []) {
    const cellId = generateId();
    const typeHashHex = computeCDMTypeHash(productType);
    const reportingParty = parties.find(p => p.role === 'reporting-party') ?? parties[0];
    const lei = reportingParty?.lei ?? 'UNKNOWN0000000000';
    const uti = generateUTI(lei, tradeDate, cellId);
    return {
        cellId,
        productType,
        linearity: 'LINEAR',
        parties,
        economicTerms,
        lifecycleState: 'proposed',
        regulatoryObligations,
        typeHashHex,
        uti,
        tradeDate,
    };
}
/** Create a lifecycle event record. */
export function createLifecycleEvent(eventType, product, effectiveDate, before, after, actorCertId, economicEffect) {
    return {
        eventId: generateId(),
        eventType,
        timestamp: Date.now(),
        effectiveDate,
        parties: product.parties,
        before,
        after,
        economicEffect,
        productCellId: product.cellId,
    };
}
/** Create a regulatory report. */
export function createRegulatoryReport(regime, product, event, reportType = 'trade-report') {
    const reportingParty = product.parties.find(p => p.role === 'reporting-party') ?? product.parties[0];
    const counterparty = product.parties.find(p => p.partyId !== reportingParty?.partyId) ?? product.parties[1];
    return {
        cellId: generateId(),
        regime,
        reportType,
        uti: product.uti,
        leiReportingParty: reportingParty?.lei ?? 'UNKNOWN',
        leiCounterparty: counterparty?.lei ?? 'UNKNOWN',
        productTaxonomy: product.productType,
        eventTimestamp: new Date(event.timestamp).toISOString(),
        effectiveDate: event.effectiveDate,
        economicTermsSummary: {
            notional: product.economicTerms.notional,
            currency: product.economicTerms.notional.currency,
        },
        sourceEventCell: event.eventId,
        linearity: 'RELEVANT',
    };
}
//# sourceMappingURL=types.js.map
```
