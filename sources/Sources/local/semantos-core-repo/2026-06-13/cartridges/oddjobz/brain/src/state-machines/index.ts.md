---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/state-machines/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.529355+00:00
---

# cartridges/oddjobz/brain/src/state-machines/index.ts

```ts
/**
 * D-O4 — Oddjobz state-machine registry.
 *
 * Re-exports the four LINEAR-cell FSMs (Job, Quote, Visit, Invoice)
 * and a registry mapping cell-type-hash-hex → FSM module so consumers
 * (the Semantos Brain dispatcher, the helm UI, the mobile shell) can dispatch
 * on the cell-type bytes coming off the wire.
 *
 * The eight oddjobz cell types per D-O2:
 *   - LINEAR (state-bearing, FSM here):
 *       oddjobz.job.v1, oddjobz.quote.v1, oddjobz.visit.v1, oddjobz.invoice.v1
 *   - AFFINE (discardable draft, no FSM):
 *       oddjobz.estimate.v1
 *   - PERSISTENT/RELEVANT (accumulating, no FSM):
 *       oddjobz.customer.v1, oddjobz.site.v1, oddjobz.message.v1
 *
 * Reference:
 *  - docs/design/ODDJOBZ-EXTENSION-PLAN.md §O4
 *  - cartridges/oddjobz/brain/src/cell-types/{job,quote,visit,invoice}.ts
 *  - cartridges/oddjobz/brain/src/cell-types/linearity.ts
 */

export * from './kernel-gate.js';
export * from './job-fsm.js';
export * from './quote-fsm.js';
export * from './visit-fsm.js';
export * from './invoice-fsm.js';

import {
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
} from '../cell-types/index.js';

import {
  JOB_TRANSITIONS,
  jobTransition,
  type JobFsmState,
} from './job-fsm.js';
import {
  QUOTE_TRANSITIONS,
  quoteTransition,
  type QuoteFsmState,
} from './quote-fsm.js';
import {
  VISIT_TRANSITIONS,
  visitTransition,
  type VisitFsmState,
} from './visit-fsm.js';
import {
  INVOICE_TRANSITIONS,
  invoiceTransition,
  type InvoiceFsmState,
} from './invoice-fsm.js';

/**
 * The FSM registry — maps each LINEAR cell-type's `typeHashHex` to a
 * record carrying the cell-type def, the canonical FSM transition
 * table, and the transition function.
 *
 * Consumers that route an inbound cell off the wire (header → typeHash
 * → 32-byte hex) look up the FSM here and dispatch the call.
 */
export interface OddjobzFsmModule {
  readonly cellTypeName: string;
  readonly cellTypeHashHex: string;
  readonly transitions: ReadonlyArray<{
    readonly from: string;
    readonly to: string;
    readonly capRequired: string | null;
    readonly principalKinds: readonly string[];
  }>;
  readonly transition: (...args: never[]) => unknown;
}

export const ODDJOBZ_FSM_MODULES: Readonly<Record<string, OddjobzFsmModule>> =
  Object.freeze({
    [jobCellType.typeHashHex]: Object.freeze({
      cellTypeName: jobCellType.name,
      cellTypeHashHex: jobCellType.typeHashHex,
      transitions: JOB_TRANSITIONS as ReadonlyArray<OddjobzFsmModule['transitions'][number]>,
      transition: jobTransition as (...args: never[]) => unknown,
    }) satisfies OddjobzFsmModule,
    [quoteCellType.typeHashHex]: Object.freeze({
      cellTypeName: quoteCellType.name,
      cellTypeHashHex: quoteCellType.typeHashHex,
      transitions: QUOTE_TRANSITIONS as ReadonlyArray<OddjobzFsmModule['transitions'][number]>,
      transition: quoteTransition as (...args: never[]) => unknown,
    }) satisfies OddjobzFsmModule,
    [visitCellType.typeHashHex]: Object.freeze({
      cellTypeName: visitCellType.name,
      cellTypeHashHex: visitCellType.typeHashHex,
      transitions: VISIT_TRANSITIONS as ReadonlyArray<OddjobzFsmModule['transitions'][number]>,
      transition: visitTransition as (...args: never[]) => unknown,
    }) satisfies OddjobzFsmModule,
    [invoiceCellType.typeHashHex]: Object.freeze({
      cellTypeName: invoiceCellType.name,
      cellTypeHashHex: invoiceCellType.typeHashHex,
      transitions: INVOICE_TRANSITIONS as ReadonlyArray<OddjobzFsmModule['transitions'][number]>,
      transition: invoiceTransition as (...args: never[]) => unknown,
    }) satisfies OddjobzFsmModule,
  });

/** Lookup an FSM module by cell-type-hash-hex; undefined if not LINEAR. */
export function fsmModuleForTypeHash(
  typeHashHex: string,
): OddjobzFsmModule | undefined {
  return ODDJOBZ_FSM_MODULES[typeHashHex];
}

/** Lookup an FSM module by canonical cell-type name. */
export function fsmModuleForTypeName(name: string): OddjobzFsmModule | undefined {
  for (const m of Object.values(ODDJOBZ_FSM_MODULES)) {
    if (m.cellTypeName === name) return m;
  }
  return undefined;
}

/** All LINEAR FSM cell-type names — used by tests + glossary asserts. */
export const ODDJOBZ_FSM_CELL_TYPE_NAMES: readonly string[] = Object.freeze([
  'oddjobz.job.v1',
  'oddjobz.quote.v1',
  'oddjobz.visit.v1',
  'oddjobz.invoice.v1',
]);

export type {
  JobFsmState,
  QuoteFsmState,
  VisitFsmState,
  InvoiceFsmState,
};

```
