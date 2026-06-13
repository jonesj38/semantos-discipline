---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/stub-network-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.878528+00:00
---

# core/protocol-types/src/adapters/stub-network-adapter.ts

```ts
/**
 * StubNetworkAdapter — in-memory pub/sub for development and testing.
 *
 * Every method computes deterministic results. This is NOT a mock.
 * It is permanent infrastructure used as the dev/test harness.
 *
 * - publish() stores in local map, fires subscriber callbacks
 * - resolve() queries local map by path/content/owner/type/parent
 * - subscribe() registers callback that fires on publish
 * - No network calls, fully deterministic, synchronous-like behavior
 *
 * Cross-references:
 *   network.ts → NetworkAdapter interface
 *   adapters/memory-adapter.ts → Same pattern for StorageAdapter
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

export class StubNetworkAdapter implements NetworkAdapter {
  /** Published objects keyed by semanticPath. */
  private readonly objects = new Map<string, NetworkResult>();

  /** Subscribers keyed by topic. */
  private readonly subscribers = new Map<string, Set<(event: NetworkEvent) => void>>();

  /** Monotonic counter for deterministic txid generation. */
  private txidCounter = 0;

  /** Configured node BCA. */
  private readonly nodeBCA: string | null;

  constructor(config?: { nodeBCA?: string }) {
    this.nodeBCA = config?.nodeBCA ?? null;
  }

  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    const txid = this.generateTxid();
    const now = Date.now();
    const topic = options?.topic ?? 'tm_semantos_objects';

    const result: NetworkResult = {
      txid,
      vout: 0,
      cellBytes: object.cellBytes,
      semanticPath: object.semanticPath,
      contentHash: object.contentHash,
      ownerCert: object.ownerCert,
      typeHash: object.typeHash,
      parentPath: object.parentPath,
      publishedAt: now,
      multicastGroup: topic,
    };

    // Store in local map
    this.objects.set(object.semanticPath, result);

    const publishResult: PublishResult = {
      txid,
      publishedAt: now,
      multicastGroup: topic,
    };

    // Fire subscribers AFTER constructing the publish result
    const event: NetworkEvent = {
      type: 'object_published',
      result,
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

    for (const result of this.objects.values()) {
      if (results.length >= limit) break;

      let matches = true;

      if (query.path !== undefined && result.semanticPath !== query.path) matches = false;
      if (query.contentHash !== undefined && result.contentHash !== query.contentHash) matches = false;
      if (query.ownerCert !== undefined && result.ownerCert !== query.ownerCert) matches = false;
      if (query.typeHash !== undefined && result.typeHash !== query.typeHash) matches = false;
      if (query.parentPath !== undefined && result.parentPath !== query.parentPath) matches = false;

      if (matches) results.push(result);
    }

    return results;
  }

  async resolveBCA(_address: string): Promise<NodeInfo | null> {
    return null;
  }

  async sendToNode(_targetBCA: string, _message: Uint8Array): Promise<{ delivered: boolean }> {
    return { delivered: true };
  }

  isConnected(): boolean {
    return true;
  }

  getNodeBCA(): string | null {
    return this.nodeBCA;
  }

  /** Clear all state. Non-interface method for test cleanup. */
  clear(): void {
    this.objects.clear();
    this.subscribers.clear();
    this.txidCounter = 0;
  }

  private fireSubscribers(topic: string, event: NetworkEvent): void {
    const callbacks = this.subscribers.get(topic);
    if (callbacks) {
      for (const cb of callbacks) {
        cb(event);
      }
    }
  }

  /**
   * Generate a deterministic txid.
   * Format: "stub" + hex counter padded to 60 chars (total 64 chars like a real txid).
   */
  private generateTxid(): string {
    this.txidCounter++;
    return 'stub' + this.txidCounter.toString(16).padStart(60, '0');
  }
}

```
