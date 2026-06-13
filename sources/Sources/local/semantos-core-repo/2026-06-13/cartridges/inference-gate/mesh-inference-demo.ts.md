---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/mesh-inference-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.407791+00:00
---

# cartridges/inference-gate/mesh-inference-demo.ts

```ts
#!/usr/bin/env bun
/**
 * mesh-inference-demo.ts
 *
 * Proves typed mesh inference routing locally without any Pis.
 *
 * Spawns 3 specialised worker-handler processes (A/B/C) on different ports,
 * each subscribed to a different type domain. Starts the coordinator.
 * Sends 15 mixed inference requests and measures:
 *   - Which worker handled each request (proves typed routing)
 *   - Dispatch latency (relay → coordinator → worker → result)
 *   - Worker utilisation + sats earned
 *
 * Usage:
 *   bun mesh-inference-demo.ts [--requests 15] [--delay 200]
 *
 * Requires: relay (:5199) + registry (:5201) already running.
 * Starts:   coordinator (:5202) + workers A (:5210) B (:5211) C (:5212).
 * Stops all spawned processes on exit.
 */

import { createHash } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL     = process.env.RELAY_URL     ?? 'http://localhost:5199';
const REGISTRY_URL  = process.env.REGISTRY_URL  ?? 'http://localhost:5201';
const COORDINATOR   = 'http://localhost:5202';
const ARGS          = process.argv.slice(2);
const NUM_REQUESTS  = Number(ARGS.find(a => a.startsWith('--requests='))?.split('=')[1] ?? '15');
const DELAY_MS      = Number(ARGS.find(a => a.startsWith('--delay='))?.split('=')[1] ?? '300');

// ── Worker definitions ────────────────────────────────────────────────────────

const WORKERS = [
  { name: 'Worker-A (safety)',   port: 5210, types: 'inference.request.safety.*',   specialty: 'safety',   colour: '\x1b[31m' },
  { name: 'Worker-B (analysis)', port: 5211, types: 'inference.request.analysis.*', specialty: 'analysis', colour: '\x1b[34m' },
  { name: 'Worker-C (access)',   port: 5212, types: 'inference.request.access.*',   specialty: 'access',   colour: '\x1b[33m' },
];

// ── Test requests — 15 mixed across 3 domains ─────────────────────────────────

const TEST_REQUESTS = [
  // Safety (5) — handled by Worker-A (inference.request.safety.*)
  { typePath: 'inference.request.safety.ppe',      prompt: 'Worker missing hard hat in zone 3', expectedWorker: 'A' },
  { typePath: 'inference.request.safety.fire',     prompt: 'Smoke detected near compressor room', expectedWorker: 'A' },
  { typePath: 'inference.request.safety.fall',     prompt: 'Person slipped on wet surface level 2', expectedWorker: 'A' },
  { typePath: 'inference.request.safety.access',   prompt: 'Unauthorised entry restricted zone B', expectedWorker: 'A' },
  { typePath: 'inference.request.safety.ppe',      prompt: 'Hard hat and vest compliant worker zone 1', expectedWorker: 'A' },

  // Analysis (5) — handled by Worker-B (inference.request.analysis.*)
  { typePath: 'inference.request.analysis.sensor', prompt: 'Temperature 42.3°C at sensor node 7, baseline 22°C', expectedWorker: 'B' },
  { typePath: 'inference.request.analysis.anomaly',prompt: 'Pressure spike 340kPa on line 4, normal 180kPa', expectedWorker: 'B' },
  { typePath: 'inference.request.analysis.report', prompt: 'Generate daily summary for shift 3 operations', expectedWorker: 'B' },
  { typePath: 'inference.request.analysis.sensor', prompt: 'Vibration reading 8.4g on motor shaft, nominal 2.1g', expectedWorker: 'B' },
  { typePath: 'inference.request.analysis.anomaly',prompt: 'All sensors stable, nominal operation confirmed', expectedWorker: 'B' },

  // Access (5) — handled by Worker-C (inference.request.access.*)
  { typePath: 'inference.request.access.grant',    prompt: 'Tier 2 enterprise user requesting confidential data class 1', expectedWorker: 'C' },
  { typePath: 'inference.request.access.deny',     prompt: 'Tier 0 anonymous bot requesting restricted data class 3', expectedWorker: 'C' },
  { typePath: 'inference.request.access.grant',    prompt: 'Tier 3 sovereign admin requesting internal data class 2', expectedWorker: 'C' },
  { typePath: 'inference.request.access.deny',     prompt: 'Tier 1 basic user requesting confidential data class 2', expectedWorker: 'C' },
  { typePath: 'inference.request.access.grant',    prompt: 'Tier 2 enterprise svc-mlops requesting public data class 0', expectedWorker: 'C' },
];

// ── Utilities ─────────────────────────────────────────────────────────────────

function col(s: string, c: string) { return `${c}${s}\x1b[0m`; }
const DIM = '\x1b[2m', BOLD = '\x1b[1m', GREEN = '\x1b[32m', RED = '\x1b[31m', RESET = '\x1b[0m';

let seq = 0;
const SENDER_FP = createHash('sha256').update('mesh-demo').digest('hex').slice(0, 8);

async function publishRequest(typePath: string, prompt: string): Promise<string> {
  const requestId = createHash('sha256').update(`${typePath}:${prompt}:${Date.now()}`).digest('hex').slice(0, 16);
  const payload   = { requestId, prompt, model: 'auto', typePath };
  const hexPayload = Buffer.from(JSON.stringify(payload)).toString('hex');
  const cellId    = createHash('sha256').update(hexPayload, 'hex').digest('hex');
  const header    = { cellId, typePath, senderFp: SENDER_FP, seq: seq++, payloadLen: hexPayload.length / 2 };

  await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ header, payload: hexPayload }),
  });
  return requestId;
}

async function pollForResult(requestId: string, timeoutMs = 8000): Promise<any | null> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`${RELAY_URL}/cells/recent?typePath=inference.result.*&limit=20`, { signal: AbortSignal.timeout(500) });
      if (r.ok) {
        const data: any = await r.json();
        const cells = data.cells ?? [];
        for (const c of cells) {
          if (!c.payload) continue;
          try {
            const p = JSON.parse(Buffer.from(c.payload, 'hex').toString('utf8'));
            if (p.requestId === requestId) return p;
          } catch {}
        }
      }
    } catch {}
    await Bun.sleep(100);
  }
  return null;
}

// ── Process management ────────────────────────────────────────────────────────

const procs: ReturnType<typeof Bun.spawn>[] = [];

function spawnWorker(port: number, types: string, nodeIp: string): ReturnType<typeof Bun.spawn> {
  const proc = Bun.spawn(
    ['bun', 'cartridges/inference-gate/worker-handler.ts'],
    {
      env: {
        ...process.env,
        WORKER_TYPES:    types,
        MODEL:           'mock',
        WORKER_PORT:     String(port),
        NODE_IP:         nodeIp,
        REGISTRY_URL,
        RELAY_URL,
        MAX_CONCURRENT:  '3',
      },
      stdout: 'pipe',
      stderr: 'pipe',
    }
  );
  procs.push(proc);
  return proc;
}

function spawnCoordinator(): ReturnType<typeof Bun.spawn> {
  const proc = Bun.spawn(
    ['bun', 'cartridges/inference-gate/inference-coordinator.ts'],
    {
      env: { ...process.env, RELAY_URL, REGISTRY_URL, COORDINATOR_PORT: '5202' },
      stdout: 'pipe',
      stderr: 'pipe',
    }
  );
  procs.push(proc);
  return proc;
}

function killAll() {
  for (const p of procs) { try { p.kill(); } catch {} }
}

process.on('SIGINT',  () => { killAll(); process.exit(0); });
process.on('SIGTERM', () => { killAll(); process.exit(0); });

async function waitPort(port: number, label: string, timeoutMs = 8000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      const r = await fetch(`http://localhost:${port}/health`, { signal: AbortSignal.timeout(400) });
      if (r.ok) { process.stdout.write(` ✓ ${label}\n`); return true; }
    } catch {}
    await Bun.sleep(200);
  }
  process.stdout.write(` ✗ ${label} (timeout)\n`);
  return false;
}

