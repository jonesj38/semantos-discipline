---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/bsv-overlay-network-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.876303+00:00
---

# core/protocol-types/src/adapters/bsv-overlay-network-adapter.ts

```ts
/**
 * BsvOverlayNetworkAdapter — NetworkAdapter backed by BRC-22 SHIP + BRC-24 SLAP.
 *
 * Composes:
 * - TopicManagerClient for publish (BRC-22 SHIP)
 * - LookupServiceClient for resolve queries (BRC-24 SLAP)
 * - ShardProxyClient for UDP multicast (optional, for throughput)
 *
 * Decoupled from storage — this is pure network, not persistence.
 * BsvOverlayAdapter (StorageAdapter) handles byte persistence via overlay;
 * this adapter handles object movement and discovery.
 *
 * Cross-references:
 *   network.ts                      → NetworkAdapter interface
 *   overlay/topic-manager-client.ts → TopicManagerClient
 *   overlay/lookup-service-client.ts → LookupServiceClient
 *   overlay/shard-proxy-client.ts   → ShardProxyClient
 *   cell-token.ts                   → CellToken for PushDrop scripts
 *   adapters/bsv-overlay-adapter.ts → Sibling StorageAdapter (not imported)
 */

import type {
  NetworkAdapter,
  NetworkQuery,
  NetworkResult,
  NetworkEvent,
  PublishableObject,
  PublishOptions,
  PublishResult,
  NodeInfo,
} from '../network';
import { CellToken } from '../cell-token';
import { TopicManagerClient, topicForKey, type TopicManagerClientConfig } from '../overlay/topic-manager-client';
import { LookupServiceClient, type LookupServiceClientConfig } from '../overlay/lookup-service-client';
import type { ShardProxyClient } from '../overlay/shard-proxy-client';
import { deserializeCellHeader } from '../cell-header';
import {
  CELL_SIZE, HEADER_SIZE, PAYLOAD_SIZE,
  MAGIC_1, MAGIC_2, MAGIC_3, MAGIC_4,
} from '../constants';
import {
  Transaction,
  PrivateKey,
  PublicKey,
  type LookupAnswer,
} from '@bsv/sdk';

export interface BsvOverlayNetworkAdapterConfig {
  /** BSV network. Default: 'testnet'. */
  network?: 'mainnet' | 'testnet';
  /** Owner's private key for signing publish transactions. */
  ownerKey: PrivateKey;
  /** Topic manager client config override. */
  topicManagerConfig?: TopicManagerClientConfig;
  /** Lookup service client config override. */
  lookupServiceConfig?: LookupServiceClientConfig;
  /** Optional shard proxy client for UDP multicast writes. */
  shardProxy?: ShardProxyClient;
  /** This node's BCA address. */
  nodeBCA?: string;
}

export class BsvOverlayNetworkAdapter implements NetworkAdapter {
  private readonly ownerKey: PrivateKey;
  private readonly ownerPubKey: PublicKey;
  private readonly topicManager: TopicManagerClient;
  private readonly lookupService: LookupServiceClient;
  private readonly shardProxy?: ShardProxyClient;
  private readonly subscribers = new Map<string, Set<(event: NetworkEvent) => void>>();
  private readonly nodeBCAValue: string | null;

  constructor(config: BsvOverlayNetworkAdapterConfig) {
    this.ownerKey = config.ownerKey;
    this.ownerPubKey = config.ownerKey.toPublicKey();
    this.nodeBCAValue = config.nodeBCA ?? null;
    this.shardProxy = config.shardProxy;

    const networkPreset = config.network === 'mainnet' ? 'mainnet' as const : 'testnet' as const;
    this.topicManager = new TopicManagerClient({
      networkPreset,
      ...config.topicManagerConfig,
    });
    this.lookupService = new LookupServiceClient({
      networkPreset,
      ...config.lookupServiceConfig,
    });
  }

  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    const topic = options?.topic ?? this.topicForObject(object);
    const contentHashBytes = hexToBytes(object.contentHash);

    const lockingScript = CellToken.createOutputScript(
      object.cellBytes,
      object.semanticPath,
      contentHashBytes,
      this.ownerPubKey,
    );

    const tx = new Transaction();
    tx.addOutput({ lockingScript, satoshis: 1 });
    await tx.sign();

    let shardIndex: number | undefined;
    let multicastGroup: string | undefined;

    if (this.shardProxy) {
      const result = await this.shardProxy.publish(tx);
      shardIndex = result.shardIndex;
      multicastGroup = result.multicastGroup;
    } else {
      await this.topicManager.submit(tx, [topic]);
    }

    const now = Date.now();
    const txid = tx.id('hex');

    const publishResult: PublishResult = {
      txid,
      shardIndex,
      multicastGroup,
      publishedAt: now,
    };

    // Fire subscribers after publish completes
    const event: NetworkEvent = {
      type: 'object_published',
      result: {
        txid,
        vout: 0,
        cellBytes: object.cellBytes,
        semanticPath: object.semanticPath,
        contentHash: object.contentHash,
        ownerCert: object.ownerCert,
        typeHash: object.typeHash,
        parentPath: object.parentPath,
        publishedAt: now,
        multicastGroup,
      },
      timestamp: now,
    };
    this.fireSubscribers(topic, event);

    return publishResult;
  }

  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void {
    let topicSubscribers = this.subscribers.get(topic);
    if (!topicSubscribers) {
      topicSubscribers = new Set();
      this.subscribers.set(topic, topicSubscribers);
    }
    topicSubscribers.add(callback);

    return () => {
      this.subscribers.get(topic)?.delete(callback);
    };
  }

  async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    const limit = query.limit ?? 10;
    const results: NetworkResult[] = [];

    if (query.path) {
      const answer = await this.lookupService.queryByPath(query.path, {
        prefix: false,
        depth: query.depth,
      });
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.contentHash) {
      const answer = await this.lookupService.queryByContent(query.contentHash);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.ownerCert) {
      const answer = await this.lookupService.queryByOwner(query.ownerCert);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.typeHash) {
      const answer = await this.lookupService.queryByType(query.typeHash);
      results.push(...this.decodeAnswerToResults(answer));
    }

    if (query.parentPath) {
      const answer = await this.lookupService.queryByParent(query.parentPath);
      results.push(...this.decodeAnswerToResults(answer));
    }

    return results.slice(0, limit);
  }

  async resolveBCA(_address: string): Promise<NodeInfo | null> {
    // BCA resolution requires enterprise sovereign node infrastructure.
    // Placeholder for Phase 26E (node bootstrap).
    return null;
  }

  async sendToNode(_targetBCA: string, _message: Uint8Array): Promise<{ delivered: boolean }> {
    // Authenticated node-to-node messaging requires capability token wrapping.
    // Placeholder for Phase 26E (node bootstrap).
    return { delivered: false };
  }

  isConnected(): boolean {
    // Full implementation would probe SLAP resolvers.
    // For now, assume connected if constructor succeeded.
    return true;
  }

  getNodeBCA(): string | null {
    return this.nodeBCAValue;
  }

  /**
   * Determine the overlay topic for a publishable object.
   * Maps semantic path prefix to SEMANTOS_TOPICS via topicForKey().
   */
  private topicForObject(object: PublishableObject): string {
    try {
      return topicForKey(object.semanticPath);
    } catch {
      // Default topic if path prefix doesn't match
      return 'tm_semantos_objects';
    }
  }

  /**
   * Decode a LookupAnswer into NetworkResult[].
   * Converts @bsv/sdk types to primitive NetworkResult types at the boundary.
   */
  private decodeAnswerToResults(answer: LookupAnswer): NetworkResult[] {
    const decoded = this.lookupService.decodeLookupOutputs(answer);
    const now = Date.now();

    return decoded.map(output => {
      // Extract typeHash from cell header
      const header = deserializeCellHeader(output.cellBytes);
      const typeHashHex = hexFromBytes(header.typeHash);

      return {
        txid: output.txid,
        vout: output.vout,
        cellBytes: output.cellBytes,
        semanticPath: output.semanticPath,
        contentHash: hexFromBytes(output.contentHash),
        ownerCert: output.ownerPubKey.toString(),
        typeHash: typeHashHex,
        parentPath: header.parentHash ? hexFromBytes(header.parentHash) : undefined,
        publishedAt: Number(header.timestamp) || now,
      };
    });
  }

  private fireSubscribers(topic: string, event: NetworkEvent): void {
    const callbacks = this.subscribers.get(topic);
    if (callbacks) {
      for (const cb of callbacks) {
        cb(event);
      }
    }
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

function hexFromBytes(buf: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < buf.length; i++) {
    hex += buf[i].toString(16).padStart(2, '0');
  }
  return hex;
}

```
