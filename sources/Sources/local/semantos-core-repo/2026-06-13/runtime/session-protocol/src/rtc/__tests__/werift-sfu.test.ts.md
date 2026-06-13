---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/werift-sfu.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.060755+00:00
---

# runtime/session-protocol/src/rtc/__tests__/werift-sfu.test.ts

```ts
/**
 * S4 SFU — real RTP forwarding through the brain-hosted relay (RTC matrix
 * S4/A3). Not a mock: a werift publisher sends RTP to the SFU, which forwards
 * it to two werift subscribers — each receives the real packets. Plus the
 * access-grant admission gate (a participant without a valid credential is
 * refused). Loopback host candidates; no network.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { RTCPeerConnection, MediaStreamTrack, RtpPacket, RtpHeader } from 'werift';
import { SfuRoom, OPEN_ADMISSION, type SfuAdmission } from '../werift-sfu';

type Pc = InstanceType<typeof RTCPeerConnection>;
const cleanups: Array<() => void> = [];
afterEach(() => {
  for (const c of cleanups.splice(0)) {
    try {
      c();
    } catch {
      /* ignore */
    }
  }
});

function newPc(): Pc {
  const pc = new RTCPeerConnection({});
  cleanups.push(() => pc.close());
  return pc;
}

/** A publisher peer that sends a synthetic audio RTP stream. */
function publisherPeer(): { pc: Pc; track: MediaStreamTrack; start: () => void; stop: () => void } {
  const pc = newPc();
  const track = new MediaStreamTrack({ kind: 'audio' });
  pc.addTransceiver(track, { direction: 'sendonly' });
  let timer: ReturnType<typeof setInterval> | undefined;
  let seq = 0;
  let ts = 0;
  return {
    pc,
    track,
    start() {
      timer = setInterval(() => {
        const header = new RtpHeader({ payloadType: 96, sequenceNumber: seq++ & 0xffff, timestamp: (ts += 160), ssrc: 0xabcd });
        track.writeRtp(new RtpPacket(header, Buffer.from([0xde, 0xad, 0xbe, 0xef])));
      }, 20);
      cleanups.push(() => timer && clearInterval(timer));
    },
    stop() {
      if (timer) clearInterval(timer);
    },
  };
}

describe('SFU broadcast room — real RTP forwarding', () => {
  test('one publisher fans out to two subscribers through the relay', async () => {
    const room = new SfuRoom({ admission: OPEN_ADMISSION });
    cleanups.push(() => room.close());

    // ── publisher joins ──
    const pub = publisherPeer();
    const pubAns = await room.publish({
      participantId: 'pub',
      offerSdp: await (async () => {
        const o = await pub.pc.createOffer();
        await pub.pc.setLocalDescription(o);
        return pub.pc.localDescription!.sdp;
      })(),
      onIceCandidate: (c) => void pub.pc.addIceCandidate(c as any),
    });
    expect(pubAns.admitted).toBe(true);
    pub.pc.onIceCandidate.subscribe((c: any) => c?.candidate && room.addIceCandidate('pub', c));
    await pub.pc.setRemoteDescription({ type: 'answer', sdp: pubAns.answerSdp! } as any);
    pub.start();

    // ── two subscribers join (the SFU offers them the forward track) ──
    async function subscribe(id: string): Promise<Promise<number>> {
      const subPc = newPc();
      const got = new Promise<number>((resolve) => {
        subPc.onTrack.subscribe((t: MediaStreamTrack) => {
          let n = 0;
          t.onReceiveRtp.subscribe(() => {
            if (++n === 3) resolve(n); // a few packets through the relay
          });
        });
      });
      const offer = await room.subscribe({
        participantId: id,
        onIceCandidate: (c) => void subPc.addIceCandidate(c as any),
      });
      expect(offer.admitted).toBe(true);
      subPc.onIceCandidate.subscribe((c: any) => c?.candidate && room.addIceCandidate(id, c));
      await subPc.setRemoteDescription({ type: 'offer', sdp: offer.offerSdp! } as any);
      const answer = await subPc.createAnswer();
      await subPc.setLocalDescription(answer);
      await room.completeSubscribe(id, subPc.localDescription!.sdp);
      return got;
    }

    const sub1 = await subscribe('sub1');
    const sub2 = await subscribe('sub2');

    // Both subscribers receive the publisher's forwarded RTP.
    expect(await sub1).toBeGreaterThanOrEqual(3);
    expect(await sub2).toBeGreaterThanOrEqual(3);
    expect(room.size()).toBe(3);
    expect(room.bytesForwardedFrom('pub')).toBeGreaterThan(0);

    pub.stop();
  }, 25_000);

  test('the access-grant admission gate refuses a participant without a valid credential', async () => {
    // Admission that only admits a participant carrying ANY credential (stands
    // in for the engine-checked BrainAccessGrantVerifier).
    const admission: SfuAdmission = { admit: async (_id, cred) => cred !== undefined };
    const room = new SfuRoom({ admission });
    cleanups.push(() => room.close());

    const pub = publisherPeer();
    const o = await pub.pc.createOffer();
    await pub.pc.setLocalDescription(o);

    // No credential → refused, no PeerConnection created.
    const denied = await room.publish({ participantId: 'nope', offerSdp: pub.pc.localDescription!.sdp });
    expect(denied.admitted).toBe(false);
    expect(denied.answerSdp).toBeUndefined();
    expect(room.size()).toBe(0);

    // With a credential → admitted.
    const ok = await room.publish({
      participantId: 'yes',
      offerSdp: pub.pc.localDescription!.sdp,
      credential: { grantCell: new Uint8Array(1024), intentCell: new Uint8Array(1024) },
    });
    expect(ok.admitted).toBe(true);
    expect(room.size()).toBe(1);
  }, 15_000);
});

```
