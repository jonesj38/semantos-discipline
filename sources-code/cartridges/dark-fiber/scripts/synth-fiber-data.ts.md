---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/scripts/synth-fiber-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.421633+00:00
---

# cartridges/dark-fiber/scripts/synth-fiber-data.ts

```ts
#!/usr/bin/env bun
// Synthesise a 30-day dark fiber utilization + bid stream.
//
// Simulates EU Networks long-haul wavelength utilization on a realistic
// pattern:
//   • Diurnal: low utilization overnight (30-45%), builds through morning
//     (55-65%), peaks midday/early-afternoon (70-85%), evening plateau,
//     then drops.
//   • Weekly: weekends ~15% lower utilization across all hours.
//   • AI training burst events: 3-5 random multi-hour episodes where
//     demand spikes 20%+ and bids jump 2-3× — simulating a hyperscaler
//     kicking off a large model training run.
//   • Base bids track utilization loosely with noise: low util → low bids,
//     high util → higher bids.  Bursts spike bids independently.
//
// Output: CSV to stdout — timestamp,utilizationPct,bidCentsPerGbps,demandGbps
// (8,640 rows per 30 days at 5-min resolution)
//
// Usage:
//   bun scripts/synth-fiber-data.ts --days 30 --seed 42 > fiber-30d.csv

interface Args {
  days: number;
  seed: number;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { days: 30, seed: 42 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--days') a.days = Number.parseInt(argv[++i] ?? '30', 10);
    else if (argv[i] === '--seed') a.seed = Number.parseInt(argv[++i] ?? '42', 10);
  }
  return a;
}

// Deterministic PRNG — same seed always produces the same stream.
function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function main(): void {
  const args = parseArgs(process.argv.slice(2));
  const rng = mulberry32(args.seed);
  const intervalsPerDay = 24 * 12; // 5-min bars per day
  const totalIntervals = args.days * intervalsPerDay;

  // Pre-select AI training burst windows (3-5 events, each 2-6 hours long).
  const numBursts = 3 + Math.floor(rng() * 3); // 3..5
  const bursts: Array<{ start: number; end: number }> = [];
  for (let b = 0; b < numBursts; b++) {
    const startInterval = Math.floor(rng() * (totalIntervals - 72)); // not in last 6h
    const durationIntervals = 24 + Math.floor(rng() * 48); // 2h..6h in 5-min bars
    bursts.push({ start: startInterval, end: startInterval + durationIntervals });
  }

  function isBurst(i: number): boolean {
    return bursts.some(b => i >= b.start && i < b.end);
  }

  console.log('timestamp,utilizationPct,bidCentsPerGbps,demandGbps');

  // Epoch: 2026-01-01 00:00 UTC — a 30-day window of spot market data.
  const baseTs = Date.UTC(2026, 0, 1, 0, 0, 0);
  // Total link capacity for this route (e.g., 4×100 Gbps DWDM = 400 Gbps).
  const TOTAL_CAPACITY_GBPS = 400;

  for (let i = 0; i < totalIntervals; i++) {
    const tsMs = baseTs + i * 5 * 60 * 1000;
    const iso = new Date(tsMs).toISOString();
    const hourOfDay = ((tsMs / 3600000) % 24 + 24) % 24;
    const dayOfWeek = new Date(tsMs).getUTCDay(); // 0=Sun, 6=Sat
    const isWeekend = dayOfWeek === 0 || dayOfWeek === 6;

    // ── Diurnal utilization baseline (%) ──────────────────────────────
    let baseUtil: number;
    if (hourOfDay >= 0 && hourOfDay < 5) {
      // Deep overnight: minimal contracted traffic
      baseUtil = 30 + rng() * 15; // 30-45%
    } else if (hourOfDay >= 5 && hourOfDay < 8) {
      // Pre-market ramp
      baseUtil = 45 + ((hourOfDay - 5) / 3) * 20 + rng() * 8; // 45→65%
    } else if (hourOfDay >= 8 && hourOfDay < 13) {
      // Business hours — peak
      baseUtil = 65 + rng() * 20; // 65-85%
    } else if (hourOfDay >= 13 && hourOfDay < 18) {
      // Afternoon plateau — slightly lower than peak
      baseUtil = 60 + rng() * 18; // 60-78%
    } else if (hourOfDay >= 18 && hourOfDay < 22) {
      // Evening ramp down
      baseUtil = 50 - ((hourOfDay - 18) / 4) * 20 + rng() * 12; // 50→30%
    } else {
      // Late evening
      baseUtil = 35 + rng() * 12; // 35-47%
    }

    // Weekend discount: ~15% lower utilization
    if (isWeekend) baseUtil *= 0.85;

    // ── AI training burst overlay ──────────────────────────────────────
    let burstMultiplier = 1.0;
    let burstBidMultiplier = 1.0;
    if (isBurst(i)) {
      burstMultiplier = 1.2 + rng() * 0.25;    // +20..+45% utilization
      burstBidMultiplier = 2.0 + rng() * 1.5;   // 2×..3.5× bid spike
    }

    const utilizationPct = Math.min(98, Math.max(5, Math.round(baseUtil * burstMultiplier)));

    // ── Demand (Gbps) — derived from utilization ──────────────────────
    const demandGbps = Math.round(utilizationPct / 100 * TOTAL_CAPACITY_GBPS);

    // ── Bid (€-cents per Gbps-hr) ─────────────────────────────────────
    // Base bid loosely tracks utilization: higher util = tighter supply = higher bids.
    // Range: 150-300 base, spikes to 400-800 during bursts.
    let baseBid: number;
    if (utilizationPct < 40) {
      baseBid = 150 + rng() * 80; // 150-230
    } else if (utilizationPct < 60) {
      baseBid = 200 + rng() * 100; // 200-300
    } else if (utilizationPct < 75) {
      baseBid = 250 + rng() * 100; // 250-350
    } else {
      baseBid = 300 + rng() * 150; // 300-450 at high utilization
    }

    const bidCentsPerGbps = Math.round(baseBid * burstBidMultiplier);

    console.log(`${iso},${utilizationPct},${bidCentsPerGbps},${demandGbps}`);
  }
}

main();

```
