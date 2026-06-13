---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/xmpp-node/ws-xmpp-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.044355+00:00
---

# runtime/session-protocol/src/xmpp-node/ws-xmpp-transport.ts

```ts
/**
 * WsXmppTransport — a real `XmppTransport` over the runtime's native WebSocket.
 *
 * The brain-native s2s transport (SRS-XMPP §12, decision: serverless-first). It
 * is the same port `StubXmppTransport` satisfies, but over real sockets instead
 * of an in-memory bus — so `createXmppNode` runs against it UNCHANGED. No
 * ejabberd/Prosody, no stream library: each node runs a WebSocket server (accept
 * inbound peers) and dials peers out; frames are XMPP stanzas reusing the §3
 * `bundle-stanza` codec.
 *
 *   • Connection registry keyed by the directed-message host literal `[BCA]`.
 *     A dialer sends `<hello from="[selfHost]"/>` first; the acceptor learns the
 *     peer's host from it, so ONE socket carries both directions.
 *   • Directed `<message>` routed by `to="[BCA]"` → the peer's connection
 *     (dial-on-demand if absent).
 *   • Gossip pubsub: `subscribeNode` broadcasts `<sub node>` to peers; a peer's
 *     `publishItem` fans `<item>` out only to connections that subscribed.
 *   • Stream auth: NONE (v1) — `wss://` is the encryption; the `SignedBundle`
 *     cert chain is the trust (SRS-XMPP §12.1 decision 3).
 *
 * Runtime: bun-native (`Bun.serve` + global `WebSocket`). A node deployment
 * swaps the two socket primitives for `ws`; nothing else changes.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §12.
 */

import type { XmppTransport, XmppPubSubEvent, PubSubAddress } from '@semantos/protocol-types/xmpp';

// bun globals (avoid a hard bun-types dependency at the type layer).
declare const Bun: { serve(opts: unknown): { port: number; stop(closeActive?: boolean): void } };

/** Uniform send/close over a ServerWebSocket or a client WebSocket. */
interface Sender {
  send(s: string): void;
  close(): void;
}

interface Peer {
  sender: Sender | null;
  ready: boolean;
  /** Frames queued while an outbound dial is in flight. */
  queue: string[];
  /** Pubsub nodes this peer asked us to forward to it. */
  remoteSubs: Set<string>;
}

const attrOf = (name: string, s: string): string | null => {
  const m = new RegExp(`\\b${name}="([^"]*)"`).exec(s);
  return m ? m[1]! : null;
};

export interface WsXmppTransportConfig {
  /** This node's directed-message host literal, e.g. "[2602:f9f8::1]". */
  selfHost: string;
  /** Listen port; 0 (default) lets the OS assign one — read back via `.port`. */
  port?: number;
  /** Resolve a peer host literal → a ws:// URL to dial, or null if unroutable. */
  dial: (host: string) => string | null;
}

export class WsXmppTransport implements XmppTransport {
  readonly selfHost: string;
  private readonly cfg: WsXmppTransportConfig;
  private server: { port: number; stop(closeActive?: boolean): void } | null = null;
  private online = false;
  private _port = 0;

  private readonly peers = new Map<string, Peer>(); // host literal → peer
  private readonly localSubs = new Set<string>();
  private readonly messageHandlers = new Set<(xml: string) => void>();
  private readonly pubsubHandlers = new Set<(ev: XmppPubSubEvent) => void>();

  constructor(cfg: WsXmppTransportConfig) {
    this.cfg = cfg;
    this.selfHost = cfg.selfHost;
  }

  /** The actual listen port (valid after `start()`). */
  get port(): number {
    return this._port;
  }

  /** Start the WS server so peers can connect to us. */
  async start(): Promise<this> {
    const self = this;
    this.server = Bun.serve({
      port: this.cfg.port ?? 0,
      fetch(req: Request, server: { upgrade(r: Request, o?: unknown): boolean }) {
        if (server.upgrade(req, { data: { host: null } })) return undefined;
        return new Response('xmpp-s2s', { status: 426 });
      },
      websocket: {
        message(ws: { send(s: string): void; close(): void; data: { host: string | null } }, msg: string | Uint8Array) {
          const text = typeof msg === 'string' ? msg : new TextDecoder().decode(msg);
          self.onFrame(text, { send: (s) => ws.send(s), close: () => ws.close() }, ws);
        },
        close(ws: { data: { host: string | null } }) {
          self.onClose(ws.data?.host ?? null);
        },
      },
    }) as { port: number; stop(closeActive?: boolean): void };
    this._port = this.server.port;
    this.online = true;
    return this;
  }

  /** Pre-establish a connection to a peer (e.g. to exchange presence). */
  async connect(host: string): Promise<void> {
    await this.dialPeer(host);
  }

  // ── XmppTransport ──

  isOnline(): boolean {
    return this.online;
  }

  async sendStanza(xml: string): Promise<void> {
    const host = attrOf('to', xml);
    if (!host) throw new Error('WsXmppTransport.sendStanza: stanza has no `to`');
    let peer = this.peers.get(host);
    if (!peer || !peer.ready || !peer.sender) peer = await this.dialPeer(host);
    peer.sender!.send(xml);
  }

  onMessage(handler: (xml: string) => void): () => void {
    this.messageHandlers.add(handler);
    return () => this.messageHandlers.delete(handler);
  }

