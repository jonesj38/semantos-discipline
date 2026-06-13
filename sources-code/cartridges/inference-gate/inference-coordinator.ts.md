---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/inference-coordinator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.410673+00:00
---

# cartridges/inference-gate/inference-coordinator.ts

```ts
#!/usr/bin/env bun
/**
 * inference-coordinator.ts  (:5202)
 *
 * Subscribes to ALL inference.request.* cells, looks up available workers
 * from the registry, and republishes the cell with a routing hint
 * (scopeHash = SHA-256(workerId)[0:32]) so the correct worker picks it up.
 *
 * ── PIPELINE mode ─────────────────────────────────────────────────────────────
 * Request payload may include `_pipeline: string[]` — a list of additional
 * typePaths to dispatch the result through sequentially after the initial stage.
 *
 *   Client → relay:  inference.request.safety.ppe  payload:{ prompt, _pipeline:["inference.request.analysis.*"] }
 *   Coordinator:     dispatch to Pi #1 (safety worker), mark _pipelineId
 *   Pi #1 result:    inference.result.response  { _pipelineId, label, result }
 *   Coordinator:     dispatch result to Pi #2 (analysis worker), prompt = prior result
 *   Pi #2 result:    inference.result.response  { _pipelineId }
 *   Coordinator:     no more stages → publish inference.result.pipeline { stages, results }
 *
 * ── ENSEMBLE mode ─────────────────────────────────────────────────────────────
 * Request payload may include `_ensemble: { n: number, required: number }` — fan
 * out to N workers for the same typePath, settle when `required` agree on label.
 *
 *   Client → relay:  inference.request.safety.ppe  payload:{ prompt, _ensemble:{n:3,required:2} }
 *   Coordinator:     dispatch to 3 safety workers, mark _ensembleId
 *   Results:         3× inference.result.response  { _ensembleId, label }
 *   Coordinator:     2 agree on "ppe_violation" → publish inference.result.ensemble { label, votes, results }
 *
 * ── HTTP :5202 ────────────────────────────────────────────────────────────────
 *   GET /coordinator/stats       totals, no-worker count, by-type breakdown
 *   GET /coordinator/queue       pending (received but not yet dispatched)
 *   GET /coordinator/log         last 50 dispatches
 *   GET /coordinator/pipelines   active pipeline states
 *   GET /coordinator/ensembles   active ensemble states
 *   GET /health                  service health
 *
 * ── ENV ───────────────────────────────────────────────────────────────────────
 *   COORDINATOR_PORT   listen port (default 5202)
 *   RELAY_URL          multicast relay (default http://localhost:5199)
 *   REGISTRY_URL       worker registry (default http://localhost:5201)
 *   DISPATCH_TIMEOUT   max ms to wait for a worker query (default 500)
 */

import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const PORT             = Number(process.env.COORDINATOR_PORT ?? '5202');
const RELAY_URL        = process.env.RELAY_URL        ?? 'http://localhost:5199';
const REGISTRY_URL     = process.env.REGISTRY_URL     ?? 'http://localhost:5201';
const DISPATCH_TIMEOUT = Number(process.env.DISPATCH_TIMEOUT ?? '500');

const COORDINATOR_FP   = createHash('sha256').update('inference-coordinator').digest('hex').slice(0, 8);

// ── Types ─────────────────────────────────────────────────────────────────────

interface CanonicalCellHeader {
  cellId:     string;
  typePath:   string;
  senderFp:   string;
  seq:        number;
  payloadLen: number;
  scopeHash?: string;
  ts?:        number;
}

interface WorkerRecord {
  workerId:     string;
  nodeIp:       string;
  typePaths:    string[];
  model:        string;
  loadPct:      number;
  cellsHandled: number;
  satsEarned:   number;
  lastSeen:     number;
  active:       boolean;
}

interface PendingRequest {
  cellId:     string;
  typePath:   string;
  receivedAt: number;
}

// ── Pipeline state ────────────────────────────────────────────────────────────
// Each pipeline tracks remaining stages after the initial dispatch.
// When coordinator sees a result with _pipelineId, it advances to the next stage.

interface PipelineStageResult {
  stageTypePath: string;
  label:         string;
  result:        string;
  confidence:    number;
  workerId:      string;
  nodeIp:        string;
  latencyMs:     number;
}

interface PipelineState {
  pipelineId:        string;
  originalRequestId: string;
  initialTypePath:   string;
  stages:            string[];   // additional stages after the first
  nextStageIdx:      number;     // index into stages[] for the next dispatch
  accumulated:       PipelineStageResult[];
  startedAt:         number;
  settled:           boolean;
}

// ── Ensemble state ────────────────────────────────────────────────────────────
// When coordinator fans out to N workers, it waits for M-of-N to agree on a label.

interface EnsembleVote {
  label:     string;
  result:    string;
  confidence: number;
  workerId:  string;
  nodeIp:    string;
  latencyMs: number;
}

interface EnsembleState {
  ensembleId:        string;
  originalRequestId: string;
  typePath:          string;
  n:                 number;  // total dispatches
  required:          number;  // votes needed for agreement
  votes:             EnsembleVote[];
  labelTally:        Record<string, number>;
  startedAt:         number;
  settled:           boolean;
}

// ── State ─────────────────────────────────────────────────────────────────────

let seq              = 0;
let totalDispatched  = 0;
let noWorkerCount    = 0;
let totalPipelined   = 0;
let totalEnsembled   = 0;
let relayConnected   = false;
let reconnectMs      = 1000;
let resultRelayConnected = false;
let resultReconnectMs    = 1000;

const byTypePath: Record<string, number>    = {};
const noWorkerByType: Record<string, number> = {};
const pendingQueue    = new Map<string, PendingRequest>();
const dispatchLog:    unknown[] = [];

const activePipelines = new Map<string, PipelineState>();
const activeEnsembles = new Map<string, EnsembleState>();

// ── Deduplication ─────────────────────────────────────────────────────────────
// Tracks cellIds we've already dispatched. SSE reconnects replay the ring buffer,
// so without this we'd re-dispatch the same request multiple times.
const dispatchedCellIds = new Map<string, number>(); // cellId → timestamp
const DEDUP_TTL_MS = 10 * 60 * 1000; // 10 minutes

function markDispatched(cellId: string): void {
  dispatchedCellIds.set(cellId, Date.now());
  // Prune old entries
  if (dispatchedCellIds.size > 1000) {
    const cutoff = Date.now() - DEDUP_TTL_MS;
    for (const [id, ts] of dispatchedCellIds) {
      if (ts < cutoff) dispatchedCellIds.delete(id);
    }
  }
}

function alreadyDispatched(cellId: string): boolean {
  const ts = dispatchedCellIds.get(cellId);
  return ts !== undefined && Date.now() - ts < DEDUP_TTL_MS;
}

// ── Registry queries ──────────────────────────────────────────────────────────

async function getAvailableWorkers(typePath: string, limit = 1): Promise<WorkerRecord[]> {
  try {
    const resp = await fetch(
      `${REGISTRY_URL}/workers/available?typePath=${encodeURIComponent(typePath)}&maxLoad=80`,
      { signal: AbortSignal.timeout(DISPATCH_TIMEOUT) }
    );
    if (!resp.ok) return [];
    const data: any = await resp.json();
    const workers: WorkerRecord[] = data.available ?? [];
    return workers.slice(0, limit); // already sorted by loadPct ascending
  } catch {
    return [];
  }
}

// ── Cell publishing ───────────────────────────────────────────────────────────

async function publishCell(typePath: string, payload: object, scopeHash?: string): Promise<void> {
  const payloadHex = Buffer.from(JSON.stringify(payload)).toString('hex');
  const cellId     = createHash('sha256').update(payloadHex, 'hex').digest('hex');
  const header: CanonicalCellHeader = {
    cellId, typePath, senderFp: COORDINATOR_FP,
    seq: seq++, payloadLen: payloadHex.length / 2,
    ...(scopeHash ? { scopeHash } : {}),
  };
  await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ header, payload: payloadHex }),
    signal: AbortSignal.timeout(2000),
  });
}

// ── Pipeline helpers ──────────────────────────────────────────────────────────

function routingScope(workerId: string): string {
  return createHash('sha256').update(workerId).digest('hex').slice(0, 32);
}

async function dispatchPipelineStage(state: PipelineState, lastResult: PipelineStageResult): Promise<void> {
  if (state.nextStageIdx >= state.stages.length) {
    // All stages done — publish final pipeline result
    state.settled = true;
    activePipelines.delete(state.pipelineId);
    totalPipelined++;

    console.log(`[coordinator] Pipeline ${state.pipelineId.slice(0,12)} complete — ${state.accumulated.length} stages`);
    await publishCell('inference.result.pipeline', {
      requestId:   state.originalRequestId,
      pipelineId:  state.pipelineId,
      stages:      [state.initialTypePath, ...state.stages],
      results:     state.accumulated,
      finalResult: lastResult.result,
      finalLabel:  lastResult.label,
      totalMs:     Date.now() - state.startedAt,
    });
    dispatchLog.push({ ts: Date.now(), type: 'pipeline_complete', pipelineId: state.pipelineId, stages: state.accumulated.length });
    if (dispatchLog.length > 100) dispatchLog.shift();
    return;
  }

  const nextTypePath = state.stages[state.nextStageIdx];
  const workers = await getAvailableWorkers(nextTypePath, 1);
  if (!workers.length) {
    console.warn(`[coordinator] Pipeline ${state.pipelineId.slice(0,12)} — no worker for stage ${nextTypePath}`);
    activePipelines.delete(state.pipelineId);
    await publishCell('inference.result.error', {
      requestId:  state.originalRequestId,
      pipelineId: state.pipelineId,
      error:      'no_worker_for_pipeline_stage',
      stage:      nextTypePath,
    });
    return;
  }

  const worker = workers[0];
  state.nextStageIdx++;

  // Dispatch next pipeline stage — published with COORDINATOR_FP so coordinator's
  // own request-SSE won't re-dispatch it (loop prevention). Worker DOES pick it up.
  await publishCell(nextTypePath, {
    requestId:        state.originalRequestId,
    prompt:           lastResult.result, // feed prior result as next prompt
    _pipelineId:      state.pipelineId,
    _pipelineStages:  state.stages,
    _pipelineStageN:  state.nextStageIdx,
    _previousResults: state.accumulated,
    _dispatchedTo:    worker.workerId,
    _dispatchedBy:    'coordinator-pipeline',
  }, routingScope(worker.workerId));

  console.log(`[coordinator] Pipeline ${state.pipelineId.slice(0,12)} stage ${state.nextStageIdx}/${state.stages.length}: ${nextTypePath} → ${worker.workerId.slice(0,8)} @ ${worker.nodeIp}`);
}

// ── Ensemble helpers ──────────────────────────────────────────────────────────

async function settleEnsemble(state: EnsembleState, winner: string): Promise<void> {
  state.settled = true;
  activeEnsembles.delete(state.ensembleId);
  totalEnsembled++;

  const winningVotes = state.votes.filter(v => v.label === winner);
  const avgLatency   = Math.round(state.votes.reduce((s, v) => s + v.latencyMs, 0) / state.votes.length);

  console.log(`[coordinator] Ensemble ${state.ensembleId.slice(0,12)} settled: "${winner}" (${winningVotes.length}/${state.n})`);
  await publishCell('inference.result.ensemble', {
    requestId:   state.originalRequestId,
    ensembleId:  state.ensembleId,
    label:       winner,
    result:      winningVotes[0].result,
    confidence:  winningVotes[0].confidence,
    votes:       state.votes,
    tally:       state.labelTally,
    n:           state.n,
    required:    state.required,
    avgLatencyMs: avgLatency,
    totalMs:     Date.now() - state.startedAt,
  });
  dispatchLog.push({ ts: Date.now(), type: 'ensemble_settled', ensembleId: state.ensembleId, winner, votes: state.votes.length });
  if (dispatchLog.length > 100) dispatchLog.shift();
}

// ── Result handler (pipeline + ensemble chaining) ─────────────────────────────

async function handleResult(payloadHex: string | null): Promise<void> {
  if (!payloadHex) return;
  let p: any;
  try { p = JSON.parse(Buffer.from(payloadHex, 'hex').toString('utf8')); } catch { return; }

  // ── Pipeline advancement ──────────────────────────────────────────────────
  if (p._pipelineId) {
    const state = activePipelines.get(p._pipelineId);
    if (!state || state.settled) return;

    const stageResult: PipelineStageResult = {
      stageTypePath: p.workerTypePaths?.[0] ?? 'unknown',
      label:         p.label ?? 'unknown',
      result:        p.result ?? '',
      confidence:    p.confidence ?? 0,
      workerId:      p.workerId ?? '',
      nodeIp:        p.nodeIp ?? '',
      latencyMs:     p.latencyMs ?? 0,
    };
    state.accumulated.push(stageResult);

    await dispatchPipelineStage(state, stageResult).catch(err =>
      console.error(`[coordinator] Pipeline stage dispatch error: ${err}`)
    );
    return;
  }

  // ── Ensemble vote collection ───────────────────────────────────────────────
  if (p._ensembleId) {
    const state = activeEnsembles.get(p._ensembleId);
    if (!state || state.settled) return;

    const vote: EnsembleVote = {
      label:      p.label ?? 'unknown',
      result:     p.result ?? '',
      confidence: p.confidence ?? 0,
      workerId:   p.workerId ?? '',
      nodeIp:     p.nodeIp ?? '',
      latencyMs:  p.latencyMs ?? 0,
    };
    state.votes.push(vote);
    state.labelTally[vote.label] = (state.labelTally[vote.label] ?? 0) + 1;

    console.log(`[coordinator] Ensemble ${state.ensembleId.slice(0,12)} vote ${state.votes.length}/${state.n}: "${vote.label}" from ${vote.workerId.slice(0,8)}`);

    // Check for consensus
    for (const [label, count] of Object.entries(state.labelTally)) {
      if (count >= state.required) {
        await settleEnsemble(state, label).catch(err =>
          console.error(`[coordinator] Ensemble settle error: ${err}`)
        );
        return;
      }
    }

    // All votes in but no consensus — settle with plurality
    if (state.votes.length >= state.n) {
      const plurality = Object.entries(state.labelTally).sort(([,a],[,b]) => b - a)[0]?.[0] ?? 'unknown';
      console.warn(`[coordinator] Ensemble ${state.ensembleId.slice(0,12)} no consensus — settling with plurality "${plurality}"`);
      await settleEnsemble(state, plurality).catch(console.error);
    }
  }
}

// ── Dispatch logic ────────────────────────────────────────────────────────────

async function dispatchCell(header: CanonicalCellHeader, payloadHex: string | null): Promise<void> {
  const { cellId, typePath } = header;

  // Skip cells already dispatched (SSE replay on reconnect)
  if (alreadyDispatched(cellId)) return;
  markDispatched(cellId);

  pendingQueue.set(cellId, { cellId, typePath, receivedAt: Date.now() });

  try {
    let payload: any = {};
    if (payloadHex) {
      try { payload = JSON.parse(Buffer.from(payloadHex, 'hex').toString('utf8')); } catch {}
    }

    // ── Ensemble mode ─────────────────────────────────────────────────────────
    if (payload._ensemble) {
      const { n = 2, required = 2 } = payload._ensemble as { n?: number; required?: number };
      const actualN = Math.min(n, 8);  // cap at 8

      const workers = await getAvailableWorkers(typePath, actualN);
      if (!workers.length) {
        noWorkerCount++;
        noWorkerByType[typePath] = (noWorkerByType[typePath] ?? 0) + 1;
        console.warn(`[coordinator] Ensemble: No workers for ${typePath}`);
        await publishCell('inference.result.error', {
          requestId: cellId.slice(0, 16), error: 'no_workers', typePath,
        });
        return;
      }

      const ensembleId = `ens-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
      const requestId  = payload.requestId ?? cellId.slice(0, 16);
      const effectiveN = workers.length;  // may be fewer than requested
      const effectiveRequired = Math.min(required, effectiveN);

      const state: EnsembleState = {
        ensembleId, originalRequestId: requestId,
        typePath, n: effectiveN, required: effectiveRequired,
        votes: [], labelTally: {}, startedAt: Date.now(), settled: false,
      };
      activeEnsembles.set(ensembleId, state);

      console.log(`[coordinator] Ensemble ${ensembleId.slice(0,12)}: fanning out to ${effectiveN} workers for ${typePath} (need ${effectiveRequired})`);

      // Fan out to all available workers
      for (const worker of workers) {
        const enriched = { ...payload, _ensembleId: ensembleId, _ensembleN: effectiveN, _ensembleRequired: effectiveRequired, _dispatchedTo: worker.workerId, _dispatchedBy: 'coordinator-ensemble' };
        delete enriched._ensemble; // prevent recursive ensemble
        await publishCell(typePath, enriched, routingScope(worker.workerId));
        totalDispatched++;
      }

      byTypePath[typePath] = (byTypePath[typePath] ?? 0) + 1;
      dispatchLog.push({ ts: Date.now(), cellId: cellId.slice(0,16), typePath, mode: 'ensemble', workers: workers.map(w => w.workerId.slice(0,8)), ensembleId });
      if (dispatchLog.length > 100) dispatchLog.shift();
      return;
    }

    // ── Pipeline mode ─────────────────────────────────────────────────────────
    const pipeline = payload._pipeline as string[] | undefined;
    const hasPipeline = Array.isArray(pipeline) && pipeline.length > 0;

    // ── Normal / first-stage dispatch ─────────────────────────────────────────
    const workers = await getAvailableWorkers(typePath, 1);
    if (!workers.length) {
      noWorkerCount++;
      noWorkerByType[typePath] = (noWorkerByType[typePath] ?? 0) + 1;
      console.warn(`[coordinator] No worker for ${typePath} — publishing error cell`);
      await publishCell('inference.result.error', {
        requestId: cellId.slice(0, 16), error: 'no_workers', typePath, coordinator: true,
      });
      dispatchLog.push({ ts: Date.now(), cellId: cellId.slice(0,16), typePath, workerId: null, status: 'no_worker' });
      if (dispatchLog.length > 100) dispatchLog.shift();
      return;
    }

    const worker = workers[0];
    const scope  = routingScope(worker.workerId);

    // If pipeline, create pipeline state and tag the enriched payload
    let pipelineId: string | undefined;
    if (hasPipeline) {
      // Deterministic pipelineId from requestId so SSE replays don't create duplicate states
      pipelineId = `pipe-${(payload.requestId ?? cellId).slice(0, 16)}`;
      if (activePipelines.has(pipelineId)) {
        // Already in-flight — SSE replay, skip
        return;
      }
      const state: PipelineState = {
        pipelineId,
        originalRequestId: payload.requestId ?? cellId.slice(0, 16),
        initialTypePath:   typePath,
        stages:            pipeline!,
        nextStageIdx:      0,
        accumulated:       [],
        startedAt:         Date.now(),
        settled:           false,
      };
      activePipelines.set(pipelineId, state);
      console.log(`[coordinator] Pipeline ${pipelineId.slice(0,12)}: ${typePath} → [${pipeline!.join(' → ')}] via ${worker.workerId.slice(0,8)}`);
    }

    const enriched: any = {
      ...payload,
      _dispatchedTo: worker.workerId,
      _dispatchedBy: 'coordinator',
      ...(pipelineId ? {
        _pipelineId:     pipelineId,
        _pipelineStages: pipeline,
        _pipelineStageN: 0,
      } : {}),
    };
    delete enriched._pipeline; // don't re-trigger pipeline on the worker side

    await publishCell(typePath, enriched, scope);
    totalDispatched++;
    byTypePath[typePath] = (byTypePath[typePath] ?? 0) + 1;

    console.log(`[coordinator] ${typePath} → worker ${worker.workerId.slice(0,8)} @ ${worker.nodeIp} (load:${worker.loadPct}%)${pipelineId ? ' [pipeline]' : ''}`);
    dispatchLog.push({ ts: Date.now(), cellId: cellId.slice(0,16), typePath, workerId: worker.workerId, nodeIp: worker.nodeIp, status: 'dispatched', pipelineId });
    if (dispatchLog.length > 100) dispatchLog.shift();
  } finally {
    pendingQueue.delete(cellId);
  }
}

