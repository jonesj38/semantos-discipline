---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/mic-to-cell.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.407212+00:00
---

# cartridges/inference-gate/mic-to-cell.ts

```ts
#!/usr/bin/env bun
/**
 * mic-to-cell.ts — Microphone capture → whisper.cpp → inference cell
 *
 * Designed to run on an Orange Pi Prime (H5) or any Armbian/Linux node
 * with a USB microphone and a local whisper.cpp server on :8080.
 *
 * The capture loop:
 *   1. Record N seconds of audio via `arecord` (ALSA) → /tmp/mic-clip.wav
 *   2. POST audio to whisper.cpp REST server → transcription text
 *   3. Publish text as inference.request.classify cell to the relay
 *   4. Optionally wait for inference.result.response and log the result
 *
 * This is the "device side" of the construction site demo:
 *   mic → transcription → cell → relay → cell-handler → classification → dashboard
 *
 * USAGE
 * ─────
 *   bun mic-to-cell.ts                                    # default: 3s clips, continuous
 *   bun mic-to-cell.ts --duration 5                       # 5-second clips
 *   bun mic-to-cell.ts --once                             # single capture then exit
 *   bun mic-to-cell.ts --device plughw:1,0               # specific ALSA device
 *   RELAY_URL=http://192.168.0.50:5199 bun mic-to-cell.ts
 *   WHISPER_URL=http://localhost:8080 bun mic-to-cell.ts  # explicit whisper endpoint
 *
 * DEPENDENCIES (on the Pi)
 * ─────────────────────────
 *   sudo apt-get install -y alsa-utils          # provides arecord
 *   whisper.cpp server on :8080                 # from deploy-model-to-pis.sh
 *
 * LIST AUDIO DEVICES (on Pi)
 *   arecord -l                                  # find your USB mic device
 *   arecord --device=plughw:1,0 -d 1 /dev/null # quick test
 */

import { createHash, randomBytes } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { unlink, stat } from 'node:fs/promises';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL    = process.env.RELAY_URL    ?? 'http://localhost:5199';
const WHISPER_URL  = process.env.WHISPER_URL  ?? 'http://localhost:8080';
const CLIENT_FP    = createHash('sha256').update('mic-to-cell').digest('hex').slice(0, 8);

const argv        = process.argv.slice(2);
const flag        = (f: string) => { const i = argv.indexOf(f); return i !== -1 ? argv[i + 1] : undefined; };
const hasFlag     = (f: string) => argv.includes(f);

const DURATION    = parseInt(flag('--duration') ?? '3', 10);   // seconds per clip
const ALSA_DEVICE = flag('--device') ?? process.env.ALSA_DEVICE ?? 'default';
const ONCE        = hasFlag('--once');
const WAIT_RESULT = !hasFlag('--no-wait');                       // wait for result cell
const RESULT_MS   = 10_000;                                      // max ms to wait for result

// ── Helpers ───────────────────────────────────────────────────────────────────

let seq = 0;

function log(msg: string) {
  const ts = new Date().toLocaleTimeString();
  console.log(`[${ts}] ${msg}`);
}

async function fileExists(path: string): Promise<boolean> {
  try { await stat(path); return true; } catch { return false; }
}

// ── Step 1: Record audio via arecord ─────────────────────────────────────────
// 16kHz mono 16-bit signed — optimal format for whisper.cpp

async function recordClip(wavPath: string): Promise<void> {
  log(`🎙  Recording ${DURATION}s @ 16kHz mono — device=${ALSA_DEVICE}`);
  const proc = Bun.spawn([
    'arecord',
    '--device', ALSA_DEVICE,
    '--channels', '1',
    '--rate',     '16000',
    '--format',   'S16_LE',
    '--duration',  String(DURATION),
    wavPath,
  ], { stderr: 'pipe' });

  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    const errText = await new Response(proc.stderr).text();
    throw new Error(`arecord failed (exit ${exitCode}): ${errText.slice(0, 200)}`);
  }

  const { size } = await stat(wavPath);
  log(`   Recorded ${(size / 1024).toFixed(1)} KB WAV`);
}

// ── Step 2: Transcribe via whisper.cpp REST ────────────────────────────────

async function transcribe(wavPath: string): Promise<string> {
  log(`📝 Transcribing via whisper.cpp at ${WHISPER_URL}…`);
  const t0 = Date.now();

  // whisper.cpp REST API: multipart/form-data with 'file' field
  const wavData = await Bun.file(wavPath).arrayBuffer();
  const formData = new FormData();
  formData.append('file', new Blob([wavData], { type: 'audio/wav' }), 'audio.wav');
  // Optional: request JSON response format
  formData.append('response_format', 'json');

  const r = await fetch(`${WHISPER_URL}/inference`, {
    method: 'POST',
    body: formData,
    signal: AbortSignal.timeout(30_000),
  });

  if (!r.ok) {
    const body = await r.text().catch(() => '');
    throw new Error(`whisper.cpp HTTP ${r.status}: ${body.slice(0, 100)}`);
  }

  const contentType = r.headers.get('content-type') ?? '';
  let text: string;

  if (contentType.includes('application/json')) {
    const json = await r.json() as { text?: string; results?: Array<{ text: string }> };
    text = json.text ?? json.results?.[0]?.text ?? '';
  } else {
    // Some versions return plain text
    text = await r.text();
  }

  text = text.trim();
  const ms = Date.now() - t0;
  log(`   Transcription (${ms}ms): "${text}"`);
  return text;
}

// ── Step 3: Publish as inference.request.classify cell ───────────────────────

async function publishCell(text: string): Promise<string> {
  const requestId = randomBytes(8).toString('hex');
  const payload   = JSON.stringify({
    requestId,
    prompt:  text,
    model:   'auto',
    source:  'whisper-mic',
    captureS: DURATION,
    device:  ALSA_DEVICE,
  });
  const payloadHex = Buffer.from(payload, 'utf8').toString('hex');
  const cellId     = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  const body = {
    header: {
      cellId,
      typePath:   'inference.request.classify',
      senderFp:   CLIENT_FP,
      seq,
      payloadLen: payload.length,
    },
    payload: payloadHex,
  };

  const r = await fetch(`${RELAY_URL}/publish`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
    signal:  AbortSignal.timeout(5000),
  });

  if (!r.ok) throw new Error(`relay publish HTTP ${r.status}`);
  log(`📡 Cell published: requestId=${requestId}  cellId=${cellId.slice(0, 12)}…`);
  return requestId;
}

// ── Step 4: Wait for result cell ──────────────────────────────────────────────

interface RecentCell {
  header: { cellId: string; typePath: string; ts: number; payloadLen: number };
  payload: string | null;
}

async function waitForResult(requestId: string): Promise<void> {
  const deadline = Date.now() + RESULT_MS;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${RELAY_URL}/cells/recent`, { signal: AbortSignal.timeout(2000) });
      if (r.ok) {
        const { cells } = await r.json() as { cells: RecentCell[] };
        for (const cell of cells) {
          if (cell.header.typePath !== 'inference.result.response' || !cell.payload) continue;
          try {
            const res = JSON.parse(Buffer.from(cell.payload, 'hex').toString('utf8')) as {
              requestId?: string; result?: string; label?: string; confidence?: number; latencyMs?: number;
            };
            if (res.requestId !== requestId) continue;
            log(`✅ Result: "${res.result}"`);
            if (res.label) log(`   Label: ${res.label}  confidence: ${((res.confidence ?? 0) * 100).toFixed(0)}%`);
            if (res.latencyMs) log(`   Infer: ${res.latencyMs}ms`);
            return;
          } catch { /* skip malformed */ }
        }
      }
    } catch { /* relay unreachable — keep polling */ }
    await Bun.sleep(400);
  }
  log(`⚠️  No result received within ${RESULT_MS}ms — is cell-handler.ts running?`);
}

