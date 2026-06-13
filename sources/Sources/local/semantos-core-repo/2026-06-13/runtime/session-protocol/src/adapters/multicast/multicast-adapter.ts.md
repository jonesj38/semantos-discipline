---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/multicast-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.068248+00:00
---

# runtime/session-protocol/src/adapters/multicast/multicast-adapter.ts

```ts
/**
 * MulticastAdapter — orchestrator that wires the per-concern modules
 * under `./` behind the `NetworkAdapter` interface.
 *
 * Owns the only stateful seam (constructor wiring, lifecycle timers,
 * transport `onMessage` hookup); every reducer / codec / queue /
 * registry it composes is a pure module. See
 * docs/prd/refactor-monoliths/38-multicast-adapter-split.md.
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  NetworkQuery,
  NetworkResult,
  NodeInfo,
  PublishOptions,
  PublishResult,
  PublishableObject,
} from "@semantos/protocol-types/network";
import type { RemoteInfo } from "@semantos/protocol-types/adapters/udp-transport";

import {
  resolveConfig,
  type MulticastAdapterConfig,
  type ResolvedConfig,
} from "./config.js";
import {
  clearPeers,
  createPeerStore,
  getPeerByAddress,
  listPeers,
  peerCount,
} from "./peer-manager.js";
import { clearSubscribers, createSubscriptionStore } from "./subscription-store.js";
import {
  clearObjects,
  createObjectStore,
  objectCount,
  queryObjects,
} from "./object-store.js";
import { createOutboundQueue } from "./outbound-queue.js";
import { createGroupMembership } from "./group-membership.js";
import { handleIncoming } from "./message-handler.js";
import { applyEffects } from "./effect-applier.js";
import {
  publishObject,
  sendControlMessage,
  sendUnicast,
  subscribeTopic,
} from "./operations.js";
import { emitHeartbeatTick, evictionTick } from "./lifecycle.js";
import { resolveNodeInfo } from "./resolve-bca.js";
import { createObserverList } from "./observers.js";
import { deriveNodeIdShort } from "./wire-header.js";
import type {
  ControlMessage,
  DuplicatePathEvent,
  MulticastPeerInfo,
} from "./types.js";

export type { MulticastAdapterConfig } from "./config.js";

export class MulticastAdapter implements NetworkAdapter {
  private readonly cfg: ResolvedConfig;
  private readonly peers = createPeerStore();
  private readonly subscribers = createSubscriptionStore();
  private readonly objects = createObjectStore();
  private readonly outbound;
  private readonly membership;
  private readonly cellObservers = createObserverList<NetworkEvent>();
  private readonly peerOfflineObservers = createObserverList<MulticastPeerInfo>();
  private readonly controlObservers =
    createObserverList<{ msg: ControlMessage; rinfo: RemoteInfo }>();
  private readonly duplicatePathObservers = createObserverList<DuplicatePathEvent>();

  private bca = "";
  private nodeIdShort = 0;
  private msgIdCounter = 0;
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private evictionTimer: ReturnType<typeof setInterval> | null = null;
  private startedAt = 0;
  private running = false;
  private readonly nextMsgId = () => {
    this.msgIdCounter = (this.msgIdCounter + 1) & 0xffff;
    return this.msgIdCounter;
  };

  constructor(config: MulticastAdapterConfig) {
    this.cfg = resolveConfig(config);
    this.outbound = createOutboundQueue({
      send: (p, port, addr) => this.cfg.transport.send(p, port, addr),
    });
    this.membership = createGroupMembership({
      transport: this.cfg.transport,
      topicToGroup: this.cfg.topicToGroup,
      primaryGroup: this.cfg.primaryGroup,
    });
  }

  // ── Lifecycle ──
  async start(): Promise<void> {
    const id = await this.cfg.identity.identity();
    this.bca = id.bca;
    this.nodeIdShort = deriveNodeIdShort(id.pubkey);
    this.startedAt = Date.now();
    this.running = true;
    this.cfg.transport.onMessage((m, r) => this.onIncoming(m, r));
    await this.cfg.transport.bind(this.cfg.port, this.cfg.primaryGroup);
    this.membership.markJoined(this.cfg.primaryGroup);
    this.heartbeatTimer = setInterval(() => this.tickHeartbeat(), this.cfg.heartbeatIntervalMs);
    this.evictionTimer = setInterval(() => this.tickEviction(), this.cfg.heartbeatIntervalMs);
    this.tickHeartbeat();
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    if (this.evictionTimer) clearInterval(this.evictionTimer);
    this.heartbeatTimer = this.evictionTimer = null;
    await this.outbound.drain();
    await this.cfg.transport.close();
  }
  // ── NetworkAdapter ──
  publish(o: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    return publishObject(this.tx(), o, options);
  }
  subscribe(topic: string, cb: (e: NetworkEvent) => void): () => void {
    return subscribeTopic(this.sub(), topic, cb);
  }
  resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    return Promise.resolve(queryObjects(this.objects, query));
  }
  resolveBCA(address: string): Promise<NodeInfo | null> {
    return resolveNodeInfo(this.peers, address, this.cfg.metadataProvider);
  }
  async sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }> {
    const peer = getPeerByAddress(this.peers, targetBCA);
    if (!peer) return { delivered: false };
    await sendUnicast(this.tx(), peer.address, message);
    return { delivered: true };
  }
  isConnected(): boolean { return this.running; }
  getNodeBCA(): string | null { return this.bca || null; }
  // ── Non-interface API (preserved from legacy adapter) ──
  discoverPeers(): MulticastPeerInfo[] { return listPeers(this.peers); }
  onPeerOffline(cb: (p: MulticastPeerInfo) => void): void { this.peerOfflineObservers.add(cb); }
  onAnyCell(cb: (e: NetworkEvent) => void): () => void { return this.cellObservers.add(cb); }
  onDuplicatePath(cb: (e: DuplicatePathEvent) => void): () => void {
    return this.duplicatePathObservers.add(cb);
  }
  onControlMessage(cb: (msg: ControlMessage, r: RemoteInfo) => void): void {
    this.controlObservers.add(({ msg, rinfo }) => cb(msg, rinfo));
  }
  sendControl(msg: ControlMessage): Promise<void> {
    return sendControlMessage(this.tx(), msg);
  }
  getStats(): { peers: number; objects: number; uptime: number } {
    return {
      peers: peerCount(this.peers),
      objects: objectCount(this.objects),
      uptime: this.startedAt ? Date.now() - this.startedAt : 0,
    };
  }
  clear(): void {
    clearObjects(this.objects);
    clearSubscribers(this.subscribers);
    clearPeers(this.peers);
    this.msgIdCounter = 0;
  }

  // ── Internals (timer ticks + ctx builders) ──
  private onIncoming(msg: Uint8Array, rinfo: RemoteInfo): void {
    applyEffects(
      this.apply(),
      handleIncoming(msg, rinfo, {
        ownNodeIdShort: this.nodeIdShort,
        codec: this.cfg.codec,
        now: Date.now(),
      }),
      rinfo,
    );
  }
  private tickHeartbeat(): void {
    emitHeartbeatTick({
      cfg: this.cfg, peers: this.peers, outbound: this.outbound,
      bca: this.bca, nodeIdShort: this.nodeIdShort,
      startedAt: this.startedAt, running: this.running,
      nextMsgId: this.nextMsgId,
    });
  }
  private tickEviction(): void {
    evictionTick({
      peers: this.peers,
      staleTimeoutMs: this.cfg.staleTimeoutMs,
      peerOfflineObservers: this.peerOfflineObservers,
    });
  }
  private tx() {
    return {
      cfg: this.cfg, membership: this.membership, outbound: this.outbound,
      objects: this.objects, subscribers: this.subscribers,
      cellObservers: this.cellObservers,
      duplicatePathObservers: this.duplicatePathObservers,
      nodeIdShort: this.nodeIdShort, nextMsgId: this.nextMsgId,
    };
  }
  private sub() {
    return { cfg: this.cfg, membership: this.membership, subscribers: this.subscribers };
  }
  private apply() {
    return {
      peers: this.peers, subscribers: this.subscribers, objects: this.objects,
      cellObservers: this.cellObservers, controlObservers: this.controlObservers,
      duplicatePathObservers: this.duplicatePathObservers,
      heartbeatSink: this.cfg.heartbeatSink,
    };
  }
}

```
