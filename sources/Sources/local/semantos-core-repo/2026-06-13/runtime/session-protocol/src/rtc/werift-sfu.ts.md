---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/werift-sfu.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.039546+00:00
---

# runtime/session-protocol/src/rtc/werift-sfu.ts

```ts
/**
 * werift-sfu — S4 SFU relay: the brain as paid-pubsub-for-RTP (RTC matrix
 * row S4 / adapter A3).
 *
 * A Selective Forwarding Unit hosted by a sovereign-node (bun/werift) service:
 * each participant holds ONE PeerConnection to the SFU (not to every peer, as
 * in the A2 mesh); the SFU forwards a publisher's RTP to subscribers WITHOUT
 * decode/re-encode (no transcode cost). Structurally this is the paid swarm
 * relay applied to RTP — an SFU is paid-pubsub for media. A participant is
 * admitted by the SAME engine-checked `access.grant` that gates file-share
 * (#987) and broadcast (#991) — the SESSION_ACCESS sibling (see
 * `accessGrantAdmission`). Metering forwarded bytes reuses the swarm's per-chunk
 * pattern (the `bytesForwardedFrom` counter is the hook).
 *
 * Node/bun server component (werift-specific, like werift-peer-connection.ts);
 * intentionally NOT re-exported from the rtc barrel. Participants connect with
 * the runtime-agnostic client port; the relay is werift.
 *
 * SCOPE (first slice): the BROADCAST-room shape with two roles — PUBLISHERS
 * offer a sendonly track to the SFU; SUBSCRIBERS receive an offer FROM the SFU
 * carrying the publishers' forward tracks. This is the proven no-renegotiation
 * topology (a talk / town-hall / low-latency paid livestream). Symmetric group
 * calls (every joiner re-offers to existing peers to add their track) are the
 * documented follow-on. Media never rides in cells (RTC §7) — only the
 * admission decision + metering receipts do.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml rows S4/A3,
 * swarm/brain-access-grant-verifier.ts (admission), media.ts (the client port).
 */

import { RTCPeerConnection, MediaStreamTrack } from 'werift';
import type { RtcIceConfig } from './ice';
import type { AccessGrantVerifier } from '../swarm/access-grant-serve';

/** A participant's proof of admission (the engine-checked access-grant proof). */
export interface SfuCredential {
  /** The LINEAR access.grant cell (binds to the room). */
  grantCell: Uint8Array;
  /** The grantee's signed verify.intent cell. */
  intentCell: Uint8Array;
}

/**
 * The admission gate. The real implementation runs the engine-checked verify on
 * the 2-PDA (`BrainAccessGrantVerifier`): a participant joins only with a valid
 * SESSION_ACCESS grant for the room. Returns true to admit.
 */
export interface SfuAdmission {
  admit(participantId: string, credential: SfuCredential | undefined): Promise<boolean>;
}

/** Open admission (dev / no-auth). Production wires `accessGrantAdmission`. */
export const OPEN_ADMISSION: SfuAdmission = { admit: async () => true };

/**
 * Admission backed by the engine-checked access-grant verifier (#991): the SFU
 * admits a participant iff the 2-PDA accepts their signed grant. This is the
 * RTC ↔ DAM convergence for interactive calls — the SESSION_ACCESS sibling of
 * file-share's DATA_ACCESS.
 */
export function accessGrantAdmission(verifier: AccessGrantVerifier): SfuAdmission {
  return {
    async admit(_id, credential) {
      if (!credential) return false;
      const { ok } = await verifier.verify({
        grantCell: credential.grantCell,
        intentCell: credential.intentCell,
      });
      return ok;
    },
  };
}

type IceCb = (candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number }) => void;
type WeriftPc = InstanceType<typeof RTCPeerConnection>;

interface Publisher {
  id: string;
  pc: WeriftPc;
  tracks: MediaStreamTrack[];
  bytesForwarded: number;
}
interface Subscriber {
  id: string;
  pc: WeriftPc;
}

export interface SfuRoomOptions {
  iceConfig?: RtcIceConfig;
  admission?: SfuAdmission;
}

export class SfuRoom {
  private readonly publishers = new Map<string, Publisher>();
  private readonly subscribers = new Map<string, Subscriber>();
  private readonly admission: SfuAdmission;
  private readonly iceConfig: Record<string, unknown>;

  constructor(opts: SfuRoomOptions = {}) {
    this.admission = opts.admission ?? OPEN_ADMISSION;
    this.iceConfig = (opts.iceConfig ?? {}) as Record<string, unknown>;
  }

  size(): number {
    return this.publishers.size + this.subscribers.size;
  }

  /** Bytes the SFU has forwarded from a publisher's media (metering hook). */
  bytesForwardedFrom(publisherId: string): number {
    return this.publishers.get(publisherId)?.bytesForwarded ?? 0;
  }

  /**
   * Admit a PUBLISHER. They offer a sendonly track; the SFU answers and begins
   * receiving their RTP (available to forward to current + future subscribers).
   */
  async publish(req: {
    participantId: string;
    offerSdp: string;
    credential?: SfuCredential;
    onIceCandidate?: IceCb;
  }): Promise<{ admitted: boolean; answerSdp?: string }> {
    if (!(await this.admission.admit(req.participantId, req.credential))) return { admitted: false };

    const pc = new RTCPeerConnection(this.iceConfig);
    const pub: Publisher = { id: req.participantId, pc, tracks: [], bytesForwarded: 0 };
    this.wireIce(pc, req.onIceCandidate);
    pc.onTrack.subscribe((track: MediaStreamTrack) => {
      pub.tracks.push(track);
      // Fan out to subscribers already connected when this track arrives.
      for (const sub of this.subscribers.values()) this.forward(pub, track, sub.pc);
    });

    await pc.setRemoteDescription({ type: 'offer', sdp: req.offerSdp } as any);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    this.publishers.set(req.participantId, pub);
    return { admitted: true, answerSdp: pc.localDescription?.sdp };
  }

  /**
   * Admit a SUBSCRIBER. The SFU OFFERS them the current publishers' forward
   * tracks; the caller delivers the offer and returns the answer via
   * `completeSubscribe`. (SFU-as-offerer is the no-renegotiation downstream leg.)
   */
  async subscribe(req: {
    participantId: string;
    credential?: SfuCredential;
    onIceCandidate?: IceCb;
  }): Promise<{ admitted: boolean; offerSdp?: string }> {
    if (!(await this.admission.admit(req.participantId, req.credential))) return { admitted: false };

    const pc = new RTCPeerConnection(this.iceConfig);
    this.wireIce(pc, req.onIceCandidate);
    // Attach a forward track for every current publisher track.
    for (const pub of this.publishers.values()) {
      for (const track of pub.tracks) this.forward(pub, track, pc);
    }
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    this.subscribers.set(req.participantId, { id: req.participantId, pc });
    return { admitted: true, offerSdp: pc.localDescription?.sdp };
  }

  /** Apply a subscriber's SDP answer to the SFU offer. */
  async completeSubscribe(participantId: string, answerSdp: string): Promise<void> {
    await this.subscribers
      .get(participantId)
      ?.pc.setRemoteDescription({ type: 'answer', sdp: answerSdp } as any);
  }

  /** Add a participant's trickled ICE candidate to the SFU-side connection. */
  async addIceCandidate(
    participantId: string,
    candidate: { candidate: string; sdpMid?: string; sdpMLineIndex?: number },
  ): Promise<void> {
    const pc = this.publishers.get(participantId)?.pc ?? this.subscribers.get(participantId)?.pc;
    await pc?.addIceCandidate(candidate as any);
  }

  /** Remove a participant and tear down its connection. */
  leave(participantId: string): void {
    for (const map of [this.publishers, this.subscribers]) {
      const p = map.get(participantId) as { pc: WeriftPc } | undefined;
      if (p) {
        try {
          p.pc.close();
        } catch {
          /* already closed */
        }
        map.delete(participantId);
      }
    }
  }

  close(): void {
    for (const id of [...this.publishers.keys(), ...this.subscribers.keys()]) this.leave(id);
  }

  private wireIce(pc: WeriftPc, cb?: IceCb): void {
    if (!cb) return;
    pc.onIceCandidate.subscribe((c: any) => {
      if (c?.candidate) cb({ candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex });
    });
  }

  /** Pipe a source track's RTP onto a fresh forward track on `destPc`. */
  private forward(source: Publisher, srcTrack: MediaStreamTrack, destPc: WeriftPc): void {
    const fwd = new MediaStreamTrack({ kind: srcTrack.kind });
    destPc.addTransceiver(fwd, { direction: 'sendonly' });
    srcTrack.onReceiveRtp.subscribe((rtp: any) => {
      source.bytesForwarded += rtp.payload?.length ?? 0; // metering hook
      fwd.writeRtp(rtp);
    });
  }
}

```
