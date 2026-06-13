---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/xmpp-node/__tests__/ws-xmpp-transport.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.063145+00:00
---

# runtime/session-protocol/src/xmpp-node/__tests__/ws-xmpp-transport.test.ts

```ts
/**
 * WsXmppTransport integration tests — the real brain-native s2s transport over
 * actual loopback WebSocket sockets (no server, no stream lib). Proves
 * `createXmppNode` runs UNCHANGED against the real port (same shape the
 * in-memory StubXmppTransport proved).
 *
 *   1. directed dispatch A→B over a real socket (dial-on-demand) decodes
 *      identically with the correct from-JID
 *   2. bidirectional over a single learned connection (B→A reuses the socket A
 *      dialed, via the <hello> host-learning handshake)
 *   3. gossip pubsub fan-out — B subscribes, A publishes, only the subscribed
 *      node delivers
 *   4. isOnline lifecycle across stop()
 */

import { describe, it, expect, afterEach } from '@jest/globals';
import { createXmppNode, type BundleSigner, type XmppNode } from '../index';
import { WsXmppTransport } from '../ws-xmpp-transport';
import { deriveBCABytes, bcaBytesToIPv6 } from '../../signer';
import {
  ENVELOPE_VERSION,
  type RosterBook,
  type NetworkEvent,
  type PublishableObject,
} from '@semantos/protocol-types/xmpp';

const SIG = 'ab'.repeat(64);
const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const SUBNET = new Uint8Array([0x26, 0x02, 0xf9, 0xf8, 0, 0, 0, 0]);
const MODIFIER = new Uint8Array(16).fill(0x11);
const SEC = 3;

function pubkey(seed: number): Uint8Array {
  const k = new Uint8Array(33);
  k[0] = 0x02;
  for (let i = 1; i < 33; i++) k[i] = (seed + i) & 0xff;
  return k;
}
const bcaOf = (seed: number) => bcaBytesToIPv6(deriveBCABytes(pubkey(seed), SUBNET, MODIFIER, SEC));

function contact(certId: string, name: string) {
  return { certId, publicKey: '02' + '00'.repeat(32), displayName: name, source: 'manual' as const, addedAt: 1, updatedAt: 1 };
}
function messagingEdge(theirCert: string) {
  return { edgeId: `e-${theirCert}`, initiatorCertId: 'self', responderCertId: theirCert, edgeType: 'MESSAGING' as const, signingKeyIndex: 1, recoveryPolicy: 'NONE' as const, createdAt: 1 };
}
function fakeBook(contacts: ReturnType<typeof contact>[], edges: Record<string, ReturnType<typeof messagingEdge>>): RosterBook {
  const byId = new Map(contacts.map((c) => [c.certId, c]));
  return {
    listContacts: () => [...byId.values()],
    getContact: (id: string) => byId.get(id) ?? null,
    getEdge: (id: string) => edges[id] ?? null,
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

async function waitFor(pred: () => boolean, ms = 3000): Promise<void> {
  const start = Date.now();
  while (!pred()) {
    if (Date.now() - start > ms) throw new Error('waitFor: timed out');
    await new Promise((r) => setTimeout(r, 10));
  }
}

interface Pair {
  nodeA: XmppNode;
  nodeB: XmppNode;
  tA: WsXmppTransport;
  tB: WsXmppTransport;
  stop(): Promise<void>;
}

async function makePair(): Promise<Pair> {
  const HOST_A = `[${bcaOf(1)}]`;
  const HOST_B = `[${bcaOf(2)}]`;
  const urls = new Map<string, string>();
  const dial = (h: string) => urls.get(h) ?? null;

  const tA = await new WsXmppTransport({ selfHost: HOST_A, dial }).start();
  const tB = await new WsXmppTransport({ selfHost: HOST_B, dial }).start();
  urls.set(HOST_A, `ws://localhost:${tA.port}`);
  urls.set(HOST_B, `ws://localhost:${tB.port}`);

  const nodeA = createXmppNode({
    identity: { pubkey: pubkey(1), certId: CERT_A, contextTag: 0x10 },
    network: { subnetPrefix: SUBNET, modifier: MODIFIER, sec: SEC, pubsubServiceJid: 'pubsub.home' },
    transport: tA,
    contacts: fakeBook([contact(CERT_B, 'Bob')], { [CERT_B]: messagingEdge(CERT_B) }),
    bcaResolver: (c) => (c.certId === CERT_B ? bcaOf(2) : null),
    signBundle,
  });
  const nodeB = createXmppNode({
    identity: { pubkey: pubkey(2), certId: CERT_B, contextTag: 0x00 },
    network: { subnetPrefix: SUBNET, modifier: MODIFIER, sec: SEC, pubsubServiceJid: 'pubsub.home' },
    transport: tB,
    contacts: fakeBook([contact(CERT_A, 'Alice')], { [CERT_A]: messagingEdge(CERT_A) }),
    bcaResolver: (c) => (c.certId === CERT_A ? bcaOf(1) : null),
    signBundle,
  });

  return { nodeA, nodeB, tA, tB, stop: async () => { await tA.stop(); await tB.stop(); } };
}

