---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.495863+00:00
---

# packages/cdm/cdm/src/types.ts

```ts
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

// ── Product Taxonomy (WHAT axis) ──────────────────────────────

/** CDM Product taxonomy — maps to WHAT axis of the semantic object. */
export type CDMProductType =
  | 'rates.swap.fixed-float'
  | 'rates.swap.basis'
  | 'rates.swap.ois'
  | 'rates.fra'
  | 'rates.cap-floor'
  | 'credit.cds.single-name'
  | 'credit.cds.index'
  | 'credit.cds.tranche'
  | 'equity.option.vanilla.european'
  | 'equity.option.vanilla.american'
  | 'equity.option.exotic.barrier'
  | 'equity.swap.total-return'
  | 'fx.forward.deliverable'
  | 'fx.forward.ndf'
  | 'fx.option.vanilla'
  | 'fx.swap';

// ── Lifecycle States (HOW axis) ───────────────────────────────

/** CDM lifecycle states — maps to HOW axis. */
export type CDMLifecycleState =
  | 'proposed'
  | 'executed'
  | 'confirmed'
  | 'cleared'
  | 'settled'
  | 'novated'
  | 'partially-terminated'
  | 'terminated'
  | 'defaulted'
  | 'close-out';

// ── Event Types ───────────────────────────────────────────────

/** CDM lifecycle event types — each maps to a state transition. */
export type CDMEventType =
  | 'execution'
  | 'confirmation'
  | 'clearing'
  | 'settlement'
  | 'novation'
  | 'partial-termination'
  | 'full-termination'
  | 'rate-reset'
  | 'payment'
  | 'margin-call'
  | 'default'
  | 'close-out-netting';

// ── Regulatory Tags (WHY axis) ────────────────────────────────

/** Regulatory regime identifiers. */
export type RegulatoryRegime = 'CFTC' | 'EMIR' | 'MAS' | 'JFSA' | 'ASIC';

/** WHY axis regulatory/economic tags. */
export type RegulatoryTag =
  | `reporting.${Lowercase<RegulatoryRegime>}`
  | 'hedging.interest-rate'
  | 'hedging.credit'
  | 'hedging.fx'
  | 'speculation.directional'
  | 'speculation.relative-value';

// ── Party Roles ───────────────────────────────────────────────

/** CDM party role — maps to identity hat + capability set. */
export type CDMPartyRoleType =
  | 'buyer'
  | 'seller'
  | 'clearing-member'
  | 'ccp'
  | 'calculation-agent'
  | 'reporting-party';

/** A party in a CDM trade, linked to an identity hat. */
export interface CDMPartyRole {
  partyId: string;
  role: CDMPartyRoleType;
  capabilities: number[];
  hatCertId?: string;
  lei?: string;
  jurisdiction?: string;
}

// ── Economic Terms ────────────────────────────────────────────

/** Economic terms — the payload of the product cell. */
export interface EconomicTerms {
  notional: { amount: number; currency: string };
  effectiveDate: string;
  terminationDate: string;
  fixedRate?: number;
  floatingRateIndex?: string;
  paymentFrequency?: string;
  dayCountConvention?: string;
  businessDayConvention?: string;
}

/** Economic effect of a lifecycle event (e.g., notional reduction). */
export interface EconomicEffect {
  notionalChange?: number;
  rateReset?: { newRate: number; resetDate: string };
  paymentAmount?: number;
}

// ── CDM Product ───────────────────────────────────────────────

/**
 * CDM Product — a view over a LINEAR cell.
 *
 * Trades are LINEAR: they exist once, cannot be duplicated.
 * Novation is a transfer, not a copy. Termination is consumption.
 */
export interface CDMProduct {
  cellId: string;
  productType: CDMProductType;
  linearity: 'LINEAR';
  parties: CDMPartyRole[];
  economicTerms: EconomicTerms;
  lifecycleState: CDMLifecycleState;
  regulatoryObligations: RegulatoryTag[];
  previousEventCell?: string;
  typeHashHex: string;
  uti: string;
  tradeDate: string;
  /** Preserves unknown fields from CDM JSON import. */
  _extensions?: Record<string, unknown>;
}

// ── CDM Lifecycle Event ───────────────────────────────────────

/** CDM lifecycle event — maps to a state transition on a cell. */
export interface CDMLifecycleEvent {
  eventId: string;
  eventType: CDMEventType;
  timestamp: number;
  effectiveDate: string;
  parties: CDMPartyRole[];
  before: CDMLifecycleState;
  after: CDMLifecycleState;
  economicEffect?: EconomicEffect;
  regulatoryReport?: RegulatoryReport;
  policyCell?: string;
  productCellId: string;
  prevStateHash?: string;
  newStateHash?: string;
}

// ── Regulatory Report ─────────────────────────────────────────

/**
 * Regulatory report — a RELEVANT cell for compliance.
 *
 * Reports are RELEVANT linearity: they MUST be kept, CANNOT be destroyed.
 * The cell engine rejects consumption of RELEVANT cells at the opcode level.
 */
export interface RegulatoryReport {
  cellId: string;
  regime: RegulatoryRegime;
  reportType: 'trade-report' | 'valuation-report' | 'margin-report' | 'position-report';
  uti: string;
  usi?: string;
  leiReportingParty: string;
  leiCounterparty: string;
  productTaxonomy: string;
  eventTimestamp: string;
  effectiveDate: string;
  economicTermsSummary: Record<string, unknown>;
  sourceEventCell: string;
  linearity: 'RELEVANT';
}

// ── Dispute / Resolution (minimal — no Phase 9.5 dependency) ──

/** CDM dispute on a trade. */
export interface CDMDispute {
  disputeId: string;
  productId: string;
  raisedBy: string;
  reason: string;
  status: 'open' | 'resolved' | 'escalated';
  raisedAt: number;
}

/** Resolution of a CDM dispute. */
export interface CDMResolution {
  disputeId: string;
  resolvedBy: string;
  outcome: string;
  resolvedAt: number;
}

// ── Close-Out Result ──────────────────────────────────────────

/** Result of close-out netting across a portfolio. */
export interface CloseOutResult {
  netAmount: number;
  currency: string;
  events: CDMLifecycleEvent[];
  products: CDMProduct[];
}

// ── Result Type (matches metering FSM pattern) ────────────────

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

// ── Factory Functions ─────────────────────────────────────────

/** Generate a unique resource ID (hex string). */
function generateId(): string {
  return Math.random().toString(16).slice(2) + Date.now().toString(16);
}

/**
 * Compute the CDM type hash for a product type.
 * Format: SHA256("cdm." + productType + ":lifecycle:inst.derivative.otc")
 */
export function computeCDMTypeHash(productType: CDMProductType): string {
  const canonical = `cdm.${productType}:lifecycle:inst.derivative.otc`;
  return createHash('sha256').update(canonical, 'utf-8').digest('hex');
}

/**
 * Generate a Unique Transaction Identifier (UTI) per ISDA format.
 * Format: {LEI_PREFIX}_{tradeDate}_{hash8}
 */
export function generateUTI(lei: string, tradeDate: string, productId: string): string {
  const prefix = lei.slice(0, 10) || 'NOENTITY00';
  const hash = createHash('sha256')
    .update(`${productId}:${tradeDate}:${lei}`)
    .digest('hex')
    .slice(0, 8);
  return `${prefix}_${tradeDate.replace(/-/g, '')}${hash}`;
}

/** Create a new CDM product in 'proposed' state. */
export function createCDMProduct(
  productType: CDMProductType,
  economicTerms: EconomicTerms,
  parties: CDMPartyRole[],
  tradeDate: string,
  regulatoryObligations: RegulatoryTag[] = [],
): CDMProduct {
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
export function createLifecycleEvent(
  eventType: CDMEventType,
  product: CDMProduct,
  effectiveDate: string,
  before: CDMLifecycleState,
  after: CDMLifecycleState,
  actorCertId: string,
  economicEffect?: EconomicEffect,
): CDMLifecycleEvent {
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
export function createRegulatoryReport(
  regime: RegulatoryRegime,
  product: CDMProduct,
  event: CDMLifecycleEvent,
  reportType: RegulatoryReport['reportType'] = 'trade-report',
): RegulatoryReport {
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

```
