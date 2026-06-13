---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/jingle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.039836+00:00
---

# runtime/session-protocol/src/rtc/jingle.ts

```ts
/**
 * Jingle stanza codec — S1 signalling vocabulary (RTC matrix row S1, axis B).
 *
 * Jingle (XEP-0166 session / -0167 RTP / -0176 ICE-UDP / -0320 DTLS-SRTP) is
 * the standardised mapping of WebRTC call setup onto XMPP stanzas. This module
 * is the codec half of S1: it turns the four call-setup actions into XML and
 * back, with the load-bearing security field — the DTLS `a=fingerprint` — and
 * the ICE coordinates (`ufrag`/`pwd`/candidates) hoisted into first-class
 * Jingle elements so they are inspectable at the signalling layer, not buried
 * in an opaque blob.
 *
 *   session-initiate   SDP offer  + fingerprint + ufrag/pwd + initial candidates
 *   session-accept     SDP answer + fingerprint + ufrag/pwd + initial candidates
 *   transport-info     one trickled ICE candidate
 *   session-terminate  a reason
 *
 * The full SDP rides as a base64 `<sdp>` child so a real RTCPeerConnection in
 * S3 (rtc.media) can feed it to setLocal/RemoteDescription verbatim. The
 * per-line SDP↔Jingle `<description>` transcoding (codecs, payload-types,
 * rtcp-fb) is deliberately NOT done here — it is a media-layer concern that
 * wants a real PeerConnection to validate against. S1 owns setup + the
 * fingerprint commitment; S3 owns the media description.
 *
 * Parsing is regex-based to match the house style of the sibling XMPP codec
 * (`core/protocol-types/src/xmpp/bundle-stanza.ts`,
 * `xmpp-network-adapter.ts`) — these stanzas are machine-generated, so a full
 * XML DOM is unnecessary overhead.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §3 (the signalling mapping),
 * docs/canon/rtc-matrix.yml row S1.
 */

const JINGLE_NS = 'urn:xmpp:jingle:1';
const RTP_NS = 'urn:xmpp:jingle:apps:rtp:1';
const ICEUDP_NS = 'urn:xmpp:jingle:transports:ice-udp:1';
const DTLS_NS = 'urn:xmpp:jingle:apps:dtls:0';
/** semantos extension: the opaque negotiated SDP, for S3's PeerConnection. */
const SDP_NS = 'urn:semantos:rtc:sdp:1';

export type JingleAction =
  | 'session-initiate'
  | 'session-accept'
  | 'transport-info'
  | 'session-terminate';

export type MediaKind = 'audio' | 'video';

/** A DTLS-SRTP fingerprint — the value axis A pins into the SignedBundle. */
export interface DtlsFingerprint {
  /** Hash algorithm, e.g. `sha-256`. */
  hash: string;
  /** DTLS role: `actpass` | `active` | `passive`. */
  setup: string;
  /** Colon-separated uppercase hex (the `a=fingerprint` value). */
  value: string;
}

/** One ICE candidate — the raw attribute value of an SDP `a=candidate:` line. */
export interface IceCandidate {
  /** Everything after `candidate:` in the SDP line. */
  candidate: string;
  /** Media id this candidate belongs to (mline grouping). */
  sdpMid?: string;
  sdpMLineIndex?: number;
}

/** The offer/answer payload of an initiate / accept action. */
export interface JingleDescription {
  /** Opaque SDP (offer or answer) from the RTCPeerConnection. */
  sdp: string;
  /** Convenience: which media kinds the SDP advertises (its m-lines). */
  media: MediaKind[];
  ufrag?: string;
  pwd?: string;
  /** Load-bearing — the value the receiver pins (RTC axis A). */
  fingerprint: DtlsFingerprint;
  /** Candidates bundled into the initiate/accept (pre-trickle). */
  candidates: IceCandidate[];
}

export interface JingleStanza {
  action: JingleAction;
  /** Session id — stable across all stanzas of one call. */
  sid: string;
  /** Full JID of the call initiator. */
  initiator: string;
  /** Full JID of the responder (set on accept). */
  responder?: string;
  /** Present on session-initiate / session-accept. */
  description?: JingleDescription;
  /** Present on transport-info. */
  candidate?: IceCandidate;
  /** Present on session-terminate. */
  reason?: string;
}

// ── SDP introspection ──────────────────────────────────────────────────
// Pull the ICE + DTLS coordinates out of an SDP so they can be hoisted into
// proper Jingle elements (and so the fingerprint pin is the SAME value the
// real DTLS handshake later presents — there is one source of truth).

function firstMatch(re: RegExp, sdp: string): string | undefined {
  const m = re.exec(sdp);
  return m ? m[1] : undefined;
}

/** Extract the DTLS fingerprint (+ setup role) from an SDP. Throws if absent. */
export function fingerprintFromSdp(sdp: string): DtlsFingerprint {
  const fp = /^a=fingerprint:(\S+)\s+(\S+)/m.exec(sdp);
  if (!fp) {
    throw new Error('fingerprintFromSdp: SDP has no a=fingerprint line');
  }
  const setup = firstMatch(/^a=setup:(\S+)/m, sdp) ?? 'actpass';
  return { hash: fp[1]!.toLowerCase(), setup, value: fp[2]!.toUpperCase() };
}

/** Build a JingleDescription from an SDP offer/answer string. */
export function descriptionFromSdp(sdp: string): JingleDescription {
  const media = [...sdp.matchAll(/^m=(audio|video)\b/gm)].map((m) => m[1] as MediaKind);
  const candidates: IceCandidate[] = [...sdp.matchAll(/^a=candidate:(.+?)\s*$/gm)].map((m) => ({
    candidate: m[1]!,
  }));
  const desc: JingleDescription = {
    sdp,
    media,
    fingerprint: fingerprintFromSdp(sdp),
    candidates,
  };
  const ufrag = firstMatch(/^a=ice-ufrag:(\S+)/m, sdp);
  const pwd = firstMatch(/^a=ice-pwd:(\S+)/m, sdp);
  if (ufrag) desc.ufrag = ufrag;
  if (pwd) desc.pwd = pwd;
  return desc;
}

// ── XML helpers (mirrors bundle-stanza.ts) ─────────────────────────────

function esc(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
function unesc(s: string): string {
  return s
    .replace(/&quot;/g, '"')
    .replace(/&gt;/g, '>')
    .replace(/&lt;/g, '<')
    .replace(/&amp;/g, '&');
}
function b64(s: string): string {
  return Buffer.from(s, 'utf8').toString('base64');
}
function unb64(s: string): string {
  return Buffer.from(s, 'base64').toString('utf8');
}
const attrOf = (name: string, s: string): string | undefined => {
  const m = new RegExp(`\\b${name}="([^"]*)"`).exec(s);
  return m ? unesc(m[1]!) : undefined;
};

