---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/browser-peer-connection.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.042614+00:00
---

# runtime/session-protocol/src/rtc/browser-peer-connection.ts

```ts
/**
 * browser-peer-connection — the BROWSER WebRTC runtime adapter for S3.
 *
 * Wraps the native `RTCPeerConnection` (the W3C API the PWA / loom-svelte helm
 * runs) into the normalised `RtcPeerConnection` port. The port was shaped after
 * the W3C surface, so this adapter is thin — it normalises the event API
 * (`onicecandidate`, `ontrack`, `ondatachannel`) to the port's callback style
 * and exposes `localDescription()` as a method.
 *
 * Pairs with werift-peer-connection.ts (node/bun). Both satisfy the same port,
 * so the call binding (call.ts) is identical in the browser and on a sovereign
 * node — a contact call placed from the helm and one relayed by the brain SFU
 * run the same code.
 *
 * Browser tracks attach to a `<video>`/`<audio>` sink via `native` (a
 * `MediaStreamTrack`); the port's `onRtp` is a no-op here (raw RTP is not
 * exposed in the browser — that's the node/werift path, for recording or the
 * SFU forward).
 *
 * The `RTCPeerConnection` constructor is injectable (defaults to the global) so
 * this module imports cleanly off-DOM (node typecheck) and can be unit-tested
 * with a fake; real verification is in a browser.
 *
 * Cross-reference: media.ts (the port), call.ts (the binding),
 * werift-peer-connection.ts (the node sibling).
 */

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

/** Minimal structural type for the native RTCPeerConnection (avoids a DOM lib dep). */
type NativePc = any;
type NativeCtor = new (config?: unknown) => NativePc;

function wrapTrack(native: any): RtcMediaTrack {
  return {
    kind: native.kind as MediaKind,
    native,
    // Browser tracks are consumed by attaching `native` to a media element;
    // raw RTP is not available in the browser.
    onRtp() {
      /* no-op in the browser */
    },
  };
}

function wrapChannel(ch: any): RtcDataChannel {
  return {
    label: ch.label,
    send(data) {
      ch.send(data);
    },
    onOpen(cb) {
      if (ch.readyState === 'open') cb();
      ch.addEventListener('open', () => cb());
    },
    onMessage(cb) {
      ch.addEventListener('message', (ev: { data: string | ArrayBuffer | Uint8Array }) => {
        cb(typeof ev.data === 'string' ? ev.data : new Uint8Array(ev.data as ArrayBuffer));
      });
    },
    readyState() {
      return ch.readyState;
    },
    close() {
      ch.close();
    },
  };
}

class BrowserRtcPeerConnection implements RtcPeerConnection {
  constructor(private readonly pc: NativePc) {}

  async createOffer(): Promise<RtcSessionDescription> {
    const o = await this.pc.createOffer();
    return { type: 'offer', sdp: o.sdp };
  }
  async createAnswer(): Promise<RtcSessionDescription> {
    const a = await this.pc.createAnswer();
    return { type: 'answer', sdp: a.sdp };
  }
  async setLocalDescription(d: RtcSessionDescription): Promise<void> {
    await this.pc.setLocalDescription(d);
  }
  async setRemoteDescription(d: RtcSessionDescription): Promise<void> {
    await this.pc.setRemoteDescription(d);
  }
  async addIceCandidate(c: IceCandidate): Promise<void> {
    await this.pc.addIceCandidate({ candidate: c.candidate, sdpMid: c.sdpMid, sdpMLineIndex: c.sdpMLineIndex });
  }
  localDescription(): RtcSessionDescription | null {
    const d = this.pc.localDescription;
    return d ? { type: d.type, sdp: d.sdp } : null;
  }
  onIceCandidate(cb: (c: IceCandidate) => void): void {
    this.pc.addEventListener('icecandidate', (ev: { candidate: any }) => {
      const c = ev.candidate;
      if (!c || !c.candidate) return;
      cb({
        candidate: c.candidate,
        ...(c.sdpMid != null ? { sdpMid: c.sdpMid } : {}),
        ...(c.sdpMLineIndex != null ? { sdpMLineIndex: c.sdpMLineIndex } : {}),
      });
    });
  }
  onConnectionStateChange(cb: (s: RtcConnectionState) => void): void {
    this.pc.addEventListener('connectionstatechange', () => cb(this.pc.connectionState as RtcConnectionState));
  }
  connectionState(): RtcConnectionState {
    return this.pc.connectionState as RtcConnectionState;
  }
  createDataChannel(label: string): RtcDataChannel {
    return wrapChannel(this.pc.createDataChannel(label));
  }
  onDataChannel(cb: (ch: RtcDataChannel) => void): void {
    this.pc.addEventListener('datachannel', (ev: { channel: any }) => cb(wrapChannel(ev.channel)));
  }
  addTrack(track: RtcMediaTrack): void {
    this.pc.addTrack(track.native);
  }
  onTrack(cb: (track: RtcMediaTrack) => void): void {
    this.pc.addEventListener('track', (ev: { track: any }) => cb(wrapTrack(ev.track)));
  }
  close(): void {
    this.pc.close();
  }
}

/** Wrap a browser `MediaStreamTrack` (e.g. from getUserMedia) as an RtcMediaTrack. */
export function browserTrack(native: any): RtcMediaTrack {
  return wrapTrack(native);
}

/**
 * The browser WebRTC factory. Pass the native `RTCPeerConnection` constructor
 * (defaults to the global) — `makeBrowserPeerConnectionFactory()` in the helm,
 * or inject a fake in a unit test.
 */
export function makeBrowserPeerConnectionFactory(ctor?: NativeCtor): RtcPeerConnectionFactory {
  const PC = ctor ?? (globalThis as { RTCPeerConnection?: NativeCtor }).RTCPeerConnection;
  if (!PC) {
    throw new Error('makeBrowserPeerConnectionFactory: no RTCPeerConnection (not a browser); pass a constructor');
  }
  return (config: RtcIceConfig) => new BrowserRtcPeerConnection(new PC(config));
}

```
