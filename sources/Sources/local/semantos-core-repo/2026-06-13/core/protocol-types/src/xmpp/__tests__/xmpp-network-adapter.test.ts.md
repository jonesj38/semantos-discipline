---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/xmpp/__tests__/xmpp-network-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.903259+00:00
---

# core/protocol-types/src/xmpp/__tests__/xmpp-network-adapter.test.ts

```ts
/**
 * D-XMPP-network-adapter tests — XmppNetworkAdapter end-to-end over the
 * in-memory StubXmppTransport (no server, no stream lib).
 *
 *   1. sendToNode → directed <message> routed by [BCA] host → decodes to the
 *      identical SignedBundle on the recipient
 *   2. publish → subscribe fires a NetworkResult that reconstructs the cell
 *      (bytes + routable header) on a joined subscriber only
 *   3. resolve pulls retained pubsub item history back as NetworkResults
 *   4. isConnected reflects transport liveness; getNodeBCA; resolveBCA delegates
 *   5. unsubscribe stops delivery
 */

import { describe, it, expect } from '@jest/globals';
import { XmppNetworkAdapter } from '../xmpp-network-adapter';
import { InMemoryXmppBus } from '../stub-xmpp-transport';
import { decodeBundleStanza } from '../bundle-stanza';
import { ENVELOPE_VERSION, type SignedBundle } from '../../signed-bundle/types';
import type { NetworkEvent, NodeInfo, PublishableObject } from '../../network';

const SIG = 'ab'.repeat(64);
const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const BCA_A = '2602:f9f8::1';
const BCA_B = '2602:f9f8::2';

function bundle(): SignedBundle {
  return {
    v: ENVELOPE_VERSION,
    sender_cert_chain: [{ cert_id: CERT_A, pubkey: '02' + 'cd'.repeat(32), context_tag: 0x10, parent_cert_id: null }],
    recipient_cert_id: CERT_B,
    payload_type: 'dispatch.request',
    payload: '{"verb":"ping"}',
    signature: SIG,
    signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: 'ef'.repeat(32), timestamp_unix: 1_750_000_000 },
  };
}

function cellObject(typeHash: string): PublishableObject {
  const cellBytes = new Uint8Array(1024);
  for (let i = 0; i < cellBytes.length; i++) cellBytes[i] = (i * 7) & 0xff;
  return {
    cellBytes,
    semanticPath: 'trades/job/plumbing-1774',
    contentHash: 'f00dbabe' + '00'.repeat(28),
    ownerCert: CERT_A,
    typeHash,
    parentPath: 'trades/job',
  };
}

function adapterFor(opts: {
  bus: InMemoryXmppBus;
  certId: string;
  bca: string;
  resolveBcaFn?: (a: string) => Promise<NodeInfo | null>;
}) {
  const transport = opts.bus.connect(`[${opts.bca}]`);
  const adapter = new XmppNetworkAdapter({
    transport,
    selfCertId: opts.certId,
    selfBcaIPv6: opts.bca,
    selfContextTag: 0x10,
    pubsubServiceJid: 'pubsub.home',
    now: () => 1_750_000_123,
    ...(opts.resolveBcaFn ? { resolveBcaFn: opts.resolveBcaFn } : {}),
  });
  return { transport, adapter };
}

describe('sendToNode (directed unicast)', () => {
  it('routes a SignedBundle to the [BCA] host and decodes identically', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter: sender } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { transport: recvTransport } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    const received: SignedBundle[] = [];
    recvTransport.onMessage((xml) => received.push(decodeBundleStanza(xml).bundle));

    const bytes = new TextEncoder().encode(JSON.stringify(bundle()));
    const res = await sender.sendToNode(BCA_B, bytes);

    expect(res.delivered).toBe(true);
    expect(received).toHaveLength(1);
    expect(received[0]).toEqual(bundle());
  });

  it('does not deliver to a non-addressed host', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter: sender } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { transport: other } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    const seen: string[] = [];
    other.onMessage((xml) => seen.push(xml));

    // Address a third, unconnected host → dropped, `other` sees nothing.
    await sender.sendToNode('2602:f9f8::99', new TextEncoder().encode(JSON.stringify(bundle())));
    expect(seen).toEqual([]);
  });
});

describe('publish / subscribe (type-multicast pubsub)', () => {
  const TYPE = 'sha256-trades-job';
  const TOPIC = `urn:type:${TYPE}`; // matches the adapter's default flat-node strategy

  it('delivers a reconstructed NetworkResult to a joined subscriber', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter: pub } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { adapter: sub } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    const events: NetworkEvent[] = [];
    const off = sub.subscribe(TOPIC, (e) => events.push(e));

    const obj = cellObject(TYPE);
    const result = await pub.publish(obj);

    expect(result.multicastGroup).toBe(TOPIC);
    expect(result.txid).toBe(obj.contentHash); // contentHash is the XMPP-plane handle
    expect(events).toHaveLength(1);

    const r = events[0]!.result;
    expect(events[0]!.type).toBe('object_published');
    expect(r.semanticPath).toBe(obj.semanticPath);
    expect(r.contentHash).toBe(obj.contentHash);
    expect(r.ownerCert).toBe(obj.ownerCert);
    expect(r.typeHash).toBe(obj.typeHash);
    expect(r.parentPath).toBe(obj.parentPath);
    expect(r.multicastGroup).toBe(TOPIC);
    expect(Array.from(r.cellBytes)).toEqual(Array.from(obj.cellBytes)); // 1024 bytes round-trip

    off();
  });

  it('does not deliver to a subscriber on a different node', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter: pub } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { adapter: sub } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    const events: NetworkEvent[] = [];
    sub.subscribe('urn:type:some-other-type', (e) => events.push(e));
    await pub.publish(cellObject(TYPE));
    expect(events).toEqual([]);
  });

  it('stops delivery after unsubscribe', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter: pub } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { adapter: sub } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    const events: NetworkEvent[] = [];
    const off = sub.subscribe(TOPIC, (e) => events.push(e));
    off();
    await pub.publish(cellObject(TYPE));
    expect(events).toEqual([]);
  });
});

describe('resolve (pubsub item history)', () => {
  it('returns retained items as NetworkResults', async () => {
    const TYPE = 'sha256-resolve-type';
    const bus = new InMemoryXmppBus();
    const { adapter: pub } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    const { adapter: q } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });

    await pub.publish(cellObject(TYPE));
    await pub.publish({ ...cellObject(TYPE), contentHash: 'beadfeed' + '00'.repeat(28) });

    const results = await q.resolve({ typeHash: TYPE, limit: 10 });
    expect(results).toHaveLength(2);
    expect(results.map((r) => r.contentHash)).toEqual([
      'f00dbabe' + '00'.repeat(28),
      'beadfeed' + '00'.repeat(28),
    ]);
  });

  it('returns [] when the query names no type', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    expect(await adapter.resolve({})).toEqual([]);
  });
});

describe('adapter housekeeping', () => {
  it('reflects transport liveness and exposes the node BCA', async () => {
    const bus = new InMemoryXmppBus();
    const { adapter, transport } = adapterFor({ bus, certId: CERT_A, bca: BCA_A });
    expect(adapter.isConnected()).toBe(true);
    expect(adapter.getNodeBCA()).toBe(BCA_A);
    transport.setOnline(false);
    expect(adapter.isConnected()).toBe(false);
  });

  it('delegates resolveBCA to the injected peer-locator (null when absent)', async () => {
    const bus = new InMemoryXmppBus();
    const nodeInfo = { bca: BCA_B } as unknown as NodeInfo;
    const { adapter: withFn } = adapterFor({
      bus,
      certId: CERT_A,
      bca: BCA_A,
      resolveBcaFn: async (a) => (a === BCA_B ? nodeInfo : null),
    });
    expect(await withFn.resolveBCA(BCA_B)).toBe(nodeInfo);
    expect(await withFn.resolveBCA('2602:f9f8::abc')).toBeNull();

    const { adapter: noFn } = adapterFor({ bus, certId: CERT_B, bca: BCA_B });
    expect(await noFn.resolveBCA(BCA_A)).toBeNull();
  });
});

```
