---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/ixp-routing/scripts/backtest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.559359+00:00
---

# cartridges/ixp-routing/scripts/backtest.ts

```ts
#!/usr/bin/env bun
// IXP BGP route-acceptance backtest harness.
//
// Replays a BGP route advertisement event stream through a Rúnar-compiled
// route-acceptance predicate (loaded from the cartridge's hex golden) and
// measures routing efficiency: recall on legitimate routes, precision on
// attack patterns, and the number of prevented BGP hijack incidents.
//
// What "routing efficiency" means:
//   accepted_legit ÷ total_legit_routes  (recall — we want this high)
//   blocked_attacks ÷ total_attacks      (attack block rate — we want this high)
//   false_blocks = legit routes blocked  (we want this 0 or minimal)
//
// What the harness PROVES (when it runs):
//   • The same Rúnar-compiled hex the brain would execute on chain
//     produces the same route-accept/reject decisions during backtest.
//   • The decision trail is deterministic — same input always produces
//     the same routing outcomes.
//   • The strategy's security posture (recall vs precision tradeoff) is
//     measurable.  route_accept is strict + zero false-positives.
//     tier_prefix_product is flexible + ~85% attack block rate.
//
// What the harness DOES NOT PROVE:
//   • Real BGP stability or convergence time.
//   • MRAI (Minimum Route Advertisement Interval) compliance.
//   • Actual traffic impact of accepting vs rejecting a route.
//   • Real IXP operational constraints (route server policy, RPKI validation,
//     IRR filtering — these layer on top of this predicate, not replace it).
//
// Inputs:
//   --data <csv>          Path to CSV with timestamp,eventId,asnTier,prefixLen,asn,prefix,peerLabel
//                         (generate with: bun scripts/synth-bgp-data.ts > bgp-events.csv)
//   --strategy <name>     "route_accept" (default) or "tier_prefix_product"
//   --anchor-summary      Anchor a SHA-256 commitment of this run to BSV mainnet
//
// Output:
//   JSON summary: total events, accepted/rejected counts, efficiency metrics,
//   attack blocks vs false blocks, per-incident-window breakdown.

import { promises as fs } from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { execute, pushSmallInt, hexToBytes, concat } from './script-interpreter';

// ─────────────────────────────────────────────────────────────────────
// CLI parsing
// ─────────────────────────────────────────────────────────────────────

type StrategyName = 'route_accept' | 'tier_prefix_product';

const RUNAR_STRATEGIES: StrategyName[] = ['route_accept', 'tier_prefix_product'];

interface Args {
  dataPath: string;
  strategy: StrategyName;
  anchorSummary: boolean;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { dataPath: '', strategy: 'route_accept', anchorSummary: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--data') a.dataPath = argv[++i] ?? '';
    else if (arg === '--strategy') a.strategy = (argv[++i] ?? 'route_accept') as StrategyName;
    else if (arg === '--anchor-summary') a.anchorSummary = true;
    else if (arg === '--help' || arg === '-h') {
      console.error('usage: bun backtest.ts --data <csv> [--strategy <name>] [--anchor-summary]');
      console.error(`strategies: ${RUNAR_STRATEGIES.join(', ')}`);
      console.error('--anchor-summary anchors a SHA-256 commitment of this run on BSV mainnet');
      process.exit(0);
    } else {
      console.error(`unknown arg: ${arg}`);
      process.exit(2);
    }
  }
  if (!a.dataPath) {
    console.error('--data <csv> required');
    process.exit(2);
  }
  return a;
}

// ─────────────────────────────────────────────────────────────────────
// Data
// ─────────────────────────────────────────────────────────────────────

interface Row {
  timestamp: string;
  eventId: string;
  asnTier: number;     // 0-3
  prefixLen: number;   // 8-32
  asn: string;
  prefix: string;
  peerLabel: string;
}

async function readCsv(p: string): Promise<Row[]> {
  const text = await fs.readFile(p, 'utf-8');
  const rows: Row[] = [];
  const lines = text.split(/\r?\n/).filter(l => l.length > 0 && !l.startsWith('#'));
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i]!.split(',');
    if (parts.length < 7) continue;
    const asnTier = Number.parseInt(parts[2]!, 10);
    const prefixLen = Number.parseInt(parts[3]!, 10);
    if (!Number.isFinite(asnTier) || !Number.isFinite(prefixLen)) continue; // skip header
    rows.push({
      timestamp: parts[0]!,
      eventId: parts[1]!,
      asnTier,
      prefixLen,
      asn: parts[4]!,
      prefix: parts[5]!,
      peerLabel: parts[6]!,
    });
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────
// Strategy: Rúnar-compiled predicate evaluation
// ─────────────────────────────────────────────────────────────────────

async function loadStrategyHex(name: string): Promise<Uint8Array> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const hexPath = path.join(here, '..', 'strategies', `${name}.expected.hex`);
  const raw = await fs.readFile(hexPath, 'utf-8');
  return hexToBytes(raw);
}

/** Build `OP_PUSH(asnTier) || OP_PUSH(prefixLen) || <predicate>` and
 *  execute via the local Bitcoin Script interpreter.  Returns the
 *  predicate's accept/reject + the opcount (gas equivalent).
 *
 *  Stack convention matches what the brain would produce:
 *    - asnTier pushed first (lower on stack)
 *    - prefixLen pushed second (higher on stack / top) */
function evaluatePredicate(
  predicateHex: Uint8Array,
  asnTier: number,
  prefixLen: number,
): { ok: boolean; opcount: number } {
  const script = concat(
    pushSmallInt(asnTier),
    pushSmallInt(prefixLen),
    predicateHex,
  );
  const r = execute(script);
  return { ok: r.ok, opcount: r.opcount };
}

// ─────────────────────────────────────────────────────────────────────
// Attack pattern classification
// (mirrors the incident-window logic in synth-bgp-data.ts)
// ─────────────────────────────────────────────────────────────────────

/** BGP hijack pattern: tier-0 peer advertising a super-aggregate (/8-/15). */
function isAttackPattern(row: Row): boolean {
  return row.asnTier === 0 && row.prefixLen <= 15;
}

/** Legitimate route: registered peer (tier ≥ 1) with non-super-aggregate prefix. */
function isLegitimateLegit(row: Row): boolean {
  return row.asnTier >= 1 && row.prefixLen >= 16;
}

// ─────────────────────────────────────────────────────────────────────
// Incident window detection (same fractions as synth-bgp-data.ts)
// ─────────────────────────────────────────────────────────────────────

const INCIDENT_WINDOWS = [
  { startFrac: 0.08, endFrac: 0.11, label: '2am-UTC (overnight)' },
  { startFrac: 0.38, endFrac: 0.41, label: '9am-UTC (morning peak)' },
  { startFrac: 0.74, endFrac: 0.77, label: '5:45pm-UTC (EOD)' },
];

const DAY_START_MS = Date.UTC(2026, 0, 15, 0, 0, 0);
const DAY_MS = 24 * 60 * 60 * 1000;

function rowIncidentIdx(row: Row): number {
  const tsMs = new Date(row.timestamp).getTime();
  const frac = (tsMs - DAY_START_MS) / DAY_MS;
  for (let i = 0; i < INCIDENT_WINDOWS.length; i++) {
    const w = INCIDENT_WINDOWS[i]!;
    if (frac >= w.startFrac && frac < w.endFrac) return i;
  }
  return -1;
}

// ─────────────────────────────────────────────────────────────────────
// Anchor helpers (same pattern as aemo-dispatch)
// ─────────────────────────────────────────────────────────────────────

async function readFileSha256(p: string): Promise<string> {
  const buf = await fs.readFile(p);
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function objectSha256(obj: object): string {
  return crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex');
}

function composeAnchorContext(
  strategyHexHex: string,
  dataSha256Hex: string,
  resultSha256Hex: string,
): { cellHashHex: string; typeHashHex: string } {
  const tripleHex = strategyHexHex + dataSha256Hex + resultSha256Hex;
  const cellHashHex = crypto.createHash('sha256').update(Buffer.from(tripleHex, 'hex')).digest('hex');
  const typeHashHex = crypto.createHash('sha256').update('ixp-routing.backtest.v1').digest('hex');
  return { cellHashHex, typeHashHex };
}

async function anchorViaFlushScript(
  cellHashHex: string,
  typeHashHex: string,
): Promise<string | null> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const flushScript = path.resolve(here, '..', '..', 'wallet-headers', 'brain', 'scripts', 'flush-anchor-once.ts');
  try {
    await fs.access(flushScript);
  } catch {
    console.error(`[anchor] flush-anchor-once.ts not found at: ${flushScript}`);
    return null;
  }
  console.error(`[anchor] cell_hash:  ${cellHashHex}`);
  console.error(`[anchor] type_hash:  ${typeHashHex}`);
  console.error(`[anchor] invoking flush-anchor-once.ts...`);

  const proc = Bun.spawn(
    ['bun', flushScript, cellHashHex, typeHashHex, '--cartridge-id', 'ixp-routing', '--entity-tag', '22'],
    { env: { ...process.env }, stdout: 'pipe', stderr: 'pipe' },
  );
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  await proc.exited;
  if (proc.exitCode !== 0) {
    console.error(`[anchor] flush failed (exit ${proc.exitCode}):\n${stderr}`);
    return null;
  }
  const txid = stdout.trim();
  if (!/^[0-9a-f]{64}$/.test(txid)) {
    console.error(`[anchor] expected 64-hex txid on stdout; got: ${txid}`);
    return null;
  }
  return txid;
}

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  const rows = await readCsv(args.dataPath);
  if (rows.length === 0) { console.error('no data rows read'); return 1; }

  console.error(`[backtest] strategy:     ${args.strategy}`);
  console.error(`[backtest] data rows:    ${rows.length}`);

  const predicate = await loadStrategyHex(args.strategy);
  const hexStr = Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('');
  console.error(`[backtest] predicate:    ${predicate.length} bytes (${hexStr})`);

  // Aggregate counters
  let totalAccepted = 0;
  let totalRejected = 0;
  let attacksBlocked = 0;
  let attacksPassed = 0;
  let legitAccepted = 0;
  let legitBlocked = 0;   // false-positives: legitimate route blocked
  let ambiguousAccepted = 0; // tier-0 with specific prefix (not super-aggregate)
  let ambiguousBlocked = 0;

  // Per-incident counters
  const incidentStats = INCIDENT_WINDOWS.map((w, i) => ({
    label: w.label,
    attacks: 0,
    blocked: 0,
    passed: 0,
    false_blocks: 0,
  }));

  for (const row of rows) {
    const { ok } = evaluatePredicate(predicate, row.asnTier, row.prefixLen);

    if (ok) totalAccepted++; else totalRejected++;

    const isAttack = isAttackPattern(row);
    const isLegit = isLegitimateLegit(row);
    const incIdx = rowIncidentIdx(row);

    if (isAttack) {
      if (!ok) attacksBlocked++; else attacksPassed++;
      if (incIdx >= 0) {
        incidentStats[incIdx]!.attacks++;
        if (!ok) incidentStats[incIdx]!.blocked++;
        else incidentStats[incIdx]!.passed++;
      }
    } else if (isLegit) {
      if (ok) legitAccepted++; else {
        legitBlocked++;
        if (incIdx >= 0) incidentStats[incIdx]!.false_blocks++;
      }
    } else {
      // Ambiguous: tier-0 with specific prefix, or tier≥1 with super-aggregate
      if (ok) ambiguousAccepted++; else ambiguousBlocked++;
    }
  }

  const totalAttacks = attacksBlocked + attacksPassed;
  const totalLegit = legitAccepted + legitBlocked;
  const attackBlockRate = totalAttacks > 0 ? attacksBlocked / totalAttacks : 0;
  const routingEfficiency = totalLegit > 0 ? legitAccepted / totalLegit : 0;

  const summary: Record<string, unknown> = {
    strategy: args.strategy,
    strategy_hex: hexStr,
    rows_processed: rows.length,
    totals: {
      accepted: totalAccepted,
      rejected: totalRejected,
    },
    attack_patterns: {
      total_detected: totalAttacks,
      blocked: attacksBlocked,
      passed_through: attacksPassed,
      block_rate_pct: (attackBlockRate * 100).toFixed(1),
    },
    legitimate_routes: {
      total: totalLegit,
      accepted: legitAccepted,
      false_blocks: legitBlocked,
      routing_efficiency_pct: (routingEfficiency * 100).toFixed(1),
    },
    ambiguous_routes: {
      accepted: ambiguousAccepted,
      blocked: ambiguousBlocked,
    },
    incident_windows: incidentStats.map(s => ({
      window: s.label,
      attack_events: s.attacks,
      blocked: s.blocked,
      passed: s.passed,
      false_blocks: s.false_blocks,
      block_rate_pct: s.attacks > 0 ? ((s.blocked / s.attacks) * 100).toFixed(1) : 'n/a',
    })),
    verdict: `${args.strategy} blocked ${attacksBlocked} of ${totalAttacks} BGP hijack-pattern routes (${(attackBlockRate * 100).toFixed(1)}%) with ${legitBlocked} false blocks on legitimate routes.`,
  };

  if (args.anchorSummary) {
    const dataSha = await readFileSha256(args.dataPath);
    const resultSrc = { ...summary };
    const resultSha = objectSha256(resultSrc);
    const { cellHashHex, typeHashHex } = composeAnchorContext(hexStr, dataSha, resultSha);
    summary['anchor'] = {
      cell_hash: cellHashHex,
      type_hash: typeHashHex,
      strategy_hex: hexStr,
      data_sha256: dataSha,
      result_sha256: resultSha,
      cartridge_id: 'ixp-routing',
    };
    const txid = await anchorViaFlushScript(cellHashHex, typeHashHex);
    if (txid) {
      (summary['anchor'] as Record<string, unknown>)['txid'] = txid;
      (summary['anchor'] as Record<string, unknown>)['wo_url'] = `https://whatsonchain.com/tx/${txid}`;
      console.error(`[anchor] ✓ landed: https://whatsonchain.com/tx/${txid}`);
    } else {
      (summary['anchor'] as Record<string, unknown>)['error'] = 'broadcast_failed';
    }
  }

  console.log(JSON.stringify(summary, null, 2));
  return 0;
}

const code = await main();
process.exit(code);

```
