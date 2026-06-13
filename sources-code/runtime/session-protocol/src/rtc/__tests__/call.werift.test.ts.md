---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/call.werift.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.061892+00:00
---

# runtime/session-protocol/src/rtc/__tests__/call.werift.test.ts

```ts
/**
 * A1 1:1 call — REAL media over werift, signalled by S1 (RTC matrix A1/S1/S2/S3).
 *
 * Not a mock: two real werift PeerConnections complete an ICE + DTLS handshake
 * and exchange data over SCTP. Signalling (Jingle offer/answer/ICE trickle)
 * rides the in-memory signal channel (the StubXmppTransport analogue), exactly
 * as it would ride the signed XMPP carrier in production. Proves the whole P1
 * substrate end-to-end: S1 (signal) + S2 (ICE) + S3 (media) wired by the A1
 * call binding, with the DTLS fingerprint flowing through signalling.
 *
 * Host-candidate only (config = {}), so it needs no STUN/network — loopback ICE.
 */
import { describe, expect, test } from 'bun:test';
import { RtcSignalPlane, type InboundSignal, type RtcSignalChannel } from '../signal';
import { placeMediaCall, answerMediaCall, type MediaCall } from '../call';
import { localFingerprint } from '../media';
import { weriftPeerConnectionFactory } from '../werift-peer-connection';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

/** In-memory signalling fabric (routes by cert id; tags the verified sender). */
class MemSignalBus {
  private readonly inbound = new Map<string, (m: InboundSignal) => void>();
  channelFor(certId: string): RtcSignalChannel {
    return {
      sendTo: async (peerCertId, jingleXml) => {
        this.inbound.get(peerCertId)?.({ fromCertId: certId, jingleXml });
      },
      onInbound: (handler) => {
        this.inbound.set(certId, handler);
        return () => {
          if (this.inbound.get(certId) === handler) this.inbound.delete(certId);
        };
      },
    };
  }
}

describe('A1 1:1 media call over werift, signalled by S1', () => {
  test('caller and callee complete a real ICE/DTLS connection and exchange data', async () => {
    const bus = new MemSignalBus();
    let n = 0;
    const genSid = () => `call-${++n}`;
    const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'alice', genSid });
    const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'bob', genSid });

    let bobCall: MediaCall | undefined;
    const bobGotMessage = new Promise<string>((resolve) => {
      bob.onIncomingCall(async (incoming) => {
        bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {});
        bobCall.onDataChannel((ch) => ch.onMessage((m) => resolve(m.toString())));
      });
    });

    const aliceCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, { channels: ['chat'] });
    const aliceConnected = new Promise<void>((resolve) => aliceCall.onConnected(resolve));
    const dc = aliceCall.channel('chat')!;
    dc.onOpen(() => dc.send('hello-over-real-webrtc'));

    // The connection actually establishes (real ICE + DTLS), and data flows.
    await aliceConnected;
    expect(aliceCall.pc.connectionState()).toBe('connected');
    const received = await bobGotMessage;
    expect(received).toBe('hello-over-real-webrtc');

    // Axis A: the fingerprint Alice pinned for Bob (from Bob's signed answer)
    // is the fingerprint Bob's media endpoint actually presents.
    const pinned = aliceCall.pinnedRemoteFingerprint();
    expect(pinned).toBeDefined();
    expect(pinned!.value).toBe(localFingerprint(bobCall!.pc)!.value);

    await aliceCall.hangup();
    expect(aliceCall.signal.state).toBe('terminated');
  }, 20_000);
});

```
