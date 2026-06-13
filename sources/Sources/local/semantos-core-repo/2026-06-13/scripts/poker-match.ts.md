---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/poker-match.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.317480+00:00
---

# scripts/poker-match.ts

```ts
#!/usr/bin/env bun
/**
 * poker-match.ts — Run a heads-up poker match between two Claude-powered agents.
 *
 * Usage:
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts --hands 50
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts --no-anchor    # skip on-chain
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts --port 2121    # bsv-desktop
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts --fast         # no delay
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-match.ts --direct      # bypass wallet, ARC direct broadcast
 *
 * Environment:
 *   ANTHROPIC_API_KEY  — Required. Claude API key for agent reasoning.
 *   WALLET_PORT        — Optional. BSV Desktop Wallet port (default: 3321).
 */

import { VendorSDK } from '../packages/plexus-vendor-sdk/src/VendorSDK';
import { AgentContext } from '../packages/protocol-types/src/agent-context';
import { WalletClient } from '../packages/protocol-types/src/wallet-client';
import { GameStateDB } from '../packages/poker-agent/src/game-state-db';
import { AgentRuntime, PERSONALITIES } from '../packages/poker-agent/src/agent-runtime';
import { GameLoop } from '../packages/poker-agent/src/game-loop';
import { DirectBroadcastEngine } from '../packages/poker-agent/src/direct-broadcast-engine';
import { DirectPokerStateMachine } from '../packages/poker-agent/src/direct-poker-state-machine';

// ── CLI ──

const args = process.argv.slice(2);
const portFlag = args.indexOf('--port');
const port = portFlag !== -1 ? parseInt(args[portFlag + 1], 10) : parseInt(process.env.WALLET_PORT ?? '3321', 10);
const handsFlag = args.indexOf('--hands');
const maxHands = handsFlag !== -1 ? parseInt(args[handsFlag + 1], 10) : 20;
const noAnchor = args.includes('--no-anchor');
const fast = args.includes('--fast');
const turbo = args.includes('--turbo');
const lean = args.includes('--lean');
const direct = args.includes('--direct'); // bypass wallet, use ARC direct broadcast
const modelFlag = args.indexOf('--model');
const model = modelFlag !== -1 ? args[modelFlag + 1] : undefined;
const arcUrlFlag = args.indexOf('--arc-url');
const arcUrl = arcUrlFlag !== -1 ? args[arcUrlFlag + 1] : undefined;

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error('\x1b[31mError:\x1b[0m ANTHROPIC_API_KEY environment variable required.');
  console.error('  export ANTHROPIC_API_KEY=sk-ant-...');
  process.exit(1);
}

const baseUrl = `http://localhost:${port}`;

// ── Helpers ──

function log(label: string, value: unknown) {
  console.log(`\x1b[36m[${label}]\x1b[0m`, typeof value === 'string' ? value : JSON.stringify(value, null, 2));
}

// ── Main ──

