---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/shard-subscription-manager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.893936+00:00
---

# core/protocol-types/src/overlay/shard-subscription-manager.ts

```ts
/**
 * ShardSubscriptionManager — multicast receiver for storage providers.
 *
 * Provider-side code that listens on IPv6 multicast groups for BRC-12
 * framed cell-token transactions. Decodes frames, extracts PushDrop
 * data, and invokes a callback for each valid cell-token.
 *
 * This runs on storage infrastructure, not on end-user devices.
 *
 * Cross-references:
 *   overlay/shard-frame.ts → ShardFrame decode, multicastAddr
 *   overlay/shard-proxy-client.ts → MULTICAST_SCOPE
 *   cell-token.ts → CellToken.extract
 */

import { Transaction } from '@bsv/sdk';
import { ShardFrame, SHARD_FRAME_HEADER_SIZE } from './shard-frame';
import { MULTICAST_SCOPE, type MulticastScope } from './shard-proxy-client';
import { CellToken } from '../cell-token';

export interface ShardSubscriptionConfig {
  /** Network interface for multicast receive. */
  iface: string;
  /** Egress port the shard proxy forwards to. Default: 9001. */
  egressPort: number;
  /** Shard bits — must match the proxy's configuration. */
  shardBits: number;
  /** Which shard groups to subscribe to (or 'all'). */
  groups: number[] | 'all';
  /** Multicast scope. Default: 'link'. */
  scope?: MulticastScope;
  /** Callback for each received cell-token. */
  onCellToken: (result: {
    txid: string;
    shardIndex: number;
    cellBytes: Uint8Array;
    semanticPath: string;
    contentHash: Uint8Array;
    ownerPubKey: Uint8Array;
  }) => Promise<void>;
}

export interface ShardMetrics {
  packetsReceived: number;
  framesDecoded: number;
  cellsExtracted: number;
  errors: number;
}

export class ShardSubscriptionManager {
  private socket: any | null = null;
  private running = false;
  private readonly metrics: ShardMetrics = {
    packetsReceived: 0,
    framesDecoded: 0,
    cellsExtracted: 0,
    errors: 0,
  };

  constructor(private config: ShardSubscriptionConfig) {}

  /**
   * Start listening on configured multicast groups.
   *
   * For each received datagram:
   * 1. Decode BRC-12 frame
   * 2. Parse BSV transaction from payload
   * 3. Extract PushDrop data from output scripts
   * 4. Call onCellToken callback with extracted cell data
   */
  async start(): Promise<void> {
    if (this.running) return;

    const dgram = await import('dgram');
    this.socket = dgram.createSocket({ type: 'udp6', reuseAddr: true });
    const port = this.config.egressPort;

    this.socket.on('message', async (msg: Buffer) => {
      this.metrics.packetsReceived++;
      await this.handleDatagram(new Uint8Array(msg));
    });

    await new Promise<void>((resolve, reject) => {
      this.socket.bind(port, (err: Error | null) => {
        if (err) reject(err);
        else resolve();
      });
    });

    // Join multicast groups
    const scope = MULTICAST_SCOPE[this.config.scope ?? 'link'];
    const numGroups = 1 << this.config.shardBits;
    const groupsToJoin = this.config.groups === 'all'
      ? Array.from({ length: numGroups }, (_, i) => i)
      : this.config.groups;

    for (const groupIndex of groupsToJoin) {
      await this.joinGroup(groupIndex, scope);
    }

    this.running = true;
  }

  /** Join an additional shard group at runtime. */
  async joinGroup(groupIndex: number, scope?: number): Promise<void> {
    if (!this.socket) return;
    const s = scope ?? MULTICAST_SCOPE[this.config.scope ?? 'link'];
    const addr = ShardFrame.multicastAddr(groupIndex, s, new Uint8Array(10));
    const addrStr = formatIPv6(addr);
    this.socket.addMembership(addrStr, this.config.iface);
  }

  /** Leave a shard group. */
  async leaveGroup(groupIndex: number): Promise<void> {
    if (!this.socket) return;
    const scope = MULTICAST_SCOPE[this.config.scope ?? 'link'];
    const addr = ShardFrame.multicastAddr(groupIndex, scope, new Uint8Array(10));
    const addrStr = formatIPv6(addr);
    this.socket.dropMembership(addrStr, this.config.iface);
  }

  /** Get metrics. */
  getMetrics(): ShardMetrics {
    return { ...this.metrics };
  }

  /** Stop listening and leave all multicast groups. */
  async stop(): Promise<void> {
    if (!this.running || !this.socket) return;
    this.running = false;
    this.socket.close();
    this.socket = null;
  }

  /** Handle a received UDP datagram. */
  private async handleDatagram(data: Uint8Array): Promise<void> {
    const decoded = ShardFrame.decode(data);
    if (!decoded) {
      this.metrics.errors++;
      return;
    }
    this.metrics.framesDecoded++;

    try {
      const tx = Transaction.fromBinary(Array.from(decoded.payload));
      const txidHex = Array.from(decoded.txid)
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
      const shardIndex = ShardFrame.shardIndex(decoded.txid, this.config.shardBits);

      for (const output of tx.outputs) {
        const extracted = CellToken.extract(output.lockingScript);
        if (!extracted) continue;

        this.metrics.cellsExtracted++;
        await this.config.onCellToken({
          txid: txidHex,
          shardIndex,
          cellBytes: extracted.cellBytes,
          semanticPath: extracted.semanticPath,
          contentHash: extracted.contentHash,
          ownerPubKey: new Uint8Array(extracted.ownerPubKey.encode(true) as number[]),
        });
      }
    } catch {
      this.metrics.errors++;
    }
  }
}

function formatIPv6(addr: Uint8Array): string {
  const groups: string[] = [];
  for (let i = 0; i < 16; i += 2) {
    groups.push(((addr[i] << 8) | addr[i + 1]).toString(16));
  }
  return groups.join(':');
}

```
