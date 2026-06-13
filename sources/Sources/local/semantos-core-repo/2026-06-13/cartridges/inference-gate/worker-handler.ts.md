---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/worker-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.410103+00:00
---

# cartridges/inference-gate/worker-handler.ts

```ts
#!/usr/bin/env bun
/**
 * worker-handler.ts — Specialised mesh inference worker
 *
 * Designed to run on each Orange Pi in the Skyminer mesh. Registers with
 * the worker registry, subscribes ONLY to its designated type paths, processes
 * inference cells, and heartbeats its load back to the registry.
 *
 * Key difference from cell-handler.ts:
 *   - Typed SSE subscription: only sees cells matching its WORKER_TYPES
 *   - Registers with worker registry so coordinator can find it
 *   - Heartbeats load% every 5s for load-aware dispatch
 *   - Earns sats via CashLanes per processed cell
 *
 * USAGE
 * ─────
 *   bun worker-handler.ts
 *
 * ENV VARS
 * ────────
 *   WORKER_TYPES     comma-separated type filters, e.g. "inference.safety.*,inference.ppe.*"
 *   MODEL            model hint: "mock" | "llama-1b" | "llama-3b" | "whisper-small"
 *   MAX_CONCURRENT   max parallel inference requests (default 2)
 *   REGISTRY_URL     worker registry base URL (default http://localhost:5201)
 *   RELAY_URL        multicast relay base URL (default http://localhost:5199)
 *   BRIDGE_URL       CashLanes bridge base URL (default http://localhost:5198)
 *   WORKER_PORT      HTTP port for this worker (default 5196)
 *   NODE_IP          advertised IP (default 127.0.0.1)
 *   WORKER_ID        fixed ID (default: auto-generated)
 *   LLAMA_URL        llama-server base URL for real inference (default http://localhost:8080)
 *   WHISPER_URL      whisper.cpp base URL for audio (default '')
 *   OLLAMA_URL       ollama base URL (default '')
 *   OLLAMA_MODEL     ollama model name (default 'phi3')
 *
 * HTTP :5196 (or WORKER_PORT)
 *   GET /health   worker health + registry status
 *   GET /stats    request stats + latency percentiles
 *   GET /log      last 50 request/response pairs
 */

import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL      = process.env.RELAY_URL      ?? 'http://localhost:5199';
const REGISTRY_URL   = process.env.REGISTRY_URL   ?? 'http://localhost:5201';
const BRIDGE_URL     = process.env.BRIDGE_URL      ?? 'http://localhost:5198';
const LLAMA_URL      = process.env.LLAMA_URL      ?? 'http://localhost:8080';
const WHISPER_URL    = process.env.WHISPER_URL    ?? '';
const OLLAMA_URL     = process.env.OLLAMA_URL     ?? '';
const OLLAMA_MODEL   = process.env.OLLAMA_MODEL   ?? 'phi3';
const HTTP_PORT      = Number(process.env.WORKER_PORT ?? '5196');
const NODE_IP        = process.env.NODE_IP        ?? '127.0.0.1';
const MAX_CONCURRENT = Number(process.env.MAX_CONCURRENT ?? '2');
const MODEL          = process.env.MODEL          ?? 'mock';

const WORKER_TYPES: string[] = (process.env.WORKER_TYPES ?? 'inference.*')
  .split(',').map(s => s.trim()).filter(Boolean);

const WORKER_ID: string = process.env.WORKER_ID
  ?? createHash('sha256').update(`${NODE_IP}:${WORKER_TYPES.join(',')}:${Date.now()}`).digest('hex').slice(0, 16);

const SENDER_FP: string = createHash('sha256')
  .update(WORKER_ID).digest('hex').slice(0, 8);

const MODEL_LABEL = WHISPER_URL
  ? `whisper@${WHISPER_URL}`
  : OLLAMA_URL
  ? `${OLLAMA_MODEL}@ollama`
  : MODEL === 'mock'
  ? 'mock-classifier'
  : `${MODEL}@llama-server`;

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

interface InferenceRequest {
  requestId?:       string;
  prompt?:          string;
  audio?:           string;
  model?:           string;
  maxTokens?:       number;
  description?:     string;
  zone?:            string;
  eventType?:       string;
  // Pipeline passthrough — coordinator chains multi-stage inference
  _pipelineId?:     string;
  _pipelineStages?: string[];
  _pipelineStageN?: number;
  _previousResults?: unknown[];
  // Ensemble passthrough — coordinator fans out to N workers for voting
  _ensembleId?:     string;
  _ensembleN?:      number;
  _ensembleRequired?: number;
  // General — skip re-dispatch if already handled
  _dispatchedTo?:   string;
  _dispatchedBy?:   string;
}

// ── State ─────────────────────────────────────────────────────────────────────

// Deduplication: skip cells whose requestId we've already processed (coordinator re-dispatch)
const processedIds = new Set<string>();
const MAX_DEDUP = 500;

let activeRequests   = 0;
let cellsHandled     = 0;
let satsEarned       = 0;
let errorCount       = 0;
let relayConnected   = false;
let registryOnline   = false;
let seq              = 0;
let reconnectMs      = 1000;
const latencies: number[] = [];
const requestLog: unknown[] = [];

// ── Registry integration ──────────────────────────────────────────────────────

async function registerWithRegistry(): Promise<void> {
  try {
    const resp = await fetch(`${REGISTRY_URL}/workers/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workerId:  WORKER_ID,
        nodeIp:    NODE_IP,
        typePaths: WORKER_TYPES,
        model:     MODEL_LABEL,
        loadPct:   loadPct(),
        cellsHandled,
        satsEarned,
      }),
      signal: AbortSignal.timeout(3000),
    });
    if (resp.ok) {
      registryOnline = true;
      console.log(`[worker] Registered with registry: ${WORKER_ID}`);
    }
  } catch (err) {
    registryOnline = false;
    console.warn(`[worker] Registry unavailable: ${err}`);
  }
}

