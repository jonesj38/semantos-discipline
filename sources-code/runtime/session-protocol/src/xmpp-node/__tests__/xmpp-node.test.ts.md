---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/xmpp-node/__tests__/xmpp-node.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.062833+00:00
---

# runtime/session-protocol/src/xmpp-node/__tests__/xmpp-node.test.ts

```ts
/**
 * xmpp-node wiring tests — binds the XMPP binding to a (fake) ContactBook + the
 * BCA deriver + an injected bundle signer, over the in-memory StubXmppTransport.
 *
 *   1. PKI→address: selfBcaIPv6 == independently-derived BCA; selfJid() shape
 *   2. contacts: syncRoster maps the book → bare-JID roster items
 *   3. end-to-end: sendDispatch signs + routes a bundle that the peer node
 *      receives via onInboundBundle, identical, with the correct from-JID
 *   4. presence: decideInboundSubscription approve/defer/deny off the signed edge
 *   5. sendDispatch error paths (unknown contact / unresolved BCA)
 */

import { describe, it, expect } from '@jest/globals';
import { createXmppNode, type BundleSigner, type XmppNodeConfig } from '../index';
import { deriveBCABytes, bcaBytesToIPv6 } from '../../signer';
import {
  InMemoryXmppBus,
  bareJidForNode,
  ENVELOPE_VERSION,
  type RosterBook,
  type SignedBundle,
} from '@semantos/protocol-types/xmpp';

const SIG = 'ab'.repeat(64);
const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const CERT_C = 'cccccccccccccccccccccccccccccccc';

// deterministic network params
const SUBNET = new Uint8Array([0x26, 0x02, 0xf9, 0xf8, 0x00, 0x00, 0x00, 0x00]);
const MODIFIER = new Uint8Array(16).fill(0x11);
const SEC = 3;

function pubkey(seed: number): Uint8Array {
  const k = new Uint8Array(33);
  k[0] = 0x02;
  for (let i = 1; i < 33; i++) k[i] = (seed + i) & 0xff;
  return k;
}

function bcaOf(seed: number): string {
  return bcaBytesToIPv6(deriveBCABytes(pubkey(seed), SUBNET, MODIFIER, SEC));
}

// ── fake ContactBook slice ──
function contact(certId: string, name: string) {
  return { certId, publicKey: '02' + '00'.repeat(32), displayName: name, source: 'manual' as const, addedAt: 1, updatedAt: 1 };
}
function messagingEdge(theirCert: string, revoked = false) {
  return {
    edgeId: `e-${theirCert}`,
    initiatorCertId: 'self',
    responderCertId: theirCert,
    edgeType: 'MESSAGING' as const,
    signingKeyIndex: 1,
    recoveryPolicy: 'NONE' as const,
    createdAt: 1,
    ...(revoked ? { revokedAt: 2 } : {}),
  };
}
function fakeBook(contacts: ReturnType<typeof contact>[], edges: Record<string, ReturnType<typeof messagingEdge> | null>): RosterBook {
  const byId = new Map(contacts.map((c) => [c.certId, c]));
  return {
    listContacts: () => [...byId.values()],
    getContact: (id: string) => byId.get(id) ?? null,
    getEdge: (id: string, t?: string) => (t === undefined || t === 'MESSAGING' ? edges[id] ?? null : null),
  } as unknown as RosterBook;
}

const signBundle: BundleSigner = (req) => ({
  v: ENVELOPE_VERSION,
  sender_cert_chain: [{ cert_id: CERT_A, pubkey: '02' + 'cd'.repeat(32), context_tag: 0x10, parent_cert_id: null }],
  recipient_cert_id: req.recipientCertId,
  payload_type: req.payloadType,
  payload: req.payload,
  signature: SIG,
  signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: 'ef'.repeat(32), timestamp_unix: 1_750_000_000 },
});

function nodeConfig(over: Partial<XmppNodeConfig> & Pick<XmppNodeConfig, 'identity' | 'transport' | 'contacts' | 'bcaResolver'>): XmppNodeConfig {
  return {
    network: { subnetPrefix: SUBNET, modifier: MODIFIER, sec: SEC, pubsubServiceJid: 'pubsub.home' },
    signBundle,
    ...over,
  };
}

describe('PKI → address', () => {
  it('derives selfBcaIPv6 from the cert pubkey and builds the self-JID', () => {
    const bus = new InMemoryXmppBus();
    const node = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
      transport: bus.connect(`[${bcaOf(1)}]`),
      contacts: fakeBook([], {}),
      bcaResolver: () => null,
    }));
    expect(node.selfBcaIPv6).toBe(bcaOf(1));
    expect(node.selfJid()).toBe(`${CERT_A}@[${bcaOf(1)}]/10`);
  });
});

describe('contacts → roster', () => {
  it('maps the ContactBook into bare-JID roster items', () => {
    const bus = new InMemoryXmppBus();
    const node = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
      transport: bus.connect(`[${bcaOf(1)}]`),
      contacts: fakeBook([contact(CERT_B, 'Bob')], { [CERT_B]: messagingEdge(CERT_B) }),
      bcaResolver: (c) => (c.certId === CERT_B ? bcaOf(2) : null),
    }));
    const { items, unresolved } = node.syncRoster();
    expect(unresolved).toEqual([]);
    expect(items).toHaveLength(1);
    expect(items[0]!.jid).toBe(bareJidForNode({ certId: CERT_B, bcaIPv6: bcaOf(2) }));
    expect(items[0]!.subscription).toBe('both');
  });
});

describe('end-to-end dispatch over the stub bus', () => {
  it('signs + routes a bundle the peer receives identically', async () => {
    const bus = new InMemoryXmppBus();
    const nodeA = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
      transport: bus.connect(`[${bcaOf(1)}]`),
      contacts: fakeBook([contact(CERT_B, 'Bob')], { [CERT_B]: messagingEdge(CERT_B) }),
      bcaResolver: (c) => (c.certId === CERT_B ? bcaOf(2) : null),
    }));
    const nodeB = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(2), certId: CERT_B, contextTag: 0x00 },
      transport: bus.connect(`[${bcaOf(2)}]`),
      contacts: fakeBook([], {}),
      bcaResolver: () => null,
    }));

    const inbound: Array<{ bundle: SignedBundle; from: string }> = [];
    nodeB.onInboundBundle((bundle, from) => inbound.push({ bundle, from }));

    const res = await nodeA.sendDispatch(CERT_B, '{"verb":"ping"}');
    expect(res.delivered).toBe(true);
    expect(inbound).toHaveLength(1);
    expect(inbound[0]!.bundle.recipient_cert_id).toBe(CERT_B);
    expect(inbound[0]!.bundle.payload).toBe('{"verb":"ping"}');
    expect(inbound[0]!.bundle.payload_type).toBe('dispatch.request');
    expect(inbound[0]!.from).toBe(nodeA.selfJid());
  });

  it('throws on an unknown contact or an unresolved BCA', async () => {
    const bus = new InMemoryXmppBus();
    const node = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
      transport: bus.connect(`[${bcaOf(1)}]`),
      contacts: fakeBook([contact(CERT_C, 'Carol')], {}),
      bcaResolver: () => null, // Carol's BCA never resolves
    }));
    await expect(node.sendDispatch('deadbeefdeadbeefdeadbeefdeadbeef', 'x')).rejects.toThrow(/unknown contact/);
    await expect(node.sendDispatch(CERT_C, 'x')).rejects.toThrow(/unresolved BCA/);
  });
});

describe('presence subscription decision (signed edge is the authoriser)', () => {
  it('approves an active edge, defers no-edge, denies unknown', () => {
    const bus = new InMemoryXmppBus();
    const node = createXmppNode(nodeConfig({
      identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
      transport: bus.connect(`[${bcaOf(1)}]`),
      contacts: fakeBook([contact(CERT_B, 'Bob'), contact(CERT_C, 'Carol')], { [CERT_B]: messagingEdge(CERT_B) }),
      bcaResolver: (c) => bcaOf(c.certId === CERT_B ? 2 : 3),
    }));
    expect(node.decideInboundSubscription(bareJidForNode({ certId: CERT_B, bcaIPv6: bcaOf(2) })).decision).toBe('approve');
    expect(node.decideInboundSubscription(bareJidForNode({ certId: CERT_C, bcaIPv6: bcaOf(3) })).decision).toBe('defer');
    expect(node.decideInboundSubscription(bareJidForNode({ certId: 'deadbeefdeadbeefdeadbeefdeadbeef', bcaIPv6: bcaOf(9) })).decision).toBe('deny');
  });
});

```