function describeXml(d: JingleDescription): string {
  const parts: string[] = [];
  for (const m of d.media) {
    parts.push(`<description xmlns="${RTP_NS}" media="${m}"/>`);
  }
  const transportAttrs = [`xmlns="${ICEUDP_NS}"`];
  if (d.ufrag) transportAttrs.push(`ufrag="${esc(d.ufrag)}"`);
  if (d.pwd) transportAttrs.push(`pwd="${esc(d.pwd)}"`);
  const transportChildren: string[] = [
    `<fingerprint xmlns="${DTLS_NS}" hash="${esc(d.fingerprint.hash)}" setup="${esc(
      d.fingerprint.setup,
    )}">${esc(d.fingerprint.value)}</fingerprint>`,
  ];
  for (const c of d.candidates) transportChildren.push(candidateXml(c));
  parts.push(`<transport ${transportAttrs.join(' ')}>${transportChildren.join('')}</transport>`);
  parts.push(`<sdp xmlns="${SDP_NS}">${b64(d.sdp)}</sdp>`);
  return `<content creator="initiator" name="rtc">${parts.join('')}</content>`;
}

function candidateXml(c: IceCandidate): string {
  const a = [`>${esc(c.candidate)}`];
  const open: string[] = [];
  if (c.sdpMid !== undefined) open.push(`sdpMid="${esc(c.sdpMid)}"`);
  if (c.sdpMLineIndex !== undefined) open.push(`sdpMLineIndex="${c.sdpMLineIndex}"`);
  return `<candidate ${open.join(' ')}${a.join('')}</candidate>`;
}

// ── encode ─────────────────────────────────────────────────────────────

export interface EncodeArgs {
  from: string;
  to: string;
  /** IQ id (correlation handle). */
  id: string;
  jingle: JingleStanza;
}

