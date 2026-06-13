---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/oddjobz-ingestion-attention-smoke.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.317884+00:00
---

# scripts/oddjobz-ingestion-attention-smoke.ts

```ts
#!/usr/bin/env bun
/**
 * Robust local rehearsal for the source-neutral Oddjobz ingestion path.
 *
 * Copies the current Oddjobz view-store into a temp SEMANTOS root, injects a
 * mix of timestamped Gmail / Meta / widget / operator-voice mock turns, routes
 * each turn through the dispatch butler, then projects the resulting graph into
 * attention signals + Pask interactions. Live state is never modified.
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
import { homedir } from 'node:os';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { PaskAdapter, loadPask, type StableThread } from '../core/pask/bindings/ts/src';
import {
  ConversationDispatchRouter,
  JsonlConversationDispatchDecisionSink,
  JsonlConversationTurnPatchSink,
  OddjobzAttentionPaskProjector,
  OddjobzConversationGraphResolver,
  defaultConversationDispatchDecisionPath,
  defaultConversationTurnPatchPath,
  type ConversationPaskQuery,
  type ConversationTurnEvent,
  type OddjobzDispatchDecisionRecord,
  type OddjobzMessagePatch,
  type PaskInteractFn,
  type RawItem,
} from '../runtime/legacy-ingest/src';

type JsonRecord = Record<string, unknown>;

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

interface JobRow extends JsonRecord {
  id?: string;
  cellId?: string;
  summary?: string;
  state?: string;
  workOrderNumber?: string | null;
  siteRef?: string;
  customerRefs?: Array<{ cellId?: string; role?: string; primary?: boolean }>;
}

interface AttachmentRow extends JsonRecord {
  cellId?: string;
  jobRef?: string;
  sourceBlobKey?: string;
}

interface Scenario {
  name: string;
  timestamp: number;
  write(): boolean;
}

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

  neighbours(cellId: string, hops: 1 | 2 | 3 = 1): string[] {
    const em = this.edgeMap();
    const visited = new Set<string>([cellId]);
    let frontier = new Set<string>([cellId]);
    for (let h = 0; h < hops; h++) {
      const next = new Set<string>();
      for (const c of frontier) {
        for (const n of em.get(c) ?? []) {
          if (!visited.has(n)) {
            visited.add(n);
            next.add(n);
          }
        }
      }
      frontier = next;
    }
    visited.delete(cellId);
    return [...visited];
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

const liveRoot = argValue('--root') ?? process.env.SEMANTOS_ROOT ?? join(homedir(), '.semantos');
const keep = hasFlag('--keep');
const mockPask = hasFlag('--mock-pask');
const paskWasmPath = argValue('--pask-wasm') ?? join(process.cwd(), 'core/pask/zig-out/bin/pask.wasm');
const baseTime = argValue('--base-time')
  ? Date.parse(argValue('--base-time')!)
  : Date.parse('2026-05-06T08:30:00+10:00');

if (!Number.isFinite(baseTime)) {
  console.error('Invalid --base-time. Use an ISO date, e.g. 2026-05-06T08:30:00+10:00');
  process.exit(1);
}

const liveOddjobzDir = join(liveRoot, 'data', 'oddjobz');
if (!existsSync(liveOddjobzDir)) {
  console.error(`Oddjobz graph directory not found: ${liveOddjobzDir}`);
  process.exit(1);
}

const tempRoot = mkdtempSync(join(tmpdir(), 'oddjobz-ingest-attention-'));
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
  console.error('Could not find a job/customer fixture in the local Oddjobz graph.');
  process.exit(1);
}

const hotJobCell = `oddjobz:job:${jobRef(fixture.job)}`;
const pask = await makePaskHarness({
  hotJobCell,
  mock: mockPask,
  wasmPath: paskWasmPath,
});
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

const capturedPatches: OddjobzMessagePatch[] = [];
let writeClock = baseTime;
const turnSink = new JsonlConversationTurnPatchSink({
  root: tempRoot,
  now: () => writeClock,
  onPatch: (patch) => capturedPatches.push(patch),
});

const messagesPath = defaultConversationTurnPatchPath(tempRoot);
const dispatchPath = defaultConversationDispatchDecisionPath(tempRoot);
const scenarios = buildScenarios({
  fixture,
  baseTime,
  turnSink,
  setWriteClock: (n) => { writeClock = n; },
  messagesPath,
});

const scenarioResults: Array<{ name: string; wrote: boolean }> = [];
for (const scenario of scenarios) {
  const before = capturedPatches.length;
  writeClock = scenario.timestamp + 100;
  const wrote = scenario.write();
  scenarioResults.push({ name: scenario.name, wrote });
  const newPatches = capturedPatches.slice(before);
  for (const patch of newPatches) await dispatchSink.append(patch);
}

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
const signals = projector.pollSignals(baseTime + 3 * 60 * 60 * 1000);
const realPaskSnapshot = pask instanceof RealPaskHarness ? pask.snapshot() : null;
const stableThreads = pask instanceof RealPaskHarness ? pask.stableThreads(10) : [];

const laneCounts = countBy(dispatches, (d) => d.lane);
const dispatchPrimaryKinds = countBy(dispatches, (d) => d.primaryTarget.type);
const dispatchSources = countBy(dispatches, (d) => d.primaryTarget.source);
const decisionIds = new Set(dispatches.map((d) => d.decisionId));
const signalKinds = countBy(signals, (s) => String(s.synthesizesObject?.payload.kind ?? 'unknown'));
const maxPaskCellLength = Math.max(
  0,
  ...pask.calls.flatMap((c) => [c.cellId, ...(c.relatedCells ?? [])]).map((id) => id.length),
);
const overflowPaskCellIds = pask.calls
  .flatMap((c) => [c.cellId, ...(c.relatedCells ?? [])])
  .filter((id) => id.length > 63);

const assertions = [
  ['all scenarios wrote message patches', scenarioResults.every((r) => r.wrote)],
  ['message rows equal scenario count', messages.length === scenarios.length],
  ['dispatch rows equal scenario count', dispatches.length === scenarios.length],
  ['dispatch decision ids are unique', decisionIds.size === dispatches.length],
  ['direct lane exercised', (laneCounts.direct ?? 0) >= 3],
  ['self lane exercised', (laneCounts.self ?? 0) >= 1],
  ['squad multicast lane exercised', (laneCounts.squad ?? 0) >= 1],
  ['broadcast lane exercised', (laneCounts.broadcast ?? 0) >= 1],
  ['agent lane exercised', (laneCounts.agent ?? 0) >= 1],
  ['graph/pask selected at least one job target', (dispatchPrimaryKinds.job ?? 0) >= 1],
  ['Pask boost influenced at least one route', (dispatchSources.pask ?? 0) >= 1],
  ['broadcast requires ratification', dispatches.some((d) => d.lane === 'broadcast' && d.requiresRatification)],
  ['Pask replay emitted interactions', replaySummary.interactions > graph.sites.length + graph.customers.length + graph.jobs.length],
  ['real Pask kernel accepted graph', !(pask instanceof RealPaskHarness) || ((realPaskSnapshot?.nodes ?? 0) > 0 && (realPaskSnapshot?.edges ?? 0) > 0)],
  ['Pask cell ids fit 63-byte kernel cap', overflowPaskCellIds.length === 0 && maxPaskCellLength <= 63],
  ['attention contains dispatch signals', (signalKinds.dispatch ?? 0) >= 1],
  ['attention contains message signals', (signalKinds.message ?? 0) >= 1],
] as const;
const failures = assertions.filter(([, ok]) => !ok).map(([name]) => name);

const summary = {
  verdict: failures.length === 0 ? 'pass' : 'fail',
  failures,
  liveRoot,
  tempRoot: keep ? tempRoot : '(deleted)',
  selectedFixture: {
    jobRef: redact(jobRef(fixture.job)),
    workOrderPresent: !!fixture.job.workOrderNumber,
    customerRef: redact(fixture.customer.cellId ?? fixture.customer.email ?? 'customer'),
    siteRef: redact(fixture.site?.cellId ?? fixture.job.siteRef ?? 'site'),
  },
  graphRows: {
    sites: graph.sites.length,
    customers: graph.customers.length,
    jobs: graph.jobs.length,
    attachments: graph.attachments.length,
  },
  scenarios: scenarioResults,
  writtenRows: {
    messages: messages.length,
    dispatches: dispatches.length,
  },
  dispatch: {
    laneCounts,
    primaryTargetKinds: dispatchPrimaryKinds,
    primaryTargetSources: dispatchSources,
    ratificationRequired: dispatches.filter((d) => d.requiresRatification).length,
    parallelizable: dispatches.filter((d) => d.parallelizable).length,
  },
  pask: {
    mode: pask instanceof RealPaskHarness ? 'real-wasm' : 'recording',
    wasmPath: pask instanceof RealPaskHarness ? paskWasmPath : null,
    replaySummary,
    interactionsRecorded: pask.calls.length,
    snapshot: realPaskSnapshot,
    stableThreads: stableThreads.slice(0, 8).map((t) => ({
      cellId: t.cellId,
      hState: Number(t.hState.toFixed(3)),
      interactionCount: t.interactionCount,
      isStable: t.isStable,
      totalConstraintStrength: Number(t.totalConstraintStrength.toFixed(3)),
    })),
    uniqueCells: new Set(pask.calls.map((c) => c.cellId)).size,
    maxCellIdLength: maxPaskCellLength,
    overflowCellIds: overflowPaskCellIds.length,
  },
  attention: {
    signals: signals.length,
    signalKinds,
    top: signals.slice(0, 8).map((s) => ({
      id: s.synthesizesObject?.id,
      kind: s.synthesizesObject?.payload.kind,
      status: s.synthesizesObject?.payload.status,
      score: Number(s.score.toFixed(3)),
      reason: s.factor.signal,
    })),
  },
};

if (!keep) rmSync(tempRoot, { recursive: true, force: true });

console.log(JSON.stringify(summary, null, 2));
if (failures.length > 0) process.exit(1);

function buildScenarios(input: {
  fixture: NonNullable<ReturnType<typeof chooseFixture>>;
  baseTime: number;
  turnSink: JsonlConversationTurnPatchSink;
  setWriteClock(n: number): void;
  messagesPath: string;
}): Scenario[] {
  const { fixture, baseTime, turnSink, setWriteClock, messagesPath } = input;
  const workOrder = fixture.job.workOrderNumber ?? jobRef(fixture.job).slice(0, 12);
  const customerName = fixture.customer.display_name ?? 'the customer';
  const customerContact =
    fixture.customer.email
    ?? fixture.customer.phone
    ?? fixture.customer.cellId
    ?? 'customer:unknown';
  const address = fixture.site?.fullAddress ?? fixture.site?.normalisedAddress ?? 'the job site';

  const appendOperatorPatch = (patch: OddjobzMessagePatch): boolean => {
    appendFileSync(messagesPath, `${JSON.stringify(patch)}\n`);
    capturedPatches.push(patch);
    return true;
  };

  return [
    {
      name: 'gmail customer asks for invoice against existing work order',
      timestamp: baseTime,
      write() {
        setWriteClock(baseTime + 100);
        return turnSink.appendRawItem(makeEmailRawItem({
          id: 'mock-gmail-invoice-1',
          from: `${customerName} <${fixture.customer.email ?? 'customer@example.test'}>`,
          subject: `Invoice for work order ${workOrder}`,
          body: `Hi Todd, can you send the invoice for work order ${workOrder} at ${address}?`,
          timestamp: baseTime,
        }));
      },
    },
    {
      name: 'meta customer follow-up resolves by work order text',
      timestamp: baseTime + 7 * 60_000,
      write() {
        return turnSink.append(makeTurn({
          providerId: 'meta',
          channel: 'meta_messenger',
          sessionId: 'meta:thread-existing-job',
          recipientId: 'psid:customer-existing',
          role: 'customer',
          text: `Hey mate, any update on job ${workOrder}? This is for ${address}.`,
          timestamp: baseTime + 7 * 60_000,
        }));
      },
    },
    {
      name: 'widget new lead stays source-neutral without graph match',
      timestamp: baseTime + 14 * 60_000,
      write() {
        return turnSink.append(makeTurn({
          providerId: 'widget',
          channel: 'widget',
          sessionId: 'widget:new-lead',
          recipientId: 'web:visitor-1',
          role: 'customer',
          text: 'Need someone to fix a broken hinge next week, not sure if it needs replacing.',
          timestamp: baseTime + 14 * 60_000,
        }));
      },
    },
    {
      name: 'operator self note binds to active job via Pask boost',
      timestamp: baseTime + 21 * 60_000,
      write() {
        return appendOperatorPatch(makeOperatorPatch({
          patchId: 'mock-operator-self-1',
          sessionId: 'voice:self',
          channel: 'voice',
          text: `Note to self: add a parts-run variance receipt to work order ${workOrder}.`,
          timestamp: baseTime + 21 * 60_000,
        }));
      },
    },
    {
      name: 'operator direct reply resolves in parallel with graph context',
      timestamp: baseTime + 28 * 60_000,
      write() {
        return appendOperatorPatch(makeOperatorPatch({
          patchId: 'mock-operator-direct-1',
          sessionId: 'voice:direct',
          channel: 'voice',
          recipientId: customerContact,
          text: `Tell ${customerName} I am running 30 minutes late for work order ${workOrder}.`,
          timestamp: baseTime + 28 * 60_000,
        }));
      },
    },
    {
      name: 'operator squad message becomes multicast',
      timestamp: baseTime + 35 * 60_000,
      write() {
        return appendOperatorPatch(makeOperatorPatch({
          patchId: 'mock-operator-squad-1',
          sessionId: 'voice:squad',
          channel: 'voice',
          text: `Squad, bring the big ladder for work order ${workOrder} at ${address}.`,
          timestamp: baseTime + 35 * 60_000,
        }));
      },
    },
    {
      name: 'operator broadcast is ratification-gated',
      timestamp: baseTime + 42 * 60_000,
      write() {
        return appendOperatorPatch(makeOperatorPatch({
          patchId: 'mock-operator-broadcast-1',
          sessionId: 'voice:broadcast',
          channel: 'voice',
          text: 'Broadcast: bookings are tight this week, emergency leak callouts only until Friday.',
          timestamp: baseTime + 42 * 60_000,
        }));
      },
    },
    {
      name: 'operator addresses agent/butler lane',
      timestamp: baseTime + 49 * 60_000,
      write() {
        return appendOperatorPatch(makeOperatorPatch({
          patchId: 'mock-operator-agent-1',
          sessionId: 'voice:agent',
          channel: 'voice',
          text: `Brain, check whether work order ${workOrder} should be quoted as repair or replacement.`,
          timestamp: baseTime + 49 * 60_000,
        }));
      },
    },
  ];
}

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

function makeTurn(input: ConversationTurnEvent): ConversationTurnEvent {
  return input;
}

function makeOperatorPatch(input: {
  patchId: string;
  sessionId: string;
  channel: string;
  text: string;
  timestamp: number;
  recipientId?: string;
}): OddjobzMessagePatch {
  return {
    schema: 'oddjobz.message.v1',
    patchId: input.patchId,
    op: 'oddjobz.message.v1',
    providerId: 'voice',
    sessionId: input.sessionId,
    channel: input.channel,
    recipientId: input.recipientId ?? 'operator:self',
    role: 'operator',
    text: input.text,
    timestamp: input.timestamp,
    writtenAt: input.timestamp + 100,
    target: {
      type: 'conversation-session',
      ref: input.sessionId,
    },
  };
}

function makeEmailRawItem(input: {
  id: string;
  from: string;
  subject: string;
  body: string;
  timestamp: number;
}): RawItem {
  const date = new Date(input.timestamp).toUTCString();
  const bytes = new TextEncoder().encode([
    `Message-ID: <${input.id}@oddjobz-smoke.local>`,
    `Date: ${date}`,
    `From: ${input.from}`,
    'To: Todd <todd@oddjobtodd.info>',
    `Subject: ${input.subject}`,
    '',
    input.body,
  ].join('\r\n'));
  return {
    providerId: 'gmail',
    providerItemId: input.id,
    fetchedAt: input.timestamp + 50,
    contentType: 'email/rfc822',
    bytes,
    metadata: {
      internalDate: String(input.timestamp),
      subject: input.subject,
      from: input.from,
      to: 'Todd <todd@oddjobtodd.info>',
      threadId: `mock-thread-${input.id}`,
      snippet: input.body.slice(0, 120),
    },
  };
}

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
  const customersById = new Map(graph.customers.filter((c) => c.cellId).map((c) => [c.cellId!, c]));
  const sitesById = new Map(graph.sites.filter((s) => s.cellId).map((s) => [s.cellId!, s]));
  for (const job of graph.jobs) {
    if (!job.workOrderNumber) continue;
    const primary = (job.customerRefs ?? []).find((r) => r.primary) ?? job.customerRefs?.[0];
    const customer = primary?.cellId ? customersById.get(primary.cellId) : undefined;
    if (!customer?.email && !customer?.phone) continue;
    return {
      job,
      customer,
      site: job.siteRef ? sitesById.get(job.siteRef) ?? null : null,
    };
  }
  return null;
}

function readJsonl<T>(path: string): T[] {
  if (!existsSync(path)) return [];
  const out: T[] = [];
  for (const line of readFileSync(path, 'utf8').split(/\n/)) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line) as T);
    } catch {
      // Smoke tests should survive historical malformed append-only rows.
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
  return job.cellId ?? job.id ?? '';
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

```
