---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/api-worker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.408088+00:00
---

# cartridges/inference-gate/api-worker.ts

```ts
#!/usr/bin/env bun
/**
 * api-worker.ts — Claude API inference worker for the Semantos mesh
 *
 * Slots into the existing coordinator → worker protocol as a drop-in
 * companion to worker-handler.ts. Subscribes to one or more typePaths
 * via the relay SSE, processes cells dispatched to it by the coordinator,
 * calls the Anthropic Claude API, and publishes an `inference.result.response`
 * cell back to the relay — exactly what the other workers do.
 *
 * Useful for:
 *   - Long-form compliance reports (mining rehab inspection text)
 *   - NDVI / sensor data interpretation
 *   - Any task where an Orange Pi 1-3B model isn't enough
 *
 * ENV VARS
 * ────────
 *   ANTHROPIC_API_KEY   (required) — your Anthropic API key
 *   WORKER_TYPES        comma-separated type filters (default "inference.request.classify")
 *   CLAUDE_MODEL        Claude model name (default "claude-haiku-4-5")
 *   MAX_TOKENS          max output tokens per request (default 512)
 *   SYSTEM_PROMPT       custom system prompt (default: mining-rehab expert)
 *   MAX_CONCURRENT      max parallel Claude API calls (default 3)
 *   REGISTRY_URL        worker registry (default http://localhost:5201)
 *   RELAY_URL           multicast relay (default http://localhost:5199)
 *   BRIDGE_URL          CashLanes bridge (default http://localhost:5198)
 *   WORKER_PORT         HTTP port for this worker (default 5205)
 *   NODE_IP             advertised IP (default 127.0.0.1)
 *   WORKER_ID           fixed ID (default: auto-generated)
 *
 * HTTP :5205 (or WORKER_PORT)
 *   GET /health   worker health + registry status
 *   GET /stats    request stats + latency percentiles
 *   GET /log      last 50 request/response pairs
 *   POST /ask     direct (non-mesh) API call for testing
 */

import Anthropic from '@anthropic-ai/sdk';
import { createHash } from 'node:crypto';

// ── Config ─────────────────────────────────────────────────────────────────────

const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;
if (!ANTHROPIC_API_KEY) {
  console.error('[api-worker] ANTHROPIC_API_KEY is not set. Exiting.');
  process.exit(1);
}

const RELAY_URL      = process.env.RELAY_URL      ?? 'http://localhost:5199';
const REGISTRY_URL   = process.env.REGISTRY_URL   ?? 'http://localhost:5201';
const BRIDGE_URL     = process.env.BRIDGE_URL      ?? 'http://localhost:5198';
const HTTP_PORT      = Number(process.env.WORKER_PORT ?? '5205');
const NODE_IP        = process.env.NODE_IP        ?? '127.0.0.1';
const MAX_CONCURRENT = Number(process.env.MAX_CONCURRENT ?? '3');
const MAX_TOKENS     = Number(process.env.MAX_TOKENS ?? '512');
const CLAUDE_MODEL   = process.env.CLAUDE_MODEL   ?? 'claude-haiku-4-5';

const WORKER_TYPES: string[] = (process.env.WORKER_TYPES ?? 'inference.request.classify')
  .split(',').map(s => s.trim()).filter(Boolean);

const WORKER_ID: string = process.env.WORKER_ID
  ?? createHash('sha256').update(`api-worker:${NODE_IP}:${CLAUDE_MODEL}:${Date.now()}`).digest('hex').slice(0, 16);

const SENDER_FP: string = createHash('sha256')
  .update(WORKER_ID).digest('hex').slice(0, 8);

const MODEL_LABEL = `claude@${CLAUDE_MODEL}`;

const DEFAULT_SYSTEM = `You are an AI assistant specialised in mining rehabilitation compliance and environmental monitoring in New South Wales, Australia.

You analyse sensor data, drone imagery descriptions, NDVI vegetation indices, and field inspection reports. You provide:
- Concise compliance assessments against NSW Resources Regulator rehabilitation standards
- Vegetation coverage estimates and trajectory forecasts
- Risk flags for erosion, weed invasion, or revegetation failure
- Recommended intervention actions