// ── Relay SSE subscription — requests ─────────────────────────────────────────

async function subscribeRequests(): Promise<void> {
  const url = `${RELAY_URL}/cells/stream?typePath=inference.request.*`;
  console.log(`[coordinator] Connecting to relay (requests): ${url}`);

  try {
    const resp = await fetch(url, { headers: { Accept: 'text/event-stream' } });
    if (!resp.ok || !resp.body) throw new Error(`relay SSE ${resp.status}`);

    relayConnected = true;
    reconnectMs    = 1000;
    console.log('[coordinator] ✓ Request SSE connected — watching inference.request.*');

    const reader = resp.body.getReader();
    const tdec   = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += tdec.decode(value, { stream: true });

      const lines = buf.split('\n');
      buf = lines.pop() ?? '';

      let eventType = '', dataLine = '';
      for (const line of lines) {
        if (line.startsWith('event: ')) eventType = line.slice(7).trim();
        if (line.startsWith('data: '))  dataLine  = line.slice(6).trim();
        if (line === '' && dataLine) {
          if (eventType === 'cell' || !eventType) {
            try {
              const ev = JSON.parse(dataLine) as { header: CanonicalCellHeader; payload: string | null };
              if (ev.header.typePath.includes('.request.')) {
                // Skip cells we re-published ourselves (loop prevention)
                // Note: pipeline stage cells published by coordinator also have COORDINATOR_FP —
                // they skip this handler (the worker picks them up directly).
                if (ev.header.senderFp !== COORDINATOR_FP) {
                  dispatchCell(ev.header, ev.payload ?? null).catch(console.error);
                }
              }
            } catch {}
          }
          eventType = ''; dataLine = '';
        }
      }
    }
  } catch (err) {
    relayConnected = false;
    console.warn(`[coordinator] Request SSE error: ${err}. Reconnecting in ${reconnectMs}ms…`);
  }

  setTimeout(() => subscribeRequests(), reconnectMs);
  reconnectMs = Math.min(reconnectMs * 2, 30_000);
}

