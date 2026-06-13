---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/demo/type-fuzzer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.436578+00:00
---

# cartridges/shared/demo/type-fuzzer.ts

```ts
#!/usr/bin/env bun
/**
 * type-fuzzer.ts — typeHash segment routing stress tester
 *
 * Generates cells across the full combinatorial type-path space using the
 * canonical (8|8|8|8) typeHash construction (4 × sha256[0:8] segments).
 *
 * Demonstrates three things simultaneously:
 *   1. Priority routing — relay dispatches high-contract tiers first under load
 *   2. Deduplication — cell-store handles 4096 unique type paths cleanly
 *   3. Throughput ceiling — queue depth vs. ingest rate shows relay headroom
 *
 * typeHash construction (matches cell-anchor.spec.ts buildTestTypeHash):
 *   bytes  0- 7:  sha256(tier)[0:8]       e.g. sha256("inference")[0:8]
 *   bytes  8-15:  sha256(domain)[0:8]     e.g. sha256("access")[0:8]
 *   bytes 16-23:  sha256(verb)[0:8]       e.g. sha256("grant")[0:8]
 *   bytes 24-31:  sha256(qualifier)[0:8]  e.g. sha256("")[0:8]
 *
 * Payment contract matching uses bytes 0-7 (tier prefix) only.
 *
 * Usage:
 *   bun cartridges/shared/demo/type-fuzzer.ts
 *   FUZZ_RATE=200 bun cartridges/shared/demo/type-fuzzer.ts   # cells/sec
 *   FUZZ_RATE=500 FUZZ_SECS=10 bun ...                         # 10s burst
 *   RELAY_URL=http://localhost:5199 bun ...
 */

import { createHash, randomBytes } from 'node:crypto';

// ── Config ────────────────────────────────────────────────────────────────────

const RELAY_URL     = process.env.RELAY_URL   ?? 'http://localhost:5199';
const FUZZ_RATE     = parseInt(process.env.FUZZ_RATE  ?? '50',  10);  // cells/sec
const FUZZ_SECS     = parseInt(process.env.FUZZ_SECS  ?? '0',   10);  // 0 = infinite
const SENDER_HAT    = process.env.FUZZ_HAT    ?? 'type-fuzzer';
const PAYLOAD_BYTES = parseInt(process.env.FUZZ_PAYLOAD ?? '64', 10); // bytes per cell

// ── Type-path combinatorial space ─────────────────────────────────────────────

const TIERS = [
  'ixp', 'dark', 'inference', 'mnca',
  'bsv', 'ipv6', 'p2p', 'compute',
];

const DOMAINS = [
  'route', 'fiber', 'access', 'tile',
  'tx', 'seg', 'peer', 'thread',
];

const VERBS = [
  'accept', 'commit', 'grant', 'tick',
  'broadcast', 'forward', 'hold', 'deny',
];

const QUALIFIERS = [
  '', 'v2', 'fast', 'slow',
  'bulk', 'audit', 'test', 'demo',
];

// Total: 8 × 8 × 8 × 8 = 4,096 distinct type paths
const TOTAL_PATHS = TIERS.length * DOMAINS.length * VERBS.length * QUALIFIERS.length;

function randomTypePath(): { typePath: string; tier: string; domain: string; verb: string; qualifier: string } {
  const tier      = TIERS[Math.floor(Math.random() * TIERS.length)]!;
  const domain    = DOMAINS[Math.floor(Math.random() * DOMAINS.length)]!;
  const verb      = VERBS[Math.floor(Math.random() * VERBS.length)]!;
  const qualifier = QUALIFIERS[Math.floor(Math.random() * QUALIFIERS.length)]!;
  const typePath  = qualifier ? `${tier}.${domain}.${verb}.${qualifier}` : `${tier}.${domain}.${verb}`;
  return { typePath, tier, domain, verb, qualifier };
}

// ── Canonical typeHash (matches buildTestTypeHash in cell-anchor.spec.ts) ─────

function seg8(s: string): Uint8Array {
  return new Uint8Array(createHash('sha256').update(s).digest().buffer).slice(0, 8);
}

function buildTypeHash(tier: string, domain: string, verb: string, qualifier: string): string {
  const out = new Uint8Array(32);
  out.set(seg8(tier),      0);
  out.set(seg8(domain),    8);
  out.set(seg8(verb),     16);
  out.set(seg8(qualifier), 24);
  return Buffer.from(out).toString('hex');
}

// ── Hat fingerprint ────────────────────────────────────────────────────────────

const SENDER_FP = createHash('sha256').update(SENDER_HAT).digest('hex').slice(0, 8);

// ── Payment contracts — colour-coded by sats/cell ─────────────────────────────
// Tier prefix = sha256(tierName)[0:8] as 16-char hex

const PAYMENT_CONTRACTS = [
  { label: 'inference', tierHex: Buffer.from(seg8('inference')).toString('hex'), satsPerCell: 200 },
  { label: 'bsv',       tierHex: Buffer.from(seg8('bsv')).toString('hex'),       satsPerCell: 150 },
  { label: 'ixp',       tierHex: Buffer.from(seg8('ixp')).toString('hex'),       satsPerCell: 100 },
  { label: 'p2p',       tierHex: Buffer.from(seg8('p2p')).toString('hex'),       satsPerCell:  75 },
  { label: 'compute',   tierHex: Buffer.from(seg8('compute')).toString('hex'),   satsPerCell:  60 },
  { label: 'ipv6',      tierHex: Buffer.from(seg8('ipv6')).toString('hex'),      satsPerCell:  40 },
  { label: 'dark',      tierHex: Buffer.from(seg8('dark')).toString('hex'),      satsPerCell:  50 },
  { label: 'mnca',      tierHex: Buffer.from(seg8('mnca')).toString('hex'),      satsPerCell:   5 },
];

function contractFor(typeHashHex: string): { label: string; satsPerCell: number } {
  const tierHex = typeHashHex.slice(0, 16); // first 8 bytes = 16 hex chars
  const c = PAYMENT_CONTRACTS.find(p => p.tierHex === tierHex);
  return c ?? { label: 'default', satsPerCell: 10 };
}

// Export contract table for relay to consume
export { PAYMENT_CONTRACTS };

// ── Stats ──────────────────────────────────────────────────────────────────────

let sent = 0;
let errors = 0;
let totalSats = 0;
const contractCounts: Record<string, number> = {};
const seenTypePaths = new Set<string>();
let seqCounter = 0;

// ── Publish one cell ───────────────────────────────────────────────────────────

async function publishFuzzCell(): Promise<void> {
  const { typePath, tier, domain, verb, qualifier } = randomTypePath();
  const typeHashHex = buildTypeHash(tier, domain, verb, qualifier);
  const contract    = contractFor(typeHashHex);
  const payload     = randomBytes(PAYLOAD_BYTES).toString('hex');
  const payloadBytes = Buffer.from(payload, 'hex');
  const cellId      = createHash('sha256').update(payloadBytes).digest('hex');

  const body = {
    header: {
      cellId,
      typePath,
      typeHash:   typeHashHex,         // 64-hex canonical typeHash
      senderFp:   SENDER_FP,
      seq:        seqCounter++,
      payloadLen: payloadBytes.length,
    },
    payload,
  };

  try {
    const r = await fetch(`${RELAY_URL}/publish`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/json' },
      body:    JSON.stringify(body),
      signal:  AbortSignal.timeout(2000),
    });
    if (r.ok) {
      sent++;
      totalSats += contract.satsPerCell;
      seenTypePaths.add(typePath);
      contractCounts[contract.label] = (contractCounts[contract.label] ?? 0) + 1;
    } else {
      errors++;
    }
  } catch {
    errors++;
  }
}

// ── Main loop ──────────────────────────────────────────────────────────────────

const INTERVAL_MS = Math.max(1, Math.round(1000 / FUZZ_RATE));

console.log('\n╔══════════════════════════════════════════════════════════════╗');
console.log('║  typeHash Segment Routing Fuzzer                             ║');
console.log('║  Layer Collapse — Payment Contract Routing Demo              ║');
console.log('╚══════════════════════════════════════════════════════════════╝\n');
console.log(`  Relay:        ${RELAY_URL}`);
console.log(`  Rate:         ${FUZZ_RATE} cells/sec`);
console.log(`  Payload:      ${PAYLOAD_BYTES} bytes/cell`);
console.log(`  Type space:   ${TOTAL_PATHS} unique paths (8×8×8×8)`);
console.log(`  Sender:       ${SENDER_HAT} (fp=${SENDER_FP})`);
console.log(`  Duration:     ${FUZZ_SECS > 0 ? `${FUZZ_SECS}s` : 'until Ctrl+C'}\n`);

// Print contract table
console.log('  Payment Contracts (tier → sats/cell):');
for (const c of PAYMENT_CONTRACTS) {
  const prefix = c.tierHex.slice(0, 8) + '…'; // first 4 bytes displayed
  console.log(`    ${c.label.padEnd(12)} sha256("${c.label}")[0:8] = ${prefix}  → ${String(c.satsPerCell).padStart(3)} sats/cell`);
}
console.log();

const startTs = Date.now();
let lastPrintTs = Date.now();
let lastSent = 0;

const timer = setInterval(async () => {
  await publishFuzzCell();

  const now = Date.now();
  if (now - lastPrintTs >= 1000) {
    const elapsed    = (now - startTs) / 1000;
    const rate       = (sent - lastSent);
    lastSent         = sent;
    lastPrintTs      = now;

    const topContracts = Object.entries(contractCounts)
      .sort(([, a], [, b]) => b - a)
      .slice(0, 4)
      .map(([l, n]) => `${l}:${n}`)
      .join('  ');

    process.stdout.write(
      `\r  t=${elapsed.toFixed(0)}s  sent=${sent}  err=${errors}  `      +
      `rate=${rate}/s  paths=${seenTypePaths.size}/${TOTAL_PATHS}  `     +
      `sats=${totalSats.toLocaleString()}  top: ${topContracts}  `
    );

    if (FUZZ_SECS > 0 && elapsed >= FUZZ_SECS) {
      clearInterval(timer);
      printSummary();
      process.exit(0);
    }
  }
}, INTERVAL_MS);

function printSummary() {
  const elapsed = (Date.now() - startTs) / 1000;
  console.log('\n\n  ── Fuzz Summary ─────────────────────────────────────────────');
  console.log(`  Duration:     ${elapsed.toFixed(1)}s`);
  console.log(`  Total sent:   ${sent}  (${(sent / elapsed).toFixed(0)} cells/sec avg)`);
  console.log(`  Errors:       ${errors}`);
  console.log(`  Unique paths: ${seenTypePaths.size} / ${TOTAL_PATHS} (${(seenTypePaths.size / TOTAL_PATHS * 100).toFixed(1)}% coverage)`);
  console.log(`  Total sats:   ${totalSats.toLocaleString()} routed value`);
  console.log('\n  Contract distribution:');
  for (const [label, count] of Object.entries(contractCounts).sort(([, a], [, b]) => b - a)) {
    const contract = PAYMENT_CONTRACTS.find(c => c.label === label) ?? { satsPerCell: 10 };
    const sats = count * contract.satsPerCell;
    const pct  = (count / sent * 100).toFixed(1);
    console.log(`    ${label.padEnd(12)} ${String(count).padStart(6)} cells  ${String(sats).padStart(9)} sats  (${pct}%)`);
  }
  console.log();
}

process.on('SIGINT', () => { clearInterval(timer); printSummary(); process.exit(0); });

```
