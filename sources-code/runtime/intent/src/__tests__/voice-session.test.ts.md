---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/voice-session.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.354970+00:00
---

# runtime/intent/src/__tests__/voice-session.test.ts

```ts
/**
 * D-A7 voice-session stub — unit tests.
 *
 * Acceptance gates from the wave-1.5 commission §7.3 D-A7 row:
 *   - Voice-session producer rejects sessions without a cert.
 *   - Transcripts carry the speaker's cert_id.
 *   - Bad cert / bad signature → rejected.
 *   - Two transcripts in the same session share a deterministic
 *     session-bound identifier derived from the cert + session start
 *     time.
 *   - Minimum 6 unit tests.
 */

import { describe, expect, test } from 'bun:test';

import {
  addTranscript,
  canonicalTranscriptPreimage,
  createVoiceSession,
  deriveTranscriptId,
  deriveVoiceSessionId,
  hexToBytes,
  MissingCertError,
  transcriptBelongsToSession,
  verifyTranscript,
  VoiceContractError,
  voiceSessionPreimage,
  type Transcript,
  type VoiceIdentityProvider,
  type VoiceSignature,
} from '../voice';

// ── Test fixtures ────────────────────────────────────────────

const FIXED_CERT_ID =
  'a'.repeat(64); // valid 32-byte hex
const FIXED_SUBJECT_PUBKEY =
  '02' + 'b'.repeat(64); // 33-byte compressed key, 66 hex chars
const FIXED_STARTED_AT = 1_700_000_000_000;

function makeProvider(over: {
  cert?: { certId: string; subjectPublicKey: string } | null;
  sign?: VoiceIdentityProvider['sign'];
} = {}): VoiceIdentityProvider {
  const cert =
    over.cert === undefined
      ? { certId: FIXED_CERT_ID, subjectPublicKey: FIXED_SUBJECT_PUBKEY }
      : over.cert;
  return {
    currentCert: () => cert,
    sign:
      over.sign ??
      ((preimage: Uint8Array): VoiceSignature => ({
        bytes: new Uint8Array([1, 2, 3, ...preimage.slice(0, 4)]),
        algorithm: 'ecdsa-secp256k1',
        keyId: cert?.certId ?? '',
      })),
  };
}

const acceptingVerifier = () => true;
const rejectingVerifier = () => false;

// ── Tests ────────────────────────────────────────────────────

describe('createVoiceSession', () => {
  test('rejects when identity provider has no bound cert (acceptance: cert required)', () => {
    const provider = makeProvider({ cert: null });
    expect(() => createVoiceSession(provider)).toThrow(MissingCertError);
  });

  test('rejects when provider returns malformed cert (missing certId)', () => {
    const provider = makeProvider({
      cert: { certId: '', subjectPublicKey: FIXED_SUBJECT_PUBKEY },
    });
    expect(() => createVoiceSession(provider)).toThrow(VoiceContractError);
  });

  test('builds a session bound to the speaker cert_id, with deterministic id from (cert_id, startedAt)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, {
      now: () => FIXED_STARTED_AT,
      deviceId: 'mic-01',
    });

    expect(session.certId).toBe(FIXED_CERT_ID);
    expect(session.subjectPublicKey).toBe(FIXED_SUBJECT_PUBKEY);
    expect(session.startedAt).toBe(FIXED_STARTED_AT);
    expect(session.deviceId).toBe('mic-01');
    expect(session.id).toBe(deriveVoiceSessionId(FIXED_CERT_ID, FIXED_STARTED_AT));

    // 64 lowercase hex chars (SHA-256 output).
    expect(session.id).toMatch(/^[0-9a-f]{64}$/);

    // Two calls with the same (cert_id, startedAt) produce the same id.
    const again = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    expect(again.id).toBe(session.id);

    // Different startedAt → different id.
    const later = createVoiceSession(provider, { now: () => FIXED_STARTED_AT + 1 });
    expect(later.id).not.toBe(session.id);
  });
});

describe('addTranscript', () => {
  test('produced transcript carries the speaker cert_id (acceptance: speaker binding)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });

    const tx = addTranscript(session, 'hello world', provider, {
      now: () => FIXED_STARTED_AT + 100,
      sequence: 0,
    });

    expect(tx.certId).toBe(FIXED_CERT_ID);
    expect(tx.signature.keyId).toBe(FIXED_CERT_ID);
    expect(tx.sessionId).toBe(session.id);
    expect(tx.text).toBe('hello world');
    expect(tx.timestamp).toBe(FIXED_STARTED_AT + 100);
    expect(tx.id).toBe(deriveTranscriptId(session.id, 0));
  });

  test('two transcripts in the same session share the session-bound deterministic id (acceptance: deterministic session id)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });

    const a = addTranscript(session, 'first', provider, {
      now: () => FIXED_STARTED_AT + 100,
      sequence: 0,
    });
    const b = addTranscript(session, 'second', provider, {
      now: () => FIXED_STARTED_AT + 250,
      sequence: 1,
    });

    // Both share the parent session id (the deterministic value).
    expect(a.sessionId).toBe(session.id);
    expect(b.sessionId).toBe(session.id);
    expect(a.sessionId).toBe(b.sessionId);
    // And both share the cert_id.
    expect(a.certId).toBe(b.certId);
    // Per-transcript ids differ because sequence differs.
    expect(a.id).not.toBe(b.id);
  });

  test('rejects when signer returns a keyId that disagrees with session.certId (acceptance: bad cert binding rejected)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });

    const evilSigner: Pick<VoiceIdentityProvider, 'sign'> = {
      sign: () => ({
        bytes: new Uint8Array([9, 9, 9]),
        algorithm: 'ecdsa-secp256k1',
        keyId: 'f'.repeat(64), // different cert_id
      }),
    };

    expect(() => addTranscript(session, 'spoof', evilSigner)).toThrow(VoiceContractError);
  });
});

describe('verifyTranscript', () => {
  test('returns true for a well-formed transcript with an accepting verifier', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const tx = addTranscript(session, 'ok', provider, { sequence: 0 });

    expect(verifyTranscript(tx, acceptingVerifier)).toBe(true);
  });

  test('returns false when the verifier rejects the signature (acceptance: bad signature rejected)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const tx = addTranscript(session, 'tampered', provider, { sequence: 0 });

    expect(verifyTranscript(tx, rejectingVerifier)).toBe(false);
  });

  test('returns false when transcript.signature.keyId does not match transcript.certId (acceptance: cert binding check)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const good = addTranscript(session, 'hi', provider, { sequence: 0 });

    // Forge a transcript with mismatched keyId — bypass addTranscript's
    // contract guard by hand-rolling the value (emulates a malicious
    // peer over the wire).
    const forged: Transcript = {
      ...good,
      signature: { ...good.signature, keyId: '0'.repeat(64) },
    };

    // Even with an "accepting" verifier, the structural check fails first.
    expect(verifyTranscript(forged, acceptingVerifier)).toBe(false);
  });

  test('returns false when the verifier throws (defensive)', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const tx = addTranscript(session, 'hi', provider, { sequence: 0 });

    const throwingVerifier = () => {
      throw new Error('verifier exploded');
    };
    expect(verifyTranscript(tx, throwingVerifier)).toBe(false);
  });
});

describe('canonical preimages', () => {
  test('voiceSessionPreimage encodes cert_id_bytes(32) ‖ started_at_be_u64(8) = 40 bytes', () => {
    const preimage = voiceSessionPreimage(FIXED_CERT_ID, FIXED_STARTED_AT);
    expect(preimage.length).toBe(40);
    // First 32 bytes match the cert_id bytes.
    const certBytes = hexToBytes(FIXED_CERT_ID);
    for (let i = 0; i < 32; i++) {
      expect(preimage[i]).toBe(certBytes[i]!);
    }
    // Last 8 bytes are big-endian started_at.
    let recovered = 0;
    for (let i = 32; i < 40; i++) {
      recovered = recovered * 256 + preimage[i]!;
    }
    expect(recovered).toBe(FIXED_STARTED_AT);
  });

  test('canonicalTranscriptPreimage is deterministic across key-insertion orders', () => {
    const a = canonicalTranscriptPreimage({
      certId: FIXED_CERT_ID,
      sequence: 7,
      sessionId: 'aabb' as never,
      text: 'hello',
      timestamp: 42,
    });
    // Same fields, different argument-construction order.
    const fields = {
      timestamp: 42,
      text: 'hello',
      sessionId: 'aabb' as never,
      sequence: 7,
      certId: FIXED_CERT_ID,
    };
    const b = canonicalTranscriptPreimage(fields);
    expect(Buffer.from(a).toString('hex')).toBe(Buffer.from(b).toString('hex'));
  });

  test('hexToBytes rejects malformed input', () => {
    expect(() => hexToBytes('xyz')).toThrow();
    expect(() => hexToBytes('a')).toThrow(); // odd length
    expect(() => hexToBytes('')).toThrow();
  });
});

describe('transcriptBelongsToSession', () => {
  test('matches a freshly produced transcript', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const tx = addTranscript(session, 'hi', provider, { sequence: 0 });

    expect(transcriptBelongsToSession(tx, session)).toBe(true);
  });

  test('refuses a transcript whose sessionId does not match a recomputed value', () => {
    const provider = makeProvider();
    const session = createVoiceSession(provider, { now: () => FIXED_STARTED_AT });
    const tx = addTranscript(session, 'hi', provider, { sequence: 0 });

    // Lie about startedAt — the recomputed id differs.
    expect(
      transcriptBelongsToSession(tx, { ...session, startedAt: FIXED_STARTED_AT + 1 }),
    ).toBe(false);
  });
});

```
