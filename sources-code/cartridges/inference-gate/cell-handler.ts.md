---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/cell-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.409245+00:00
---

# cartridges/inference-gate/cell-handler.ts

```ts
#!/usr/bin/env bun
/**
 * cell-handler.ts — Inference Gate cell handler
 *
 * Subscribes to the multicast relay's SSE stream, picks up cells whose
 * typePath starts with "inference.request.*", runs inference (mock by
 * default, real model optional), and publishes result cells back to the
 * relay so any subscriber — including the inference-gate dashboard — can
 * see the completed round-trip.
 *
 * MODES
 * ─────
 *   Default (mock):   keyword classifier — no model required, immediate response
 *   WHISPER_URL set:  proxy audio payload to whisper.cpp REST (:8080)
 *   OLLAMA_URL set:   proxy text payload to Ollama (/api/generate)
 *
 * USAGE
 * ─────
 *   bun cartridges/inference-gate/cell-handler.ts
 *   RELAY_URL=http://192.168.0.10:5199 bun cell-handler.ts   # remote relay
 *   WHISPER_URL=http://localhost:8080  bun cell-handler.ts   # real ASR
 *   OLLAMA_URL=http://localhost:11434  bun cell-handler.ts   # real LLM
 *
 * HTTP :5196
 *   GET /health   { ok, requestsHandled, uptime, relayConnected, model }
 *   GET /stats    { requestsTotal, requestsPerMin, p50Ms, p99Ms, errorCount }
 *   GET /log      last 50 request/response pairs (JSON array)
 */

import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL    = process.env.RELAY_URL    ?? 'http://localhost:5199';
const WHISPER_URL  = process.env.WHISPER_URL  ?? '';   // e.g. http://localhost:8080
const OLLAMA_URL   = process.env.OLLAMA_URL   ?? '';   // e.g. http://localhost:11434
const OLLAMA_MODEL = process.env.OLLAMA_MODEL ?? 'phi3';
const HTTP_PORT    = parseInt(process.env.CELL_HANDLER_PORT ?? '5196', 10);
const HANDLER_NAME = process.env.HANDLER_NAME ?? 'inference-gate-handler';

// Stable 8-hex fingerprint for this handler instance
const HANDLER_FP: string = createHash('sha256')
  .update(HANDLER_NAME)
  .digest('hex').slice(0, 8);

// Model identity string shown in health/stats
const MODEL_LABEL = WHISPER_URL
  ? `whisper.cpp@${WHISPER_URL}`
  : OLLAMA_URL
  ? `${OLLAMA_MODEL}@ollama`
  : 'mock-classifier';

// ── Types ─────────────────────────────────────────────────────────────────────

interface CanonicalCellHeader {
  cellId:     string;
  typeHash?:  string;
  typePath:   string;
  senderFp:   string;
  seq:        number;
  payloadLen: number;
  ts:         number;
}

interface InferenceRequest {
  requestId?: string;    // optional correlation id
  prompt?:    string;    // text prompt (for LLM/classifier)
  audio?:     string;    // base64 audio data (for whisper)
  model?:     string;    // hint: "auto" | "whisper" | "llm" | "classify"
  maxTokens?: number;
}

interface InferenceResult {
  requestId:  string;
  result:     string;
  label?:     string;    // classification label
  confidence?: number;   // 0-1
  model:      string;
  latencyMs:  number;
  error?:     string;
}

interface LogEntry {
  ts:         number;
  requestId:  string;
  cellId:     string;
  typePath:   string;
  model:      string;
  latencyMs:  number;
  resultSnip: string;    // first 80 chars of result
  ok:         boolean;
}

// ── State ─────────────────────────────────────────────────────────────────────

let sseConnected    = false;
let requestsTotal   = 0;
let errorCount      = 0;
let seqOut          = 0;
const startTs       = Date.now();
const latencies:  number[] = [];   // sliding window, max 1000
const requestLog: LogEntry[] = []; // ring buffer max 50

function recordLatency(ms: number) {
  latencies.push(ms);
  if (latencies.length > 1000) latencies.splice(0, latencies.length - 1000);
}

function percentile(arr: number[], p: number): number {
  if (arr.length === 0) return 0;
  const s = [...arr].sort((a, b) => a - b);
  return s[Math.floor(s.length * p / 100)] ?? 0;
}

function cellsPerMin(): number {
  const cutoff = Date.now() - 60_000;
  return requestLog.filter(e => e.ts > cutoff).length;
}

// ── Mock classifier ───────────────────────────────────────────────────────────
// Simple keyword classifier — runs synchronously with no dependencies.
// Replace the body of mockInfer() to plug in any local model.

const SAFETY_KEYWORDS   = ['fire', 'fall', 'unsafe', 'hazard', 'helmet', 'hard hat', 'hardhat', 'ppe',
                           'protective', 'danger', 'injury', 'emergency', 'missing ppe', 'no ppe',
                           'without ppe', 'smoke', 'evacuation', 'alarm'];
const MOTION_KEYWORDS   = ['movement', 'enter', 'exit', 'detected', 'person', 'vehicle', 'count',
                           'entered', 'restricted area', 'access', 'motion'];
const ANOMALY_KEYWORDS  = ['temperature', 'pressure', 'vibration', 'spike', 'threshold', 'exceeded',
                           'alert', 'sensor', 'abnormal', 'fault', 'failure', 'drop', 'surge'];
const COMMAND_KEYWORDS  = ['on', 'off', 'start', 'stop', 'enable', 'disable', 'open', 'close',
                           'lock', 'unlock', 'activate', 'deactivate', 'clearance'];

function mockInfer(req: InferenceRequest): { result: string; label: string; confidence: number } {
  const text = (req.prompt ?? '').toLowerCase();

  if (!text) {
    return { result: 'no prompt provided', label: 'empty', confidence: 1.0 };
  }

  // Score each category
  const scores: Record<string, number> = {
    safety:  SAFETY_KEYWORDS.filter(k  => text.includes(k)).length,
    motion:  MOTION_KEYWORDS.filter(k  => text.includes(k)).length,
    anomaly: ANOMALY_KEYWORDS.filter(k => text.includes(k)).length,
    command: COMMAND_KEYWORDS.filter(k => text.includes(k)).length,
  };

  const best = Object.entries(scores).sort((a, b) => b[1] - a[1])[0]!;

  if (best[1] === 0) {
    // No keywords matched — fall back to length heuristic
    const wordCount = text.split(/\s+/).length;
    const label = wordCount > 20 ? 'narrative' : 'unknown';
    return {
      result: `Classified as ${label} (no keyword match, ${wordCount} words)`,
      label,
      confidence: 0.35,
    };
  }

  const total   = Object.values(scores).reduce((s, v) => s + v, 0);
  const conf    = Math.min(0.55 + best[1] * 0.1, 0.97);
  const confPct = (conf * 100).toFixed(0);

  const resultMap: Record<string, string> = {
    safety:  `⚠️  Safety event detected (${best[1]} indicator${best[1] > 1 ? 's' : ''}) — ${confPct}% confidence`,
    motion:  `🚶 Motion/presence event (${best[1]} indicator${best[1] > 1 ? 's' : ''}) — ${confPct}% confidence`,
    anomaly: `📈 Sensor anomaly (${best[1]} indicator${best[1] > 1 ? 's' : ''}) — ${confPct}% confidence`,
    command: `🎛  Command intent (${best[1]} keyword${best[1] > 1 ? 's' : ''}) — ${confPct}% confidence`,
  };

  return {
    result:     resultMap[best[0]] ?? 'classified',
    label:      best[0],
    confidence: conf,
  };
}

// ── Whisper.cpp proxy ─────────────────────────────────────────────────────────
// Forwards base64-encoded audio to a local whisper.cpp server.
// whisper.cpp REST API (llama.cpp compatible): POST /inference { file: base64 }

async function whisperInfer(req: InferenceRequest): Promise<{ result: string; label: string; confidence: number }> {
  if (!req.audio) throw new Error('whisper mode requires audio field (base64)');
  const r = await fetch(`${WHISPER_URL}/inference`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ file: req.audio }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!r.ok) throw new Error(`whisper.cpp HTTP ${r.status}`);
  const body = await r.json() as { text?: string };
  return {
    result:     body.text ?? '',
    label:      'transcription',
    confidence: 0.9,
  };
}

// ── Ollama proxy ──────────────────────────────────────────────────────────────

async function ollamaInfer(req: InferenceRequest): Promise<{ result: string; label: string; confidence: number }> {
  if (!req.prompt) throw new Error('ollama mode requires prompt field');
  const r = await fetch(`${OLLAMA_URL}/api/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model:  OLLAMA_MODEL,
      prompt: req.prompt,
      stream: false,
      options: { num_predict: req.maxTokens ?? 200 },
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!r.ok) throw new Error(`Ollama HTTP ${r.status}`);
  const body = await r.json() as { response?: string };
  return {
    result:     body.response ?? '',
    label:      'generation',
    confidence: 0.85,
  };
}

