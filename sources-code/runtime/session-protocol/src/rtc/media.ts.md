---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/media.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.041227+00:00
---

# runtime/session-protocol/src/rtc/media.ts

```ts
/**
 * rtc.media — S3 media pipeline (RTC matrix row S3).
 *
 * The WebRTC PeerConnection: the real SRTP/DTLS media + data path. This module
 * is the shell-native, runtime-AGNOSTIC surface — a normalised `RtcPeerConnection`
 * port that both the browser-native `RTCPeerConnection` and the node/bun
 * `werift` runtime implement (see werift-peer-connection.ts). Cartridges +
 * the call binding (call.ts) program against this port, never a concrete
 * WebRTC library, so the same calling code runs in the PWA and in a sovereign-
 * node service (the brain as a real WebRTC endpoint: SFU relay, recorder,
 * telehealth bridge).
 *
 * Media rides native SRTP over the UDP path ICE establishes — NEVER wrapped in
 * the 1024-byte cell (RTC §7). The cell rail carries only the signalling
 * (Jingle, via S1), the fingerprint commitment, and metering receipts.
 *
 * The DTLS fingerprint that axis A pins (S1) is read from the local SDP via the
 * Jingle codec's `fingerprintFromSdp`, so S1 and S3 agree byte-for-byte on the
 * value.
 *
 * Cross-reference: docs/canon/rtc-matrix.yml row S3, ice.ts (S2 config),
 * signal.ts/jingle.ts (S1), call.ts (the A1 binding).
 */

import { fingerprintFromSdp, type DtlsFingerprint, type IceCandidate } from './jingle';
import type { RtcIceConfig } from './ice';

export interface RtcSessionDescription {
  type: 'offer' | 'answer';
  sdp: string;
}

export type RtcConnectionState =
  | 'new'
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'failed'
  | 'closed';

/** A bidirectional data channel (the simplest media: app data over SCTP/DTLS). */
export interface RtcDataChannel {
  readonly label: string;
  send(data: string | Uint8Array): void;
  onOpen(cb: () => void): void;
  onMessage(cb: (data: string | Uint8Array) => void): void;
  readyState(): string;
  close(): void;
}

export type MediaKind = 'audio' | 'video';

/**
 * A media track handle. The substrate negotiates + routes tracks (SRTP over the
 * ICE path); what a track *is* depends on the runtime: a browser track attaches
 * to a `<video>`/`<audio>` sink via `native`; a node/werift track exposes its
 * RTP via `onRtp` (for a recorder, an SFU forward, or a test). One of the two
 * accessors is always present — the browser path uses `native`, the node path
 * uses `onRtp` (and `native` for forwarding to another werift PeerConnection).
 */
export interface RtcMediaTrack {
  readonly kind: MediaKind;
  /** The runtime-native track (browser/werift `MediaStreamTrack`). */
  readonly native: unknown;
  /** Subscribe to received RTP payloads (node/werift receiver path). */
  onRtp(cb: (payload: Uint8Array) => void): void;
}

/**
 * The normalised PeerConnection port. A small, W3C-shaped subset that both the
 * browser and werift satisfy. Track (audio/video) plumbing is intentionally
 * minimal here (data channel first); media tracks extend this in a follow-on.
 */
export interface RtcPeerConnection {
  createOffer(): Promise<RtcSessionDescription>;
  createAnswer(): Promise<RtcSessionDescription>;
  setLocalDescription(d: RtcSessionDescription): Promise<void>;
  setRemoteDescription(d: RtcSessionDescription): Promise<void>;
  addIceCandidate(c: IceCandidate): Promise<void>;
  /** The local SDP once set (carries the DTLS fingerprint S1 pins). */
  localDescription(): RtcSessionDescription | null;
  onIceCandidate(cb: (c: IceCandidate) => void): void;
  onConnectionStateChange(cb: (s: RtcConnectionState) => void): void;
  connectionState(): RtcConnectionState;
  createDataChannel(label: string): RtcDataChannel;
  onDataChannel(cb: (ch: RtcDataChannel) => void): void;
  /** Publish a local media track (adds a sendonly m-line). */
  addTrack(track: RtcMediaTrack): void;
  /** Fires for each remote media track the peer publishes. */
  onTrack(cb: (track: RtcMediaTrack) => void): void;
  close(): void;
}

/** Construct a PeerConnection for an ICE config. Browser + werift each provide one. */
export type RtcPeerConnectionFactory = (config: RtcIceConfig) => RtcPeerConnection;

/**
 * The DTLS fingerprint from a peer's local description — the value S1 pins into
 * the SignedBundle. Returns null before `setLocalDescription`. Uses the same
 * Jingle codec parser as S1, so the pinned and observed values are identical
 * representations.
 */
export function localFingerprint(pc: RtcPeerConnection): DtlsFingerprint | null {
  const d = pc.localDescription();
  if (!d) return null;
  try {
    return fingerprintFromSdp(d.sdp);
  } catch {
    return null;
  }
}

```