// ── Main loop ─────────────────────────────────────────────────────────────────

async function checkWhisper(): Promise<boolean> {
  try {
    const r = await fetch(`${WHISPER_URL}/health`, { signal: AbortSignal.timeout(2000) });
    return r.ok;
  } catch {
    return false;
  }
}

async function runOnce(): Promise<void> {
  const wavPath = join(tmpdir(), `mic-clip-${Date.now()}.wav`);
  try {
    await recordClip(wavPath);
    const text = await transcribe(wavPath);
    if (!text) { log('⚠️  Empty transcription — skipping cell publish'); return; }
    const requestId = await publishCell(text);
    if (WAIT_RESULT) await waitForResult(requestId);
  } finally {
    if (await fileExists(wavPath)) await unlink(wavPath).catch(() => {});
  }
}

async function main() {
  console.log('\n  Inference Gate mic-to-cell');
  console.log(`  relay=${RELAY_URL}  whisper=${WHISPER_URL}`);
  console.log(`  device=${ALSA_DEVICE}  duration=${DURATION}s  clientFp=${CLIENT_FP}\n`);

  // Check whisper is reachable
  if (!(await checkWhisper())) {
    console.warn(`  ⚠️  whisper.cpp not responding at ${WHISPER_URL}`);
    console.warn('      Is deploy-model-to-pis.sh complete? Is the build done?');
    console.warn('      Monitor build: tail -f /tmp/whisper-build.log\n');
    if (ONCE) process.exit(1);
    console.warn('      Waiting 30s and retrying…');
    await Bun.sleep(30_000);
    if (!(await checkWhisper())) {
      console.error('  ✗ whisper.cpp still offline — exiting');
      process.exit(1);
    }
  }

  log('whisper.cpp reachable — starting capture loop');

  if (ONCE) {
    await runOnce();
    return;
  }

  // Continuous loop: record, transcribe, publish, repeat
  log(`Continuous mode — ${DURATION}s clips, Ctrl+C to stop`);
  while (true) {
    try {
      await runOnce();
    } catch (e: any) {
      log(`⚠️  Error in capture loop: ${e.message}`);
      await Bun.sleep(2000);
    }
  }
}

main().catch(e => { console.error(e); process.exit(1); });

```
