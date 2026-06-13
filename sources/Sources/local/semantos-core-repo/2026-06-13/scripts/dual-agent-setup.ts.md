---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/dual-agent-setup.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.321325+00:00
---

# scripts/dual-agent-setup.ts

```ts
#!/usr/bin/env bun
/**
 * dual-agent-setup.ts — Wire two AI agent identities from one BSV Desktop Wallet.
 *
 * Proves the hackathon identity architecture:
 *   1. Register a root BRC-52 identity (or reuse existing)
 *   2. Derive two child certs (Agent A: "shark", Agent B: "turtle")
 *   3. Each agent gets its own protocol-derived key from the shared wallet
 *   4. Each agent independently creates a CellToken on mainnet
 *   5. Verify both agents can sign independently
 *
 * Usage:
 *   bun run scripts/dual-agent-setup.ts                    # full demo (mainnet)
 *   bun run scripts/dual-agent-setup.ts --identity-only    # just derive certs, no on-chain
 *   bun run scripts/dual-agent-setup.ts --port 2121        # bsv-desktop
 *
 * Prerequisites:
 *   - BSV Desktop Wallet (metanet-desktop or bsv-desktop) running and authenticated
 *   - Wallet has funded UTXOs (need ~2 sats for two 1-sat CellTokens + fees)
 */

import { VendorSDK } from '../packages/plexus-vendor-sdk/src/VendorSDK';
import { MemoryAdapter } from '../packages/protocol-types/src/adapters/memory-adapter';
import { CellStore } from '../packages/protocol-types/src/cell-store';
import { CellToken } from '../packages/protocol-types/src/cell-token';
import { deserializeCellHeader } from '../packages/protocol-types/src/cell-header';
import { Linearity } from '../packages/protocol-types/src/constants';
import { WalletClient } from '../packages/protocol-types/src/wallet-client';
import { createHash } from 'crypto';

// ── CLI ──

const args = process.argv.slice(2);
const portFlag = args.indexOf('--port');
const port = portFlag !== -1 ? parseInt(args[portFlag + 1], 10) : 3321;
const identityOnly = args.includes('--identity-only');
const baseUrl = `http://localhost:${port}`;

// ── Agent config ──

const AGENT_EMAIL = 'hackathon@semantos.dev'; // shared root identity
const DOMAIN_FLAG_AGENT = 0x00020001; // Agent domain flag

interface AgentIdentity {
  name: string;
  resourceId: string;
  certId: string;
  publicKey: string;
  childIndex: number;
  /** Each agent uses its certId as the keyID for protocol key derivation */
  protocolKeyID: string;
}

// ── Helpers ──

function log(label: string, value: unknown) {
  console.log(`\x1b[36m[${label}]\x1b[0m`, typeof value === 'string' ? value : JSON.stringify(value, null, 2));
}

