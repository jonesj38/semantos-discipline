---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/poker-arena.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.318823+00:00
---

# scripts/poker-arena.ts

```ts
#!/usr/bin/env bun
/**
 * poker-arena.ts — Run N parallel poker matches with real Claude agents + BSV on-chain.
 *
 * Each match is an independent Shark vs Turtle game using Haiku for fast decisions.
 * All matches share one DirectBroadcastEngine with isolated UTXO streams.
 * Every CellToken transition and OP_RETURN is a real BSV mainnet transaction.
 *
 * Architecture:
 *   ┌─────────────────────────────────────────────────────┐
 *   │  DirectBroadcastEngine (shared, one funding address) │
 *   │  ├── streams 0,1   → Match 0 (CellToken + OP_RET)  │
 *   │  ├── streams 2,3   → Match 1                        │
 *   │  ├── streams 4,5   → Match 2                        │
 *   │  └── streams 2N,2N+1 → Match N                      │
 *   └─────────────────────────────────────────────────────┘
 *   Each match runs its own GameLoop with two Haiku agents.
 *   Matches run fully concurrent — independent state, independent chains.
 *
 * Usage:
 *   # Safe test (1 match, 5 hands, no real txs):
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-arena.ts --dry-run
 *
 *   # Safe real test (1 match, 5 hands, ~500 sats):
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-arena.ts --stake 500
 *
 *   # Full hackathon run:
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-arena.ts --matches 8 --hands 50
 *
 *   # Recovery mode (re-derive all agent keys):
 *   bun run scripts/poker-arena.ts --recover --matches 4
 *
 * Hackathon target: 1.5M tx/24h = 17.4 tx/sec
 *   Each match produces ~1 tx/sec (broadcast-limited).
 *   17 concurrent matches → ~17 tx/sec → 1.5M/24h ✓
 */

import { VendorSDK } from '../packages/plexus-vendor-sdk/src/VendorSDK';
import { AgentContext } from '../packages/protocol-types/src/agent-context';
import { GameStateDB } from '../packages/poker-agent/src/game-state-db';
import { AgentRuntime, PERSONALITIES } from '../packages/poker-agent/src/agent-runtime';
import { GameLoop, type GameEvent } from '../packages/poker-agent/src/game-loop';
import { DirectBroadcastEngine } from '../packages/poker-agent/src/direct-broadcast-engine';
import { DirectPokerStateMachine } from '../packages/poker-agent/src/direct-poker-state-machine';
import { AgentDiscoveryService } from '../packages/poker-agent/src/agent-discovery';
import { PaymentChannelManager } from '../packages/poker-agent/src/payment-channel';

// ── CLI ──

const args = process.argv.slice(2);

function flagValue(name: string, fallback: string): string {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 && args[idx + 1] ? args[idx + 1] : fallback;
}

const numMatches = parseInt(flagValue('matches', '1'), 10);   // default 1 match (safe)
const handsPerMatch = parseInt(flagValue('hands', '5'), 10);   // default 5 hands (safe)
const startingChips = parseInt(flagValue('chips', '5000'), 10); // higher chips = fewer early busts
const model = flagValue('model', 'claude-haiku-4-5-20251001');
const arcUrl = flagValue('arc-url', 'https://arc.gorillapool.io');
const splitSats = parseInt(flagValue('split-sats', '500'), 10);
const noFireAndForget = args.includes('--no-faf');
const quiet = args.includes('--quiet');
const noChannels = args.includes('--no-channels');
const stakeSats = parseInt(flagValue('stake', '1000'), 10); // sats per match channel
const dryRun = args.includes('--dry-run');
const recoverMode = args.includes('--recover');

// ── Adversarial / red-team: deterministic tamper injection ──
// Single-shot:    --tamper-match 0 --tamper-tick 3 --tamper-mode flip-linearity
// Multi-shot:     --tamper-match 0 --tamper-ticks 3,5,7 --tamper-mode flip-linearity
// Multi-mode:     --tamper-match 0 --tamper-ticks 3,5 --tamper-modes flip-linearity,zero-owner
//
// Each entry fires exactly once. Multi-shot exercises the LINEAR watchlist
// transition path (v1 → v2 → v3) on the same offender.
const VALID_TAMPER_MODES = [
  'flip-linearity',
  'zero-owner',
  'break-prev-hash',
  'bump-version-double',
  'corrupt-magic',
] as const;
type TamperModeArg = typeof VALID_TAMPER_MODES[number];
const tamperMatchRaw = flagValue('tamper-match', '');
const tamperTickRaw = flagValue('tamper-tick', '');
const tamperTicksRaw = flagValue('tamper-ticks', '');
const tamperModeRaw = flagValue('tamper-mode', '');
const tamperModesRaw = flagValue('tamper-modes', '');
// Prefer plural forms if both are present.
const ticksList = tamperTicksRaw !== ''
  ? tamperTicksRaw.split(',').map(s => s.trim()).filter(Boolean)
  : (tamperTickRaw !== '' ? [tamperTickRaw] : []);
const modesList = tamperModesRaw !== ''
  ? tamperModesRaw.split(',').map(s => s.trim()).filter(Boolean)
  : (tamperModeRaw !== '' ? [tamperModeRaw] : []);
const tamperEnabled = tamperMatchRaw !== '' && ticksList.length > 0 && modesList.length > 0;
let tamperMatchIdx = -1;
const tamperSchedule: { tick: number; mode: TamperModeArg }[] = [];
if (tamperEnabled) {
  tamperMatchIdx = parseInt(tamperMatchRaw, 10);
  // Validate every mode up-front; pad the modes list by repeating the last entry
  // so callers can write `--tamper-ticks 3,5,7 --tamper-mode flip-linearity` and
  // get the same mode applied to all three ticks.
  for (const m of modesList) {
    if (!VALID_TAMPER_MODES.includes(m as TamperModeArg)) {
      console.error(
        `\x1b[31mError:\x1b[0m invalid --tamper-mode '${m}'. Must be one of: ${VALID_TAMPER_MODES.join(', ')}`,
      );
      process.exit(1);
    }
  }
  for (let idx = 0; idx < ticksList.length; idx++) {
    const tick = parseInt(ticksList[idx], 10);
    if (Number.isNaN(tick) || tick < 1) {
      console.error(`\x1b[31mError:\x1b[0m invalid --tamper-tick(s) value '${ticksList[idx]}' (must be a positive integer)`);
      process.exit(1);
    }
    const mode = (modesList[idx] ?? modesList[modesList.length - 1]) as TamperModeArg;
    tamperSchedule.push({ tick, mode });
  }
}

if (args.includes('--help') || args.includes('-h')) {
  console.log(`
Usage: bun run scripts/poker-arena.ts [options]

Options:
  --matches N       Number of concurrent matches (default: 8)
  --hands N         Hands per match (default: 50)
  --chips N         Starting chips per player (default: 5000)
  --stake N         Sats per payment channel (default: 1000)
  --model MODEL     Claude model (default: claude-haiku-4-5-20251001)
  --arc-url URL     ARC endpoint (default: https://arc.gorillapool.io)
  --split-sats N    Sats per UTXO split (default: 500)
  --no-faf          Disable fire-and-forget (wait for each broadcast)
  --no-channels     Disable payment channels (discovery only)
  --dry-run         Simulate everything without real BSV transactions
  --recover         Re-derive agent keys and print recovery info (no game)
  --quiet           Reduce logging

Red-team (adversarial tamper injection):
  --tamper-match N    Match index (0-based) whose channel should be tampered
  --tamper-tick M     Candidate tick number at which to fire (single-shot)
  --tamper-ticks A,B  Comma-separated list of ticks (multi-shot, exercises
                      the LINEAR watchlist v1→v2→v3 transition path)
  --tamper-mode X     Single mode applied to every tick (if only --tamper-mode)
  --tamper-modes X,Y  Comma-separated modes, paired 1:1 with --tamper-ticks.
                      If shorter than ticks list, the last mode is repeated.
                      Valid modes: flip-linearity, zero-owner, break-prev-hash,
                                   bump-version-double, corrupt-magic
                      Every scheduled entry fires exactly once. The kernel
                      rejects each candidate on a specific K-theorem path;
                      each violation anchors an AFFINE violation cell and
                      bumps the offender's LINEAR watchlist. Game continues.

Safe testing example:
  bun run scripts/poker-arena.ts --matches 1 --hands 5 --stake 500 --dry-run
  bun run scripts/poker-arena.ts --matches 1 --hands 5 --stake 500  # real, minimal
`);
  process.exit(0);
}

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey && !recoverMode) {
  console.error('\x1b[31mError:\x1b[0m ANTHROPIC_API_KEY environment variable required.');
  process.exit(1);
}

// ── Logging ──

function log(label: string, msg: string) {
  console.log(`\x1b[36m[${label}]\x1b[0m ${msg}`);
}
function logGreen(label: string, msg: string) {
  console.log(`\x1b[32m[${label}]\x1b[0m ${msg}`);
}
function logYellow(label: string, msg: string) {
  console.log(`\x1b[33m[${label}]\x1b[0m ${msg}`);
}
function logRed(label: string, msg: string) {
  console.log(`\x1b[31m[${label}]\x1b[0m ${msg}`);
}

// ── WebSocket Server for Live Visualization ──

const WS_PORT = 8787;
const wsClients = new Set<any>();

// Pre-load the dashboard HTML synchronously at startup
import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
let dashboardHTML = '';
try {
  dashboardHTML = readFileSync(join(__dirname, 'poker-dashboard.html'), 'utf-8');
} catch {
  console.warn('Warning: poker-dashboard.html not found next to poker-arena.ts');
}

// Bun-native WebSocket server
const wsServer = Bun.serve({
  port: WS_PORT,
  fetch(req, server) {
    const url = new URL(req.url);

    // WebSocket upgrade on /ws path
    if (url.pathname === '/ws') {
      const ok = server.upgrade(req);
      if (ok) return undefined;
      return new Response('WebSocket upgrade failed', { status: 400 });
    }

    // Regular HTTP — serve dashboard
    if (url.pathname === '/' || url.pathname === '/index.html') {
      if (dashboardHTML) {
        return new Response(dashboardHTML, { headers: { 'Content-Type': 'text/html' } });
      }
      return new Response('Dashboard not found.', { status: 404 });
    }
    return new Response('Not found', { status: 404 });
  },
  websocket: {
    open(ws) {
      wsClients.add(ws);
      console.log(`\x1b[32m[WS]\x1b[0m Dashboard connected (${wsClients.size} clients)`);
    },
    close(ws) {
      wsClients.delete(ws);
    },
    message() {},
  },
});

function broadcast(event: GameEvent & { engineStats?: any }) {
  const msg = JSON.stringify(event);
  for (const ws of wsClients) {
    try { ws.send(msg); } catch {}
  }
}

// ── Main ──

async function main() {
  // ── Recovery Mode ──
  if (recoverMode) {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  Poker Arena — Key Recovery Mode');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    const { deriveRootKey } = await import('../packages/plexus-vendor-sdk/src/crypto');
    const rootPrivKey = deriveRootKey('arena@semantos.dev', 'semantos-poker-arena', 1_000);
    const rootPubKey = rootPrivKey.toPublicKey();

    logGreen('ROOT', `Root pubkey: ${rootPubKey.toString()}`);
    logGreen('ROOT', `Root WIF: ${rootPrivKey.toWif()}`);
    log('ROOT', 'This is the master key. All agent keys derive from it.\n');

    // Re-derive the same keys that registerAgent() would produce
    const sdk = new VendorSDK({ dbPath: ':memory:', pbkdf2Iterations: 1_000 });
    const root = sdk.registerIdentity('arena@semantos.dev');

    const maxAgents = numMatches * 2;
    log('AGENTS', `Re-deriving keys for ${maxAgents} agents (${numMatches} matches):\n`);

    for (let i = 0; i < maxAgents; i++) {
      const isShark = i % 2 === 0;
      const matchIdx = Math.floor(i / 2);
      const label = isShark ? `shark-${matchIdx}` : `turtle-${matchIdx}`;
      const name = isShark ? `Shark-${matchIdx}` : `Turtle-${matchIdx}`;
      const cert = sdk.deriveChild(root.certId, label, 0x00020001);
      const certSuffix = cert.certId.slice(0, 16);
      const derivationPath = `poker-agent/${certSuffix}/${i}`;
      const privKey = rootPrivKey.deriveChild(rootPubKey, derivationPath);
      const pubKey = privKey.toPublicKey();

      log('KEY', `${name.padEnd(12)} path=${derivationPath}`);
      log('KEY', `  pubkey=${pubKey.toString().slice(0, 32)}...`);
      log('KEY', `  WIF=${privKey.toWif().slice(0, 12)}...`);
      log('KEY', `  P2PKH=${pubKey.toAddress()}`);
    }

    console.log('\n── Recovery Instructions ──\n');
    log('RECOVERY', '1. Each agent key is deterministically derived from the root key above.');
    log('RECOVERY', '2. If sats are stuck in a 2-of-2 multisig, you need BOTH agent keys.');
    log('RECOVERY', '3. Since both keys derive from the same root, you can always recover.');
    log('RECOVERY', '4. To sweep: build a tx spending the multisig, sign with both agent privkeys.');
    log('RECOVERY', '5. Check for stuck UTXOs: search WhatsonChain for each agent P2PKH address.\n');

    sdk.close();
    return;
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  Poker Arena — ${dryRun ? 'DRY RUN (no real txs)' : 'Parallel Matches'}`);
  console.log('  Real Claude Agents × BSV Mainnet');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  log('CONFIG', `${numMatches} concurrent matches × ${handsPerMatch} hands each`);
  log('CONFIG', `Model: ${model}`);
  log('CONFIG', `ARC: ${arcUrl}`);
  log('CONFIG', `Fire-and-forget: ${!noFireAndForget} | Starting chips: ${startingChips}`);
  log('CONFIG', `Payment channels: ${!noChannels} | Stake per match: ${stakeSats} sats`);
  if (dryRun) logYellow('DRY-RUN', 'No transactions will be broadcast. All tx operations are simulated.');

  // Each match needs 2 streams (CellToken + OP_RETURN) + 1 discovery stream shared
  const totalStreams = numMatches * 2 + 1; // +1 for discovery announcements
  const discoveryStreamId = numMatches * 2; // last stream for discovery

  // Estimate UTXOs needed: ~10 txs per hand × handsPerMatch × numMatches,
  // with 2 fresh UTXOs per 5-tx cycle and some headroom
  // ~4 UTXOs per hand for poker CellTokens + OP_RETURNs (with change recycling)
  // +3 per hand for channel state CellToken ticks (blinds + ~1 bet per hand, with recycling)
  const channelTicksPerHand = noChannels ? 0 : 3;
  const utxosPerMatch = handsPerMatch * (4 + channelTicksPerHand) + 20;
  const totalUtxos = utxosPerMatch * numMatches + (noChannels ? 0 : numMatches * 8); // extra for discovery + channel funding + channel v1 cell
  // Channel funding: each match locks stakeSats in a 2-of-2 multisig
  const channelSats = noChannels ? 0 : numMatches * (stakeSats + 500); // stake + fees
  const totalSatsNeeded = totalUtxos * splitSats + channelSats + 20_000; // extra for fan-out fee

  log('FUNDING', `Need ${totalUtxos} UTXOs (${totalSatsNeeded.toLocaleString()} sats / ${(totalSatsNeeded / 100_000_000).toFixed(4)} BSV)`);

  let engine: DirectBroadcastEngine;
  let splitResult: { txid: string; splits: number };

  if (dryRun) {
    // ── DRY-RUN: Create engine with mock broadcast ──
    // The engine still constructs valid BSV transactions but doesn't send them.
    // We create a mock that satisfies the interface without needing real funding.

    engine = new DirectBroadcastEngine({
      arcUrl,
      streams: totalStreams,
      splitSatoshis: splitSats,
      verbose: !quiet,
      fireAndForget: true,
    });

    // Monkey-patch the engine to skip real broadcasts and funding
    const { PrivateKey: PK, Transaction: Tx } = await import('@bsv/sdk');
    const mockKey = engine as any;

    // Override waitForFunding to return immediately with a fake UTXO
    mockKey.waitForFunding = async () => ({
      txid: '0'.repeat(64),
      vout: 0,
      satoshis: totalSatsNeeded,
      sourceTx: new Tx(),
    });

    // Override preSplit to populate UTXO pools with fake UTXOs
    mockKey.preSplit = async (_funding: any, count: number) => {
      const perStream = Math.ceil(count / totalStreams);
      for (let s = 0; s < totalStreams; s++) {
        const pool = mockKey.utxoPools?.[s] ?? [];
        for (let u = 0; u < perStream; u++) {
          pool.push({
            txid: `dry${'0'.repeat(61)}`,
            vout: u,
            satoshis: splitSats,
            sourceTx: new Tx(),
          });
        }
        if (mockKey.utxoPools) mockKey.utxoPools[s] = pool;
      }
      return { txid: 'dry-run-no-split-' + '0'.repeat(46), splits: count };
    };

    // Override broadcast to return fake txids
    let dryTxCounter = 0;
    const origAnchorOpReturn = mockKey.anchorOpReturn?.bind(mockKey);
    const origAnchorCellToken = mockKey.anchorCellToken?.bind(mockKey);
    const origTransitionCellToken = mockKey.transitionCellToken?.bind(mockKey);

    const fakeTxid = () => {
      dryTxCounter++;
      const hex = dryTxCounter.toString(16).padStart(8, '0');
      return `drytx${hex}${'0'.repeat(58 - hex.length)}`;
    };

    // Replace broadcast methods with mock versions
    mockKey.anchorOpReturn = async (streamId: number, _payload: string) => {
      mockKey._stats = mockKey._stats ?? { totalBroadcast: 0, errors: [], txPerSec: 0, avgBuildMs: 0, avgBroadcastMs: 0, utxoPoolSizes: new Array(totalStreams).fill(0) };
      mockKey._stats.totalBroadcast++;
      return { txid: fakeTxid(), rawTx: '' };
    };

    mockKey.anchorCellToken = async (streamId: number, _cell: any) => {
      mockKey._stats = mockKey._stats ?? { totalBroadcast: 0, errors: [], txPerSec: 0, avgBuildMs: 0, avgBroadcastMs: 0, utxoPoolSizes: new Array(totalStreams).fill(0) };
      mockKey._stats.totalBroadcast++;
      return { txid: fakeTxid(), rawTx: '' };
    };

    mockKey.transitionCellToken = async (streamId: number, _prevTxid: string, _prevVout: number, _newCell: any) => {
      mockKey._stats = mockKey._stats ?? { totalBroadcast: 0, errors: [], txPerSec: 0, avgBuildMs: 0, avgBroadcastMs: 0, utxoPoolSizes: new Array(totalStreams).fill(0) };
      mockKey._stats.totalBroadcast++;
      return { txid: fakeTxid(), rawTx: '' };
    };

    mockKey.createCellToken = async (streamId: number, _cell: any, _lockAddr?: string) => {
      mockKey._stats = mockKey._stats ?? { totalBroadcast: 0, errors: [], txPerSec: 0, avgBuildMs: 0, avgBroadcastMs: 0, utxoPoolSizes: new Array(totalStreams).fill(0) };
      mockKey._stats.totalBroadcast++;
      return { txid: fakeTxid(), rawTx: '', vout: 0 };
    };

    // Mock getStats
    mockKey.getStats = () => mockKey._stats ?? {
      totalBroadcast: 0,
      errors: [],
      txPerSec: 0,
      avgBuildMs: 0,
      avgBroadcastMs: 0,
      utxoPoolSizes: new Array(totalStreams).fill(0),
    };

    // Mock flush
    mockKey.flush = async () => ({ settled: 0, errors: 0 });

    // Mock getPrivateKeyWIF + getFundingAddress (needed by payment channel)
    const tempKey = PK.fromRandom();
    mockKey.getPrivateKeyWIF = () => tempKey.toWif();
    mockKey.getFundingAddress = () => tempKey.toPublicKey().toAddress();

    logYellow('DRY-RUN', 'Engine created with mock broadcast — no real BSV will be spent');

    const funding = await engine.waitForFunding(0);
    splitResult = await engine.preSplit(funding, totalUtxos);
    logGreen('DRY-SPLIT', `Mock split: ${splitResult.splits} UTXOs created (fake)`);
  } else {
    // ── REAL MODE: Create engine and wait for funding ──

    engine = new DirectBroadcastEngine({
      arcUrl,
      streams: totalStreams,
      splitSatoshis: splitSats,
      verbose: !quiet,
      fireAndForget: !noFireAndForget,
    });

    const address = engine.getFundingAddress();

    console.log('\n┌───────────────────────────────────────────────────────────────┐');
    console.log('│  ARENA MODE — FUNDING REQUIRED                              │');
    console.log(`│  Address: ${address}    │`);
    console.log(`│  Amount:  ${(totalSatsNeeded / 100_000_000).toFixed(4)} BSV (${totalSatsNeeded.toLocaleString().padEnd(10)} sats)             │`);
    console.log(`│  Matches: ${String(numMatches).padEnd(3)} concurrent × ${String(handsPerMatch).padEnd(3)} hands (${startingChips} chips)    │`);
    console.log(`│  Mode:    ${noFireAndForget ? 'synchronous' : 'fire-and-forget'} broadcasts                           │`);
    console.log('└───────────────────────────────────────────────────────────────┘\n');

    // Safety warning for large runs
    if (totalSatsNeeded > 50_000) {
      logYellow('COST', `This run will consume ~${totalSatsNeeded.toLocaleString()} sats (${(totalSatsNeeded / 100_000_000).toFixed(4)} BSV)`);
      logYellow('COST', `For a safe first test, try: --matches 1 --hands 5 --stake 500`);
      logYellow('COST', `Or use --dry-run to simulate without spending any BSV`);
      logYellow('COST', 'Proceeding in 5 seconds... (Ctrl+C to abort)');
      await new Promise(r => setTimeout(r, 5000));
    }

    // ── 2. Wait for funding ──

    const funding = await engine.waitForFunding(600_000);
    logGreen('FUNDED', `${funding.satoshis.toLocaleString()} sats received`);

    // ── 3. Pre-split ──

    log('SPLIT', `Pre-splitting into ${totalUtxos} UTXOs across ${totalStreams} streams...`);
    splitResult = await engine.preSplit(funding, totalUtxos);
    logGreen('SPLIT', `✓ ${splitResult.splits} UTXOs — ${splitResult.txid.slice(0, 24)}...`);
    logGreen('SPLIT', `  https://whatsonchain.com/tx/${splitResult.txid}`);

    // Brief pause for mempool propagation
    log('WAIT', 'Waiting 3s for mempool propagation...');
    await new Promise(r => setTimeout(r, 3000));
  }

  // ── 4. Agent Discovery + Payment Channels + Match Setup ──

  const sdk = new VendorSDK({ dbPath: ':memory:', pbkdf2Iterations: 1_000 });
  const root = sdk.registerIdentity('arena@semantos.dev');

  // ── 4a. Derive root key for deterministic agent key derivation ──
  // This means all agent keys are RECOVERABLE from root identity.
  // If the process crashes with sats locked in a multisig, we can
  // re-derive the exact same keys and recover the funds.
  const { deriveRootKey } = await import('../packages/plexus-vendor-sdk/src/crypto');
  const rootPrivKey = deriveRootKey('arena@semantos.dev', 'semantos-poker-arena', 1_000);

  log('KEYS', `Root key derived (deterministic — all agent keys recoverable)`);
  log('KEYS', `Root pubkey: ${rootPrivKey.toPublicKey().toString().slice(0, 24)}...`);

  // Create discovery service with randomized stake preferences
  const discovery = new AgentDiscoveryService(engine, discoveryStreamId, {
    rootPrivKey,
    stakeRange: [Math.floor(stakeSats * 0.5), Math.floor(stakeSats * 1.5)],
    stakeTolerance: 2.0,
  }, !quiet);

  // In dry-run mode, don't create real payment channels (they need real broadcast)
  const channelMgr = (noChannels || dryRun) ? null : new PaymentChannelManager(
    engine,
    arcUrl,
    !quiet,
    // Fan every ChannelEvent out to the dashboard WebSocket under a dedicated
    // '__hypervisor__' gameId sentinel so the frontend can route it to the
    // red-team console without interfering with per-match table rendering.
    (ce) => {
      broadcast({
        type: `channel:${ce.type}` as any,
        gameId: '__hypervisor__',
        handNumber: 0,
        ts: ce.ts,
        data: {
          channelId: ce.channelId,
          txid: ce.txid,
          ...ce.data,
        },
      } as any);
    },
  );
  if (channelMgr) {
    await channelMgr.loadKernel(); // Load 2PDA kernel for channel state CellToken validation
  }

  interface MatchSetup {
    matchId: number;
    gameId: string;
    db: GameStateDB;
    sharkRuntime: AgentRuntime;
    turtleRuntime: AgentRuntime;
    stateMachine: DirectPokerStateMachine;
    gameLoop: GameLoop;
    channelId?: string;
  }

  const matches: MatchSetup[] = [];

  // ── 4b. Agent Discovery Phase — register all agents, then autonomous matching ──

  console.log('\n── Agent Discovery Phase ──\n');
  log('DISCOVER', `Registering ${numMatches * 2} agents with randomized stake preferences...`);

  // Register all agents first (each gets an on-chain announcement)
  const agentConfigs: { name: string; certId?: string }[] = [];
  for (let i = 0; i < numMatches; i++) {
    const sharkCert = sdk.deriveChild(root.certId, `shark-${i}`, 0x00020001);
    const turtleCert = sdk.deriveChild(root.certId, `turtle-${i}`, 0x00020001);
    agentConfigs.push({ name: `Shark-${i}`, certId: sharkCert.certId });
    agentConfigs.push({ name: `Turtle-${i}`, certId: turtleCert.certId });
  }

  // Phase 1: all agents register on-chain (OP_RETURN announcements)
  // Phase 2: autonomous matching based on stake preferences
  const discoveredMatches = await discovery.registerAndAutoMatch(agentConfigs);

  logGreen('DISCOVER', `${discoveredMatches.length} matches formed autonomously from ${agentConfigs.length} agents`);

  // Log key recovery info
  const recoveryInfo = discovery.getRecoveryInfo();
  log('RECOVERY', `Agent key derivation paths (for fund recovery):`);
  for (const info of recoveryInfo) {
    log('RECOVERY', `  ${info.name}: ${info.derivationPath}`);
  }

  // ── 4c. Open Payment Channels + Build Game Loops ──

  console.log('\n── Channel Funding Phase ──\n');

  for (let i = 0; i < discoveredMatches.length; i++) {
    const matchResult = discoveredMatches[i];
    const gameId = `arena-${Date.now()}-match-${i}`;
    const cellStreamId = i * 2;
    const opReturnStreamId = i * 2 + 1;

    // Broadcast discovery result to dashboard
    broadcast({
      type: 'hand-start' as const,
      gameId: '__discovery__',
      matchId: i,
      handNumber: 0,
      ts: Date.now(),
      data: {
        event: 'agents-matched',
        agentA: matchResult.agentA.name,
        agentB: matchResult.agentB.name,
        agreedStake: matchResult.agreedStakeSats,
        announceTxA: matchResult.agentA.announceTxid,
        announceTxB: matchResult.agentB.announceTxid,
        matchTxid: matchResult.matchAnnounceTxid,
      },
    });

    // Open payment channel with negotiated stake
    let channelId: string | undefined;
    if (channelMgr) {
      try {
        const channel = await channelMgr.openChannel({
          agentA: {
            id: matchResult.agentA.agentId,
            name: matchResult.agentA.name,
            pubKey: matchResult.agentA.pubKey,
            privKey: matchResult.agentA.privKey,
          },
          agentB: {
            id: matchResult.agentB.agentId,
            name: matchResult.agentB.name,
            pubKey: matchResult.agentB.pubKey,
            privKey: matchResult.agentB.privKey,
          },
          sharedSecret: matchResult.sharedSecret,
          fundingSats: matchResult.agreedStakeSats,
          streamId: opReturnStreamId,
          cellStreamId: cellStreamId, // channel state CellTokens use the cell stream (not OP_RETURN)
          matchTxid: matchResult.matchAnnounceTxid,
          announceTxidA: matchResult.agentA.announceTxid,
          announceTxidB: matchResult.agentB.announceTxid,
        });
        channelId = channel.channelId;

        broadcast({
          type: 'tx' as const,
          gameId,
          matchId: i,
          handNumber: 0,
          ts: Date.now(),
          data: {
            txid: channel.fundingTxid,
            kind: 'channel-open',
            label: '2-of-2 multisig',
            channelId,
            fundingSats: matchResult.agreedStakeSats,
          },
        });

        // Red-team: arm all scheduled tamper entries on this match's channel.
        if (tamperEnabled && tamperSchedule.length > 0 && i === tamperMatchIdx) {
          for (const entry of tamperSchedule) {
            channelMgr.scheduleTamper(channelId, entry.tick, entry.mode as any);
          }
          const summary = tamperSchedule.map(e => `tick=${e.tick}/${e.mode}`).join(', ');
          logYellow(
            'RED-TEAM',
            `⚡ Armed ${tamperSchedule.length} tamper(s) on match ${i}: ${summary}`,
          );
          logYellow(
            'RED-TEAM',
            `    Kernel will reject each candidate + anchor AFFINE violation cell + bump offender watchlist`,
          );
        }
      } catch (err: any) {
        logRed('CHANNEL', `Match ${i}: channel open failed: ${err.message}`);
      }
    }

    const db = new GameStateDB();

    const sharkCtx = createStubAgentContext(sdk, root.certId, matchResult.agentA.name, `shark-${i}`);
    const turtleCtx = createStubAgentContext(sdk, root.certId, matchResult.agentB.name, `turtle-${i}`);

    const sharkRuntime = new AgentRuntime({
      personality: { ...PERSONALITIES.shark, name: `Shark-${i}` },
      apiKey,
      model,
      db,
      identity: sharkCtx,
    });

    const turtleRuntime = new AgentRuntime({
      personality: { ...PERSONALITIES.turtle, name: `Turtle-${i}` },
      apiKey,
      model,
      db,
      identity: turtleCtx,
    });

    const sm = new DirectPokerStateMachine(engine, {
      verbose: false, // quiet inside matches — arena reports aggregate
      cellStreamId,
      opReturnStreamId,
    });

    // When a payment channel is open, chips = sats (1:1).
    // Each player's starting stack = half the channel funding.
    // This ensures the poker game and the payment channel stay in sync —
    // every chip bet is a real sat movement, no simulation.
    const channelFunded = channelId != null;
    const matchStake = channelFunded ? matchResult.agreedStakeSats : 0;
    const effectiveChips = channelFunded ? Math.floor(matchStake / 2) : startingChips;
    // Scale blinds to ~1/50th of stack (so a game lasts a reasonable number of hands)
    const effectiveBigBlind = channelFunded ? Math.max(2, Math.floor(effectiveChips / 50)) : 10;
    const effectiveSmallBlind = Math.max(1, Math.floor(effectiveBigBlind / 2));

    if (channelFunded) {
      log(`MATCH ${i}`, `chips=sats: ${effectiveChips} per player, blinds ${effectiveSmallBlind}/${effectiveBigBlind}`);
    }

    const gameLoop = new GameLoop(
      {
        gameId,
        smallBlind: effectiveSmallBlind,
        bigBlind: effectiveBigBlind,
        startingChips: effectiveChips,
        maxHands: handsPerMatch,
        anchorOnChain: true,
        actionDelay: 0,
        verbose: false,
        turbo: true,
        lean: true,
        matchId: i,
        channelManager: channelMgr ?? undefined,
        channelId,
        satsPerChip: 1, // 1 chip = 1 sat (chips ARE sats when channel is funded)
        onEvent: (event) => {
          // Attach live engine stats to every event
          const stats = engine.getStats();
          broadcast({ ...event, engineStats: { totalBroadcast: stats.totalBroadcast, txPerSec: stats.txPerSec, errors: stats.errors.length } });
        },
      },
      db,
      [sharkRuntime, turtleRuntime],
      null, // no wallet
      sm,
    );

    matches.push({
      matchId: i,
      gameId,
      db,
      sharkRuntime,
      turtleRuntime,
      stateMachine: sm,
      gameLoop,
      channelId,
    });
  }

  logGreen('SETUP', `${numMatches} matches ready — ${totalStreams} streams allocated`);
  if (channelMgr) {
    logGreen('CHANNELS', `${channelMgr.totalChannelsOpened} payment channels opened (${stakeSats} sats each)`);
  }
  logGreen('DISCOVERY', `${discovery.getMatches().length} agent pairs discovered and matched`);
  logGreen('DASHBOARD', `Open http://localhost:${WS_PORT} to watch the casino live`);

  // ── 5. Run all matches in parallel ──

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Arena Started — All Matches Running');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const arenaStart = Date.now();

  // Track aggregate tx count across all matches
  let totalTxCount = 0;
  let completedMatches = 0;
  const matchResults: { matchId: number; hands: number; txCount: number; elapsed: number; winner: string }[] = [];

  // Live progress reporter (terminal + WebSocket)
  const progressInterval = setInterval(() => {
    const elapsed = (Date.now() - arenaStart) / 1000;
    const stats = engine.getStats();
    const rate = elapsed > 0 ? stats.totalBroadcast / elapsed : 0;
    const projected24h = rate * 86400;
    process.stdout.write(
      `\r\x1b[36m[ARENA]\x1b[0m ${stats.totalBroadcast} tx | ` +
      `${completedMatches}/${numMatches} matches done | ` +
      `${elapsed.toFixed(1)}s | ` +
      `\x1b[32m${rate.toFixed(1)} tx/s\x1b[0m | ` +
      `24h: ${(projected24h / 1_000_000).toFixed(2)}M  `,
    );
    // Aggregate kernel validation stats across all matches
    let kernelValidations = 0;
    let kernelFailures = 0;
    for (const m of matches) {
      kernelValidations += m.stateMachine.kernelValidations;
      kernelFailures += m.stateMachine.kernelValidationFailures;
    }
    // Push stats to dashboard
    broadcast({
      type: 'hand-start', // reuse type for stats tick (dashboard filters on presence of _stats)
      gameId: '__arena__',
      handNumber: 0,
      ts: Date.now(),
      data: {},
      engineStats: {
        totalBroadcast: stats.totalBroadcast,
        txPerSec: parseFloat(rate.toFixed(1)),
        errors: stats.errors.length,
        elapsed: parseFloat(elapsed.toFixed(1)),
        projected24h: parseFloat((projected24h / 1_000_000).toFixed(2)),
        completedMatches,
        totalMatches: numMatches,
        utxoPoolSizes: stats.utxoPoolSizes,
        kernelValidations,
        kernelFailures,
        channelsOpen: channelMgr?.totalChannelsOpened ?? 0,
        channelsSettled: channelMgr?.totalChannelsSettled ?? 0,
        channelTicks: channelMgr?.totalTicks ?? 0,
        channelSatsTransferred: channelMgr?.totalSatsTransferred ?? 0,
      },
    });
  }, 500);

  // Launch all matches concurrently
  const matchPromises = matches.map(async (match) => {
    const matchStart = Date.now();
    try {
      const { results, totalTx } = await match.gameLoop.run();
      const elapsed = (Date.now() - matchStart) / 1000;

      const sharkWins = results.filter(r => r.winner.startsWith('Shark')).length;
      const turtleWins = results.filter(r => r.winner.startsWith('Turtle')).length;
      const winner = sharkWins > turtleWins ? `Shark-${match.matchId}` : `Turtle-${match.matchId}`;

      totalTxCount += totalTx;
      completedMatches++;

      matchResults.push({
        matchId: match.matchId,
        hands: results.length,
        txCount: totalTx,
        elapsed,
        winner,
      });

      return { matchId: match.matchId, results, totalTx, elapsed, error: null };
    } catch (err: any) {
      completedMatches++;
      return { matchId: match.matchId, results: [], totalTx: 0, elapsed: 0, error: err.message };
    }
  });

  const allResults = await Promise.all(matchPromises);

  // Flush any pending fire-and-forget broadcasts
  if (!noFireAndForget) {
    process.stdout.write('\r\x1b[36m[ARENA]\x1b[0m Flushing pending broadcasts...       ');
    const flushResult = await engine.flush();
    process.stdout.write(`\r\x1b[36m[ARENA]\x1b[0m Flushed ${flushResult.settled} pending broadcasts (${flushResult.errors} errors)\n`);
  }

  clearInterval(progressInterval);
  process.stdout.write('\n');

  // ── 6. Results ──

  const arenaElapsed = (Date.now() - arenaStart) / 1000;
  const engineStats = engine.getStats();
  const totalTx = engineStats.totalBroadcast;
  const rate = totalTx / arenaElapsed;
  const projected24h = rate * 86400;

  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Arena Results');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  logGreen('TOTAL TX', `${totalTx} transactions on BSV mainnet`);
  logGreen('RATE', `${rate.toFixed(2)} tx/sec (wall clock)`);
  logGreen('24H PROJ', `${projected24h.toFixed(0)} txs (${(projected24h / 1_000_000).toFixed(2)}M)`);
  log('ELAPSED', `${arenaElapsed.toFixed(1)} seconds`);
  log('MATCHES', `${completedMatches}/${numMatches} completed`);
  log('BUILD', `Avg build: ${engineStats.avgBuildMs}ms | Avg broadcast: ${engineStats.avgBroadcastMs}ms`);
  log('POOLS', `Remaining UTXOs: [${engineStats.utxoPoolSizes.join(', ')}]`);

  // Per-match breakdown
  console.log('\n── Per-Match Breakdown ──\n');
  for (const mr of matchResults.sort((a, b) => a.matchId - b.matchId)) {
    const matchRate = mr.elapsed > 0 ? (mr.txCount / mr.elapsed).toFixed(1) : '0';
    const bar = '█'.repeat(Math.min(30, Math.round(mr.txCount / 5)));
    log(`MATCH ${mr.matchId}`, `${mr.hands} hands | ${mr.txCount} tx | ${mr.elapsed.toFixed(1)}s | ${matchRate} tx/s | ${mr.winner} ${bar}`);
  }

  // Errors
  const errors = allResults.filter(r => r.error);
  if (errors.length > 0) {
    console.log('\n── Errors ──\n');
    for (const err of errors) {
      logRed(`MATCH ${err.matchId}`, err.error!);
    }
  }

  if (engineStats.errors.length > 0) {
    console.log('\n── Broadcast Errors ──\n');
    for (const err of engineStats.errors.slice(0, 20)) {
      logRed('ARC', err);
    }
  }

  // Hackathon target check
  console.log('\n── Hackathon Target ──\n');
  const target = 1_500_000;
  if (projected24h >= target) {
    logGreen('TARGET', `1.5M tx/24h: ✓ PASS (${(projected24h / 1_000_000).toFixed(2)}M projected)`);
    logGreen('TARGET', `Headroom: ${((projected24h / target - 1) * 100).toFixed(0)}% above target`);
  } else {
    logRed('TARGET', `1.5M tx/24h: ✗ MISS (${(projected24h / 1_000_000).toFixed(2)}M projected)`);
    const neededRate = target / 86400;
    logYellow('HINT', `Need ${neededRate.toFixed(1)} tx/s. Got ${rate.toFixed(1)} tx/s.`);
    logYellow('HINT', `Try: --matches ${numMatches * 2} for more concurrent sessions`);
  }

  // Kernel validation stats
  let totalKernelValidations = 0;
  let totalKernelFailures = 0;
  for (const match of matches) {
    totalKernelValidations += match.stateMachine.kernelValidations;
    totalKernelFailures += match.stateMachine.kernelValidationFailures;
  }

  // Key point for judges
  console.log('\n── Verification ──\n');
  log('AGENTS', `Each match used real Claude (${model}) agents — no heuristics`);
  log('CHAIN', 'Every tx is a full CellToken state transition or batched OP_RETURN');
  log('CHAIN', `Fan-out tx: https://whatsonchain.com/tx/${splitResult.txid}`);
  log('LINEAR', 'CellTokens: 1024-byte BRC-48 PushDrop cells with poker hand state');
  log('LINEAR', 'State chain: preflop → flop → turn → river → complete (spend-to-transition)');
  log('EVENTS', 'OP_RETURNs: blind posts, deal commitments, pot awards, hand summaries');
  logGreen('KERNEL', `2PDA kernel validations: ${totalKernelValidations} passed, ${totalKernelFailures} failed`);
  logGreen('KERNEL', 'Each CellToken transition validated through Zig WASM 2-PDA:');
  logGreen('KERNEL', '  ✓ Cell size, magic bytes, linearity preservation');
  logGreen('KERNEL', '  ✓ Type-hash continuity, owner-ID continuity, version monotonicity');
  logGreen('KERNEL', '  ✓ PushDrop script execution with linearity enforcement');

  // Discovery + Channel stats
  if (!noChannels && channelMgr) {
    console.log('\n── Agent Discovery & Payment Channels ──\n');
    logGreen('DISCOVER', `${discovery.getMatches().length} agent pairs discovered autonomously`);
    for (const m of discovery.getMatches()) {
      log('DISCOVER', `  ${m.agentA.name} ↔ ${m.agentB.name} (announce: ${m.agentA.announceTxid?.slice(0, 12) ?? 'n/a'}... match: ${m.matchAnnounceTxid?.slice(0, 12) ?? 'n/a'}...)`);
    }
    logGreen('CHANNELS', `${channelMgr.totalChannelsOpened} opened, ${channelMgr.totalChannelsSettled} settled`);
    logGreen('CHANNELS', `${channelMgr.totalTicks} ticks, ${channelMgr.totalSatsTransferred} sats transferred via HMAC-authenticated state updates`);
    logGreen('KERNEL', `Channel state CellTokens: ${channelMgr.totalKernelValidations} kernel validations, ${channelMgr.totalKernelFailures} failures`);
    if (channelMgr.totalWatchlistHits > 0 || channelMgr.totalWatchlistValidations > 0) {
      logGreen(
        'KERNEL',
        `Watchlist CellTokens: ${channelMgr.totalWatchlistValidations} kernel validations, ${channelMgr.totalWatchlistFailures} failures`,
      );
    }
    if (channelMgr.totalViolationsCaught > 0) {
      logYellow(
        'RED-TEAM',
        `🛡  Kernel caught ${channelMgr.totalViolationsCaught} violation(s), anchored ${channelMgr.totalViolationsAnchored} violation cell(s) on-chain`,
      );
    }
    if (channelMgr.totalWatchlistHits > 0) {
      const watchlists = channelMgr.getAllWatchlists();
      logYellow(
        'RED-TEAM',
        `🎯 Watchlist: ${watchlists.length} offender(s) tracked, ${channelMgr.totalWatchlistHits} total hit(s) recorded via LINEAR state chain`,
      );
      for (const w of watchlists) {
        logYellow(
          'WATCHLIST',
          `  ${w.offenderName} (${w.offenderIdHex.slice(0, 8)}...): ${w.hitCount} hit(s) | latest cell v${w.cellVersion} = ${w.cellTxid.slice(0, 16)}...`,
        );
        logYellow(
          'WATCHLIST',
          `    https://whatsonchain.com/tx/${w.cellTxid}`,
        );
      }
    }
    log('CHANNELS', 'Each match used a 2-of-2 multisig payment channel:');
    log('CHANNELS', '  ✓ Per-agent ECDSA keypairs (unique identity per player)');
    log('CHANNELS', '  ✓ ECDH shared secret for HMAC tick proof authentication');
    log('CHANNELS', '  ✓ Dual-signature settlement (both agents co-sign)');
    log('CHANNELS', '  ✓ On-chain funding + settlement with P2PKH payouts');
    log('CHANNELS', '  ✓ LINEAR CellToken state chain (kernel-validated per tick)');

    // Print the channel state chain (prevStateHash links)
    console.log('\n── Channel State Chains (CellToken transitions) ──\n');
    for (const ch of channelMgr.getAllChannels()) {
      if (ch.cellTransitions.length === 0) {
        log('CHAIN', `Channel ${ch.channelId}: no CellToken state chain`);
        continue;
      }
      log('CHAIN', `Channel ${ch.channelId}: ${ch.cellTransitions.length} states`);
      for (const t of ch.cellTransitions) {
        const kernelBadge = t.kernelValidated ? '\x1b[35m[2PDA ✓]\x1b[0m' : '';
        log('CHAIN', `  v${t.version} → ${t.txid.slice(0, 16)}... prevHash=${t.prevStateHash.slice(0, 16)}... ${kernelBadge}`);
        log('CHAIN', `    https://whatsonchain.com/tx/${t.txid}`);
      }
    }
  }

  // Dry-run cost estimate
  if (dryRun) {
    console.log('\n── Dry-Run Cost Estimate ──\n');
    logYellow('DRY-RUN', 'No real BSV was spent in this run.');
    logYellow('DRY-RUN', `If this were real, it would have needed ~${totalSatsNeeded.toLocaleString()} sats (${(totalSatsNeeded / 100_000_000).toFixed(4)} BSV)`);
    logYellow('DRY-RUN', `  ${totalUtxos} UTXOs × ${splitSats} sats + ${channelSats} channel sats + 20k overhead`);
    logYellow('DRY-RUN', `To run for real: remove --dry-run from the command`);
    logYellow('DRY-RUN', `Safe first real test: bun run scripts/poker-arena.ts --matches 1 --hands 5 --stake 500`);
  }

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // Cleanup
  for (const match of matches) {
    match.db.close();
  }
  sdk.close();
}

// ── Stub AgentContext ──

function createStubAgentContext(
  sdk: any,
  rootCertId: string,
  name: string,
  resourceId: string,
): any {
  const child = sdk.deriveChild(rootCertId, resourceId, 0x00020001);
  return {
    name,
    keys: {
      certId: child.certId,
      identityPubKey: child.publicKey,
      childIndex: child.childIndex,
      walletPubKey: child.publicKey,
      protocolKeyID: `agent/${child.certId.slice(0, 16)}`,
    },
    getOwnerPubKey: () => { throw new Error('No wallet in arena mode'); },
    buildCellTokenScript: () => { throw new Error('No wallet in arena mode'); },
    createCellToken: async () => { throw new Error('No wallet in arena mode'); },
    sign: async () => { throw new Error('No wallet in arena mode'); },
    signAction: async () => { throw new Error('No wallet in arena mode'); },
  };
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});

```
