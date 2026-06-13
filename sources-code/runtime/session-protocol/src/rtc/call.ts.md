---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/call.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.040662+00:00
---

# runtime/session-protocol/src/rtc/call.ts

```ts
/**
 * rtc/call — the A1 1:1 call binding (RTC matrix row A1): S1 signalling +
 * S2 ICE + S3 media, fingerprint-pinned. This is the flagship
 * PKI-authenticated 1:1 call on the smallest surface — pure peer-to-peer, no
 * media server.
 *
 * It wires the signalling plane (Jingle offer/answer/trickle over the signed
 * carrier) to a real PeerConnection (browser-native or werift):
 *
 *   caller:  placeMediaCall → createOffer → signal.placeCall → on answer:
 *            setRemoteDescription; ICE trickles both ways over S1.
 *   callee:  on plane.onIncomingCall → answerMediaCall → setRemoteDescription
 *            (the offer) → createAnswer → signal.answer; ICE trickles.
 *
 * The DTLS fingerprint in each side's SDP is pinned into the SignedBundle by S1
 * (axis A); media only flows to the cert holder because the DTLS handshake's
 * certificate must match the fingerprint in the (signed) remote description.
 * `pinnedRemoteFingerprint()` exposes the pinned value for the S3 admission
 * check.
 *
 * Runtime-agnostic: it takes an `RtcPeerConnectionFactory`, so the same call
 * runs in the PWA (browser RTCPeerConnection) and in a sovereign-node service
 * (werift) — the brain as a real call endpoint.
 *
 * Cross-reference: signal.ts (S1), media.ts (S3), ice.ts (S2),
 * docs/canon/rtc-matrix.yml rows A1/S1/S2/S3.
 */

import type { RtcSignalPlane, RtcCall } from './signal';
import type { RtcIceConfig } from './ice';
import {
  type RtcConnectionState,
  type RtcDataChannel,
  type RtcMediaTrack,
  type RtcPeerConnection,
  type RtcPeerConnectionFactory,
} from './media';
import type { DtlsFingerprint } from './jingle';

export interface MediaCall {
  readonly sid: string;
  readonly peerCertId: string;
  /** The underlying PeerConnection (for tracks / stats / advanced use). */
  readonly pc: RtcPeerConnection;
  /** The signalling call (state, hangup events). */
  readonly signal: RtcCall;
  /** A data channel this side opened at call setup (by label). */
  channel(label: string): RtcDataChannel | undefined;
  /** Channels the remote side opened (callee observes the caller's channels). */
  onDataChannel(cb: (ch: RtcDataChannel) => void): void;
  /** Media tracks the remote side published (audio/video). */
  onTrack(cb: (track: RtcMediaTrack) => void): void;
  onConnectionStateChange(cb: (s: RtcConnectionState) => void): void;
  onConnected(cb: () => void): void;
  /** The remote DTLS fingerprint pinned from the signed offer/answer (axis A). */
  pinnedRemoteFingerprint(): DtlsFingerprint | undefined;
  hangup(reason?: string): Promise<void>;
}

function bind(pc: RtcPeerConnection, call: RtcCall, channels: Map<string, RtcDataChannel>): MediaCall {
  // Trickle local ICE out over the signed signalling channel.
  pc.onIceCandidate((c) => {
    void call.addCandidate(c).catch(() => {});
  });
  // Apply remote ICE arriving over signalling.
  call.onRemoteCandidate((c) => {
    void pc.addIceCandidate(c).catch(() => {});
  });
  // Tear the media down when the call ends.
  call.onTerminate(() => pc.close());

  return {
    sid: call.sid,
    peerCertId: call.peerCertId,
    pc,
    signal: call,
    channel: (label) => channels.get(label),
    onDataChannel: (cb) => pc.onDataChannel(cb),
    onTrack: (cb) => pc.onTrack(cb),
    onConnectionStateChange: (cb) => pc.onConnectionStateChange(cb),
    onConnected: (cb) =>
      pc.onConnectionStateChange((s) => {
        if (s === 'connected') cb();
      }),
    pinnedRemoteFingerprint: () => call.pinnedRemoteFingerprint(),
    async hangup(reason) {
      await call.hangup(reason);
      pc.close();
    },
  };
}

/**
 * Caller: place a PKI-authenticated 1:1 media call. Creates the PeerConnection,
 * offers, signals via S1, and applies the answer when it arrives.
 */
export interface MediaCallOptions {
  /**
   * Data-channel labels to open at setup. At least one media section (a channel
   * or a track) MUST exist before the offer, else the SDP carries no
   * a=fingerprint. Defaults to `['data']` ONLY when no tracks are published.
   */
  channels?: string[];
  /** Local media tracks (audio/video) to publish on the call. */
  tracks?: RtcMediaTrack[];
}

export async function placeMediaCall(
  plane: RtcSignalPlane,
  factory: RtcPeerConnectionFactory,
  config: RtcIceConfig,
  peerCertId: string,
  opts: MediaCallOptions = {},
): Promise<MediaCall> {
  const pc = factory(config);
  // Publish media tracks + open app channels BEFORE offering, so the SDP has an
  // m-line (and therefore an a=fingerprint). A default data channel is added
  // only when nothing else provides an m-line.
  const tracks = opts.tracks ?? [];
  for (const t of tracks) pc.addTrack(t);
  const channels = new Map<string, RtcDataChannel>();
  const channelLabels = opts.channels ?? (tracks.length === 0 ? ['data'] : []);
  for (const label of channelLabels) channels.set(label, pc.createDataChannel(label));

  const offer = await pc.createOffer();
  await pc.setLocalDescription(offer);
  // Signal the LOCAL description (post-set) — that's where the runtime fills in
  // the a=fingerprint line that S1 pins; the raw createOffer SDP lacks it.
  const localSdp = pc.localDescription()?.sdp ?? offer.sdp;
  const call = await plane.placeCall(peerCertId, { sdp: localSdp });
  call.onAnswer((answer) => {
    void pc.setRemoteDescription({ type: 'answer', sdp: answer.sdp }).catch(() => {});
  });
  return bind(pc, call, channels);
}

/**
 * Callee: answer an incoming media call (from `plane.onIncomingCall`). Applies
 * the offer, answers via S1, and returns the live media call.
 */
export async function answerMediaCall(
  incoming: RtcCall,
  factory: RtcPeerConnectionFactory,
  config: RtcIceConfig,
  opts: { tracks?: RtcMediaTrack[] } = {},
): Promise<MediaCall> {
  if (!incoming.remoteDescription) {
    throw new Error('answerMediaCall: incoming call has no remote offer');
  }
  const pc = factory(config);
  await pc.setRemoteDescription({ type: 'offer', sdp: incoming.remoteDescription.sdp });
  // Publish the callee's tracks AFTER the offer is applied so they attach to the
  // transceivers the offer created — making the call two-way (sendrecv).
  for (const t of opts.tracks ?? []) pc.addTrack(t);
  const answer = await pc.createAnswer();
  await pc.setLocalDescription(answer);
  const mediaCall = bind(pc, incoming, new Map());
  // Signal the local description (post-set) so the answer carries a=fingerprint.
  const localSdp = pc.localDescription()?.sdp ?? answer.sdp;
  await incoming.answer({ sdp: localSdp });
  return mediaCall;
}

```
