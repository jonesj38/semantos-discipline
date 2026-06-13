---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/regulatory.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.495528+00:00
---

# packages/cdm/cdm/src/regulatory.ts

```ts
/**
 * Regulatory Report Generator — auto-generates RELEVANT cells for trade lifecycle events.
 *
 * Reports are RELEVANT linearity: they MUST be kept, CANNOT be destroyed.
 * The cell engine rejects consumption of RELEVANT cells at the opcode level.
 *
 * Each report references the source event cell, creating a verifiable audit trail.
 * UTI generation follows ISDA's identifier standards.
 *
 * Phase 28 / D28.3
 */

import { buildCellHeader, packCell, computeTypeHash, LINEARITY } from '../../../core/cell-ops/src/typeHashRegistry';
import { computeDomainPayloadRoot } from '../../../core/plexus-schema-registry/src/hash';
import {
  commerceSchemaV1,
  commercePayload,
} from '../../../core/plexus-schema-registry/src/schemas/commerce';
import {
  type CDMProduct,
  type CDMLifecycleEvent,
  type RegulatoryRegime,
  type RegulatoryReport,
  createRegulatoryReport,
} from './types';

// ── Jurisdiction → Regime Mapping ─────────────────────────────

const JURISDICTION_REGIME: Record<string, RegulatoryRegime> = {
  US: 'CFTC',
  EU: 'EMIR', DE: 'EMIR', FR: 'EMIR', IT: 'EMIR', ES: 'EMIR', NL: 'EMIR',
  IE: 'EMIR', BE: 'EMIR', AT: 'EMIR', PT: 'EMIR', GR: 'EMIR', FI: 'EMIR',
  LU: 'EMIR', SE: 'EMIR', DK: 'EMIR', PL: 'EMIR',
  SG: 'MAS',
  JP: 'JFSA',
  AU: 'ASIC',
};

const CURRENCY_REGIME: Record<string, RegulatoryRegime> = {
  USD: 'CFTC',
  EUR: 'EMIR',
  SGD: 'MAS',
  JPY: 'JFSA',
  AUD: 'ASIC',
};

// ── RegulatoryReportGenerator ─────────────────────────────────

export class RegulatoryReportGenerator {
  /**
   * Generate reports for a lifecycle event based on applicable regimes.
   * Returns one RELEVANT report cell per applicable regime.
   */
  generate(event: CDMLifecycleEvent, product: CDMProduct): RegulatoryReport[] {
    const regimes = this.applicableRegimes(product);
    return regimes.map(regime => createRegulatoryReport(regime, product, event));
  }

  /**
   * Determine which regulatory regimes apply based on party jurisdictions and currency.
   */
  applicableRegimes(product: CDMProduct): RegulatoryRegime[] {
    const regimes = new Set<RegulatoryRegime>();

    // Check party jurisdictions
    for (const party of product.parties) {
      if (party.jurisdiction) {
        const regime = JURISDICTION_REGIME[party.jurisdiction.toUpperCase()];
        if (regime) regimes.add(regime);
      }
    }

    // Check currency
    const currency = product.economicTerms.notional.currency;
    const currencyRegime = CURRENCY_REGIME[currency];
    if (currencyRegime) regimes.add(currencyRegime);

    return [...regimes];
  }

  /**
   * Format a report for a specific regime.
   * Returns a regime-specific field mapping for submission.
   */
  format(report: RegulatoryReport, regime: RegulatoryRegime): Record<string, unknown> {
    const base = {
      reportId: report.cellId,
      uti: report.uti,
      reportingPartyLEI: report.leiReportingParty,
      counterpartyLEI: report.leiCounterparty,
      productClassification: report.productTaxonomy,
      eventTimestamp: report.eventTimestamp,
      effectiveDate: report.effectiveDate,
      notionalAmount: report.economicTermsSummary.notional,
      currency: report.economicTermsSummary.currency,
    };

    switch (regime) {
      case 'CFTC':
        return {
          ...base,
          reportFormat: 'CFTC-Part43',
          usi: report.usi ?? report.uti,
          assetClass: mapProductToAssetClass(report.productTaxonomy),
          executionVenue: 'OFF',
          clearingExemption: false,
        };
      case 'EMIR':
        return {
          ...base,
          reportFormat: 'EMIR-SFTR',
          tradeRepositoryId: 'DTCC-GTR-EU',
          intragroup: false,
          reportingTimestamp: report.eventTimestamp,
        };
      case 'MAS':
        return {
          ...base,
          reportFormat: 'MAS-SFA',
          reportingEntity: report.leiReportingParty,
        };
      case 'JFSA':
        return {
          ...base,
          reportFormat: 'JFSA-FIEA',
          japanSpecificTaxonomy: report.productTaxonomy,
        };
      case 'ASIC':
        return {
          ...base,
          reportFormat: 'ASIC-DERIVATIVE',
          australianReportingEntity: report.leiReportingParty,
        };
    }
  }

  /**
   * Pack a regulatory report as a RELEVANT cell.
   * Returns the packed cell bytes.
   */
  packReportCell(report: RegulatoryReport): Uint8Array {
    const payloadJson = JSON.stringify(report);
    const payloadBuf = Buffer.from(payloadJson, 'utf-8');

    const typeHash = computeTypeHash(
      `cdm.report.${report.regime.toLowerCase()}`,
      'reporting',
      'inst.regulatory.trade-report',
    );

    // RM-041: commerce taxonomy → schema-encoded payload root.
    const domainPayload = Buffer.from(
      computeDomainPayloadRoot(
        commerceSchemaV1,
        commercePayload({ phase: 'outcome', dimension: 'composite' }),
      ),
    );
    const header = buildCellHeader({
      typeHash,
      linearity: LINEARITY.RELEVANT,
      ownerId: Buffer.alloc(16, 0),
      domainPayload,
      payloadSize: payloadBuf.length,
    });

    return packCell(header, payloadBuf);
  }
}

// ── Helpers ───────────────────────────────────────────────────

function mapProductToAssetClass(productTaxonomy: string): string {
  if (productTaxonomy.startsWith('rates.')) return 'IR';
  if (productTaxonomy.startsWith('credit.')) return 'CR';
  if (productTaxonomy.startsWith('equity.')) return 'EQ';
  if (productTaxonomy.startsWith('fx.')) return 'FX';
  return 'OT';
}

```