  onPubSubEvent(handler: (ev: XmppPubSubEvent) => void): () => void {
    this.pubsubHandlers.add(handler);
    return () => this.pubsubHandlers.delete(handler);
  }

  async subscribeNode(addr: PubSubAddress): Promise<void> {
    this.localSubs.add(addr.node);
    const frame = `<sub node="${addr.node}"/>`;
    for (const peer of this.peers.values()) if (peer.ready && peer.sender) peer.sender.send(frame);
  }

  async unsubscribeNode(addr: PubSubAddress): Promise<void> {
    this.localSubs.delete(addr.node);
    const frame = `<unsub node="${addr.node}"/>`;
    for (const peer of this.peers.values()) if (peer.ready && peer.sender) peer.sender.send(frame);
  }

  async publishItem(addr: PubSubAddress, itemId: string, payloadXml: string): Promise<void> {
    const frame = `<item node="${addr.node}" id="${itemId}">${payloadXml}</item>`;
    for (const peer of this.peers.values()) {
      if (peer.ready && peer.sender && peer.remoteSubs.has(addr.node)) peer.sender.send(frame);
    }
  }

  /** Stop the server and close all peer connections. */
  async stop(): Promise<void> {
    this.online = false;
    for (const peer of this.peers.values()) {
      try {
        peer.sender?.close();
      } catch {
        /* ignore */
      }
    }
    this.peers.clear();
    this.server?.stop(true);
    this.server = null;
  }

  // ── internals ──

  private async dialPeer(host: string): Promise<Peer> {
    const existing = this.peers.get(host);
    if (existing && existing.ready && existing.sender) return existing;
    const url = this.cfg.dial(host);
    if (!url) throw new Error(`WsXmppTransport: no route to ${host}`);

    const peer: Peer = existing ?? { sender: null, ready: false, queue: [], remoteSubs: new Set() };
    this.peers.set(host, peer);

    const ws = new (globalThis as { WebSocket: new (u: string) => WSClient }).WebSocket(url);
    const sender: Sender = { send: (s) => ws.send(s), close: () => ws.close() };

    await new Promise<void>((resolve, reject) => {
      ws.addEventListener('open', () => {
        peer.sender = sender;
        ws.send(`<hello from="${this.selfHost}"/>`); // let the peer learn our host
        peer.ready = true;
        for (const f of peer.queue.splice(0)) ws.send(f);
        this.advertiseSubsTo(sender); // re-advertise our subs on the new link
        resolve();
      });
      ws.addEventListener('error', () => reject(new Error(`WsXmppTransport: dial failed ${url}`)));
      ws.addEventListener('message', (e: { data: string | Uint8Array }) => {
        const text = typeof e.data === 'string' ? e.data : new TextDecoder().decode(e.data);
        this.onFrame(text, sender, null, host);
      });
      ws.addEventListener('close', () => this.onClose(host));
    });
    return peer;
  }

  /**
   * Dispatch one inbound frame. `knownHost` is set for client (outbound) sockets
   * where we already know the peer; for server (inbound) sockets the host is
   * learned from the peer's `<hello>` and stamped on `ws.data.host`.
   */
  private onFrame(xml: string, sender: Sender, ws: { data: { host: string | null } } | null, knownHost?: string): void {
    const s = xml.trim();

    if (s.startsWith('<hello')) {
      const from = attrOf('from', s);
      if (from) {
        const peer = this.peers.get(from) ?? { sender: null, ready: true, queue: [], remoteSubs: new Set() };
        peer.sender = sender;
        peer.ready = true;
        this.peers.set(from, peer);
        if (ws) ws.data.host = from;
        this.advertiseSubsTo(sender); // re-advertise our subs to the newly-learned peer
      }
      return;
    }
    if (s.startsWith('<message')) {
      for (const h of this.messageHandlers) h(s);
      return;
    }
    if (s.startsWith('<presence')) {
      return; // liveness only — no XmppTransport hook
    }
    if (s.startsWith('<sub') || s.startsWith('<unsub')) {
      const node = attrOf('node', s);
      const host = knownHost ?? ws?.data.host ?? null;
      if (node && host) {
        const peer = this.peers.get(host);
        if (peer) s.startsWith('<unsub') ? peer.remoteSubs.delete(node) : peer.remoteSubs.add(node);
      }
      return;
    }
    if (s.startsWith('<item')) {
      const node = attrOf('node', s);
      const itemId = attrOf('id', s) ?? '';
      const inner = /<item\b[^>]*>([\s\S]*)<\/item>$/.exec(s);
      if (node && inner) {
        const ev: XmppPubSubEvent = { node, itemId, payloadXml: inner[1]! };
        for (const h of this.pubsubHandlers) h(ev);
      }
      return;
    }
  }

  /** (Re-)advertise our active subscriptions to a peer when a link forms. */
  private advertiseSubsTo(sender: Sender): void {
    for (const node of this.localSubs) sender.send(`<sub node="${node}"/>`);
  }

  private onClose(host: string | null): void {
    if (!host) return;
    const peer = this.peers.get(host);
    if (peer) {
      peer.ready = false;
      peer.sender = null;
    }
  }
}

/** Minimal client-WebSocket surface we rely on (web-standard, bun-native). */
interface WSClient {
  send(s: string): void;
  close(): void;
  addEventListener(type: 'open' | 'error' | 'close', cb: () => void): void;
  addEventListener(type: 'message', cb: (e: { data: string | Uint8Array }) => void): void;
}

```
