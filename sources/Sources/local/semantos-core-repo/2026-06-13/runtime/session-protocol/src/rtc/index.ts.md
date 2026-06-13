---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.040396+00:00
---

# runtime/session-protocol/src/rtc/index.ts

```ts
/**
 * `rtc/` — the shell-native real-time-communication substrate (RTC matrix S7).
 *
 * The single import surface cartridges bind into for voice / video / metered
 * streaming. Real-time calling is NOT a cartridge — it is a shell-native
 * primitive (like streams + the conversation engine) that telehealth,
 * betterment check-ins, oddjobz walk-throughs, a jam-room video layer, etc.
 * all import. Cartridges express WHAT (typed surfaces, UI, FSM verbs); this
 * module owns HOW (the media stack). The one-way-dependency gate
 * (`tests/gates/rtc-substrate-one-way-dep.test.ts`) enforces
 * cartridge → rtc, never rtc → cartridge.
 *
 * Slice status (docs/canon/rtc-matrix.yml):
 *   ✓ S1 rtc.signal   — this slice: Jingle codec + offer/answer/trickle FSM +
 *                       the DTLS-fingerprint pin (axis A authentication half).
 *   ✗ S2 rtc.ice      — STUN/TURN config (next slice; needs a WebRTC runtime).
 *   ✗ S3 rtc.media    — PeerConnection / SRTP (wires into verifyDtlsFingerprint).
 *   ✗ S4 rtc.sfu / S5 rtc.crypto / S6 rtc.meter — later phases.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §4 (the shell import contract).
 */

export * from './jingle';
export * from './fingerprint';
export * from './signal';
export * from './xmpp-signal-channel';
// Signalling carrier over the brain MessageBox — rings a contact through the
// brain (lets two separate helms call each other; no both-peers-in-one-process).
export * from './brain-rtc-signal-channel';
// S2 ICE config + S3 media (PeerConnection port) + the A1 call binding.
export * from './ice';
export * from './media';
export * from './call';
// Text-based conversation → SCG conversation graph (REPLIES_TO relations).
export * from './rtc-text-conversation';
// The browser WebRTC adapter is light (no heavy deps; the native
// RTCPeerConnection is resolved lazily/injectably) so the helm imports it from
// the barrel. `rtcOverXmpp` (xmpp-signal-channel) wires a contact-call plane.
export * from './browser-peer-connection';
// A4 broadcast/VOD — segmented media over the paid swarm (re-export).
export * from './broadcast';

// NOTE: the werift PeerConnection adapter (node/bun runtime) is intentionally
// NOT re-exported here — it pulls the `werift` runtime, which a browser shell
// must not bundle. Node/bun callers import `./werift-peer-connection` directly.

```
