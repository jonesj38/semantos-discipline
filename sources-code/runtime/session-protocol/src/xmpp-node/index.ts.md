---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/xmpp-node/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.044063+00:00
---

# runtime/session-protocol/src/xmpp-node/index.ts

```ts
/**
 * xmpp-node — the wiring layer that binds the SRS × XMPP identity-transport
 * binding (`@semantos/protocol-types/xmpp`) to a live ContactBook + cert stack.
 *
 * This is the seam the binding was missing: the `xmpp/*` modules are pure
 * (string-only JID, type-only ContactBook/SignedBundle deps), so they model the
 * connection to contacts + PKI without holding a runtime link to either.
 * `createXmppNode` fills it:
 *
 *   • PKI → address.  Derives this node's BCA from its cert pubkey via the
 *     in-layer `deriveBCABytes`/`bcaBytesToIPv6` (signer.ts) and builds the
 *     self-JID `certId@[BCA]/hat`.
 *   • PKI → payload.  Takes the bundle signer as an INJECTED port
 *     (`signBundle`), so this layer never imports `@bsv/sdk` or the cartridge
 *     `send-bundle.ts` — the caller wires it to `buildBundle(...)`. Inbound
 *     signature/cert-chain verification stays in the brain (`signed_bundle.zig`).
 *   • Contacts.  Takes the app's ContactBook as a structural `RosterBook` slice
 *     (no new contact-book dependency) + a `BcaResolver`, and exposes roster
 *     sync, the signed-edge presence-subscription decision, and revocation
 *     teardown.
 *
 * The produced `adapter` is a plain `NetworkAdapter`, so it drops straight into
 * the existing `SessionRuntime` `adapter` slot. It runs today against
 * `StubXmppTransport` (in-memory) and unchanged against the real
 * `@xmpp/client`/ejabberd port when that lands.
 *
 * Cross-reference: docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md §4 + §7.
 */

import {
  XmppNetworkAdapter,
  buildRoster,
  decidePresenceSubscription,
  edgeRevocationTeardown,
  jidForNode,
  decodeBundleStanza,
  type XmppTransport,
  type XmppNetworkAdapterConfig,
  type RosterBook,
  type BcaResolver,
  type RosterBuildResult,
  type SubscriptionDecision,
  type SignedBundle,
} from '@semantos/protocol-types/xmpp';
import { deriveBCABytes, bcaBytesToIPv6 } from '../signer';

// ── injected PKI→payload port ──────────────────────────────────────────

/** The fields the caller's signer needs to build + sign a dispatch bundle. */
export interface DispatchBundleRequest {
  recipientCertId: string;
  payload: string;
  payloadType: string;
}

/**
 * Build + sign a `SignedBundle`. Wire to `send-bundle.ts::buildBundle`, closing
 * over the node's `senderCertChain` + `signerPriv`. Async-friendly so a
 * key-custody service / HSM can sign out-of-process.
 */
export type BundleSigner = (req: DispatchBundleRequest) => SignedBundle | Promise<SignedBundle>;

// ── config ─────────────────────────────────────────────────────────────

export interface XmppNodeIdentity {
  /** 33-byte compressed secp256k1 node pubkey (the cert leaf key). */
  pubkey: Uint8Array;
  /** 32-hex cert id (`certIdFromPubkey`) — the JID localpart. */
  certId: string;
  /** Active hat / context tag (0-255) — the JID resource. */
  contextTag: number;
}

export interface XmppNodeNetwork {
  /** 8-byte subnet prefix the BCA lives under (Phase-26D). */
  subnetPrefix: Uint8Array;
  /** 16-byte BCA modifier. */
  modifier: Uint8Array;
  /** Security/scope nibble (0-7). */
  sec: number;
  /** Pubsub service JID hosting the type-multicast nodes. */
  pubsubServiceJid: string;
}

export interface XmppNodeConfig {
  identity: XmppNodeIdentity;
  network: XmppNodeNetwork;
  /** Transport port — `StubXmppTransport` today, the real port later. */
  transport: XmppTransport;
  /** The app's ContactBook, narrowed to the slice the roster bridge reads. */
  contacts: RosterBook;
  /** Resolve a contact → peer BCA IPv6 (unbracketed), or null if unknown. */
  bcaResolver: BcaResolver;
  /** Build + sign a dispatch bundle (wires to send-bundle.buildBundle). */
  signBundle: BundleSigner;
  /** Optional type-multicast group strategies (pubsub-group-strategy). */
  groupForObject?: XmppNetworkAdapterConfig['groupForObject'];
  groupForQuery?: XmppNetworkAdapterConfig['groupForQuery'];
  /** Optional peer-locator for `resolveBCA`. */
  resolveBcaFn?: XmppNetworkAdapterConfig['resolveBcaFn'];
}