function loadPct(): number {
  return Math.round((activeRequests / MAX_CONCURRENT) * 100);
}

// Heartbeat every 5s
setInterval(async () => {
  try {
    const resp = await fetch(`${REGISTRY_URL}/workers/heartbeat/${WORKER_ID}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ loadPct: loadPct(), cellsHandled, satsEarned }),
      signal: AbortSignal.timeout(2000),
    });
    registryOnline = resp.ok;
  } catch {
    registryOnline = false;
  }
}, 5000);

// Deregister on shutdown
process.on('SIGTERM', async () => {
  try {
    await fetch(`${REGISTRY_URL}/workers/${WORKER_ID}`, { method: 'DELETE', signal: AbortSignal.timeout(2000) });
  } catch {}
  process.exit(0);
});
process.on('SIGINT', async () => {
  try {
    await fetch(`${REGISTRY_URL}/workers/${WORKER_ID}`, { method: 'DELETE', signal: AbortSignal.timeout(2000) });
  } catch {}
  process.exit(0);
});

// ── Inference engines ─────────────────────────────────────────────────────────

// Safety-domain mock: PPE, fire, fall, access
const SAFETY_KEYWORDS: Record<string, string> = {
  'hard hat': 'ppe_violation', 'no helmet': 'ppe_violation', 'missing ppe': 'ppe_violation',
  'fire': 'fire_detected', 'smoke': 'smoke_detected', 'flame': 'fire_detected',
  'fall': 'fall_detected', 'trip': 'fall_risk', 'slip': 'fall_risk',
  'restricted': 'access_violation', 'unauthorised': 'access_violation', 'trespassing': 'access_violation',
  'vest': 'ppe_compliant', 'helmet on': 'ppe_compliant', 'compliant': 'ppe_compliant',
};

// Analysis-domain mock: anomaly, sensor, report
const ANALYSIS_KEYWORDS: Record<string, string> = {
  'temperature': 'sensor_reading', 'pressure': 'sensor_reading', 'vibration': 'sensor_reading',
  'anomaly': 'anomaly_detected', 'spike': 'anomaly_detected', 'unusual': 'anomaly_detected',
  'report': 'report_generated', 'summary': 'report_generated', 'digest': 'report_generated',
  'normal': 'normal_operation', 'stable': 'normal_operation', 'nominal': 'normal_operation',
};

// Access-domain mock: grant, deny
const ACCESS_KEYWORDS: Record<string, string> = {
  'tier 0': 'access_denied', 'anonymous': 'access_denied', 'bot': 'access_denied', 'unauthenticated': 'access_denied',
  'tier 1': 'access_granted', 'tier 2': 'access_granted', 'tier 3': 'access_granted',
  'restricted': 'access_denied', 'confidential': 'access_denied',
  'public': 'access_granted', 'internal': 'access_granted',
};

function mockInfer(prompt: string, typePath: string): { result: string; label: string; confidence: number } {
  const lower = prompt.toLowerCase();

  // Pick keyword map based on type domain
  let kwMap = SAFETY_KEYWORDS;
  if (typePath.includes('analysis') || typePath.includes('sensor') || typePath.includes('anomaly')) kwMap = ANALYSIS_KEYWORDS;
  if (typePath.includes('access') || typePath.includes('grant') || typePath.includes('deny'))       kwMap = ACCESS_KEYWORDS;

  for (const [kw, label] of Object.entries(kwMap)) {
    if (lower.includes(kw)) {
      const confidence = 0.82 + Math.random() * 0.15;
      return { result: `[${label}] ${prompt.slice(0, 80)}`, label, confidence };
    }
  }
  return {
    result: `[unclassified] ${prompt.slice(0, 80)}`,
    label: 'unclassified',
    confidence: 0.45 + Math.random() * 0.2,
  };
}

async function llamaInfer(prompt: string): Promise<{ result: string; label: string; confidence: number }> {
  const resp = await fetch(`${LLAMA_URL}/completion`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, n_predict: 16, temperature: 0.1 }),
    signal: AbortSignal.timeout(300_000), // 3B model ~13s/tok; 16tok × 13s = ~208s; 300s headroom
  });
  if (!resp.ok) throw new Error(`llama-server ${resp.status}`);
  const data: any = await resp.json();
  const result = data.content?.trim() ?? '';
  return { result, label: 'llm_response', confidence: 0.9 };
}

async function ollamaInfer(prompt: string): Promise<{ result: string; label: string; confidence: number }> {
  const resp = await fetch(`${OLLAMA_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: OLLAMA_MODEL, prompt, stream: false }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!resp.ok) throw new Error(`ollama ${resp.status}`);
  const data: any = await resp.json();
  return { result: data.response?.trim() ?? '', label: 'llm_response', confidence: 0.9 };
}

async function runInference(req: InferenceRequest, typePath: string): Promise<{ result: string; label: string; confidence: number }> {
  const prompt = req.prompt ?? req.description ?? req.eventType ?? 'no prompt';

  if (OLLAMA_URL) return ollamaInfer(prompt);
  if (LLAMA_URL && MODEL !== 'mock') return llamaInfer(prompt);
  // Small simulated latency for mock mode
  await Bun.sleep(80 + Math.random() * 120);
  return mockInfer(prompt, typePath);
}

// ── Cell publishing ───────────────────────────────────────────────────────────

async function publishCell(typePath: string, payload: object): Promise<void> {
  const payloadHex = Buffer.from(JSON.stringify(payload)).toString('hex');
  const cellId     = createHash('sha256').update(payloadHex, 'hex').digest('hex');
  const header: CanonicalCellHeader = {
    cellId, typePath, senderFp: SENDER_FP,
    seq: seq++, payloadLen: payloadHex.length / 2,
  };
  await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ header, payload: payloadHex }),
    signal: AbortSignal.timeout(2000),
  });
}

