---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/xmpp-network-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.864326+00:00
---

# core/protocol-types/src/xmpp/xmpp-network-adapter.ts

```ts
/**
 * D-XMPP-network-adapter — XmppNetworkAdapter implements NetworkAdapter.
 *
 * Binds the SRS address plane onto XMPP (see docs/design/SRS-XMPP-IDENTITY-
 * TRANSPORT.md §7).  It is the third selectable transport beside
 * StubNetworkAdapter (in-memory) and BsvOverlayNetworkAdapter (SHIP/SLAP):
 *
 *   sendToNode  → directed <message> to [BCA] host, body = SignedBundle
 *   publish     → XEP-0060 publish to the type-multicast pubsub node
 *   subscribe   → join the ff03:… group / pubsub node, fire on items
 *   resolve     → pubsub item fetch over the query's node
 *   resolveBCA  → peer-locator delegate (identity-only regime; SRS §10.1)
 *   getNodeBCA  → this node's BCA IPv6
 *
 * Library-agnostic: it consumes an injected `XmppTransport` port rather than a
 * concrete client (@xmpp/client, ejabberd c2s, etc.).  Wiring code supplies the
 * port + the two addressing strategies; nothing here imports a stream library
 * or `@bsv/sdk`.
 *
 * v0.1 honesty notes are inline.  The load-bearing limitations:
 *   • PublishableObject carries only the COMPOSITE typeHash, not the per-axis
 *     WHAT/HOW/INST paths — so the default group strategy is a FLAT node per
 *     composite type (exact-type pub/sub works; SNS prefix subscription does
 *     not).  Pass `groupForObject`/`groupForQuery` built on Phase-34A's
 *     `deriveMulticastGroup` to get hierarchical addressing.
 *   • There is no chain txid on the XMPP plane; `PublishResult.txid` is set to
 *     the object's contentHash as a delivery handle.  Settlement/anchoring is
 *     the BSV plane's job, not XMPP's.
 */

import type {
  NetworkAdapter,
  NetworkEvent,
  NetworkQuery,
  NetworkResult,
  NodeInfo,
  PublishableObject,
  PublishOptions,
  PublishResult,
} from '../network';
import type { SignedBundle } from '../signed-bundle/types';
import {
  encodeBundleStanza,
  decodeBundleStanza,
  parseBundleJson,
} from './bundle-stanza';
import { jidForNode, pubsubAddressForType, type PubSubAddress } from './jid';

// ─────────────────────────────────────────────────────────────────────
// Transport port — the minimal XMPP surface the adapter needs.  A wiring
// layer implements this over @xmpp/client (or a brain-native s2s loop).
// ─────────────────────────────────────────────────────────────────────

export interface XmppPubSubEvent {
  /** Pubsub node id (= type-multicast group string). */
  node: string;
  /** Item id. */
  itemId: string;
  /** The item's inner payload XML (the <cell> element, escaped). */
  payloadXml: string;
}

export interface XmppTransport {
  isOnline(): boolean;
  /** Send a raw stanza (e.g. the output of `encodeBundleStanza`). */
  sendStanza(xml: string): Promise<void>;
  /** Register a directed-<message> handler; returns an unsubscribe fn. */
  onMessage(handler: (xml: string) => void): () => void;
  /** Register a pubsub-event handler; returns an unsubscribe fn. */
  onPubSubEvent(handler: (ev: XmppPubSubEvent) => void): () => void;
  subscribeNode(addr: PubSubAddress): Promise<void>;
  unsubscribeNode(addr: PubSubAddress): Promise<void>;
  publishItem(addr: PubSubAddress, itemId: string, payloadXml: string): Promise<void>;
  /** Optional: fetch existing items for resolve(); absent → resolve returns []. */
  fetchItems?(addr: PubSubAddress, limit: number): Promise<Array<{ itemId: string; payloadXml: string }>>;
}

export interface XmppNetworkAdapterConfig {
  transport: XmppTransport;
  /** This node's identity. */
  selfCertId: string;
  /** This node's BCA as an unbracketed RFC-5952 IPv6 string. */
  selfBcaIPv6: string;
  /** This node's active hat / context tag (0-255). */
  selfContextTag: number;
  /** Pubsub service JID that hosts type nodes (e.g. the home/relay BCA host). */
  pubsubServiceJid: string;
  /** Map a publishable object to its pubsub node.  Default: flat per typeHash. */
  groupForObject?: (o: PublishableObject) => PubSubAddress;
  /** Map a resolve/subscribe query to a pubsub node.  Default: flat per typeHash. */
  groupForQuery?: (q: NetworkQuery) => PubSubAddress | null;
  /** Peer-locator: BCA IPv6 → NodeInfo.  Absent → resolveBCA returns null. */
  resolveBcaFn?: (address: string) => Promise<NodeInfo | null>;
  /** Injected clock for publishedAt (epoch ms).  Default: Date.now. */
  now?: () => number;
}

// ─────────────────────────────────────────────────────────────────────
// Cell item wire form (pubsub payload).  A published cell rides as base64
// inside a <cell> element carrying the routable header fields so subscribers
// reconstruct a NetworkResult without opening the 1024 bytes.
// ─────────────────────────────────────────────────────────────────────

const CELL_NS = 'urn:semantos:cell:1';

function xmlEscapeAttr(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
}
function xmlUnescapeAttr(s: string): string {
  return s.replace(/&lt;/g, '<').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
}
function toBase64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}
function fromBase64(b64: string): Uint8Array {
  return Uint8Array.from(Buffer.from(b64, 'base64'));
}

function cellItemXml(o: PublishableObject): string {
  const attrs = [
    `xmlns="${CELL_NS}"`,
    `path="${xmlEscapeAttr(o.semanticPath)}"`,
    `typeHash="${xmlEscapeAttr(o.typeHash)}"`,
    `owner="${xmlEscapeAttr(o.ownerCert)}"`,
    `contentHash="${xmlEscapeAttr(o.contentHash)}"`,
  ];
  if (o.parentPath) attrs.push(`parent="${xmlEscapeAttr(o.parentPath)}"`);
  return `<cell ${attrs.join(' ')}>${toBase64(o.cellBytes)}</cell>`;
}

const CELL_EL_RE = new RegExp(`<cell\\s+xmlns="${CELL_NS}"([^>]*)>([\\s\\S]*?)</cell>`);
const attr = (name: string, s: string): string | undefined => {
  const m = new RegExp(`\\b${name}="([^"]*)"`).exec(s);
  return m ? xmlUnescapeAttr(m[1]!) : undefined;
};