Respond in structured JSON when asked for classification or analysis. Keep responses focused and actionable.`;

const SYSTEM_PROMPT = process.env.SYSTEM_PROMPT ?? DEFAULT_SYSTEM;

// ── Types ──────────────────────────────────────────────────────────────────────

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
  requestId?:        string;
  prompt?:           string;
  description?:      string;
  zone?:             string;
  eventType?:        string;
  model?:            string;
  maxTokens?:        number;
  systemPrompt?:     string;
  // Pipeline / ensemble passthrough — coordinator fields
  _pipelineId?:      string;
  _pipelineStages?:  string[];
  _pipelineStageN?:  number;
  _previousResults?: unknown[];
  _ensembleId?:      string;
  _ensembleN?:       number;
  _ensembleRequired?: number;
  _dispatchedTo?:    string;
  _dispatchedBy?:    string;
}

// ── State ──────────────────────────────────────────────────────────────────────

const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

const processedIds = new Set<string>();
const MAX_DEDUP    = 500;

let activeRequests  = 0;
let cellsHandled    = 0;
let satsEarned      = 0;
let errorCount      = 0;
let relayConnected  = false;
let registryOnline  = false;
let seq             = 0;
let reconnectMs     = 1000;

const latencies: number[]  = [];
const requestLog: unknown[] = [];

// ── Registry ───────────────────────────────────────────────────────────────────

async function registerWithRegistry(): Promise<void> {
  try {
    const resp = await fetch(`${REGISTRY_URL}/workers/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        workerId:    WORKER_ID,
        nodeIp:      NODE_IP,
        typePaths:   WORKER_TYPES,
        model:       MODEL_LABEL,
        loadPct:     loadPct(),
        cellsHandled,
        satsEarned,
      }),
      signal: AbortSignal.timeout(3000),
    });
    if (resp.ok) { registryOnline = true; console.log(`[api-worker] Registered: ${WORKER_ID}`); }
  } catch (err) { registryOnline = false; console.warn(`[api-worker] Registry unavailable: ${err}`); }
}

function loadPct(): number {
  return Math.round((activeRequests / MAX_CONCURRENT) * 100);
}

