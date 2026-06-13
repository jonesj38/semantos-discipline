---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/op-return-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.783146+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/op-return-builder.ts

```ts
/**
 * Standalone OP_RETURN tx builder + the poker cell-builder helper.
 *
 * Both are isolated from `celltoken-tx-builder.ts` so each file
 * stays under the prompt-18 LOC ceiling and so the OP_RETURN path
 * can be replaced wholesale (e.g. for batched payloads) without
 * touching the CellToken-specific code.
 */

import {
  type Transaction as TransactionType,
  LockingScript,
  P2PKH,
  Transaction,
  type LockingScript as LockingScriptType,
  type PrivateKey,
  type PublicKey,
} from '@bsv/sdk';
import { createHash } from 'crypto';

import { CellStore } from '../../../../core/protocol-types/src/cell-store';
import { MemoryAdapter } from '../../../../core/protocol-types/src/adapters/memory-adapter';
import { Linearity } from '../../../../core/protocol-types/src/constants';

import { FEE_RATE, MIN_FEE, type FundingUtxo } from './types';

/** Same hash used by the legacy direct-broadcast-engine + prompt-17. */
const POKER_HAND_TYPE_HASH = createHash('sha256')
  .update('semantos/poker/hand-state/v1')
  .digest();

export interface BuildOpReturnOptions {
  privateKey: PrivateKey;
  publicKey: PublicKey;
  funding: FundingUtxo;
  payload: string;
}

export interface BuildOpReturnResult {
  tx: TransactionType;
  /** Recycled change utxo, or null when no change is left. */
  change: FundingUtxo | null;
}

/** Build + sign a 0-sat OP_RETURN tx with one change output. */
export async function opReturnTx(opts: BuildOpReturnOptions): Promise<BuildOpReturnResult> {
  const payloadBytes = Array.from(new TextEncoder().encode(opts.payload));
  const opReturnScript = new LockingScript([
    { op: 0 }, // OP_FALSE
    { op: 0x6a }, // OP_RETURN
    payloadBytes.length <= 75
      ? { op: payloadBytes.length, data: payloadBytes }
      : payloadBytes.length <= 255
        ? { op: 0x4c, data: payloadBytes }
        : { op: 0x4d, data: payloadBytes },
  ]);

  const p2pkh = new P2PKH();
  const tx = new Transaction();

  tx.addInput({
    sourceTXID: opts.funding.txid,
    sourceOutputIndex: opts.funding.vout,
    sourceTransaction: opts.funding.sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(opts.privateKey),
  });
  tx.addOutput({ lockingScript: opReturnScript, satoshis: 0 });

  const estTxSize = 10 + 148 + (payloadBytes.length + 3 + 9) + (25 + 9);
  const fee = Math.max(estTxSize * FEE_RATE, MIN_FEE);
  const change = opts.funding.satoshis - fee;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(opts.publicKey.toAddress()) as LockingScriptType,
      satoshis: change,
    });
  }
  await tx.sign();

  const txid = tx.id('hex') as string;
  return {
    tx,
    change:
      change > 0
        ? { txid, vout: 1, satoshis: change, sourceTx: tx }
        : null,
  };
}

// ── Poker cell helper ─────────────────────────────────────────────

export interface BuildPokerCellResult {
  cellBytes: Uint8Array;
  contentHash: Uint8Array;
  semanticPath: string;
}

/**
 * Build a 1024-byte poker hand-state cell. Mirrors the legacy
 * direct-broadcast-engine helper byte-for-byte (same path, same
 * type hash, same version bump rules).
 */
export async function buildPokerCell(
  gameId: string,
  handNumber: number,
  phase: string,
  data: Record<string, unknown>,
  version?: number,
): Promise<BuildPokerCellResult> {
  const storage = new MemoryAdapter();
  const cellStore = new CellStore(storage);
  const semanticPath = `game/poker/${gameId}/hand-${handNumber}/state`;
  const ownerId = hexToBytes(
    createHash('sha256').update(gameId).digest('hex').slice(0, 32),
  );

  const payload = { gameId, handNumber, phase, ...data };
  const cellData = new TextEncoder().encode(JSON.stringify(payload));
  const cellRef = await cellStore.put(semanticPath, cellData, {
    linearity: Linearity.LINEAR,
    ownerId,
    typeHash: POKER_HAND_TYPE_HASH,
  });

  const cellBytes = await storage.read(semanticPath);
  if (!cellBytes) throw new Error('Failed to read cell');

  if (version && version > 1) {
    const dv = new DataView(cellBytes.buffer, cellBytes.byteOffset, cellBytes.byteLength);
    dv.setUint32(20, version, true);
  }

  return { cellBytes, contentHash: hexToBytes(cellRef.contentHash), semanticPath };
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

export { POKER_HAND_TYPE_HASH };

```
