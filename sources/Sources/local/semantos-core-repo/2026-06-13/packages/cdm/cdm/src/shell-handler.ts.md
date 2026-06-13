---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/shell-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.496855+00:00
---

# packages/cdm/cdm/src/shell-handler.ts

```ts
/**
 * CDM shell command router — handles `semantos cdm <subcommand>` verbs.
 *
 * Subcommands:
 *   import    — Import CDM JSON or FpML, create product cell
 *   event     — Execute a lifecycle event on a product
 *   novate    — Transfer product to new counterparty (Phase 17 transfer)
 *   report    — Generate regulatory report for a product
 *   history   — Show lifecycle event DAG for a product
 *   portfolio — List all CDM products
 *   netting   — Close-out netting across a portfolio
 *
 * Phase 28 / D28.6
 */

// extensions → runtime imports are LEGAL. Use shell's public package
// surface, not its internal paths. shell's package.json now exposes
// /parser, /types, and /error-codes as supported subpath exports.
import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';
import {
  INVALID_CDM_USAGE, CDM_IMPORT_FAILED, MISSING_EVENT_TYPE, PRODUCT_NOT_FOUND,
  EVENT_EXECUTION_FAILED, NOVATE_FAILED, NO_LIFECYCLE_EVENTS, NETTING_FAILED,
  FPML_NOT_SUPPORTED,
} from '@semantos/shell/error-codes';

// Now that we live inside packages/cdm/, sibling imports are relative.
import { CDMLifecycleEngine } from './lifecycle';
import { RegulatoryReportGenerator } from './regulatory';
import { CDMBridge } from './bridge/index';
import type {
  CDMProduct,
  CDMLifecycleEvent,
  CDMEventType,
  RegulatoryRegime,
} from './types';

// Self-register with the shared verb dispatcher in runtime-services.
// Neither shell nor this extension needs to import the other directly —
// both talk to the neutral registry.
import { registerVerb } from '@semantos/runtime-services';

// ── In-Memory Product Store (shell session scoped) ────────────

const productStore = new Map<string, CDMProduct>();
const eventStore: CDMLifecycleEvent[] = [];

const engine = new CDMLifecycleEngine();
const reportGen = new RegulatoryReportGenerator();
const bridge = new CDMBridge();

/** Route CDM subcommands. */
export async function routeCDM(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  const subcommand = cmd.flags['subcommand'] as string | undefined;

  switch (subcommand) {
    case 'import':
      return cdmImport(cmd);
    case 'event':
      return cdmEvent(cmd);
    case 'novate':
      return cdmNovate(cmd);
    case 'report':
      return cdmReport(cmd);
    case 'history':
      return cdmHistory(cmd);
    case 'portfolio':
      return cdmPortfolio();
    case 'netting':
      return cdmNetting(cmd);
    default:
      return {
        error: `Unknown cdm subcommand: '${subcommand ?? '(none)'}'. ` +
          'Available: import, event, novate, report, history, portfolio, netting',
        code: INVALID_CDM_USAGE,
      };
  }
}

// ── Subcommand Implementations ────────────────────────────────

function cdmImport(cmd: ShellCommand): unknown {
  const file = cmd.flags['file'] as string | undefined;
  const format = cmd.flags['format'] as string | undefined;

  if (!file) {
    return { error: 'Usage: semantos cdm import --file <path> [--format fpml]', code: INVALID_CDM_USAGE };
  }

  // For now, accept inline JSON via --json flag or file path reference
  const jsonStr = cmd.flags['json'] as string | undefined;
  if (jsonStr || (format !== 'fpml')) {
    try {
      const json = jsonStr ? JSON.parse(jsonStr) : { productType: file };
      const result = bridge.importProduct(json);
      if (!result.ok) return { error: result.error, code: CDM_IMPORT_FAILED };
      productStore.set(result.value.cellId, result.value);
      return {
        status: 'imported',
        cellId: result.value.cellId,
        productType: result.value.productType,
        uti: result.value.uti,
        lifecycleState: result.value.lifecycleState,
      };
    } catch (err) {
      return { error: `Import failed: ${err instanceof Error ? err.message : String(err)}`, code: CDM_IMPORT_FAILED };
    }
  }

  return { error: 'FpML file import requires reading from disk. Use --json for inline JSON.', code: FPML_NOT_SUPPORTED };
}

function cdmEvent(cmd: ShellCommand): unknown {
  const productId = cmd.objectId ?? (cmd.flags['product'] as string);
  const eventType = cmd.flags['type'] as CDMEventType | undefined;
  const effectiveDate = (cmd.flags['effective-date'] as string) ?? new Date().toISOString().split('T')[0];

  if (!productId) {
    return { error: 'Usage: semantos cdm event <product-id> --type <event-type>', code: INVALID_CDM_USAGE };
  }
  if (!eventType) {
    return { error: 'Missing --type flag. Valid types: execution, confirmation, clearing, settlement, novation, partial-termination, full-termination, rate-reset, payment, margin-call, default, close-out-netting', code: MISSING_EVENT_TYPE };
  }

  const product = productStore.get(productId);
  if (!product) {
    return { error: `Product not found: ${productId}`, code: PRODUCT_NOT_FOUND };
  }

  const result = engine.executeEvent(product, eventType, effectiveDate, {}, 'shell-user');
  if (!result.ok) return { error: result.error, code: EVENT_EXECUTION_FAILED };

  // Update store
  productStore.set(result.value.product.cellId, result.value.product);
  eventStore.push(result.value.event);

  // Auto-generate regulatory reports
  const reports = reportGen.generate(result.value.event, result.value.product);

  return {
    status: 'event_executed',
    eventId: result.value.event.eventId,
    eventType: result.value.event.eventType,
    before: result.value.event.before,
    after: result.value.event.after,
    productCellId: result.value.product.cellId,
    newState: result.value.product.lifecycleState,
    reports: reports.map(r => ({ regime: r.regime, uti: r.uti, cellId: r.cellId })),
  };
}

function cdmNovate(cmd: ShellCommand): unknown {
  const productId = cmd.objectId ?? (cmd.flags['product'] as string);
  const fromId = cmd.flags['from'] as string | undefined;
  const toId = cmd.flags['to'] as string | undefined;

  if (!productId || !toId) {
    return { error: 'Usage: semantos cdm novate <product-id> --from <party-id> --to <party-id>', code: INVALID_CDM_USAGE };
  }

  const product = productStore.get(productId);
  if (!product) return { error: `Product not found: ${productId}`, code: PRODUCT_NOT_FOUND };

  const oldParty = product.parties.find(p => p.partyId === fromId) ?? product.parties[0];
  const newParty = {
    partyId: toId,
    role: oldParty.role,
    capabilities: oldParty.capabilities,
  };

  const result = engine.novate(product, oldParty, newParty, 'shell-user');
  if (!result.ok) return { error: result.error, code: NOVATE_FAILED };

  productStore.set(result.value.product.cellId, result.value.product);
  eventStore.push(result.value.event);

  return {
    status: 'novated',
    productCellId: result.value.product.cellId,
    transferRecord: {
      resourceId: result.value.transferRecord.resourceId,
      from: result.value.transferRecord.fromParentCertId,
      to: result.value.transferRecord.toParentCertId,
    },
    newParties: result.value.product.parties.map(p => ({ partyId: p.partyId, role: p.role })),
  };
}

function cdmReport(cmd: ShellCommand): unknown {
  const productId = cmd.objectId ?? (cmd.flags['product'] as string);
  const regime = cmd.flags['regime'] as RegulatoryRegime | undefined;

  if (!productId) {
    return { error: 'Usage: semantos cdm report <product-id> --regime <CFTC|EMIR|MAS|JFSA|ASIC>', code: INVALID_CDM_USAGE };
  }

  const product = productStore.get(productId);
  if (!product) return { error: `Product not found: ${productId}`, code: PRODUCT_NOT_FOUND };

  const regimes = regime ? [regime] : reportGen.applicableRegimes(product);
  const lastEvent = eventStore.filter(e => e.productCellId === productId).pop();

  if (!lastEvent) {
    return { error: 'No lifecycle events found for this product. Execute an event first.', code: NO_LIFECYCLE_EVENTS };
  }

  const reports = regimes.map(r => {
    const report = reportGen.generate(lastEvent, product).find(rep => rep.regime === r);
    if (!report) return { regime: r, error: 'Not applicable' };
    return {
      regime: report.regime,
      uti: report.uti,
      reportType: report.reportType,
      linearity: report.linearity,
      sourceEvent: report.sourceEventCell,
      formatted: reportGen.format(report, r),
    };
  });

  return { productId, reports };
}

function cdmHistory(cmd: ShellCommand): unknown {
  const productId = cmd.objectId ?? (cmd.flags['product'] as string);

  if (!productId) {
    return { error: 'Usage: semantos cdm history <product-id>', code: INVALID_CDM_USAGE };
  }

  const product = productStore.get(productId);
  if (!product) return { error: `Product not found: ${productId}`, code: PRODUCT_NOT_FOUND };

  const history = engine.eventHistory(product, eventStore);

  return {
    productId,
    productType: product.productType,
    currentState: product.lifecycleState,
    events: history.map(e => ({
      eventId: e.eventId,
      eventType: e.eventType,
      before: e.before,
      after: e.after,
      effectiveDate: e.effectiveDate,
      timestamp: new Date(e.timestamp).toISOString(),
    })),
  };
}

function cdmPortfolio(): unknown {
  const products = [...productStore.values()];

  return products.map(p => ({
    cellId: p.cellId,
    productType: p.productType,
    lifecycleState: p.lifecycleState,
    notional: p.economicTerms.notional,
    parties: p.parties.map(pt => ({ partyId: pt.partyId, role: pt.role })),
    uti: p.uti,
  }));
}

function cdmNetting(cmd: ShellCommand): unknown {
  const productIds = cmd.flags['products'] as string | undefined;
  const partyId = cmd.flags['party'] as string | undefined;

  if (!productIds) {
    return { error: 'Usage: semantos cdm netting --products <id1,id2,...> --party <defaulting-party-id>', code: INVALID_CDM_USAGE };
  }

  const ids = productIds.split(',').map(s => s.trim());
  const products: CDMProduct[] = [];
  for (const id of ids) {
    const p = productStore.get(id);
    if (!p) return { error: `Product not found: ${id}`, code: PRODUCT_NOT_FOUND };
    products.push(p);
  }

  const defaultingParty = products[0].parties.find(p => p.partyId === partyId) ?? products[0].parties[0];

  const result = engine.closeOutNet(products, defaultingParty, 'shell-user');
  if (!result.ok) return { error: result.error, code: NETTING_FAILED };

  // Update store
  for (const p of result.value.products) {
    productStore.set(p.cellId, p);
  }
  eventStore.push(...result.value.events);

  return {
    status: 'netted',
    netAmount: result.value.netAmount,
    currency: result.value.currency,
    productsNetted: result.value.products.length,
  };
}

// ── Self-registration (module-load side effect) ──────────────────
//
// Importing this module — typically via a dynamic import in shell's
// binary entry, driven by configs/extensions/* — wires the 'cdm'
// verb into the runtime-services registry. shell's router looks up
// handlers via `getVerb('cdm')` instead of importing routeCDM directly.

registerVerb('cdm', routeCDM as (cmd: unknown, ctx: unknown) => Promise<unknown>);

```
