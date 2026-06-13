---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/signal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.043175+00:00
---

# runtime/session-protocol/src/rtc/signal.ts

```ts
/**
 * rtc.signal — S1 Signalling Plane (RTC matrix row S1).
 *
 * The offer/answer/trickle state machine for a call, carried over a
 * transport-agnostic `RtcSignalChannel`. This is the public S1 surface the
 * roadmap names — `placeCall / answer / addCandidate / hangup` — plus the
 * fingerprint pin that makes axis A meaningful on every downstream row.
 *
 *   caller:  placeCall(peer, { sdp:offer })  ──session-initiate──▶
 *                                            ◀──session-accept──   onAnswer
 *   callee:  onIncomingCall(call)            ◀──session-initiate──
 *            call.answer({ sdp:answer })      ──session-accept──▶
 *   both:    addCandidate(c)                 ──transport-info──▶   onRemoteCandidate
 *            hangup(reason)                  ──session-terminate─▶  onTerminate
 *
 * Trust model: the peer's identity is the cert id the carrier reports
 * (`fromCertId` — extracted from the verified SignedBundle the Jingle rode in),
 * NOT the self-asserted `initiator`/`responder` JID inside the stanza. The
 * remote fingerprint is pinned to that cert id (see fingerprint.ts).
 *
 * The plane holds NO media: it never touches a PeerConnection, getUserMedia, or
 * SRTP. It produces/consumes SDP blobs and ICE candidates as opaque strings.
 * S3 (rtc.media) owns the PeerConnection and calls `verifyDtlsFingerprint`
 * before letting media flow.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §3 + §4, docs/canon/rtc-matrix.yml
 * row S1.
 */

import {
  decodeJingleStanza,
  descriptionFromSdp,
  encodeJingleStanza,
  type DtlsFingerprint,
  type IceCandidate,
  type JingleDescription,
} from './jingle';
import { FingerprintPinStore } from './fingerprint';

// ── the carrier port ───────────────────────────────────────────────────
// Implemented by the merged XMPP node (see xmpp-signal-channel.ts) or by an
// in-memory pair in tests. The channel is responsible for PKI verification of
// the inbound bundle BEFORE handing the Jingle up: `fromCertId` is trusted.

export interface InboundSignal {
  /** Cert id of the verified sender (from the SignedBundle's leaf cert). */
  fromCertId: string;
  /** The raw Jingle `<iq>` stanza. */
  jingleXml: string;
}

export interface RtcSignalChannel {
  /** Send a Jingle stanza to a peer addressed by cert id. */
  sendTo(peerCertId: string, jingleXml: string): Promise<void>;
  /** Subscribe to inbound (already-verified) Jingle stanzas. */
  onInbound(handler: (msg: InboundSignal) => void): () => void;
}

// ── call model ─────────────────────────────────────────────────────────

export type CallRole = 'caller' | 'callee';
export type CallState = 'offering' | 'incoming' | 'active' | 'terminated';

type Listener<T> = (arg: T) => void;
function emitterSet<T>() {
  const set = new Set<Listener<T>>();
  return {
    add(l: Listener<T>): () => void {
      set.add(l);
      return () => set.delete(l);
    },
    fire(arg: T): void {
      for (const l of [...set]) l(arg);
    },
    clear(): void {
      set.clear();
    },
  };
}

/**
 * One call. Created by `placeCall` (caller) or on an inbound session-initiate
 * (callee). Exposes the per-call control surface + events.
 */
export class RtcCall {
  state: CallState;
  /** The remote SDP (offer for the callee, answer for the caller). */
  remoteDescription?: JingleDescription;

  private readonly onAnswerE = emitterSet<JingleDescription>();
  private readonly onRemoteCandidateE = emitterSet<IceCandidate>();
  private readonly onTerminateE = emitterSet<string>();
  private readonly onStateE = emitterSet<CallState>();
  private seq = 0;

  constructor(
    readonly sid: string,
    readonly role: CallRole,
    /** Trusted peer cert id (from the verified carrier). */
    readonly peerCertId: string,
    readonly selfJid: string,
    private readonly channel: RtcSignalChannel,
    private readonly pins: FingerprintPinStore,
    initialState: CallState,
  ) {
    this.state = initialState;
  }

  private nextId(): string {
    return `${this.sid}-${++this.seq}`;
  }

  private setState(s: CallState): void {
    if (this.state === s) return;
    this.state = s;
    this.onStateE.fire(s);
  }

  /** @internal — caller side: an inbound session-accept landed. */
  _acceptedBy(fromCertId: string, answer: JingleDescription): void {
    if (this.role !== 'caller' || this.state !== 'offering') return;
    if (fromCertId !== this.peerCertId) return; // accept from a stranger — ignore
    this.pins.pin(this.sid, this.peerCertId, answer.fingerprint);
    this.remoteDescription = answer;
    this.setState('active');
    this.onAnswerE.fire(answer);
  }

  /** @internal — an inbound trickled candidate landed. */
  _remoteCandidate(c: IceCandidate): void {
    if (this.state === 'terminated') return;
    this.onRemoteCandidateE.fire(c);
  }

  /** @internal — an inbound session-terminate landed. */
  _terminated(reason: string): void {
    if (this.state === 'terminated') return;
    this.setState('terminated');
    this.pins.clear(this.sid);
    this.onTerminateE.fire(reason);
  }

  /**
   * Callee: answer an incoming call with the local SDP answer. Sends
   * session-accept; transitions to active.
   */
  async answer(local: { sdp: string }): Promise<void> {
    if (this.role !== 'callee' || this.state !== 'incoming') {
      throw new Error(`RtcCall.answer: not an incoming call in 'incoming' state (state=${this.state})`);
    }
    const description = descriptionFromSdp(local.sdp);
    const xml = encodeJingleStanza({
      from: this.selfJid,
      to: this.peerCertId,
      id: this.nextId(),
      jingle: {
        action: 'session-accept',
        sid: this.sid,
        initiator: this.peerCertId,
        responder: this.selfJid,
        description,
      },
    });
    await this.channel.sendTo(this.peerCertId, xml);
    this.setState('active');
  }

  /** Trickle one local ICE candidate to the peer (transport-info). */
  async addCandidate(candidate: IceCandidate): Promise<void> {
    if (this.state === 'terminated') {
      throw new Error('RtcCall.addCandidate: call is terminated');
    }
    const xml = encodeJingleStanza({
      from: this.selfJid,
      to: this.peerCertId,
      id: this.nextId(),
      jingle: { action: 'transport-info', sid: this.sid, initiator: this.selfJid, candidate },
    });
    await this.channel.sendTo(this.peerCertId, xml);
  }

  /** End the call (session-terminate). Idempotent. */
  async hangup(reason = 'success'): Promise<void> {
    if (this.state === 'terminated') return;
    const xml = encodeJingleStanza({
      from: this.selfJid,
      to: this.peerCertId,
      id: this.nextId(),
      jingle: { action: 'session-terminate', sid: this.sid, initiator: this.selfJid, reason },
    });
    this.setState('terminated');
    this.pins.clear(this.sid);
    await this.channel.sendTo(this.peerCertId, xml);
  }

  /**
   * The media admission gate (called by S3 once the real DTLS handshake yields
   * a fingerprint). True iff the observed fingerprint matches the pinned one.
   */
  verifyDtlsFingerprint(observed: DtlsFingerprint): boolean {
    return this.pins.verify(this.sid, observed);
  }

  /**
   * The remote peer's DTLS fingerprint pinned from their signed offer/answer
   * (the value the media endpoint must present). Undefined until the pin lands
   * (caller: after the answer; callee: on the incoming offer).
   */
  pinnedRemoteFingerprint(): DtlsFingerprint | undefined {
    return this.pins.get(this.sid)?.fingerprint;
  }

  onAnswer(l: Listener<JingleDescription>): () => void {
    return this.onAnswerE.add(l);
  }
  onRemoteCandidate(l: Listener<IceCandidate>): () => void {
    return this.onRemoteCandidateE.add(l);
  }
  onTerminate(l: Listener<string>): () => void {
    return this.onTerminateE.add(l);
  }
  onStateChange(l: Listener<CallState>): () => void {
    return this.onStateE.add(l);
  }
}

// ── the plane ──────────────────────────────────────────────────────────

export interface RtcSignalPlaneConfig {
  channel: RtcSignalChannel;
  /** This node's full JID (informational `from`/`initiator`). */
  selfJid: string;
  /** Shared pin store (S3 reads the same instance). Default: a fresh one. */
  pinStore?: FingerprintPinStore;
  /** Session-id generator (injectable for deterministic tests). */
  genSid?: () => string;
}

export class RtcSignalPlane {
  readonly pins: FingerprintPinStore;
  private readonly calls = new Map<string, RtcCall>();
  private readonly onIncomingE = emitterSet<RtcCall>();
  private readonly genSid: () => string;
  private readonly off: () => void;

  constructor(private readonly cfg: RtcSignalPlaneConfig) {
    this.pins = cfg.pinStore ?? new FingerprintPinStore();
    this.genSid = cfg.genSid ?? (() => globalThis.crypto.randomUUID());
    this.off = cfg.channel.onInbound((msg) => this.handleInbound(msg));
  }

  /** Caller: place a 1:1 call with the local SDP offer. */
  async placeCall(peerCertId: string, local: { sdp: string }): Promise<RtcCall> {
    const sid = this.genSid();
    const description = descriptionFromSdp(local.sdp);
    const call = new RtcCall(
      sid,
      'caller',
      peerCertId,
      this.cfg.selfJid,
      this.cfg.channel,
      this.pins,
      'offering',
    );
    this.calls.set(sid, call);
    const xml = encodeJingleStanza({
      from: this.cfg.selfJid,
      to: peerCertId,
      id: `${sid}-0`,
      jingle: { action: 'session-initiate', sid, initiator: this.cfg.selfJid, description },
    });
    await this.cfg.channel.sendTo(peerCertId, xml);
    return call;
  }

  /** Subscribe to inbound calls (callee side). */
  onIncomingCall(handler: (call: RtcCall) => void): () => void {
    return this.onIncomingE.add(handler);
  }

  /** Look up a tracked call. */
  getCall(sid: string): RtcCall | undefined {
    return this.calls.get(sid);
  }

  /** Detach from the carrier. */
  close(): void {
    this.off();
    this.onIncomingE.clear();
    this.calls.clear();
  }

  private handleInbound(msg: InboundSignal): void {
    let decoded;
    try {
      decoded = decodeJingleStanza(msg.jingleXml);
    } catch {
      return; // not a Jingle stanza — ignore
    }
    const { jingle } = decoded;
    const existing = this.calls.get(jingle.sid);

    switch (jingle.action) {
      case 'session-initiate': {
        if (existing) return; // replay / duplicate sid — ignore
        if (!jingle.description) return;
        const call = new RtcCall(
          jingle.sid,
          'callee',
          msg.fromCertId,
          this.cfg.selfJid,
          this.cfg.channel,
          this.pins,
          'incoming',
        );
        call.remoteDescription = jingle.description;
        // Pin the initiator's committed fingerprint immediately — it arrived
        // inside their signed offer.
        this.pins.pin(jingle.sid, msg.fromCertId, jingle.description.fingerprint);
        this.calls.set(jingle.sid, call);
        this.onIncomingE.fire(call);
        return;
      }
      case 'session-accept': {
        if (!existing || !jingle.description) return;
        existing._acceptedBy(msg.fromCertId, jingle.description);
        return;
      }
      case 'transport-info': {
        if (!existing || !jingle.candidate) return;
        if (msg.fromCertId !== existing.peerCertId) return;
        existing._remoteCandidate(jingle.candidate);
        return;
      }
      case 'session-terminate': {
        if (!existing) return;
        if (msg.fromCertId !== existing.peerCertId) return;
        existing._terminated(jingle.reason ?? 'success');
        return;
      }
    }
  }
}

```
