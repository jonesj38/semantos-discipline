---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/infer-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.410957+00:00
---

# cartridges/inference-gate/infer-client.ts

```ts
#!/usr/bin/env bun
/**
 * infer-client.ts — Inference Gate demo client
 *
 * Sends a cell with typePath="inference.request.classify" to the relay,
 * then polls /cells/recent for the matching "inference.result.response"
 * cell and prints the round-trip result.
 *
 * This proves the full inference cell loop:
 *   client → relay → cell-handler → relay → client
 *
 * USAGE
 * ─────
 *   bun cartridges/inference-gate/infer-client.ts "hard hat detected near zone 3"
 *   bun infer-client.ts --model whisper --audio /path/to/clip.wav
 *   RELAY_URL=http://192.168.0.10:5199 bun infer-client.ts "temperature spike 47C"
 *   bun infer-client.ts --loop 10          # send 10 random prompts, 1/sec
 */

import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';

const RELAY_URL   = process.env.RELAY_URL ?? 'http://localhost:5199';
const CLIENT_FP   = createHash('sha256').update('infer-client').digest('hex').slice(0, 8);
const TIMEOUT_MS  = parseInt(process.env.TIMEOUT_MS ?? '15000', 10);

// ── CLI ───────────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
let loopCount   = 0;
let model       = 'auto';
let audioFile   = '';
let promptText  = '';

for (let i = 0; i < argv.length; i++) {
  const a = argv[i]!;
  if (a === '--loop')  { loopCount  = parseInt(argv[++i] ?? '5', 10); }
  else if (a === '--model') { model = argv[++i] ?? 'auto'; }
  else if (a === '--audio') { audioFile = argv[++i] ?? ''; }
  else if (!a.startsWith('--')) { promptText = a; }
}

// ── Random prompts for --loop mode ───────────────────────────────────────────

const RANDOM_PROMPTS = [
  'Hard hat missing in zone 3 near the scaffolding — worker without PPE detected',
  'Temperature sensor exceeded threshold: 47°C spike on motor housing unit B',
  'Person entered restricted area — motion detected near compressor zone',
  'Fire detected near panel room — smoke sensor triggered emergency alert',
  'Unlock the main gate — forklift operator requesting access clearance',
  'Pressure drop alert: hydraulic system reading 2.3 bar below normal range',
  'Fall detected near loading bay — emergency alert triggered zone 4',
  'Vehicle count update: 3 trucks entered, 1 exited delivery dock since last sync',
];

function randomPrompt(): string {
  return RANDOM_PROMPTS[Math.floor(Math.random() * RANDOM_PROMPTS.length)]!;
}

// ── Send inference request cell ───────────────────────────────────────────────

let seq = 0;

async function sendInferenceRequest(prompt: string, opts: { model?: string; audio?: string } = {}): Promise<string> {
  const requestId = randomBytes(8).toString('hex');
  const reqPayload: Record<string, string> = { requestId, prompt, model: opts.model ?? 'auto' };
  if (opts.audio) reqPayload['audio'] = opts.audio;

  const payloadStr = JSON.stringify(reqPayload);
  const payloadHex = Buffer.from(payloadStr, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  const body = {
    header: {
      cellId,
      typePath:   'inference.request.classify',
      senderFp:   CLIENT_FP,
      seq,
      payloadLen: payloadStr.length,
    },
    payload: payloadHex,
  };

  const r = await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(5000),
  });

  if (!r.ok) {
    const text = await r.text().catch(() => '');
    throw new Error(`relay publish failed HTTP ${r.status}: ${text}`);
  }

  return requestId;
}

// ── Poll for result cell ──────────────────────────────────────────────────────

interface RecentCell {
  header: {
    cellId:    string;
    typePath:  string;
    senderFp:  string;
    seq:       number;
    payloadLen: number;
    ts:        number;
  };
  payload: string | null;
}

interface InferenceResult {
  requestId:   string;
  result:      string;
  label?:      string;
  confidence?: number;
  model:       string;
  latencyMs:   number;
  error?:      string;
}

async function pollForResult(requestId: string, deadline: number): Promise<InferenceResult | null> {
  while (Date.now() < deadline) {
    const r = await fetch(`${RELAY_URL}/cells/recent`, { signal: AbortSignal.timeout(3000) });
    if (!r.ok) { await Bun.sleep(500); continue; }

    const { cells } = await r.json() as { cells: RecentCell[] };
    for (const cell of cells) {
      if (cell.header.typePath !== 'inference.result.response') continue;
      if (!cell.payload) continue;
      try {
        const res = JSON.parse(Buffer.from(cell.payload, 'hex').toString('utf8')) as InferenceResult;
        if (res.requestId === requestId) return res;
      } catch { /* malformed — skip */ }
    }

    await Bun.sleep(300);
  }
  return null;
}

// ── Single inference round-trip ───────────────────────────────────────────────

async function infer(prompt: string, opts: { model?: string; audio?: string } = {}): Promise<void> {
  const t0       = Date.now();
  const display  = prompt.length > 70 ? prompt.slice(0, 70) + '…' : prompt;
  process.stdout.write(`→ ${display}\n`);

  let requestId: string;
  try {
    requestId = await sendInferenceRequest(prompt, opts);
  } catch (e: any) {
    console.error(`  ✗ Send failed: ${e.message}`);
    return;
  }

  process.stdout.write(`  ✉  requestId=${requestId}  waiting for result…`);
  const deadline = t0 + TIMEOUT_MS;
  const res      = await pollForResult(requestId, deadline);

  if (!res) {
    console.log(`\n  ✗ Timeout after ${TIMEOUT_MS}ms — is cell-handler.ts running?`);
    return;
  }

  const rtt = Date.now() - t0;
  console.log('\n');
  console.log(`  ✓ Result     : ${res.result}`);
  if (res.label)      console.log(`  ✓ Label      : ${res.label}  (confidence ${((res.confidence ?? 0) * 100).toFixed(0)}%)`);
  if (res.error)      console.log(`  ✗ Error      : ${res.error}`);
  console.log(`  ✓ Model      : ${res.model}`);
  console.log(`  ✓ Infer time : ${res.latencyMs}ms`);
  console.log(`  ✓ Round-trip : ${rtt}ms (including relay pub/poll)`);
  console.log('');
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n  Inference Gate client  relay=${RELAY_URL}`);
  console.log(`  clientFp=${CLIENT_FP}  timeout=${TIMEOUT_MS}ms`);
  console.log(`  model=${model}\n`);

  // --loop N mode
  if (loopCount > 0) {
    console.log(`  Sending ${loopCount} random inference requests at 1/sec…\n`);
    for (let i = 0; i < loopCount; i++) {
      await infer(randomPrompt(), { model });
      if (i < loopCount - 1) await Bun.sleep(1000);
    }
    return;
  }

  // --audio mode
  if (audioFile) {
    const audio = readFileSync(audioFile).toString('base64');
    await infer(`[audio: ${audioFile}]`, { model: 'whisper', audio });
    return;
  }

  // Single prompt
  const prompt = promptText || randomPrompt();
  await infer(prompt, { model });
}

main().catch(e => { console.error(e); process.exit(1); });

```
