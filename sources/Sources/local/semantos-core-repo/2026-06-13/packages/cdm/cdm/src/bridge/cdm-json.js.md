---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/cdm-json.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.503585+00:00
---

# packages/cdm/cdm/src/bridge/cdm-json.js

```js
/**
 * CDM JSON Import/Export — maps between ISDA CDM JSON and Semantos CDMProduct.
 *
 * CDM JSON is an import/export format, NOT the source of truth.
 * The cell IS the product. CDM JSON is a view.
 *
 * Unknown fields in CDM JSON are preserved in _extensions for round-trip fidelity.
 *
 * Phase 28 / D28.5
 */
import { createCDMProduct, } from '../types';
/** Known CDM JSON top-level fields for product import. */
const KNOWN_PRODUCT_FIELDS = new Set([
    'productType', 'economicTerms', 'parties', 'tradeDate',
    'lifecycleState', 'regulatoryObligations', 'tradeIdentifier',
]);
/** Known CDM JSON top-level fields for event import. */
const KNOWN_EVENT_FIELDS = new Set([
    'eventType', 'effectiveDate', 'timestamp', 'parties',
    'before', 'after', 'economicEffect', 'productCellId',
]);
// ── Product Import/Export ─────────────────────────────────────
/**
 * Import a CDM JSON object into a CDMProduct.
 * Unknown fields are preserved in _extensions.
 */
export function importProduct(json) {
    try {
        const productType = extractProductType(json);
        if (!productType) {
            return { ok: false, error: 'Missing or invalid productType in CDM JSON' };
        }
        const economicTerms = extractEconomicTerms(json);
        if (!economicTerms) {
            return { ok: false, error: 'Missing or invalid economicTerms in CDM JSON' };
        }
        const parties = extractParties(json);
        const tradeDate = json.tradeDate ?? new Date().toISOString().split('T')[0];
        const regulatoryObligations = json.regulatoryObligations ?? [];
        const product = createCDMProduct(productType, economicTerms, parties, tradeDate, regulatoryObligations);
        // Set lifecycle state if provided
        if (json.lifecycleState && isValidLifecycleState(json.lifecycleState)) {
            product.lifecycleState =
                json.lifecycleState;
        }
        // Preserve unknown fields
        const extensions = {};
        for (const [key, value] of Object.entries(json)) {
            if (!KNOWN_PRODUCT_FIELDS.has(key)) {
                extensions[key] = value;
            }
        }
        if (Object.keys(extensions).length > 0) {
            product._extensions = extensions;
        }
        return { ok: true, value: product };
    }
    catch (err) {
        return { ok: false, error: `CDM JSON import failed: ${err instanceof Error ? err.message : String(err)}` };
    }
}
/**
 * Export a CDMProduct to CDM JSON.
 * Round-trips _extensions back into the output.
 */
export function exportProduct(product) {
    const json = {
        productType: product.productType,
        economicTerms: {
            notional: product.economicTerms.notional,
            effectiveDate: product.economicTerms.effectiveDate,
            terminationDate: product.economicTerms.terminationDate,
        },
        parties: product.parties.map(p => ({
            partyId: p.partyId,
            role: p.role,
            lei: p.lei,
            jurisdiction: p.jurisdiction,
        })),
        tradeDate: product.tradeDate,
        lifecycleState: product.lifecycleState,
        regulatoryObligations: product.regulatoryObligations,
        tradeIdentifier: {
            uti: product.uti,
        },
    };
    // Add optional economic terms fields
    if (product.economicTerms.fixedRate !== undefined) {
        json.economicTerms.fixedRate = product.economicTerms.fixedRate;
    }
    if (product.economicTerms.floatingRateIndex) {
        json.economicTerms.floatingRateIndex = product.economicTerms.floatingRateIndex;
    }
    if (product.economicTerms.paymentFrequency) {
        json.economicTerms.paymentFrequency = product.economicTerms.paymentFrequency;
    }
    if (product.economicTerms.dayCountConvention) {
        json.economicTerms.dayCountConvention = product.economicTerms.dayCountConvention;
    }
    if (product.economicTerms.businessDayConvention) {
        json.economicTerms.businessDayConvention = product.economicTerms.businessDayConvention;
    }
    // Round-trip extensions
    if (product._extensions) {
        for (const [key, value] of Object.entries(product._extensions)) {
            json[key] = value;
        }
    }
    return json;
}
// ── Event Import/Export ───────────────────────────────────────
/** Import a CDM lifecycle event from JSON. */
export function importEvent(json) {
    try {
        const eventType = json.eventType;
        if (!eventType) {
            return { ok: false, error: 'Missing eventType in CDM event JSON' };
        }
        const event = {
            eventId: json.eventId ?? `evt-${Date.now().toString(16)}`,
            eventType,
            timestamp: json.timestamp ?? Date.now(),
            effectiveDate: json.effectiveDate ?? new Date().toISOString().split('T')[0],
            parties: extractParties(json),
            before: json.before ?? 'proposed',
            after: json.after ?? 'executed',
            productCellId: json.productCellId ?? '',
        };
        if (json.economicEffect) {
            event.economicEffect = json.economicEffect;
        }
        return { ok: true, value: event };
    }
    catch (err) {
        return { ok: false, error: `CDM event import failed: ${err instanceof Error ? err.message : String(err)}` };
    }
}
/** Export a CDM lifecycle event to JSON. */
export function exportEvent(event) {
    return {
        eventId: event.eventId,
        eventType: event.eventType,
        timestamp: event.timestamp,
        effectiveDate: event.effectiveDate,
        parties: event.parties.map(p => ({
            partyId: p.partyId,
            role: p.role,
            lei: p.lei,
        })),
        before: event.before,
        after: event.after,
        economicEffect: event.economicEffect,
        productCellId: event.productCellId,
    };
}
// ── Extractors ────────────────────────────────────────────────
function extractProductType(json) {
    const pt = json.productType;
    if (typeof pt !== 'string')
        return null;
    return pt;
}
function extractEconomicTerms(json) {
    const et = json.economicTerms;
    if (!et || typeof et !== 'object')
        return null;
    const terms = et;
    const notional = terms.notional;
    if (!notional || typeof notional.amount !== 'number' || typeof notional.currency !== 'string') {
        return null;
    }
    return {
        notional,
        effectiveDate: terms.effectiveDate ?? '',
        terminationDate: terms.terminationDate ?? '',
        fixedRate: terms.fixedRate,
        floatingRateIndex: terms.floatingRateIndex,
        paymentFrequency: terms.paymentFrequency,
        dayCountConvention: terms.dayCountConvention,
        businessDayConvention: terms.businessDayConvention,
    };
}
function extractParties(json) {
    const parties = json.parties;
    if (!Array.isArray(parties))
        return [];
    return parties.map((p) => ({
        partyId: p.partyId ?? `party-${Math.random().toString(36).slice(2, 8)}`,
        role: p.role ?? 'buyer',
        capabilities: p.capabilities ?? [],
        facetCertId: p.facetCertId,
        lei: p.lei,
        jurisdiction: p.jurisdiction,
    }));
}
const VALID_LIFECYCLE_STATES = new Set([
    'proposed', 'executed', 'confirmed', 'cleared', 'settled',
    'novated', 'partially-terminated', 'terminated', 'defaulted', 'close-out',
]);
function isValidLifecycleState(s) {
    return VALID_LIFECYCLE_STATES.has(s);
}
//# sourceMappingURL=cdm-json.js.map
```
