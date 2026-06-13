---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/pipeline-ensemble-test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.418127+00:00
---

# cartridges/inference-gate/scripts/pipeline-ensemble-test.ts

```ts
#!/usr/bin/env bun
/**
 * pipeline-ensemble-test.ts
 *
 * Tests the coordinator's pipeline and ensemble modes against the live mesh.
 *
 * PIPELINE test:
 *   Sends inference.request.safety.ppe with _pipeline:["inference.request.analysis.*"]
 *   Pi #1 (safety) classifies → coordinator chains → Pi #2 (analysis) analyses
 *   Final: inference.result.pipeline with both stage results
 *
 * ENSEMBLE test:
 *   Sends inference.request.analysis.* with _ensemble:{n:3,required:2}
 *   Coordinator fans out to Pi #2, #3, #4 (analysis/access/ppe workers)
 *   Waits for 2-of-3 label agreement → inference.result.ensemble
 *
 * Usage:
 *   bun pipeline-ensemble-test.ts
 *   bun pipeline-ensemble-test.ts --test pipeline
 *   bun pipeline-ensemble-test.ts --test ensemble
 */

const RELAY_URL      = process.env.RELAY_URL      ?? 'http://localhost:5199';
const REGISTRY_URL   = process.env.REGISTRY_URL   ?? 'http://localhost:5201';
const COORD_URL      = process.env.COORD_URL       ?? 'http://localhost:5202';

const _testFlagIdx = process.argv.indexOf('--test');
const testArg = process.argv.find(a => a.startsWith('--test='))?.slice(7)
             ?? (_testFlagIdx >= 0 ? process.argv[_testFlagIdx + 1] : undefined)
             ?? 'both';

import { createHash } from 'crypto';

function hex(payload: object): string {
  return Buffer.from(JSON.stringify(payload)).toString('hex');
}

function cellId(payloadHex: string): string {
  return createHash('sha256').update(payloadHex, 'hex').digest('hex');
}

async function publish(typePath: string, payload: object): Promise<string> {
  const payloadHex = hex(payload);
  const id = cellId(payloadHex);
  const senderFp = Math.random().toString(16).slice(2, 10);
  await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      header: { cellId: id, typePath, senderFp, seq: 0, payloadLen: payloadHex.length / 2 },
      payload: payloadHex,
    }),
  });
  return id;
}

/**
 * Subscribe to a result typePath and wait for a cell matching predicate.
 * Falls back to polling /cells/recent after SSE disconnect (Bun SSE bug).
 */
async function waitForResult(
  typePath: string,
  predicate: (p: any) => boolean,
  timeoutMs = 90_000
): Promise<any> {
  const deadline = Date.now() + timeoutMs;

  // Try SSE first
  const sseResult = await new Promise<any | null>((resolve) => {
    let done = false;
    const t = setTimeout(() => { if (!done) { done = true; resolve(null); } }, Math.min(timeoutMs, 30_000));

    (async () => {
      try {
        const resp = await fetch(`${RELAY_URL}/cells/stream?typePath=${encodeURIComponent(typePath)}`, {
          headers: { Accept: 'text/event-stream' },
        });
        if (!resp.ok || !resp.body) { clearTimeout(t); resolve(null); return; }

        const reader = resp.body.getReader();
        const tdec = new TextDecoder();
        let buf = '';
        while (Date.now() < deadline) {
          const { done: d, value } = await reader.read();
          if (d) break;
          buf += tdec.decode(value, { stream: true });
          const lines = buf.split('\n');
          buf = lines.pop() ?? '';
          let evType = '', data = '';
          for (const line of lines) {
            if (line.startsWith('event: ')) evType = line.slice(7).trim();
            if (line.startsWith('data: '))  data  = line.slice(6).trim();
            if (line === '' && data) {
              try {
                const ev = JSON.parse(data);
                if (ev.payload) {
                  const p = JSON.parse(Buffer.from(ev.payload, 'hex').toString('utf8'));
                  if (predicate(p)) {
                    clearTimeout(t);
                    if (!done) { done = true; resolve(p); }
                    return;
                  }
                }
              } catch {}
              evType = ''; data = '';
            }
          }
        }
        clearTimeout(t);
        if (!done) { done = true; resolve(null); }
      } catch { clearTimeout(t); if (!done) { done = true; resolve(null); } }
    })();
  });

  if (sseResult) return sseResult;

  // SSE closed (Bun bug) — poll /cells/recent
  console.log('  ⚠ SSE closed early (Bun aarch64 bug) — polling /cells/recent...');
  while (Date.now() < deadline) {
    await Bun.sleep(2000);
    try {
      const resp = await fetch(`${RELAY_URL}/cells/recent?typePath=${encodeURIComponent(typePath)}&limit=50`);
      if (resp.ok) {
        const data: any = await resp.json();
        // Relay returns { cells: [...], count, filter } — not a raw array
        const cells: any[] = Array.isArray(data) ? data : (data.cells ?? []);
        for (const c of cells) {
          if (!c.payload) continue;
          try {
            const p = JSON.parse(Buffer.from(c.payload, 'hex').toString('utf8'));
            if (predicate(p)) return p;
          } catch {}
        }
      }
    } catch {}
    process.stdout.write('.');
  }
  throw new Error(`timeout after ${timeoutMs}ms`);
}

// ── Banner ────────────────────────────────────────────────────────────────────

console.log('');
console.log('══════════════════════════════════════════════════════');
console.log('  Coordinator Pipeline + Ensemble Test');
console.log('══════════════════════════════════════════════════════');
console.log(`  Relay:       ${RELAY_URL}`);
console.log(`  Coordinator: ${COORD_URL}`);
console.log(`  Tests:       ${testArg}`);
console.log('');

// Check coordinator health
const health: any = await fetch(`${COORD_URL}/health`).then(r => r.json()).catch(() => null);
if (!health) {
  console.error('✗ Coordinator not reachable — start it first:');
  console.error('  bun cartridges/inference-gate/inference-coordinator.ts');
  process.exit(1);
}
console.log(`✓ Coordinator online (dispatched: ${health.totalDispatched}, relay: ${health.relayConnected})`);
console.log('');

// ── Pipeline test ─────────────────────────────────────────────────────────────

async function testPipeline() {
  console.log('══════════════════════════════════════════════════════');
  console.log('  TEST: Multi-Stage Pipeline Inference');
  console.log('  Stage 1: inference.request.safety.ppe  → Pi #1 (safety)');
  console.log('  Stage 2: inference.request.analysis.*  → Pi #2 (analysis)');
  console.log('══════════════════════════════════════════════════════');
  console.log('');

  const requestId = `pipe-test-${Date.now().toString(36)}`;
  const t0 = Date.now();

  console.log(`[1] Publishing pipeline request (requestId: ${requestId})...`);
  await publish('inference.request.safety.ppe', {
    requestId,
    prompt: 'Worker in Zone B-12 operating forklift without seatbelt. Classify safety violation:',
    _pipeline: ['inference.request.analysis.*'],
  });
  console.log('  ✓ Published');

  console.log('[2] Waiting for pipeline result (inference.result.pipeline)...');
  console.log('    Stage 1 → 2 chaining adds ~latency of both workers...');
  console.log('    (Mock workers: ~200ms each. Real Llama: ~30s per stage.)');

  const result = await waitForResult(
    'inference.result.*',
    p => p.requestId === requestId && (p.pipelineId || p.stages),
    240_000  // 3B model: ~90s/stage; need 240s for 2 stages + polling overhead
  );

  const wallMs = Date.now() - t0;
  console.log('');
  console.log('══════════════════════════════════════════════════════');
  console.log('  ✓ PIPELINE RESULT');
  console.log('══════════════════════════════════════════════════════');
  console.log(`  requestId:   ${result.requestId}`);
  console.log(`  pipelineId:  ${result.pipelineId ?? '(none)'}`);
  console.log(`  stages:      ${JSON.stringify(result.stages ?? [])}`);
  console.log(`  finalLabel:  ${result.finalLabel ?? result.label}`);
  console.log(`  finalResult: ${String(result.finalResult ?? result.result ?? '').slice(0, 100)}`);
  console.log(`  totalMs:     ${result.totalMs ?? wallMs}ms`);
  if (result.results?.length) {
    console.log('  stages:');
    for (const [i, s] of result.results.entries()) {
      console.log(`    [${i}] ${s.stageTypePath}: label=${s.label} (${s.latencyMs}ms) result="${String(s.result).slice(0, 60)}"`);
    }
  }
  console.log('══════════════════════════════════════════════════════');
  console.log('');
  return result;
}

// ── Ensemble test ─────────────────────────────────────────────────────────────

async function testEnsemble() {
  console.log('══════════════════════════════════════════════════════');
  console.log('  TEST: Ensemble Voting (fan-out + 2-of-3 agreement)');
  console.log('  Workers: Pi #2 (analysis), Pi #3 (access), Pi #4 (ppe)');
  console.log('══════════════════════════════════════════════════════');
  console.log('');

  const requestId = `ens-test-${Date.now().toString(36)}`;
  const t0 = Date.now();

  // Use analysis.* which has workers on Pi #2, #3, #4 (mock)
  // Note: with the current fleet, different typePaths are on different Pis.
  // Ensemble works best when N workers share the same typePath.
  // For this test, we dispatch to inference.request.analysis.* and let
  // the coordinator find up to 3 workers.
  console.log(`[1] Publishing ensemble request (requestId: ${requestId}, n=3, required=2)...`);
  await publish('inference.request.analysis.anomaly', {
    requestId,
    prompt: 'Anomaly detected: temperature spike 42°C in server room A-3. Assess criticality.',
    _ensemble: { n: 3, required: 2 },
  });
  console.log('  ✓ Published');

  console.log('[2] Waiting for ensemble result (inference.result.ensemble)...');
  console.log('    Coordinator fans out to N workers, waits for 2-of-3 label agreement...');
  console.log('    (If only 1 worker available for this type, ensemble settles with 1 vote)');

  const result = await waitForResult(
    'inference.result.*',
    p => p.requestId === requestId && (p.ensembleId || p.tally),
    60_000
  );

  const wallMs = Date.now() - t0;
  console.log('');
  console.log('══════════════════════════════════════════════════════');
  console.log('  ✓ ENSEMBLE RESULT');
  console.log('══════════════════════════════════════════════════════');
  console.log(`  requestId:   ${result.requestId}`);
  console.log(`  ensembleId:  ${result.ensembleId ?? '(none)'}`);
  console.log(`  label:       ${result.label} (winner)`);
  console.log(`  tally:       ${JSON.stringify(result.tally ?? {})}`);
  console.log(`  votes:       ${result.n ?? 1} dispatched, ${result.required ?? 1} required`);
  console.log(`  avgLatency:  ${result.avgLatencyMs ?? 'n/a'}ms`);
  console.log(`  totalMs:     ${result.totalMs ?? wallMs}ms`);
  if (result.votes?.length) {
    console.log('  individual votes:');
    for (const v of result.votes) {
      console.log(`    ${v.workerId?.slice(0,8)??'?'} @ ${v.nodeIp}: label="${v.label}" (${v.latencyMs}ms)`);
    }
  }
  console.log('══════════════════════════════════════════════════════');
  console.log('');
  return result;
}

// ── Run tests ─────────────────────────────────────────────────────────────────

try {
  if (testArg === 'both' || testArg === 'pipeline') {
    await testPipeline();
  }
  if (testArg === 'both' || testArg === 'ensemble') {
    await testEnsemble();
  }

  console.log('');
  console.log(`${testArg === 'both' ? '✓ All' : '✓'} tests complete`);
  console.log('');
  console.log('  Coordinator stats:');
  const stats: any = await fetch(`${COORD_URL}/coordinator/stats`).then(r => r.json()).catch(() => ({}));
  console.log(`    totalDispatched: ${stats.totalDispatched ?? '?'}`);
  console.log(`    totalPipelined:  ${stats.totalPipelined ?? '?'}`);
  console.log(`    totalEnsembled:  ${stats.totalEnsembled ?? '?'}`);
  console.log('');
} catch (err) {
  console.error(`\n✗ Test failed: ${err}`);
  process.exit(1);
}

```
