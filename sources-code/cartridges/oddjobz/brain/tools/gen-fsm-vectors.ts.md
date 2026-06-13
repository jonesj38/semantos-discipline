---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/gen-fsm-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.468796+00:00
---

# cartridges/oddjobz/brain/tools/gen-fsm-vectors.ts

```ts
/**
 * D-O4 — FSM transition conformance-vector generator.
 *
 * Emits one JSON file per FSM at
 * `cartridges/oddjobz/brain/tests/vectors/state-machines/<fsm>.json`
 * listing every valid (from, to) transition + the expected
 * successor-cell shape.
 *
 * Vector shape:
 *
 *   {
 *     "fsm":             "job" | "quote" | "visit" | "invoice",
 *     "cellTypeName":    "oddjobz.<type>.v1",
 *     "cellTypeHashHex": "<64 hex>",
 *     "transitions": [
 *       {
 *         "from":           "<state>",
 *         "to":             "<state>",
 *         "capRequired":    "cap.oddjobz.<verb>" | null,
 *         "principalKinds": ["operator" | "service", ...],
 *         "input":          (canonical cell payload before),
 *         "expectedOutput": (canonical cell payload after),
 *         "consumedCellId": "<cell-id consumed at the kernel gate>",
 *         "successorCellId": "<successor cell-id>"
 *       }
 *     ]
 *   }
 *
 * The vectors are deterministic — the same `STABLE_*` constants used
 * in the §O3 cap vectors. Re-running the generator produces byte-
 * identical files.
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  jobCellType,
  quoteCellType,
  visitCellType,
  invoiceCellType,
} from '../src/cell-types/index.js';
import {
  JOB_TRANSITIONS,
  jobCellId,
  jobTransition,
  QUOTE_TRANSITIONS,
  quoteCellId,
  quoteTransition,
  VISIT_TRANSITIONS,
  visitCellId,
  visitTransition,
  INVOICE_TRANSITIONS,
  invoiceCellId,
  invoiceTransition,
  makeConsumedCellSet,
  type PresentedCap,
  type SigningPrincipal,
} from '../src/state-machines/index.js';
import {
  capabilityByName,
  type OddjobzCapName,
} from '../src/capabilities.js';
import type { OddjobzJob } from '../src/cell-types/job.js';
import type { OddjobzQuote } from '../src/cell-types/quote.js';
import type { OddjobzVisit } from '../src/cell-types/visit.js';
import type { OddjobzInvoice } from '../src/cell-types/invoice.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT_DIR = resolve(HERE, '..', 'tests', 'vectors', 'state-machines');
mkdirSync(OUT_DIR, { recursive: true });

const NOW = '2026-05-01T00:00:00.000Z';
const STABLE_JOB_ID = '11111111-2222-3333-4444-555555555555';
const STABLE_QUOTE_ID = '12121212-3434-5656-7878-9a9a9a9a9a9a';
const STABLE_VISIT_ID = '21212121-4343-6565-8787-a9a9a9a9a9a9';
const STABLE_INVOICE_ID = 'a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5';
const AMOUNT_CENTS = 250_00;

function structuralCap(capName: OddjobzCapName): PresentedCap {
  return {
    kind: 'structural',
    domainFlag: capabilityByName[capName].domainFlag,
  };
}

interface TransitionVector {
  from: string;
  to: string;
  capRequired: string | null;
  principalKinds: readonly string[];
  input: unknown;
  expectedOutput: unknown;
  consumedCellId: string;
  successorCellId: string;
}

interface FsmVectorFile {
  fsm: string;
  cellTypeName: string;
  cellTypeHashHex: string;
  transitions: TransitionVector[];
}

/* ── Job ── */

function buildJobInputCell(state: string): OddjobzJob {
  return {
    jobId: STABLE_JOB_ID,
    status: state as OddjobzJob['status'],
    createdAt: NOW,
    updatedAt: NOW,
  };
}

function buildJobVectors(): FsmVectorFile {
  const transitions: TransitionVector[] = [];
  for (const t of JOB_TRANSITIONS) {
    const consumed = makeConsumedCellSet();
    const cell = buildJobInputCell(t.from);
    const presentedCap = t.capRequired === null ? null : structuralCap(t.capRequired);
    const principal = t.principalKinds[0] as SigningPrincipal;
    const r = jobTransition({
      cell,
      to: t.to,
      presentedCap,
      principal,
      nowIso: NOW,
      consumed,
    });
    if (!r.ok) throw new Error(`vector build failed for Job ${t.from}→${t.to}: ${JSON.stringify(r.error)}`);
    transitions.push({
      from: t.from,
      to: t.to,
      capRequired: t.capRequired,
      principalKinds: t.principalKinds,
      input: cell,
      expectedOutput: r.value.cell,
      consumedCellId: r.value.consumedCellId,
      successorCellId: r.value.successorCellId,
    });
  }
  return {
    fsm: 'job',
    cellTypeName: jobCellType.name,
    cellTypeHashHex: jobCellType.typeHashHex,
    transitions,
  };
}

/* ── Quote ── */

function buildQuoteInputCell(state: string): OddjobzQuote {
  return {
    quoteId: STABLE_QUOTE_ID,
    jobId: STABLE_JOB_ID,
    status: state as OddjobzQuote['status'],
    costMin: 50_00,
    costMax: 200_00,
    createdAt: NOW,
    updatedAt: NOW,
  };
}

function buildQuoteVectors(): FsmVectorFile {
  const transitions: TransitionVector[] = [];
  for (const t of QUOTE_TRANSITIONS) {
    const consumed = makeConsumedCellSet();
    const cell = buildQuoteInputCell(t.from);
    const principal = t.principalKinds[0] as SigningPrincipal;
    const r = quoteTransition({
      cell,
      to: t.to,
      principal,
      nowIso: NOW,
      consumed,
    });
    if (!r.ok) throw new Error(`vector build failed for Quote ${t.from}→${t.to}: ${JSON.stringify(r.error)}`);
    transitions.push({
      from: t.from,
      to: t.to,
      capRequired: t.capRequired,
      principalKinds: t.principalKinds,
      input: cell,
      expectedOutput: r.value.cell,
      consumedCellId: r.value.consumedCellId,
      successorCellId: r.value.successorCellId,
    });
  }
  return {
    fsm: 'quote',
    cellTypeName: quoteCellType.name,
    cellTypeHashHex: quoteCellType.typeHashHex,
    transitions,
  };
}

/* ── Visit ── */

function buildVisitInputCell(state: string): OddjobzVisit {
  return {
    visitId: STABLE_VISIT_ID,
    jobId: STABLE_JOB_ID,
    visitType: 'scheduled_work',
    status: state as OddjobzVisit['status'],
    createdAt: NOW,
    updatedAt: NOW,
  };
}

function buildVisitVectors(): FsmVectorFile {
  const transitions: TransitionVector[] = [];
  for (const t of VISIT_TRANSITIONS) {
    const consumed = makeConsumedCellSet();
    const cell = buildVisitInputCell(t.from);
    const principal = t.principalKinds[0] as SigningPrincipal;
    const r = visitTransition({
      cell,
      to: t.to,
      principal,
      nowIso: NOW,
      outcome: t.to === 'completed' ? 'completed' : undefined,
      consumed,
    });
    if (!r.ok) throw new Error(`vector build failed for Visit ${t.from}→${t.to}: ${JSON.stringify(r.error)}`);
    transitions.push({
      from: t.from,
      to: t.to,
      capRequired: t.capRequired,
      principalKinds: t.principalKinds,
      input: cell,
      expectedOutput: r.value.cell,
      consumedCellId: r.value.consumedCellId,
      successorCellId: r.value.successorCellId,
    });
  }
  return {
    fsm: 'visit',
    cellTypeName: visitCellType.name,
    cellTypeHashHex: visitCellType.typeHashHex,
    transitions,
  };
}

/* ── Invoice ── */

function buildInvoiceInputCell(state: string): OddjobzInvoice {
  const base: OddjobzInvoice = {
    invoiceId: STABLE_INVOICE_ID,
    jobId: STABLE_JOB_ID,
    status: state as OddjobzInvoice['status'],
    amount: AMOUNT_CENTS,
    createdAt: NOW,
    updatedAt: NOW,
  };
  if (state === 'sent' || state === 'viewed' || state === 'partial' || state === 'overdue') {
    return { ...base, sentAt: NOW };
  }
  if (state === 'paid') return { ...base, sentAt: NOW, paidAt: NOW, amountPaid: AMOUNT_CENTS };
  return base;
}

function buildInvoiceVectors(): FsmVectorFile {
  const transitions: TransitionVector[] = [];
  for (const t of INVOICE_TRANSITIONS) {
    const consumed = makeConsumedCellSet();
    let cell = buildInvoiceInputCell(t.from);
    const principal = t.principalKinds[0] as SigningPrincipal;
    let amountPaid: number | undefined;
    if (t.to === 'paid') {
      amountPaid = AMOUNT_CENTS;
    } else if (t.to === 'partial') {
      amountPaid = 100_00;
    }
    const r = invoiceTransition({
      cell,
      to: t.to,
      principal,
      nowIso: NOW,
      amountPaid,
      consumed,
    });
    if (!r.ok) throw new Error(`vector build failed for Invoice ${t.from}→${t.to}: ${JSON.stringify(r.error)}`);
    transitions.push({
      from: t.from,
      to: t.to,
      capRequired: t.capRequired,
      principalKinds: t.principalKinds,
      input: cell,
      expectedOutput: r.value.cell,
      consumedCellId: r.value.consumedCellId,
      successorCellId: r.value.successorCellId,
    });
  }
  return {
    fsm: 'invoice',
    cellTypeName: invoiceCellType.name,
    cellTypeHashHex: invoiceCellType.typeHashHex,
    transitions,
  };
}

function writeVectorFile(name: string, file: FsmVectorFile): void {
  const path = resolve(OUT_DIR, `${name}.json`);
  // eslint-disable-next-line no-console
  console.log(`wrote ${file.transitions.length}-row vector for ${file.fsm} → ${path}`);
  writeFileSync(path, JSON.stringify(file, null, 2) + '\n', 'utf-8');
}

writeVectorFile('job_fsm', buildJobVectors());
writeVectorFile('quote_fsm', buildQuoteVectors());
writeVectorFile('visit_fsm', buildVisitVectors());
writeVectorFile('invoice_fsm', buildInvoiceVectors());

// eslint-disable-next-line no-console
console.log('done.');

// Avoid unused-export complaints under strict settings.
void jobCellId;
void quoteCellId;
void visitCellId;
void invoiceCellId;

```
