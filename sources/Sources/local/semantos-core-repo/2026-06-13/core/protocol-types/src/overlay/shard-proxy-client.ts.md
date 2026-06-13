---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/shard-proxy-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.894224+00:00
---

# core/protocol-types/src/overlay/shard-proxy-client.ts

```ts
/**
 * ShardProxyClient — UDP client for publishing cell-token transactions
 * through the bitcoin-shard-proxy.
 *
 * The shard proxy receives BRC-12 framed UDP datagrams, derives an IPv6
 * multicast group from the txid's top N bits, and fans out to all
 * subscribers on that group. This replaces HTTP polling with push-based
 * delivery for high-throughput writes.
 *
 * Cross-references:
 *   overlay/shard-frame.ts → ShardFrame encode/decode/shardIndex
 *   github.com/lightwebinc/bitcoin-shard-proxy → Go implementation
 */

import { Transaction } from '@bsv/sdk';
import { ShardFrame } from './shard-frame';

/** Multicast scope values matching the Go implementation. */
export const MULTICAST_SCOPE = {
  link: 0x02,
  site: 0x05,
  org: 0x08,
  global: 0x0E,
} as const;

export type MulticastScope = keyof typeof MULTICAST_SCOPE;

export interface ShardProxyConfig {
  /** Shard proxy ingress address. Default: 'localhost'. */
  host: string;
  /** Shard proxy ingress port. Default: 9000. */
  port: number;
  /** Shard bits — must match the proxy's configuration. */
  shardBits: number;
  /** Multicast scope — must match the proxy's configuration. Default: 'link'. */
  scope?: MulticastScope;
}

export interface PublishResult {
  txid: string;
  shardIndex: number;
  multicastGroup: string;
}

export class ShardProxyClient {
  private readonly host: string;
  private readonly port: number;
  private readonly shardBits: number;
  private readonly scope: number;
  private socket: any | null = null;

  constructor(private config: ShardProxyConfig) {
    this.host = config.host;
    this.port = config.port;
    this.shardBits = config.shardBits;
    this.scope = MULTICAST_SCOPE[config.scope ?? 'link'];
  }

  /**
   * Publish a cell-token transaction through the shard proxy.
   *
   * Wraps the transaction in a BRC-12 frame and sends via UDP.
   * The shard proxy forwards the frame to the multicast group
   * derived from the txid's top N bits.
   *
   * @param tx Signed BSV transaction containing PushDrop output(s)
   * @returns The shard group index the tx was routed to
   */
  async publish(tx: Transaction): Promise<PublishResult> {
    const txBin = tx.toBinary();
    const txidHex = tx.id('hex');

    // Convert txid hex to bytes (internal byte order = reversed display order)
    const txid = hexToBytes(txidHex);

    // Encode BRC-12 frame
    const frame = ShardFrame.encode(txid, new Uint8Array(txBin));

    // Compute shard group
    const shardIndex = ShardFrame.shardIndex(txid, this.shardBits);
    const multicastAddr = ShardFrame.multicastAddr(
      shardIndex,
      this.scope,
      new Uint8Array(10),
    );
    const multicastGroup = formatIPv6(multicastAddr);

    // Send via UDP
    await this.sendUdp(frame);

    return { txid: txidHex, shardIndex, multicastGroup };
  }

  /**
   * Compute which shard group(s) a semantic path maps to.
   *
   * Since shard routing is by txid (not semantic path), the mapping
   * is probabilistic — transactions under a given semantic path
   * distribute uniformly across all shard groups.
   */
  shardGroupsForTopic(topicName: string): {
    strategy: 'subscribe-all' | 'subscribe-range';
    groups?: { start: number; end: number };
    note: string;
  } {
    return {
      strategy: 'subscribe-all',
      note:
        `Shard routing is by txid, not topic name. Transactions for topic ` +
        `'${topicName}' distribute uniformly across all ${1 << this.shardBits} ` +
        `shard groups. Subscribe to all groups and filter by inspecting the ` +
        `PushDrop script's semantic path field.`,
    };
  }

  /** Check if the shard proxy is reachable by sending a minimal probe. */
  async healthCheck(): Promise<boolean> {
    try {
      // Send a frame with invalid magic to test connectivity.
      // A responsive proxy will receive it (and silently discard it).
      // We just check that the UDP send succeeds without error.
      const probe = new Uint8Array(44);
      await this.sendUdp(probe);
      return true;
    } catch {
      return false;
    }
  }

  /** Close the UDP socket. */
  close(): void {
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
  }

  /** Send a UDP datagram to the shard proxy ingress. */
  private async sendUdp(data: Uint8Array): Promise<void> {
    const dgram = await import('dgram');
    if (!this.socket) {
      this.socket = dgram.createSocket('udp4');
    }
    return new Promise<void>((resolve, reject) => {
      this.socket.send(
        Buffer.from(data),
        0,
        data.length,
        this.port,
        this.host,
        (err: Error | null) => {
          if (err) reject(err);
          else resolve();
        },
      );
    });
  }
}

// ── Helpers ──

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function formatIPv6(addr: Uint8Array): string {
  const groups: string[] = [];
  for (let i = 0; i < 16; i += 2) {
    groups.push(((addr[i] << 8) | addr[i + 1]).toString(16));
  }
  return groups.join(':');
}

```