async function advanceCashLanes(requestId: string): Promise<string | null> {
  try {
    const resp = await fetch(`${BRIDGE_URL}/channel/advance`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ bytes: 1024, meta: { requestId } }),
      signal: AbortSignal.timeout(2000),
    });
    if (!resp.ok) return null;
    const data: any = await resp.json();
    const earned = data.satsCharged ?? 0;
    satsEarned += earned;
    return data.settlementTxid ?? null;
  } catch {
    return null;
  }
}

// ── Cell processing ───────────────────────────────────────────────────────────

async function handleCell(header: CanonicalCellHeader, payloadHex: string | null): Promise<void> {
  if (activeRequests >= MAX_CONCURRENT) return; // back-pressure

  // Dedup: skip if we already processed this cell (coordinator may re-dispatch)
  const dedupKey = header.cellId;
  if (processedIds.has(dedupKey)) return;
  processedIds.add(dedupKey);
  if (processedIds.size > MAX_DEDUP) {
    const first = processedIds.values().next().value;
    if (first) processedIds.delete(first);
  }

  // Only process cells explicitly dispatched to this worker by the coordinator.
  // The coordinator always sets _dispatchedTo on cells it routes. We reject:
  //   - undispatched original request cells (ring-buffer replay artifact)
  //   - cells dispatched to other workers or prior incarnations of this worker
  // This ensures only one worker processes each request and prevents stale
  // ring-buffer cells from occupying slots on worker restart.
  let req: InferenceRequest = {};
  if (payloadHex) {
    try { req = JSON.parse(Buffer.from(payloadHex, 'hex').toString('utf8')); } catch {}
  }
  if (req._dispatchedTo !== WORKER_ID) return;

  activeRequests++;
  const t0 = Date.now();

  try {

    const { result, label, confidence } = await runInference(req, header.typePath);
    const latencyMs = Date.now() - t0;
    latencies.push(latencyMs);
    if (latencies.length > 200) latencies.shift();

    const requestId = req.requestId ?? header.cellId.slice(0, 16);
    const txid      = await advanceCashLanes(requestId);

    // Build pipeline / ensemble passthrough fields (coordinator uses these for chaining)
    const chainMeta: Record<string, unknown> = {};
    if (req._pipelineId)     chainMeta._pipelineId     = req._pipelineId;
    if (req._pipelineStages) chainMeta._pipelineStages = req._pipelineStages;
    if (req._pipelineStageN !== undefined) chainMeta._pipelineStageN = req._pipelineStageN;
    if (req._previousResults) chainMeta._previousResults = req._previousResults;
    if (req._ensembleId)     chainMeta._ensembleId     = req._ensembleId;
    if (req._ensembleN !== undefined)       chainMeta._ensembleN       = req._ensembleN;
    if (req._ensembleRequired !== undefined) chainMeta._ensembleRequired = req._ensembleRequired;

    await publishCell('inference.result.response', {
      requestId,
      result,
      label,
      confidence,
      model:    MODEL_LABEL,
      latencyMs,
      workerId: WORKER_ID,
      nodeIp:   NODE_IP,
      workerTypePaths: WORKER_TYPES,
      bsvTxid: txid,
      certTier:  req.model ?? 'auto',
      dataClass: 'inference',
      policyHex: '7c760101a2697ca2',
      ...chainMeta,
    });

    cellsHandled++;
    const entry = { ts: Date.now(), requestId, typePath: header.typePath, workerId: WORKER_ID, ok: true, label, latencyMs, result: result.slice(0, 200) };
    requestLog.push(entry);
    if (requestLog.length > 50) requestLog.shift();

    console.log(`[worker:${WORKER_ID.slice(0,8)}] ${header.typePath} → ${label} (${latencyMs}ms)${txid ? ' ✓ BSV' : ''}`);
  } catch (err) {
    errorCount++;
    console.error(`[worker] Error handling ${header.cellId}: ${err}`);
    const requestId = header.cellId.slice(0, 16);
    await publishCell('inference.result.error', { requestId, error: String(err), workerId: WORKER_ID }).catch(() => {});
  } finally {
    activeRequests--;
  }
}

