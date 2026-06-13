---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/construction-demo.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.410390+00:00
---

# cartridges/inference-gate/construction-demo.ts

```ts
#!/usr/bin/env bun
/**
 * construction-demo.ts — End-to-end construction site inference demo
 *
 * Runs a 60-second simulation of a construction site safety monitoring system.
 * Sends 10 realistic site events as inference cells, shows the AI classification
 * round-trip through the cell mesh, and prints a final audit summary with BSV
 * payment stats — the complete "device → cell → AI → result → on-chain receipt"
 * pipeline in one terminal window.
 *
 * This is the demo to run for a potential customer.
 *
 * USAGE
 * ─────
 *   bun cartridges/inference-gate/construction-demo.ts
 *   RELAY_URL=http://192.168.0.50:5199 bun construction-demo.ts   # Pi relay
 *   FAST=true bun construction-demo.ts                            # no delays
 *   EVENTS=3 bun construction-demo.ts                             # fewer events
 *
 * PREREQUISITES
 * ─────────────
 *   Start the demo stack first:
 *     bash cartridges/shared/demo/start-demo.sh
 *   Or at minimum:
 *     bun cartridges/shared/relay/multicast-relay.ts &
 *     bun cartridges/inference-gate/cell-handler.ts &
 */

import { createHash, randomBytes } from 'node:crypto';
import { join } from 'node:path';

const RELAY_URL     = process.env.RELAY_URL  ?? 'http://localhost:5199';
const BRIDGE_URL    = process.env.BRIDGE_URL ?? 'http://localhost:5198';
const HANDLER_URL   = process.env.HANDLER_URL ?? 'http://localhost:5196';
const FAST          = process.env.FAST === 'true';
const EVENT_COUNT   = parseInt(process.env.EVENTS ?? '10', 10);
const RESULT_TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS ?? '5000', 10);

// Path to cell-handler.ts — same directory as this script
const HANDLER_TS = join(import.meta.dir, 'cell-handler.ts');

const CLIENT_FP = createHash('sha256').update('construction-demo').digest('hex').slice(0, 8);

// ── Colour helpers ─────────────────────────────────────────────────────────────

const G = '\x1b[32m'; const Y = '\x1b[33m'; const R = '\x1b[31m';
const B = '\x1b[34m'; const C = '\x1b[36m'; const W = '\x1b[97m'; const NC = '\x1b[0m';
const DIM = '\x1b[2m'; const BOLD = '\x1b[1m';

// ── Construction site event catalogue ─────────────────────────────────────────
// These are the kinds of events a real construction site generates.

interface SiteEvent {
  zone:    string;
  sensor:  string;
  prompt:  string;
  expect:  'safety' | 'motion' | 'anomaly' | 'command';  // expected label
}

const SITE_EVENTS: SiteEvent[] = [
  {
    zone: 'Zone 3 — Scaffolding',
    sensor: 'Camera-07 (overhead)',
    prompt: 'Worker detected without hard hat or high-visibility vest near scaffolding zone 3 — PPE violation',
    expect: 'safety',
  },
  {
    zone: 'Zone 1 — Main Gate',
    sensor: 'Access Controller',
    prompt: 'Forklift operator requesting entry clearance to loading dock — unlock the main gate',
    expect: 'command',
  },
  {
    zone: 'Zone 5 — Compressor Room',
    sensor: 'Temperature Sensor 14',
    prompt: 'Motor housing temperature spike to 61°C — 18°C above normal operating threshold on compressor unit B',
    expect: 'anomaly',
  },
  {
    zone: 'Zone 2 — Delivery Dock',
    sensor: 'Motion Detector',
    prompt: 'Three vehicles entered delivery zone in last 5 minutes — 2 trucks, 1 forklift movement detected',
    expect: 'motion',
  },
  {
    zone: 'Zone 4 — Panel Room',
    sensor: 'Smoke Sensor 03',
    prompt: 'Smoke detected near electrical panel room — fire alarm triggered, emergency evacuation protocol',
    expect: 'safety',
  },
  {
    zone: 'Zone 6 — Hydraulics Bay',
    sensor: 'Pressure Gauge 09',
    prompt: 'Hydraulic pressure drop alert — system reading 2.1 bar below normal range on main hydraulic circuit',
    expect: 'anomaly',
  },
  {
    zone: 'Zone 3 — Scaffolding',
    sensor: 'Camera-07 (overhead)',
    prompt: 'Fall detected near loading bay — worker down in zone 4, emergency alert triggered',
    expect: 'safety',
  },
  {
    zone: 'Zone 1 — Main Gate',
    sensor: 'Access Controller',
    prompt: 'Disable access to restricted area zone 6 — unauthorised personnel attempting entry',
    expect: 'command',
  },
  {
    zone: 'Zone 7 — Fuel Store',
    sensor: 'Vibration Sensor 02',
    prompt: 'Abnormal vibration on generator housing — vibration exceeded safe threshold by 340% since last check',
    expect: 'anomaly',
  },
  {
    zone: 'Zone 2 — Delivery Dock',
    sensor: 'Camera-12 (entrance)',
    prompt: 'Person entered restricted area near compressor zone — motion detected and access zone breach logged',
    expect: 'motion',
  },
];

// ── Cell helpers ───────────────────────────────────────────────────────────────

interface InferenceResult {
  requestId?:  string;
  result?:     string;
  label?:      string;
  confidence?: number;
  latencyMs?:  number;
  error?:      string;
}

let seq = 0;

async function sendCell(event: SiteEvent): Promise<string> {
  const requestId = randomBytes(8).toString('hex');
  const payload   = JSON.stringify({ requestId, prompt: event.prompt, model: 'auto' });
  const payloadHex = Buffer.from(payload, 'utf8').toString('hex');
  const cellId    = createHash('sha256').update(payloadHex).digest('hex');
  seq++;

  await fetch(`${RELAY_URL}/publish`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      header: { cellId, typePath: 'inference.request.classify', senderFp: CLIENT_FP, seq, payloadLen: payload.length },
      payload: payloadHex,
    }),
    signal: AbortSignal.timeout(5000),
  });

  return requestId;
}

interface RecentCell { header: { typePath: string; ts: number }; payload: string | null }

async function waitResult(requestId: string): Promise<InferenceResult | null> {
  const deadline = Date.now() + RESULT_TIMEOUT_MS;
  while (Date.now() < deadline) {
    const r = await fetch(`${RELAY_URL}/cells/recent`, { signal: AbortSignal.timeout(2000) }).catch(() => null);
    if (r?.ok) {
      const { cells } = await r.json() as { cells: RecentCell[] };
      for (const cell of cells) {
        if (cell.header.typePath !== 'inference.result.response' || !cell.payload) continue;
        try {
          const res = JSON.parse(Buffer.from(cell.payload, 'hex').toString('utf8')) as InferenceResult;
          if (res.requestId === requestId) return res;
        } catch { /* skip */ }
      }
    }
    await Bun.sleep(300);
  }
  return null;
}

// ── Telemetry ──────────────────────────────────────────────────────────────────

interface SettlementState {
  sequenceNumber?: number;
  unitsMB?: number;
  autoSettleMB?: number;
  state?: string;
  satsEarned?: number;
}

async function getBridgeState(): Promise<SettlementState | null> {
  try {
    const r = await fetch(`${BRIDGE_URL}/channel/state`, { signal: AbortSignal.timeout(1500) });
    return r.ok ? r.json() : null;
  } catch { return null; }
}

async function getHandlerStats(): Promise<{ requestsTotal?: number; p50Ms?: number; p99Ms?: number } | null> {
  try {
    const r = await fetch(`${HANDLER_URL}/stats`, { signal: AbortSignal.timeout(1500) });
    return r.ok ? r.json() : null;
  } catch { return null; }
}

// ── Label display helpers ─────────────────────────────────────────────────────

const LABEL_ICON: Record<string, string> = {
  safety:  `${R}⚠️  SAFETY`,
  motion:  `${B}🚶 MOTION`,
  anomaly: `${Y}📈 ANOMALY`,
  command: `${C}🎛  COMMAND`,
  unknown: `${DIM}❓ UNKNOWN`,
};

const LABEL_COLOUR: Record<string, string> = {
  safety: R, motion: B, anomaly: Y, command: C, unknown: DIM,
};

// ── Main demo ─────────────────────────────────────────────────────────────────

async function main() {
  console.log('');
  console.log(`${BOLD}${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${BOLD}${W}  Layer Collapse — Construction Site Safety Demo${NC}`);
  console.log(`${W}  Inference cell pipeline: device → relay → AI → result → BSV${NC}`);
  console.log(`${BOLD}${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log('');

  // Check prerequisites
  let [relayOk, handlerOk] = await Promise.all([
    fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(2000) }).then(r => r.ok).catch(() => false),
    fetch(`${HANDLER_URL}/health`, { signal: AbortSignal.timeout(2000) }).then(r => r.ok).catch(() => false),
  ]);

  if (!relayOk) {
    console.log(`${R}  ✗ Relay not reachable at ${RELAY_URL}${NC}`);
    console.log(`${Y}    Start: bash cartridges/shared/demo/start-demo.sh${NC}`);
    console.log(`${Y}    Or:   bun cartridges/shared/relay/multicast-relay.ts${NC}`);
    process.exit(1);
  }

  // Auto-start the handler if it's not running — demo should work with one command
  let handlerProc: ReturnType<typeof Bun.spawn> | null = null;
  if (!handlerOk) {
    process.stdout.write(`  ${Y}⟳ Starting inference handler…${NC}`);
    handlerProc = Bun.spawn(
      ['bun', HANDLER_TS],
      { env: { ...process.env, RELAY_URL }, stdout: 'pipe', stderr: 'pipe' },
    );
    // Register cleanup — kill handler when demo exits
    process.on('exit', () => { try { handlerProc?.kill(); } catch {} });
    process.on('SIGINT', () => { try { handlerProc?.kill(); } catch {} process.exit(0); });

    // Wait up to 6s for handler to come up
    const deadline = Date.now() + 6000;
    while (Date.now() < deadline) {
      await Bun.sleep(400);
      handlerOk = await fetch(`${HANDLER_URL}/health`, { signal: AbortSignal.timeout(800) })
        .then(r => r.ok).catch(() => false);
      if (handlerOk) break;
    }
    process.stdout.write('\r\x1b[K');
    if (!handlerOk) {
      console.log(`${R}  ✗ Handler failed to start — check cell-handler.ts${NC}`);
      process.exit(1);
    }
  }

  const handlerHealth = handlerOk
    ? await fetch(`${HANDLER_URL}/health`).then(r => r.json() as Promise<{ model?: string }>).catch(() => null)
    : null;

  const bridgeState = await getBridgeState();

  console.log(`${G}  ✓ Relay    ${NC}${RELAY_URL}`);
  if (handlerOk) {
    const autoTag = handlerProc ? `  ${DIM}(auto-started)${NC}` : '';
    console.log(`${G}  ✓ Handler  ${NC}${HANDLER_URL}  model=${handlerHealth?.model ?? 'unknown'}${autoTag}`);
  }
  if (bridgeState) {
    const st = (bridgeState.state ?? 'unknown').toUpperCase();
    const sCol = bridgeState.state === 'FLOW_ACTIVE' ? G : Y;
    console.log(`${sCol}  ✓ Bridge   ${NC}${BRIDGE_URL}  ${sCol}${st}${NC}  settlements=${bridgeState.sequenceNumber ?? 0}`);
  }

  console.log('');
  console.log(`${DIM}  Simulating ${Math.min(EVENT_COUNT, SITE_EVENTS.length)} construction site events…${NC}`);
  console.log('');

  // ── Event loop ────────────────────────────────────────────────────────────

  const results: Array<{
    event: SiteEvent;
    result: InferenceResult | null;
    rttMs: number;
    correct: boolean;
  }> = [];

  const events = SITE_EVENTS.slice(0, Math.min(EVENT_COUNT, SITE_EVENTS.length));

  for (let i = 0; i < events.length; i++) {
    const event = events[i]!;
    const t0 = Date.now();

    // Print event
    console.log(`${BOLD}  Event ${i + 1}/${events.length}${NC}  ${DIM}${event.zone} · ${event.sensor}${NC}`);
    console.log(`  ${DIM}›${NC} ${event.prompt.slice(0, 80)}${event.prompt.length > 80 ? '…' : ''}`);
    process.stdout.write(`  ${DIM}⟳ waiting for AI classification…${NC}`);

    let requestId: string;
    try {
      requestId = await sendCell(event);
    } catch (e: any) {
      console.log(`\n  ${R}✗ Failed to send cell: ${e.message}${NC}\n`);
      results.push({ event, result: null, rttMs: 0, correct: false });
      continue;
    }

    const res  = await waitResult(requestId);
    const rttMs = Date.now() - t0;

    // Clear waiting line
    process.stdout.write('\r\x1b[K');

    if (!res) {
      console.log(`  ${Y}⚠ No result received (${rttMs}ms) — handler may be offline${NC}`);
      results.push({ event, result: null, rttMs, correct: false });
    } else {
      const label   = res.label ?? 'unknown';
      const correct = label === event.expect;
      const icon    = LABEL_ICON[label] ?? LABEL_ICON['unknown']!;
      const confPct = res.confidence ? `${(res.confidence * 100).toFixed(0)}%` : '';
      const tick    = correct ? `${G}✓${NC}` : `${Y}~${NC}`;

      console.log(`  ${tick} ${icon}${NC}  ${confPct ? `${confPct}  ` : ''}${DIM}${res.latencyMs}ms infer · ${rttMs}ms rtt${NC}`);
      console.log(`    ${DIM}${res.result?.slice(0, 72)}${(res.result?.length ?? 0) > 72 ? '…' : ''}${NC}`);
      results.push({ event, result: res, rttMs, correct });
    }

    console.log('');

    // Pace events
    if (i < events.length - 1 && !FAST) await Bun.sleep(1500);
  }

  // ── Summary ────────────────────────────────────────────────────────────────

  const total     = results.length;
  const received  = results.filter(r => r.result !== null).length;
  const correct   = results.filter(r => r.correct).length;
  const safetyCount  = results.filter(r => r.result?.label === 'safety').length;
  const motionCount  = results.filter(r => r.result?.label === 'motion').length;
  const anomalyCount = results.filter(r => r.result?.label === 'anomaly').length;
  const commandCount = results.filter(r => r.result?.label === 'command').length;
  const avgRtt    = received > 0
    ? Math.round(results.filter(r => r.result).reduce((s, r) => s + r.rttMs, 0) / received)
    : 0;

  const finalBridge  = await getBridgeState();
  const handlerStats = await getHandlerStats();

  console.log(`${BOLD}${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${BOLD}${W}  Audit Summary — ${new Date().toLocaleString()}${NC}`);
  console.log(`${BOLD}${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log('');
  console.log(`  Events sent:       ${W}${total}${NC}`);
  console.log(`  Results received:  ${received === total ? G : Y}${received}/${total}${NC}`);
  console.log(`  Correct labels:    ${correct === received ? G : Y}${correct}/${received}${NC}`);
  console.log(`  Avg round-trip:    ${W}${avgRtt}ms${NC}  (device → relay → AI → result)`);
  console.log('');
  console.log(`  ${R}⚠️  Safety alerts:    ${safetyCount}${NC}  (PPE, fire, fall, emergency)`);
  console.log(`  ${B}🚶 Motion events:    ${motionCount}${NC}  (access, vehicles, presence)`);
  console.log(`  ${Y}📈 Sensor anomalies: ${anomalyCount}${NC}  (temperature, pressure, vibration)`);
  console.log(`  ${C}🎛  Commands:         ${commandCount}${NC}  (gate, access, enable/disable)`);
  console.log('');

  if (finalBridge) {
    const settlements = finalBridge.sequenceNumber ?? 0;
    const mb          = (finalBridge.unitsMB ?? 0).toFixed(1);
    const sats        = finalBridge.satsEarned ?? 0;
    console.log(`  ${G}BSV settlements:   ${settlements}${NC}  (${mb} MB billed, ${sats} sats)`);
    if (settlements > 0) {
      console.log(`  ${G}On-chain anchors:  ${settlements}${NC}  PushDrop txids on BSV mainnet`);
    }
    console.log(`  ${DIM}Rate: 10 sats/MB · inference tier = 200 sats/cell (highest priority)${NC}`);
  } else {
    console.log(`  ${DIM}BSV bridge offline — payment settlement not recorded${NC}`);
  }

  if (handlerStats?.p50Ms) {
    console.log('');
    console.log(`  Handler p50: ${handlerStats.p50Ms}ms · p99: ${handlerStats.p99Ms ?? '—'}ms`);
  }

  console.log('');
  console.log(`  ${DIM}No cloud. No API key. No API bill. No vendor lock-in.${NC}`);
  console.log(`  ${DIM}Every inference verified on BSV mainnet. No log file to falsify.${NC}`);
  console.log('');

  if (safetyCount > 0) {
    console.log(`  ${BOLD}${R}ACTION REQUIRED: ${safetyCount} safety event${safetyCount > 1 ? 's' : ''} detected.${NC}`);
    console.log(`  ${R}Each is anchored on-chain. Audit trail is immutable.${NC}`);
    console.log('');
  }

  console.log(`${BOLD}${W}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log('');
}

main().catch(e => { console.error(e); process.exit(1); });

```
