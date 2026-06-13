---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-complete-board.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.319206+00:00
---

# scripts/oddjobz-complete-board.ts

```ts
#!/usr/bin/env bun
import { existsSync, mkdirSync, readFileSync, appendFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { FsPersistence } from '../apps/legacy-cli/src/fs-persistence';
import { unlockWithPassphrase } from '../apps/legacy-cli/src/kek-from-passphrase';
import { ProposalStore } from '../runtime/legacy-ingest/src';
import type { Proposal } from '../runtime/legacy-ingest/src/extractor/types';

type JsonRecord = Record<string, unknown>;

interface SiteRow extends JsonRecord {
  cellId?: string;
  fullAddress?: string;
  normalisedAddress?: string;
  keyNumber?: string | null;
}

interface CustomerRow extends JsonRecord {
  cellId?: string;
  display_name?: string;
  phone?: string;
  email?: string;
  role?: string;
}

interface AttachmentRow extends JsonRecord {
  cellId?: string;
  jobRef?: string;
  sourceBlobKey?: string;
  mimeType?: string;
  mime_type?: string;
  pageCount?: number | null;
  photoCount?: number | null;
  hasPhotos?: boolean;
}

interface JobRow extends JsonRecord {
  id?: string;
  cellId?: string;
  customer_name?: string;
  state?: string;
  workOrderNumber?: string | null;
  issuanceDate?: string | null;
  dueDate?: string | null;
  propertyKey?: string | null;
  billingParty?: { name?: string; type?: string };
  siteRef?: string;
  customerRefs?: Array<{ cellId?: string; role?: string; primary?: boolean }>;
  sourceAttachmentPath?: string;
  summary?: string;
}

interface ContactDetail {
  name: string;
  role: string;
  phone: string;
  email: string;
  primary: boolean;
}

interface CompletionMarker {
  ts: number;
  kind: 'completed';
  itemKey: string;
  completedAt: string;
  provider?: string;
  workOrderNumber?: string;
  address?: string;
  summary?: string;
  source?: string;
}

interface BoardItem {
  itemKey: string;
  provider: 'RJR' | 'Clever';
  kind: string;
  workOrderNumber: string;
  address: string;
  dueDate: string | null;
  issuedDate: string | null;
  keyNumber: string | null;
  primaryContact: string;
  phone: string;
  agent: string;
  summary: string;
  source: 'graph' | 'pending';
  status: string;
  completed: boolean;
  highlight: boolean;
  graphId: string;
  siteRef: string;
  sourceAttachmentPath: string;
  proposalId: string;
  providerItemId: string;
  threadKey: string;
  contacts: ContactDetail[];
  sourceBlobKeys: string[];
}

const root = process.env.SEMANTOS_ROOT ?? join(mustHome(), '.semantos');
const dataDir = process.env.BRAIN_DATA_DIR ?? join(root, 'data');
const oddjobzDir = join(dataDir, 'oddjobz');
const completionsPath = process.env.ODDJOBZ_COMPLETIONS_PATH
  ?? join(oddjobzDir, 'job-completions.jsonl');
const port = Number(process.env.PORT ?? process.argv.find(a => a.startsWith('--port='))?.split('=')[1] ?? 8787);
let unlockedLegacyPassphrase = process.env.ODDJOBZ_LEGACY_PASSPHRASE?.trim() || null;

function mustHome(): string {
  const home = process.env.HOME ?? process.env.USERPROFILE;
  if (!home) throw new Error('cannot determine HOME');
  return home;
}

function readJsonl<T extends JsonRecord>(path: string): T[] {
  if (!existsSync(path)) return [];
  return readFileSync(path, 'utf8')
    .split(/\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => JSON.parse(line) as T);
}

function completionMarkers(): CompletionMarker[] {
  return readJsonl<CompletionMarker>(completionsPath);
}

function completedKeys(): Set<string> {
  return new Set(completionMarkers()
    .filter((m) => m.kind === 'completed' && m.itemKey)
    .map((m) => m.itemKey));
}

function normaliseProvider(raw: string | null | undefined): 'RJR' | 'Clever' | null {
  const v = (raw ?? '').toLowerCase();
  if (v.includes('robert james') || v === 'rjr') return 'RJR';
  if (v.includes('clever')) return 'Clever';
  return null;
}

function normaliseAddress(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/\bqueensland\b/g, 'qld')
    .replace(/\s+/g, ' ')
    .replace(/[.,]/g, '')
    .trim();
}

function normaliseWorkOrder(raw: string | null | undefined): string {
  const v = String(raw ?? '').trim().toUpperCase();
  return /^\d+$/.test(v) ? String(Number(v)) : v;
}

function itemKey(provider: 'RJR' | 'Clever', workOrderNumber: string, address: string): string {
  return [
    provider,
    normaliseWorkOrder(workOrderNumber),
    normaliseAddress(address),
  ].join('|');
}

function bestByKey(items: BoardItem[]): BoardItem[] {
  const byKey = new Map<string, BoardItem>();
  for (const item of items) {
    const prev = byKey.get(item.itemKey);
    if (!prev) {
      byKey.set(item.itemKey, item);
      continue;
    }
    byKey.set(item.itemKey, mergeBetter(prev, item));
  }
  return [...byKey.values()];
}

function mergeBetter(a: BoardItem, b: BoardItem): BoardItem {
  const primary = scoreItem(b) > scoreItem(a) ? { ...b } : { ...a };
  const secondary = primary === b ? a : b;
  return {
    ...primary,
    dueDate: primary.dueDate ?? secondary.dueDate,
    issuedDate: primary.issuedDate ?? secondary.issuedDate,
    keyNumber: primary.keyNumber ?? secondary.keyNumber,
    primaryContact: primary.primaryContact || secondary.primaryContact,
    phone: primary.phone || secondary.phone,
    agent: primary.agent || secondary.agent,
    summary: primary.summary || secondary.summary,
    status: primary.status || secondary.status,
    completed: primary.completed || secondary.completed,
    highlight: primary.highlight || secondary.highlight,
    graphId: primary.graphId || secondary.graphId,
    siteRef: primary.siteRef || secondary.siteRef,
    sourceAttachmentPath: primary.sourceAttachmentPath || secondary.sourceAttachmentPath,
    proposalId: primary.proposalId || secondary.proposalId,
    providerItemId: primary.providerItemId || secondary.providerItemId,
    threadKey: primary.threadKey || secondary.threadKey,
    contacts: primary.contacts.length >= secondary.contacts.length ? primary.contacts : secondary.contacts,
    sourceBlobKeys: [...new Set([...primary.sourceBlobKeys, ...secondary.sourceBlobKeys])],
  };
}

function scoreItem(item: BoardItem): number {
  return [
    item.source === 'pending' ? 3 : 0,
    item.summary ? 3 : 0,
    item.dueDate ? 2 : 0,
    item.primaryContact ? 1 : 0,
    item.phone ? 1 : 0,
    item.keyNumber ? 1 : 0,
  ].reduce((a, b) => a + b, 0);
}

function sortItems(items: BoardItem[]): BoardItem[] {
  return items.sort((a, b) => {
    if (a.highlight !== b.highlight) return a.highlight ? -1 : 1;
    const ad = a.dueDate ? Date.parse(a.dueDate) : 0;
    const bd = b.dueDate ? Date.parse(b.dueDate) : 0;
    if (ad !== bd) return bd - ad;
    return a.provider.localeCompare(b.provider) || a.address.localeCompare(b.address);
  });
}

function loadGraphItems(completed: Set<string>): BoardItem[] {
  const sites = new Map(readJsonl<SiteRow>(join(oddjobzDir, 'sites.jsonl'))
    .filter((row) => row.cellId)
    .map((row) => [row.cellId!, row]));
  const customers = new Map(readJsonl<CustomerRow>(join(oddjobzDir, 'customers.jsonl'))
    .filter((row) => row.cellId)
    .map((row) => [row.cellId!, row]));
  const attachmentsByJob = new Map<string, AttachmentRow[]>();
  for (const attachment of readJsonl<AttachmentRow>(join(oddjobzDir, 'attachments.jsonl'))) {
    if (!attachment.jobRef) continue;
    const current = attachmentsByJob.get(attachment.jobRef) ?? [];
    current.push(attachment);
    attachmentsByJob.set(attachment.jobRef, current);
  }

  return readJsonl<JobRow>(join(oddjobzDir, 'jobs.jsonl'))
    .map((job) => {
      const provider = normaliseProvider(job.billingParty?.name);
      if (!provider || !job.workOrderNumber) return null;
      const site = job.siteRef ? sites.get(job.siteRef) : undefined;
      const address = site?.fullAddress ?? site?.normalisedAddress ?? '';
      if (!address) return null;
      const contacts = (job.customerRefs ?? [])
        .map((ref) => ({ ref, customer: ref.cellId ? customers.get(ref.cellId) : undefined }))
        .filter((entry) => entry.customer?.display_name);
      const primary = contacts.find((entry) => entry.ref.primary) ?? contacts[0];
      const agent = contacts.find((entry) => /pm|agent/i.test(entry.ref.role ?? entry.customer?.role ?? ''));
      const workOrderNumber = String(job.workOrderNumber);
      const key = itemKey(provider, workOrderNumber, address);
      const graphId = job.cellId ?? job.id ?? '';
      const attachments = graphId ? attachmentsByJob.get(graphId) ?? [] : [];
      const sourceBlobKeys = [
        ...attachments.map((attachment) => attachment.sourceBlobKey).filter(isNonEmptyString),
        job.sourceAttachmentPath,
      ].filter(isNonEmptyString);
      return {
        itemKey: key,
        provider,
        kind: 'Work Order',
        workOrderNumber,
        address,
        dueDate: job.dueDate ?? null,
        issuedDate: job.issuanceDate ?? null,
        keyNumber: job.propertyKey ?? site?.keyNumber ?? null,
        primaryContact: primary?.customer?.display_name ?? cleanDisplayName(job.customer_name ?? ''),
        phone: primary?.customer?.phone ?? '',
        agent: agent?.customer?.display_name ?? '',
        summary: job.summary ?? '',
        source: 'graph',
        status: String(job.state ?? ''),
        completed: completed.has(key),
        highlight: isMoorindilStartJob(workOrderNumber, address),
        graphId,
        siteRef: job.siteRef ?? '',
        sourceAttachmentPath: job.sourceAttachmentPath ?? '',
        proposalId: '',
        providerItemId: '',
        threadKey: '',
        contacts: contacts.map(({ ref, customer }) => ({
          name: customer?.display_name ?? '',
          role: ref.role ?? customer?.role ?? '',
          phone: customer?.phone ?? '',
          email: customer?.email ?? '',
          primary: Boolean(ref.primary),
        })),
        sourceBlobKeys: [...new Set(sourceBlobKeys)],
      } satisfies BoardItem;
    })
    .filter((item): item is BoardItem => item !== null);
}

async function loadPendingItems(passphrase: string | null, completed: Set<string>): Promise<BoardItem[]> {
  if (!passphrase) return [];
  const kek = await unlockWithPassphrase(passphrase);
  const store = new ProposalStore({
    persistence: new FsPersistence({ root }),
    kekProvider: async () => kek,
  });
  await verifyProposalPassphrase(store);
  const proposals = await store.list({ providerId: 'gmail', status: 'pending' });
  return proposals
    .map((proposal) => proposalToBoardItem(proposal, completed))
    .filter((item): item is BoardItem => item !== null);
}

async function verifyProposalPassphrase(store: ProposalStore): Promise<void> {
  const dir = join(root, 'legacy-proposals', 'gmail');
  if (!existsSync(dir)) return;
  const first = readdirSync(dir)
    .find((name) => name.endsWith('.enc'));
  if (!first) return;
  try {
    await store.get('gmail', first.replace(/\.enc$/, ''));
  } catch {
    throw new Error('That passphrase did not unlock the encrypted proposal queue. Check the characters and try Load again.');
  }
}

function proposalToBoardItem(proposal: Proposal, completed: Set<string>): BoardItem | null {
  const provider = normaliseProvider(proposal.billingParty?.name ?? proposal.summary);
  if (!provider || !proposal.workOrderNumber || !proposal.propertyAddress) return null;
  const workOrderNumber = String(proposal.workOrderNumber);
  const key = itemKey(provider, workOrderNumber, proposal.propertyAddress);
  const secondary = proposal.secondaryContacts ?? [];
  const agent = secondary.find((c) => /pm|agent/i.test(c.role));
  return {
    itemKey: key,
    provider,
    kind: inferKind(proposal),
    workOrderNumber,
    address: proposal.propertyAddress,
    dueDate: proposal.dueDate ?? null,
    issuedDate: proposal.issuanceDate ?? null,
    keyNumber: proposal.propertyKey ?? null,
    primaryContact: proposal.primaryContact?.name ?? proposal.pointOfContact ?? '',
    phone: proposal.primaryContact?.phone ?? '',
    agent: agent?.name ?? '',
    summary: proposal.summary ?? '',
    source: 'pending',
    status: proposal.status,
    completed: completed.has(key),
    highlight: isMoorindilStartJob(workOrderNumber, proposal.propertyAddress),
    graphId: '',
    siteRef: '',
    sourceAttachmentPath: proposal.sourceAttachmentPath ?? '',
    proposalId: proposal.proposalId,
    providerItemId: proposal.provenance.providerItemId,
    threadKey: proposal.threadKey ?? '',
    contacts: [
      proposal.primaryContact
        ? {
            name: proposal.primaryContact.name,
            role: proposal.primaryContact.role,
            phone: proposal.primaryContact.phone ?? '',
            email: proposal.primaryContact.email ?? '',
            primary: true,
          }
        : null,
      ...secondary.map((c) => ({
        name: c.name,
        role: c.role,
        phone: c.phone ?? '',
        email: c.email ?? '',
        primary: false,
      })),
    ].filter((c): c is ContactDetail => c !== null),
    sourceBlobKeys: proposal.sourceAttachmentPath ? [proposal.sourceAttachmentPath] : [],
  };
}

function inferKind(proposal: Proposal): string {
  const text = `${proposal.summary ?? ''} ${proposal.program ? JSON.stringify(proposal.program).slice(0, 500) : ''}`.toLowerCase();
  if (text.includes('quote request') || text.includes('quote')) return 'Quote';
  return 'Work Order';
}

function cleanDisplayName(raw: string): string {
  return raw.replace(/\s*\((tenant|pm|agent|owner|other)\)\s*/gi, '').trim();
}

function isMoorindilStartJob(workOrderNumber: string, address: string): boolean {
  return normaliseWorkOrder(workOrderNumber) === '2512039176'
    || normaliseAddress(address).includes('unit 19/139 moorindil');
}

function isNonEmptyString(v: unknown): v is string {
  return typeof v === 'string' && v.trim().length > 0;
}

async function boardItems(passphrase: string | null, includeCompleted: boolean): Promise<{ items: BoardItem[]; completedCount: number; pendingUnlocked: boolean; graphCount: number; pendingCount: number }> {
  const completed = completedKeys();
  const graph = loadGraphItems(completed);
  const pending = await loadPendingItems(passphrase, completed);
  const items = bestByKey([...graph, ...pending]);
  const filtered = includeCompleted ? items : items.filter((item) => !item.completed);
  return {
    items: sortItems(filtered),
    completedCount: completed.size,
    pendingUnlocked: Boolean(passphrase),
    graphCount: graph.filter((item) => includeCompleted || !item.completed).length,
    pendingCount: pending.filter((item) => includeCompleted || !item.completed).length,
  };
}

function appendCompletions(items: BoardItem[]): number {
  if (items.length === 0) return 0;
  mkdirSync(dirname(completionsPath), { recursive: true, mode: 0o700 });
  const existing = completedKeys();
  let written = 0;
  for (const item of items) {
    if (!item.itemKey || existing.has(item.itemKey)) continue;
    const marker: CompletionMarker = {
      ts: Date.now(),
      kind: 'completed',
      itemKey: item.itemKey,
      completedAt: new Date().toISOString(),
      provider: item.provider,
      workOrderNumber: item.workOrderNumber,
      address: item.address,
      summary: item.summary,
      source: item.source,
    };
    appendFileSync(completionsPath, `${JSON.stringify(marker)}\n`, { mode: 0o600 });
    existing.add(item.itemKey);
    written += 1;
  }
  return written;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

Bun.serve({
  port,
  hostname: '127.0.0.1',
  async fetch(req) {
    const url = new URL(req.url);
    if (req.method === 'GET' && url.pathname === '/') {
      try {
        const data = await boardItems(unlockedLegacyPassphrase, false);
        return new Response(renderHtml(data), {
          headers: {
            'content-type': 'text/html; charset=utf-8',
            'cache-control': 'no-store',
          },
        });
      } catch (err) {
        return new Response(renderErrorHtml(err instanceof Error ? err.message : String(err)), {
          status: 500,
          headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
        });
      }
    }
    if (req.method === 'POST' && url.pathname === '/api/jobs') {
      try {
        const body = await req.json().catch(() => ({})) as { passphrase?: string; includeCompleted?: boolean };
        const suppliedPassphrase = body.passphrase?.trim() || null;
        if (suppliedPassphrase) unlockedLegacyPassphrase = suppliedPassphrase;
        return json(await boardItems(unlockedLegacyPassphrase, Boolean(body.includeCompleted)));
      } catch (err) {
        return json({ error: err instanceof Error ? err.message : String(err) }, 400);
      }
    }
    if (req.method === 'POST' && url.pathname === '/api/complete') {
      try {
        const body = await req.json().catch(() => ({})) as { items?: BoardItem[] };
        const selected = Array.isArray(body.items) ? body.items : [];
        return json({ ok: true, completed: appendCompletions(selected) });
      } catch (err) {
        return json({ error: err instanceof Error ? err.message : String(err) }, 400);
      }
    }
    if (req.method === 'POST' && url.pathname === '/complete-form') {
      try {
        const form = await req.formData();
        const keys = new Set(form.getAll('itemKey').map((v) => String(v)));
        const data = await boardItems(unlockedLegacyPassphrase, true);
        const selected = data.items.filter((item) => keys.has(item.itemKey));
        appendCompletions(selected);
        return Response.redirect('http://127.0.0.1:' + port + '/', 303);
      } catch (err) {
        return new Response(renderErrorHtml(err instanceof Error ? err.message : String(err)), {
          status: 400,
          headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' },
        });
      }
    }
    return new Response('not found', { status: 404 });
  },
});

console.log(`Oddjobz completion board listening on http://127.0.0.1:${port}`);
console.log(`Completion markers: ${completionsPath}`);

