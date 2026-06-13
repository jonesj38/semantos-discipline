---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/voice/voice-session.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.352745+00:00
---

# runtime/intent/src/voice/voice-session.ts

```ts
/**
 * Voice-session producer (cert-bound) + transcript signing/verification.
 *
 * Three pure functions form the cert-bound contract that future voice
 * transcription work consumes (D-A7 stub):
 *
 *   - `createVoiceSession(provider, opts)` — refuses to construct a
 *     session unless the identity provider has a bound BRC-52 cert.
 *     The returned session id is deterministic in
 *     `(cert_id, started_at)`.
 *
 *   - `addTranscript(session, text, signer, opts)` — produces a signed
 *     transcript whose `keyId` equals the speaker's cert_id and whose
 *     id + sessionId are session-bound deterministic values. Refuses
 *     if the signer's keyId disagrees with the session's certId
 *     (catches misconfigured signers before the artifact reaches the
 *     verifier sidecar).
 *
 *   - `verifyTranscript(transcript, verifier)` — re-runs the signature
 *     check against the canonical preimage. Returns false on bad
 *     cert binding (keyId ≠ certId) or bad signature.
 *
 * Every error is a `MissingCertError` or `VoiceContractError` so
 * callers can distinguish "no cert" from "bad cert binding". Both
 * extend `Error`.
 */

import {
  canonicalTranscriptPreimage,
  deriveTranscriptId,
  deriveVoiceSessionId,
} from './preimage';
import type {
  Transcript,
  TranscriptId,
  VoiceIdentityProvider,
  VoiceSession,
  VoiceSessionId,
  VoiceSignature,
} from './types';

// ── Errors ───────────────────────────────────────────────────

/**
 * Thrown by `createVoiceSession` when the identity provider has no
 * bound cert. Voice channels MUST be cert-bound (per Unification
 * Roadmap §5 D-A7). There is no anonymous-voice fallback.
 */
export class MissingCertError extends Error {
  readonly code = 'VOICE_CERT_REQUIRED';
  constructor(message = 'Voice session requires a bound BRC-52 cert; identity provider returned null') {
    super(message);
    this.name = 'MissingCertError';
  }
}

/**
 * Thrown when a voice contract invariant is violated by the caller —
 * e.g. signer.keyId ≠ session.certId.
 */
export class VoiceContractError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
    this.name = 'VoiceContractError';
  }
}

// ── createVoiceSession ───────────────────────────────────────

export interface CreateVoiceSessionOptions {
  /** Override Date.now() — for deterministic tests. */
  now?: () => number;
  /** Optional opaque device id; carried only for diagnostics. */
  deviceId?: string;
}

/**
 * Create a cert-bound VoiceSession.
 *
 * @throws MissingCertError if `provider.currentCert()` returns null.
 */
export function createVoiceSession(
  provider: VoiceIdentityProvider,
  opts: CreateVoiceSessionOptions = {},
): VoiceSession {
  const cert = provider.currentCert();
  if (cert === null) {
    throw new MissingCertError();
  }
  if (!cert.certId || !cert.subjectPublicKey) {
    throw new VoiceContractError(
      'VOICE_CERT_INVALID',
      'identity provider returned a cert without certId or subjectPublicKey',
    );
  }
  const startedAt = (opts.now ?? Date.now)();
  const id = deriveVoiceSessionId(cert.certId, startedAt);
  return {
    id,
    certId: cert.certId,
    subjectPublicKey: cert.subjectPublicKey,
    startedAt,
    deviceId: opts.deviceId,
  };
}

// ── addTranscript ────────────────────────────────────────────

export interface AddTranscriptOptions {
  /** Override Date.now() — for deterministic tests. */
  now?: () => number;
  /**
   * Sequence number for this transcript within the session. Callers
   * own monotonicity (the producer can be a stream — the substrate is
   * stateless w.r.t. sequencing). Defaults to 0 if absent; supply the
   * running counter in real use.
   */
  sequence?: number;
}

/**
 * Append a signed Transcript to a VoiceSession.
 *
 * The signer's `sign(preimage)` must return a `VoiceSignature` whose
 * `keyId` equals `session.certId` (otherwise the transcript would
 * advertise a different speaker than the session, which the verifier
 * sidecar would reject at the boundary).
 *
 * @throws VoiceContractError if signer.keyId disagrees with session.certId.
 */
export function addTranscript(
  session: VoiceSession,
  text: string,
  signer: Pick<VoiceIdentityProvider, 'sign'>,
  opts: AddTranscriptOptions = {},
): Transcript {
  const sequence = opts.sequence ?? 0;
  const timestamp = (opts.now ?? Date.now)();

  const preimage = canonicalTranscriptPreimage({
    sessionId: session.id,
    certId: session.certId,
    sequence,
    text,
    timestamp,
  });

  const signature: VoiceSignature = signer.sign(preimage);
  if (signature.keyId !== session.certId) {
    throw new VoiceContractError(
      'VOICE_KEYID_MISMATCH',
      `signer keyId ${signature.keyId} does not match session certId ${session.certId}`,
    );
  }

  const id = deriveTranscriptId(session.id, sequence) as TranscriptId;
  return {
    id,
    sessionId: session.id,
    certId: session.certId,
    sequence,
    text,
    timestamp,
    signature,
  };
}

// ── verifyTranscript ─────────────────────────────────────────

/**
 * Capability the caller supplies for signature verification — same
 * shape every other surface in the substrate uses (BRC-100 wallet
 * client / verifier sidecar). Pure: returns boolean, no I/O contract.
 */
export type VerifySignatureFn = (
  preimage: Uint8Array,
  signature: VoiceSignature,
) => boolean;

/**
 * Verify a Transcript's cert binding and signature.
 *
 * Returns `false` (never throws) if:
 *   - signature.keyId ≠ certId (the speaker advertised on the
 *     transcript), OR
 *   - the supplied verifier returns false for the canonical preimage.
 *
 * In production the verifier is delegated to the verifier sidecar
 * (D-V1) via the BRC-100 wallet interface. Tests can supply a pure
 * function. This split keeps the voice module free of any vendor SDK
 * dependency at compile time (no `@bsv/sdk` ECDSA call inside the
 * runtime tier — the runtime only uses `Hash.sha256` for preimage
 * derivation, which is already a workspace dependency).
 */
export function verifyTranscript(
  transcript: Transcript,
  verify: VerifySignatureFn,
): boolean {
  // Cheap structural checks first — catch misuse before paying for ECDSA.
  if (transcript.signature.keyId !== transcript.certId) {
    return false;
  }
  const preimage = canonicalTranscriptPreimage({
    sessionId: transcript.sessionId,
    certId: transcript.certId,
    sequence: transcript.sequence,
    text: transcript.text,
    timestamp: transcript.timestamp,
  });
  try {
    return verify(preimage, transcript.signature) === true;
  } catch {
    return false;
  }
}

/**
 * Convenience: re-derive the session id a transcript claims to belong
 * to and check it matches the embedded `sessionId`. Useful as a guard
 * before calling `verifyTranscript` (e.g. when correlating incoming
 * transcripts to an active session by cert_id + start time).
 *
 * Returns `false` if the recomputed session id disagrees.
 */
export function transcriptBelongsToSession(
  transcript: Transcript,
  session: Pick<VoiceSession, 'id' | 'certId' | 'startedAt'>,
): boolean {
  if (transcript.sessionId !== session.id) return false;
  if (transcript.certId !== session.certId) return false;
  const expected = deriveVoiceSessionId(session.certId, session.startedAt);
  return expected === session.id;
}

export type { VoiceSessionId };

```