// ── Core inference dispatcher ─────────────────────────────────────────────────

async function runInference(req: InferenceRequest): Promise<{ result: string; label: string; confidence: number }> {
  const hint = (req.model ?? 'auto').toLowerCase();

  // Explicit model hints
  if (hint === 'whisper' && WHISPER_URL) return whisperInfer(req);
  if (hint === 'llm' && OLLAMA_URL)      return ollamaInfer(req);

  // Auto-select: whisper if audio present, ollama if llm available, else mock
  if (req.audio && WHISPER_URL)          return whisperInfer(req);
  if (req.prompt && OLLAMA_URL)          return ollamaInfer(req);

  // Always-available mock
  return mockInfer(req);
}

// ── Publish result cell ───────────────────────────────────────────────────────

async function publishResultCell(reqCellId: string, res: InferenceResult) {
  const payloadStr = JSON.stringify(res);
  const payloadHex = Buffer.from(payloadStr, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seqOut++;

  const body = {
    header: {
      cellId,
      typePath:   'inference.result.response',
      senderFp:   HANDLER_FP,
      seq:        seqOut,
      payloadLen: payloadStr.length,
    } satisfies Omit<CanonicalCellHeader, 'ts' | 'typeHash'>,
    payload: payloadHex,
  };

  try {
    const r = await fetch(`${RELAY_URL}/publish`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000),
    });
    if (!r.ok) {
      console.warn(`[handler] relay publish failed HTTP ${r.status} for requestId=${res.requestId}`);
    }
  } catch (e: any) {
    console.warn(`[handler] relay publish error: ${e.message}`);
  }
}

