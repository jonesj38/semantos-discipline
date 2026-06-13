---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/swarm/swarm-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.051063+00:00
---

# runtime/session-protocol/src/swarm/swarm-transport.ts

```ts
/**
 * SwarmTransport — the data-plane seam.
 *
 * The swarm hot path needs exactly three primitives: broadcast a raw frame to
 * the swarm group, unicast a raw frame to one peer, and receive raw frames with
 * the sender's address. The system's cell/topic `NetworkAdapter` can't
 * broadcast raw frames, so the swarm programs against this narrower port. It is
 * transport-agnostic: backed by `UdpTransport` today (loopback in tests,
 * NodeUdpTransport on a real mesh), and a WSS implementation drops in later (M9
 * swaps the implementation, the session is unchanged).
 *
 * Addresses are opaque transport strings. Multicast delivery excludes the
 * sender; unicast targets a peer's address (learned from its HAVE broadcast).
 */

import type { UdpTransport } from '@semantos/protocol-types';

export type FrameHandler = (frame: Uint8Array, fromAddress: string) => void;

export interface SwarmTransport {
  /** This node's transport address (peers address replies here). */
  localAddress(): string;
  /** Send a frame to every peer in the swarm group (except self). */
  broadcast(frame: Uint8Array): Promise<void>;
  /** Send a frame to one peer by address. */
  sendTo(address: string, frame: Uint8Array): Promise<void>;
  /** Register a frame handler. Multiple handlers are supported. */
  onFrame(handler: FrameHandler): void;
  start(): Promise<void>;
  stop(): Promise<void>;
}

export interface UdpSwarmTransportOptions {
  udp: UdpTransport;
  /** This node's address (must match the UdpTransport's bound address). */
  address: string;
  /** UDP port shared by the swarm. */
  port: number;
  /** Multicast group for the swarm (one group per swarm/topic). */
  group: string;
}

/** A SwarmTransport backed by a `UdpTransport` (loopback or node:dgram). */
export function udpSwarmTransport(opts: UdpSwarmTransportOptions): SwarmTransport {
  const { udp, address, port, group } = opts;
  const handlers: FrameHandler[] = [];
  let started = false;

  return {
    localAddress: () => address,
    async start() {
      if (started) return;
      started = true;
      udp.onMessage((msg, rinfo) => {
        for (const h of handlers) h(msg, rinfo.address);
      });
      await udp.bind(port, group);
    },
    async stop() {
      started = false;
      handlers.length = 0;
      await udp.close();
    },
    async broadcast(frame) {
      await udp.send(frame, port, group);
    },
    async sendTo(targetAddress, frame) {
      await udp.send(frame, port, targetAddress);
    },
    onFrame(handler) {
      handlers.push(handler);
    },
  };
}

// ── In-memory transport (transport-agnosticism proof / WSS-ready seam) ─────────

/**
 * A pure in-process message bus — no UdpTransport, no sockets. Used to prove
 * the swarm engine is transport-agnostic: a SwarmSession built on this runs the
 * exact same download as one built on UDP multicast, so a WSS implementation of
 * SwarmTransport (35B) drops in later with zero engine changes.
 */
export class SwarmBus {
  private readonly handlers = new Map<string, FrameHandler>();

  register(address: string, handler: FrameHandler): void {
    this.handlers.set(address, handler);
  }
  unregister(address: string): void {
    this.handlers.delete(address);
  }
  /** Deliver to every peer except the sender (async, like a real datagram). */
  broadcast(from: string, frame: Uint8Array): void {
    for (const [addr, h] of this.handlers) {
      if (addr === from) continue;
      const copy = frame.slice();
      queueMicrotask(() => h(copy, from));
    }
  }
  /** Deliver to one peer by address. */
  sendTo(from: string, to: string, frame: Uint8Array): void {
    const h = this.handlers.get(to);
    if (!h) return;
    const copy = frame.slice();
    queueMicrotask(() => h(copy, from));
  }
}

/** A SwarmTransport backed by an in-process {@link SwarmBus}. */
export function inMemorySwarmTransport(bus: SwarmBus, address: string): SwarmTransport {
  const handlers: FrameHandler[] = [];
  const fanout: FrameHandler = (frame, from) => {
    for (const h of handlers) h(frame, from);
  };
  return {
    localAddress: () => address,
    async start() {
      bus.register(address, fanout);
    },
    async stop() {
      bus.unregister(address);
      handlers.length = 0;
    },
    async broadcast(frame) {
      bus.broadcast(address, frame);
    },
    async sendTo(to, frame) {
      bus.sendTo(address, to, frame);
    },
    onFrame(handler) {
      handlers.push(handler);
    },
  };
}

```