/** Encode a Jingle action as an `<iq type='set'>` carrying a `<jingle>`. */
export function encodeJingleStanza(args: EncodeArgs): string {
  const { from, to, id, jingle } = args;
  const jAttrs = [
    `xmlns="${JINGLE_NS}"`,
    `action="${jingle.action}"`,
    `initiator="${esc(jingle.initiator)}"`,
    `sid="${esc(jingle.sid)}"`,
  ];
  if (jingle.responder) jAttrs.push(`responder="${esc(jingle.responder)}"`);

  const children: string[] = [];
  if (jingle.description) children.push(describeXml(jingle.description));
  if (jingle.candidate) {
    children.push(
      `<content creator="initiator" name="rtc"><transport xmlns="${ICEUDP_NS}">${candidateXml(
        jingle.candidate,
      )}</transport></content>`,
    );
  }
  if (jingle.reason) {
    children.push(`<reason><${esc(jingle.reason)}/></reason>`);
  }

  return (
    `<iq from="${esc(from)}" to="${esc(to)}" type="set" id="${esc(id)}">` +
    `<jingle ${jAttrs.join(' ')}>${children.join('')}</jingle></iq>`
  );
}

// ── decode ─────────────────────────────────────────────────────────────

export interface DecodedJingle {
  from: string;
  to: string;
  id: string;
  jingle: JingleStanza;
}

function decodeCandidate(xml: string): IceCandidate | undefined {
  const m = /<candidate\b([^>]*)>([\s\S]*?)<\/candidate>/.exec(xml);
  if (!m) return undefined;
  const head = m[1]!;
  const cand: IceCandidate = { candidate: unesc(m[2]!.trim()) };
  const mid = attrOf('sdpMid', head);
  const idx = attrOf('sdpMLineIndex', head);
  if (mid !== undefined) cand.sdpMid = mid;
  if (idx !== undefined) cand.sdpMLineIndex = Number(idx);
  return cand;
}

function decodeDescription(jingleInner: string): JingleDescription | undefined {
  const sdpM = new RegExp(`<sdp xmlns="${SDP_NS}">([\\s\\S]*?)</sdp>`).exec(jingleInner);
  const fpM = /<fingerprint\b([^>]*)>([\s\S]*?)<\/fingerprint>/.exec(jingleInner);
  if (!sdpM || !fpM) return undefined;
  const sdp = unb64(sdpM[1]!.trim());
  // Re-derive everything from the authoritative SDP, then trust the hoisted
  // fingerprint element as the value the sender COMMITTED to (it must match).
  const desc = descriptionFromSdp(sdp);
  const fpHead = fpM[1]!;
  desc.fingerprint = {
    hash: (attrOf('hash', fpHead) ?? desc.fingerprint.hash).toLowerCase(),
    setup: attrOf('setup', fpHead) ?? desc.fingerprint.setup,
    value: unesc(fpM[2]!.trim()).toUpperCase(),
  };
  return desc;
}

/** Decode an `<iq>`-wrapped Jingle stanza. Throws if it is not one. */
export function decodeJingleStanza(xml: string): DecodedJingle {
  const jM = /<jingle\b([^>]*)>([\s\S]*?)<\/jingle>/.exec(xml);
  if (!jM) throw new Error('decodeJingleStanza: no <jingle> element');
  const head = jM[1]!;
  const inner = jM[2]!;

  const action = attrOf('action', head) as JingleAction | undefined;
  const sid = attrOf('sid', head);
  const initiator = attrOf('initiator', head);
  if (!action || !sid || !initiator) {
    throw new Error('decodeJingleStanza: missing action/sid/initiator');
  }

  const jingle: JingleStanza = { action, sid, initiator };
  const responder = attrOf('responder', head);
  if (responder) jingle.responder = responder;

  if (action === 'session-initiate' || action === 'session-accept') {
    const desc = decodeDescription(inner);
    if (!desc) throw new Error(`decodeJingleStanza: ${action} without a description`);
    jingle.description = desc;
  } else if (action === 'transport-info') {
    const cand = decodeCandidate(inner);
    if (!cand) throw new Error('decodeJingleStanza: transport-info without a candidate');
    jingle.candidate = cand;
  } else if (action === 'session-terminate') {
    const r = /<reason><([a-zA-Z0-9-]+)\s*\/>/.exec(inner);
    jingle.reason = r ? r[1]! : 'success';
  }

  return {
    from: attrOf('from', xml) ?? '',
    to: attrOf('to', xml) ?? '',
    id: attrOf('id', xml) ?? '',
    jingle,
  };
}

```
