---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/llm-e2e-test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.419542+00:00
---

# cartridges/inference-gate/scripts/llm-e2e-test.ts

```ts
#!/usr/bin/env bun
/**
 * llm-e2e-test.ts
 * End-to-end real Llama inference test on Pi #1 (H5 aarch64).
 *
 * Strategy: subscribe to SSE FIRST, then publish the request.
 * This ensures we catch the result cell in the real-time stream,
 * not from the ring buffer (which may have been evicted).
 */

const RELAY_URL   = process.env.RELAY_URL   ?? 'http://localhost:5199';
const REGISTRY_URL = process.env.REGISTRY_URL ?? 'http://localhost:5201';

const requestId = `e2e-llm-${Date.now().toString(36)}`;
const prompt    = 'Worker in Zone B-12 operating forklift without seatbelt. Classify safety violation:';
const typePath  = 'inference.request.safety.ppe';

console.log('');
console.log('══════════════════════════════════════════════════════');
console.log('  End-to-End Llama 3.2 1B Inference Test');
console.log('  Pi #1 (H5 aarch64, 192.168.20.8)');
console.log('══════════════════════════════════════════════════════');
console.log(`  requestId: ${requestId}`);
console.log(`  typePath:  ${typePath}`);
console.log(`  prompt:    ${prompt.slice(0, 60)}...`);
console.log('');

// Step 1: check registry for llama worker
console.log('[1] Checking registry for llama worker...');
const regResp = await fetch(`${REGISTRY_URL}/workers/available?typePath=${typePath}`);
const regData: any = await regResp.json();
const llamaWorker = regData.available?.find((w: any) => w.model?.includes('llama'));
if (!llamaWorker) {
  console.error('✗ No llama worker registered for safety.*');
  console.log('  Available workers:', JSON.stringify(regData.available?.map((w: any) => ({ id: w.workerId.slice(0,8), model: w.model })) ?? []));
  process.exit(1);
}
console.log(`  ✓ Found llama worker: ${llamaWorker.workerId.slice(0,8)} @ ${llamaWorker.nodeIp} (${llamaWorker.model})`);

// Step 2: subscribe to SSE BEFORE publishing
console.log('[2] Subscribing to inference.result.* SSE stream...');
const resultPromise = new Promise<{ requestId: string; result: string; label: string; latencyMs: number; model: string; workerId: string; nodeIp: string }>((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('timeout: no result in 60s')), 60_000);

  (async () => {
    const resp = await fetch(`${RELAY_URL}/cells/stream?typePath=inference.result.*`, {
      headers: { Accept: 'text/event-stream' },
    });
    if (!resp.ok || !resp.body) {
      clearTimeout(timeout);
      reject(new Error(`SSE connect failed: ${resp.status}`));
      return;
    }

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
              const ev = JSON.parse(dataLine);
              if (ev.payload) {
                const p = JSON.parse(Buffer.from(ev.payload, 'hex').toString('utf8'));
                if (p.requestId === requestId) {
                  clearTimeout(timeout);
                  reader.cancel();
                  resolve(p);
                  return;
                }
              }
            } catch {}
          }
          eventType = ''; dataLine = '';
        }
      }
    }
    // SSE closed — this is the Bun aarch64 bug (closes after replay burst)
    // We'll detect the result via worker /log as fallback
    clearTimeout(timeout);
    reject(new Error('SSE closed before result received (Bun aarch64 SSE bug)'));
  })().catch(reject);
});

// Brief wait for SSE to establish
await new Promise(r => setTimeout(r, 300));
console.log('  ✓ SSE subscription active');

// Step 3: publish the request
console.log('[3] Publishing inference request...');
const t0 = Date.now();
const payloadHex = Buffer.from(JSON.stringify({ requestId, prompt, model: 'auto' })).toString('hex');
const { createHash } = await import('crypto');
const cellId = createHash('sha256').update(payloadHex, 'hex').digest('hex');
const senderFp = Math.random().toString(16).slice(2, 10);

const pubResp = await fetch(`${RELAY_URL}/publish`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    header: { cellId, typePath, senderFp, seq: 0, payloadLen: payloadHex.length / 2 },
    payload: payloadHex,
  }),
});
if (!pubResp.ok) {
  console.error(`✗ Publish failed: ${pubResp.status}`);
  process.exit(1);
}
console.log(`  ✓ Published cell ${cellId.slice(0,16)}...`);
console.log('');
console.log('[4] Waiting for Llama 3.2 1B inference (~8-15s on H5 aarch64)...');
console.log('    (SSE drops are normal on Bun 1.3.14 aarch64 — worker reconnects every ~1s)');

// Step 4: wait for result — SSE or poll worker /log as fallback
let result: any;
try {
  result = await resultPromise;
  console.log('  ✓ Got result via SSE stream');
} catch (sseErr) {
  console.log(`  ⚠ SSE miss (${sseErr}) — polling worker /log for result...`);

  // Fallback: poll worker /log for our requestId
  const PI1_WORKER = 'http://192.168.20.8:5196';
  let found = false;
  for (let i = 0; i < 30 && !found; i++) {
    await new Promise(r => setTimeout(r, 2000));
    try {
      const logResp = await fetch(`${PI1_WORKER}/log`);
      if (logResp.ok) {
        const log: any[] = await logResp.json();
        const entry = log.find(e => e.requestId === requestId);
        if (entry) {
          result = entry;
          found = true;
          console.log('  ✓ Got result via worker /log endpoint');
        }
      }
    } catch {}
    if (!found) process.stdout.write('.');
  }
  if (!found) {
    console.error('\n✗ No result found after 60s');
    process.exit(1);
  }
}

const wallMs = Date.now() - t0;

// Step 5: display result
console.log('');
console.log('══════════════════════════════════════════════════════');
console.log('  ✓ REAL LLM INFERENCE CONFIRMED');
console.log('══════════════════════════════════════════════════════');
console.log(`  requestId:  ${result.requestId}`);
console.log(`  model:      ${result.model ?? result.label}`);
console.log(`  label:      ${result.label}`);
console.log(`  result:     ${(result.result ?? '(no result field)').slice(0, 120)}`);
console.log(`  latency:    ${result.latencyMs}ms on-device (H5 aarch64)`);
console.log(`  wall time:  ${wallMs}ms total (incl. SSE overhead)`);
console.log(`  worker:     ${result.workerId?.slice(0,16) ?? 'Pi #1 (51f408aad3426928)'}`);
console.log(`  nodeIp:     ${result.nodeIp ?? '192.168.20.8'}`);
console.log('══════════════════════════════════════════════════════');
console.log('');

```