function cellResultFromItem(node: string, payloadXml: string, publishedAt: number): NetworkResult | null {
  const m = CELL_EL_RE.exec(payloadXml);
  if (!m) return null;
  const a = m[1]!;
  return {
    txid: attr('contentHash', a) ?? '',
    vout: 0,
    cellBytes: fromBase64(m[2]!.trim()),
    semanticPath: attr('path', a) ?? '',
    contentHash: attr('contentHash', a) ?? '',
    ownerCert: attr('owner', a) ?? '',
    typeHash: attr('typeHash', a) ?? '',
    ...(attr('parent', a) ? { parentPath: attr('parent', a)! } : {}),
    publishedAt,
    multicastGroup: node,
  };
}

// ─────────────────────────────────────────────────────────────────────
// The adapter.
// ─────────────────────────────────────────────────────────────────────

export class XmppNetworkAdapter implements NetworkAdapter {
  private readonly cfg: XmppNetworkAdapterConfig;
  private readonly now: () => number;

  constructor(cfg: XmppNetworkAdapterConfig) {
    this.cfg = cfg;
    this.now = cfg.now ?? (() => Date.now());
  }

  private selfJid(): string {
    return jidForNode({
      certId: this.cfg.selfCertId,
      bcaIPv6: this.cfg.selfBcaIPv6,
      contextTag: this.cfg.selfContextTag,
    });
  }

