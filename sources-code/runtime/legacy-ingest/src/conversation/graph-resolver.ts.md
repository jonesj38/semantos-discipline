---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/graph-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.162230+00:00
---

# runtime/legacy-ingest/src/conversation/graph-resolver.ts

```ts
/**
 * Oddjobz graph-backed conversation dispatch resolver.
 *
 * Reads the same JSONL view-store that brain/ratification writes
 * (`sites.jsonl`, `customers.jsonl`, `jobs.jsonl`, `attachments.jsonl`) and
 * turns a source-neutral message patch into dispatch candidates. This is where
 * Gmail, Meta, widget, voice, and socials start sharing the same job/customer
 * graph instead of each channel carrying its own half-context.
 */

import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type {
  ConversationDispatchCandidate,
  ConversationDispatchLane,
  ConversationDispatchResolver,
  ConversationDispatchResolverInput,
  ConversationDispatchTarget,
} from './dispatch-router';
import type { OddjobzMessagePatch } from './turn-patch-store';

type JsonRecord = Record<string, unknown>;

interface SiteRow extends JsonRecord {
  cellId?: string;
  fullAddress?: string;
  normalisedAddress?: string;
  lookupKey?: string;
}

interface CustomerRow extends JsonRecord {
  cellId?: string;
  display_name?: string;
  phone?: string;
  email?: string;
  role?: string;
  siteRef?: string;
  sourceProvenance?: {
    providerId?: string;
    providerItemId?: string;
  };
}

interface JobRow extends JsonRecord {
  id?: string;
  cellId?: string;
  customer_name?: string;
  summary?: string;
  state?: string;
  workOrderNumber?: string | null;
  siteRef?: string;
  sourceAttachmentPath?: string;
  customerRefs?: Array<{ cellId?: string; role?: string; primary?: boolean }>;
}

interface AttachmentRow extends JsonRecord {
  cellId?: string;
  jobRef?: string;
  sourceBlobKey?: string;
}

interface OddjobzGraphSnapshot {
  readonly sites: SiteRow[];
  readonly customers: CustomerRow[];
  readonly jobs: JobRow[];
  readonly attachments: AttachmentRow[];
}

export interface ConversationPaskQuery {
  getActiveContext?(): string | null;
  distance?(cellId: string, targetCellId: string, maxHops?: number): number;
  neighbours?(cellId: string, hops?: 1 | 2 | 3): string[];
}

export interface OddjobzConversationGraphResolverOpts {
  /** SEMANTOS_HOME-style root. Defaults to `SEMANTOS_HOME` or `~/.semantos`. */
  readonly root?: string;
  /** Explicit `<data>/oddjobz` directory. Overrides `root`. */
  readonly oddjobzDir?: string;
  /** Optional Pask graph query surface for proximity boosts. */
  readonly pask?: ConversationPaskQuery;
  /** Cap candidates to keep routing decisions tight and cheap. */
  readonly maxCandidates?: number;
}

export class OddjobzConversationGraphResolver {
  readonly resolve: ConversationDispatchResolver;

  private readonly oddjobzDir: string;
  private readonly pask: ConversationPaskQuery | null;
  private readonly maxCandidates: number;

  constructor(opts: OddjobzConversationGraphResolverOpts = {}) {
    this.oddjobzDir = opts.oddjobzDir ?? defaultOddjobzGraphDir(opts.root);
    this.pask = opts.pask ?? null;
    this.maxCandidates = opts.maxCandidates ?? 12;
    this.resolve = (input) => this.resolveFor(input);
  }

  private resolveFor(input: ConversationDispatchResolverInput): ConversationDispatchCandidate[] {
    const graph = loadGraph(this.oddjobzDir);
    const evidence = buildEvidence(input.patch, input.text);
    const matches = collectMatches(graph, evidence);
    const out: ConversationDispatchCandidate[] = [];

    for (const customer of matches.customers) {
      const customerTarget = customerTargetFor(customer, input.lane);
      if (customerTarget) {
        out.push({
          lane: input.lane,
          target: this.withPaskBoost(customerTarget, input),
          reason: `matched customer ${customer.display_name || customer.email || customer.cellId}`,
        });
      }
    }

    for (const site of matches.sites) {
      out.push({
        lane: input.lane,
        target: this.withPaskBoost(siteTargetFor(site), input),
        reason: `matched site ${site.fullAddress || site.normalisedAddress || site.cellId}`,
      });
    }

    for (const job of matches.jobs) {
      out.push({
        lane: input.lane,
        target: this.withPaskBoost(jobTargetFor(job), input),
        reason: job.workOrderNumber
          ? `matched job work order ${job.workOrderNumber}`
          : `matched job ${job.cellId || job.id}`,
      });
    }

    return dedupeCandidates(out)
      .sort((a, b) => b.target.score - a.target.score)
      .slice(0, this.maxCandidates);
  }

  private withPaskBoost(
    target: ConversationDispatchTarget,
    input: ConversationDispatchResolverInput,
  ): ConversationDispatchTarget {
    if (!this.pask || !target.paskCellId) return target;
    const sources = [
      this.pask.getActiveContext?.() ?? null,
      `ingest:session:${input.patch.sessionId}`,
      `ingest:participant:${hashToken(input.patch.recipientId)}`,
    ].filter((v): v is string => !!v);

    let bestBoost = 0;
    for (const source of sources) {
      try {
        const distance = this.pask.distance?.(source, target.paskCellId, 3);
        if (distance !== undefined && Number.isFinite(distance)) {
          bestBoost = Math.max(bestBoost, 0.16 / (1 + distance));
        }
      } catch {
        // Pask is a ranking hint only; graph resolution must stay usable
        // when the WASM graph is cold, absent, or mid-restore.
      }
    }
    if (bestBoost === 0) return target;
    return {
      ...target,
      score: clamp01(target.score + bestBoost),
      source: 'pask',
    };
  }
}

export function defaultOddjobzGraphDir(root?: string): string {
  const base = root ?? process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos');
  const dataDir = process.env.BRAIN_DATA_DIR ?? join(base, 'data');
  return join(dataDir, 'oddjobz');
}

function loadGraph(oddjobzDir: string): OddjobzGraphSnapshot {
  return {
    sites: readJsonl<SiteRow>(join(oddjobzDir, 'sites.jsonl')),
    customers: readJsonl<CustomerRow>(join(oddjobzDir, 'customers.jsonl')),
    jobs: readJsonl<JobRow>(join(oddjobzDir, 'jobs.jsonl')),
    attachments: readJsonl<AttachmentRow>(join(oddjobzDir, 'attachments.jsonl')),
  };
}

function readJsonl<T extends JsonRecord>(path: string): T[] {
  if (!existsSync(path)) return [];
  const out: T[] = [];
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      out.push(JSON.parse(trimmed) as T);
    } catch {
      // Leave malformed append-only rows alone; callers still get the rest of
      // the graph. This mirrors the "never block ingestion on indexing" rule.
    }
  }
  return out;
}

function buildEvidence(patch: OddjobzMessagePatch, text: string): {
  emails: Set<string>;
  phones: Set<string>;
  blobKeys: Set<string>;
  workOrders: Set<string>;
  haystack: string;
} {
  const haystack = [
    text,
    patch.recipientId,
    patch.source?.from,
    patch.source?.to,
    patch.source?.subject,
    patch.source?.snippet,
    patch.source?.providerItemId,
  ].filter(Boolean).join('\n').toLowerCase();

  const emails = new Set<string>();
  for (const raw of [
    patch.recipientId,
    patch.source?.from,
    patch.source?.to,
    ...haystack.matchAll(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/gi),
  ]) {
    const value = Array.isArray(raw) ? raw[0] : raw;
    const email = extractEmail(value ?? '');
    if (email) emails.add(email);
  }

  const phones = new Set<string>();
  for (const match of haystack.matchAll(/(?:\+?61|0)[\d\s().-]{7,}/g)) {
    const phone = normalisePhone(match[0]);
    if (phone) phones.add(phone);
  }

  const blobKeys = new Set<string>();
  if (patch.source?.sourceBlobKey) blobKeys.add(patch.source.sourceBlobKey);
  if (patch.source?.providerItemId) {
    blobKeys.add(`legacy-ingest/${patch.providerId}/${patch.source.providerItemId}`);
  }

  const workOrders = new Set<string>();
  for (const match of haystack.matchAll(/\b(?:job|work\s*order|wo|reference(?:\s*number)?)[:#\s-]*([a-z0-9]{4,})\b/gi)) {
    workOrders.add(normaliseToken(match[1] ?? ''));
  }
  for (const match of haystack.matchAll(/\b(?:aq[a-z0-9]{4,}|\d{7,})\b/gi)) {
    workOrders.add(normaliseToken(match[0]));
  }

  return { emails, phones, blobKeys, workOrders, haystack };
}

function collectMatches(graph: OddjobzGraphSnapshot, evidence: ReturnType<typeof buildEvidence>): {
  customers: CustomerRow[];
  sites: SiteRow[];
  jobs: JobRow[];
} {
  const customers = new Map<string, CustomerRow>();
  const sites = new Map<string, SiteRow>();
  const jobs = new Map<string, JobRow>();
  const sitesById = new Map(graph.sites.filter((s) => s.cellId).map((s) => [s.cellId!, s]));
  const customersById = new Map(graph.customers.filter((c) => c.cellId).map((c) => [c.cellId!, c]));
  const jobsById = new Map(graph.jobs.filter((j) => jobRef(j)).map((j) => [jobRef(j), j]));

  for (const customer of graph.customers) {
    const email = extractEmail(customer.email ?? '');
    const phone = normalisePhone(customer.phone ?? '');
    const provenanceItem = customer.sourceProvenance?.providerItemId;
    if (
      (email && evidence.emails.has(email)) ||
      (phone && evidence.phones.has(phone)) ||
      (provenanceItem && evidence.blobKeys.has(
        `legacy-ingest/${customer.sourceProvenance?.providerId ?? 'gmail'}/${provenanceItem}`,
      ))
    ) {
      addByRef(customers, customer.cellId ?? customer.email ?? customer.display_name, customer);
      if (customer.siteRef) addByRef(sites, customer.siteRef, sitesById.get(customer.siteRef));
    }
  }

  for (const attachment of graph.attachments) {
    if (!attachment.sourceBlobKey || !evidence.blobKeys.has(attachment.sourceBlobKey)) continue;
    const job = attachment.jobRef ? jobsById.get(attachment.jobRef) : undefined;
    addByRef(jobs, attachment.jobRef, job);
  }

  for (const job of graph.jobs) {
    const ref = jobRef(job);
    if (!ref) continue;
    const workOrder = normaliseToken(String(job.workOrderNumber ?? ''));
    if (workOrder && evidence.workOrders.has(workOrder)) addByRef(jobs, ref, job);
    if (job.sourceAttachmentPath && evidence.blobKeys.has(job.sourceAttachmentPath)) addByRef(jobs, ref, job);
    for (const customerRef of job.customerRefs ?? []) {
      if (customerRef.cellId && customers.has(customerRef.cellId)) addByRef(jobs, ref, job);
    }
    if (job.siteRef && sites.has(job.siteRef)) addByRef(jobs, ref, job);
  }

  for (const site of graph.sites) {
    if (siteMatches(site, evidence.haystack)) {
      addByRef(sites, site.cellId, site);
    }
  }

  for (const job of graph.jobs) {
    if (job.siteRef && sites.has(job.siteRef)) addByRef(jobs, jobRef(job), job);
  }

  for (const job of jobs.values()) {
    if (job.siteRef) addByRef(sites, job.siteRef, sitesById.get(job.siteRef));
    for (const ref of job.customerRefs ?? []) {
      if (ref.cellId) addByRef(customers, ref.cellId, customersById.get(ref.cellId));
    }
  }

  return {
    customers: [...customers.values()],
    sites: [...sites.values()],
    jobs: [...jobs.values()],
  };
}

function customerTargetFor(
  customer: CustomerRow,
  lane: ConversationDispatchLane,
): ConversationDispatchTarget | null {
  const ref = lane === 'direct'
    ? extractEmail(customer.email ?? '') || normalisePhone(customer.phone ?? '') || customer.cellId
    : customer.cellId;
  if (!ref) return null;
  return {
    type: lane === 'direct' ? 'participant' : 'customer',
    ref,
    label: customer.display_name || customer.email || customer.phone,
    paskCellId: customer.email ? `ingest:customer:${hashToken(customer.email)}` : undefined,
    score: lane === 'direct' ? 0.9 : 0.82,
    source: 'graph',
  };
}

function siteTargetFor(site: SiteRow): ConversationDispatchTarget {
  return {
    type: 'site',
    ref: site.cellId ?? site.lookupKey ?? site.normalisedAddress ?? site.fullAddress ?? 'site:unknown',
    label: site.fullAddress ?? site.normalisedAddress,
    paskCellId: site.cellId ? `oddjobz:site:${site.cellId}` : undefined,
    score: 0.74,
    source: 'graph',
  };
}

function jobTargetFor(job: JobRow): ConversationDispatchTarget {
  const ref = jobRef(job);
  return {
    type: 'job',
    ref,
    label: job.summary ?? job.customer_name ?? job.workOrderNumber ?? ref,
    paskCellId: `oddjobz:job:${ref}`,
    score: job.workOrderNumber ? 0.88 : 0.78,
    source: 'graph',
  };
}

function siteMatches(site: SiteRow, haystack: string): boolean {
  const address = (site.fullAddress ?? site.normalisedAddress ?? '').toLowerCase();
  if (!address) return false;
  const parts = address
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((part) => part.length >= 3 && !['qld', 'queensland'].includes(part));
  if (parts.length === 0) return false;
  const hits = parts.filter((part) => haystack.includes(part)).length;
  return hits >= Math.min(3, parts.length);
}

function dedupeCandidates(
  candidates: ReadonlyArray<ConversationDispatchCandidate>,
): ConversationDispatchCandidate[] {
  const byKey = new Map<string, ConversationDispatchCandidate>();
  for (const candidate of candidates) {
    const key = `${candidate.lane ?? '*'}:${candidate.target.type}:${candidate.target.ref}`;
    const prior = byKey.get(key);
    if (!prior || candidate.target.score > prior.target.score) byKey.set(key, candidate);
  }
  return [...byKey.values()];
}

function addByRef<T>(map: Map<string, T>, ref: string | undefined | null, value: T | undefined): void {
  if (!ref || !value) return;
  map.set(ref, value);
}

function jobRef(job: JobRow): string {
  return job.cellId ?? job.id ?? '';
}

function extractEmail(raw: string): string | null {
  const match = raw.toLowerCase().match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/);
  return match?.[0] ?? null;
}

function normalisePhone(raw: string): string | null {
  const digits = raw.replace(/\D/g, '');
  if (digits.length < 8) return null;
  if (digits.startsWith('61')) return `+${digits}`;
  if (digits.startsWith('0')) return `+61${digits.slice(1)}`;
  return digits;
}

function normaliseToken(raw: string): string {
  return raw.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function hashToken(raw: string): string {
  const s = raw.trim().toLowerCase();
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h) + s.charCodeAt(i);
    h = h | 0;
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

function clamp01(n: number): number {
  return Math.max(0, Math.min(1, n));
}

```
