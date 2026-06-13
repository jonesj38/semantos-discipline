---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/diag-overdue.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.699086+00:00
---

# archive/apps-legacy-cli/src/diag-overdue.ts

```ts
#!/usr/bin/env bun
// Overdue-job scan over the reingested typed-cell corpus.
//
// "Overdue" = a v0.6 proposal that minted a job cell whose dueDate
// (or, when no explicit due date, issuanceDate + a default SLA window)
// is in the past, AND whose state is still open (lead — every fresh
// reingest mints in `lead`; completed/closed/paid are excluded).
//
// Reads the LOCAL proposal-store + reingest-receipt-store; no brain
// round-trip. The receipt store tells us which proposals actually
// minted (so we only report jobs that exist as cells on the brain).

import { ProposalStore, ReingestReceiptStore } from '@semantos/legacy-ingest';
import { unlockWithPassphrase } from './kek-from-passphrase';
import { FsPersistence } from './fs-persistence';

const root = process.env.HOME + '/.semantos';
const persistence = new FsPersistence({ root });
const passphrase = process.env.SEMANTOS_LEGACY_PASSPHRASE;
if (!passphrase) { console.error('set SEMANTOS_LEGACY_PASSPHRASE'); process.exit(1); }
const kek = await unlockWithPassphrase(passphrase);
const ps = new ProposalStore({ persistence, kekProvider: async () => kek });
const rs = new ReingestReceiptStore({ persistence, kekProvider: async () => kek });

const proposals = await ps.list({ providerId: 'gmail' });
const v06 = proposals.filter(p => p.provenance.extractorVersion === 'email-rfc822-v0.6');
const receipts = await rs.list('gmail');
const receiptByProposal = new Map(receipts.map(r => [r.proposalId, r]));

// Default SLA window when a work order carries no explicit due date:
// Clever/RJR maintenance orders are typically "attend within 14 days
// of issuance" unless flagged urgent. Tunable; surfaced in output.
const DEFAULT_SLA_DAYS = 14;
const now = new Date();
const today = now.toISOString().slice(0, 10);

interface Row {
  proposalId: string;
  jobCellId: string;
  due: string;
  dueSource: 'due_date' | 'issuance+SLA';
  daysOverdue: number;
  summary: string;
  address: string;
  wo: string;
  poc: string;
}

const overdue: Row[] = [];
const noDate: { proposalId: string; summary: string }[] = [];

for (const p of v06) {
  const receipt = receiptByProposal.get(p.proposalId);
  if (!receipt) continue; // never minted — skip

  let due: string | null = null;
  let dueSource: Row['dueSource'] = 'due_date';
  if (p.dueDate) {
    due = p.dueDate;
    dueSource = 'due_date';
  } else if (p.issuanceDate) {
    const d = new Date(p.issuanceDate + 'T00:00:00Z');
    d.setUTCDate(d.getUTCDate() + DEFAULT_SLA_DAYS);
    due = d.toISOString().slice(0, 10);
    dueSource = 'issuance+SLA';
  }
  if (!due) {
    noDate.push({ proposalId: p.proposalId, summary: (p.summary ?? '').slice(0, 70) });
    continue;
  }
  if (due >= today) continue; // not overdue yet

  const dueMs = new Date(due + 'T00:00:00Z').getTime();
  const daysOverdue = Math.floor((now.getTime() - dueMs) / 86400000);
  overdue.push({
    proposalId: p.proposalId,
    jobCellId: receipt.jobCellId,
    due,
    dueSource,
    daysOverdue,
    summary: (p.summary ?? '').slice(0, 90),
    address: p.propertyAddress ?? '(no address)',
    wo: p.workOrderNumber ?? '—',
    poc: p.pointOfContact ?? '—',
  });
}

// Collapse duplicate proposals that resolved to the same job_cell
// (job-dedupe: bundle-fanout / re-extract dupes now share a cell id).
// Keep the most-overdue row per unique jobCellId.
const byCell = new Map<string, Row>();
for (const r of overdue) {
  const prev = byCell.get(r.jobCellId);
  if (!prev || r.daysOverdue > prev.daysOverdue) byCell.set(r.jobCellId, r);
}
const uniqueOverdue = [...byCell.values()].sort((a, b) => b.daysOverdue - a.daysOverdue);
const collapsed = overdue.length - uniqueOverdue.length;

overdue.sort((a, b) => b.daysOverdue - a.daysOverdue);

console.log(`\n=== OVERDUE JOBS (${uniqueOverdue.length} unique, ${collapsed} dup proposals collapsed) — as of ${today}, SLA=${DEFAULT_SLA_DAYS}d ===\n`);
for (const r of uniqueOverdue) {
  console.log(`${String(r.daysOverdue).padStart(4)}d  WO ${r.wo.padEnd(8)}  due ${r.due} (${r.dueSource})`);
  console.log(`       ${r.address}`);
  console.log(`       ${r.summary}`);
  console.log(`       poc=${r.poc}  job_cell=${r.jobCellId.slice(0, 16)}…`);
  console.log();
}
console.log(`Proposals (v0.6 minted): ${receipts.length}`);
console.log(`Unique overdue jobs: ${uniqueOverdue.length}  (collapsed ${collapsed} duplicate proposals)`);
console.log(`No date (cannot age — operator review): ${noDate.length}`);
if (noDate.length > 0) {
  console.log('\nNo-date jobs:');
  for (const n of noDate) console.log(`  ${n.proposalId.slice(0, 12)}  ${n.summary}`);
}

```