// ── the node ─────────────────────────────────────────────────────────────

export interface XmppNode {
  /** The NetworkAdapter — drop into `SessionRuntime({ adapter })`. */
  readonly adapter: XmppNetworkAdapter;
  /** This node's BCA as an unbracketed RFC-5952 IPv6 string. */
  readonly selfBcaIPv6: string;
  /** This node's full JID `certId@[BCA]/hat`. */
  selfJid(): string;
  /** Rebuild the roster from the current ContactBook state. */
  syncRoster(): RosterBuildResult;
  /** Decide an inbound `<presence subscribe>` — signed edge is the authoriser. */
  decideInboundSubscription(fromBareJid: string): SubscriptionDecision;
  /** Presence-teardown stanzas to emit after an edge is revoked. */
  teardownAfterRevoke(theirCertId: string): string[];
  /**
   * Sign + send a dispatch bundle to a contact (directed unicast). Resolves the
   * peer's BCA from the ContactBook, builds+signs the bundle via the injected
   * signer, and hands the JSON bytes to the adapter.
   */
  sendDispatch(toCertId: string, payload: string, payloadType?: string): Promise<{ delivered: boolean }>;
  /**
   * Register an inbound-bundle handler. The bundle is shape-validated only —
   * the caller MUST verify the signature + cert chain (brain `signed_bundle.zig`)
   * before acting on it. Returns an unsubscribe fn.
   */
  onInboundBundle(handler: (bundle: SignedBundle, fromJid: string) => void): () => void;
}

export function createXmppNode(cfg: XmppNodeConfig): XmppNode {
  // PKI → address: BCA from the node's cert pubkey.
  const selfBcaIPv6 = bcaBytesToIPv6(
    deriveBCABytes(cfg.identity.pubkey, cfg.network.subnetPrefix, cfg.network.modifier, cfg.network.sec),
  );

  const adapter = new XmppNetworkAdapter({
    transport: cfg.transport,
    selfCertId: cfg.identity.certId,
    selfBcaIPv6,
    selfContextTag: cfg.identity.contextTag,
    pubsubServiceJid: cfg.network.pubsubServiceJid,
    ...(cfg.groupForObject ? { groupForObject: cfg.groupForObject } : {}),
    ...(cfg.groupForQuery ? { groupForQuery: cfg.groupForQuery } : {}),
    ...(cfg.resolveBcaFn ? { resolveBcaFn: cfg.resolveBcaFn } : {}),
  });

  return {
    adapter,
    selfBcaIPv6,
    selfJid: () =>
      jidForNode({ certId: cfg.identity.certId, bcaIPv6: selfBcaIPv6, contextTag: cfg.identity.contextTag }),
    syncRoster: () => buildRoster(cfg.contacts, cfg.bcaResolver),
    decideInboundSubscription: (fromBareJid) => decidePresenceSubscription(fromBareJid, cfg.contacts),
    teardownAfterRevoke: (theirCertId) => edgeRevocationTeardown(theirCertId, cfg.contacts, cfg.bcaResolver),

    async sendDispatch(toCertId, payload, payloadType = 'dispatch.request') {
      const contact = cfg.contacts.getContact(toCertId);
      if (!contact) throw new Error(`sendDispatch: unknown contact ${toCertId}`);
      const peerBca = cfg.bcaResolver(contact);
      if (!peerBca) throw new Error(`sendDispatch: unresolved BCA for contact ${toCertId}`);
      const bundle = await cfg.signBundle({ recipientCertId: toCertId, payload, payloadType });
      const bytes = new TextEncoder().encode(JSON.stringify(bundle));
      return adapter.sendToNode(peerBca, bytes);
    },

    onInboundBundle(handler) {
      return cfg.transport.onMessage((xml) => {
        const stanza = decodeBundleStanza(xml);
        handler(stanza.bundle, stanza.from);
      });
    },
  };
}

```
