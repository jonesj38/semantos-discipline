---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/fpml.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.504167+00:00
---

# packages/cdm/cdm/src/bridge/fpml.js

```js
/**
 * FpML Import/Export — maps between FpML XML (subset) and Semantos CDMProduct.
 *
 * Supports vanilla products only:
 * - Interest Rate Swaps (<swap>)
 * - Single-Name CDS (<creditDefaultSwap>)
 * - Deliverable FX Forwards (<fxSingleLeg>)
 *
 * Uses string-based extraction — no external XML dependency.
 *
 * Phase 28 / D28.5
 */
import { createCDMProduct, } from '../types';
// ── FpML Import ───────────────────────────────────────────────
/**
 * Import FpML XML into CDMProduct(s).
 * Supports: <swap>, <creditDefaultSwap>, <fxSingleLeg>
 */
export function importFpML(xml) {
    try {
        const products = [];
        // Detect swap
        if (xml.includes('<swap>') || xml.includes('<swap ')) {
            const swap = parseSwap(xml);
            if (swap.ok)
                products.push(swap.value);
            else
                return swap;
        }
        // Detect CDS
        if (xml.includes('<creditDefaultSwap>') || xml.includes('<creditDefaultSwap ')) {
            const cds = parseCDS(xml);
            if (cds.ok)
                products.push(cds.value);
            else
                return cds;
        }
        // Detect FX Forward
        if (xml.includes('<fxSingleLeg>') || xml.includes('<fxSingleLeg ')) {
            const fx = parseFXForward(xml);
            if (fx.ok)
                products.push(fx.value);
            else
                return fx;
        }
        if (products.length === 0) {
            return { ok: false, error: 'No supported FpML product found. Supported: <swap>, <creditDefaultSwap>, <fxSingleLeg>' };
        }
        return { ok: true, value: products };
    }
    catch (err) {
        return { ok: false, error: `FpML import failed: ${err instanceof Error ? err.message : String(err)}` };
    }
}
/**
 * Export CDMProduct(s) to FpML XML.
 * Only supports vanilla IRS, CDS, and FX forwards.
 */
export function exportFpML(products) {
    const fragments = products.map(p => {
        if (p.productType.startsWith('rates.swap'))
            return exportSwapFpML(p);
        if (p.productType.startsWith('credit.cds'))
            return exportCDSFpML(p);
        if (p.productType.startsWith('fx.forward'))
            return exportFXForwardFpML(p);
        return `<!-- Unsupported product type: ${p.productType} -->`;
    });
    return [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<FpML xmlns="http://www.fpml.org/FpML-5/confirmation" version="5-12">',
        ...fragments,
        '</FpML>',
    ].join('\n');
}
// ── Swap Parser ───────────────────────────────────────────────
function parseSwap(xml) {
    const notionalStr = extractTag(xml, 'notionalAmount') ?? extractTag(xml, 'initialValue');
    const currency = extractTag(xml, 'currency') ?? 'USD';
    const effectiveDate = extractTag(xml, 'effectiveDate') ?? extractTag(xml, 'adjustedDate') ?? '';
    const terminationDate = extractTag(xml, 'terminationDate') ?? '';
    const fixedRateStr = extractTag(xml, 'fixedRate') ?? extractTag(xml, 'rate');
    const floatingIndex = extractTag(xml, 'floatingRateIndex') ?? '';
    const payFreq = extractTag(xml, 'paymentFrequency') ?? extractTag(xml, 'periodMultiplier');
    const dayCount = extractTag(xml, 'dayCountFraction') ?? '';
    const notional = parseFloat(notionalStr ?? '0');
    const fixedRate = fixedRateStr ? parseFloat(fixedRateStr) : undefined;
    const parties = extractFpMLParties(xml);
    const tradeDate = extractTag(xml, 'tradeDate') ?? new Date().toISOString().split('T')[0];
    const productType = floatingIndex
        ? 'rates.swap.fixed-float'
        : 'rates.swap.basis';
    const economicTerms = {
        notional: { amount: notional, currency },
        effectiveDate,
        terminationDate,
        fixedRate,
        floatingRateIndex: floatingIndex || undefined,
        paymentFrequency: payFreq || undefined,
        dayCountConvention: dayCount || undefined,
    };
    return { ok: true, value: createCDMProduct(productType, economicTerms, parties, tradeDate) };
}
// ── CDS Parser ────────────────────────────────────────────────
function parseCDS(xml) {
    const notionalStr = extractTag(xml, 'notionalAmount') ?? extractTag(xml, 'initialValue') ?? '0';
    const currency = extractTag(xml, 'currency') ?? 'USD';
    const effectiveDate = extractTag(xml, 'effectiveDate') ?? '';
    const terminationDate = extractTag(xml, 'scheduledTerminationDate') ?? extractTag(xml, 'terminationDate') ?? '';
    const fixedRateStr = extractTag(xml, 'fixedRate') ?? extractTag(xml, 'couponRate');
    const referenceEntity = extractTag(xml, 'entityName') ?? extractTag(xml, 'referenceEntity') ?? '';
    const parties = extractFpMLParties(xml);
    const tradeDate = extractTag(xml, 'tradeDate') ?? new Date().toISOString().split('T')[0];
    const economicTerms = {
        notional: { amount: parseFloat(notionalStr), currency },
        effectiveDate,
        terminationDate,
        fixedRate: fixedRateStr ? parseFloat(fixedRateStr) : undefined,
    };
    return {
        ok: true,
        value: createCDMProduct('credit.cds.single-name', economicTerms, parties, tradeDate),
    };
}
// ── FX Forward Parser ─────────────────────────────────────────
function parseFXForward(xml) {
    const currency1 = extractTag(xml, 'currency', 0) ?? 'USD';
    const amount1Str = extractTag(xml, 'amount', 0) ?? '0';
    const currency2 = extractTag(xml, 'currency', 1) ?? 'EUR';
    const valueDate = extractTag(xml, 'valueDate') ?? '';
    const parties = extractFpMLParties(xml);
    const tradeDate = extractTag(xml, 'tradeDate') ?? new Date().toISOString().split('T')[0];
    const economicTerms = {
        notional: { amount: parseFloat(amount1Str), currency: currency1 },
        effectiveDate: tradeDate,
        terminationDate: valueDate,
    };
    return {
        ok: true,
        value: createCDMProduct('fx.forward.deliverable', economicTerms, parties, tradeDate),
    };
}
// ── FpML Export ───────────────────────────────────────────────
function exportSwapFpML(product) {
    const et = product.economicTerms;
    return [
        '  <swap>',
        `    <tradeDate>${product.tradeDate}</tradeDate>`,
        '    <swapStream>',
        `      <notionalAmount>${et.notional.amount}</notionalAmount>`,
        `      <currency>${et.notional.currency}</currency>`,
        `      <effectiveDate>${et.effectiveDate}</effectiveDate>`,
        `      <terminationDate>${et.terminationDate}</terminationDate>`,
        et.fixedRate !== undefined ? `      <fixedRate>${et.fixedRate}</fixedRate>` : '',
        et.floatingRateIndex ? `      <floatingRateIndex>${et.floatingRateIndex}</floatingRateIndex>` : '',
        et.paymentFrequency ? `      <paymentFrequency>${et.paymentFrequency}</paymentFrequency>` : '',
        et.dayCountConvention ? `      <dayCountFraction>${et.dayCountConvention}</dayCountFraction>` : '',
        '    </swapStream>',
        ...exportPartiesFpML(product.parties),
        '  </swap>',
    ].filter(Boolean).join('\n');
}
function exportCDSFpML(product) {
    const et = product.economicTerms;
    return [
        '  <creditDefaultSwap>',
        `    <tradeDate>${product.tradeDate}</tradeDate>`,
        `    <notionalAmount>${et.notional.amount}</notionalAmount>`,
        `    <currency>${et.notional.currency}</currency>`,
        `    <effectiveDate>${et.effectiveDate}</effectiveDate>`,
        `    <scheduledTerminationDate>${et.terminationDate}</scheduledTerminationDate>`,
        et.fixedRate !== undefined ? `    <fixedRate>${et.fixedRate}</fixedRate>` : '',
        ...exportPartiesFpML(product.parties),
        '  </creditDefaultSwap>',
    ].filter(Boolean).join('\n');
}
function exportFXForwardFpML(product) {
    const et = product.economicTerms;
    return [
        '  <fxSingleLeg>',
        `    <tradeDate>${product.tradeDate}</tradeDate>`,
        `    <amount>${et.notional.amount}</amount>`,
        `    <currency>${et.notional.currency}</currency>`,
        `    <valueDate>${et.terminationDate}</valueDate>`,
        ...exportPartiesFpML(product.parties),
        '  </fxSingleLeg>',
    ].filter(Boolean).join('\n');
}
function exportPartiesFpML(parties) {
    return parties.map(p => `    <party><partyId>${p.partyId}</partyId><partyRole>${p.role}</partyRole></party>`);
}
// ── XML Helpers ───────────────────────────────────────────────
/**
 * Extract the text content of an XML tag by name.
 * Returns the Nth occurrence (0-indexed) if occurrence is specified.
 */
function extractTag(xml, tagName, occurrence = 0) {
    const regex = new RegExp(`<${tagName}[^>]*>([^<]*)</${tagName}>`, 'g');
    let match;
    let count = 0;
    while ((match = regex.exec(xml)) !== null) {
        if (count === occurrence)
            return match[1].trim();
        count++;
    }
    return null;
}
/** Extract party elements from FpML XML. */
function extractFpMLParties(xml) {
    const parties = [];
    const partyRegex = /<party[^>]*>[\s\S]*?<\/party>/g;
    let match;
    while ((match = partyRegex.exec(xml)) !== null) {
        const block = match[0];
        const partyId = extractTag(block, 'partyId') ?? `party-${parties.length}`;
        const role = extractTag(block, 'partyRole');
        parties.push({
            partyId,
            role: role ?? (parties.length === 0 ? 'buyer' : 'seller'),
            capabilities: [],
        });
    }
    // If no party tags found, create default buyer/seller
    if (parties.length === 0) {
        parties.push({ partyId: 'party-1', role: 'buyer', capabilities: [] }, { partyId: 'party-2', role: 'seller', capabilities: [] });
    }
    return parties;
}
//# sourceMappingURL=fpml.js.map
```
