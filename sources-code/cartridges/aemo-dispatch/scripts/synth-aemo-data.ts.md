---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/synth-aemo-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.572274+00:00
---

# cartridges/aemo-dispatch/scripts/synth-aemo-data.ts

```ts
#!/usr/bin/env bun
// Synthesise a price stream that looks like AEMO 5-min NEM data.
//
// Why synthetic first: real AEMO archive CSVs are tens of GB and
// require staged download.  A synthetic stream with realistic
// statistics (diurnal cycle + evening price spikes + occasional
// scarcity events) lets us prove the backtest pipe end-to-end before
// pulling real data.  Replace this with an AEMO scraper in a
// follow-up PR.
//
// Stats this synth captures:
//   • Diurnal: low overnight ($30-80/MWh), morning ramp, midday solar
//     trough, evening peak ($150-300+/MWh).
//   • Scarcity spikes: random intervals where price jumps to
//     $500-15000/MWh for 1-3 bars.
//   • Negative pricing: occasional bars during high solar where price
//     goes to -$100/MWh or so (curtailment incentive).
//
// Output: CSV to stdout — `timestamp,priceCents`
//
// Usage:
//   bun scripts/synth-aemo-data.ts --days 7 --seed 42 > synthetic.csv

interface Args {
  days: number;
  seed: number;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { days: 7, seed: 42 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--days') a.days = Number.parseInt(argv[++i] ?? '7', 10);
    else if (argv[i] === '--seed') a.seed = Number.parseInt(argv[++i] ?? '42', 10);
  }
  return a;
}

// Deterministic PRNG so the same seed reproduces the same data.
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
  const intervalsPerDay = 24 * 12; // 5-min bars
  const totalIntervals = args.days * intervalsPerDay;

  console.log('timestamp,priceCents');
  const baseTs = Date.UTC(2024, 0, 1, 0, 0, 0);
  for (let i = 0; i < totalIntervals; i++) {
    const tsMs = baseTs + i * 5 * 60 * 1000;
    const iso = new Date(tsMs).toISOString();
    const hourOfDay = (tsMs / 3600000) % 24;

    // Diurnal baseline in $/MWh.
    let base = 80; // overnight
    if (hourOfDay >= 6 && hourOfDay < 9) base = 120; // morning ramp
    else if (hourOfDay >= 9 && hourOfDay < 16) base = 50; // solar trough
    else if (hourOfDay >= 16 && hourOfDay < 21) base = 200; // evening peak
    else if (hourOfDay >= 21 || hourOfDay < 1) base = 100; // ramp down

    // Random noise ±30%.
    base *= 1 + (rng() - 0.5) * 0.6;

    // Scarcity spike: 0.4% of intervals jump to $1k-15k/MWh.
    if (rng() < 0.004) base = 1000 + rng() * 14000;

    // Negative pricing during solar trough: ~5% chance of -$50/MWh.
    if (hourOfDay >= 10 && hourOfDay < 14 && rng() < 0.05) base = -50 + rng() * 30;

    const priceCents = Math.round(base * 100);
    console.log(`${iso},${priceCents}`);
  }
}

main();

```
