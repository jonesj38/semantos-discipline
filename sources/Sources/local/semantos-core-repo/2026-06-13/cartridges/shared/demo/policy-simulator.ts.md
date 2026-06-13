---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/demo/policy-simulator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.436302+00:00
---

# cartridges/shared/demo/policy-simulator.ts

```ts
#!/usr/bin/env bun
/**
 * policy-simulator.ts — Synthetic policy event generator for layer-collapse demo
 *
 * Fires a mix of all six infra-demo event types at a configurable rate so
 * the Cell Mesh panel on every dashboard shows diverse traffic alongside the
 * MNCA tile cells.  Uses the legacy /publish format so no funded channel is
 * needed (same as direct dashboard clicks).
 *
 * Usage:
 *   DEMO_MODE=true bun cartridges/shared/demo/policy-simulator.ts
 *   RATE=0.5 bun cartridges/shared/demo/policy-simulator.ts   # 0.5 events/sec
 *   RELAY_URL=http://192.168.20.5:5199 bun ...
 */

const RELAY_URL = process.env.RELAY_URL ?? 'http://localhost:5199';
const RATE      = parseFloat(process.env.RATE ?? '0.3');   // events/sec (avg)
const INTERVAL  = 1000 / RATE;                             // ms between events

// ── Event templates ───────────────────────────────────────────────────────────

interface PolicyEvent {
  typePath: string;
  hat:      string;
  inputs:   () => Record<string, unknown>;
}

const EVENTS: PolicyEvent[] = [
  {
    typePath: 'ixp.route.accept',
    hat:      'ixp-ams-noc',
    inputs:   () => ({
      prefix: `185.${rnd(1,255)}.${rnd(0,255)}.0/24`,
      asPath: [rnd(1000, 65000), rnd(1000, 65000)],
      metric: rnd(10, 200),
    }),
  },
  {
    typePath: 'ixp.route.reject',
    hat:      'ixp-ams-noc',
    inputs:   () => ({
      prefix: `45.${rnd(1,255)}.${rnd(0,255)}.0/24`,
      reason: pick(['bogon', 'invalid-origin', 'rpki-invalid', 'policy-denied']),
    }),
  },
  {
    typePath: 'dark.fiber.commit',
    hat:      'dark-fiber-ops',
    inputs:   () => ({
      linkId: `DF-${rnd(100,999)}`,
      capacityGbps: pick([10, 40, 100, 400]),
      latencyUs: rnd(50, 2000),
    }),
  },
  {
    typePath: 'dark.fiber.hold',
    hat:      'dark-fiber-ops',
    inputs:   () => ({
      linkId: `DF-${rnd(100,999)}`,
      reason: pick(['maintenance', 'capacity-limit', 'dispute', 'policy']),
    }),
  },
  {
    typePath: 'inference.access.grant',
    hat:      'inference-gate-ai',
    inputs:   () => ({
      modelId: pick(['gpt-4o', 'claude-3-5', 'gemini-pro', 'llama-3']),
      tier:    pick([0, 1, 2, 3]),
      tokensPerMin: rnd(1000, 100000),
    }),
  },
  {
    typePath: 'inference.access.deny',
    hat:      'inference-gate-ai',
    inputs:   () => ({
      modelId: pick(['gpt-4o', 'claude-3-5']),
      reason:  pick(['rate-limit', 'insufficient-tier', 'policy', 'quota-exceeded']),
    }),
  },
];

function rnd(lo: number, hi: number): number {
  return Math.floor(Math.random() * (hi - lo + 1)) + lo;
}
function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)]!;
}

// ── Weighted selection — accepts 4× more than rejects for realism ─────────────
const WEIGHTED: PolicyEvent[] = [
  ...EVENTS,
  EVENTS[0]!, EVENTS[0]!, EVENTS[2]!, EVENTS[4]!,  // extra accepts/grants/commits
];

// ── Main loop ─────────────────────────────────────────────────────────────────

let sentCount  = 0;
let errorCount = 0;

console.log(`\n[policy-sim] relay=${RELAY_URL}  rate=${RATE} events/sec`);
console.log(`[policy-sim] Press Ctrl+C to stop\n`);

// Health check
try {
  const r = await fetch(`${RELAY_URL}/health`, { signal: AbortSignal.timeout(2000) });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  console.log('[policy-sim] ✓ relay online');
} catch (e: any) {
  console.error(`[policy-sim] ✗ relay offline: ${e.message}`);
  process.exit(1);
}

async function fireEvent(): Promise<void> {
  const ev  = pick(WEIGHTED);
  const body = {
    typePath: ev.typePath,
    verdict:  !ev.typePath.endsWith('.reject') &&
              !ev.typePath.endsWith('.deny') &&
              !ev.typePath.endsWith('.hold'),
    inputs:   ev.inputs(),
    hat:      ev.hat,
  };
  const r = await fetch(`${RELAY_URL}/publish`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(body),
    signal:  AbortSignal.timeout(1500),
  });
  if (!r.ok && r.status !== 402) throw new Error(`HTTP ${r.status}`);
  sentCount++;
  const j = await r.json() as { shortGroup?: string };
  const grp = j.shortGroup ?? '?';
  process.stdout.write(`\r[policy-sim] sent=${sentCount} errors=${errorCount}  last: ${ev.typePath.padEnd(28)} → ${grp}  `);
}

// Jitter ±30% so the events don't feel robotic (clamped to ≥0)
setInterval(async () => {
  const jitter = INTERVAL * 0.3;
  const delay  = Math.max(0, Math.random() * jitter * 2 - jitter);
  await new Promise(r => setTimeout(r, delay));
  try {
    await fireEvent();
  } catch (e: any) {
    errorCount++;
    if (errorCount % 10 === 1)
      process.stdout.write(`\n[policy-sim] error: ${e.message}\n`);
  }
}, INTERVAL);

process.on('SIGINT', () => {
  console.log(`\n\n[policy-sim] Done.  sent=${sentCount}  errors=${errorCount}`);
  process.exit(0);
});

```