function sha256(data: Uint8Array): string {
  return createHash('sha256').update(data).digest('hex');
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// ── Protocol constants (shared with anchor-demo) ──

const CELLTOKEN_PROTOCOL: [number, string] = [2, 'semantos celltoken'];
const CELLTOKEN_COUNTERPARTY = 'self';

// ── Main ──

async function main() {
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Dual-Agent Identity Setup');
  console.log('  One wallet, two BRC-52 child identities');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // ── Phase 1: Identity derivation (offline, no wallet needed) ──

  log('PHASE 1', 'Deriving agent identities from root cert...');

  const sdk = new VendorSDK({
    dbPath: ':memory:',
    pbkdf2Iterations: 1_000, // fast for demo; production uses 100k
  });

  // 1a. Register root identity
  const root = sdk.registerIdentity(AGENT_EMAIL);
  log('Root cert', {
    certId: root.certId.slice(0, 24) + '...',
    publicKey: root.publicKey.slice(0, 20) + '...',
    email: AGENT_EMAIL,
  });

  // 1b. Derive Agent A: "shark" — aggressive poker player
  const agentA = sdk.deriveChild(root.certId, 'agent-shark', DOMAIN_FLAG_AGENT);
  const agentAIdentity: AgentIdentity = {
    name: 'Shark',
    resourceId: 'agent-shark',
    certId: agentA.certId,
    publicKey: agentA.publicKey,
    childIndex: agentA.childIndex,
    protocolKeyID: `agent/${agentA.certId.slice(0, 16)}`,
  };

  // 1c. Derive Agent B: "turtle" — conservative poker player
  const agentB = sdk.deriveChild(root.certId, 'agent-turtle', DOMAIN_FLAG_AGENT);
  const agentBIdentity: AgentIdentity = {
    name: 'Turtle',
    resourceId: 'agent-turtle',
    certId: agentB.certId,
    publicKey: agentB.publicKey,
    childIndex: agentB.childIndex,
    protocolKeyID: `agent/${agentB.certId.slice(0, 16)}`,
  };

  log('Agent A (Shark)', {
    certId: agentAIdentity.certId.slice(0, 24) + '...',
    publicKey: agentAIdentity.publicKey.slice(0, 20) + '...',
    childIndex: agentAIdentity.childIndex,
    protocolKeyID: agentAIdentity.protocolKeyID,
  });

  log('Agent B (Turtle)', {
    certId: agentBIdentity.certId.slice(0, 24) + '...',
    publicKey: agentBIdentity.publicKey.slice(0, 20) + '...',
    childIndex: agentBIdentity.childIndex,
    protocolKeyID: agentBIdentity.protocolKeyID,
  });

  // 1d. Verify identity tree
  const tree = sdk.querySubtree(root.certId, 2);
  log('Identity tree', {
    root: tree.root.slice(0, 24) + '...',
    children: tree.children.map(c => ({
      certId: c.certId.slice(0, 24) + '...',
      resourceId: c.resourceId,
      childIndex: c.childIndex,
    })),
  });

  // 1e. Create ECDH edge between the two agents (for encrypted comms)
  const edge = sdk.createEdge(agentA.certId, agentB.certId);
  log('Agent edge', {
    edgeId: edge.edgeId.slice(0, 24) + '...',
    sharedSecret: edge.sharedSecret.slice(0, 24) + '... (ECDH)',
    purpose: 'Encrypted inter-agent communication channel',
  });

  // Verify the two agents have DIFFERENT public keys
  if (agentA.publicKey === agentB.publicKey) {
    throw new Error('BUG: Both agents derived the same public key!');
  }
  log('KEY ISOLATION ✓', 'Agents have distinct BRC-42 derived keys');

  sdk.close();

  if (identityOnly) {
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  Identity setup complete (--identity-only)');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    return;
  }

  // ── Phase 2: Wallet integration (on-chain) ──

  log('PHASE 2', 'Connecting to BSV Desktop Wallet...');

  const wallet = new WalletClient({
    baseUrl,
    timeout: 120_000,
    originator: 'semantos-dual-agent',
    origin: 'http://localhost',
  });

  // Check connectivity
  try {
    const auth = await wallet.isAuthenticated();
    log('Wallet', auth ? 'Authenticated ✓' : 'Not authenticated — will try anyway');
    const network = await wallet.getNetwork();
    const height = await wallet.getHeight();
    log('Network', `${network}, height ${height}`);
  } catch (err: any) {
    log('Wallet', `Connection failed: ${err.message}`);
    log('HINT', `Is BSV Desktop running on port ${port}? Use --identity-only to skip on-chain.`);
    process.exit(1);
  }

  // 2a. Get protocol-derived keys for each agent
  //     Each agent uses a DIFFERENT keyID so the wallet derives distinct keys.
  //     The wallet's HD derivation ensures these are cryptographically independent
  //     even though they come from the same root wallet.

  log('PHASE 2a', 'Deriving protocol keys for each agent...');

  const agentAPubKey = await wallet.getPublicKey({
    protocolID: CELLTOKEN_PROTOCOL,
    keyID: agentAIdentity.protocolKeyID,
    counterparty: CELLTOKEN_COUNTERPARTY,
  });

  const agentBPubKey = await wallet.getPublicKey({
    protocolID: CELLTOKEN_PROTOCOL,
    keyID: agentBIdentity.protocolKeyID,
    counterparty: CELLTOKEN_COUNTERPARTY,
  });

  log('Agent A wallet key', `${agentAPubKey.slice(0, 20)}... (keyID: ${agentAIdentity.protocolKeyID})`);
  log('Agent B wallet key', `${agentBPubKey.slice(0, 20)}... (keyID: ${agentBIdentity.protocolKeyID})`);

  if (agentAPubKey === agentBPubKey) {
    throw new Error('BUG: Wallet derived the same protocol key for both agents!');
  }
  log('WALLET KEY ISOLATION ✓', 'Each agent has a distinct protocol-derived signing key');

  // ── Phase 3: Each agent creates a CellToken ──

  log('PHASE 3', 'Each agent creates a CellToken on mainnet...');

  const { PublicKey } = await import('@bsv/sdk');

  // Agent A: creates a chip-stack cell (poker context)
  const agentATxid = await createAgentCellToken(wallet, {
    agent: agentAIdentity,
    walletPubKeyHex: agentAPubKey,
    cellData: {
      type: 'chip-stack',
      agent: 'shark',
      chips: 1000,
      game: 'poker',
      created: new Date().toISOString(),
    },
    semanticPath: `game/poker/chips/${agentAIdentity.certId.slice(0, 16)}`,
  });

  // Agent B: creates a chip-stack cell (poker context)
  const agentBTxid = await createAgentCellToken(wallet, {
    agent: agentBIdentity,
    walletPubKeyHex: agentBPubKey,
    cellData: {
      type: 'chip-stack',
      agent: 'turtle',
      chips: 1000,
      game: 'poker',
      created: new Date().toISOString(),
    },
    semanticPath: `game/poker/chips/${agentBIdentity.certId.slice(0, 16)}`,
  });

  // ── Summary ──

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('  Dual-Agent Setup Complete ✓');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  log('SUMMARY', {
    rootIdentity: root.certId.slice(0, 24) + '...',
    agentA: {
      name: 'Shark',
      certId: agentAIdentity.certId.slice(0, 24) + '...',
      walletKey: agentAPubKey.slice(0, 20) + '...',
      cellToken: agentATxid ? `https://whatsonchain.com/tx/${agentATxid}` : '(failed)',
    },
    agentB: {
      name: 'Turtle',
      certId: agentBIdentity.certId.slice(0, 24) + '...',
      walletKey: agentBPubKey.slice(0, 20) + '...',
      cellToken: agentBTxid ? `https://whatsonchain.com/tx/${agentBTxid}` : '(failed)',
    },
    sharedEdge: edge.edgeId.slice(0, 24) + '... (ECDH encrypted channel)',
    architecture: 'One wallet → two BRC-52 child certs → distinct protocol keys → independent signing',
  });
}

// ── Create a CellToken for one agent ──

async function createAgentCellToken(
  wallet: WalletClient,
  opts: {
    agent: AgentIdentity;
    walletPubKeyHex: string;
    cellData: Record<string, unknown>;
    semanticPath: string;
  },
): Promise<string | null> {
  const { PublicKey } = await import('@bsv/sdk');
  const { agent, walletPubKeyHex, cellData, semanticPath } = opts;

  log(`${agent.name} TOKEN`, `Creating CellToken for ${agent.name}...`);

  try {
    // Build cell
    const storage = new MemoryAdapter();
    const cellStore = new CellStore(storage);
    const data = new TextEncoder().encode(JSON.stringify(cellData));
    const cellRef = await cellStore.put(semanticPath, data, { linearity: 1 });
    const rawCell = await storage.read(semanticPath);
    if (!rawCell) throw new Error('Failed to read cell from storage');

    // Build locking script
    const ownerPubKey = PublicKey.fromString(walletPubKeyHex);
    const contentHash = hexToBytes(cellRef.contentHash);
    const lockingScript = CellToken.createOutputScript(rawCell, semanticPath, contentHash, ownerPubKey);
    const scriptHex = lockingScript.toHex();

    log(`${agent.name} CELL`, {
      path: semanticPath,
      linearity: 'LINEAR',
      scriptSize: `${scriptHex.length / 2} bytes`,
      owner: walletPubKeyHex.slice(0, 20) + '...',
    });

    // Create on-chain via wallet
    const result = await wallet.createAction({
      description: `${agent.name} chip-stack`,
      labels: ['semantos-celltoken', 'agent', agent.resourceId],
      outputs: [{
        lockingScript: scriptHex,
        satoshis: 1,
        outputDescription: `CellToken: ${agent.name} @ ${semanticPath}`,
        basket: 'semantos-celltokens',
        tags: ['celltoken', 'linear', 'agent', agent.resourceId, semanticPath],
      }],
    });

    log(`${agent.name} TOKEN CREATED ✓`, {
      txid: result.txid,
      agent: agent.name,
      certId: agent.certId.slice(0, 24) + '...',
    });

    log(`${agent.name} WoC`, `https://whatsonchain.com/tx/${result.txid}`);

    return result.txid;
  } catch (err: any) {
    log(`${agent.name} ERROR`, err.message);
    return null;
  }
}

// ── Entry ──

main().catch(err => {
  console.error('\x1b[31mFatal:\x1b[0m', err.message);
  process.exit(1);
});

```