let current: Pair | null = null;
afterEach(async () => { await current?.stop(); current = null; });

describe('WsXmppTransport over real loopback sockets', () => {
  it('routes a directed dispatch A→B that decodes identically', async () => {
    current = await makePair();
    const { nodeA, nodeB } = current;
    const inbound: Array<{ payload: string; from: string }> = [];
    nodeB.onInboundBundle((b, from) => inbound.push({ payload: b.payload, from }));

    const res = await nodeA.sendDispatch(CERT_B, '{"verb":"ping"}');
    expect(res.delivered).toBe(true);
    await waitFor(() => inbound.length === 1);
    expect(inbound[0]!.payload).toBe('{"verb":"ping"}');
    expect(inbound[0]!.from).toBe(nodeA.selfJid());
  });

  it('carries both directions over the one learned connection', async () => {
    current = await makePair();
    const { nodeA, nodeB } = current;
    const atA: string[] = [];
    const atB: string[] = [];
    nodeA.onInboundBundle((b) => atA.push(b.payload));
    nodeB.onInboundBundle((b) => atB.push(b.payload));

    await nodeA.sendDispatch(CERT_B, '{"to":"B"}'); // A dials B; B learns A via <hello>
    await waitFor(() => atB.length === 1);
    await nodeB.sendDispatch(CERT_A, '{"to":"A"}'); // B reuses the same socket back to A
    await waitFor(() => atA.length === 1);

    expect(atB).toEqual(['{"to":"B"}']);
    expect(atA).toEqual(['{"to":"A"}']);
  });

  it('fans pubsub items only to subscribers of the node', async () => {
    current = await makePair();
    const { nodeA, nodeB, tA } = current;
    await tA.connect(`[${bcaOf(2)}]`); // establish the A↔B link (+ B learns A)

    const got: NetworkEvent[] = [];
    nodeB.adapter.subscribe('urn:type:trade', (e) => got.push(e));
    // give the <sub> a tick to reach A
    await new Promise((r) => setTimeout(r, 50));

    const cell = new Uint8Array(1024).fill(7);
    const obj: PublishableObject = {
      cellBytes: cell, semanticPath: 'trade/x', contentHash: 'cd'.repeat(32), ownerCert: CERT_A, typeHash: 'trade',
    };
    await nodeA.adapter.publish(obj);
    await nodeA.adapter.publish({ ...obj, typeHash: 'other', contentHash: 'ef'.repeat(32) }); // different node

    await waitFor(() => got.length === 1);
    expect(got[0]!.result.semanticPath).toBe('trade/x');
    expect(Array.from(got[0]!.result.cellBytes)).toEqual(Array.from(cell));
    // the 'other'-node publish must NOT arrive on the 'trade' subscription
    await new Promise((r) => setTimeout(r, 50));
    expect(got).toHaveLength(1);
  });

  it('reflects liveness across stop()', async () => {
    current = await makePair();
    const { tA } = current;
    expect(tA.isOnline()).toBe(true);
    await tA.stop();
    expect(tA.isOnline()).toBe(false);
  });
});

```