async function main() {
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Poker Match — Shark vs Turtle');
  console.log(`  Claude-powered agents, BSV on-chain${direct ? ' (DIRECT ARC)' : ''}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // ── 1. Identity setup ──

  log('SETUP', 'Deriving agent identities...');

  const sdk = new VendorSDK({ dbPath: ':memory:', pbkdf2Iterations: 1_000 });
  const root = sdk.registerIdentity('hackathon@semantos.dev');

  // ── 2. Wallet connection ──

  let wallet: WalletClient | null = null;
  const anchorOnChain = !noAnchor;

  if (anchorOnChain) {
    log('WALLET', `Connecting to BSV Desktop Wallet at ${baseUrl}...`);
    wallet = new WalletClient({
      baseUrl,
      timeout: 120_000,
      originator: 'semantos-poker-match',
      origin: 'http://localhost',
    });

    try {
      const auth = await wallet.isAuthenticated();
      if (!auth) {
        log('WALLET', 'Not authenticated — continuing without on-chain anchoring');
        wallet = null;
      } else {
        const network = await wallet.getNetwork();
        const height = await wallet.getHeight();
        log('WALLET', `Connected: ${network}, height ${height}`);
      }
    } catch (err: any) {
      log('WALLET', `Connection failed: ${err.message} — continuing without on-chain anchoring`);
      wallet = null;
    }
  }

  // ── 3. Create agent contexts ──

  log('AGENTS', 'Creating agent contexts...');

  const sharkCtx = wallet
    ? await AgentContext.create(wallet, sdk, root.certId, { name: 'Shark', resourceId: 'agent-shark' })
    : createStubAgentContext(sdk, root.certId, 'Shark', 'agent-shark');

  const turtleCtx = wallet
    ? await AgentContext.create(wallet, sdk, root.certId, { name: 'Turtle', resourceId: 'agent-turtle' })
    : createStubAgentContext(sdk, root.certId, 'Turtle', 'agent-turtle');

  log('Shark', `certId: ${sharkCtx.keys.certId.slice(0, 24)}...`);
  log('Turtle', `certId: ${turtleCtx.keys.certId.slice(0, 24)}...`);

  // ── 4. Create agent runtimes ──

  const effectiveModel = model ?? (turbo ? 'claude-haiku-4-5-20251001' : undefined);
  const db = new GameStateDB(); // in-memory for the match

  const sharkRuntime = new AgentRuntime({
    personality: PERSONALITIES.shark,
    apiKey,
    model: effectiveModel,
    db,
    identity: sharkCtx,
  });

  const turtleRuntime = new AgentRuntime({
    personality: PERSONALITIES.turtle,
    apiKey,
    model: effectiveModel,
    db,
    identity: turtleCtx,
  });

  // ── 5. Direct broadcast engine (optional) ──

  let directSM: DirectPokerStateMachine | undefined;
  if (direct) {
    log('DIRECT', 'Bypassing wallet — using DirectBroadcastEngine + ARC');
    const engine = new DirectBroadcastEngine({
      arcUrl: arcUrl ?? 'https://arc.gorillapool.io',
      streams: 4,
      splitSatoshis: 500,
      verbose: !turbo,
    });

    const address = engine.getFundingAddress();
    console.log('\n┌─────────────────────────────────────────────────────┐');
    console.log('│  DIRECT MODE — FUNDING REQUIRED                     │');
    console.log(`│  Address: ${address}  │`);
    console.log(`│  Send ~${((maxHands * 10 + 100) * 100 / 100_000_000).toFixed(4)} BSV (${(maxHands * 10 + 100) * 100} sats)  │`);
    console.log('└─────────────────────────────────────────────────────┘\n');

    const funding = await engine.waitForFunding(600_000);
    log('DIRECT', `Funded: ${funding.satoshis} sats`);

    const splits = Math.min(maxHands * 10 + 50, Math.floor(funding.satoshis / 100));
    await engine.preSplit(funding, splits);
    log('DIRECT', `Pre-split into ${splits} UTXOs`);

    directSM = new DirectPokerStateMachine(engine, {
      verbose: !turbo,
      cellStreamId: 0,
      opReturnStreamId: 1,
    });
  }

  // ── 6. Run the game ──
  const anchoringMode = direct ? 'DIRECT ARC broadcast' : (anchorOnChain && wallet ? 'wallet on-chain anchoring' : 'no anchoring');
  log('MATCH', `${maxHands} hands, ${anchoringMode}, ${turbo ? 'TURBO MODE' : fast ? 'fast' : 'normal'}, model: ${effectiveModel ?? 'default'}`);

  const gameLoop = new GameLoop(
    {
      gameId: `poker-${Date.now()}`,
      smallBlind: 5,
      bigBlind: 10,
      startingChips: 1000,
      maxHands,
      anchorOnChain: direct || (anchorOnChain && !!wallet),
      actionDelay: turbo || fast ? 0 : 500,
      verbose: !turbo,
      turbo,
      lean: lean || turbo,
    },
    db,
    [sharkRuntime, turtleRuntime],
    direct ? null : wallet, // no wallet needed in direct mode
    directSM, // inject the direct state machine
  );

  const startTime = Date.now();
  const { results, totalTx } = await gameLoop.run();
  const elapsedSec = (Date.now() - startTime) / 1000;

  // ── 6. Summary ──

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Match Complete');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const sharkWins = results.filter(r => r.winner === 'Shark').length;
  const turtleWins = results.filter(r => r.winner === 'Turtle').length;

  const txPerSec = totalTx > 0 ? (totalTx / elapsedSec).toFixed(2) : '0';
  const handsPerMin = results.length > 0 ? ((results.length / elapsedSec) * 60).toFixed(1) : '0';
  const projectedTx24h = (parseFloat(txPerSec) * 86400).toFixed(0);

  log('RESULTS', {
    handsPlayed: results.length,
    sharkWins,
    turtleWins,
    totalOnChainTx: totalTx,
    txPerHand: results.length > 0 ? (totalTx / results.length).toFixed(1) : 0,
    elapsedSeconds: elapsedSec.toFixed(1),
    txPerSecond: txPerSec,
    handsPerMinute: handsPerMin,
    projectedTx24h: `${projectedTx24h} (${(parseFloat(projectedTx24h) / 1_000_000).toFixed(2)}M)`,
  });

  // ── TXID Audit Log ──
  if (totalTx > 0) {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  On-Chain Transaction Audit Log');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    let txNum = 0;
    for (const hand of results) {
      console.log(`\x1b[36m── Hand #${hand.handNumber} ──\x1b[0m  Winner: ${hand.winner} | Pot: ${hand.potSize}`);

      // State chain (LINEAR CellToken transitions)
      if (hand.stateChain.length > 0) {
        console.log(`  \x1b[32mCellToken state chain (${hand.stateChain.length} transitions):\x1b[0m`);
        for (let i = 0; i < hand.stateChain.length; i++) {
          txNum++;
          const label = i === 0 ? 'birth' : i === hand.stateChain.length - 1 ? 'complete' : `v${i + 1}`;
          console.log(`    ${String(txNum).padStart(3)}. ${hand.stateChain[i]}  (${label})`);
          console.log(`         https://whatsonchain.com/tx/${hand.stateChain[i]}`);
        }
      }

      // OP_RETURN events (everything in txids that isn't in stateChain)
      const stateSet = new Set(hand.stateChain);
      const opReturnTxids = hand.txids.filter(t => !stateSet.has(t));
      if (opReturnTxids.length > 0) {
        console.log(`  \x1b[33mOP_RETURN events (${opReturnTxids.length}):\x1b[0m`);
        for (const txid of opReturnTxids) {
          txNum++;
          console.log(`    ${String(txNum).padStart(3)}. ${txid}`);
        }
      }
      console.log('');
    }

    console.log(`\x1b[36mTotal: ${txNum} transactions on BSV mainnet\x1b[0m`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  }

  // DirectBroadcastEngine stats (if in direct mode)
  if (direct && directSM) {
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  DirectBroadcastEngine Stats');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    // Access engine stats through the variable in closure
    log('DIRECT', `Avg build: N/A (see engine stats above)`);
    log('DIRECT', `Wall-clock: ${elapsedSec.toFixed(1)}s for ${totalTx} txs = ${txPerSec} tx/sec`);
    log('DIRECT', `24h projected: ${projectedTx24h} txs`);
    console.log('');
  }

  // Agent memory dump
  log('Shark memory', db.getAllMemory('Shark'));
  log('Turtle memory', db.getAllMemory('Turtle'));

  sdk.close();
  db.close();
}

// ── Stub AgentContext (when no wallet) ──

function createStubAgentContext(
  sdk: VendorSDK,
  rootCertId: string,
  name: string,
  resourceId: string,
): AgentContext {
  const child = sdk.deriveChild(rootCertId, resourceId, 0x00020001);
  // Return a minimal AgentContext-compatible object for offline mode
  return {
    name,
    keys: {
      certId: child.certId,
      identityPubKey: child.publicKey,
      childIndex: child.childIndex,
      walletPubKey: child.publicKey, // stub: use identity key
      protocolKeyID: `agent/${child.certId.slice(0, 16)}`,
    },
    getOwnerPubKey: () => { throw new Error('No wallet in offline mode'); },
    buildCellTokenScript: () => { throw new Error('No wallet in offline mode'); },
    createCellToken: async () => { throw new Error('No wallet in offline mode'); },
    sign: async () => { throw new Error('No wallet in offline mode'); },
    signAction: async () => { throw new Error('No wallet in offline mode'); },
  } as any;
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});

```