function escapeHtml(value: unknown): string {
  return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[ch] ?? ch);
}

function compactId(value: string): string {
  if (!value) return '';
  return value.length > 18 ? `${value.slice(0, 10)}...${value.slice(-8)}` : value;
}

function detailsHtml(job: BoardItem): string {
  const detailRows = [
    ['Job cell', compactId(job.graphId)],
    ['Site cell', compactId(job.siteRef)],
    ['Proposal', compactId(job.proposalId)],
    ['Provider item', job.providerItemId],
    ['Thread', compactId(job.threadKey)],
    ['Source attachment', job.sourceAttachmentPath],
  ].filter(([, value]) => value);
  const sourceBlobRows = job.sourceBlobKeys
    .slice(0, 5)
    .map((key) => `<li>${escapeHtml(key)}</li>`)
    .join('');
  const contactRows = job.contacts
    .map((c) => {
      const role = [c.primary ? 'primary' : '', c.role].filter(Boolean).join(' ');
      const line = [c.name, role ? `(${role})` : '', c.phone, c.email].filter(Boolean).join(' ');
      return `<li>${escapeHtml(line)}</li>`;
    })
    .join('');
  return `
    <details class="drawer">
      <summary>Conversation / evidence</summary>
      <div class="drawer-grid">
        <section>
          <h2>Refs</h2>
          ${detailRows.length ? `<dl>${detailRows.map(([label, value]) => `<dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd>`).join('')}</dl>` : '<p class="meta">No graph refs yet.</p>'}
        </section>
        <section>
          <h2>Contacts</h2>
          ${contactRows ? `<ul>${contactRows}</ul>` : '<p class="meta">No contact cells linked yet.</p>'}
        </section>
        <section>
          <h2>Source</h2>
          ${sourceBlobRows ? `<ul>${sourceBlobRows}</ul>` : '<p class="meta">No source attachment linked yet.</p>'}
        </section>
      </div>
      <p class="meta intent-note">Meta/widget/voice turns should land here as oddjobz.message.v1 patches against this job, site, or customer.</p>
    </details>
  `;
}

