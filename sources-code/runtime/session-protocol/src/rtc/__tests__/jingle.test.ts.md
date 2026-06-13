---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/jingle.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.059020+00:00
---

# runtime/session-protocol/src/rtc/__tests__/jingle.test.ts

```ts
/**
 * Jingle codec tests — encode/decode round-trips for the four call-setup
 * actions, plus SDP introspection (fingerprint / ufrag / candidates).
 */

import { describe, it, expect } from '@jest/globals';
import {
  decodeJingleStanza,
  descriptionFromSdp,
  encodeJingleStanza,
  fingerprintFromSdp,
  type JingleStanza,
} from '../jingle';

const FP = 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

function sdp(opts: { ufrag?: string; media?: 'audio' | 'video'; fp?: string } = {}): string {
  const { ufrag = 'ufragA', media = 'audio', fp = FP } = opts;
  return [
    'v=0',
    'o=- 4611731400430051336 2 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    `m=${media} 9 UDP/TLS/RTP/SAVPF 111`,
    `a=ice-ufrag:${ufrag}`,
    `a=ice-pwd:pwd-${ufrag}`,
    `a=fingerprint:sha-256 ${fp}`,
    'a=setup:actpass',
    'a=candidate:1 1 UDP 2122252543 192.0.2.1 54321 typ host',
  ].join('\r\n');
}

const FROM = 'aaaa@[2602:f9f8::1]/x';
const TO = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

describe('SDP introspection', () => {
  it('extracts the DTLS fingerprint (hash lowercased, value uppercased)', () => {
    const fp = fingerprintFromSdp(sdp());
    expect(fp.hash).toBe('sha-256');
    expect(fp.value).toBe(FP);
    expect(fp.setup).toBe('actpass');
  });

  it('throws when the SDP has no fingerprint', () => {
    expect(() => fingerprintFromSdp('v=0\r\nm=audio 9 UDP 111')).toThrow(/no a=fingerprint/);
  });

  it('derives media kinds, ufrag/pwd, and bundled candidates', () => {
    const d = descriptionFromSdp(sdp({ media: 'video', ufrag: 'zzz' }));
    expect(d.media).toEqual(['video']);
    expect(d.ufrag).toBe('zzz');
    expect(d.pwd).toBe('pwd-zzz');
    expect(d.candidates).toHaveLength(1);
    expect(d.candidates[0]!.candidate).toContain('typ host');
  });
});

describe('Jingle encode/decode round-trip', () => {
  it('session-initiate carries the description + hoists the fingerprint', () => {
    const description = descriptionFromSdp(sdp());
    const xml = encodeJingleStanza({
      from: FROM,
      to: TO,
      id: 'sid-0',
      jingle: { action: 'session-initiate', sid: 'sid', initiator: FROM, description },
    });
    // The fingerprint is a first-class element, not buried in base64.
    expect(xml).toContain('<fingerprint');
    expect(xml).toContain(FP);

    const back = decodeJingleStanza(xml);
    expect(back.from).toBe(FROM);
    expect(back.to).toBe(TO);
    expect(back.jingle.action).toBe('session-initiate');
    expect(back.jingle.sid).toBe('sid');
    expect(back.jingle.initiator).toBe(FROM);
    expect(back.jingle.description!.sdp).toBe(description.sdp);
    expect(back.jingle.description!.fingerprint.value).toBe(FP);
    expect(back.jingle.description!.media).toEqual(['audio']);
  });

  it('session-accept preserves the responder + answer SDP', () => {
    const description = descriptionFromSdp(sdp({ ufrag: 'ufragB' }));
    const j: JingleStanza = {
      action: 'session-accept',
      sid: 'sid',
      initiator: FROM,
      responder: TO,
      description,
    };
    const back = decodeJingleStanza(encodeJingleStanza({ from: TO, to: FROM, id: 'sid-1', jingle: j }));
    expect(back.jingle.action).toBe('session-accept');
    expect(back.jingle.responder).toBe(TO);
    expect(back.jingle.description!.ufrag).toBe('ufragB');
  });

  it('transport-info carries one trickled candidate', () => {
    const candidate = { candidate: '2 1 UDP 1686052607 198.51.100.7 60000 typ srflx', sdpMid: '0', sdpMLineIndex: 0 };
    const back = decodeJingleStanza(
      encodeJingleStanza({
        from: FROM,
        to: TO,
        id: 'sid-2',
        jingle: { action: 'transport-info', sid: 'sid', initiator: FROM, candidate },
      }),
    );
    expect(back.jingle.action).toBe('transport-info');
    expect(back.jingle.candidate!.candidate).toBe(candidate.candidate);
    expect(back.jingle.candidate!.sdpMid).toBe('0');
    expect(back.jingle.candidate!.sdpMLineIndex).toBe(0);
  });

  it('session-terminate carries a reason', () => {
    const back = decodeJingleStanza(
      encodeJingleStanza({
        from: FROM,
        to: TO,
        id: 'sid-3',
        jingle: { action: 'session-terminate', sid: 'sid', initiator: FROM, reason: 'busy' },
      }),
    );
    expect(back.jingle.action).toBe('session-terminate');
    expect(back.jingle.reason).toBe('busy');
  });

  it('rejects a stanza with no <jingle> element', () => {
    expect(() => decodeJingleStanza('<iq><query/></iq>')).toThrow(/no <jingle>/);
  });
});

```
