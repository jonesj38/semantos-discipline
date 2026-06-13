---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/voice/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.351831+00:00
---

# runtime/intent/src/voice/types.ts

```ts
/**
 * Voice — placeholder cert-bound input modality.
 *
 * Wave-1.5 D-A7 (A8×A) deliverable. Voice (matrix row A8) is a
 * placeholder surface. This module lands the cert-bound interface that
 * future voice-transcription work will consume so that the contract is
 * fixed before the implementation arrives:
 *
 *   - A `VoiceSession` is bound to a BRC-52 cert at creation time.
 *     Without a cert, the producer rejects — there is no anonymous
 *     voice channel in the protocol (otherwise the channel is
 *     unauthenticated speech, per Unification Roadmap §5 D-A7).
 *
 *   - A `Transcript` carries the speaker's `cert_id` and a session-bound
 *     identifier deterministically derived from `(cert_id, started_at)`
 *     — not a random session id (per protocol-v0.5.md §4 and the
 *     wave-1.5 commission §7.3 acceptance gates).
 *
 *   - Each transcript is signed; `verifyTranscript` re-checks the
 *     signature against the canonical preimage so downstream consumers
 *     can prove authorship without re-asking the identity layer.
 *
 * Spec sources:
 *   - docs/spec/protocol-v0.5.md §4 (Identity protocol — cert_id is the
 *     32-byte SHA-256 of the canonical BRC-52 preimage; every actor
 *     binds to a BRC-52 cert).
 *   - docs/canon/glossary.yml (cert-id, brc-52).
 *   - docs/prd/UNIFICATION-ROADMAP.md §5 D-A7, §2 row A8.
 *
 * Canonical term: cert_id (snake_case wire form). K invariants: K2
 * applies — every Transcript carries an identity binding that the
 * verifier sidecar will check at the boundary; this module produces
 * artifacts the sidecar can verify.
 */

// ── Branded IDs ──────────────────────────────────────────────

/**
 * Deterministic identifier for a VoiceSession. Computed as
 * `SHA-256(cert_id || started_at_be_u64)` and hex-encoded; see
 * `deriveVoiceSessionId`. NOT a random id — voice sessions inherit
 * their identity from the speaker's cert plus the start time.
 */
export type VoiceSessionId = string & { readonly __brand: 'VoiceSessionId' };

/** Deterministic per-transcript identifier (sequence-numbered within a session). */
export type TranscriptId = string & { readonly __brand: 'TranscriptId' };

// ── Voice signature shape ────────────────────────────────────
//
// Mirrors the shape of `Signature` in `../types.ts` so a downstream
// adapter can cross-cast trivially. Re-declared here to keep the voice
// stub independent of the broader Intent surface (a transcript is a
// cert-bound artifact regardless of whether it ever becomes an Intent).

/**
 * Signature over a transcript canonical preimage. The keyId MUST equal
 * the speaker's `cert_id`. The bytes are produced by the BRC-100 wallet
 * client bound to that cert (per protocol-v0.5.md §4.6).
 */
export interface VoiceSignature {
  bytes: Uint8Array;
  algorithm: string;
  /** Equals the speaker's `cert_id`. */
  keyId: string;
}

// ── Identity provider ────────────────────────────────────────

/**
 * Minimal identity capability a voice producer needs. Structural — the
 * voice stub does not depend on any concrete identity adapter; the
 * caller wires this from `IdentityAdapter` (D-A0b) or the verifier
 * sidecar's cert resolver.
 *
 * `subjectPublicKey` is the 33-byte compressed secp256k1 pubkey from
 * the BRC-52 cert's `subject` field, hex-encoded. Held on the session
 * so a verifier can re-derive the BCA without re-resolving the cert.
 */
export interface VoiceIdentityProvider {
  /**
   * Return the cert binding for the active speaker. Returns `null` if
   * no cert is currently bound — the producer rejects in that case.
   */
  currentCert(): {
    certId: string;
    subjectPublicKey: string;
  } | null;

  /**
   * Sign the transcript canonical preimage with the speaker's signing
   * key. The returned `keyId` MUST equal the cert_id of the speaker.
   */
  sign(preimage: Uint8Array): VoiceSignature;
}

// ── VoiceSession ─────────────────────────────────────────────

/**
 * A cert-bound voice capture session. Created via `createVoiceSession`,
 * which rejects if no cert is bound. The session id is deterministic —
 * derived from (cert_id, startedAt) so two transcripts in the same
 * session share a session-bound identifier without consulting any
 * server-side session registry.
 */
export interface VoiceSession {
  /** `SHA-256(cert_id || started_at_be_u64)` as 64-char lowercase hex. */
  id: VoiceSessionId;
  /** Speaker's cert_id (from BRC-52). */
  certId: string;
  /**
   * 33-byte compressed secp256k1 pubkey from the cert's `subject`
   * field, hex-encoded (66 chars). Held on the session so a verifier
   * can re-derive the BCA without re-resolving the cert.
   */
  subjectPublicKey: string;
  /** Milliseconds since epoch — fixed at session creation. */
  startedAt: number;
  /**
   * Optional opaque identifier for the capture device. Not used by the
   * cert binding; carried only for diagnostics and audit.
   */
  deviceId?: string;
}

// ── Transcript ───────────────────────────────────────────────

/**
 * A signed segment of speech transcribed within a VoiceSession.
 *
 * `sessionId` is the VoiceSession's deterministic id (NOT a random
 * value). `certId` is the speaker — equal to the parent session's
 * `certId`. The `signature.keyId` MUST equal `certId`; verification
 * fails otherwise.
 *
 * The canonical preimage covered by the signature is documented in
 * `canonicalTranscriptPreimage` (./preimage.ts).
 */
export interface Transcript {
  /** Per-transcript identifier; deterministic from session + sequence. */
  id: TranscriptId;
  /** Parent VoiceSession id (deterministic from cert + start time). */
  sessionId: VoiceSessionId;
  /** Speaker's cert_id — equals `session.certId`. */
  certId: string;
  /** Monotonic per-session sequence number, starting at 0. */
  sequence: number;
  /** Verbatim transcribed text. */
  text: string;
  /** Milliseconds since epoch. */
  timestamp: number;
  /** Signature over the canonical preimage; `keyId` MUST equal `certId`. */
  signature: VoiceSignature;
}

```