setInterval(async () => {
  try {
    const resp = await fetch(`${REGISTRY_URL}/workers/heartbeat/${WORKER_ID}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ loadPct: loadPct(), cellsHandled, satsEarned }),
      signal: AbortSignal.timeout(2000),
    });
    registryOnline = resp.ok;
  } catch { registryOnline = false; }
}, 5000);

async function deregister(): Promise<void> {
  try {
    await fetch(`${REGISTRY_URL}/workers/${WORKER_ID}`, { method: 'DELETE', signal: AbortSignal.timeout(2000) });
  } catch {}
}
process.on('SIGTERM', async () => { await deregister(); process.exit(0); });
process.on('SIGINT',  async () => { await deregister(); process.exit(0); });

// ── Claude API call ────────────────────────────────────────────────────────────

async function callClaude(req: InferenceRequest): Promise<{ result: string; label: string; confidence: number }> {
  const userPrompt = req.prompt ?? req.description ?? req.eventType ?? 'No prompt provided.';
  const systemOverride = req.systemPrompt;
  const tokens = req.maxTokens ?? MAX_TOKENS;

  // If previous pipeline results exist, prepend them as context
  let fullPrompt = userPrompt;
  if (req._previousResults && req._previousResults.length > 0) {
    const ctx = req._previousResults.map((r, i) => `Stage ${i + 1}: ${JSON.stringify(r)}`).join('\n');
    fullPrompt = `Prior analysis stages:\n${ctx}\n\nCurrent task:\n${userPrompt}`;
  }

  const message = await client.messages.create({
    model:      CLAUDE_MODEL,
    max_tokens: tokens,
    system:     systemOverride ?? SYSTEM_PROMPT,
    messages: [{ role: 'user', content: fullPrompt }],
  });

  const content = message.content[0];
  if (!content || content.type !== 'text') throw new Error('Claude returned non-text content');
  const result = content.text.trim();

  // Best-effort label extraction: look for JSON label field or leading bracket
  let label = 'claude_response';
  let confidence = 0.92;
  try {
    // Look for {"label": "..."} or {"classification": "..."} in the response
    const jsonMatch = result.match(/\{[^}]*"(?:label|classification|status|result)"\s*:\s*"([^"]+)"/);
    if (jsonMatch) label = jsonMatch[1]!.toLowerCase().replace(/\s+/g, '_');
  } catch {}

  return { result, label, confidence };
}

// ── Cell publishing ────────────────────────────────────────────────────────────

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
    signal: AbortSignal.timeout(5000),
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
  } catch { return null; }
}

// ── Cell processing ────────────────────────────────────────────────────────────

async function handleCell(header: CanonicalCellHeader, payloadHex: string | null): Promise<void> {
  if (activeRequests >= MAX_CONCURRENT) return;

  const dedupKey = header.cellId;
  if (processedIds.has(dedupKey)) return;
  processedIds.add(dedupKey);
  if (processedIds.size > MAX_DEDUP) {
    const first = processedIds.values().next().value;
    if (first) processedIds.delete(first);
  }

  // Only process cells explicitly routed to this worker by the coordinator
  let req: InferenceRequest = {};
  if (payloadHex) {
    try { req = JSON.parse(Buffer.from(payloadHex, 'hex').toString('utf8')); } catch {}
  }
  if (req._dispatchedTo !== WORKER_ID) return;

  activeRequests++;
  const t0 = Date.now();

  try {
    const { result, label, confidence } = await callClaude(req);
    const latencyMs = Date.now() - t0;
    latencies.push(latencyMs);
    if (latencies.length > 200) latencies.shift();

    const requestId = req.requestId ?? header.cellId.slice(0, 16);
    const txid      = await advanceCashLanes(requestId);

    // Pass pipeline / ensemble fields through unchanged
    const chainMeta: Record<string, unknown> = {};
    if (req._pipelineId)      chainMeta._pipelineId     = req._pipelineId;
    if (req._pipelineStages)  chainMeta._pipelineStages = req._pipelineStages;
    if (req._pipelineStageN !== undefined) chainMeta._pipelineStageN = req._pipelineStageN;
    if (req._previousResults) chainMeta._previousResults = req._previousResults;
    if (req._ensembleId)      chainMeta._ensembleId     = req._ensembleId;
    if (req._ensembleN !== undefined)        chainMeta._ensembleN       = req._ensembleN;
    if (req._ensembleRequired !== undefined) chainMeta._ensembleRequired = req._ensembleRequired;

    await publishCell('inference.result.response', {
      requestId,
      result,
      label,
      confidence,
      model:           MODEL_LABEL,
      latencyMs,
      workerId:        WORKER_ID,
      nodeIp:          NODE_IP,
      workerTypePaths: WORKER_TYPES,
      bsvTxid:         txid,
      certTier:        req.model ?? 'auto',
      dataClass:       'inference',
      policyHex:       '7c760101a2697ca2',
      ...chainMeta,
    });

    cellsHandled++;
    const entry = {
      ts: Date.now(), requestId, typePath: header.typePath, workerId: WORKER_ID,
      ok: true, label, latencyMs, result: result.slice(0, 400),
    };
    requestLog.push(entry);
    if (requestLog.length > 50) requestLog.shift();

    console.log(`[api-worker:${WORKER_ID.slice(0, 8)}] ${header.typePath} → ${label} (${latencyMs}ms)${txid ? ' ✓ BSV' : ''}`);

  } catch (err) {
    errorCount++;
    console.error(`[api-worker] Error handling ${header.cellId}: ${err}`);
    const requestId = header.cellId.slice(0, 16);
    await publishCell('inference.result.error', { requestId, error: String(err), workerId: WORKER_ID }).catch(() => {});
  } finally {
    activeRequests--;
  }
}

// ── Relay SSE ─────────────────────────────────────────────────────────────────

function matchesFilter(typePath: string, filter: string): boolean {
  if (filter.endsWith('.*')) return typePath.startsWith(filter.slice(0, -1));
  if (filter.endsWith('*'))  return typePath.startsWith(filter.slice(0, -1));
  return typePath === filter;
}

async function subscribeRelay(): Promise<void> {
  const filterPath = WORKER_TYPES.length === 1 ? WORKER_TYPES[0] : 'inference.*';
  const url = `${RELAY_URL}/cells/stream?typePath=${encodeURIComponent(filterPath)}`;
  console.log(`[api-worker] Connecting to relay: ${url}`);

  try {
    const resp = await fetch(url, { headers: { Accept: 'text/event-stream' } });
    if (!resp.ok || !resp.body) throw new Error(`relay SSE ${resp.status}`);

    relayConnected = true;
    reconnectMs    = 1000;
    console.log(`[api-worker:${WORKER_ID.slice(0, 8)}] ✓ Relay connected | model: ${MODEL_LABEL}`);

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
              if (!WORKER_TYPES.some(f => matchesFilter(h.typePath, f))) { dataLine = ''; eventType = ''; continue; }
              const isRequest = h.typePath.includes('.request.') || h.typePath.startsWith('inference.request');
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
    console.warn(`[api-worker] Relay SSE error: ${err}. Reconnecting in ${reconnectMs}ms…`);
  }

  setTimeout(() => subscribeRelay(), reconnectMs);
  reconnectMs = Math.min(reconnectMs * 2, 30_000);
}

// ── Percentiles ────────────────────────────────────────────────────────────────

function percentile(arr: number[], p: number): number {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length * p / 100)] ?? 0;
}

// ── HTTP server ────────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

Bun.serve({
  port: HTTP_PORT,
  async fetch(req) {
    const url  = new URL(req.url);
    const path = url.pathname;
    if (req.method === 'OPTIONS') return new Response(null, { headers: { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST', 'Access-Control-Allow-Headers': 'Content-Type' } });

    if (path === '/health') return json({
      service: 'api-worker', workerId: WORKER_ID, port: HTTP_PORT,
      nodeIp: NODE_IP, model: MODEL_LABEL, workerTypes: WORKER_TYPES,
      activeRequests, maxConcurrent: MAX_CONCURRENT, loadPct: loadPct(),
      cellsHandled, satsEarned, errorCount, relayConnected, registryOnline,
      claudeModel: CLAUDE_MODEL, maxTokens: MAX_TOKENS,
    });

    if (path === '/stats') return json({
      cellsHandled, errorCount, satsEarned,
      p50Ms: percentile(latencies, 50), p99Ms: percentile(latencies, 99),
      loadPct: loadPct(), activeRequests, maxConcurrent: MAX_CONCURRENT,
    });

    if (path === '/log') return json(requestLog.slice(-50).reverse());

    // POST /ask — direct API call for testing (bypass mesh routing)
    if (path === '/ask' && req.method === 'POST') {
      try {
        const body: any = await req.json();
        const prompt = body.prompt ?? body.description ?? 'Tell me about mining rehabilitation.';
        const { result, label, confidence } = await callClaude({ prompt });
        return json({ result, label, confidence, model: MODEL_LABEL });
      } catch (err) {
        return json({ error: String(err) }, 500);
      }
    }

    return json({ error: 'not found' }, 404);
  },
});

// ── Boot ───────────────────────────────────────────────────────────────────────

console.log(`
╔══════════════════════════════════════════════════════════╗
║   api-worker  :${HTTP_PORT}                                  ║
║   Claude API Inference Worker                           ║
╠══════════════════════════════════════════════════════════╣
║   Worker ID: ${WORKER_ID}          ║
║   Model:     ${CLAUDE_MODEL.slice(0, 46).padEnd(46)} ║
║   Types:     ${WORKER_TYPES.join(',').slice(0, 46).padEnd(46)} ║
║   Capacity:  ${MAX_CONCURRENT} concurrent    Max tokens: ${String(MAX_TOKENS).padEnd(16)} ║
╠══════════════════════════════════════════════════════════╣
║   Registry:  ${REGISTRY_URL.padEnd(46)} ║
║   Relay:     ${RELAY_URL.padEnd(46)} ║
╚══════════════════════════════════════════════════════════╝
`);

await registerWithRegistry();
subscribeRelay();

```
