---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/inference-gate/scripts/backtest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.418966+00:00
---

# cartridges/inference-gate/scripts/backtest.ts

```ts
#!/usr/bin/env bun
// Inference Gateway access-control backtest harness.
//
// Replays a synthetic access-request stream through a Rúnar-compiled
// access-control predicate (loaded from the cartridge's hex golden) and
// reports allowed/denied counts, "prevented breach" counts, and a
// per-request decision audit log — suitable for anchoring to BSV mainnet.
//
// The key property: the SAME hex the brain executes in production via
// PolicyRuntime.evaluateReal is what this harness runs.  No port.
// The policy IS the bytes.  The bytes are immutable once anchored.
//
// "Prevented breach" = request was DENIED because certTier < dataClass
// (i.e. a tier-1 identity tried to access class-2 or class-3 data, or
// an anonymous user tried to access anything class >= 1).  These are not
// errors in the system; they are the system working exactly as designed.
// GDPR-relevant: every prevented breach is anchored individually.
//
// Inputs:
//   --data <csv>        Path to CSV produced by synth-access-data.ts
//   --strategy <name>   cert_gate (default) or enterprise_gate
//   --anchor-summary    Commit run summary to BSV mainnet (requires HAT_SEED)
//
// Output:
//   One JSON line per request decision (to stdout)
//   Final summary JSON (strategy, totals, anchor if --anchor-summary used)

import { promises as fs } from 'fs';
import * as path from 'path';
import * as crypto from 'crypto';
import { execute, pushSmallInt, hexToBytes, concat } from './script-interpreter';

// ─────────────────────────────────────────────────────────────────────
// CLI
// ─────────────────────────────────────────────────────────────────────

type StrategyName = 'cert_gate' | 'enterprise_gate';

interface Args {
  dataPath: string;
  strategy: StrategyName;
  anchorSummary: boolean;
  verbose: boolean;
}

function parseArgs(argv: string[]): Args {
  const a: Args = { dataPath: '', strategy: 'cert_gate', anchorSummary: false, verbose: false };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]!;
    if (arg === '--data') a.dataPath = argv[++i] ?? '';
    else if (arg === '--strategy') a.strategy = (argv[++i] ?? 'cert_gate') as Args['strategy'];
    else if (arg === '--anchor-summary') a.anchorSummary = true;
    else if (arg === '--verbose' || arg === '-v') a.verbose = true;
    else if (arg === '--help' || arg === '-h') {
      console.error('usage: bun backtest.ts --data <csv> [--strategy cert_gate|enterprise_gate] [--anchor-summary] [--verbose]');
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
  requestId: string;
  certTier: number;    // 0..3
  dataClass: number;   // 0..3
  identityLabel: string;
  resourceLabel: string;
}

async function readCsv(p: string): Promise<Row[]> {
  const text = await fs.readFile(p, 'utf-8');
  const rows: Row[] = [];
  const lines = text.split(/\r?\n/).filter(l => l.length > 0);
  for (let i = 0; i < lines.length; i++) {
    const parts = lines[i]!.split(',');
    if (parts.length < 6) continue;
    const certTier = Number.parseInt(parts[2]!, 10);
    if (!Number.isFinite(certTier)) continue; // skip header
    rows.push({
      timestamp: parts[0]!,
      requestId: parts[1]!,
      certTier,
      dataClass: Number.parseInt(parts[3]!, 10),
      identityLabel: parts[4]!,
      resourceLabel: parts[5]!,
    });
  }
  return rows;
}

// ─────────────────────────────────────────────────────────────────────
// Strategy loading
// ─────────────────────────────────────────────────────────────────────

async function loadStrategyHex(name: string): Promise<Uint8Array> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const hexPath = path.join(here, '..', 'strategies', `${name}.expected.hex`);
  const raw = await fs.readFile(hexPath, 'utf-8');
  return hexToBytes(raw.trim());
}

// ─────────────────────────────────────────────────────────────────────
// Predicate evaluation
//
// Stack built as: PUSH(certTier) || PUSH(dataClass) || <predicate_hex>
// This mirrors how the brain's PolicyRuntime.evaluateReal builds the
// unlock script: input A (certTier) pushed first (lower in stack),
// input B (dataClass) pushed second (top of stack on entry).
// The predicate's first op (OP_SWAP 0x7c) re-orders them into
// [dataClass, certTier] for the GTE comparisons.
// ─────────────────────────────────────────────────────────────────────

interface PredicateResult {
  ok: boolean;
  opcount: number;
}

function evaluatePredicate(
  predicateHex: Uint8Array,
  certTier: number,
  dataClass: number,
): PredicateResult {
  const script = concat(
    pushSmallInt(certTier),
    pushSmallInt(dataClass),
    predicateHex,
  );
  const r = execute(script);
  return { ok: r.ok, opcount: r.opcount };
}

// ─────────────────────────────────────────────────────────────────────
// Breach classification
// A "prevented breach" is a DENY where the denial was specifically
// because the requester's certTier was below the dataClass (not just
// a tier-0 blanket reject).  Tier-0 blocks everything — those are
// "unauthorized access attempts", not prevented breaches per se.
// ─────────────────────────────────────────────────────────────────────

function isPreventedBreach(certTier: number, dataClass: number, ok: boolean): boolean {
  if (ok) return false;
  // Tier-0 blocked everything — counts as unauthorized attempt, not breach
  if (certTier === 0) return false;
  // Tier >= 1 but certTier < dataClass — clearance shortfall
  return certTier < dataClass;
}

// ─────────────────────────────────────────────────────────────────────
// Anchor helpers (reuses same structure as aemo-dispatch)
// ─────────────────────────────────────────────────────────────────────

interface AnchorInput {
  strategyHexHex: string;
  dataSha256Hex: string;
  resultSha256Hex: string;
}

function composeCellHash(input: AnchorInput): { cellHashHex: string; typeHashHex: string } {
  // cell_hash = SHA-256(strategy_hex || data_sha256 || result_sha256)
  const tripleHex = input.strategyHexHex + input.dataSha256Hex + input.resultSha256Hex;
  const cellHashHex = crypto.createHash('sha256').update(Buffer.from(tripleHex, 'hex')).digest('hex');
  // type_hash = SHA-256("inference-gate.backtest.v1")
  const typeHashHex = crypto.createHash('sha256').update('inference-gate.backtest.v1').digest('hex');
  return { cellHashHex, typeHashHex };
}

async function readFileSha256(p: string): Promise<string> {
  const buf = await fs.readFile(p);
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function objectSha256(obj: object): string {
  return crypto.createHash('sha256').update(JSON.stringify(obj)).digest('hex');
}

async function anchorViaFlushScript(
  cellHashHex: string,
  typeHashHex: string,
): Promise<string | null> {
  const here = path.dirname(import.meta.url.replace('file://', ''));
  const flushScript = path.resolve(
    here, '..', '..', 'wallet-headers', 'brain', 'scripts', 'flush-anchor-once.ts',
  );
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
    ['bun', flushScript, cellHashHex, typeHashHex, '--cartridge-id', 'inference-gate', '--entity-tag', '22'],
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
    console.error(`[anchor] expected 64-hex txid; got: ${txid}`);
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

  const predicate = await loadStrategyHex(args.strategy);
  const strategyHexHex = Array.from(predicate).map(b => b.toString(16).padStart(2, '0')).join('');

  console.error(`[backtest] strategy:     ${args.strategy}`);
  console.error(`[backtest] predicate:    ${predicate.length} bytes (${strategyHexHex})`);
  console.error(`[backtest] data rows:    ${rows.length}`);

  let allowed = 0;
  let denied = 0;
  let preventedBreaches = 0;
  let unauthorizedAttempts = 0;

  const decisions: object[] = [];

  for (const row of rows) {
    const { ok, opcount } = evaluatePredicate(predicate, row.certTier, row.dataClass);
    if (ok) {
      allowed++;
    } else {
      denied++;
      if (isPreventedBreach(row.certTier, row.dataClass, ok)) {
        preventedBreaches++;
      } else if (row.certTier === 0) {
        unauthorizedAttempts++;
      }
    }

    const decision = {
      timestamp: row.timestamp,
      requestId: row.requestId,
      certTier: row.certTier,
      dataClass: row.dataClass,
      identityLabel: row.identityLabel,
      resourceLabel: row.resourceLabel,
      decision: ok ? 'ALLOW' : 'DENY',
      preventedBreach: isPreventedBreach(row.certTier, row.dataClass, ok),
      opcount,
    };

    if (args.verbose) {
      process.stdout.write(JSON.stringify(decision) + '\n');
    }
    decisions.push(decision);
  }

  const summary: Record<string, unknown> = {
    strategy: args.strategy,
    strategy_hex: strategyHexHex,
    rows_processed: rows.length,
    decisions: {
      allowed,
      denied,
      prevented_breaches: preventedBreaches,
      unauthorized_attempts: unauthorizedAttempts,
    },
    allow_rate_pct: ((allowed / rows.length) * 100).toFixed(1),
    breach_prevention_rate_pct: ((preventedBreaches / rows.length) * 100).toFixed(1),
  };

  if (args.anchorSummary) {
    const dataSha = await readFileSha256(args.dataPath);
    const resultShaSrc = { ...summary };
    const resultSha = objectSha256(resultShaSrc);
    const { cellHashHex, typeHashHex } = composeCellHash({
      strategyHexHex,
      dataSha256Hex: dataSha,
      resultSha256Hex: resultSha,
    });
    summary['anchor'] = {
      cell_hash: cellHashHex,
      type_hash: typeHashHex,
      strategy_hex: strategyHexHex,
      data_sha256: dataSha,
      result_sha256: resultSha,
      cartridge_id: 'inference-gate',
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