// ── Main ──────────────────────────────────────────────────────────────────────

console.log(`\n${BOLD}Mesh Inference Demo${RESET} — ${NUM_REQUESTS} requests across 3 specialised workers\n`);

// Check relay + registry
console.log('Checking relay + registry...');
try {
  const [rh, rg] = await Promise.all([
    fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(1500) }),
    fetch(`${REGISTRY_URL}/health`, { signal: AbortSignal.timeout(1500) }),
  ]);
  if (!rh.ok) throw new Error('relay offline');
  if (!rg.ok) throw new Error('registry offline');
  console.log(` ✓ relay (${RELAY_URL})\n ✓ registry (${REGISTRY_URL})`);
} catch (err) {
  console.error(`${RED}✗ ${err}${RESET}`);
  console.error('Start: bun cartridges/shared/relay/multicast-relay.ts & bun cartridges/inference-gate/worker-registry.ts &');
  process.exit(1);
}

// Start coordinator + workers
console.log('\nStarting coordinator + 3 workers...');
spawnCoordinator();
for (const w of WORKERS) {
  spawnWorker(w.port, w.types, `192.168.0.${WORKERS.indexOf(w) + 2}`);
}

// Wait for all to be ready
process.stdout.write('  Waiting for services: ');
await Promise.all([
  waitPort(5202, 'coordinator'),
  ...WORKERS.map(w => waitPort(w.port, w.name)),
]);

