---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/loom-svelte/src/lib/rtc-call.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.082185+00:00
---

# apps/loom-svelte/src/lib/rtc-call.ts

```ts
/**
 * rtc-call — helm-side wiring for real WebRTC calls to a contact.
 *
 * Binds the substrate RTC modules (aliased `@rtc/*` — pure TS/DOM/fetch, see
 * vite.config.mjs) into the helm: signalling rides the brain MessageBox relay
 * (`rtcOverBrain`), media uses the browser's native RTCPeerConnection
 * (`makeBrowserPeerConnectionFactory`), capture is `getUserMedia`. The operator
 * identity (mailbox = pin pubkey, cert id) comes from GET /api/v1/info; a
 * contact's mailbox is its `publicKey`.
 *
 * SIGNER: a call's Jingle is wrapped in a SignedBundle signed by the operator
 * key. That key lives on the brain (the sovereign node), not in this SPA — so
 * the helm signs via the brain "sign-as-operator" endpoint
 * (`makeBrainOperatorSigner` → POST /api/v1/bundle/sign, D-helm-rtc-operator-sign).
 * The recipient verifies inbound calls against the sender contact's pubkey
 * (`makeContactBundleVerifier`, #999), so forged/tampered calls are rejected.
 */

import { rtcOverBrain } from '@rtc/brain-rtc-signal-channel';
import { makeBrowserPeerConnectionFactory, browserTrack } from '@rtc/browser-peer-connection';
import { placeMediaCall, answerMediaCall, type MediaCall } from '@rtc/call';
import { DEFAULT_ICE_CONFIG } from '@rtc/ice';
import { makeBrainOperatorSigner } from '@rtc/brain-operator-signer';
import { makeContactBundleVerifier } from '@rtc/bsv-signed-bundle-verifier';
import type { RtcSignalPlane, RtcCall } from '@rtc/signal';

/** GET /api/v1/info — the operator's pin identity (parity with the me panel). */
export interface BrainInfoIdentity {
  brain_pin_pubkey: string; // 66-hex compressed operator pin pubkey
  brain_pin_cert_id: string;
}

export async function getBrainIdentity(brainBase: string, bearer: string): Promise<BrainInfoIdentity> {
  const res = await fetch(`${brainBase}/api/v1/info`, { headers: { Authorization: `Bearer ${bearer}` } });
  if (!res.ok) throw new Error(`/api/v1/info ${res.status}`);
  const j = (await res.json()) as Partial<BrainInfoIdentity>;
  return { brain_pin_pubkey: j.brain_pin_pubkey ?? '', brain_pin_cert_id: j.brain_pin_cert_id ?? '' };
}

export interface HelmRtcDeps {
  brainBase: string;
  bearer: string;
  identity: BrainInfoIdentity;
  /** Resolve a contact cert id → its 66-hex pubkey (mailbox). */
  contactPubkey: (certId: string) => string | undefined;
}

/** A signalling plane that rings contacts through the brain (MessageBox relay). */
export function makeHelmRtcPlane(deps: HelmRtcDeps): RtcSignalPlane {
  return rtcOverBrain({
    brainBase: deps.brainBase,
    bearer: deps.bearer,
    selfMailbox: deps.identity.brain_pin_pubkey,
    mailboxFor: (certId) => deps.contactPubkey(certId) ?? certId,
    // Operator-signed via the brain (POST /api/v1/bundle/sign); the SPA never
    // holds the operator key.
    signBundle: makeBrainOperatorSigner({
      brainBase: deps.brainBase,
      bearer: deps.bearer,
      selfCertId: deps.identity.brain_pin_cert_id,
      selfPubkeyHex: deps.identity.brain_pin_pubkey,
    }),
    // Reject inbound calls whose operator signature doesn't verify against the
    // sender contact's known pubkey.
    verifyInbound: makeContactBundleVerifier(deps.contactPubkey),
    selfJid: deps.identity.brain_pin_cert_id,
  });
}

const factory = makeBrowserPeerConnectionFactory();

/** Capture the mic as RtcMediaTracks (audio-only first cut). */
export async function captureMic(): Promise<{ tracks: ReturnType<typeof browserTrack>[]; stop: () => void }> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  return {
    tracks: stream.getAudioTracks().map((t) => browserTrack(t)),
    stop: () => stream.getTracks().forEach((t) => t.stop()),
  };
}

/** Attach a remote media track to a hidden <audio> sink so it plays. */
export function playRemote(call: MediaCall): () => void {
  const audio = new Audio();
  audio.autoplay = true;
  const stream = new MediaStream();
  call.onTrack((track) => {
    stream.addTrack(track.native as MediaStreamTrack);
    audio.srcObject = stream;
    void audio.play().catch(() => {});
  });
  return () => {
    audio.pause();
    audio.srcObject = null;
  };
}

/** Place an outgoing 1:1 audio call to a contact. */
export async function placeCall(plane: RtcSignalPlane, contactCertId: string): Promise<{ call: MediaCall; stopMic: () => void }> {
  const mic = await captureMic();
  const call = await placeMediaCall(plane, factory, DEFAULT_ICE_CONFIG, contactCertId, { tracks: mic.tracks });
  return { call, stopMic: mic.stop };
}

/** Answer an incoming call (from `plane.onIncomingCall`). */
export async function answerCall(incoming: RtcCall): Promise<{ call: MediaCall; stopMic: () => void }> {
  const mic = await captureMic();
  const call = await answerMediaCall(incoming, factory, DEFAULT_ICE_CONFIG, { tracks: mic.tracks });
  return { call, stopMic: mic.stop };
}

export { devSignBundle };

```
