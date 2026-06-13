---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/stub-xmpp-transport.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.863475+00:00
---

# core/protocol-types/src/xmpp/stub-xmpp-transport.ts

```ts
/**
 * StubXmppTransport — in-memory XmppTransport (the development / test tier).
 *
 * The XMPP analogue of `StubNetworkAdapter`: a fully in-process implementation
 * of the `XmppTransport` port that `XmppNetworkAdapter` consumes, with NO
 * stream library, server, or socket.  Many `StubXmppTransport`s attach to one
 * shared `InMemoryXmppBus`, which routes:
 *
 *   • directed <message> stanzas — by the bracketed host literal in `to="[…]"`,
 *     so `sendToNode([BCA], …)` lands on the transport that registered that
 *     host (and only that one);
 *   • pubsub items — fanned out to every transport subscribed to the node id
 *     (= the type-multicast group string), INCLUDING the publisher, mirroring a
 *     real XEP-0060 service that notifies the publisher's own subscription.
 *
 * The bus retains the last `retain` items per node so `fetchItems` (and hence
 * `XmppNetworkAdapter.resolve`) returns history, the way MAM / pubsub item
 * persistence would.  This is enough to exercise the full adapter path
 * end-to-end; the real `@xmpp/client` / brain-native s2s port swaps in at
 * integration without touching the adapter.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §7 + §11
 * (`XmppTransport` impl deliverable).
 */

import type { PubSubAddress } from './jid';
import type { XmppPubSubEvent, XmppTransport } from './xmpp-network-adapter';

type MessageHandler = (xml: string) => void;
type PubSubHandler = (ev: XmppPubSubEvent) => void;

interface RetainedItem {
  itemId: string;
  payloadXml: string;
}

/** Parse the host literal out of a `to="[host]"` (or `to="host"`) attribute. */
function toHostOf(stanzaXml: string): string | null {
  const m = /\bto="([^"]*)"/.exec(stanzaXml);
  if (!m) return null;
  return m[1]!;
}

/**
 * The shared in-memory fabric.  Construct one, then `bus.connect(host)` for each
 * node to obtain its `StubXmppTransport`.
 */
export class InMemoryXmppBus {
  /** host literal (e.g. "[2602:f9f8::1]") → its transport. */
  private readonly byHost = new Map<string, StubXmppTransport>();
  /** All attached transports (for pubsub fan-out lookup). */
  private readonly transports = new Set<StubXmppTransport>();
  /** node id (multicast group string) → retained items (newest last). */
  private readonly retained = new Map<string, RetainedItem[]>();
  /** Per-node retention cap. */
  private readonly retain: number;

  constructor(opts: { retain?: number } = {}) {
    this.retain = opts.retain ?? 50;
  }

  /** Attach a node identified by its directed-message host literal. */
  connect(hostLiteral: string): StubXmppTransport {
    const t = new StubXmppTransport(this, hostLiteral);
    this.byHost.set(hostLiteral, t);
    this.transports.add(t);
    return t;
  }

  /** @internal — detach a transport (its `close()`). */
  _disconnect(t: StubXmppTransport): void {
    this.transports.delete(t);
    if (this.byHost.get(t.hostLiteral) === t) this.byHost.delete(t.hostLiteral);
  }

  /** @internal — route a directed stanza to the transport owning its `to` host. */
  _routeDirected(xml: string): void {
    const host = toHostOf(xml);
    if (host === null) return;
    const target = this.byHost.get(host);
    if (target) target._deliverMessage(xml);
    // No registered host → dropped (an offline/unknown peer).  A real server
    // would queue via MAM; the stub deliberately drops so tests can assert it.
  }

  /** @internal — record + fan out a pubsub item to every node subscriber. */
  _publish(node: string, itemId: string, payloadXml: string): void {
    const items = this.retained.get(node) ?? [];
    items.push({ itemId, payloadXml });
    if (items.length > this.retain) items.splice(0, items.length - this.retain);
    this.retained.set(node, items);
    const ev: XmppPubSubEvent = { node, itemId, payloadXml };
    for (const t of this.transports) t._deliverPubSub(node, ev);
  }

  /** @internal — newest-last retained items for a node, capped to `limit`. */
  _itemsFor(node: string, limit: number): RetainedItem[] {
    const items = this.retained.get(node) ?? [];
    return items.slice(-limit);
  }
}

/**
 * One node's view of the bus.  Implements the `XmppTransport` port; pass it
 * straight to `new XmppNetworkAdapter({ transport, … })`.
 */
export class StubXmppTransport implements XmppTransport {
  private online = true;
  private readonly messageHandlers = new Set<MessageHandler>();
  private readonly pubsubHandlers = new Set<PubSubHandler>();
  /** node ids this transport has joined. */
  private readonly joined = new Set<string>();

  constructor(
    private readonly bus: InMemoryXmppBus,
    /** This node's directed-message host literal, e.g. "[2602:f9f8::1]". */
    public readonly hostLiteral: string,
  ) {}

  // ── XmppTransport ──

  isOnline(): boolean {
    return this.online;
  }

  async sendStanza(xml: string): Promise<void> {
    if (!this.online) throw new Error('StubXmppTransport offline');
    this.bus._routeDirected(xml);
  }

  onMessage(handler: MessageHandler): () => void {
    this.messageHandlers.add(handler);
    return () => this.messageHandlers.delete(handler);
  }

  onPubSubEvent(handler: PubSubHandler): () => void {
    this.pubsubHandlers.add(handler);
    return () => this.pubsubHandlers.delete(handler);
  }

  async subscribeNode(addr: PubSubAddress): Promise<void> {
    this.joined.add(addr.node);
  }

  async unsubscribeNode(addr: PubSubAddress): Promise<void> {
    this.joined.delete(addr.node);
  }

  async publishItem(addr: PubSubAddress, itemId: string, payloadXml: string): Promise<void> {
    if (!this.online) throw new Error('StubXmppTransport offline');
    this.bus._publish(addr.node, itemId, payloadXml);
  }

  async fetchItems(addr: PubSubAddress, limit: number): Promise<RetainedItem[]> {
    return this.bus._itemsFor(addr.node, limit);
  }

  // ── test/lifecycle controls ──

  /** Simulate a disconnect (isOnline() → false; sends throw). */
  setOnline(v: boolean): void {
    this.online = v;
  }

  /** Detach from the bus. */
  close(): void {
    this.bus._disconnect(this);
    this.messageHandlers.clear();
    this.pubsubHandlers.clear();
    this.joined.clear();
  }

  // ── bus callbacks ──

  /** @internal */
  _deliverMessage(xml: string): void {
    for (const h of this.messageHandlers) h(xml);
  }

  /** @internal — only fires if this transport joined the node. */
  _deliverPubSub(node: string, ev: XmppPubSubEvent): void {
    if (!this.joined.has(node)) return;
    for (const h of this.pubsubHandlers) h(ev);
  }
}

```
