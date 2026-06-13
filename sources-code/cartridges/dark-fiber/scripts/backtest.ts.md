---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/dark-fiber/scripts/backtest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.421916+00:00
---

# cartridges/dark-fiber/scripts/backtest.ts

```ts
#!/usr/bin/env bun
// Dark fiber wavelength spot-market backtest harness.
//
// Replays a 5-min utilization + bid stream through a Rúnar-compiled
// commitment predicate (loaded from the cartridge's hex golden) and
// compares the rule-driven strategy against a naive baseline.
//
// What "naive baseline" means here: commit whenever bid > 200
// (€2.00/Gbps-hr), regardless of link utilization.  No capacity awareness,
// no threshold discipline.  The strawman any predicate-governed strategy
// must beat to justify the complexity.
//
// What the harness PROVES (when it runs):
//   • The same Rúnar-compiled hex the brain would execute on chain
//     produces the same commitment decisions during backtest.
//   • The decision trail is deterministic — re-running with the same
//     input always produces the same commitments and the same P&L.
//   • The strategy's edge is measurable as a net revenue figure in €.
//
// What the harness DOES NOT PROVE:
//   • Forward performance (spot market conditions change).
//   • Actual switching cost modelling (assumed flat €0.20 per commit/uncommit).
//   • Regulatory constraints on wavelength resale in a given jurisdiction.
//
// Inputs:
//   --data <csv>         Path to CSV: timestamp,utilizationPct,bidCentsPerGbps,demandGbps
//                        (synthetic by default — bun scripts/synth-fiber-data.ts)
//   --strategy <name>    "threshold_commit" (default) or "premium_threshold" or "naive"
//   --capacity-gbps <n>  Wavelength capacity available for spot (default 100 Gbps)
//   --anchor-summary     Anchor run to BSV mainnet (requires HAT_SEED env)
//
// P&L model per 5-min slot:
//   revenue_cents = bidCentsPerGbps × capacityGbps × (5/60)  [Gbps-hr × €/Gbps-hr]
//   switching_cost_cents = 20 [flat 20 cent cost per commit or uncommit transition]
//   net = revenue - switching_cost_on_state_change
//
// Output:
//   One JSON summary line per run.

import { promises as fs } from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { execute, pushSmallInt, hexToBytes, concat } from './script-interpreter';

// ─────────────────────────────────────────────────────────────────────
// CLI parsing
// ─────────────────────────────────────────────────────────────────────

type StrategyName = 'threshold_commit' | 'premium_threshold' | 'naive';

const RUNAR_STRATEGIES: StrategyName[] = ['threshold_commit', 'premium_threshold'];

interface Args {
  dataPath: string;
  strategy: StrategyName;
  capacityGbps: number;
  anchorSummary: boolean;
}

function parseArgs(argv: string[]): Args {
  const a: Args = {
    dataPath: '',
    strategy: 'threshold_commit',
    capacityGbps: 100,
    anchorSummary: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--data') a.dataPath = argv[++i] ?? '';
    else if (arg === '--strategy') a.strategy = (argv[++i] ?? 'threshold_commit') as StrategyName;
    else if (arg === '--capacity-gbps') a.capacityGbps = Number.parseFloat(argv[++i] ?? '100');
    else if (arg === '--anchor-summary') a.anchorSummary = true;
    else if (arg === '--help' || arg === '-h') {
      console.error('usage: bun backtest.ts --data <csv> [--strategy <name>] [--capacity-gbps 100] [--anchor-summary]');
      console.error(`strategies: ${[...RUNAR_STRATEGIES, 'naive'].join(', ')}`);
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
  utilizationPct: number; // 0..100
  bidCentsPerGbps: number; // €-cents per Gbps-hr
  demandGbps: number;
}

async function readCsv(p: string): Promise<Row[]> {
  const text = await fs.readFile(p, 'utf-8');
  const rows: Row[] = [];
  const lines = text.split(/\r?\n/).filter(l => l.length > 0 && !l.startsWith('#'));
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i]!.split(',');
    if (parts.length < 3) continue;
    const utilizationPct = Number.parseInt(parts[1]!, 10);
    if (!Number.isFinite(utilizationPct)) continue; // header / blank
    rows.push({
      timestamp: parts[0]!,
      utilizationPct,
      bidCentsPerGbps: Number.parseInt(parts[2]!, 10),
      demandGbps: parts[3] ? Number.parseInt(parts[3], 10) : 0,
    });
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────
// Strategy: Rúnar predicate executor
// ─────────────────────────────────────────────────────────────────────

async function loadStrategyHex(name: string): Promise<Uint8Array> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const hexPath = path.join(here, '..', 'strategies', `${name}.expected.hex`);
  const raw = await fs.readFile(hexPath, 'utf-8');
  return hexToBytes(raw);
}

/** Build `OP_PUSH(utilizationPct) || OP_PUSH(bidCentsPerGbps) || <predicate>` and
 *  execute.  Returns whether the predicate accepts (commit the wavelength slot). */
function evaluatePredicate(
  predicateHex: Uint8Array,
  utilizationPct: number,
  bidCentsPerGbps: number,
): { ok: boolean; opcount: number } {
  const script = concat(
    pushSmallInt(utilizationPct),
    pushSmallInt(bidCentsPerGbps),
    predicateHex,
  );
  const r = execute(script);
  return { ok: r.ok, opcount: r.opcount };
}

// ─────────────────────────────────────────────────────────────────────
// Decision logic
// ─────────────────────────────────────────────────────────────────────

type Decision = 'commit' | 'hold';

function decideRunar(predicate: Uint8Array, row: Row): Decision {
  const { ok } = evaluatePredicate(predicate, row.utilizationPct, row.bidCentsPerGbps);
  return ok ? 'commit' : 'hold';
}

function decideNaive(row: Row): Decision {
  // Strawman: commit whenever bid > 200 €-cents/Gbps-hr, ignoring utilization.
  return row.bidCentsPerGbps > 200 ? 'commit' : 'hold';
}

// ─────────────────────────────────────────────────────────────────────
// P&L accounting
// ─────────────────────────────────────────────────────────────────────

// Revenue per 5-min slot if committed:
//   bidCentsPerGbps × capacityGbps × (5min / 60min) = Gbps-hr revenue in €-cents
const SLOT_FRACTION = 5 / 60; // fraction of an hour
const SWITCHING_COST_CENTS = 20; // flat 20 € cents per commit/uncommit transition

interface AccountingState {
  netCents: number;
  grossCents: number;
  switchingCostCents: number;
  commits: number;
  holds: number;
  prevDecision: Decision | null;
}

function applyDecision(
  state: AccountingState,
  decision: Decision,
  bidCentsPerGbps: number,
  capacityGbps: number,
): void {
  // Switching cost on state transitions
  if (state.prevDecision !== null && state.prevDecision !== decision) {
    state.switchingCostCents += SWITCHING_COST_CENTS;
    state.netCents -= SWITCHING_COST_CENTS;
  }
  state.prevDecision = decision;

  if (decision === 'commit') {
    const revCents = Math.round(bidCentsPerGbps * capacityGbps * SLOT_FRACTION);
    state.grossCents += revCents;
    state.netCents += revCents;
    state.commits++;
  } else {
    state.holds++;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Anchor helpers (identical pattern to aemo-dispatch)
// ─────────────────────────────────────────────────────────────────────

interface AnchorInput {
  strategy: string;
  strategyHexHex: string;
  dataPath: string;
  dataSha256Hex: string;
  resultSha256Hex: string;
  summary: object;
}

async function readFileSha256(p: string): Promise<string> {
  const buf = await fs.readFile(p);
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function objectSha256(obj: object): string {
  return crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex');
}

function composeAnchorContext(input: AnchorInput): { cellHashHex: string; typeHashHex: string } {
  const tripleHex = input.strategyHexHex + input.dataSha256Hex + input.resultSha256Hex;
  const cellHashHex = crypto.createHash('sha256').update(Buffer.from(tripleHex, 'hex')).digest('hex');
  const typeHashHex = crypto.createHash('sha256').update('dark-fiber.backtest.v1').digest('hex');
  return { cellHashHex, typeHashHex };
}

async function anchorViaFlushScript(
  cellHashHex: string,
  typeHashHex: string,
  cartridgeId: string,
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
    [
      'bun', flushScript,
      cellHashHex, typeHashHex,
      '--cartridge-id', cartridgeId,
      '--entity-tag', '22',
    ],
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
    console.error(`[anchor] expected 64-hex txid on stdout; got: ${txid}\n${stderr}`);
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
  if (rows.length === 0) {
    console.error('no data rows read');
    return 1;
  }
  console.error(`[backtest] strategy:      ${args.strategy}`);
  console.error(`[backtest] data rows:     ${rows.length}`);
  console.error(`[backtest] capacity:      ${args.capacityGbps} Gbps`);

  const predicate = args.strategy === 'naive'
    ? new Uint8Array(0)
    : await loadStrategyHex(args.strategy);

  if (predicate.length > 0) {
    const hexStr = Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('');
    console.error(`[backtest] predicate:     ${predicate.length} bytes (${hexStr})`);
  }

  const state: AccountingState = {
    netCents: 0,
    grossCents: 0,
    switchingCostCents: 0,
    commits: 0,
    holds: 0,
    prevDecision: null,
  };

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]!;
    const decision: Decision = args.strategy === 'naive'
      ? decideNaive(row)
      : decideRunar(predicate, row);
    applyDecision(state, decision, row.bidCentsPerGbps, args.capacityGbps);
  }

  const netEuros = (state.netCents / 100).toFixed(2);
  const grossEuros = (state.grossCents / 100).toFixed(2);
  const switchEuros = (state.switchingCostCents / 100).toFixed(2);

  const summary: Record<string, unknown> = {
    strategy: args.strategy,
    rows_processed: rows.length,
    decisions: { commit: state.commits, hold: state.holds },
    gross_revenue_eur: grossEuros,
    switching_cost_eur: switchEuros,
    net_revenue_eur: netEuros,
  };

  if (args.anchorSummary) {
    if (predicate.length === 0) {
      console.error('[anchor] --anchor-summary requires a Rúnar strategy (not naive)');
    } else {
      const dataSha = await readFileSha256(args.dataPath);
      const strategyHexHex = Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('');
      const resultSha = objectSha256({ ...summary });
      const { cellHashHex, typeHashHex } = composeAnchorContext({
        strategy: args.strategy,
        strategyHexHex,
        dataPath: args.dataPath,
        dataSha256Hex: dataSha,
        resultSha256Hex: resultSha,
        summary,
      });
      summary['anchor'] = {
        cell_hash: cellHashHex,
        type_hash: typeHashHex,
        strategy_hex: strategyHexHex,
        data_sha256: dataSha,
        result_sha256: resultSha,
        cartridge_id: 'dark-fiber',
      };
      const txid = await anchorViaFlushScript(cellHashHex, typeHashHex, 'dark-fiber');
      if (txid) {
        (summary['anchor'] as Record<string, unknown>)['txid'] = txid;
        (summary['anchor'] as Record<string, unknown>)['wo_url'] = `https://whatsonchain.com/tx/${txid}`;
        console.error(`[anchor] ✓ landed: https://whatsonchain.com/tx/${txid}`);
      } else {
        (summary['anchor'] as Record<string, unknown>)['error'] = 'broadcast_failed';
      }
    }
  }

  console.log(JSON.stringify(summary, null, 2));
  return 0;
}

const code = await main();
process.exit(code);

```
