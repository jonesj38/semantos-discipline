---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/__tests__/brain-relay-call.integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.060188+00:00
---

# runtime/session-protocol/src/rtc/__tests__/brain-relay-call.integration.test.ts

```ts
/**
 * LIVE brain-relayed call — two separate clients ring each other THROUGH the
 * brain (RTC matrix A1 + the "D-network-wss-direct" signalling-relay gap).
 *
 * This is the piece the helm Talk was waiting on ("no transport"): the
 * signalling traverses the brain's MessageBox, so the two peers are NOT in one
 * process. Client A places a call addressed by B's cert id; the Jingle (signed)
 * is relayed by the brain; B polls, receives it, answers; a real werift
 * ICE/DTLS connection establishes and audio flows.
 *
 * GATED on `BRAIN_BASE` (+ `BRAIN_BEARER`) — skipped green when no brain is up.
 * To run:
 *   cd runtime/semantos-brain && zig build && ./zig-out/bin/brain serve localhost --port 8080
 *   TOKEN=$(./zig-out/bin/brain bearer issue --label rtc | grep -A0 Token -m1 ...)  # the 64-hex token
 *   BRAIN_BASE='http://[::1]:8080' BRAIN_BEARER="$TOKEN" \
 *     bun test src/rtc/__tests__/brain-relay-call.integration.test.ts
 */
import { describe, expect, test } from 'bun:test';
import { ENVELOPE_VERSION } from '@semantos/protocol-types/xmpp';
import type { BundleSigner } from '../../xmpp-node';
import { BrainRtcSignalChannel } from '../brain-rtc-signal-channel';
import { RtcSignalPlane } from '../signal';
import { placeMediaCall, answerMediaCall, type MediaCall } from '../call';
import { weriftPeerConnectionFactory, weriftMediaSource } from '../werift-peer-connection';

const BRAIN_BASE = process.env.BRAIN_BASE;
const BRAIN_BEARER = process.env.BRAIN_BEARER ?? '';
const d = BRAIN_BASE ? describe : describe.skip;

const CERT_A = 'a'.repeat(32);
const CERT_B = 'b'.repeat(32);
// 66-hex mailboxes (the MessageBox requires length 66 — the contact's pubkey hex).
const MBOX = { [CERT_A]: '02' + 'aa'.repeat(32), [CERT_B]: '02' + 'bb'.repeat(32) } as Record<string, string>;
const mailboxFor = (certId: string) => MBOX[certId]!;

function signerFor(senderCertId: string): BundleSigner {
  return (req) => ({
    v: ENVELOPE_VERSION,
    sender_cert_chain: [{ cert_id: senderCertId, pubkey: '02' + 'cd'.repeat(32), context_tag: 0x10, parent_cert_id: null }],
    recipient_cert_id: req.recipientCertId,
    payload_type: req.payloadType,
    payload: req.payload,
    signature: 'ab'.repeat(64),
    signature_metadata: { algorithm: 'ecdsa-secp256k1-sha256', nonce_hex: 'ef'.repeat(32), timestamp_unix: 1_750_000_000 },
  });
}
function planeFor(certId: string): RtcSignalPlane {
  const channel = new BrainRtcSignalChannel({
    brainBase: BRAIN_BASE!,
    bearer: BRAIN_BEARER,
    selfMailbox: mailboxFor(certId),
    mailboxFor,
    signBundle: signerFor(certId),
    pollMs: 250,
  });
  return new RtcSignalPlane({ channel, selfJid: certId });
}

d('brain-relayed contact call (live MessageBox + real media)', () => {
  test('A rings B through the brain; B answers; ICE/DTLS connects and audio flows', async () => {
    const alice = planeFor(CERT_A);
    const bob = planeFor(CERT_B);

    const bobGotAudio = new Promise<string>((resolve) => {
      bob.onIncomingCall(async (incoming) => {
        expect(incoming.peerCertId).toBe(CERT_A);
        const bobCall = await answerMediaCall(incoming, weriftPeerConnectionFactory, {});
        bobCall.onTrack((track) => {
          let n = 0;
          track.onRtp(() => {
            if (++n === 3) resolve(track.kind);
          });
        });
      });
    });

    const source = weriftMediaSource('audio');
    const aliceCall: MediaCall = await placeMediaCall(alice, weriftPeerConnectionFactory, {}, CERT_B, { tracks: [source.track] });
    aliceCall.onConnected(() => {
      let seq = 0;
      let ts = 0;
      const timer = setInterval(() => source.writeRtp(Buffer.from([1, 2, 3, 4]), seq++, (ts += 160)), 20);
      setTimeout(() => clearInterval(timer), 4000);
    });

    expect(await bobGotAudio).toBe('audio');
    expect(aliceCall.pc.connectionState()).toBe('connected');

    await aliceCall.hangup();
    alice.close();
    bob.close();
  }, 30_000);
});

```
