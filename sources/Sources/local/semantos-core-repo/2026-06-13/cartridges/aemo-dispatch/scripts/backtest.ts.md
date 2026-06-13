---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/aemo-dispatch/scripts/backtest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.573209+00:00
---

# cartridges/aemo-dispatch/scripts/backtest.ts

```ts
#!/usr/bin/env bun
// AEMO battery-dispatch backtest harness.
//
// Replays a 5-min price + battery-state stream through a Rúnar-compiled
// dispatch predicate (loaded from the cartridge's hex golden) and
// compares the rule-driven strategy against a naive baseline.
//
// What "naive baseline" means here: charge whenever price is below the
// average; discharge whenever price is above the average.  No
// hysteresis, no thresholds, no SoC awareness.  This is the strawman
// any rule-based strategy must beat to be worth deploying.
//
// What the harness PROVES (when it runs):
//   • The same Rúnar-compiled hex the brain would execute on chain
//     produces the same dispatch decisions during backtest.
//   • The decision trail is deterministic — re-running with the same
//     input always produces the same dispatch + the same P&L.
//   • The strategy's edge (or absence of edge) is measurable as a
//     dollar number.
//
// What the harness DOES NOT PROVE:
//   • Forward performance (markets change; past P&L is not future P&L).
//   • Slippage / liquidity effects (assumed 0 here; real AEMO bids
//     get cleared at the dispatch price, slippage = 0 in spec).
//   • Battery wear / cycle limits / regulatory caps.  Real deployment
//     needs additional predicates layered on top.
//
// Inputs:
//   --data <csv>         Path to CSV with timestamp,priceCents,demand
//                        (synthetic by default — bun scripts/synth-aemo-data.ts)
//   --capacity-mwh <n>   Battery capacity in MWh (default 1.0)
//   --power-mw <n>       Battery power rating in MW (default 1.0)
//   --initial-soc <pct>  Starting state-of-charge (default 50)
//   --strategy <name>    "peak_discharge" (default) or "naive"
//
// Output:
//   One JSON line per dispatch decision (timestamp, action, priceCents,
//   socPct, predicate_ok, gross_pl_cents)
//   Final summary line: total dispatched MWh, total $ in/out, net P&L

import { promises as fs } from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { execute, pushSmallInt, hexToBytes, concat } from './script-interpreter';

// ─────────────────────────────────────────────────────────────────────
// CLI parsing
// ─────────────────────────────────────────────────────────────────────

type StrategyName =
  | 'peak_discharge'
  | 'soc_adaptive'
  | 'scarcity_only'
  | 'band_discharge'
  | 'soc_quadratic'
  | 'naive';

const RUNAR_STRATEGIES: StrategyName[] = [
  'peak_discharge',
  'soc_adaptive',
  'scarcity_only',
  'band_discharge',
  'soc_quadratic',
];

interface Args {
  dataPath: string;
  capacityMwh: number;
  powerMw: number;
  initialSocPct: number;
  strategy: StrategyName;
  anchorSummary: boolean;
}

function parseArgs(argv: string[]): Args {
  const a: Args = {
    dataPath: '',
    capacityMwh: 1.0,
    powerMw: 1.0,
    initialSocPct: 50,
    strategy: 'peak_discharge',
    anchorSummary: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--data') a.dataPath = argv[++i] ?? '';
    else if (arg === '--capacity-mwh') a.capacityMwh = Number.parseFloat(argv[++i] ?? '1.0');
    else if (arg === '--power-mw') a.powerMw = Number.parseFloat(argv[++i] ?? '1.0');
    else if (arg === '--initial-soc') a.initialSocPct = Number.parseInt(argv[++i] ?? '50', 10);
    else if (arg === '--strategy') a.strategy = (argv[++i] ?? 'peak_discharge') as Args['strategy'];
    else if (arg === '--anchor-summary') a.anchorSummary = true;
    else if (arg === '--help' || arg === '-h') {
      console.error('usage: bun backtest.ts --data <csv> [--capacity-mwh 1.0] [--power-mw 1.0] [--initial-soc 50] [--strategy <name>] [--anchor-summary]');
      console.error(`strategies: ${[...RUNAR_STRATEGIES, 'naive'].join(', ')}`);
      console.error('--anchor-summary anchors a SHA-256(strategy_hex||data_hash||result_hash) on BSV mainnet');
      console.error('                 via Metanet Desktop on :3321; requires HAT_SEED env');
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
// Data + state
// ─────────────────────────────────────────────────────────────────────

interface Row {
  timestamp: string;
  priceCents: number; // cents per MWh
}

async function readCsv(p: string): Promise<Row[]> {
  const text = await fs.readFile(p, 'utf-8');
  const rows: Row[] = [];
  const lines = text.split(/\r?\n/).filter(l => l.length > 0 && !l.startsWith('#'));
  // Tolerate a header row; detect by non-numeric second column.
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i]!.split(',');
    if (parts.length < 2) continue;
    const priceCents = Number.parseInt(parts[1]!, 10);
    if (!Number.isFinite(priceCents)) continue; // skip headers / blanks
    rows.push({ timestamp: parts[0]!, priceCents });
  }
  return rows;
}

interface BatteryState {
  socPct: number;       // 0..100
  capacityMwh: number;
  powerMw: number;
  /** Cumulative cash flow in cents.  Positive = revenue, negative = cost. */
  cashCents: number;
  /** Cumulative MWh dispatched (discharge + charge). */
  totalMwh: number;
}

// ─────────────────────────────────────────────────────────────────────
// Strategy: Rúnar-compiled predicate
// ─────────────────────────────────────────────────────────────────────

async function loadStrategyHex(name: string): Promise<Uint8Array> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const hexPath = path.join(here, '..', 'strategies', `${name}.expected.hex`);
  const raw = await fs.readFile(hexPath, 'utf-8');
  return hexToBytes(raw);
}

/** Build `OP_PUSH(priceCents) || OP_PUSH(socPct) || <predicate>` and
 *  execute via the local Bitcoin Script interpreter.  Returns the
 *  predicate's accept/reject + the opcount (for joining against the
 *  brain's audit log gas counter when wired in production). */
function evaluatePredicate(
  predicateHex: Uint8Array,
  priceCents: number,
  socPct: number,
): { ok: boolean; opcount: number } {
  const script = concat(
    pushSmallInt(priceCents),
    pushSmallInt(socPct),
    predicateHex,
  );
  const r = execute(script);
  return { ok: r.ok, opcount: r.opcount };
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch logic
// ─────────────────────────────────────────────────────────────────────

type Action = 'discharge' | 'charge' | 'hold';

function decideRunar(
  predicate: Uint8Array,
  row: Row,
  state: BatteryState,
): Action {
  const dispatch = evaluatePredicate(predicate, row.priceCents, Math.round(state.socPct));
  // Symmetric heuristic for the charge side: if predicate WOULDN'T
  // dispatch (price low) AND we have headroom, charge.  Otherwise hold.
  // Future PR can author a separate charge predicate per strategy.
  if (dispatch.ok) return 'discharge';
  // Cheap-price + headroom → charge.  $50/MWh threshold matches
  // Australian wholesale electricity floor + battery loss factor.
  if (row.priceCents < 5000 && state.socPct < 95) return 'charge';
  return 'hold';
}

function decideNaive(rows: Row[], idx: number, state: BatteryState): Action {
  // Strawman baseline: discharge if price > rolling-window mean, charge if <.
  const WINDOW = 12; // 60 minutes of 5-min bars
  const start = Math.max(0, idx - WINDOW);
  let sum = 0; let n = 0;
  for (let i = start; i < idx; i++) { sum += rows[i]!.priceCents; n++; }
  const mean = n > 0 ? sum / n : rows[idx]!.priceCents;
  const p = rows[idx]!.priceCents;
  if (p > mean && state.socPct > 5) return 'discharge';
  if (p < mean && state.socPct < 95) return 'charge';
  return 'hold';
}

// 5-minute interval at battery's full power rating, expressed in MWh.
function intervalMwh(powerMw: number): number {
  return powerMw * (5 / 60);
}

function step(state: BatteryState, action: Action, priceCents: number): void {
  const dE = intervalMwh(state.powerMw); // MWh of the interval
  if (action === 'discharge') {
    const deliverable = Math.min(dE, state.capacityMwh * (state.socPct / 100));
    if (deliverable <= 0) return;
    state.cashCents += deliverable * priceCents;
    state.socPct -= (deliverable / state.capacityMwh) * 100;
    state.totalMwh += deliverable;
  } else if (action === 'charge') {
    const headroom = state.capacityMwh * ((100 - state.socPct) / 100);
    const absorbed = Math.min(dE, headroom);
    if (absorbed <= 0) return;
    state.cashCents -= absorbed * priceCents;
    state.socPct += (absorbed / state.capacityMwh) * 100;
    state.totalMwh += absorbed;
  }
}

// ─────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────
// Reproducibility anchor — commits (strategy_hex || data_hash ||
// result_hash) to BSV mainnet as a single PushDrop.  Anyone with the
// txid can later verify "the same Rúnar source + the same input data
// reproduces the same backtest result", without trusting the
// operator's report.
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
  const h = crypto.createHash('sha256').update(buf).digest('hex');
  return h;
}

function objectSha256(obj: object): string {
  return crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex');
}

/** Compose the cell_hash + type_hash the anchor should commit to.
 *  cell_hash = SHA-256(strategy_hex || data_sha || result_sha) —
 *              uniquely identifies this exact backtest run
 *  type_hash = SHA-256("aemo-dispatch.backtest.v1") — stable cell
 *              type so wallets can recognize backtest anchors. */
function composeAnchorContext(input: AnchorInput): { cellHashHex: string; typeHashHex: string } {
  const tripleHex = input.strategyHexHex + input.dataSha256Hex + input.resultSha256Hex;
  const cellHashHex = crypto.createHash('sha256').update(Buffer.from(tripleHex, 'hex')).digest('hex');
  const typeHashHex = crypto.createHash('sha256').update('aemo-dispatch.backtest.v1').digest('hex');
  return { cellHashHex, typeHashHex };
}

async function anchorViaFlushScript(
  cellHashHex: string,
  typeHashHex: string,
  cartridgeId: string,
): Promise<string | null> {
  // Invoke the wallet-headers flush-anchor-once.ts as a child process.
  // Reuses all the proven Metanet Desktop + PushDrop + hat-derivation
  // wiring; backtest doesn't reimplement anchor mechanics.
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
      'bun',
      flushScript,
      cellHashHex,
      typeHashHex,
      '--cartridge-id',
      cartridgeId,
      '--entity-tag',
      '21', // dispatch backtest entity tag — pick any non-0x20 non-reserved
    ],
    {
      env: { ...process.env },
      stdout: 'pipe',
      stderr: 'pipe',
    },
  );
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  await proc.exited;
  if (proc.exitCode !== 0) {
    console.error(`[anchor] flush failed (exit ${proc.exitCode}):\n${stderr}`);
    return null;
  }
  // flush-anchor-once.ts prints the txid as the only stdout line.
  const txid = stdout.trim();
  if (!/^[0-9a-f]{64}$/.test(txid)) {
    console.error(`[anchor] expected 64-hex txid on stdout; got: ${txid}`);
    console.error(`[anchor] stderr:\n${stderr}`);
    return null;
  }
  return txid;
}

async function main(): Promise<number> {
  const args = parseArgs(process.argv.slice(2));
  const rows = await readCsv(args.dataPath);
  if (rows.length === 0) {
    console.error('no data rows read');
    return 1;
  }
  console.error(`[backtest] strategy:     ${args.strategy}`);
  console.error(`[backtest] data rows:    ${rows.length}`);
  console.error(`[backtest] capacity:     ${args.capacityMwh} MWh`);
  console.error(`[backtest] power:        ${args.powerMw} MW`);
  console.error(`[backtest] initial SoC:  ${args.initialSocPct}%`);

  // Naive is JS-only; runar strategies load their hex.  The single-
  // source-of-truth property is: Rúnar source → Rúnar compile →
  // identical hex consumed by the brain in production AND this
  // backtest.  No port.
  const predicate = args.strategy === 'naive'
    ? new Uint8Array(0)
    : await loadStrategyHex(args.strategy);
  if (predicate.length > 0) {
    console.error(`[backtest] predicate:    ${predicate.length} bytes (${Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('')})`);
  }

  const state: BatteryState = {
    socPct: args.initialSocPct,
    capacityMwh: args.capacityMwh,
    powerMw: args.powerMw,
    cashCents: 0,
    totalMwh: 0,
  };

  const decisions: Action[] = [];

  for (let i = 0; i < rows.length; i++) {
    const row = rows[i]!;
    let action: Action;
    if (args.strategy === 'naive') {
      action = decideNaive(rows, i, state);
    } else {
      // peak_discharge OR soc_adaptive — both load their Rúnar-emitted
      // predicate hex; the decision logic is the same wrapper.
      action = decideRunar(predicate, row, state);
    }
    decisions.push(action);
    step(state, action, row.priceCents);
  }

  // Final state mark-to-market at last price — what's the remaining
  // SoC worth?  Treat at the close as if you could sell it cheaply.
  const lastPrice = rows[rows.length - 1]!.priceCents;
  const remainingMwh = state.capacityMwh * (state.socPct / 100);
  const remainingValueCents = remainingMwh * lastPrice;

  const summary: Record<string, unknown> = {
    strategy: args.strategy,
    rows_processed: rows.length,
    decisions: {
      discharge: decisions.filter(d => d === 'discharge').length,
      charge: decisions.filter(d => d === 'charge').length,
      hold: decisions.filter(d => d === 'hold').length,
    },
    total_mwh_dispatched: state.totalMwh.toFixed(3),
    cash_cents: Math.round(state.cashCents),
    cash_dollars: (state.cashCents / 100).toFixed(2),
    final_soc_pct: state.socPct.toFixed(2),
    remaining_value_cents: Math.round(remainingValueCents),
    net_pl_dollars: ((state.cashCents + remainingValueCents) / 100).toFixed(2),
  };

  // Anchor the summary (reproducibility commitment).  Real BSV mainnet
  // PushDrop committing SHA-256(strategy_hex || data_sha || result_sha)
  // — anyone with the txid can later verify same-inputs-same-outputs.
  if (args.anchorSummary) {
    if (predicate.length === 0) {
      console.error('[anchor] --anchor-summary requires a Rúnar strategy (not naive)');
    } else {
      const dataSha = await readFileSha256(args.dataPath);
      const strategyHexHex = Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('');
      // Result hash is computed BEFORE the txid is added (otherwise
      // we'd have a chicken-and-egg).
      const resultShaSrc = { ...summary };
      const resultSha = objectSha256(resultShaSrc);
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
        cartridge_id: 'aemo-dispatch',
      };
      const txid = await anchorViaFlushScript(cellHashHex, typeHashHex, 'aemo-dispatch');
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
