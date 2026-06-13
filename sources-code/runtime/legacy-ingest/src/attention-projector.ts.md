---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/attention-projector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.132459+00:00
---

# runtime/legacy-ingest/src/attention-projector.ts

```ts
/**
 * Oddjobz attention/Pask projector.
 *
 * Bridges the source-neutral Oddjobz graph (`oddjobz.message.v1`,
 * `oddjobz.dispatch.v1`, jobs/customers/sites/attachments) into:
 *
 *   1. the Pask interaction graph, so stable threads + graph proximity can
 *      learn from work reality; and
 *   2. AttentionSignals with synthesized LoomObjects, so the attention
 *      surface can show hot jobs, conversations, and dispatch decisions even
 *      before those rows have been mirrored into LoomStore proper.
 */

import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { OddjobzDispatchDecisionRecord } from './conversation/dispatch-decision-store';
import { defaultConversationDispatchDecisionPath } from './conversation/dispatch-decision-store';
import type { OddjobzMessagePatch } from './conversation/turn-patch-store';
import { defaultConversationTurnPatchPath } from './conversation/turn-patch-store';
import type { PaskInteractFn } from './pask-bridge';

type JsonRecord = Record<string, unknown>;

export interface OddjobzAttentionSignal {
  readonly sourceId: string;
  readonly attachToObjectId?: string;
  readonly synthesizesObject?: OddjobzLoomObject;
  readonly factor: {
    readonly type: 'extension_signal';
    readonly extensionId: string;
    readonly signal: string;
  };
  readonly score: number;
  readonly expiresAt?: number;
}

export interface OddjobzAttentionSignalSource {
  readonly id: string;
  readonly displayName: string;
  poll?(now: number): Promise<OddjobzAttentionSignal[]>;
}

export interface OddjobzLoomObject {
  readonly id: string;
  readonly typeDefinition: {
    readonly typeHash: string;
    readonly name: string;
    readonly icon: string;
    readonly linearity: 'RELEVANT';
    readonly defaultCapabilities: number[];
    readonly category: string;
    readonly archetype: 'action';
    readonly fields: Array<{ name: string; type: 'string' | 'datetime' }>;
    readonly conversationEnabled: true;
  };
  readonly header: {
    readonly magic: Uint8Array;
    readonly version: number;
    readonly linearity: number;
    readonly flags: number;
    readonly refCount: number;
    readonly typeHash: Uint8Array;
    readonly ownerId: Uint8Array;
    readonly timestamp: bigint;
    readonly cellCount: number;
    readonly totalSize: number;
    readonly parentHash: Uint8Array;
    readonly prevStateHash: Uint8Array;
    // RM-032b: commerce taxonomy (phase, dimension) removed; chain
    // fields (parentHash, prevStateHash) retained on the projector.
  };
  readonly payload: Record<string, unknown>;
  readonly patches: [];
  readonly visibility: 'draft';
  readonly createdAt: number;
  readonly updatedAt: number;
}

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
  siteRef?: string;
}

interface JobRow extends JsonRecord {
  id?: string;
  cellId?: string;
  customer_name?: string;
  summary?: string;
  state?: string;
  scheduled_at?: string;
  created_at?: string;
  workOrderNumber?: string | null;
  issuanceDate?: string | null;
  dueDate?: string | null;
  propertyKey?: string | null;
  siteRef?: string;
  sourceAttachmentPath?: string;
  hasPhotos?: boolean;
  photoCount?: number | null;
  customerRefs?: Array<{ cellId?: string; role?: string; primary?: boolean }>;
}

interface AttachmentRow extends JsonRecord {
  cellId?: string;
  jobRef?: string;
  sourceBlobKey?: string;
}

interface GraphSnapshot {
  readonly sites: SiteRow[];
  readonly customers: CustomerRow[];
  readonly jobs: JobRow[];
  readonly attachments: AttachmentRow[];
  readonly messages: OddjobzMessagePatch[];
  readonly dispatches: OddjobzDispatchDecisionRecord[];
}

export interface OddjobzAttentionProjectorOpts {
  readonly root?: string;
  readonly oddjobzDir?: string;
  readonly messagesPath?: string;
  readonly dispatchPath?: string;
  readonly pask?: PaskInteractFn;
  readonly maxSignals?: number;
  readonly signalTtlMs?: number;
}

export interface OddjobzAttentionSignalRegistryLike {
  register(
    source: OddjobzAttentionSignalSource,
    opts?: { enabled?: boolean },
  ): void;
}

export interface InstallOddjobzAttentionPipelineOpts extends OddjobzAttentionProjectorOpts {
  readonly signals: OddjobzAttentionSignalRegistryLike;
  readonly enabled?: boolean;
  readonly replayToPask?: boolean;
}

export interface InstalledOddjobzAttentionPipeline {
  readonly projector: OddjobzAttentionPaskProjector;
  readonly source: OddjobzAttentionSignalSource;
  readonly replaySummary: OddjobzAttentionReplaySummary | null;
}

export interface OddjobzAttentionReplaySummary {
  readonly jobs: number;
  readonly customers: number;
  readonly sites: number;
  readonly messages: number;
  readonly dispatches: number;
  readonly interactions: number;
}

export class OddjobzAttentionPaskProjector {
  private readonly root: string;
  private readonly oddjobzDir: string;
  private readonly messagesPath: string;
  private readonly dispatchPath: string;
  private readonly pask: PaskInteractFn | null;
  private readonly maxSignals: number;
  private readonly signalTtlMs: number;

  constructor(opts: OddjobzAttentionProjectorOpts = {}) {
    this.root = opts.root ?? process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos');
    const dataDir = process.env.BRAIN_DATA_DIR ?? join(this.root, 'data');
    this.oddjobzDir = opts.oddjobzDir ?? join(dataDir, 'oddjobz');
    this.messagesPath = opts.messagesPath ?? defaultConversationTurnPatchPath(this.root);
    this.dispatchPath = opts.dispatchPath ?? defaultConversationDispatchDecisionPath(this.root);
    this.pask = opts.pask ?? null;
    this.maxSignals = opts.maxSignals ?? 50;
    this.signalTtlMs = opts.signalTtlMs ?? 24 * 60 * 60 * 1000;
  }

  pollSignals(now = Date.now()): OddjobzAttentionSignal[] {
    const snapshot = this.load();
    return balancedSignals({
      jobs: this.jobSignals(snapshot, now),
      dispatches: this.dispatchSignals(snapshot, now),
      messages: this.messageSignals(snapshot, now),
      maxSignals: this.maxSignals,
    });
  }

  replayToPask(): OddjobzAttentionReplaySummary {
    const snapshot = this.load();
    let interactions = 0;
    const emit = (args: Parameters<PaskInteractFn['interact']>[0]) => {
      if (!this.pask) return;
      this.pask.interact({
        ...args,
        cellId: trimCell(args.cellId),
        relatedCells: (args.relatedCells ?? []).map(trimCell),
      });
      interactions += 1;
    };

    for (const site of snapshot.sites) {
      const ref = site.cellId;
      if (!ref) continue;
      emit({
        cellId: `oddjobz:site:${ref}`,
        kind: 'seed',
        strength: 0.08,
        relatedCells: [],
        nowMs: rowTimestamp(site),
      });
    }

    for (const customer of snapshot.customers) {
      const ref = customer.cellId;
      if (!ref) continue;
      const related = [
        customer.siteRef ? `oddjobz:site:${customer.siteRef}` : null,
        customer.email ? `ingest:customer:${hashToken(customer.email)}` : null,
      ].filter((v): v is string => !!v);
      emit({
        cellId: `oddjobz:customer:${ref}`,
        kind: 'seed',
        strength: 0.1,
        relatedCells: related,
        nowMs: rowTimestamp(customer),
      });
    }

    for (const job of snapshot.jobs) {
      const ref = jobRef(job);
      if (!ref) continue;
      emit({
        cellId: `oddjobz:job:${ref}`,
        kind: job.state === 'completed' ? 'acted-on' : 'seed',
        strength: jobStrength(job),
        relatedCells: jobRelatedCells(job),
        nowMs: rowTimestamp(job),
      });
    }

    for (const message of snapshot.messages) {
      emit({
        cellId: `ingest:message:${message.patchId}`,
        kind: 'seed',
        strength: 0.05,
        relatedCells: [
          `ingest:session:${message.sessionId}`,
          `ingest:participant:${hashToken(message.recipientId)}`,
          `ingest:channel:${message.channel}`,
          `ingest:source:${message.providerId}`,
        ],
        nowMs: message.timestamp,
      });
    }

    for (const dispatch of snapshot.dispatches) {
      emit({
        cellId: `oddjobz:dispatch:${dispatch.decisionId}`,
        kind: dispatch.requiresRatification ? 'pinned' : 'seed',
        strength: dispatch.requiresRatification ? 0.6 : 0.16,
        relatedCells: [
          `ingest:message:${dispatch.sourcePatchId}`,
          targetPaskCell(dispatch.primaryTarget.type, dispatch.primaryTarget.ref),
          dispatch.primaryTarget.paskCellId,
        ].filter((v): v is string => !!v),
        nowMs: dispatch.writtenAt,
      });
    }

    return {
      jobs: snapshot.jobs.length,
      customers: snapshot.customers.length,
      sites: snapshot.sites.length,
      messages: snapshot.messages.length,
      dispatches: snapshot.dispatches.length,
      interactions,
    };
  }

  private load(): GraphSnapshot {
    return {
      sites: readJsonl<SiteRow>(join(this.oddjobzDir, 'sites.jsonl')),
      customers: readJsonl<CustomerRow>(join(this.oddjobzDir, 'customers.jsonl')),
      jobs: readJsonl<JobRow>(join(this.oddjobzDir, 'jobs.jsonl')),
      attachments: readJsonl<AttachmentRow>(join(this.oddjobzDir, 'attachments.jsonl')),
      messages: readJsonl<OddjobzMessagePatch>(this.messagesPath),
      dispatches: readJsonl<OddjobzDispatchDecisionRecord>(this.dispatchPath),
    };
  }

  private jobSignals(snapshot: GraphSnapshot, now: number): OddjobzAttentionSignal[] {
    const sitesById = new Map(snapshot.sites.filter((s) => s.cellId).map((s) => [s.cellId!, s]));
    const customersById = new Map(snapshot.customers.filter((c) => c.cellId).map((c) => [c.cellId!, c]));
    const out: OddjobzAttentionSignal[] = [];
    for (const job of snapshot.jobs) {
      const ref = jobRef(job);
      if (!ref) continue;
      const score = jobAttentionScore(job);
      if (score <= 0) continue;
      const customer = primaryCustomer(job, customersById);
      const site = job.siteRef ? sitesById.get(job.siteRef) : undefined;
      out.push({
        sourceId: 'oddjobz-attention',
        synthesizesObject: loomObject({
          id: `oddjobz:job:${ref}`,
          typeName: 'OddjobzJob',
          title: job.summary ?? job.customer_name ?? `Job ${ref.slice(0, 8)}`,
          status: job.state ?? 'unknown',
          updatedAt: rowTimestamp(job),
          payload: {
            kind: 'job',
            jobRef: ref,
            workOrderNumber: job.workOrderNumber ?? null,
            customerName: customer?.display_name ?? job.customer_name ?? null,
            siteAddress: site?.fullAddress ?? site?.normalisedAddress ?? null,
            dueDate: job.dueDate ?? null,
            propertyKey: job.propertyKey ?? site?.keyNumber ?? null,
            hasPhotos: job.hasPhotos ?? false,
            photoCount: job.photoCount ?? null,
          },
        }),
        factor: {
          type: 'extension_signal',
          extensionId: 'oddjobz.job',
          signal: jobSignalReason(job),
        },
        score,
        expiresAt: now + this.signalTtlMs,
      });
    }
    return out;
  }

  private dispatchSignals(snapshot: GraphSnapshot, now: number): OddjobzAttentionSignal[] {
    return snapshot.dispatches
      .filter((d) => d.requiresRatification || d.confidence >= 0.72)
      .map((dispatch) => ({
        sourceId: 'oddjobz-attention',
        synthesizesObject: loomObject({
          id: `oddjobz:dispatch:${dispatch.decisionId}`,
          typeName: 'OddjobzDispatch',
          title: `${dispatch.slot} -> ${dispatch.primaryTarget.label ?? dispatch.primaryTarget.ref}`,
          status: dispatch.requiresRatification ? 'pending_ratification' : dispatch.lane,
          updatedAt: dispatch.writtenAt,
          payload: {
            kind: 'dispatch',
            lane: dispatch.lane,
            slot: dispatch.slot,
            transport: dispatch.transport,
            sourcePatchId: dispatch.sourcePatchId,
            sessionId: dispatch.sessionId,
            primaryTarget: dispatch.primaryTarget,
            text: dispatch.text,
            confidence: dispatch.confidence,
            requiresRatification: dispatch.requiresRatification,
          },
        }),
        factor: {
          type: 'extension_signal',
          extensionId: 'oddjobz.dispatch',
          signal: dispatch.requiresRatification
            ? `Ratify ${dispatch.slot} dispatch`
            : `Dispatch ${dispatch.slot}`,
        },
        score: dispatch.requiresRatification ? 0.9 : Math.min(0.78, dispatch.confidence),
        expiresAt: now + this.signalTtlMs,
      }));
  }

  private messageSignals(snapshot: GraphSnapshot, now: number): OddjobzAttentionSignal[] {
    return snapshot.messages
      .filter((m) => m.role === 'customer')
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, Math.max(5, Math.floor(this.maxSignals / 4)))
      .map((message) => ({
        sourceId: 'oddjobz-attention',
        synthesizesObject: loomObject({
          id: `ingest:message:${message.patchId}`,
          typeName: 'OddjobzMessage',
          title: message.source?.subject ?? message.text.slice(0, 80),
          status: 'open',
          updatedAt: message.timestamp,
          payload: {
            kind: 'message',
            providerId: message.providerId,
            channel: message.channel,
            sessionId: message.sessionId,
            recipientId: message.recipientId,
            text: message.text,
            source: message.source ?? null,
          },
        }),
        factor: {
          type: 'extension_signal',
          extensionId: `oddjobz.message.${message.providerId}`,
          signal: `New ${message.channel} message`,
        },
        score: 0.62,
        expiresAt: now + this.signalTtlMs,
      }));
  }
}

export function createOddjobzAttentionSource(
  opts: OddjobzAttentionProjectorOpts = {},
): OddjobzAttentionSignalSource {
  const projector = new OddjobzAttentionPaskProjector(opts);
  return sourceForProjector(projector);
}

export function installOddjobzAttentionPipeline(
  opts: InstallOddjobzAttentionPipelineOpts,
): InstalledOddjobzAttentionPipeline {
  const projector = new OddjobzAttentionPaskProjector(opts);
  const source = sourceForProjector(projector);
  opts.signals.register(source, { enabled: opts.enabled ?? true });
  const replaySummary = opts.replayToPask ? projector.replayToPask() : null;
  return { projector, source, replaySummary };
}

function sourceForProjector(
  projector: OddjobzAttentionPaskProjector,
): OddjobzAttentionSignalSource {
  return {
    id: 'oddjobz-attention',
    displayName: 'Oddjobz Attention',
    poll(now: number): Promise<OddjobzAttentionSignal[]> {
      return Promise.resolve(projector.pollSignals(now));
    },
  };
}

function readJsonl<T>(path: string): T[] {
  if (!existsSync(path)) return [];
  const out: T[] = [];
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line) as T);
    } catch {
      // Append-only logs should degrade row-by-row.
    }
  }
  return out;
}

function balancedSignals(input: {
  jobs: OddjobzAttentionSignal[];
  dispatches: OddjobzAttentionSignal[];
  messages: OddjobzAttentionSignal[];
  maxSignals: number;
}): OddjobzAttentionSignal[] {
  const max = Math.max(1, input.maxSignals);
  const selected: OddjobzAttentionSignal[] = [];
  const seen = new Set<string>();
  const add = (signal: OddjobzAttentionSignal): void => {
    const id =
      signal.synthesizesObject?.id
      ?? signal.attachToObjectId
      ?? `${signal.sourceId}:${signal.factor.extensionId}:${signal.factor.signal}`;
    if (seen.has(id) || selected.length >= max) return;
    seen.add(id);
    selected.push(signal);
  };
  const take = (items: OddjobzAttentionSignal[], count: number): void => {
    for (const signal of items.sort((a, b) => b.score - a.score).slice(0, count)) {
      add(signal);
    }
  };

  take(input.dispatches, Math.min(input.dispatches.length, Math.ceil(max * 0.25)));
  take(input.messages, Math.min(input.messages.length, Math.ceil(max * 0.25)));
  take(input.jobs, Math.min(input.jobs.length, Math.max(0, max - selected.length)));

  const remainder = [
    ...input.dispatches,
    ...input.messages,
    ...input.jobs,
  ].sort((a, b) => b.score - a.score);
  for (const signal of remainder) add(signal);

  return selected.sort((a, b) => b.score - a.score).slice(0, max);
}

function loomObject(opts: {
  id: string;
  typeName: string;
  title: string;
  status: string;
  updatedAt: number;
  payload: Record<string, unknown>;
}): OddjobzLoomObject {
  return {
    id: opts.id,
    typeDefinition: {
      typeHash: hashToken(opts.typeName),
      name: opts.typeName,
      icon: 'briefcase',
      linearity: 'RELEVANT',
      defaultCapabilities: [],
      category: 'oddjobz',
      archetype: 'action',
      fields: [
        { name: 'status', type: 'string' },
        { name: 'updatedAt', type: 'datetime' },
      ],
      conversationEnabled: true,
    },
    header: {
      magic: new Uint8Array(16),
      version: 1,
      linearity: 3,
      flags: 0,
      refCount: 0,
      typeHash: new Uint8Array(32),
      ownerId: new Uint8Array(16),
      timestamp: BigInt(opts.updatedAt),
      cellCount: 1,
      totalSize: 0,
      parentHash: new Uint8Array(32),
      prevStateHash: new Uint8Array(32),
    },
    payload: {
      title: opts.title,
      status: opts.status,
      updatedAt: opts.updatedAt,
      ...opts.payload,
    },
    patches: [],
    visibility: 'draft',
    createdAt: opts.updatedAt,
    updatedAt: opts.updatedAt,
  };
}

function primaryCustomer(
  job: JobRow,
  customersById: Map<string, CustomerRow>,
): CustomerRow | null {
  const ref = (job.customerRefs ?? []).find((r) => r.primary) ?? job.customerRefs?.[0];
  if (!ref?.cellId) return null;
  return customersById.get(ref.cellId) ?? null;
}

function jobRef(job: JobRow): string {
  return job.cellId ?? job.id ?? '';
}

function jobRelatedCells(job: JobRow): string[] {
  return [
    job.siteRef ? `oddjobz:site:${job.siteRef}` : null,
    ...(job.customerRefs ?? []).map((ref) => ref.cellId ? `oddjobz:customer:${ref.cellId}` : null),
    job.sourceAttachmentPath ? `ingest:blob:${job.sourceAttachmentPath}` : null,
  ].filter((v): v is string => !!v);
}

function targetPaskCell(type: string, ref: string): string | null {
  switch (type) {
    case 'job': return `oddjobz:job:${ref}`;
    case 'customer': return `oddjobz:customer:${ref}`;
    case 'site': return `oddjobz:site:${ref}`;
    case 'participant': return `ingest:participant:${hashToken(ref)}`;
    case 'conversation-session': return `ingest:session:${ref}`;
    case 'squad': return `oddjobz:squad:${ref}`;
    case 'agent': return `oddjobz:agent:${ref}`;
    case 'broadcast-channel': return `oddjobz:broadcast:${ref}`;
    default: return null;
  }
}

function jobStrength(job: JobRow): number {
  switch ((job.state ?? '').toLowerCase()) {
    case 'completed': return 0.5;
    case 'lead': return 0.35;
    case 'quoted': return 0.3;
    case 'in_progress': return 0.28;
    case 'invoiced': return 0.22;
    default: return 0.12;
  }
}

function jobAttentionScore(job: JobRow): number {
  switch ((job.state ?? '').toLowerCase()) {
    case 'completed': return 0.95;
    case 'lead': return 0.82;
    case 'quoted': return 0.78;
    case 'in_progress': return 0.7;
    case 'scheduled': return 0.46;
    default: return 0.25;
  }
}

function jobSignalReason(job: JobRow): string {
  switch ((job.state ?? '').toLowerCase()) {
    case 'completed': return 'Work complete - invoice needed';
    case 'lead': return 'Lead needs quote';
    case 'quoted': return 'Quote needs scheduling';
    case 'in_progress': return 'Job in progress';
    case 'scheduled': return 'Scheduled job';
    default: return 'Oddjobz job activity';
  }
}

function rowTimestamp(row: JsonRecord): number {
  const raw = row.ts ?? row.updatedAt ?? row.createdAt ?? row.created_at;
  if (typeof raw === 'number') return raw;
  if (typeof raw === 'string') {
    const asNumber = Number(raw);
    if (Number.isFinite(asNumber) && asNumber > 0) return asNumber;
    const parsed = Date.parse(raw);
    if (Number.isFinite(parsed)) return parsed;
  }
  return Date.now();
}

function trimCell(id: string): string {
  if (id.length <= 63) return id;
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (Math.imul(31, h) + id.charCodeAt(i)) | 0;
  return `${id.slice(0, 48)}#${Math.abs(h).toString(16).padStart(8, '0').slice(0, 8)}`;
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

```