// ── Result polling fallback ───────────────────────────────────────────────────
// When SSE drops (Bun aarch64 bug), poll /cells/recent for result cells.
// Tracks seen cellIds to avoid double-processing.

const seenResultCellIds = new Set<string>();

async function pollResults(): Promise<void> {
  while (true) {
    await Bun.sleep(4000);
    // Only poll when SSE is down AND there are active pipelines/ensembles
    if (resultRelayConnected) continue;
    if (activePipelines.size === 0 && activeEnsembles.size === 0) continue;

    try {
      const resp = await fetch(
        `${RELAY_URL}/cells/recent?typePath=${encodeURIComponent('inference.result.*')}&limit=50`,
        { signal: AbortSignal.timeout(3000) }
      );
      if (!resp.ok) continue;
      const cells: any[] = await resp.json();
      for (const c of cells) {
        if (!c.payload || !c.header) continue;
        const cid: string = c.header.cellId ?? '';
        if (seenResultCellIds.has(cid)) continue;
        if (c.header.senderFp === COORDINATOR_FP) { seenResultCellIds.add(cid); continue; }
        seenResultCellIds.add(cid);
        handleResult(c.payload).catch(console.error);
      }
      // Prune seen set
      if (seenResultCellIds.size > 2000) {
        const arr = [...seenResultCellIds];
        arr.splice(0, 1000).forEach(id => seenResultCellIds.delete(id));
      }
    } catch {}
  }
}