  /** Default flat node: one pubsub node per composite typeHash. */
  private groupForObject(o: PublishableObject): PubSubAddress {
    return this.cfg.groupForObject
      ? this.cfg.groupForObject(o)
      : pubsubAddressForType({ multicastIPv6: `urn:type:${o.typeHash}`, serviceJid: this.cfg.pubsubServiceJid });
  }

  private groupForQuery(q: NetworkQuery): PubSubAddress | null {
    if (this.cfg.groupForQuery) return this.cfg.groupForQuery(q);
    if (!q.typeHash) return null;
    return pubsubAddressForType({ multicastIPv6: `urn:type:${q.typeHash}`, serviceJid: this.cfg.pubsubServiceJid });
  }

  // ── directed unicast: SignedBundle over <message> ──

  /**
   * `message` must be the UTF-8 JSON of a SignedBundle (the same bytes a
   * `POST /api/v1/bundle` would carry).  We address the stanza to the bare
   * host JID `[targetBCA]`; the bundle's `recipient_cert_id` is the
   * authoritative identity (domain-only routing + payload-level trust).
   */
  async sendToNode(targetBCA: string, message: Uint8Array): Promise<{ delivered: boolean }> {
    const bundle: SignedBundle = parseBundleJson(new TextDecoder().decode(message));
    const xml = encodeBundleStanza({
      to: `[${targetBCA}]`,
      from: this.selfJid(),
      type: 'normal',
      bundle,
    });
    await this.cfg.transport.sendStanza(xml);
    return { delivered: true };
  }

  // ── pubsub: publish / subscribe over the type-multicast node ──

  async publish(object: PublishableObject, options?: PublishOptions): Promise<PublishResult> {
    const addr = options?.topic
      ? pubsubAddressForType({ multicastIPv6: options.topic, serviceJid: this.cfg.pubsubServiceJid })
      : this.groupForObject(object);
    await this.cfg.transport.publishItem(addr, object.contentHash, cellItemXml(object));
    return {
      // No chain txid on the XMPP plane — contentHash is the delivery handle.
      txid: object.contentHash,
      multicastGroup: addr.node,
      publishedAt: this.now(),
    };
  }

  subscribe(topic: string, callback: (event: NetworkEvent) => void): () => void {
    const addr = pubsubAddressForType({ multicastIPv6: topic, serviceJid: this.cfg.pubsubServiceJid });
    // Join the node (fire-and-forget; errors surface on the transport's own channel).
    void this.cfg.transport.subscribeNode(addr);
    const off = this.cfg.transport.onPubSubEvent((ev) => {
      if (ev.node !== addr.node) return;
      const result = cellResultFromItem(ev.node, ev.payloadXml, this.now());
      if (!result) return;
      callback({ type: 'object_published', result, timestamp: this.now() });
    });
    return () => {
      off();
      void this.cfg.transport.unsubscribeNode(addr);
    };
  }

  // ── resolve over pubsub item history ──

  async resolve(query: NetworkQuery): Promise<NetworkResult[]> {
    const addr = this.groupForQuery(query);
    if (!addr || !this.cfg.transport.fetchItems) return [];
    const items = await this.cfg.transport.fetchItems(addr, query.limit ?? 10);
    const now = this.now();
    return items
      .map((it) => cellResultFromItem(addr.node, it.payloadXml, now))
      .filter((r): r is NetworkResult => r !== null);
  }

  // ── identity-only-regime fallbacks ──

  async resolveBCA(address: string): Promise<NodeInfo | null> {
    // XMPP can't resolve BCA→endpoint natively until the BCA is a routable
    // SRv6 locator (SRS §10.1).  Delegate to the injected peer-locator.
    return this.cfg.resolveBcaFn ? this.cfg.resolveBcaFn(address) : null;
  }

  isConnected(): boolean {
    return this.cfg.transport.isOnline();
  }

  getNodeBCA(): string | null {
    return this.cfg.selfBcaIPv6 || null;
  }
}

```
