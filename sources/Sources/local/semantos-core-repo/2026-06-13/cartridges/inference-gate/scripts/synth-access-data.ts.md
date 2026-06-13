---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/synth-access-data.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.419263+00:00
---

# cartridges/inference-gate/scripts/synth-access-data.ts

```ts
#!/usr/bin/env bun
// Synthetic access-request data generator for the Inference Gateway demo.
//
// Produces a CSV of simulated enterprise AI-inference access requests
// spanning N days, with realistic business-hours skew, identity-tier
// distribution, and data-classification distribution.
//
// Output: timestamp,requestId,certTier,dataClass,identityLabel,resourceLabel
//
// certTier:  0=none (anonymous/bot), 1=basic, 2=enterprise, 3=sovereign
// dataClass: 0=public, 1=internal, 2=confidential, 3=restricted
//
// Usage:
//   bun synth-access-data.ts --days 7 --seed 42 > access-requests.csv
//   bun synth-access-data.ts --days 14 --seed 99 --out /tmp/access.csv

import { promises as fs } from 'fs';

// ─────────────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────────────

interface Args {
  days: number;
  seed: number;
  out: string | null;
  help: boolean;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { days: 7, seed: 42, out: null, help: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--days') a.days = Number.parseInt(argv[++i] ?? '7', 10);
    else if (arg === '--seed') a.seed = Number.parseInt(argv[++i] ?? '42', 10);
    else if (arg === '--out') a.out = argv[++i] ?? null;
    else if (arg === '--help' || arg === '-h') a.help = true;
    else { console.error(`unknown arg: ${arg}`); process.exit(2); }
  }
  return a;
}

// ─────────────────────────────────────────────────────────────────────
// Seeded PRNG (mulberry32 — deterministic, good enough for demo data)
// ─────────────────────────────────────────────────────────────────────

function mulberry32(seed: number): () => number {
  let s = seed >>> 0;
  return function () {
    s += 0x6d2b79f5;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 0x100000000;
  };
}

// ─────────────────────────────────────────────────────────────────────
// Identity + resource labels
// ─────────────────────────────────────────────────────────────────────

const TIER_LABELS: Record<number, string[]> = {
  0: ['bot-crawler-7f', 'anon-scraper-9c', 'unauthenticated', 'probe-3a1b', 'bot-monitor-c2'],
  1: ['alice.chen@basiccorp.io', 'bob.smith@trial.ai', 'carol.jones@freemium.net',
      'dave.liu@starter.io', 'erin.vance@basic.org', 'frank.kim@lite.ai'],
  2: ['svc-mlops@megatech.com', 'dr.rivera@lifesciences.eu', 'quant-team@hedgeco.io',
      'platform-api@bigpharma.com', 'model-infra@finserv.com', 'analytics@enterprise.io',
      'data-eng@insurance.com', 'research-bot@university.edu'],
  3: ['treasury@centralbank.gov', 'classified-ops@defence.gov.au',
      'audit-suite@regulator.gov', 'admin@sovereign-health.gov'],
};

const RESOURCE_LABELS: Record<number, string[]> = {
  0: ['marketing-faq.txt', 'public-brochure.pdf', 'open-dataset-v2.parquet', 'product-specs.json'],
  1: ['employee-handbook.docx', 'internal-pricing-v3.xlsx', 'q2-roadmap-draft.pdf',
      'api-schema-internal.yaml', 'vendor-list-2026.csv'],
  2: ['patient-cohort-2024.parquet', 'drug-trial-interim-results.xlsx',
      'ip-portfolio-valuation.pdf', 'm-and-a-target-analysis.pdf',
      'model-weights-proprietary.safetensors', 'financial-model-v7.xlsx'],
  3: ['patient-records-restricted/batch-7f.parquet', 'classified-intelligence-brief.pdf',
      'sovereign-treasury-model.xlsx', 'genetic-database-restricted.parquet'],
};

function pickLabel(rand: () => number, labels: string[]): string {
  return labels[Math.floor(rand() * labels.length)]!;
}

// ─────────────────────────────────────────────────────────────────────
// Request ID generation
// ─────────────────────────────────────────────────────────────────────

function makeRequestId(rand: () => number): string {
  const hex = () => Math.floor(rand() * 256).toString(16).padStart(2, '0');
  return `req-${hex()}${hex()}${hex()}${hex()}`;
}

// ─────────────────────────────────────────────────────────────────────
// Business-hours skew: hour 0..23 → weight (higher = more requests)
// Peak is 9-17, minimal overnight
// ─────────────────────────────────────────────────────────────────────

const HOUR_WEIGHTS = [
  0.05, 0.03, 0.02, 0.02, 0.03, 0.06, // 0–5  (overnight)
  0.12, 0.25, 0.45, 0.70, 0.90, 0.95, // 6–11 (morning ramp)
  0.95, 0.98, 1.00, 0.97, 0.95, 0.85, // 12–17 (business hours peak)
  0.70, 0.55, 0.40, 0.25, 0.15, 0.08, // 18–23 (evening wind-down)
];

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('usage: bun synth-access-data.ts [--days 7] [--seed 42] [--out <path>]');
    console.log('output: timestamp,requestId,certTier,dataClass,identityLabel,resourceLabel');
    process.exit(0);
  }

  const rand = mulberry32(args.seed);

  // certTier distribution: 0→10%, 1→40%, 2→35%, 3→15%
  const TIER_CUMULATIVES = [0.10, 0.50, 0.85, 1.00];
  // dataClass distribution: 0→30%, 1→35%, 2→25%, 3→10%
  const CLASS_CUMULATIVES = [0.30, 0.65, 0.90, 1.00];

  function pickTier(r: number): number {
    for (let i = 0; i < TIER_CUMULATIVES.length; i++) {
      if (r < TIER_CUMULATIVES[i]!) return i;
    }
    return 3;
  }

  function pickClass(r: number): number {
    for (let i = 0; i < CLASS_CUMULATIVES.length; i++) {
      if (r < CLASS_CUMULATIVES[i]!) return i;
    }
    return 3;
  }

  // We bias: tier-1 requesting restricted is an "attempted breach" pattern.
  // We deliberately inject these at a slightly elevated rate to make the
  // demo story visible.  The predicate catches them; they become "prevented breaches".
  function pickTierBiased(dataClass: number, r: number): number {
    // If dataClass is restricted, bump chance of a tier-1 attempt by 8%
    if (dataClass === 3 && r < 0.08) return 1;
    return pickTier(r);
  }

  // Average 300 requests/day with ±100 variance.
  const BASE_REQ_PER_DAY = 300;

  const startDate = new Date('2026-05-19T00:00:00.000Z');
  const lines: string[] = ['timestamp,requestId,certTier,dataClass,identityLabel,resourceLabel'];

  for (let day = 0; day < args.days; day++) {
    // Daily count with some variance (±100).
    const dailyCount = Math.max(
      50,
      BASE_REQ_PER_DAY + Math.floor((rand() - 0.5) * 200),
    );

    const dayMs = startDate.getTime() + day * 86400_000;

    // Spread requests across hours using the weight distribution.
    // Generate (hour, minute, second) for each request proportional to weight.
    for (let req = 0; req < dailyCount; req++) {
      // Pick a weighted hour.
      const hourRoll = rand();
      const totalWeight = HOUR_WEIGHTS.reduce((a, b) => a + b, 0);
      let cumulativeWeight = 0;
      let hour = 0;
      for (let h = 0; h < 24; h++) {
        cumulativeWeight += HOUR_WEIGHTS[h]! / totalWeight;
        if (hourRoll < cumulativeWeight) { hour = h; break; }
      }
      const minute = Math.floor(rand() * 60);
      const second = Math.floor(rand() * 60);
      const ms = Math.floor(rand() * 1000);

      const ts = new Date(dayMs + hour * 3600_000 + minute * 60_000 + second * 1000 + ms);
      const timestamp = ts.toISOString();

      // Pick data class first, then tier (allows bias injection).
      const dataClass = pickClass(rand());
      const certTier = pickTierBiased(dataClass, rand());

      const identityLabel = pickLabel(rand, TIER_LABELS[certTier]!);
      const resourceLabel = pickLabel(rand, RESOURCE_LABELS[dataClass]!);
      const requestId = makeRequestId(rand);

      lines.push(`${timestamp},${requestId},${certTier},${dataClass},${identityLabel},${resourceLabel}`);
    }
  }

  // Sort by timestamp ascending (within a day generation is approximately sorted but not exactly).
  const header = lines[0]!;
  const dataLines = lines.slice(1).sort();
  const output = [header, ...dataLines].join('\n') + '\n';

  if (args.out) {
    await fs.writeFile(args.out, output, 'utf-8');
    console.error(`[synth] wrote ${dataLines.length} rows to ${args.out}`);
  } else {
    process.stdout.write(output);
  }
}

await main();

```
