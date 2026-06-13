---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/werift-group-room.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.059323+00:00
---

# runtime/session-protocol/src/rtc/__tests__/werift-group-room.test.ts

```ts
/**
 * Symmetric group SFU — every member speaks AND hears (RTC matrix S4/A3).
 *
 * Not a mock: three real werift members join a brain-hosted relay; each
 * publishes a track and receives the other two's RTP, with the SFU driving
 * renegotiation as each member joins. Full group call through the relay.
 * Loopback host candidates; no network.
 */
import { afterEach, describe, expect, test } from 'bun:test';
import { RTCPeerConnection, MediaStreamTrack, RtpPacket, RtpHeader } from 'werift';
import { GroupSfuRoom, OPEN_ADMISSION } from '../werift-group-room';

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

function waitUntil(cond: () => boolean, timeoutMs: number, label: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const t0 = Date.now();
    const iv = setInterval(() => {
      if (cond()) {
        clearInterval(iv);
        resolve();
      } else if (Date.now() - t0 > timeoutMs) {
        clearInterval(iv);
        reject(new Error(`waitUntil timeout: ${label}`));
      }
    }, 50);
  });
}

interface Member {
  pc: Pc;
  remoteTracks: number;
  rtp: number;
}

/** A werift member that joins the room, publishes audio, and answers the SFU's
 *  renegotiation offers. */
async function joinMember(room: GroupSfuRoom, id: string, ssrc: number): Promise<Member> {
  const pc = new RTCPeerConnection({});
  cleanups.push(() => pc.close());
  const m: Member = { pc, remoteTracks: 0, rtp: 0 };

  const src = new MediaStreamTrack({ kind: 'audio' });
  pc.addTransceiver(src, { direction: 'sendrecv' });
  pc.onTrack.subscribe((t: MediaStreamTrack) => {
    m.remoteTracks++;
    t.onReceiveRtp.subscribe(() => {
      m.rtp++;
    });
  });
  pc.onIceCandidate.subscribe((c: any) => c?.candidate && room.addIceCandidate(id, c));

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  const res = await room.join({
    participantId: id,
    offerSdp: pc.localDescription!.sdp,
    onIceCandidate: (c) => void pc.addIceCandidate(c as any),
    // SFU-initiated renegotiation: apply the offer, answer it.
    onOffer: async (offerSdp: string) => {
      await pc.setRemoteDescription({ type: 'offer', sdp: offerSdp } as any);
      const ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      await room.applyAnswer(id, pc.localDescription!.sdp);
    },
  });
  await pc.setRemoteDescription({ type: 'answer', sdp: res.answerSdp! } as any);

  // Pump this member's audio.
  let seq = 0;
  let ts = 0;
  const timer = setInterval(() => {
    src.writeRtp(new RtpPacket(new RtpHeader({ payloadType: 96, sequenceNumber: seq++ & 0xffff, timestamp: (ts += 160), ssrc }), Buffer.from([1, 2, 3, 4])));
  }, 20);
  cleanups.push(() => clearInterval(timer));

  return m;
}

describe('symmetric group SFU — everyone speaks and hears', () => {
  test('three members each receive the other two via the relay', async () => {
    const room = new GroupSfuRoom({ admission: OPEN_ADMISSION });
    cleanups.push(() => room.close());

    const m1 = await joinMember(room, 'm1', 0x1111);
    const m2 = await joinMember(room, 'm2', 0x2222);
    const m3 = await joinMember(room, 'm3', 0x3333);

    // Each member ends up receiving two remote tracks (the other two members)
    // and real RTP on them.
    await waitUntil(() => m1.remoteTracks >= 2 && m2.remoteTracks >= 2 && m3.remoteTracks >= 2, 18_000, 'all members see 2 remote tracks');
    await waitUntil(() => m1.rtp > 0 && m2.rtp > 0 && m3.rtp > 0, 18_000, 'all members receive RTP');

    expect(room.size()).toBe(3);
    expect(m1.remoteTracks).toBeGreaterThanOrEqual(2);
    expect(m2.remoteTracks).toBeGreaterThanOrEqual(2);
    expect(m3.remoteTracks).toBeGreaterThanOrEqual(2);
    expect(m1.rtp).toBeGreaterThan(0);
    expect(m2.rtp).toBeGreaterThan(0);
    expect(m3.rtp).toBeGreaterThan(0);
    // The relay forwarded each member's media.
    expect(room.bytesForwardedFrom('m1')).toBeGreaterThan(0);
  }, 30_000);
});

```
