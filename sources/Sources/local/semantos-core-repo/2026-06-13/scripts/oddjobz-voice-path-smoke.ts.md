---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-voice-path-smoke.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.314620+00:00
---

# scripts/oddjobz-voice-path-smoke.ts

```ts
#!/usr/bin/env bun
/**
 * Tier 2P Phase F — Voice path fidelity smoke.
 *
 * Synthesizes 3 mock voice memos (audio bytes + transcript + SIR candidate),
 * pushes each through the brain's voice ingestion path (the same
 * ConversationDispatchRouter + OddjobzAttentionPaskProjector stack that the
 * production outbox flush drives), and verifies:
 *
 *   - 3 message patches written (providerId: 'voice')
 *   - 3 dispatch decisions produced
 *   - All 3 dispatch decisions land on lane: 'self' (operator self-notes)
 *   - Attention projector picks up the new self-lane signals
 *   - All Pask cell-ids ≤ 63 bytes
 *   - Pask kernel snapshot grows (when WASM is available)
 *
 * Live state is NEVER modified — the smoke operates against a temp copy.
 *
 * Usage:
 *   bun scripts/oddjobz-voice-path-smoke.ts [--mock-pask] [--keep] [--root <dir>]
 */

import {
  appendFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
} from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { PaskAdapter, loadPask, type StableThread } from '../core/pask/bindings/ts/src';
import {
  ConversationDispatchRouter,
  JsonlConversationDispatchDecisionSink,
  OddjobzAttentionPaskProjector,
  OddjobzConversationGraphResolver,
  defaultConversationDispatchDecisionPath,
  defaultConversationTurnPatchPath,
  type ConversationPaskQuery,
  type OddjobzDispatchDecisionRecord,
  type OddjobzMessagePatch,
  type PaskInteractFn,
} from '../runtime/legacy-ingest/src';

// ---------------------------------------------------------------------------
// CLI flags
// ---------------------------------------------------------------------------

const liveRoot = argValue('--root') ?? process.env.SEMANTOS_ROOT ?? join(homedir(), '.semantos');
const keep = hasFlag('--keep');
const mockPask = hasFlag('--mock-pask');
const paskWasmPath =
  argValue('--pask-wasm') ?? join(process.cwd(), 'core/pask/zig-out/bin/pask.wasm');
const baseTime = argValue('--base-time')
  ? Date.parse(argValue('--base-time')!)
  : Date.parse('2026-05-06T09:00:00+10:00');

if (!Number.isFinite(baseTime)) {
  console.error('Invalid --base-time. Use an ISO date, e.g. 2026-05-06T09:00:00+10:00');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Pask harnesses — mirrors the ingestion smoke pattern exactly
// ---------------------------------------------------------------------------

class RecordingPask implements PaskInteractFn, ConversationPaskQuery {
  readonly calls: Parameters<PaskInteractFn['interact']>[0][] = [];

  constructor(private readonly hotJobCell: string) {}

  interact(args: Parameters<PaskInteractFn['interact']>[0]): void {
    this.calls.push(args);
  }

  getActiveContext(): string | null {
    return this.hotJobCell;
  }

  distance(_cellId: string, targetCellId: string): number {
    return targetCellId === this.hotJobCell ? 0 : Infinity;
  }
}

class RealPaskHarness implements PaskInteractFn, ConversationPaskQuery {
  readonly calls: Parameters<PaskInteractFn['interact']>[0][] = [];
  private readonly pending: Promise<unknown>[] = [];

  constructor(
    private readonly adapter: PaskAdapter,
    private readonly hotJobCell: string,
  ) {}

  interact(args: Parameters<PaskInteractFn['interact']>[0]): void {
    this.calls.push(args);
    this.pending.push(this.adapter.interact(args));
  }

  async flush(nowMs: number): Promise<void> {
    const pending = this.pending.splice(0);
    await Promise.all(pending);
    this.adapter.finalize(nowMs);
  }

  getActiveContext(): string | null {
    return this.hotJobCell;
  }

  distance(cellId: string, targetCellId: string, maxHops = 3): number {
    if (cellId === targetCellId) return 0;
    const em = this.edgeMap();
    const visited = new Set<string>([cellId]);
    let frontier = new Set<string>([cellId]);
    for (let h = 1; h <= maxHops; h++) {
      const next = new Set<string>();
      for (const c of frontier) {
        for (const n of em.get(c) ?? []) {
          if (n === targetCellId) return h;
          if (!visited.has(n)) {
            visited.add(n);
            next.add(n);
          }
        }
      }
      if (next.size === 0) break;
      frontier = next;
    }
    return Infinity;
  }

  snapshot(): { nodes: number; edges: number } {
    const snap = this.adapter.snapshot();
    return { nodes: snap.nodes.length, edges: snap.edges.length };
  }

  stableThreads(limit = 10): StableThread[] {
    return this.adapter.stableThreads(limit);
  }

  private edgeMap(): Map<string, Set<string>> {
    const snap = this.adapter.snapshot();
    const em = new Map<string, Set<string>>();
    for (const edge of snap.edges) {
      if (!em.has(edge.fromCell)) em.set(edge.fromCell, new Set());
      if (!em.has(edge.toCell)) em.set(edge.toCell, new Set());
      em.get(edge.fromCell)!.add(edge.toCell);
      em.get(edge.toCell)!.add(edge.fromCell);
    }
    return em;
  }
}

// ---------------------------------------------------------------------------
// Type helpers
// ---------------------------------------------------------------------------

type JsonRecord = Record<string, unknown>;

interface JobRow extends JsonRecord {
  id?: string;
  cellId?: string;
  summary?: string;
  state?: string;
  workOrderNumber?: string | null;
  siteRef?: string;
  customerRefs?: Array<{ cellId?: string; role?: string; primary?: boolean }>;
}

interface SiteRow extends JsonRecord {
  cellId?: string;
  fullAddress?: string;
  normalisedAddress?: string;
}

interface CustomerRow extends JsonRecord {
  cellId?: string;
  display_name?: string;
  email?: string;
  phone?: string;
  siteRef?: string;
}

interface AttachmentRow extends JsonRecord {
  cellId?: string;
  jobRef?: string;
  sourceBlobKey?: string;
}

// ---------------------------------------------------------------------------
// Synthetic voice memo shapes
//
// The brain's production path for voice notes is:
//   1. VoiceExtractUploader POSTs multipart to /api/v1/voice-extract
//   2. BRAIN routes to the intent pipeline which writes an oddjobz.message.v1
//   3. OutboxService enqueues + flushes
//
// For the smoke we bypass the HTTP hop entirely and write the
// oddjobz.message.v1 patch directly — identical to what makeOperatorPatch()
// does in the ingestion smoke and identical to what the outbox flush adapter
// writes after a successful VoiceExtractUploader round-trip.  The
// providerId:'voice' + channel:'voice' is the canonical marker the brain uses
// to distinguish voice notes from gmail/meta/widget turns.
// ---------------------------------------------------------------------------

/** Synthesized voice memo fixture. */
interface VoiceMemo {
  /** Simulated raw audio (not decoded — size/mime only validated in the uploader). */
  readonly audioBytes: Uint8Array;
  readonly mimeType: string;
  /** On-device Whisper transcript. */
  readonly transcript: string;
  /**
   * On-device SIR candidate (Llama-produced intent).
   * In the real path this bypasses the L0→L1 producer adapter in BRAIN.
   */
  readonly sirCandidate: Record<string, unknown>;
  readonly visitId: string;
  readonly clientCorrelationId: string;
  /** Lane hint inferred on-device before the upstream brain dispatch. */
  readonly inferredLane: 'self' | 'direct' | 'squad' | 'agent' | 'broadcast';
}

function makeSyntheticVoiceMemos(opts: {
  workOrder: string;
  address: string;
  customerName: string;
  baseTime: number;
}): VoiceMemo[] {
  const { workOrder, address, customerName, baseTime: t } = opts;

  // Memo 1 — operator self-note about parts variance.
  const memo1: VoiceMemo = {
    audioBytes: syntheticAudioBytes(3_200),
    mimeType: 'audio/m4a',
    transcript: `Add parts-run variance receipt to work order ${workOrder}. Need to reconcile before invoicing.`,
    sirCandidate: {
      intent: 'add_note',
      ref: workOrder,
      subject: 'parts_variance',
      text: `Add parts-run variance receipt to work order ${workOrder}.`,
      confidence: 0.91,
    },
    visitId: `voice-smoke-visit-1-${t}`,
    clientCorrelationId: `ccid-voice-smoke-1-${t}`,
    inferredLane: 'self',
  };

  // Memo 2 — operator self-note about ETA for site.
  const memo2: VoiceMemo = {
    audioBytes: syntheticAudioBytes(2_048),
    mimeType: 'audio/m4a',
    transcript: `Running 30 minutes late to ${address}. Note to self, not sending to customer yet.`,
    sirCandidate: {
      intent: 'add_note',
      ref: workOrder,
      subject: 'eta_delay',
      text: `Running 30 minutes late to ${address}.`,
      confidence: 0.87,
    },
    visitId: `voice-smoke-visit-2-${t}`,
    clientCorrelationId: `ccid-voice-smoke-2-${t}`,
    inferredLane: 'self',
  };

  // Memo 3 — operator self-note about follow-up for customer.
  const memo3: VoiceMemo = {
    audioBytes: syntheticAudioBytes(4_096),
    mimeType: 'audio/opus',
    transcript: `Remind me to follow up with ${customerName} about warranty on work order ${workOrder} in two weeks.`,
    sirCandidate: {
      intent: 'schedule_followup',
      ref: workOrder,
      subject: 'warranty_followup',
      recipient: customerName,
      delay_days: 14,
      text: `Follow up with ${customerName} about warranty.`,
      confidence: 0.84,
    },
    visitId: `voice-smoke-visit-3-${t}`,
    clientCorrelationId: `ccid-voice-smoke-3-${t}`,
    inferredLane: 'self',
  };

  return [memo1, memo2, memo3];
}

/**
 * Synthetic audio bytes — deterministic stub so the smoke can run without a
 * real microphone.  The OutboxService / VoiceExtractUploader validates size
 * (≤5 MiB) and mime; content is opaque to the dispatch stack.
 */
function syntheticAudioBytes(sizeBytes: number): Uint8Array {
  // Mimics the m4a/opus magic-byte prefix so naive mime-sniffers pass.
  const buf = new Uint8Array(sizeBytes);
  // m4a ftyp box prefix: 00 00 00 20 66 74 79 70 4D 34 41 20
  buf[0] = 0x00; buf[1] = 0x00; buf[2] = 0x00; buf[3] = 0x20;
  buf[4] = 0x66; buf[5] = 0x74; buf[6] = 0x79; buf[7] = 0x70;
  // Fill remainder with deterministic pattern
  for (let i = 8; i < sizeBytes; i++) buf[i] = (i * 37 + 13) & 0xff;
  return buf;
}

/**
 * Convert a voice memo into an OddjobzMessagePatch — this is the canonical
 * shape the brain writes after processing a VoiceExtractUploader response.
 * The outbox flush adapter uses identical field names so the downstream
 * dispatch sink + attention projector treat voice notes identically to other
 * operator turns.
 */
function voiceMemoToMessagePatch(opts: {
  memo: VoiceMemo;
  patchId: string;
  sessionId: string;
  timestamp: number;
  writtenAt: number;
}): OddjobzMessagePatch {
  const { memo, patchId, sessionId, timestamp, writtenAt } = opts;
  return {
    schema: 'oddjobz.message.v1',
    patchId,
    op: 'oddjobz.message.v1',
    providerId: 'voice',
    sessionId,
    channel: 'voice',
    recipientId: 'operator:self',
    role: 'operator',
    text: memo.transcript,
    timestamp,
    writtenAt,
    target: {
      type: 'conversation-session',
      ref: sessionId,
    },
  };
}

// ---------------------------------------------------------------------------
// Graph loader (mirrors the ingestion smoke helper)
// ---------------------------------------------------------------------------

function loadGraph(dir: string): {
  sites: SiteRow[];
  customers: CustomerRow[];
  jobs: JobRow[];
  attachments: AttachmentRow[];
} {
  return {
    sites: readJsonl<SiteRow>(join(dir, 'sites.jsonl')),
    customers: readJsonl<CustomerRow>(join(dir, 'customers.jsonl')),
    jobs: readJsonl<JobRow>(join(dir, 'jobs.jsonl')),
    attachments: readJsonl<AttachmentRow>(join(dir, 'attachments.jsonl')),
  };
}

function chooseFixture(graph: ReturnType<typeof loadGraph>): {
  job: JobRow;
  customer: CustomerRow;
  site: SiteRow | null;
} | null {
  const customersById = new Map(
    graph.customers.filter((c) => c.cellId).map((c) => [c.cellId!, c]),
  );
  const sitesById = new Map(
    graph.sites.filter((s) => s.cellId).map((s) => [s.cellId!, s]),
  );
  for (const job of graph.jobs) {
    if (!job.workOrderNumber) continue;
    const primary = (job.customerRefs ?? []).find((r) => r.primary) ?? job.customerRefs?.[0];
    const customer = primary?.cellId ? customersById.get(primary.cellId) : undefined;
    if (!customer) continue;
    return {
      job,
      customer,
      site: job.siteRef ? sitesById.get(job.siteRef) ?? null : null,
    };
  }
  // Fallback: take any job, even without customer contact.
  const job = graph.jobs[0];
  if (!job) return null;
  const primary = (job.customerRefs ?? []).find((r) => r.primary) ?? job.customerRefs?.[0];
  const customer = primary?.cellId ? customersById.get(primary.cellId) : undefined;
  return {
    job,
    customer: customer ?? { cellId: 'customer:unknown', display_name: 'Unknown Customer' },
    site: job.siteRef ? sitesById.get(job.siteRef) ?? null : null,
  };
}

// ---------------------------------------------------------------------------
// Pask harness factory
// ---------------------------------------------------------------------------

async function makePaskHarness(input: {
  hotJobCell: string;
  mock: boolean;
  wasmPath: string;
}): Promise<RecordingPask | RealPaskHarness> {
  if (input.mock || !existsSync(input.wasmPath)) {
    return new RecordingPask(input.hotJobCell);
  }
  const bytes = readFileSync(input.wasmPath);
  const instance = await loadPask(bytes);
  const adapter = new PaskAdapter(instance);
  return new RealPaskHarness(adapter, input.hotJobCell);
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

function readJsonl<T>(path: string): T[] {
  if (!existsSync(path)) return [];
  const out: T[] = [];
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line) as T);
    } catch {
      // Append-only JSONL — degrade row-by-row.
    }
  }
  return out;
}

function countBy<T>(items: readonly T[], keyFn: (item: T) => string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const item of items) {
    const key = keyFn(item);
    out[key] = (out[key] ?? 0) + 1;
  }
  return out;
}

function jobRef(job: JobRow): string {
  return job.cellId ?? job.id ?? 'job:unknown';
}

function redact(raw: string): string {
  if (raw.length <= 12) return raw;
  return `${raw.slice(0, 8)}...${raw.slice(-4)}`;
}

function argValue(name: string): string | null {
  const exact = process.argv.indexOf(name);
  if (exact >= 0) return process.argv[exact + 1] ?? null;
  const prefixed = process.argv.find((arg) => arg.startsWith(`${name}=`));
  return prefixed ? prefixed.slice(name.length + 1) : null;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(name);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const liveOddjobzDir = join(liveRoot, 'data', 'oddjobz');
if (!existsSync(liveOddjobzDir)) {
  console.error(`Oddjobz graph directory not found: ${liveOddjobzDir}`);
  console.error('Tip: run from a machine with a live Oddjobz sync, or pass --root <dir>');
  process.exit(1);
}

// Work in an isolated temp copy — live state is never modified.
const tempRoot = mkdtempSync(join(tmpdir(), 'oddjobz-voice-smoke-'));
const tempOddjobzDir = join(tempRoot, 'data', 'oddjobz');
mkdirSync(tempOddjobzDir, { recursive: true });

for (const file of ['sites.jsonl', 'customers.jsonl', 'jobs.jsonl', 'attachments.jsonl']) {
  const src = join(liveOddjobzDir, file);
  if (existsSync(src)) cpSync(src, join(tempOddjobzDir, file));
  else appendFileSync(join(tempOddjobzDir, file), '');
}

const graph = loadGraph(tempOddjobzDir);
const fixture = chooseFixture(graph);
if (!fixture) {
  console.error('Could not find any job fixture in the local Oddjobz graph.');
  process.exit(1);
}

const workOrder = fixture.job.workOrderNumber ?? jobRef(fixture.job).slice(0, 12);
const customerName = fixture.customer.display_name ?? 'the customer';
const address =
  fixture.site?.fullAddress ?? fixture.site?.normalisedAddress ?? 'the job site';
const hotJobCell = `oddjobz:job:${jobRef(fixture.job)}`;

const pask = await makePaskHarness({ hotJobCell, mock: mockPask, wasmPath: paskWasmPath });

const graphResolver = new OddjobzConversationGraphResolver({
  oddjobzDir: tempOddjobzDir,
  pask,
});
const dispatchRouter = new ConversationDispatchRouter({
  resolveCandidates: graphResolver.resolve,
});
const dispatchSink = new JsonlConversationDispatchDecisionSink({
  root: tempRoot,
  router: dispatchRouter,
});

// Voice patches are written directly to the message JSONL — this mirrors the
// production outbox flush path after VoiceExtractUploader.upload() succeeds.
// The outbox flush adapter calls appendFileSync(messagesPath, ...) directly
// rather than going through JsonlConversationTurnPatchSink.append() (which
// expects a ConversationTurnEvent, not an OddjobzMessagePatch).
const messagesPath = defaultConversationTurnPatchPath(tempRoot);
const dispatchPath = defaultConversationDispatchDecisionPath(tempRoot);

// Ensure the messages JSONL exists (tempOddjobzDir already created above).
if (!existsSync(messagesPath)) appendFileSync(messagesPath, '', { mode: 0o600 });

// Synthesize 3 voice memos.
const memos = makeSyntheticVoiceMemos({ workOrder, address, customerName, baseTime });

// Ingest each memo: write message patch → route dispatch.
const memoResults: Array<{
  memo: number;
  visitId: string;
  patchId: string;
  patched: boolean;
  dispatched: boolean;
}> = [];

for (let i = 0; i < memos.length; i++) {
  const memo = memos[i]!;
  const timestamp = baseTime + i * 5 * 60_000; // 5 min apart
  const writtenAt = timestamp + 200;
  const patchId = `voice-smoke-patch-${i + 1}-${timestamp}`;
  const sessionId = `voice:smoke-session-${i + 1}`;

  const patch = voiceMemoToMessagePatch({
    memo,
    patchId,
    sessionId,
    timestamp,
    writtenAt,
  });

  // Write message patch directly to JSONL (outbox flush adapter pattern).
  appendFileSync(messagesPath, `${JSON.stringify(patch)}\n`);
  const patched = true;

  // Route dispatch decision for this patch.
  const dispatched = await dispatchSink.append(patch);

  memoResults.push({ memo: i + 1, visitId: memo.visitId, patchId, patched, dispatched });
}

// Project attention signals — replay all writes into Pask then poll.
const messages = readJsonl<OddjobzMessagePatch>(messagesPath);
const dispatches = readJsonl<OddjobzDispatchDecisionRecord>(dispatchPath);

const projector = new OddjobzAttentionPaskProjector({
  root: tempRoot,
  pask,
  maxSignals: 40,
  signalTtlMs: 48 * 60 * 60 * 1000,
});
const replaySummary = projector.replayToPask();
if (pask instanceof RealPaskHarness) {
  await pask.flush(baseTime + 3 * 60 * 60 * 1000);
}
const pollTime = baseTime + 3 * 60 * 60 * 1000;
const signals = projector.pollSignals(pollTime);
const realPaskSnapshot = pask instanceof RealPaskHarness ? pask.snapshot() : null;
const stableThreads = pask instanceof RealPaskHarness ? pask.stableThreads(10) : [];

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

const voiceMessages = messages.filter((m) => m.providerId === 'voice');
const selfLaneDispatches = dispatches.filter((d) => d.lane === 'self');
const voiceDispatches = dispatches.filter((d) => d.providerId === 'voice');

const decisionIds = new Set(dispatches.map((d) => d.decisionId));
const signalKinds = countBy(
  signals,
  (s) => String(s.synthesizesObject?.payload.kind ?? 'unknown'),
);

const allPaskCellIds = pask.calls.flatMap((c) => [c.cellId, ...(c.relatedCells ?? [])]);
const maxPaskCellLength = Math.max(0, ...allPaskCellIds.map((id) => id.length));
const overflowPaskCellIds = allPaskCellIds.filter((id) => id.length > 63);

const EXPECTED_MEMO_COUNT = memos.length; // 3

const assertions: ReadonlyArray<readonly [string, boolean]> = [
  ['all memos produced a message patch', memoResults.every((r) => r.patched)],
  ['all memos produced a dispatch decision', memoResults.every((r) => r.dispatched)],
  ['voice message count equals memo count', voiceMessages.length === EXPECTED_MEMO_COUNT],
  ['voice dispatch count equals memo count', voiceDispatches.length === EXPECTED_MEMO_COUNT],
  ['all voice dispatches are self-lane', selfLaneDispatches.length === EXPECTED_MEMO_COUNT],
  ['dispatch decision ids are unique', decisionIds.size === dispatches.length],
  // The attention projector emits dispatch-kind signals for operator voice
  // notes (message-kind signals are customer-only).  The 3 voice dispatch
  // decisions should produce 3 dispatch signals.
  ['attention projector emits dispatch signals for voice', (signalKinds.dispatch ?? 0) >= EXPECTED_MEMO_COUNT],
  ['Pask cell ids fit 63-byte kernel cap', overflowPaskCellIds.length === 0 && maxPaskCellLength <= 63],
  [
    'real Pask kernel accepted voice interactions',
    !(pask instanceof RealPaskHarness) ||
      ((realPaskSnapshot?.nodes ?? 0) > 0 && (realPaskSnapshot?.edges ?? 0) > 0),
  ],
  ['all voice messages carry providerId: voice', voiceMessages.every((m) => m.providerId === 'voice')],
  ['all voice messages carry channel: voice', voiceMessages.every((m) => m.channel === 'voice')],
  ['all voice messages carry role: operator', voiceMessages.every((m) => m.role === 'operator')],
];

const failures = assertions.filter(([, ok]) => !ok).map(([name]) => name);

const laneCounts = countBy(dispatches, (d) => d.lane);
const signalCount = signals.length;

const summary = {
  verdict: failures.length === 0 ? 'PASS' : 'FAIL',
  failures,
  liveRoot,
  tempRoot: keep ? tempRoot : '(deleted)',
  fixture: {
    jobRef: redact(jobRef(fixture.job)),
    workOrderPresent: !!fixture.job.workOrderNumber,
    customerRef: redact(fixture.customer.cellId ?? fixture.customer.email ?? 'customer'),
    siteRef: redact(fixture.site?.cellId ?? fixture.job.siteRef ?? 'site'),
    address: address.slice(0, 40),
  },
  graphRows: {
    sites: graph.sites.length,
    customers: graph.customers.length,
    jobs: graph.jobs.length,
    attachments: graph.attachments.length,
  },
  voiceMemos: {
    synthesized: EXPECTED_MEMO_COUNT,
    results: memoResults,
  },
  writtenRows: {
    messages: messages.length,
    voiceMessages: voiceMessages.length,
    dispatches: dispatches.length,
    voiceDispatches: voiceDispatches.length,
  },
  dispatch: {
    laneCounts,
    selfLane: selfLaneDispatches.length,
    ratificationRequired: dispatches.filter((d) => d.requiresRatification).length,
  },
  pask: {
    mode: pask instanceof RealPaskHarness ? 'real-wasm' : 'recording',
    wasmPath: pask instanceof RealPaskHarness ? paskWasmPath : null,
    replaySummary,
    interactionsRecorded: pask.calls.length,
    snapshot: realPaskSnapshot,
    stableThreads: stableThreads.slice(0, 5).map((t) => ({
      cellId: t.cellId,
      hState: Number(t.hState.toFixed(3)),
      isStable: t.isStable,
    })),
    uniqueCells: new Set(allPaskCellIds).size,
    maxCellIdLength: maxPaskCellLength,
    overflowCellIds: overflowPaskCellIds.length,
  },
  attention: {
    signals: signalCount,
    signalKinds,
    top: signals.slice(0, 5).map((s) => ({
      id: s.synthesizesObject?.id,
      kind: s.synthesizesObject?.payload.kind,
      score: Number(s.score.toFixed(3)),
      signal: s.factor.signal,
    })),
  },
};

if (!keep) rmSync(tempRoot, { recursive: true, force: true });

console.log(JSON.stringify(summary, null, 2));

// Print human-readable verdict last so it's easy to spot in CI logs.
const verdictLine =
  failures.length === 0
    ? '\n✓ PASS — voice path fidelity smoke'
    : `\n✗ FAIL — ${failures.length} assertion(s) failed:\n${failures.map((f) => `  • ${f}`).join('\n')}`;
console.log(verdictLine);

if (failures.length > 0) process.exit(1);

```
