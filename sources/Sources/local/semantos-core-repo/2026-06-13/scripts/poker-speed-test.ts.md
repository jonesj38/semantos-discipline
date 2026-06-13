---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/poker-speed-test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.324470+00:00
---

# scripts/poker-speed-test.ts

```ts
#!/usr/bin/env bun
/**
 * poker-speed-test.ts — Benchmark DirectBroadcastEngine throughput.
 *
 * Tests raw CellToken creation + transition speed without the wallet bottleneck.
 * Goal: prove we can hit 17+ tx/sec (1.5M txs in 24 hours).
 *
 * Usage:
 *   bun run scripts/poker-speed-test.ts
 *   bun run scripts/poker-speed-test.ts --streams 8 --cycles 50
 *   bun run scripts/poker-speed-test.ts --arc-url https://arc.gorillapool.io/v1
 *
 * The script will:
 *   1. Generate a fresh keypair & display funding address
 *   2. Wait for you to send BSV (or auto-detect if already funded)
 *   3. Pre-split the funding UTXO into parallel pools
 *   4. Run N streams of CellToken create→transition→transition cycles
 *   5. Report real-time throughput and project 24h capacity
 *
 * CRITICAL OPTIMIZATION: After broadcast, the Transaction object is passed
 * directly to the next transition — NO WoC fetch round-trips.
 */

import {
  DirectBroadcastEngine,
  type BroadcastResult,
} from '../packages/poker-agent/src/direct-broadcast-engine';

// ── CLI ──

const args = process.argv.slice(2);

function getFlag(name: string, defaultVal: string): string {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : defaultVal;
}

const streams = parseInt(getFlag('streams', '4'), 10);
const cycles = parseInt(getFlag('cycles', '30'), 10);
const arcUrl = getFlag('arc-url', 'https://arc.gorillapool.io');
const arcApiKey = getFlag('arc-api-key', '');
const splitSats = parseInt(getFlag('split-sats', '500'), 10);
const quiet = args.includes('--quiet');

// ── Helpers ──

function log(label: string, msg: string): void {
  console.log(`\x1b[36m[${label}]\x1b[0m ${msg}`);
}

function logGreen(label: string, msg: string): void {
  console.log(`\x1b[32m[${label}]\x1b[0m ${msg}`);
}

function logYellow(label: string, msg: string): void {
  console.log(`\x1b[33m[${label}]\x1b[0m ${msg}`);
}

function logRed(label: string, msg: string): void {
  console.log(`\x1b[31m[${label}]\x1b[0m ${msg}`);
}

// ── Main ──

async function main(): Promise<void> {
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  DirectBroadcastEngine — Speed Test');
  console.log('  Bypassing wallet, pure SPV + ARC');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const txPerCycle = 5; // 1 create + 4 transitions (preflop→flop→turn→river→complete)
  const totalExpected = streams * cycles * txPerCycle;

  log('CONFIG', `streams=${streams}, cycles=${cycles}, splitSats=${splitSats}`);
  log('CONFIG', `ARC: ${arcUrl}`);
  log('CONFIG', `Expected txs: ${totalExpected} (${cycles} cycles × ${streams} streams × ${txPerCycle} tx/cycle)`);

  // ── 1. Create engine ──

  const engine = new DirectBroadcastEngine({
    arcUrl,
    arcApiKey: arcApiKey || undefined,
    streams,
    splitSatoshis: splitSats,
    verbose: !quiet,
  });

  const address = engine.getFundingAddress();
  const minSats = streams * (cycles * 2 + 10) * splitSats;

  console.log('\n┌─────────────────────────────────────────────────────┐');
  console.log('│  FUNDING REQUIRED                                   │');
  console.log('│                                                     │');
  console.log(`│  Address: ${address}  │`);
  console.log('│                                                     │');
  console.log(`│  Min: ~${minSats.toLocaleString()} sats (${(minSats / 100_000_000).toFixed(4)} BSV)     │`);
  console.log('│  Recommended: send 50,000+ sats for headroom        │');
  console.log('│  (Send from BSV Desktop Wallet)                     │');
  console.log('└─────────────────────────────────────────────────────┘\n');

  log('KEY', `PubKey: ${engine.getPubKeyHex().slice(0, 24)}...`);

  // ── 2. Wait for funding ──

  log('FUND', 'Polling WhatsOnChain for UTXOs...');
  const funding = await engine.waitForFunding(600_000);
  logGreen('FUND', `Received ${funding.satoshis.toLocaleString()} sats at ${funding.txid.slice(0, 24)}...`);

  // ── 3. Pre-split ──

  // Each cycle needs ~2 fresh UTXOs (create + 4 transitions, with change recycling at 150-sat fee)
  const totalSplits = streams * (cycles * 2 + 10);
  log('SPLIT', `Pre-splitting into ${totalSplits} UTXOs across ${streams} streams...`);

  const splitResult = await engine.preSplit(funding, totalSplits);
  logGreen('SPLIT', `✓ ${splitResult.splits} UTXOs — ${splitResult.txid.slice(0, 24)}...`);
  logGreen('SPLIT', `  https://whatsonchain.com/tx/${splitResult.txid}`);

  // Brief pause for mempool propagation of the fan-out
  log('WAIT', 'Waiting 2s for mempool propagation...');
  await new Promise(r => setTimeout(r, 2000));

  // ── 4. Run parallel streams ──

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Starting Speed Test');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const gameId = `speed-${Date.now()}`;
  const allTxids: TxRecord[] = [];
  const startTime = Date.now();
  let completedTx = 0;

  // Live progress reporter
  const progressInterval = setInterval(() => {
    const elapsed = (Date.now() - startTime) / 1000;
    const rate = elapsed > 0 ? completedTx / elapsed : 0;
    const projected24h = rate * 86400;
    process.stdout.write(
      `\r\x1b[36m[LIVE]\x1b[0m ${completedTx}/${totalExpected} tx | ${elapsed.toFixed(1)}s | ` +
      `\x1b[32m${rate.toFixed(1)} tx/s\x1b[0m | 24h: ${(projected24h / 1_000_000).toFixed(2)}M  `,
    );
  }, 250);

  // Launch all streams in parallel
  const streamPromises = Array.from({ length: streams }, (_, streamId) =>
    runStream(engine, streamId, cycles, gameId, (record) => {
      completedTx++;
      allTxids.push(record);
    }),
  );

  const streamResults = await Promise.all(streamPromises);

  clearInterval(progressInterval);
  process.stdout.write('\n\n');

  // ── 5. Results ──

  const totalElapsed = (Date.now() - startTime) / 1000;
  const totalTx = allTxids.length;
  const rate = totalTx / totalElapsed;
  const projected24h = rate * 86400;

  const stats = engine.getStats();

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Speed Test Results');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  logGreen('TOTAL', `${totalTx} transactions in ${totalElapsed.toFixed(1)}s`);
  logGreen('RATE', `${rate.toFixed(2)} tx/sec (wall clock, including parallel streams)`);
  logGreen('24H', `${projected24h.toFixed(0)} projected (${(projected24h / 1_000_000).toFixed(2)}M)`);
  log('BUILD', `Avg build: ${stats.avgBuildMs}ms per tx`);
  log('BROADCAST', `Avg broadcast: ${stats.avgBroadcastMs}ms per tx`);
  log('POOLS', `Remaining UTXOs: [${stats.utxoPoolSizes.join(', ')}]`);

  if (stats.errors.length > 0) {
    logRed('ERRORS', `${stats.errors.length} errors:`);
    for (const err of stats.errors.slice(0, 10)) {
      logRed('  ERR', err);
    }
  }

  // Per-stream breakdown
  console.log('\n── Per-Stream Breakdown ──\n');
  for (const sr of streamResults) {
    const bar = '█'.repeat(Math.round(sr.txPerSec * 2));
    log(`STREAM ${sr.streamId}`, `${sr.txCount} tx | ${sr.totalMs.toFixed(0)}ms | ${sr.txPerSec.toFixed(1)} tx/s | err:${sr.errors} ${bar}`);
  }

  // Hackathon target check
  console.log('\n── Hackathon Target ──\n');
  const target = 1_500_000;
  const meetsTarget = projected24h >= target;
  if (meetsTarget) {
    logGreen('TARGET', `1.5M tx/24h: ✓ PASS (${(projected24h / 1_000_000).toFixed(2)}M projected)`);
    logGreen('TARGET', `Headroom: ${((projected24h / target - 1) * 100).toFixed(0)}% above target`);
  } else {
    logRed('TARGET', `1.5M tx/24h: ✗ MISS (${(projected24h / 1_000_000).toFixed(2)}M projected)`);
    const neededRate = target / 86400;
    logYellow('HINT', `Need ${neededRate.toFixed(1)} tx/s. Got ${rate.toFixed(1)} tx/s.`);
    logYellow('HINT', `Try: --streams ${streams * 2}, or --arc-url https://arc.gorillapool.io/v1`);
  }

  // Sample TXID audit log
  console.log('\n── Sample TXIDs (first 20) ──\n');
  for (const entry of allTxids.slice(0, 20)) {
    const isCreate = entry.step === 'create';
    const color = isCreate ? '\x1b[32m' : '\x1b[36m';
    console.log(
      `  ${color}S${entry.streamId}\x1b[0m C${entry.cycle} ${entry.step.padEnd(18)} ${entry.txid.slice(0, 32)}... ${entry.ms}ms`,
    );
    console.log(`    https://whatsonchain.com/tx/${entry.txid}`);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}

// ── Types ──

interface TxRecord {
  streamId: number;
  cycle: number;
  step: string;
  txid: string;
  ms: number;
}

interface StreamResult {
  streamId: number;
  txCount: number;
  totalMs: number;
  txPerSec: number;
  errors: number;
}

// ── Stream Runner ──
// Each stream runs sequential cycles of: create CellToken → transition ×4
// The Transaction object is passed directly from one step to the next — zero WoC fetches.

async function runStream(
  engine: DirectBroadcastEngine,
  streamId: number,
  cycles: number,
  gameId: string,
  onTx: (record: TxRecord) => void,
): Promise<StreamResult> {
  const streamStart = Date.now();
  let txCount = 0;
  let errors = 0;

  for (let cycle = 0; cycle < cycles; cycle++) {
    try {
      const handNum = cycle * 1000 + streamId; // unique hand number

      // ── Step 1: Create CellToken (hand birth — preflop) ──
      const cell1 = await engine.buildPokerCell(
        gameId, handNum, 'preflop',
        { stream: streamId, cycle, blinds: { small: 5, big: 10 } },
        1,
      );

      const createResult = await engine.createCellToken(
        streamId, cell1.cellBytes, cell1.semanticPath, cell1.contentHash,
      );
      txCount++;
      onTx({
        streamId, cycle, step: 'create',
        txid: createResult.txid,
        ms: createResult.buildMs + createResult.broadcastMs,
      });

      // ── Steps 2-5: Transition through phases ──
      // Key optimization: pass createResult.tx directly — no WoC fetch
      const phases = ['flop', 'turn', 'river', 'complete'] as const;
      let prevTxid = createResult.txid;
      let prevVout = 0;
      let prevTx = createResult.tx; // <-- THE TX OBJECT, not a hex fetch

      for (let p = 0; p < phases.length; p++) {
        const version = p + 2;
        const phase = phases[p];

        const cellN = await engine.buildPokerCell(
          gameId, handNum, phase,
          { stream: streamId, cycle, phase, version },
          version,
        );

        const transResult = await engine.transitionCellToken(
          streamId,
          prevTxid, prevVout, prevTx,
          cellN.cellBytes, cellN.semanticPath, cellN.contentHash,
        );
        txCount++;
        onTx({
          streamId, cycle, step: `trans-${phase}`,
          txid: transResult.txid,
          ms: transResult.buildMs + transResult.broadcastMs,
        });

        // Chain forward — use the tx object directly
        prevTxid = transResult.txid;
        prevVout = 0;
        prevTx = transResult.tx; // <-- ZERO LATENCY CHAINING
      }
    } catch (err: any) {
      errors++;
      if (!quiet) {
        console.error(`\n\x1b[31m[S${streamId} C${cycle}]\x1b[0m ${err.message}`);
      }
      // Continue to next cycle
    }
  }

  const totalMs = Date.now() - streamStart;
  return {
    streamId,
    txCount,
    totalMs,
    txPerSec: totalMs > 0 ? (txCount / totalMs) * 1000 : 0,
    errors,
  };
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});

```
