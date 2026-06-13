---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/werift-peer-connection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.041501+00:00
---

# runtime/session-protocol/src/rtc/werift-peer-connection.ts

```ts
/**
 * werift-peer-connection — the node/bun WebRTC runtime adapter for S3.
 *
 * Implements the normalised `RtcPeerConnectionFactory` over `werift` (pure-
 * TypeScript WebRTC: real ICE/DTLS/SRTP, no native addon — it runs in bun,
 * unlike the native `@roamhq/wrtc` which crashes bun's NAPI shim). This is what
 * makes a sovereign-node service a REAL WebRTC endpoint — the brain hosting
 * actual calls (SFU relay, recorder, telehealth bridge), not a mock.
 *
 * The browser uses its native `RTCPeerConnection` via a sibling adapter; both
 * satisfy the same `RtcPeerConnection` port, so the call binding (call.ts) is
 * runtime-agnostic.
 *
 * Cross-reference: media.ts (the port), https://github.com/shinyoshiaki/werift-webrtc.
 */

import { RTCPeerConnection as WeriftPeerConnection, MediaStreamTrack, RtpPacket, RtpHeader } from 'werift';
import type { IceCandidate } from './jingle';
import type { RtcIceConfig } from './ice';
import type {
  MediaKind,
  RtcConnectionState,
  RtcDataChannel,
  RtcMediaTrack,
  RtcPeerConnection,
  RtcPeerConnectionFactory,
  RtcSessionDescription,
} from './media';

/** Wrap a werift MediaStreamTrack as the normalised RtcMediaTrack. */
export function weriftTrack(native: any): RtcMediaTrack {
  return {
    kind: native.kind as MediaKind,
    native,
    onRtp(cb) {
      native.onReceiveRtp.subscribe((rtp: any) => cb(rtp.payload ?? new Uint8Array()));
    },
  };
}

/**
 * Create a writable local media source (a werift track you can pump RTP into) —
 * the node-side stand-in for a capture device or an SFU relay leg. In the
 * browser, a local track comes from `getUserMedia` instead and is wrapped the
 * same way. Returns the RtcMediaTrack to `addTrack` + a `writeRtp` to feed it.
 */
export function weriftMediaSource(kind: MediaKind, opts: { payloadType?: number; ssrc?: number } = {}): {
  track: RtcMediaTrack;
  writeRtp(payload: Uint8Array, seq: number, timestamp: number): void;
} {
  const native = new MediaStreamTrack({ kind });
  const pt = opts.payloadType ?? (kind === 'audio' ? 96 : 97);
  const ssrc = opts.ssrc ?? 0x1234abcd;
  return {
    track: weriftTrack(native),
    writeRtp(payload, seq, timestamp) {
      const header = new RtpHeader({ payloadType: pt, sequenceNumber: seq & 0xffff, timestamp, ssrc });
      native.writeRtp(new RtpPacket(header, Buffer.from(payload)));
    },
  };
}

function toWeriftConfig(config: RtcIceConfig): Record<string, unknown> {
  return {
    ...(config.iceServers ? { iceServers: config.iceServers } : {}),
    ...(config.iceTransportPolicy ? { iceTransportPolicy: config.iceTransportPolicy } : {}),
  };
}

function wrapChannel(ch: any): RtcDataChannel {
  return {
    label: ch.label,
    send(data) {
      ch.send(typeof data === 'string' ? data : Buffer.from(data));
    },
    onOpen(cb) {
      if (ch.readyState === 'open') cb();
      ch.stateChanged.subscribe((s: string) => {
        if (s === 'open') cb();
      });
    },
    onMessage(cb) {
      ch.onmessage = (ev: { data: string | Uint8Array }) => cb(ev.data);
    },
    readyState() {
      return ch.readyState;
    },
    close() {
      ch.close();
    },
  };
}

class WeriftRtcPeerConnection implements RtcPeerConnection {
  /** Buffer received tracks so a subscriber added after negotiation still sees
   *  them (the rx onTrack event does not replay to late subscribers). */
  private readonly receivedTracks: RtcMediaTrack[] = [];
  private readonly trackSubs = new Set<(t: RtcMediaTrack) => void>();

  constructor(private readonly pc: any) {
    this.pc.onTrack.subscribe((t: any) => {
      const wrapped = weriftTrack(t);
      this.receivedTracks.push(wrapped);
      for (const cb of this.trackSubs) cb(wrapped);
    });
  }

  async createOffer(): Promise<RtcSessionDescription> {
    const o = await this.pc.createOffer();
    return { type: 'offer', sdp: o.sdp };
  }
  async createAnswer(): Promise<RtcSessionDescription> {
    const a = await this.pc.createAnswer();
    return { type: 'answer', sdp: a.sdp };
  }
  async setLocalDescription(d: RtcSessionDescription): Promise<void> {
    await this.pc.setLocalDescription(d as any);
  }
  async setRemoteDescription(d: RtcSessionDescription): Promise<void> {
    await this.pc.setRemoteDescription(d as any);
  }
  async addIceCandidate(c: IceCandidate): Promise<void> {
    await this.pc.addIceCandidate({
      candidate: c.candidate,
      sdpMid: c.sdpMid,
      sdpMLineIndex: c.sdpMLineIndex,
    });
  }
  localDescription(): RtcSessionDescription | null {
    const d = this.pc.localDescription;
    return d ? { type: d.type, sdp: d.sdp } : null;
  }
  onIceCandidate(cb: (c: IceCandidate) => void): void {
    this.pc.onIceCandidate.subscribe((c: any) => {
      if (!c || !c.candidate) return;
      cb({
        candidate: c.candidate,
        ...(c.sdpMid != null ? { sdpMid: c.sdpMid } : {}),
        ...(c.sdpMLineIndex != null ? { sdpMLineIndex: c.sdpMLineIndex } : {}),
      });
    });
  }
  onConnectionStateChange(cb: (s: RtcConnectionState) => void): void {
    this.pc.connectionStateChange.subscribe((s: RtcConnectionState) => cb(s));
  }
  connectionState(): RtcConnectionState {
    return this.pc.connectionState;
  }
  createDataChannel(label: string): RtcDataChannel {
    return wrapChannel(this.pc.createDataChannel(label));
  }
  onDataChannel(cb: (ch: RtcDataChannel) => void): void {
    this.pc.onDataChannel.subscribe((ch: any) => cb(wrapChannel(ch)));
  }
  addTrack(track: RtcMediaTrack): void {
    // Reuse an existing transceiver of the same kind that has no sending track
    // yet — this is the callee attaching its own track to the transceiver the
    // offer created, making the call two-way. Otherwise create one. `sendrecv`
    // so either side can both send and receive on the m-line.
    const reusable = this.pc
      .getTransceivers()
      .find((t: any) => t.kind === track.kind && !t.sender?.track);
    if (reusable) {
      void reusable.sender.replaceTrack(track.native);
      reusable.setDirection('sendrecv');
    } else {
      this.pc.addTransceiver(track.native, { direction: 'sendrecv' });
    }
  }
  onTrack(cb: (track: RtcMediaTrack) => void): void {
    for (const t of this.receivedTracks) cb(t); // replay tracks seen before subscribe
    this.trackSubs.add(cb);
  }
  close(): void {
    this.pc.close();
  }
}

/** The node/bun WebRTC factory (werift-backed). Pass to the call binding. */
export const weriftPeerConnectionFactory: RtcPeerConnectionFactory = (config) =>
  new WeriftRtcPeerConnection(new WeriftPeerConnection(toWeriftConfig(config)));

```
