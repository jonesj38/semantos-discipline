---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/udp-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.876858+00:00
---

# core/protocol-types/src/adapters/udp-transport.ts

```ts
/**
 * UdpTransport — abstraction over UDP sockets for testability.
 *
 * Two implementations:
 * - LoopbackUdpTransport: in-process EventEmitter-based (tests T1–T8)
 * - NodeUdpTransport: wraps node:dgram for actual Docker / VPS deployments
 *   (formerly RealUdpTransport — kept as a deprecated alias)
 *
 * Multi-group membership API (Phase 35A D35A.4) lets callers subscribe to
 * additional multicast groups dynamically after bind. This is the hook
 * Phase 34 needs for type-hash → multicast-group routing: each unique type
 * hash becomes a separate group join via `addMembership(group)`.
 *
 * Cross-references:
 *   docker-multicast-adapter.ts — consumer of this interface
 *   Phase H1 PRD — DH1.1
 *   Phase 35A PRD — D35A.4 (multi-group readiness for Phase 34)
 */

export interface RemoteInfo {
  address: string;
  port: number;
  size: number;
}

export type MessageCallback = (msg: Uint8Array, rinfo: RemoteInfo) => void;

export interface UdpTransport {
  /**
   * Bind the transport to a port. Optionally join an initial multicast group
   * during bind (equivalent to a subsequent `addMembership(group)` call).
   */
  bind(port: number, multicastGroup?: string): Promise<void>;
  send(msg: Uint8Array, port: number, address: string): Promise<void>;
  onMessage(cb: MessageCallback): void;
  close(): Promise<void>;

  // ── Phase 35A multi-group membership ──────────────────────────────
  /** Join an additional multicast group after bind. Idempotent. */
  addMembership(group: string): Promise<void>;
  /** Leave a previously joined multicast group. Idempotent. */
  dropMembership(group: string): Promise<void>;
  /** Current set of joined multicast groups. */
  memberships(): ReadonlySet<string>;
}

// ── Loopback (in-process, for tests) ────────────────────────────

export class LoopbackUdpTransport implements UdpTransport {
  /** Registry keyed by `(port, group)` so membership controls delivery. */
  private static byGroup = new Map<
    string,
    Set<LoopbackUdpTransport>
  >();
  /** Registry keyed by port (for unicast address matching). */
  private static byPort = new Map<number, Set<LoopbackUdpTransport>>();

  readonly address: string;
  private port = 0;
  private readonly groups = new Set<string>();
  private callbacks: MessageCallback[] = [];
  private closed = false;

  constructor(address: string) {
    this.address = address;
  }

  static resetAll(): void {
    LoopbackUdpTransport.byGroup.clear();
    LoopbackUdpTransport.byPort.clear();
  }

  async bind(port: number, multicastGroup?: string): Promise<void> {
    this.port = port;
    let portPeers = LoopbackUdpTransport.byPort.get(port);
    if (!portPeers) {
      portPeers = new Set();
      LoopbackUdpTransport.byPort.set(port, portPeers);
    }
    portPeers.add(this);

    if (multicastGroup) {
      await this.addMembership(multicastGroup);
    }
  }

  async addMembership(group: string): Promise<void> {
    if (this.closed) return;
    this.groups.add(group);
    const key = `${this.port}::${group}`;
    let members = LoopbackUdpTransport.byGroup.get(key);
    if (!members) {
      members = new Set();
      LoopbackUdpTransport.byGroup.set(key, members);
    }
    members.add(this);
  }

  async dropMembership(group: string): Promise<void> {
    this.groups.delete(group);
    const key = `${this.port}::${group}`;
    const members = LoopbackUdpTransport.byGroup.get(key);
    if (members) {
      members.delete(this);
      if (members.size === 0) LoopbackUdpTransport.byGroup.delete(key);
    }
  }

  memberships(): ReadonlySet<string> {
    return new Set(this.groups);
  }

  async send(msg: Uint8Array, port: number, address: string): Promise<void> {
    if (this.closed) return;
    const rinfo: RemoteInfo = {
      address: this.address,
      port: this.port,
      size: msg.length,
    };
    const copy = new Uint8Array(msg);

    // Multicast: deliver only to peers that joined this (port, group).
    const key = `${port}::${address}`;
    const groupMembers = LoopbackUdpTransport.byGroup.get(key);
    if (groupMembers) {
      for (const peer of groupMembers) {
        if (peer !== this && !peer.closed) {
          queueMicrotask(() => {
            for (const cb of peer.callbacks) cb(copy, rinfo);
          });
        }
      }
      return;
    }

    // Unicast: deliver to matching address on same port.
    const portPeers = LoopbackUdpTransport.byPort.get(port);
    if (!portPeers) return;
    for (const peer of portPeers) {
      if (peer.address === address && peer !== this && !peer.closed) {
        queueMicrotask(() => {
          for (const cb of peer.callbacks) cb(copy, rinfo);
        });
      }
    }
  }

  onMessage(cb: MessageCallback): void {
    this.callbacks.push(cb);
  }

  async close(): Promise<void> {
    this.closed = true;
    const portPeers = LoopbackUdpTransport.byPort.get(this.port);
    if (portPeers) {
      portPeers.delete(this);
      if (portPeers.size === 0) LoopbackUdpTransport.byPort.delete(this.port);
    }
    for (const group of this.groups) {
      await this.dropMembership(group);
    }
    this.callbacks = [];
  }
}

// ── Real UDP (node:dgram, for Docker / VPS) ──────────────────────

export class NodeUdpTransport implements UdpTransport {
  private socket: any = null;
  private callbacks: MessageCallback[] = [];
  private readonly groups = new Set<string>();

  readonly address: string;

  constructor(address: string) {
    this.address = address;
  }

  async bind(port: number, multicastGroup?: string): Promise<void> {
    const dgram = await import('node:dgram');
    this.socket = dgram.createSocket({ type: 'udp6', reuseAddr: true });

    return new Promise((resolve, reject) => {
      this.socket!.on('error', reject);
      this.socket!.on('message', (msg: Buffer, rinfo: any) => {
        const data = new Uint8Array(msg);
        for (const cb of this.callbacks) {
          cb(data, { address: rinfo.address, port: rinfo.port, size: rinfo.size });
        }
      });

      this.socket!.bind(port, '::', () => {
        if (multicastGroup) {
          try {
            this.socket!.addMembership(multicastGroup);
            this.groups.add(multicastGroup);
          } catch {
            // Multicast may not be available
          }
        }
        this.socket!.removeListener('error', reject);
        resolve();
      });
    });
  }

  async addMembership(group: string): Promise<void> {
    if (!this.socket) throw new Error('Socket not bound');
    if (this.groups.has(group)) return;
    try {
      this.socket.addMembership(group);
      this.groups.add(group);
    } catch (err) {
      // Re-raise so callers can see the failure (LoopbackUdpTransport is silent
      // only because its membership is pure bookkeeping).
      throw err;
    }
  }

  async dropMembership(group: string): Promise<void> {
    if (!this.socket) return;
    if (!this.groups.has(group)) return;
    try {
      this.socket.dropMembership(group);
    } catch {
      // ignore — group already dropped at the OS level
    }
    this.groups.delete(group);
  }

  memberships(): ReadonlySet<string> {
    return new Set(this.groups);
  }

  async send(msg: Uint8Array, port: number, address: string): Promise<void> {
    if (!this.socket) throw new Error('Socket not bound');
    return new Promise((resolve, reject) => {
      this.socket!.send(msg, 0, msg.length, port, address, (err: Error | null) => {
        if (err) reject(err);
        else resolve();
      });
    });
  }

  onMessage(cb: MessageCallback): void {
    this.callbacks.push(cb);
  }

  async close(): Promise<void> {
    if (this.socket) {
      return new Promise(resolve => {
        this.socket!.close(() => {
          this.groups.clear();
          resolve();
        });
      });
    }
  }
}

/**
 * @deprecated Renamed to `NodeUdpTransport` — alias preserved so existing
 * callers keep working. Prefer `NodeUdpTransport` in new code. Alias will
 * be removed in a follow-up once all importers migrate.
 */
export const RealUdpTransport = NodeUdpTransport;

```
