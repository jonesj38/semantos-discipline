---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/poker-p2p.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.323408+00:00
---

# scripts/poker-p2p.ts

```ts
#!/usr/bin/env bun
/**
 * poker-p2p.ts — Run ONE player in a P2P poker match.
 *
 * Each player runs this on their own machine. Two instances
 * coordinate entirely via MessageBox (P2P) + BSV mainnet.
 * There is no central server.
 *
 * Usage:
 *   # Player 1 (Shark, seat 0):
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-p2p.ts \
 *     --seat 0 \
 *     --opponent <turtle-identity-pubkey-hex> \
 *     --game poker-1712345678
 *
 *   # Player 2 (Turtle, seat 1) — on a DIFFERENT machine:
 *   ANTHROPIC_API_KEY=sk-... bun run scripts/poker-p2p.ts \
 *     --seat 1 \
 *     --opponent <shark-identity-pubkey-hex> \
 *     --game poker-1712345678
 *
 * Both players must use the same --game ID.
 * Each player needs their own BSV Desktop Wallet running locally.
 * Each player needs their own Claude API key.
 *
 * Optional flags:
 *   --hands 20       Max hands to play (default: 20)
 *   --port 3321      Wallet port (default: 3321)
 *   --fast           No action delay
 */

import { VendorSDK } from '../packages/plexus-vendor-sdk/src/VendorSDK';
import { AgentContext } from '../packages/protocol-types/src/agent-context';
import { WalletClient } from '../packages/protocol-types/src/wallet-client';
import { GameStateDB } from '../packages/poker-agent/src/game-state-db';
import { AgentRuntime, PERSONALITIES } from '../packages/poker-agent/src/agent-runtime';
import { P2PAgentRunner } from '../packages/poker-agent/src/p2p-agent-runner';

// ── CLI ──

const args = process.argv.slice(2);

function getArg(name: string): string | undefined {
  const idx = args.indexOf(`--${name}`);
  return idx !== -1 ? args[idx + 1] : undefined;
}

const seat = parseInt(getArg('seat') ?? '', 10);
if (seat !== 0 && seat !== 1) {
  console.error('\x1b[31mError:\x1b[0m --seat must be 0 (Shark/dealer) or 1 (Turtle)');
  console.error('  Usage: bun run scripts/poker-p2p.ts --seat 0 --opponent <pubkey> --game <id>');
  process.exit(1);
}

const opponentKey = getArg('opponent');
if (!opponentKey) {
  console.error('\x1b[31mError:\x1b[0m --opponent <identity-pubkey-hex> required');
  console.error('  Run the opponent\'s process first to get their identity key.');
  process.exit(1);
}

const gameId = getArg('game') ?? `poker-${Date.now()}`;
const maxHands = parseInt(getArg('hands') ?? '20', 10);
const port = parseInt(getArg('port') ?? process.env.WALLET_PORT ?? '3321', 10);
const fast = args.includes('--fast');

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.error('\x1b[31mError:\x1b[0m ANTHROPIC_API_KEY environment variable required.');
  process.exit(1);
}

// ── Helpers ──

function log(label: string, value: unknown) {
  console.log(`\x1b[36m[${label}]\x1b[0m`, typeof value === 'string' ? value : JSON.stringify(value, null, 2));
}

// ── Main ──

async function main() {
  const personality = seat === 0 ? PERSONALITIES.shark : PERSONALITIES.turtle;
  const baseUrl = `http://localhost:${port}`;

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  P2P Poker — ${personality.name} (seat ${seat})`);
  console.log('  Zero servers. MessageBox + BSV mainnet.');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  log('CONFIG', {
    seat,
    personality: personality.name,
    gameId,
    maxHands,
    wallet: baseUrl,
    opponent: opponentKey.slice(0, 24) + '...',
  });

  // ── 1. Identity ──
  const sdk = new VendorSDK({ dbPath: ':memory:', pbkdf2Iterations: 1_000 });
  const root = sdk.registerIdentity('hackathon@semantos.dev');

  // ── 2. Wallet ──
  log('WALLET', `Connecting to ${baseUrl}...`);
  const wallet = new WalletClient({
    baseUrl,
    timeout: 120_000,
    originator: 'semantos-poker-p2p',
    origin: 'http://localhost',
  });

  const auth = await wallet.isAuthenticated();
  if (!auth) {
    console.error('\x1b[31mError:\x1b[0m Wallet not authenticated. Start BSV Desktop Wallet first.');
    process.exit(1);
  }

  const network = await wallet.getNetwork();
  const height = await wallet.getHeight();
  log('WALLET', `Connected: ${network}, height ${height}`);

  // Get our identity key so the opponent can connect to us
  const myIdentityKey = await wallet.getPublicKey({ identityKey: true });
  console.log('\n\x1b[33m┌─────────────────────────────────────────────────┐');
  console.log(`│  MY IDENTITY KEY (give this to your opponent):  │`);
  console.log(`│  ${myIdentityKey}  │`);
  console.log('└─────────────────────────────────────────────────┘\x1b[0m\n');

  // ── 3. Agent Context ──
  const resourceId = seat === 0 ? 'agent-shark' : 'agent-turtle';
  const ctx = await AgentContext.create(wallet, sdk, root.certId, {
    name: personality.name,
    resourceId,
  });

  // ── 4. Agent Runtime ──
  const db = new GameStateDB();
  const agent = new AgentRuntime({
    personality,
    apiKey,
    db,
    identity: ctx,
  });

  // ── 5. Run P2P ──
  log('P2P', `Game: ${gameId} | ${maxHands} hands | waiting for opponent handshake...`);

  const runner = new P2PAgentRunner(
    {
      gameId,
      seat: seat as 0 | 1,
      opponentIdentityKey: opponentKey,
      smallBlind: 5,
      bigBlind: 10,
      startingChips: 1000,
      maxHands,
      verbose: true,
    },
    db,
    agent,
    wallet,
  );

  const { results, allTxids } = await runner.run();

  // ── 6. Summary ──
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`  Match Complete — ${personality.name}`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  const myWins = results.filter(r => r.winner === personality.name).length;
  log('RESULTS', {
    handsPlayed: results.length,
    myWins,
    opponentWins: results.length - myWins,
    totalOnChainTx: allTxids.length,
  });

  // Print full audit log
  runner.printAuditLog();

  sdk.close();
  db.close();
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  if (err.stack) console.error(err.stack);
  process.exit(1);
});

```