// ── Relay SSE subscription — results (pipeline + ensemble chaining) ───────────

async function subscribeResults(): Promise<void> {
  const url = `${RELAY_URL}/cells/stream?typePath=inference.result.*`;
  console.log(`[coordinator] Connecting to relay (results): ${url}`);

  try {
    const resp = await fetch(url, { headers: { Accept: 'text/event-stream' } });
    if (!resp.ok || !resp.body) throw new Error(`relay SSE ${resp.status}`);

    resultRelayConnected = true;
    resultReconnectMs    = 1000;
    console.log('[coordinator] ✓ Result SSE connected — watching inference.result.* (pipeline + ensemble)');

    const reader = resp.body.getReader();
    const tdec   = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += tdec.decode(value, { stream: true });

      const lines = buf.split('\n');
      buf = lines.pop() ?? '';

      let eventType = '', dataLine = '';
      for (const line of lines) {
        if (line.startsWith('event: ')) eventType = line.slice(7).trim();
        if (line.startsWith('data: '))  dataLine  = line.slice(6).trim();
        if (line === '' && dataLine) {
          if (eventType === 'cell' || !eventType) {
            try {
              const ev = JSON.parse(dataLine) as { header: CanonicalCellHeader; payload: string | null };
              if (ev.header.typePath.includes('.result.') && ev.header.senderFp !== COORDINATOR_FP) {
                const cid = ev.header.cellId ?? '';
                if (!seenResultCellIds.has(cid)) {
                  seenResultCellIds.add(cid);
                  handleResult(ev.payload ?? null).catch(console.error);
                }
              }
            } catch {}
          }
          eventType = ''; dataLine = '';
        }
      }
    }
  } catch (err) {
    resultRelayConnected = false;
    console.warn(`[coordinator] Result SSE error: ${err}. Reconnecting in ${resultReconnectMs}ms…`);
  }

  setTimeout(() => subscribeResults(), resultReconnectMs);
  resultReconnectMs = Math.min(resultReconnectMs * 2, 30_000);
}