// ── Relay SSE subscription ────────────────────────────────────────────────────

async function subscribeRelay(): Promise<void> {
  // Build typed subscription: join all WORKER_TYPES into SSE filter
  // The relay supports a single ?typePath= filter; use the first if multiple,
  // or 'inference.*' as fallback. Workers with multiple types get all inference.*
  // and filter locally — still much better than unfiltered.
  const filterPath = WORKER_TYPES.length === 1 ? WORKER_TYPES[0] : 'inference.*';
  const url = `${RELAY_URL}/cells/stream?typePath=${encodeURIComponent(filterPath)}`;
  console.log(`[worker] Connecting to relay SSE: ${url}`);

  try {
    const resp = await fetch(url, { headers: { Accept: 'text/event-stream' } });
    if (!resp.ok || !resp.body) throw new Error(`relay SSE ${resp.status}`);

    relayConnected = true;
    reconnectMs    = 1000;
    console.log(`[worker:${WORKER_ID.slice(0,8)}] ✓ Relay connected | types: [${WORKER_TYPES.join(', ')}] | model: ${MODEL_LABEL}`);

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
              const h = ev.header;
              // Local filter: only handle types this worker is subscribed to
              if (!WORKER_TYPES.some(f => matchesFilter(h.typePath, f))) { dataLine = ''; eventType = ''; continue; }
              // Only handle request cells — typePath must contain 'request' OR match worker's types directly
              // Avoids processing result/error cells that share the same prefix
              const isRequest = h.typePath.includes('.request.') || h.typePath.includes('request.');
              const isResult  = h.typePath.includes('.result.') || h.typePath.includes('.error.');
              if (!isRequest || isResult) { dataLine = ''; eventType = ''; continue; }
              handleCell(h, ev.payload ?? null).catch(console.error);
            } catch {}
          }
          eventType = ''; dataLine = '';
        }
      }
    }
  } catch (err) {
    relayConnected = false;
    console.warn(`[worker] Relay SSE error: ${err}. Reconnecting in ${reconnectMs}ms…`);
  }

  setTimeout(() => subscribeRelay(), reconnectMs);
  reconnectMs = Math.min(reconnectMs * 2, 30_000);
}

