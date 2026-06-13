---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/bridge/cdm-json.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.503290+00:00
---

# packages/cdm/cdm/src/bridge/cdm-json.ts

```ts
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

import {
  type CDMProduct,
  type CDMLifecycleEvent,
  type CDMPartyRole,
  type CDMPartyRoleType,
  type CDMProductType,
  type CDMLifecycleState,
  type CDMEventType,
  type EconomicTerms,
  type RegulatoryTag,
  type Result,
  createCDMProduct,
} from '../types';

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
export function importProduct(json: Record<string, unknown>): Result<CDMProduct> {
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
    const tradeDate = (json.tradeDate as string) ?? new Date().toISOString().split('T')[0];
    const regulatoryObligations = (json.regulatoryObligations as RegulatoryTag[]) ?? [];

    const product = createCDMProduct(
      productType,
      economicTerms,
      parties,
      tradeDate,
      regulatoryObligations,
    );

    // Set lifecycle state if provided
    if (json.lifecycleState && isValidLifecycleState(json.lifecycleState as string)) {
      (product as { lifecycleState: CDMLifecycleState }).lifecycleState =
        json.lifecycleState as CDMLifecycleState;
    }

    // Preserve unknown fields
    const extensions: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(json)) {
      if (!KNOWN_PRODUCT_FIELDS.has(key)) {
        extensions[key] = value;
      }
    }
    if (Object.keys(extensions).length > 0) {
      product._extensions = extensions;
    }

    return { ok: true, value: product };
  } catch (err) {
    return { ok: false, error: `CDM JSON import failed: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/**
 * Export a CDMProduct to CDM JSON.
 * Round-trips _extensions back into the output.
 */
export function exportProduct(product: CDMProduct): Record<string, unknown> {
  const json: Record<string, unknown> = {
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
    (json.economicTerms as Record<string, unknown>).fixedRate = product.economicTerms.fixedRate;
  }
  if (product.economicTerms.floatingRateIndex) {
    (json.economicTerms as Record<string, unknown>).floatingRateIndex = product.economicTerms.floatingRateIndex;
  }
  if (product.economicTerms.paymentFrequency) {
    (json.economicTerms as Record<string, unknown>).paymentFrequency = product.economicTerms.paymentFrequency;
  }
  if (product.economicTerms.dayCountConvention) {
    (json.economicTerms as Record<string, unknown>).dayCountConvention = product.economicTerms.dayCountConvention;
  }
  if (product.economicTerms.businessDayConvention) {
    (json.economicTerms as Record<string, unknown>).businessDayConvention = product.economicTerms.businessDayConvention;
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
export function importEvent(json: Record<string, unknown>): Result<CDMLifecycleEvent> {
  try {
    const eventType = json.eventType as CDMEventType;
    if (!eventType) {
      return { ok: false, error: 'Missing eventType in CDM event JSON' };
    }

    const event: CDMLifecycleEvent = {
      eventId: (json.eventId as string) ?? `evt-${Date.now().toString(16)}`,
      eventType,
      timestamp: (json.timestamp as number) ?? Date.now(),
      effectiveDate: (json.effectiveDate as string) ?? new Date().toISOString().split('T')[0],
      parties: extractParties(json),
      before: (json.before as CDMLifecycleState) ?? 'proposed',
      after: (json.after as CDMLifecycleState) ?? 'executed',
      productCellId: (json.productCellId as string) ?? '',
    };

    if (json.economicEffect) {
      event.economicEffect = json.economicEffect as CDMLifecycleEvent['economicEffect'];
    }

    return { ok: true, value: event };
  } catch (err) {
    return { ok: false, error: `CDM event import failed: ${err instanceof Error ? err.message : String(err)}` };
  }
}

/** Export a CDM lifecycle event to JSON. */
export function exportEvent(event: CDMLifecycleEvent): Record<string, unknown> {
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

function extractProductType(json: Record<string, unknown>): CDMProductType | null {
  const pt = json.productType;
  if (typeof pt !== 'string') return null;
  return pt as CDMProductType;
}

function extractEconomicTerms(json: Record<string, unknown>): EconomicTerms | null {
  const et = json.economicTerms;
  if (!et || typeof et !== 'object') return null;
  const terms = et as Record<string, unknown>;

  const notional = terms.notional as { amount: number; currency: string } | undefined;
  if (!notional || typeof notional.amount !== 'number' || typeof notional.currency !== 'string') {
    return null;
  }

  return {
    notional,
    effectiveDate: (terms.effectiveDate as string) ?? '',
    terminationDate: (terms.terminationDate as string) ?? '',
    fixedRate: terms.fixedRate as number | undefined,
    floatingRateIndex: terms.floatingRateIndex as string | undefined,
    paymentFrequency: terms.paymentFrequency as string | undefined,
    dayCountConvention: terms.dayCountConvention as string | undefined,
    businessDayConvention: terms.businessDayConvention as string | undefined,
  };
}

function extractParties(json: Record<string, unknown>): CDMPartyRole[] {
  const parties = json.parties;
  if (!Array.isArray(parties)) return [];

  return parties.map((p: Record<string, unknown>) => ({
    partyId: (p.partyId as string) ?? `party-${Math.random().toString(36).slice(2, 8)}`,
    role: (p.role as CDMPartyRoleType) ?? 'buyer',
    capabilities: (p.capabilities as number[]) ?? [],
    hatCertId: p.hatCertId as string | undefined,
    lei: p.lei as string | undefined,
    jurisdiction: p.jurisdiction as string | undefined,
  }));
}

const VALID_LIFECYCLE_STATES = new Set<string>([
  'proposed', 'executed', 'confirmed', 'cleared', 'settled',
  'novated', 'partially-terminated', 'terminated', 'defaulted', 'close-out',
]);

function isValidLifecycleState(s: string): boolean {
  return VALID_LIFECYCLE_STATES.has(s);
}

```