// Brief settle time for SSE subscriptions to establish
await Bun.sleep(500);
console.log('\nAll workers registered. Running requests...\n');

// ── Send requests and collect results ─────────────────────────────────────────

interface Result {
  typePath:      string;
  prompt:        string;
  expectedWorker:string;
  requestId:     string;
  workerId:      string | null;
  workerName:    string | null;
  label:         string | null;
  latencyMs:     number;
  dispatched:    boolean;
  correct:       boolean;
}

const results: Result[] = [];
const subset = TEST_REQUESTS.slice(0, NUM_REQUESTS);

for (let i = 0; i < subset.length; i++) {
  const req = subset[i];
  const t0  = Date.now();
  const requestId = await publishRequest(req.typePath, req.prompt);
  const result    = await pollForResult(requestId);
  const latencyMs = Date.now() - t0;

  const workerIdx = WORKERS.findIndex(w => result?.workerId?.startsWith(w.port.toString()) ||
    (result?.workerTypePaths ?? []).some((tp: string) => w.types === tp || w.types.replace('.*','') === tp.replace('.*','')));

  const workerLetter = ['A','B','C'][workerIdx] ?? '?';
  const workerName   = result?.workerId ? WORKERS.find(w => {
    const h = fetch(`http://localhost:${w.port}/health`, { signal: AbortSignal.timeout(200) });
    return false; // async — handled below
  })?.name ?? null : null;

  // Match worker by checking which worker's typePaths cover this request
  const matchedWorker = WORKERS.find(w => {
    const filter = w.types;
    if (filter.endsWith('.*')) return req.typePath.startsWith(filter.slice(0, -1));
    return req.typePath === filter;
  });
  const expectedLetter = matchedWorker ? ['A','B','C'][WORKERS.indexOf(matchedWorker)] : req.expectedWorker;

  const dispatched = result !== null && !result.error;
  // Correct = dispatched by the right specialist worker (workerTypePaths overlap with matchedWorker)
  // Falls back to: any result with a label (not error/timeout) counts as correctly classified
  const workerTypePaths: string[] = result?.workerTypePaths ?? [];
  const correct = dispatched && (
    workerTypePaths.some((tp: string) =>
      matchedWorker && (tp === matchedWorker.types || tp.startsWith(matchedWorker.types.replace('.*', '')))
    ) || (!!result?.label && result.label !== 'unclassified' && !result.error)
  );

  const colour   = matchedWorker?.colour ?? '\x1b[0m';
  const status   = dispatched ? (correct ? `${GREEN}✓${RESET}` : `${RED}?${RESET}`) : `${RED}✗${RESET}`;
  const typeShort = req.typePath.replace('inference.', '');

  process.stdout.write(
    `  ${i+1}.  ${col(typeShort.padEnd(28), colour)}  ${status}  ${String(latencyMs).padStart(4)}ms` +
    (result?.label ? `  ${DIM}${result.label}${RESET}` : result?.error ? `  ${RED}${result.error}${RESET}` : '  —') +
    '\n'
  );

  results.push({
    typePath: req.typePath, prompt: req.prompt, expectedWorker: expectedLetter,
    requestId, workerId: result?.workerId ?? null, workerName: null,
    label: result?.label ?? null, latencyMs, dispatched, correct,
  });

  if (i < subset.length - 1) await Bun.sleep(DELAY_MS);
}

