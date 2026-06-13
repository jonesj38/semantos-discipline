---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/signal.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.062181+00:00
---

# runtime/session-protocol/src/rtc/__tests__/signal.test.ts

```ts
/**
 * S1 signalling end-to-end — two RtcSignalPlanes over an in-memory channel bus
 * (the StubXmppTransport analogue for the Jingle layer). Exercises the full
 * 1:1 offer/answer/trickle/hangup round-trip and the fingerprint pin on both
 * sides.
 */

import { describe, it, expect } from '@jest/globals';
import { RtcSignalPlane, type InboundSignal, type RtcSignalChannel, type RtcCall } from '../signal';

const CERT_A = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const CERT_B = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const CERT_C = 'cccccccccccccccccccccccccccccccc';
const FP_A = 'AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA';
const FP_B = 'BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB:BB';

/** In-memory signalling fabric: routes by cert id, tags the verified sender. */
class MemSignalBus {
  private readonly inbound = new Map<string, (m: InboundSignal) => void>();
  channelFor(certId: string): RtcSignalChannel {
    return {
      sendTo: async (peerCertId, jingleXml) => {
        const h = this.inbound.get(peerCertId);
        if (h) h({ fromCertId: certId, jingleXml });
      },
      onInbound: (handler) => {
        this.inbound.set(certId, handler);
        return () => {
          if (this.inbound.get(certId) === handler) this.inbound.delete(certId);
        };
      },
    };
  }
}

function sdp(opts: { ufrag: string; fp: string }): string {
  return [
    'v=0',
    'o=- 0 0 IN IP4 127.0.0.1',
    's=-',
    't=0 0',
    'm=audio 9 UDP/TLS/RTP/SAVPF 111',
    `a=ice-ufrag:${opts.ufrag}`,
    `a=ice-pwd:pwd-${opts.ufrag}`,
    `a=fingerprint:sha-256 ${opts.fp}`,
    'a=setup:actpass',
  ].join('\r\n');
}

const offer = sdp({ ufrag: 'A', fp: FP_A });
const answer = sdp({ ufrag: 'B', fp: FP_B });

function makePair() {
  const bus = new MemSignalBus();
  let n = 0;
  const genSid = () => `sid-${++n}`;
  const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'alice@[::1]/x', genSid });
  const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'bob@[::2]/x', genSid });
  return { alice, bob };
}

describe('1:1 call — offer/answer/trickle', () => {
  it('completes the handshake and pins each peer fingerprint on the opposite side', async () => {
    const { alice, bob } = makePair();
    let incoming: RtcCall | undefined;
    bob.onIncomingCall((c) => {
      incoming = c;
    });

    const aliceCall = await alice.placeCall(CERT_B, { sdp: offer });
    expect(aliceCall.role).toBe('caller');
    expect(aliceCall.state).toBe('offering');

    // Bob received the initiate and immediately pinned Alice's fingerprint.
    expect(incoming).toBeDefined();
    expect(incoming!.peerCertId).toBe(CERT_A);
    expect(incoming!.state).toBe('incoming');
    expect(incoming!.remoteDescription!.fingerprint.value).toBe(FP_A);
    expect(bob.pins.get(incoming!.sid)!.fingerprint.value).toBe(FP_A);

    // Bob answers → Alice goes active and pins Bob's fingerprint.
    let answeredWith: string | undefined;
    aliceCall.onAnswer((d) => {
      answeredWith = d.fingerprint.value;
    });
    await incoming!.answer({ sdp: answer });

    expect(incoming!.state).toBe('active');
    expect(aliceCall.state).toBe('active');
    expect(answeredWith).toBe(FP_B);
    expect(alice.pins.get(aliceCall.sid)!.fingerprint.value).toBe(FP_B);

    // The media admission gate: each side accepts the peer's real FP, rejects others.
    expect(aliceCall.verifyDtlsFingerprint({ hash: 'sha-256', setup: 'active', value: FP_B })).toBe(true);
    expect(aliceCall.verifyDtlsFingerprint({ hash: 'sha-256', setup: 'active', value: FP_A })).toBe(false);
    expect(incoming!.verifyDtlsFingerprint({ hash: 'sha-256', setup: 'passive', value: FP_A })).toBe(true);
  });

  it('trickles candidates both ways once active', async () => {
    const { alice, bob } = makePair();
    let incoming: RtcCall | undefined;
    bob.onIncomingCall((c) => (incoming = c));
    const aliceCall = await alice.placeCall(CERT_B, { sdp: offer });
    await incoming!.answer({ sdp: answer });

    const bobGot: string[] = [];
    const aliceGot: string[] = [];
    incoming!.onRemoteCandidate((c) => bobGot.push(c.candidate));
    aliceCall.onRemoteCandidate((c) => aliceGot.push(c.candidate));

    await aliceCall.addCandidate({ candidate: 'cand-from-alice typ host' });
    await incoming!.addCandidate({ candidate: 'cand-from-bob typ srflx' });

    expect(bobGot).toEqual(['cand-from-alice typ host']);
    expect(aliceGot).toEqual(['cand-from-bob typ srflx']);
  });

  it('hangup terminates both ends and clears the pin', async () => {
    const { alice, bob } = makePair();
    let incoming: RtcCall | undefined;
    bob.onIncomingCall((c) => (incoming = c));
    const aliceCall = await alice.placeCall(CERT_B, { sdp: offer });
    await incoming!.answer({ sdp: answer });

    let bobReason: string | undefined;
    incoming!.onTerminate((r) => (bobReason = r));
    await aliceCall.hangup('success');

    expect(aliceCall.state).toBe('terminated');
    expect(incoming!.state).toBe('terminated');
    expect(bobReason).toBe('success');
    expect(alice.pins.get(aliceCall.sid)).toBeUndefined();
  });
});

describe('S1 trust boundaries', () => {
  it('ignores a session-accept that arrives from a different cert than the callee', async () => {
    const bus = new MemSignalBus();
    const alice = new RtcSignalPlane({ channel: bus.channelFor(CERT_A), selfJid: 'a', genSid: () => 'sid-x' });
    // A forged accept: cert C answers a call Alice placed to cert B.
    const forged: RtcSignalChannel = bus.channelFor(CERT_C);
    const aliceCall = await alice.placeCall(CERT_B, { sdp: offer });

    await forged.sendTo(CERT_A, jingleAccept('sid-x'));
    expect(aliceCall.state).toBe('offering'); // unchanged — forged accept rejected
    expect(alice.pins.get('sid-x')).toBeUndefined();
  });

  it('ignores a duplicate session-initiate for an existing sid (replay)', async () => {
    const bus = new MemSignalBus();
    const fixedSid = () => 'sid-dup';
    const bob = new RtcSignalPlane({ channel: bus.channelFor(CERT_B), selfJid: 'b', genSid: fixedSid });
    const attacker = bus.channelFor(CERT_A);
    let count = 0;
    bob.onIncomingCall(() => count++);

    await attacker.sendTo(CERT_B, jingleInitiate('sid-dup'));
    await attacker.sendTo(CERT_B, jingleInitiate('sid-dup'));
    expect(count).toBe(1);
  });
});

// Hand-rolled stanzas for the trust-boundary cases (bypassing a real plane).
import { encodeJingleStanza, descriptionFromSdp } from '../jingle';
function jingleInitiate(sid: string): string {
  return encodeJingleStanza({
    from: 'x',
    to: CERT_B,
    id: `${sid}-0`,
    jingle: { action: 'session-initiate', sid, initiator: 'x', description: descriptionFromSdp(offer) },
  });
}
function jingleAccept(sid: string): string {
  return encodeJingleStanza({
    from: 'x',
    to: CERT_A,
    id: `${sid}-1`,
    jingle: { action: 'session-accept', sid, initiator: 'x', responder: 'x', description: descriptionFromSdp(answer) },
  });
}

```
