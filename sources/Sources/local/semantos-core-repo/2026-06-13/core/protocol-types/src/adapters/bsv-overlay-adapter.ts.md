---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/bsv-overlay-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.877501+00:00
---

# core/protocol-types/src/adapters/bsv-overlay-adapter.ts

```ts
/**
 * BsvOverlayAdapter — StorageAdapter backed by the BSV overlay network.
 *
 * Implements the same StorageAdapter interface as MemoryAdapter and NodeFsAdapter.
 * From SemanticFS/CellStore's perspective, this is just another storage backend.
 * Internally, writes create PushDrop cell-tokens broadcast via BRC-22 SHIP,
 * and reads query BRC-24 SLAP lookup services.
 *
 * STORAGE vs NETWORK (Phase 26D separation):
 *   This adapter is a StorageAdapter — it persists bytes via the overlay network.
 *   For network publishing (pub/sub, object discovery, node-to-node messaging),
 *   use BsvOverlayNetworkAdapter (NetworkAdapter) separately. A node composes
 *   both: BsvOverlayAdapter for storage, BsvOverlayNetworkAdapter for networking.
 *   They share the same underlying clients but serve different concerns.
 *
 * Cross-references:
 *   storage.ts           → StorageAdapter interface
 *   network.ts           → NetworkAdapter interface (Phase 26D)
 *   cell-token.ts        → CellToken pack/extract
 *   overlay/topic-manager-client.ts → TopicManagerClient
 *   overlay/lookup-service-client.ts → LookupServiceClient
 *   adapters/bsv-overlay-network-adapter.ts → Sibling NetworkAdapter
 */

import type { StorageAdapter, StorageStat, StorageEvent } from '../storage';
import { CellToken } from '../cell-token';
import { TopicManagerClient, topicForKey } from '../overlay/topic-manager-client';
import { LookupServiceClient } from '../overlay/lookup-service-client';
import {
  CELL_SIZE,
  HEADER_SIZE,
  PAYLOAD_SIZE,
  MAGIC_1,
  MAGIC_2,
  MAGIC_3,
  MAGIC_4,
} from '../constants';
import { serializeCellHeader, deserializeCellHeader } from '../cell-header';
import type { CellHeader } from '../cell-header';
import {
  Transaction,
  PrivateKey,
  PublicKey,
  OP,
  LockingScript,
} from '@bsv/sdk';

export interface BsvOverlayAdapterConfig {
  /** BSV network. Default: 'testnet'. */
  network?: 'mainnet' | 'testnet';
  /** Owner's private key for signing transactions. */
  ownerKey: PrivateKey;
  /** Topic manager client config override. */
  topicManagerConfig?: ConstructorParameters<typeof TopicManagerClient>[0];
  /** Lookup service client config override. */
  lookupServiceConfig?: ConstructorParameters<typeof LookupServiceClient>[0];
  /** Optional shard proxy client for UDP multicast writes. */
  shardProxy?: { publish(tx: Transaction): Promise<{ txid: string; shardIndex: number; multicastGroup: string }> };
}

/** Tracks an on-chain UTXO for a given storage key. */
interface UtxoRef {
  txid: string;
  vout: number;
  script: LockingScript;
  satoshis: number;
}

export class BsvOverlayAdapter implements StorageAdapter {
  private readonly ownerKey: PrivateKey;
  private readonly ownerPubKey: PublicKey;
  private readonly topicManager: TopicManagerClient;
  private readonly lookupService: LookupServiceClient;
  private readonly network: 'mainnet' | 'testnet';
  private readonly shardProxy?: BsvOverlayAdapterConfig['shardProxy'];

  /** Maps storage keys to their current on-chain UTXOs. */
  private readonly outpointIndex = new Map<string, UtxoRef>();

  constructor(config: BsvOverlayAdapterConfig) {
    this.ownerKey = config.ownerKey;
    this.ownerPubKey = config.ownerKey.toPublicKey();
    this.network = config.network ?? 'testnet';
    this.shardProxy = config.shardProxy;

    const networkPreset = this.network === 'mainnet' ? 'mainnet' : 'testnet';
    this.topicManager = new TopicManagerClient({
      networkPreset,
      ...config.topicManagerConfig,
    });
    this.lookupService = new LookupServiceClient({
      networkPreset,
      ...config.lookupServiceConfig,
    });
  }

  /**
   * Write data to the overlay by creating a CellToken transaction.
   *
   * 1. Pack data into a 1024-byte cell
   * 2. Create PushDrop output script via CellToken
   * 3. Build and sign transaction
   * 4. Submit to topic manager or shard proxy
   * 5. Track resulting UTXO
   */
  async write(key: string, data: Uint8Array): Promise<void> {
    // Build a minimal cell wrapping the data
    const cellBytes = this.packCell(data);
    const contentHash = await sha256Bytes(data);
    const lockingScript = CellToken.createOutputScript(
      cellBytes,
      key,
      contentHash,
      this.ownerPubKey,
    );

    const tx = new Transaction();

    // Check if this is a state transition (spending existing UTXO)
    const existingUtxo = this.outpointIndex.get(key);
    if (existingUtxo) {
      tx.addInput({
        sourceTXID: existingUtxo.txid,
        sourceOutputIndex: existingUtxo.vout,
        sequence: 0xffffffff,
        unlockingScriptTemplate: {
          sign: async (tx: Transaction, inputIndex: number) => {
            const preimage = tx.preimage(inputIndex);
            const sig = this.ownerKey.sign(preimage);
            const sigDer = sig.toDER() as number[];
            return CellToken.createInputScript(new Uint8Array([...sigDer, 0x41]));
          },
          estimateLength: async () => 73,
        },
      });
    }

    // New CellToken output
    tx.addOutput({ lockingScript, satoshis: 1 });

    // Sign all inputs
    await tx.sign();

    // Broadcast
    if (this.shardProxy) {
      const result = await this.shardProxy.publish(tx);
      this.outpointIndex.set(key, {
        txid: result.txid,
        vout: 0,
        script: lockingScript,
        satoshis: 1,
      });
    } else {
      const result = await this.topicManager.submitForKey(tx, key);
      const txid = 'txid' in result ? (result as { txid: string }).txid : tx.id('hex');
      this.outpointIndex.set(key, {
        txid,
        vout: 0,
        script: lockingScript,
        satoshis: 1,
      });
    }
  }

  /**
   * Read data from the overlay via lookup service.
   *
   * 1. Query ls_semantos_by_path for the key
   * 2. Decode PushDrop from returned output
   * 3. Extract and return payload bytes
   */
  async read(key: string): Promise<Uint8Array | null> {
    try {
      const answer = await this.lookupService.queryByPath(key);
      const outputs = this.lookupService.decodeLookupOutputs(answer);
      if (outputs.length === 0) return null;

      const output = outputs[0];
      const header = deserializeCellHeader(output.cellBytes);
      const payloadSize = Math.min(header.totalSize, PAYLOAD_SIZE);

      // Cache the UTXO reference for future state transitions
      this.outpointIndex.set(key, {
        txid: output.txid,
        vout: output.vout,
        script: CellToken.createOutputScript(
          output.cellBytes,
          output.semanticPath,
          output.contentHash,
          output.ownerPubKey,
        ),
        satoshis: 1,
      });

      return output.cellBytes.subarray(HEADER_SIZE, HEADER_SIZE + payloadSize);
    } catch {
      return null;
    }
  }

  /** Check if a key exists on the overlay. */
  async exists(key: string): Promise<boolean> {
    try {
      const answer = await this.lookupService.queryByPath(key);
      if (answer.type !== 'output-list') return false;
      return answer.outputs.length > 0;
    } catch {
      return false;
    }
  }

  /** List keys under a prefix via lookup service. */
  async list(prefix: string): Promise<string[]> {
    try {
      const answer = await this.lookupService.queryByPath(prefix, { prefix: true });
      const outputs = this.lookupService.decodeLookupOutputs(answer);
      const normalizedPrefix = prefix.endsWith('/') ? prefix : prefix + '/';
      return outputs
        .map(o => o.semanticPath)
        .filter(p => p.startsWith(normalizedPrefix))
        .map(p => p.slice(normalizedPrefix.length));
    } catch {
      return [];
    }
  }

  /**
   * Delete by spending the UTXO without creating a new CellToken output.
   * The cell is consumed, removing it from the overlay.
   */
  async delete(key: string): Promise<boolean> {
    const utxo = this.outpointIndex.get(key);
    if (!utxo) {
      // Try to find the UTXO via lookup
      const data = await this.read(key);
      if (!data) return false;
    }

    const existing = this.outpointIndex.get(key);
    if (!existing) return false;

    const tx = new Transaction();
    tx.addInput({
      sourceTXID: existing.txid,
      sourceOutputIndex: existing.vout,
      sequence: 0xffffffff,
      unlockingScriptTemplate: {
        sign: async (tx: Transaction, inputIndex: number) => {
          const preimage = tx.preimage(inputIndex);
          const sig = this.ownerKey.sign(preimage);
          const sigDer = sig.toDER() as number[];
          return CellToken.createInputScript(new Uint8Array([...sigDer, 0x41]));
        },
        estimateLength: async () => 73,
      },
    });

    // No CellToken output — just an OP_RETURN marker
    tx.addOutput({
      lockingScript: new LockingScript([{ op: OP.OP_FALSE }, { op: OP.OP_RETURN }]),
      satoshis: 0,
    });

    await tx.sign();
    await this.topicManager.submitForKey(tx, key);
    this.outpointIndex.delete(key);
    return true;
  }

  /** Get metadata about a stored value. */
  async stat(key: string): Promise<StorageStat | null> {
    try {
      const answer = await this.lookupService.queryByPath(key);
      const outputs = this.lookupService.decodeLookupOutputs(answer);
      if (outputs.length === 0) return null;

      const output = outputs[0];
      const header = deserializeCellHeader(output.cellBytes);

      return {
        size: header.totalSize,
        modifiedAt: Number(header.timestamp),
        contentHash: hexFromBytes(output.contentHash),
      };
    } catch {
      return null;
    }
  }

  /**
   * Pack raw data into a 1024-byte cell with a minimal valid header.
   * For single-cell payloads only (data ≤ 768 bytes).
   */
  private packCell(data: Uint8Array): Uint8Array {
    if (data.length > PAYLOAD_SIZE) {
      throw new Error(
        `Data exceeds single-cell payload size (${data.length} > ${PAYLOAD_SIZE}). ` +
        `Use CellStore for multi-cell files.`,
      );
    }

    const cell = new Uint8Array(CELL_SIZE);
    const dv = new DataView(cell.buffer);

    // Magic bytes
    dv.setUint32(0, MAGIC_1, true);
    dv.setUint32(4, MAGIC_2, true);
    dv.setUint32(8, MAGIC_3, true);
    dv.setUint32(12, MAGIC_4, true);

    // Minimal header fields
    dv.setUint32(16, 1, true);  // linearity: LINEAR
    dv.setUint32(20, 1, true);  // version: 1
    dv.setUint32(86, 1, true);  // cellCount: 1
    dv.setUint32(90, data.length, true); // totalSize: actual data length

    // Timestamp
    dv.setBigUint64(78, BigInt(Date.now()), true);

    // Owner ID (first 16 bytes of pubkey hash)
    const pubkeyBytes = this.ownerPubKey.encode(true) as number[];
    cell.set(pubkeyBytes.slice(0, 16), 62);

    // Payload
    cell.set(data, HEADER_SIZE);

    return cell;
  }
}

// ── Helpers ──

async function sha256Bytes(data: Uint8Array): Promise<Uint8Array> {
  if (typeof globalThis.crypto?.subtle !== 'undefined') {
    const hash = await globalThis.crypto.subtle.digest('SHA-256', data);
    return new Uint8Array(hash);
  }
  const { createHash } = await import('crypto');
  const hex = createHash('sha256').update(data).digest('hex');
  return hexToBytes(hex);
}

function hexFromBytes(buf: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < buf.length; i++) {
    hex += buf[i].toString(16).padStart(2, '0');
  }
  return hex;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

```