function rowHtml(job: BoardItem): string {
  const due = job.dueDate ? 'Due ' + job.dueDate : 'No due date';
  const key = job.keyNumber ? 'Key ' + job.keyNumber.replace(/^key\s*/i, '') : '';
  const contact = [job.primaryContact, job.phone].filter(Boolean).join(' - ');
  const agent = job.agent ? 'Agent ' + job.agent : '';
  const source = job.source === 'pending' ? 'pending proposal' : 'graph';
  return `
    <article class="row ${job.highlight ? 'highlight' : ''}" data-key="${escapeHtml(job.itemKey)}">
      <input type="checkbox" name="itemKey" value="${escapeHtml(job.itemKey)}" aria-label="Complete ${escapeHtml(job.workOrderNumber)}" />
      <div class="provider">${escapeHtml(job.provider)}</div>
      <div><div class="wo">${escapeHtml(job.workOrderNumber)}</div><div class="meta">${escapeHtml(job.kind)} - ${escapeHtml(source)}</div></div>
      <div class="addr">${escapeHtml(job.address)}</div>
      <div class="meta">${escapeHtml([due, key].filter(Boolean).join(' - '))}</div>
      <div class="meta">${escapeHtml([contact, agent].filter(Boolean).join(' - '))}</div>
      <div></div><div></div><div></div>
      <div class="summary-text">${escapeHtml(job.summary || '')}</div>
      ${detailsHtml(job)}
    </article>
  `;
}