// ── Handle one inference request cell ────────────────────────────────────────

async function handleCell(header: CanonicalCellHeader, payload: string | null) {
  const t0 = Date.now();
  requestsTotal++;

  // Decode payload
  let req: InferenceRequest = {};
  if (payload) {
    try {
      const raw = Buffer.from(payload, 'hex').toString('utf8');
      req = JSON.parse(raw) as InferenceRequest;
    } catch {
      // Payload isn't JSON — treat as raw prompt string
      try {
        req = { prompt: Buffer.from(payload, 'hex').toString('utf8') };
      } catch {
        req = { prompt: '' };
      }
    }
  }

  const requestId = req.requestId ?? header.cellId.slice(0, 16);
  console.log(`[handler] ← ${header.typePath} cellId=${header.cellId.slice(0, 12)}… requestId=${requestId} model=${MODEL_LABEL}`);

  let result: InferenceResult;
  try {
    const { result: text, label, confidence } = await runInference(req);
    const latencyMs = Date.now() - t0;
    recordLatency(latencyMs);
    result = { requestId, result: text, label, confidence, model: MODEL_LABEL, latencyMs };
    console.log(`[handler] → result: "${text.slice(0, 60)}${text.length > 60 ? '…' : ''}"  (${latencyMs}ms)`);
  } catch (e: any) {
    errorCount++;
    const latencyMs = Date.now() - t0;
    result = { requestId, result: '', model: MODEL_LABEL, latencyMs, error: e.message };
    console.warn(`[handler] inference error: ${e.message}`);
  }

  requestLog.unshift({
    ts:         Date.now(),
    requestId,
    cellId:     header.cellId,
    typePath:   header.typePath,
    model:      MODEL_LABEL,
    latencyMs:  result.latencyMs,
    resultSnip: result.result.slice(0, 80),
    ok:         !result.error,
  });
  if (requestLog.length > 50) requestLog.length = 50;

  await publishResultCell(header.cellId, result);
}

