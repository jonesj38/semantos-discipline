---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/werift-group-room.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.043460+00:00
---

# runtime/session-protocol/src/rtc/werift-group-room.ts

```ts
/**
 * werift-group-room — S4 symmetric group SFU (RTC matrix S4 / adapter A3).
 *
 * The full group call: every member holds ONE bidirectional PeerConnection to
 * the brain-hosted SFU, publishes their track, and receives every other
 * member's track — the relay forwards RTP without transcode. This generalises
 * the broadcast room (werift-sfu.ts, distinct publisher/subscriber roles) to
 * the symmetric case where everyone both speaks and hears, using the same
 * sendrecv + transceiver-reuse mechanic that makes a 1:1 call two-way (#995),
 * lifted onto the relay.
 *
 * THE HARD PART — RENEGOTIATION. A member's initial offer carries only their own
 * track, so the SFU's answer can only receive it. To send the OTHER members'
 * tracks down (and to push a newcomer's track to everyone already connected),
 * the SFU must re-offer after the connection is up. So the SFU is the offerer
 * for every renegotiation: it adds a forward track, `createOffer`s, the member
 * answers (`applyAnswer`). Renegotiations are SERIALIZED per connection (one
 * offer/answer in flight at a time) via a promise chain.
 *
 * Admission reuses the engine-checked access.grant (werift-sfu.ts
 * `accessGrantAdmission` / `BrainAccessGrantVerifier`, #991) — the SESSION_ACCESS
 * sibling. Node/bun server component (werift-specific); NOT barrel-exported.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml rows S4/A3, werift-sfu.ts (broadcast
 * room + admission), call.ts (the 1:1 sendrecv this generalises).
 */

import { RTCPeerConnection, MediaStreamTrack } from 'werift';
import type { RtcIceConfig } from './ice';
import { OPEN_ADMISSION, type SfuAdmission, type SfuCredential } from './werift-sfu';

export { OPEN_ADMISSION, accessGrantAdmission, type SfuAdmission, type SfuCredential } from './werift-sfu';

type IceCb = (candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number }) => void;
type OfferCb = (offerSdp: string) => void;
type WeriftPc = InstanceType<typeof RTCPeerConnection>;

interface Deferred {
  promise: Promise<void>;
  resolve: () => void;
}
function deferred(): Deferred {
  let resolve!: () => void;
  const promise = new Promise<void>((r) => (resolve = r));
  return { promise, resolve };
}

interface Member {
  id: string;
  pc: WeriftPc;
  /** Tracks this member published to the SFU (forwarded to everyone else). */
  published: MediaStreamTrack[];
  /** Bytes forwarded FROM this member to others (metering hook). */
  bytesForwarded: number;
  onOffer?: OfferCb;
  /** Serialises SFU-initiated renegotiations on this connection. */
  chain: Promise<void>;
  /** Resolves when the member answers the in-flight renegotiation offer. */
  pendingAnswer?: Deferred;
}

export interface GroupRoomOptions {
  iceConfig?: RtcIceConfig;
  admission?: SfuAdmission;
}

export interface GroupJoinRequest {
  participantId: string;
  /** The member's SDP offer (their own track, sendrecv). */
  offerSdp: string;
  credential?: SfuCredential;
  onIceCandidate?: IceCb;
  /** The SFU emits renegotiation OFFERS here; answer via `applyAnswer`. */
  onOffer?: OfferCb;
}

export class GroupSfuRoom {
  private readonly members = new Map<string, Member>();
  /** Idempotency guard: `${sourceId}->${destId}:${kind}` already forwarded.
   *  werift re-fires onTrack on every renegotiation, so without this each
   *  renegotiation would add another forward track → unbounded loop. */
  private readonly forwarded = new Set<string>();
  private readonly admission: SfuAdmission;
  private readonly iceConfig: Record<string, unknown>;

  constructor(opts: GroupRoomOptions = {}) {
    this.admission = opts.admission ?? OPEN_ADMISSION;
    this.iceConfig = (opts.iceConfig ?? {}) as Record<string, unknown>;
  }

  size(): number {
    return this.members.size;
  }
  bytesForwardedFrom(participantId: string): number {
    return this.members.get(participantId)?.bytesForwarded ?? 0;
  }

  /** Admit + connect a member. They offer their track; the SFU answers, then
   *  renegotiates to wire forwarding both ways once connected. */
  async join(req: GroupJoinRequest): Promise<{ admitted: boolean; answerSdp?: string }> {
    if (!(await this.admission.admit(req.participantId, req.credential))) return { admitted: false };

    const pc = new RTCPeerConnection(this.iceConfig);
    const member: Member = {
      id: req.participantId,
      pc,
      published: [],
      bytesForwarded: 0,
      onOffer: req.onOffer,
      chain: Promise.resolve(),
    };

    if (req.onIceCandidate) {
      pc.onIceCandidate.subscribe((c: any) => {
        if (c?.candidate) req.onIceCandidate!({ candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex });
      });
    }

    // When this member's track arrives, forward it to every OTHER member.
    // Dedupe by kind — werift re-fires onTrack on each renegotiation with a
    // fresh track object for the same media; take only the first per kind.
    pc.onTrack.subscribe((track: MediaStreamTrack) => {
      if (member.published.some((t) => t.kind === track.kind)) return;
      member.published.push(track);
      for (const other of this.members.values()) {
        if (other.id !== member.id) this.forward(member, track, other);
      }
    });

    // Once connected, push every existing member's tracks down to this member.
    pc.connectionStateChange.subscribe((state: string) => {
      if (state !== 'connected') return;
      for (const other of this.members.values()) {
        if (other.id === member.id) continue;
        for (const track of other.published) this.forward(other, track, member);
      }
    });

    await pc.setRemoteDescription({ type: 'offer', sdp: req.offerSdp } as any);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    this.members.set(req.participantId, member);
    return { admitted: true, answerSdp: pc.localDescription?.sdp };
  }

  /** Apply a member's answer to an SFU-initiated renegotiation offer. */
  async applyAnswer(participantId: string, answerSdp: string): Promise<void> {
    const m = this.members.get(participantId);
    if (!m) return;
    await m.pc.setRemoteDescription({ type: 'answer', sdp: answerSdp } as any);
    m.pendingAnswer?.resolve();
  }

  async addIceCandidate(
    participantId: string,
    candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number },
  ): Promise<void> {
    await this.members.get(participantId)?.pc.addIceCandidate(candidate as any);
  }

  leave(participantId: string): void {
    const m = this.members.get(participantId);
    if (!m) return;
    try {
      m.pc.close();
    } catch {
      /* already closed */
    }
    this.members.delete(participantId);
    for (const key of [...this.forwarded]) {
      if (key.startsWith(`${participantId}->`) || key.includes(`->${participantId}:`)) {
        this.forwarded.delete(key);
      }
    }
  }

  close(): void {
    for (const id of [...this.members.keys()]) this.leave(id);
  }

  /** Forward a source member's track onto a fresh track on `dest`'s PC, then
   *  renegotiate `dest` (SFU offers; dest answers via applyAnswer). */
  private forward(source: Member, srcTrack: MediaStreamTrack, dest: Member): void {
    const key = `${source.id}->${dest.id}:${srcTrack.kind}`;
    if (this.forwarded.has(key)) return; // already wired — idempotent
    this.forwarded.add(key);
    const fwd = new MediaStreamTrack({ kind: srcTrack.kind });
    dest.pc.addTransceiver(fwd, { direction: 'sendonly' });
    srcTrack.onReceiveRtp.subscribe((rtp: any) => {
      source.bytesForwarded += rtp.payload?.length ?? 0;
      fwd.writeRtp(rtp);
    });
    this.renegotiate(dest);
  }

  /** Queue a serialized SFU-initiated renegotiation on `member`'s connection. */
  private renegotiate(member: Member): void {
    member.chain = member.chain
      .then(async () => {
        if (!member.onOffer) return;
        const offer = await member.pc.createOffer();
        await member.pc.setLocalDescription(offer);
        member.pendingAnswer = deferred();
        member.onOffer(member.pc.localDescription!.sdp);
        await member.pendingAnswer.promise; // wait for applyAnswer before the next
      })
      .catch(() => {
        /* a member that dropped mid-renegotiation — skip */
      });
  }
}

```
