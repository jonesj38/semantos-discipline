---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/contact-call.werift.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.059894+00:00
---

# runtime/session-protocol/src/rtc/__tests__/contact-call.werift.test.ts

```ts
/**
 * Call a CONTACT over the SRS / XMPP carrier — the end-to-end wiring (RTC
 * matrix A1 + the contacts/PKI auth payload).
 *
 * Not a mock of the integration: two real XMPP nodes (the merged #974 carrier)
 * over a shared in-memory bus, each with a real werift media stack. Alice places
 * a call addressed by Bob's CONTACT CERT ID; the Jingle signalling rides as a
 * SignedBundle over Bob's BCA (resolved from the ContactBook); Bob's plane
 * surfaces it as an incoming call; the answer flows back; a real ICE/DTLS
 * connection establishes and audio flows. This is exactly what a helm binds:
 * `rtcOverXmpp(node)` → `placeMediaCall(plane, factory, ice, contactCertId)`.
 *
 * The contact + its BCA + the bilateral-edge signer here stand in for what the
 * offband invite → bilateral-edge → PKI flow (apps/semantos edge_invite.dart)
 * establishes in production. Loopback host candidates; no network.
 */
import { describe, expect, test } from 'bun:test';
import {
  InMemoryXmppBus,
  ENVELOPE_VERSION,
  type RosterBook,
} from '@semantos/protocol-types/xmpp';
import { createXmppNode, type BundleSigner, type XmppNodeConfig } from '../../xmpp-node';
import { deriveBCABytes, bcaBytesToIPv6 } from '../../signer';
import { rtcOverXmpp } from '../xmpp-signal-channel';
import { placeMediaCall, answerMediaCall, type MediaCall } from '../call';
import { weriftPeerConnectionFactory, weriftMediaSource } from '../werift-peer-connection';

const SUBNET = new Uint8Array([0x26, 0x02, 0xf9, 0xf8, 0x00, 0x00, 0x00, 0x00]);
const MODIFIER = new Uint8Array(16).fill(0x11);
const SEC = 3;
const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const SIG = 'ab'.repeat(64);

function pubkey(seed: number): Uint8Array {
  const k = new Uint8Array(33);
  k[0] = 0x02;
  for (let i = 1; i < 33; i++) k[i] = (seed + i) & 0xff;
  return k;
}
function bcaOf(seed: number): string {
  return bcaBytesToIPv6(deriveBCABytes(pubkey(seed), SUBNET, MODIFIER, SEC));
}
function contact(certId: string) {
  return { certId, publicKey: '02' + '00'.repeat(32), displayName: certId, source: 'manual' as const, addedAt: 1, updatedAt: 1 };
}
function edge(theirCert: string) {
  return { edgeId: `e-${theirCert}`, initiatorCertId: 'self', responderCertId: theirCert, edgeType: 'MESSAGING' as const, signingKeyIndex: 1, recoveryPolicy: 'NONE' as const, createdAt: 1 };
}
function fakeBook(certIds: string[]): RosterBook {
  const byId = new Map(certIds.map((c) => [c, contact(c)]));
  return {
    listContacts: () => [...byId.values()],
    getContact: (id: string) => byId.get(id) ?? null,
    getEdge: (id: string, t?: string) => (t === undefined || t === 'MESSAGING' ? (byId.has(id) ? edge(id) : null) : null),
  } as unknown as RosterBook;
}
/** A signer that signs as `senderCertId` — the bilateral edge identity. */
function signerFor(senderCertId: string): BundleSigner {
  return (req) => ({
    v: ENVELOPE_VERSION,
    sender_cert_chain: [{ cert_id: senderCertId, pubkey: '02' + 'cd'.repeat(32), context_tag: 0x10, parent_cert_id: null }],
    recipient_cert_id: req.recipientCertId,
    payload_type: req.payloadType,
    payload: req.payload,
    signature: SIG,
    signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: 'ef'.repeat(32), timestamp_unix: 1_750_000_000 },
  });
}
function nodeFor(opts: { certId: string; seed: number; transport: any; contacts: RosterBook; peerSeedByCert: Record<string, number> }): XmppNodeConfig {
  return {
    identity: { pubkey: pubkey(opts.seed), certId: opts.certId, contextTag: 0x10 },
    network: { subnetPrefix: SUBNET, modifier: MODIFIER, sec: SEC, pubsubServiceJid: 'pubsub.home' },
    transport: opts.transport,
    contacts: opts.contacts,
    bcaResolver: (c: any) => {
      const seed = opts.peerSeedByCert[c.certId];
      return seed ? bcaOf(seed) : null;
    },
    signBundle: signerFor(opts.certId),
  };
}

describe('call a contact over the SRS/XMPP carrier with real media', () => {
  test('Alice calls Bob by cert id; Bob gets the call; ICE/DTLS connects and audio flows', async () => {
    const bus = new InMemoryXmppBus();
    const aliceNode = createXmppNode(nodeFor({ certId: CERT_A, seed: 1, transport: bus.connect(`[${bcaOf(1)}]`), contacts: fakeBook([CERT_B]), peerSeedByCert: { [CERT_B]: 2 } }));
    const bobNode = createXmppNode(nodeFor({ certId: CERT_B, seed: 2, transport: bus.connect(`[${bcaOf(2)}]`), contacts: fakeBook([CERT_A]), peerSeedByCert: { [CERT_A]: 1 } }));

    const alice = rtcOverXmpp(aliceNode);
    const bob = rtcOverXmpp(bobNode);

    // Bob answers any incoming contact call and listens for media.
    const bobReceivedAudio = new Promise<string>((resolve) => {
      bob.onIncomingCall(async (incoming) => {
        expect(incoming.peerCertId).toBe(CERT_A); // authenticated caller identity
        const bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {});
        bobCall.onTrack((track) => {
          let n = 0;
          track.onRtp(() => {
            if (++n === 3) resolve(track.kind);
          });
        });
      });
    });

    // Alice places a media call to Bob's CONTACT CERT ID.
    const source = weriftMediaSource('audio');
    const aliceCall: MediaCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, { tracks: [source.track] });
    aliceCall.onConnected(() => {
      let seq = 0;
      let ts = 0;
      const timer = setInterval(() => source.writeRtp(Buffer.from([1, 2, 3, 4]), seq++, (ts += 160)), 20);
      setTimeout(() => clearInterval(timer), 3000);
    });

    expect(await bobReceivedAudio).toBe('audio');
    expect(aliceCall.pc.connectionState()).toBe('connected');
    // The fingerprint Alice pinned for Bob came from Bob's signed answer.
    expect(aliceCall.pinnedRemoteFingerprint()).toBeDefined();

    await aliceCall.hangup();
  }, 25_000);
});

```