// ── HTTP server ───────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

Bun.serve({
  port: PORT,
  fetch(req) {
    const path = new URL(req.url).pathname;
    if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,OPTIONS' } });

    if (path === '/coordinator/stats') return json({
      totalDispatched, noWorkerCount, totalPipelined, totalEnsembled,
      pendingCount: pendingQueue.size,
      activePipelines: activePipelines.size,
      activeEnsembles: activeEnsembles.size,
      byTypePath, noWorkerByType,
      recentDispatches: dispatchLog.slice(-10),
    });

    if (path === '/coordinator/queue') return json({
      pending: [...pendingQueue.values()],
      count: pendingQueue.size,
    });

    if (path === '/coordinator/log') return json(dispatchLog.slice(-50).reverse());

    if (path === '/coordinator/pipelines') return json({
      active:   [...activePipelines.values()],
      count:    activePipelines.size,
      completed: totalPipelined,
    });

    if (path === '/coordinator/ensembles') return json({
      active:    [...activeEnsembles.values()],
      count:     activeEnsembles.size,
      completed: totalEnsembled,
    });

    if (path === '/health') return json({
      service: 'inference-coordinator', port: PORT,
      relay: RELAY_URL, registry: REGISTRY_URL,
      relayConnected, resultRelayConnected,
      totalDispatched, noWorkerCount,
      totalPipelined, totalEnsembled,
      pendingCount: pendingQueue.size,
      activePipelines: activePipelines.size,
      activeEnsembles: activeEnsembles.size,
    });

    return json({ error: 'not found' }, 404);
  },
});