// ── Polling fallback ──────────────────────────────────────────────────────────
// When SSE drops (Bun aarch64 bug), poll /cells/recent for cells routed to us.
// Complements SSE — ensures cells dispatched during SSE-down windows are picked up.

async function pollForCells(): Promise<void> {
  const filterPath = WORKER_TYPES.length === 1 ? WORKER_TYPES[0] : 'inference.*';
  while (true) {
    await Bun.sleep(3000);
    if (relayConnected) continue; // SSE is up, no need to poll
    if (activeRequests >= MAX_CONCURRENT) continue; // busy
    try {
      const resp = await fetch(
        `${RELAY_URL}/cells/recent?typePath=${encodeURIComponent(filterPath)}&limit=50`,
        { signal: AbortSignal.timeout(3000) }
      );
      if (!resp.ok) continue;
      const data: any = await resp.json();
      const cells: any[] = data.cells ?? data;
      for (const c of cells) {
        const h: CanonicalCellHeader = c.header;
        if (!h) continue;
        if (!WORKER_TYPES.some(f => matchesFilter(h.typePath, f))) continue;
        const isRequest = h.typePath.includes('.request.') || h.typePath.includes('request.');
        if (!isRequest) continue;
        // Polling fallback: ONLY process coordinator-dispatched cells addressed to us.
        // Never pick up original (undispatched) request cells from the ring buffer —
        // the coordinator handles routing and would double-process them otherwise.
        if (c.payload) {
          try {
            const p = JSON.parse(Buffer.from(c.payload, 'hex').toString('utf8'));
            if (!p._dispatchedTo || p._dispatchedTo !== WORKER_ID) continue;
          } catch { continue; }
        } else { continue; }
        handleCell(h, c.payload ?? null).catch(console.error);
      }
    } catch {}
  }
}

function matchesFilter(typePath: string, filter: string): boolean {
  if (filter.endsWith('.*')) return typePath.startsWith(filter.slice(0, -1));
  if (filter.endsWith('*'))  return typePath.startsWith(filter.slice(0, -1));
  return typePath === filter;
}

// ── Latency percentiles ───────────────────────────────────────────────────────

function percentile(arr: number[], p: number): number {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length * p / 100)] ?? 0;
}

// ── HTTP server ───────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

Bun.serve({
  port: HTTP_PORT,
  fetch(req) {
    const path = new URL(req.url).pathname;
    if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*' } });

    if (path === '/health') return json({
      service: 'worker-handler', workerId: WORKER_ID, port: HTTP_PORT,
      nodeIp: NODE_IP, model: MODEL_LABEL, workerTypes: WORKER_TYPES,
      activeRequests, maxConcurrent: MAX_CONCURRENT, loadPct: loadPct(),
      cellsHandled, satsEarned, errorCount, relayConnected, registryOnline,
      requestsHandled: cellsHandled,
    });

    if (path === '/stats') return json({
      cellsHandled, errorCount, satsEarned,
      p50Ms: percentile(latencies, 50), p99Ms: percentile(latencies, 99),
      loadPct: loadPct(), activeRequests, maxConcurrent: MAX_CONCURRENT,
    });

    if (path === '/log') return json(requestLog.slice(-50).reverse());

    return json({ error: 'not found' }, 404);
  },
});

// ── Boot ──────────────────────────────────────────────────────────────────────

console.log(`
╔══════════════════════════════════════════════════════════╗
║   worker-handler  :${HTTP_PORT}                              ║
║   Specialised Mesh Inference Worker                     ║
╠══════════════════════════════════════════════════════════╣
║   Worker ID: ${WORKER_ID}          ║
║   Node IP:   ${NODE_IP.padEnd(46)} ║
║   Model:     ${MODEL_LABEL.slice(0,46).padEnd(46)} ║
║   Types:     ${WORKER_TYPES.join(',').slice(0,46).padEnd(46)} ║
║   Capacity:  ${MAX_CONCURRENT} concurrent requests                       ║
╠══════════════════════════════════════════════════════════╣
║   Registry:  ${REGISTRY_URL.padEnd(46)} ║
║   Relay:     ${RELAY_URL.padEnd(46)} ║
╚══════════════════════════════════════════════════════════╝
`);

await registerWithRegistry();
subscribeRelay();
pollForCells(); // polling fallback when SSE drops (Bun aarch64 bug)

```
