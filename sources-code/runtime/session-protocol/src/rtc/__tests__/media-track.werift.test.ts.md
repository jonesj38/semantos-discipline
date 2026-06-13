---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/media-track.werift.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.061037+00:00
---

# runtime/session-protocol/src/rtc/__tests__/media-track.werift.test.ts

```ts
/**
 * S3-D media tracks — REAL audio/video over an A1 call (RTC matrix S3 axis D).
 *
 * Not a mock: the caller publishes a real media track on a PKI-signalled 1:1
 * call, and the callee receives the actual RTP over SRTP. This is the media
 * pipeline the SFU forwards and the mesh carries — proven through the normalised
 * client port (browser + werift both implement it; here the node/werift path).
 *
 * Synthetic RTP source (no capture device needed headless). Real device capture
 * (getUserMedia) is the browser/PWA layer on top — same `addTrack`, the track's
 * `native` comes from the browser instead. Loopback host candidates; no network.
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

describe('A1 call carrying a real media track (werift)', () => {
  test('the caller publishes an audio track and the callee receives its RTP', async () => {
    const bus = new MemSignalBus();
    let n = 0;
    const genSid = () => `mt-${++n}`;
    const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'a', genSid });
    const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'b', genSid });

    let bobCall: MediaCall | undefined;
    const bobGotMedia = new Promise<{ kind: string; packets: number }>((resolve) => {
      bob.onIncomingCall(async (incoming) => {
        bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {});
        bobCall.onTrack((track) => {
          let packets = 0;
          track.onRtp(() => {
            if (++packets === 3) resolve({ kind: track.kind, packets });
          });
        });
      });
    });

    // Caller publishes a real audio track.
    const source = weriftMediaSource('audio');
    const aliceCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, {
      tracks: [source.track],
    });

    // Pump synthetic RTP once connected.
    aliceCall.onConnected(() => {
      let seq = 0;
      let ts = 0;
      const timer = setInterval(() => {
        source.writeRtp(Buffer.from([0xde, 0xad, 0xbe, 0xef]), seq++, (ts += 160));
      }, 20);
      // stop after the callee has surely received enough
      setTimeout(() => clearInterval(timer), 3000);
    });

    const { kind, packets } = await bobGotMedia;
    expect(kind).toBe('audio');
    expect(packets).toBeGreaterThanOrEqual(3);
    expect(aliceCall.pc.connectionState()).toBe('connected');

    await aliceCall.hangup();
  }, 25_000);
});

```
