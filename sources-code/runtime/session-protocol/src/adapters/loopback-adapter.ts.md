---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/loopback-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.044986+00:00
---

# runtime/session-protocol/src/adapters/loopback-adapter.ts

```ts
/**
 * LoopbackAdapter — in-memory full `NetworkAdapter`.
 *
 * Purpose: let tests spin up two adapters that see each other's publishes,
 * resolve each other's BCAs, and send messages, with zero transport setup.
 * Replaces the `LoopbackUdpTransport + MulticastAdapter` fixture that
 * required both the UDP shim and the multicast wire format just to exercise
 * NetworkAdapter-shaped code.
 *
 * Model:
 *
 *   - A `LoopbackNetwork` holds the registry of adapters currently on "the
 *     network" plus the global index of published objects.
 *   - Each `LoopbackAdapter` registers itself on `start()` and deregisters
 *     on `stop()`.
 *   - `publish()` inserts the object into the network's global index and
 *     synchronously fans out to every registered adapter's topic subscribers
 *     (including the publisher's own — mirroring MulticastAdapter semantics
 *     where the loopback interface receives your own frames).
 *   - `resolve()` queries the network-wide index.
 *   - A module-level `DEFAULT_LOOPBACK_NETWORK` exists for tests that don't
 *     care which network they join. Pass an explicit `network` to isolate.
 *
 * Non-goals: wire-compatibility, heartbeats, peer eviction, metering,
 * metadata injection, topic→group mapping. That's `MulticastAdapter`'s job.
 * Loopback is deliberately thin.
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
} from "@semantos/protocol-types/network";
import type { BCAProvider } from "./bca-provider.js";

// ---------------------------------------------------------------------------
// LoopbackNetwork
// ---------------------------------------------------------------------------

/**
 * The shared "network" bus. Adapters register themselves on start() and
 * the network fans publishes out to every registered adapter.
 */
export class LoopbackNetwork {
  /** Registered adapters keyed by their BCA. */
  private readonly peers = new Map<string, LoopbackAdapter>();
  /** All published objects visible to any adapter, keyed by txid. */
  private readonly objects = new Map<string, NetworkResult>();
  /** Monotonic counter for deterministic fake txids. */
  private txidCounter = 0;

  // ── Package-internal: adapter lifecycle ────────────────────

  /** @internal */
  registerPeer(bca: string, adapter: LoopbackAdapter): void {
    this.peers.set(bca, adapter);
  }

  /** @internal */
  unregisterPeer(bca: string): void {
    this.peers.delete(bca);
  }

  /** @internal */
  getPeer(bca: string): LoopbackAdapter | null {
    return this.peers.get(bca) ?? null;
  }

  // ── Package-internal: publish fan-out + object index ───────

  /** @internal */
  fanout(topic: string, event: NetworkEvent): void {
    for (const peer of this.peers.values()) {
      peer._deliver(topic, event);
    }
  }

  /** @internal */
  recordObject(result: NetworkResult): void {
    this.objects.set(result.txid, result);
  }

  /** @internal */
  objectsMatching(query: NetworkQuery): NetworkResult[] {
    const limit = query.limit ?? 10;
    const results: NetworkResult[] = [];
    for (const r of this.objects.values()) {
      if (results.length >= limit) break;
      if (query.path !== undefined && r.semanticPath !== query.path) continue;
      if (
        query.contentHash !== undefined &&
        r.contentHash !== query.contentHash
      ) {
        continue;
      }
      if (query.ownerCert !== undefined && r.ownerCert !== query.ownerCert) {
        continue;
      }
      if (query.typeHash !== undefined && r.typeHash !== query.typeHash) {
        continue;
      }
      if (
        query.parentPath !== undefined &&
        r.parentPath !== query.parentPath
      ) {
        continue;
      }
      results.push(r);
    }
    return results;
  }

  /** @internal */
  nextTxid(): string {
    this.txidCounter += 1;
    return `loopback-${this.txidCounter.toString(16).padStart(16, "0")}`;
  }

  // ── Public API ─────────────────────────────────────────────

  /** List of currently-registered peer BCAs. Handy for test assertions. */
  knownPeers(): string[] {
    return Array.from(this.peers.keys());
  }

  /**
   * Wipe all state: peers, objects, txid counter. Call between test cases
   * when using `DEFAULT_LOOPBACK_NETWORK` to avoid cross-test pollution.
   */
  reset(): void {
    this.peers.clear();
    this.objects.clear();
    this.txidCounter = 0;
  }
}

/**
 * Module-level default network. Adapters constructed without an explicit
 * `network` argument join this one. Tests that don't isolate should call
 * `DEFAULT_LOOPBACK_NETWORK.reset()` before/after to avoid pollution.
 */
export const DEFAULT_LOOPBACK_NETWORK = new LoopbackNetwork();

// ---------------------------------------------------------------------------
// LoopbackAdapter
// ---------------------------------------------------------------------------

export interface LoopbackAdapterConfig {
  /** BCAProvider supplying this adapter's identity. */
  identity: BCAProvider;
  /** Network to join. Defaults to `DEFAULT_LOOPBACK_NETWORK`. */
  network?: LoopbackNetwork;
  /** Optional baseline fields surfaced by `resolveBCA`. */
  nodeInfoBase?: Partial<Omit<NodeInfo, "bca" | "uptime">>;
}

export class LoopbackAdapter implements NetworkAdapter {
  private readonly identityProvider: BCAProvider;
  private readonly network: LoopbackNetwork;
  private readonly nodeInfoBase: Partial<Omit<NodeInfo, "bca" | "uptime">>;
  private readonly subscribers = new Map<
    string,
    Set<(event: NetworkEvent) => void>
  >();

  private bca = "";
  private running = false;
  private startedAt = 0;

  constructor(cfg: LoopbackAdapterConfig) {
    this.identityProvider = cfg.identity;
    this.network = cfg.network ?? DEFAULT_LOOPBACK_NETWORK;
    this.nodeInfoBase = cfg.nodeInfoBase ?? {};
  }

  // ── Lifecycle ──────────────────────────────────────────────

  async start(): Promise<void> {
    const id = await this.identityProvider.identity();
    this.bca = id.bca;
    this.startedAt = Date.now();
    this.running = true;
    this.network.registerPeer(this.bca, this);
  }

  async stop(): Promise<void> {
    if (!this.running) return;
    this.running = false;
    this.network.unregisterPeer(this.bca);
  }

  // ── NetworkAdapter interface ───────────────────────────────

  async publish(
    obj: PublishableObject,
    options?: PublishOptions,
  ): Promise<PublishResult> {
    const topic = options?.topic ?? "tm_semantos_objects";
    const now = Date.now();
    const txid = this.network.nextTxid();

    const result: NetworkResult = {
      txid,
      vout: 0,
      cellBytes: obj.cellBytes,
      semanticPath: obj.semanticPath,
      contentHash: obj.contentHash,
      ownerCert: obj.ownerCert,
      typeHash: obj.typeHash,
      parentPath: obj.parentPath,
      publishedAt: now,
      multicastGroup: topic,
    };

    this.network.recordObject(result);
    this.network.fanout(topic, {
      type: "object_published",
      result,
      timestamp: now,
    });

    return { txid, publishedAt: now, multicastGroup: topic };
  }

  subscribe(
    topic: string,
    callback: (event: NetworkEvent) => void,
  ): () => void {
    let topicSubs = this.subscribers.get(topic);
    if (!topicSubs) {
      topicSubs = new Set();
      this.subscribers.set(topic, topicSubs);
    }
    topicSubs.add(callback);

    return () => {
      const subs = this.subscribers.get(topic);
      if (!subs) return;
      subs.delete(callback);
      if (subs.size === 0) this.subscribers.delete(topic);
    };
  }

  async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    return this.network.objectsMatching(query);
  }

  async resolveBCA(address: string): Promise<NodeInfo | null> {
    const peer = this.network.getPeer(address);
    if (!peer) return null;

    return {
      bca: address,
      nodeCert: this.nodeInfoBase.nodeCert ?? "",
      name: this.nodeInfoBase.name ?? address,
      extensions: this.nodeInfoBase.extensions ?? [],
      adapters:
        this.nodeInfoBase.adapters ?? {
          storage: "memory",
          identity: "loopback",
          anchor: "stub",
          network: "loopback",
        },
      version: this.nodeInfoBase.version ?? "0.0.1",
      uptime: Date.now() - peer._startedAt,
      lastAnchorProof: this.nodeInfoBase.lastAnchorProof,
    };
  }

  async sendToNode(
    targetBCA: string,
    _message: Uint8Array,
  ): Promise<{ delivered: boolean }> {
    const peer = this.network.getPeer(targetBCA);
    return { delivered: peer !== null };
  }

  isConnected(): boolean {
    return this.running;
  }

  getNodeBCA(): string | null {
    return this.bca || null;
  }

  // ── Package-internal (called by LoopbackNetwork) ───────────

  /** @internal */
  _deliver(topic: string, event: NetworkEvent): void {
    const subs = this.subscribers.get(topic);
    if (!subs) return;
    // Snapshot to tolerate unsubscribe-during-delivery.
    for (const cb of Array.from(subs)) cb(event);
  }

  /** @internal */
  get _startedAt(): number {
    return this.startedAt;
  }
}

```