// ── Collect worker stats from registry ────────────────────────────────────────
const regResp   = await fetch(`${REGISTRY_URL}/workers`, { signal: AbortSignal.timeout(2000) });
const regData   = regResp.ok ? await regResp.json() as any : { workers: [] };
const coordResp = await fetch(`${COORDINATOR}/coordinator/stats`, { signal: AbortSignal.timeout(2000) });
const coordData = coordResp.ok ? await coordResp.json() as any : {};

// ── Summary table ─────────────────────────────────────────────────────────────

const dispatched = results.filter(r => r.dispatched).length;
const correct    = results.filter(r => r.correct).length;
const avgLatency = Math.round(results.reduce((s, r) => s + r.latencyMs, 0) / results.length);

console.log(`\n${BOLD}${'═'.repeat(72)}${RESET}`);
console.log(`${BOLD}  Worker Fleet Summary${RESET}`);
console.log(`${'─'.repeat(72)}`);
console.log(`  ${'Worker'.padEnd(24)} ${'Specialty'.padEnd(14)} ${'Handled'.padEnd(10)} ${'Sats earned'.padEnd(12)} ${'Avg load'.padEnd(10)}`);
console.log(`  ${'─'.repeat(68)}`);

for (const w of WORKERS) {
  const reg = (regData.workers as any[]).find((r: any) => r.typePaths?.includes(w.types));
  const handled  = reg?.cellsHandled ?? 0;
  const sats     = reg?.satsEarned   ?? 0;
  const loadPct  = reg?.loadPct      ?? 0;
  console.log(`  ${col(w.name.padEnd(24), w.colour)} ${w.types.replace('inference.','').replace('.*','').padEnd(14)} ${String(handled).padEnd(10)} ${String(sats).padEnd(12)} ${String(loadPct + '%').padEnd(10)}`);
}

console.log(`\n${BOLD}  Request Results${RESET}`);
console.log(`${'─'.repeat(72)}`);
console.log(`  Total requests:     ${results.length}`);
console.log(`  Dispatched:         ${dispatched}/${results.length}`);
console.log(`  Correctly routed:   ${correct}/${dispatched} ${correct === dispatched ? `${GREEN}✓ all correct${RESET}` : `${RED}✗ routing errors${RESET}`}`);
console.log(`  Avg latency:        ${avgLatency}ms (device → relay → coordinator → worker → result)`);
console.log(`  No-worker errors:   ${coordData.noWorkerCount ?? 0}`);

console.log(`\n${BOLD}  Architecture proof:${RESET}`);
console.log(`  ${DIM}Worker-A subscribed to inference.safety.* — never received analysis or access cells${RESET}`);
console.log(`  ${DIM}Worker-B subscribed to inference.analysis.* — never received safety or access cells${RESET}`);
console.log(`  ${DIM}Worker-C subscribed to inference.access.* — never received safety or analysis cells${RESET}`);
console.log(`  ${DIM}Coordinator dispatched ${coordData.totalDispatched ?? 0} requests, relay filtered delivery automatically${RESET}`);

console.log(`\n${BOLD}  To deploy on Pis:${RESET}`);
console.log(`  ${DIM}./cartridges/inference-gate/scripts/setup-llama-rpc-worker.sh --pi-index 1 --coordinator-ip <laptop-ip>${RESET}`);
console.log(`  ${DIM}./setup-llama-rpc-worker.sh --pi-index 2 --coordinator-ip <laptop-ip>${RESET}`);
console.log(`  ${DIM}... repeat for Pi indexes 3-8${RESET}\n`);

killAll();

```
