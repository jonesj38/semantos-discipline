---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/wallet-stake.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.430924+00:00
---

# cartridges/chess/web/src/core/wallet-stake.ts

```ts
/**
 * wallet-stake.ts — BRC-100 chess stake funding helper.
 *
 * Builds a P2PKH locking script from the wallet's identity public key and
 * calls the wallet adapter's createAction to lock the stake on-chain.
 * Works with any WalletAdapter (Metanet Desktop on :3321, or our headless
 * wallet when it's slotted in as a BRC-100 provider).
 *
 * The locking script is a standard P2PKH:
 *   OP_DUP OP_HASH160 <hash160(pubkey)> OP_EQUALVERIFY OP_CHECKSIG
 * so any BRC-100 wallet can recognise and spend it.
 */

import { sha256 } from '@noble/hashes/sha2';
import { ripemd160 } from '@noble/hashes/ripemd160';
import type { WalletAdapter } from './wallet-adapter.js';

// ── Helpers ────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2)
    out[i >> 1] = parseInt(hex.slice(i, i + 2), 16);
  return out;
}

function bytesToHex(b: Uint8Array): string {
  return Array.from(b).map((x) => x.toString(16).padStart(2, '0')).join('');
}

/** RIPEMD160(SHA256(pubkeyBytes)) */
function hash160(pubkey: Uint8Array): Uint8Array {
  return ripemd160(sha256(pubkey));
}

/**
 * Build a P2PKH locking script (hex) from a 33-byte compressed pubkey hex.
 *   76 a9 14 <20-byte hash160> 88 ac
 */
export function pubkeyHexToP2pkhScript(pubkeyHex: string): string {
  const h = bytesToHex(hash160(hexToBytes(pubkeyHex)));
  return `76a914${h}88ac`;
}

// ── Result ─────────────────────────────────────────────────────────────

export interface StakeResult {
  /** Display-order (big-endian) txid hex — safe to show in UI or log. */
  txidHex: string;
  /** The P2PKH locking script used (hex). */
  lockingScript: string;
}

// ── Main ───────────────────────────────────────────────────────────────

/**
 * Fund a chess stake output on-chain via the wallet adapter.
 *
 * @param adapter   - The active BRC-100 wallet adapter.
 * @param gameId    - The game ID (used in the output description).
 * @param stakeSats - Amount to lock, in satoshis.
 * @param color     - Which side this player is staking for.
 * @returns txidHex (BE) and the locking script used.
 * @throws if the wallet rejects, times out, or returns an unexpected response.
 */
export async function fundChessStake(
  adapter: WalletAdapter,
  gameId: string,
  stakeSats: number,
  color: 'white' | 'black' | 'join',
): Promise<StakeResult> {
  const pubkeyHex = await adapter.getIdentityKey();
  const lockingScript = pubkeyHexToP2pkhScript(pubkeyHex);

  const result = await adapter.createAction({
    description: `Chess stake: ${color} in game ${gameId} — ${stakeSats} sats`,
    outputs: [
      {
        lockingScript,
        satoshis: stakeSats,
        outputDescription: `chess stake (${color}) — ${gameId}`,
      },
    ],
  });

  return { txidHex: result.txidHex, lockingScript };
}

```