function renderErrorHtml(message: string): string {
  return `<!doctype html><meta charset="utf-8"><title>Oddjobz Board Error</title><body style="font-family:system-ui;padding:24px"><h1>Oddjobz board error</h1><p>${escapeHtml(message)}</p><p><a href="/">Back</a></p></body>`;
}

function renderHtml(initial: Awaited<ReturnType<typeof boardItems>>): string {
  const initialJson = JSON.stringify(initial).replace(/</g, '\\u003c');
  const rows = initial.items.map(rowHtml).join('');
  const stateText = initial.pendingUnlocked
    ? 'Graph + encrypted pending proposals'
    : 'Graph only; restart the local board unlocked to include pending proposals';
  const stateClass = initial.pendingUnlocked ? 'pill good' : 'pill warn';
  return String.raw`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Oddjobz Completion Board</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #17211d;
      --muted: #5f6f67;
      --line: #d9e0dc;
      --soft: #f3f6f4;
      --panel: #ffffff;
      --green: #0d7c59;
      --blue: #2457a6;
      --amber: #9a5b00;
      --danger: #a33b2b;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    * { box-sizing: border-box; }
    body { margin: 0; background: #eef2ef; color: var(--ink); }
    main { max-width: 1180px; margin: 0 auto; padding: 24px 18px 40px; }
    header { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 16px; }
    h1 { margin: 0 0 4px; font-size: 28px; line-height: 1.1; letter-spacing: 0; }
    p { margin: 0; color: var(--muted); }
    .toolbar {
      display: grid;
      grid-template-columns: minmax(220px, 1fr) auto auto auto;
      gap: 10px;
      align-items: center;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
      position: sticky;
      top: 0;
      z-index: 2;
      box-shadow: 0 8px 20px rgba(23,33,29,.06);
    }
    input, select, button {
      height: 40px;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 0 12px;
      font: inherit;
      background: #fff;
      color: var(--ink);
    }
    input[type="checkbox"] { height: 18px; width: 18px; padding: 0; }
    button { cursor: pointer; font-weight: 700; }
    button.primary { background: var(--green); color: #fff; border-color: var(--green); }
    button.secondary { background: #f8faf9; }
    button:disabled { opacity: .5; cursor: not-allowed; }
    .summary {
      display: flex;
      gap: 12px;
      align-items: center;
      flex-wrap: wrap;
      margin: 14px 0;
      color: var(--muted);
      font-size: 14px;
    }
    .pill { border: 1px solid var(--line); border-radius: 999px; padding: 5px 9px; background: #fff; }
    .pill.good { color: var(--green); border-color: #9ed7c4; background: #edf9f4; }
    .pill.warn { color: var(--amber); border-color: #e6c98e; background: #fff8e9; }
    .list { display: grid; gap: 9px; }
    .row {
      display: grid;
      grid-template-columns: 28px 72px minmax(110px, .6fr) minmax(220px, 1.2fr) minmax(110px, .7fr) minmax(180px, 1fr);
      gap: 10px;
      align-items: center;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 11px 12px;
    }
    .row.highlight { border-color: #e1ab4e; background: #fff9eb; }
    .row.hidden { display: none; }
    .provider { font-weight: 800; color: var(--blue); }
    .wo { font-weight: 800; }
    .addr { font-weight: 700; }
    .meta, .summary-text { color: var(--muted); font-size: 13px; line-height: 1.35; }
    .summary-text { grid-column: 4 / -1; }
    .drawer {
      grid-column: 3 / -1;
      border-top: 1px solid var(--line);
      padding-top: 8px;
      color: var(--muted);
      font-size: 13px;
    }
    .drawer summary {
      cursor: pointer;
      font-weight: 800;
      color: var(--ink);
      width: fit-content;
    }
    .drawer-grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 12px;
      margin-top: 10px;
    }
    .drawer h2 {
      margin: 0 0 6px;
      font-size: 12px;
      line-height: 1.2;
      text-transform: uppercase;
      color: var(--muted);
      letter-spacing: 0;
    }
    .drawer dl, .drawer ul { margin: 0; }
    .drawer dl {
      display: grid;
      grid-template-columns: 92px minmax(0, 1fr);
      gap: 4px 8px;
    }
    .drawer dt { font-weight: 700; color: var(--ink); }
    .drawer dd { margin: 0; word-break: break-word; }
    .drawer ul { padding-left: 18px; }
    .drawer li { margin: 0 0 4px; word-break: break-word; }
    .intent-note { margin-top: 10px; }
    .empty {
      margin-top: 24px;
      padding: 28px;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      text-align: center;
      color: var(--muted);
    }
    .error { color: var(--danger); font-weight: 700; }
    @media (max-width: 860px) {
      .toolbar { grid-template-columns: 1fr; position: static; }
      header { display: block; }
      .row { grid-template-columns: 28px 72px 1fr; align-items: start; }
      .addr, .meta, .summary-text, .drawer { grid-column: 3 / -1; }
      .drawer-grid { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <main>
    <header>
      <div>
        <h1>Oddjobz Completion Board</h1>
        <p>Tick completed RJR/Clever jobs, submit, and they disappear from this view.</p>
      </div>
    </header>

    <section class="toolbar">
      <input id="search" autocomplete="off" placeholder="Search address, WO, tenant, task" />
      <select id="provider">
        <option value="">All providers</option>
        <option value="RJR">RJR</option>
        <option value="Clever">Clever</option>
      </select>
      <input id="passphrase" type="password" autocomplete="current-password" placeholder="Optional: unlock pending queue" />
      <button id="reload" class="secondary">Load</button>
      <button id="submit" class="primary" type="submit" form="jobs-form" disabled>Mark selected completed</button>
    </section>

    <div class="summary">
      <span id="count" class="pill">${initial.items.length} visible / ${initial.items.length} loaded</span>
      <span id="selected" class="pill">0 selected</span>
      <span id="pendingState" class="${stateClass}">${stateText}</span>
      <span id="message">${initial.graphCount} graph rows, ${initial.pendingCount} pending rows loaded; ${initial.completedCount} completed markers hidden</span>
    </div>

    <form id="jobs-form" class="list" method="post" action="/complete-form">${rows}</form>
    <div id="empty" class="empty" ${initial.items.length === 0 ? '' : 'hidden'}>No visible jobs. Nice and quiet.</div>
  </main>

  <script>
    const initialData = ${initialJson};
    let jobs = initialData.items || [];
    const selected = new Set();

    const els = {
      list: document.getElementById('jobs-form'),
      empty: document.getElementById('empty'),
      count: document.getElementById('count'),
      selected: document.getElementById('selected'),
      pendingState: document.getElementById('pendingState'),
      message: document.getElementById('message'),
      search: document.getElementById('search'),
      provider: document.getElementById('provider'),
      passphrase: document.getElementById('passphrase'),
      reload: document.getElementById('reload'),
      submit: document.getElementById('submit'),
    };

    function esc(value) {
      return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
      })[ch]);
    }

    function compact(value) {
      const s = String(value || '');
      return s.length > 18 ? s.slice(0, 10) + '...' + s.slice(-8) : s;
    }

    function detailHtml(job) {
      const detailRows = [
        ['Job cell', compact(job.graphId)],
        ['Site cell', compact(job.siteRef)],
        ['Proposal', compact(job.proposalId)],
        ['Provider item', job.providerItemId],
        ['Thread', compact(job.threadKey)],
        ['Source attachment', job.sourceAttachmentPath],
      ].filter((row) => row[1]);
      const refs = detailRows.length
        ? '<dl>' + detailRows.map(([label, value]) => '<dt>' + esc(label) + '</dt><dd>' + esc(value) + '</dd>').join('') + '</dl>'
        : '<p class="meta">No graph refs yet.</p>';
      const contacts = (job.contacts || []).length
        ? '<ul>' + job.contacts.map((c) => {
            const role = [c.primary ? 'primary' : '', c.role].filter(Boolean).join(' ');
            return '<li>' + esc([c.name, role ? '(' + role + ')' : '', c.phone, c.email].filter(Boolean).join(' ')) + '</li>';
          }).join('') + '</ul>'
        : '<p class="meta">No contact cells linked yet.</p>';
      const source = (job.sourceBlobKeys || []).length
        ? '<ul>' + job.sourceBlobKeys.slice(0, 5).map((key) => '<li>' + esc(key) + '</li>').join('') + '</ul>'
        : '<p class="meta">No source attachment linked yet.</p>';
      return \`
        <details class="drawer">
          <summary>Conversation / evidence</summary>
          <div class="drawer-grid">
            <section><h2>Refs</h2>\${refs}</section>
            <section><h2>Contacts</h2>\${contacts}</section>
            <section><h2>Source</h2>\${source}</section>
          </div>
          <p class="meta intent-note">Meta/widget/voice turns should land here as oddjobz.message.v1 patches against this job, site, or customer.</p>
        </details>
      \`;
    }

    function matches(job) {
      const provider = els.provider.value;
      if (provider && job.provider !== provider) return false;
      const q = els.search.value.trim().toLowerCase();
      if (!q) return true;
      return [job.provider, job.kind, job.workOrderNumber, job.address, job.primaryContact, job.phone, job.agent, job.summary]
        .join(' ')
        .toLowerCase()
        .includes(q);
    }

    function render() {
      const visible = jobs.filter(matches);
      els.list.innerHTML = visible.map((job) => {
        const checked = selected.has(job.itemKey) ? 'checked' : '';
        const due = job.dueDate ? 'Due ' + job.dueDate : 'No due date';
        const key = job.keyNumber ? 'Key #' + job.keyNumber : '';
        const contact = [job.primaryContact, job.phone].filter(Boolean).join(' · ');
        const agent = job.agent ? 'Agent ' + job.agent : '';
        const source = job.source === 'pending' ? 'pending proposal' : 'graph';
        return \`
          <article class="row \${job.highlight ? 'highlight' : ''}" data-key="\${esc(job.itemKey)}">
            <input type="checkbox" name="itemKey" value="\${esc(job.itemKey)}" \${checked} aria-label="Complete \${esc(job.workOrderNumber)}" />
            <div class="provider">\${esc(job.provider)}</div>
            <div><div class="wo">\${esc(job.workOrderNumber)}</div><div class="meta">\${esc(job.kind)} - \${esc(source)}</div></div>
            <div class="addr">\${esc(job.address)}</div>
            <div class="meta">\${esc([due, key].filter(Boolean).join(' · '))}</div>
            <div class="meta">\${esc([contact, agent].filter(Boolean).join(' · '))}</div>
            <div></div><div></div><div></div>
            <div class="summary-text">\${esc(job.summary || '')}</div>
            \${detailHtml(job)}
          </article>
        \`;
      }).join('');
      els.empty.hidden = visible.length !== 0;
      els.count.textContent = visible.length + ' visible / ' + jobs.length + ' loaded';
      els.selected.textContent = selected.size + ' selected';
      els.submit.disabled = selected.size === 0;
    }

    async function load() {
        els.message.textContent = els.passphrase.value ? 'Unlocking pending queue...' : 'Loading...';
      els.message.className = '';
      try {
        const response = await fetch('/api/jobs', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({ passphrase: els.passphrase.value }),
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || 'load failed');
        jobs = data.items;
        selected.clear();
        els.pendingState.textContent = data.pendingUnlocked
          ? 'Graph + encrypted pending proposals'
          : 'Graph only; enter passphrase once to unlock pending';
        els.pendingState.className = data.pendingUnlocked ? 'pill good' : 'pill warn';
        els.message.textContent = data.graphCount + ' graph rows, ' + data.pendingCount + ' pending rows loaded; ' + data.completedCount + ' completed markers hidden';
        if (data.pendingUnlocked && !els.passphrase.value) {
          els.passphrase.placeholder = 'Pending queue already unlocked for this local session';
        }
        render();
      } catch (err) {
        els.message.textContent = err.message || String(err);
        els.message.className = 'error';
      }
    }

    async function completeSelected() {
      const items = jobs.filter((job) => selected.has(job.itemKey));
      if (items.length === 0) return;
      els.submit.disabled = true;
      els.message.textContent = 'Writing completion markers...';
      const response = await fetch('/api/complete', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ items }),
      });
      const data = await response.json();
      if (!response.ok) {
        els.message.textContent = data.error || 'complete failed';
        els.message.className = 'error';
        render();
        return;
      }
      jobs = jobs.filter((job) => !selected.has(job.itemKey));
      selected.clear();
      els.message.textContent = 'Marked ' + data.completed + ' completed';
      els.message.className = '';
      render();
    }

    els.list.addEventListener('change', (event) => {
      const checkbox = event.target;
      if (!(checkbox instanceof HTMLInputElement)) return;
      const row = checkbox.closest('.row');
      const key = row && row.getAttribute('data-key');
      if (!key) return;
      if (checkbox.checked) selected.add(key);
      else selected.delete(key);
      render();
    });
    els.search.addEventListener('input', render);
    els.provider.addEventListener('change', render);
    els.reload.addEventListener('click', load);
    els.passphrase.addEventListener('keydown', (event) => {
      if (event.key === 'Enter') load();
    });
    els.submit.addEventListener('click', (event) => {
      event.preventDefault();
      completeSelected();
    });
    els.list.addEventListener('submit', (event) => {
      event.preventDefault();
      completeSelected();
    });
    render();
  </script>
</body>
</html>`;
}

```
