---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/bidirectional-call.werift.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.062471+00:00
---

# runtime/session-protocol/src/rtc/__tests__/bidirectional-call.werift.test.ts

```ts
/**
 * Bidirectional A1 call — both peers send AND receive media (RTC matrix A1/S3).
 *
 * A real two-way audio call: the caller and callee each publish a track and each
 * receives the other's RTP over SRTP, on a single PKI-signalled PeerConnection
 * (sendrecv transceivers, negotiated in one offer/answer — no renegotiation).
 * This is the symmetric-media foundation the group-call SFU then generalises.
 * Synthetic RTP sources, loopback host candidates; no network.
 */
import { describe, expect, test } from 'bun:test';
import { RtcSignalPlane, type InboundSignal, type RtcSignalChannel } from '../signal';
import { placeMediaCall, answerMediaCall, type MediaCall } from '../call';
import { weriftPeerConnectionFactory, weriftMediaSource } from '../werift-peer-connection';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

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

/** Pump a synthetic RTP stream from a source once `call` connects. */
function pumpOnConnect(call: MediaCall, source: ReturnType<typeof weriftMediaSource>): void {
  call.onConnected(() => {
    let seq = 0;
    let ts = 0;
    const timer = setInterval(() => source.writeRtp(Buffer.from([1, 2, 3, 4]), seq++, (ts += 160)), 20);
    setTimeout(() => clearInterval(timer), 3000);
  });
}
/** Resolve once `call` has received >= 3 RTP packets on a remote track. */
function receives(call: MediaCall): Promise<number> {
  return new Promise((resolve) => {
    call.onTrack((track) => {
      let n = 0;
      track.onRtp(() => {
        if (++n === 3) resolve(n);
      });
    });
  });
}

describe('two-way A1 media call (werift)', () => {
  test('caller and callee each publish audio and each receive the other RTP', async () => {
    const bus = new MemSignalBus();
    let n = 0;
    const genSid = () => `bidi-${++n}`;
    const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'a', genSid });
    const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'b', genSid });

    const aliceSrc = weriftMediaSource('audio');
    const bobSrc = weriftMediaSource('audio');

    const bobReceived = new Promise<number>((resolveReceived) => {
      bob.onIncomingCall(async (incoming) => {
        const bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {}, { tracks: [bobSrc.track] });
        pumpOnConnect(bobCall, bobSrc);
        receives(bobCall).then(resolveReceived);
      });
    });

    const aliceCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, { tracks: [aliceSrc.track] });
    pumpOnConnect(aliceCall, aliceSrc);
    const aliceReceived = receives(aliceCall);

    // Both directions carry real RTP.
    expect(await aliceReceived).toBeGreaterThanOrEqual(3); // alice got bob's audio
    expect(await bobReceived).toBeGreaterThanOrEqual(3); // bob got alice's audio
    expect(aliceCall.pc.connectionState()).toBe('connected');

    await aliceCall.hangup();
  }, 25_000);
});

```