console.log(`
╔══════════════════════════════════════════════════════════╗
║   inference-coordinator  :${PORT}                       ║
║   Pipeline · Ensemble · Load-Aware Dispatcher           ║
╠══════════════════════════════════════════════════════════╣
║   GET /coordinator/stats      dispatch totals           ║
║   GET /coordinator/queue      pending requests          ║
║   GET /coordinator/log        last 50 dispatches        ║
║   GET /coordinator/pipelines  active pipeline states    ║
║   GET /coordinator/ensembles  active ensemble states    ║
║   GET /health                 service health            ║
╠══════════════════════════════════════════════════════════╣
║   Relay:    ${RELAY_URL.padEnd(46)} ║
║   Registry: ${REGISTRY_URL.padEnd(46)} ║
╚══════════════════════════════════════════════════════════╝

  Pipeline:  include  _pipeline: ["inference.request.analysis.*"]  in request payload
  Ensemble:  include  _ensemble: { n: 3, required: 2 }             in request payload
`);

// ── Startup: prime dedup map from current ring buffer ─────────────────────────
// Pre-mark all cells already in the relay ring buffer as dispatched so that
// the first SSE connection's ring-buffer replay doesn't re-dispatch stale
// requests from prior coordinator sessions.
(async () => {
  try {
    const resp = await fetch(`${RELAY_URL}/cells/recent?typePath=inference.request.*&limit=500`, {
      signal: AbortSignal.timeout(3000),
    });
    if (resp.ok) {
      const data: any = await resp.json();
      const cells: any[] = Array.isArray(data) ? data : (data.cells ?? []);
      let primed = 0;
      for (const c of cells) {
        if (c.header?.cellId) { markDispatched(c.header.cellId); primed++; }
      }
      if (primed) console.log(`[coordinator] Primed dedup map with ${primed} existing ring-buffer cells (replay-safe startup)`);
    }
  } catch {}
  subscribeRequests();
  subscribeResults();
  pollResults(); // polling fallback when SSE drops (Bun aarch64 bug)
})();

```