// ── SSE subscription to relay ─────────────────────────────────────────────────

function isInferenceRequest(typePath: string): boolean {
  return typePath.startsWith('inference.request.');
}

async function connectRelaySSE(): Promise<void> {
  const url = `${RELAY_URL}/cells/stream`;
  try {
    const connCtrl    = new AbortController();
    const connTimeout = setTimeout(() => connCtrl.abort(), 8000);
    let r: Response;
    try {
      r = await fetch(url, { headers: { Accept: 'text/event-stream' }, signal: connCtrl.signal });
    } finally {
      clearTimeout(connTimeout);
    }
    if (!r.ok || !r.body) throw new Error(`HTTP ${r.status}`);

    sseConnected = true;
    console.log(`[handler] SSE connected to relay ${url} — listening for inference.request.*`);

    const reader = r.body.getReader();
    const dec    = new TextDecoder();
    let buf = '';
    let eventType  = 'message';
    let dataLines: string[] = [];

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const parts = buf.split('\n');
      buf = parts.pop()!;

      for (const line of parts) {
        if (line.startsWith('event: ')) {
          eventType = line.slice(7).trim();
        } else if (line.startsWith('data: ')) {
          dataLines.push(line.slice(6));
        } else if (line === '' && dataLines.length > 0) {
          if (eventType === 'cell') {
            try {
              const { header, payload } = JSON.parse(dataLines.join('\n')) as
                { header: CanonicalCellHeader; payload: string | null };
              if (header?.cellId && isInferenceRequest(header.typePath)) {
                // Don't await — handle concurrently, don't block SSE reader
                handleCell(header, payload ?? null).catch(e =>
                  console.warn(`[handler] handleCell error: ${e.message}`)
                );
              }
            } catch { /* malformed event */ }
          }
          eventType = 'message';
          dataLines = [];
        }
      }
    }
  } catch (e: any) {
    if (sseConnected) {
      console.warn(`[handler] SSE disconnected: ${e.message} — retrying in 5s`);
    }
    sseConnected = false;
  }
  setTimeout(connectRelaySSE, 5000);
}

// ── HTTP server ───────────────────────────────────────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Bun.serve({
  port: HTTP_PORT,
  fetch(req) {
    const url      = new URL(req.url);
    const path     = url.pathname;
    const method   = req.method.toUpperCase();

    if (method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    if (method === 'GET' && path === '/health') {
      return Response.json({
        ok:              true,
        uptime:          Math.floor((Date.now() - startTs) / 1000),
        relayConnected:  sseConnected,
        requestsHandled: requestsTotal,
        errorCount,
        model:           MODEL_LABEL,
        handlerFp:       HANDLER_FP,
        relayUrl:        RELAY_URL,
      }, { headers: CORS });
    }

    if (method === 'GET' && path === '/stats') {
      return Response.json({
        requestsTotal,
        requestsPerMin:  cellsPerMin(),
        errorCount,
        p50Ms:           percentile(latencies, 50),
        p99Ms:           percentile(latencies, 99),
        model:           MODEL_LABEL,
        relayConnected:  sseConnected,
      }, { headers: CORS });
    }

    if (method === 'GET' && path === '/log') {
      return Response.json(requestLog, { headers: CORS });
    }

    return new Response('Not found', { status: 404, headers: CORS });
  },
});

// ── Start ─────────────────────────────────────────────────────────────────────

console.log(`[handler] Inference Gate cell handler`);
console.log(`[handler] HTTP :${HTTP_PORT}  relay=${RELAY_URL}`);
console.log(`[handler] model=${MODEL_LABEL}  fp=${HANDLER_FP}`);
console.log(`[handler] Listens for: inference.request.*  Publishes: inference.result.response`);
connectRelaySSE();

```
