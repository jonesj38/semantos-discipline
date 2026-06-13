---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/plexus/dispatch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.676819+00:00
---

# cartridges/wallet-headers/brain/src/plexus/dispatch.ts

```ts
// Plexus enrollment + recovery dispatcher (W7).
//
// This module is the ONLY path in the browser bundle that contacts an
// external network endpoint (per `WALLET-TIER-CUSTODY.md` §8.1). It owns:
//   • posting the dispatch envelope (built by `./envelope.ts`),
//   • driving the email-OTP loop via a caller-supplied callback,
//   • posting recovery initiation / completion,
//   • decrypting the seed locally and rebuilding tier-key material.
//
// Failure modes are surfaced as explicit `Result` values rather than thrown
// exceptions so the popup UI can render distinct messages per state. The
// dispatcher *does* throw if the BRC-100 envelope can't be built (genuine
// programmer bug — caller passed inconsistent identity material).
//
// Cross-references:
//   • design §7.7 (enrollment flow)
//   • design §7.8 (recovery flow)
//   • design §8.3 (OTP + rate limit error mapping)

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import { buildEnvelope as buildBrc100, hexToBytes, bytesToHex } from '../brc100';
import {
  buildEnvelope,
  decryptRecoverySeed,
  hashAnswerHex,
  type PlexusRecoveryEnvelope,
  type DerivationContext,
  type DerivationStateSnapshot,
} from './envelope';
import type { PlexusOperator, Brc100Wire, OperatorResponse } from './operator';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────────────────

/** Generic Result. Caller dispatches on `ok`. */
export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

/** Caller-supplied OTP prompt — the popup shows a 6-digit input and
 * resolves the promise with whatever the user typed. Resolves to null if
 * the user cancels. */
export type OtpPromptFn = (ctx: { maskedEmail: string; expiresInSeconds: number }) => Promise<string | null>;

/** Caller-supplied challenge-answer prompt for recovery. */
export type AnswerPromptFn = (questions: string[]) => Promise<string[] | null>;

export interface EnrollParams {
  identitySk: Uint8Array;
  identityPk: Uint8Array;
  certId: Uint8Array;
  contactEmail: string;
  questions: string[];
  /** Plaintext answers, same order as `questions`. Wiped after use. */
  answers: string[];
  /** 64-byte BIP39 seed. Wiped after use. */
  recoverySeed: Uint8Array;
  derivationContexts: DerivationContext[];
  derivationStateSnapshot: DerivationStateSnapshot;
  /** Resolves to OTP code typed by the user, or null on cancel. */
  requestOtp: OtpPromptFn;
}

export type EnrollError =
  | { kind: 'INVARIANT_FAILED'; check: 1 | 2 | 3 | 4 | 5; detail: string }
  | { kind: 'INVALID_INPUT'; reason: string }
  | { kind: 'NETWORK_FAILURE'; detail: string; cachedEnvelope: PlexusRecoveryEnvelope }
  | { kind: 'UNSUPPORTED_VERSION' }
  | { kind: 'RATE_LIMITED' }
  | { kind: 'OTP_EXPIRED' }
  | { kind: 'OTP_LOCKED' }
  | { kind: 'OTP_WRONG'; attemptsRemaining: number }
  | { kind: 'OTP_CANCELLED' }
  | { kind: 'OPERATOR_REJECTED'; status: number; detail: string };

export interface EnrollResult {
  envelope: PlexusRecoveryEnvelope;
  enrolledAt: number;
  operatorDomain: string;
}

export interface EnrollCachedParams {
  identitySk: Uint8Array;
  identityPk: Uint8Array;
  envelope: PlexusRecoveryEnvelope;
  /** Resolves to OTP code typed by the user, or null on cancel. */
  requestOtp: OtpPromptFn;
}

export interface RecoverParams {
  contactEmail: string;
  /** OTP prompt — same shape as enrollment. */
  requestOtp: OtpPromptFn;
  /** Answer prompt — caller renders the questions and collects answers. */
  requestAnswers: AnswerPromptFn;
}

export interface RecoverResult {
  envelope: PlexusRecoveryEnvelope;
  /** The 64-byte BIP39 seed, ready for tier-key rederivation. Caller must wipe. */
  recoveredSeed: Uint8Array;
  /** A list of (tier, derivationContext) pairs reconstructed from the envelope. */
  tierContexts: DerivationContext[];
  /** Snapshot of the DerivationState at enrollment time — caller replays this
   *  via `DerivationStateStore.replay()` (§3.5.3). */
  derivationStateSnapshot: DerivationStateSnapshot;
}

export type RecoverError =
  | { kind: 'INVALID_INPUT'; reason: string }
  | { kind: 'NETWORK_FAILURE'; detail: string }
  | { kind: 'NO_ENROLLMENT' }
  | { kind: 'RATE_LIMITED' }
  | { kind: 'OTP_EXPIRED' }
  | { kind: 'OTP_LOCKED' }
  | { kind: 'OTP_WRONG'; attemptsRemaining: number }
  | { kind: 'OTP_CANCELLED' }
  | { kind: 'CHALLENGE_FAILED' }
  | { kind: 'CHALLENGE_CANCELLED' }
  | { kind: 'DECRYPT_FAILED' }
  | { kind: 'OPERATOR_REJECTED'; status: number; detail: string };

// ──────────────────────────────────────────────────────────────────────
// Enrollment
// ──────────────────────────────────────────────────────────────────────

/**
 * Build the dispatch envelope, post it to the operator, drive the OTP loop,
 * and confirm. Wipes sensitive intermediates inside this function. The
 * caller is responsible for wiping the buffers it passed in (`answers`,
 * `recoverySeed`).
 *
 * On network failure mid-dispatch the envelope is returned in the error
 * payload so the caller can persist it locally for a "retry enrollment"
 * affordance (per design §7.7 failure mode "Network failure during dispatch").
 */
export async function enroll(
  operator: PlexusOperator,
  params: EnrollParams,
): Promise<Result<EnrollResult, EnrollError>> {
  // 1. Build envelope locally.
  const built = await buildEnvelope({
    identitySk: params.identitySk,
    identityPk: params.identityPk,
    certId: params.certId,
    contactEmail: params.contactEmail,
    questions: params.questions,
    answers: params.answers,
    recoverySeed: params.recoverySeed,
    derivationContexts: params.derivationContexts,
    derivationStateSnapshot: params.derivationStateSnapshot,
  });
  if (!built.ok) {
    if (built.error.kind === 'INVARIANT_FAILED') {
      return { ok: false, error: built.error };
    }
    return { ok: false, error: built.error };
  }

  // 2. POST /enrollment/dispatch.
  let dispatchResp: OperatorResponse;
  try {
    dispatchResp = await operator.enrollmentDispatch(brc100ToWire(built.brc100));
  } catch (e) {
    return {
      ok: false,
      error: {
        kind: 'NETWORK_FAILURE',
        detail: (e as Error).message,
        cachedEnvelope: built.envelope,
      },
    };
  }
  const dispatchErr = mapDispatchError(dispatchResp);
  if (dispatchErr) {
    return { ok: false, error: dispatchErr };
  }
  // dispatchResp.body = { otpDeliveredTo, expiresInSeconds }
  const dispatchBody = dispatchResp.body as { otpDeliveredTo: string; expiresInSeconds: number };

  // 3. Prompt user for OTP.
  const otp = await params.requestOtp({
    maskedEmail: dispatchBody.otpDeliveredTo,
    expiresInSeconds: dispatchBody.expiresInSeconds,
  });
  if (otp === null) {
    return { ok: false, error: { kind: 'OTP_CANCELLED' } };
  }

  // 4. POST /enrollment/confirm with the OTP.
  const confirmBody = JSON.stringify({ identityKey: built.envelope.identityKey, otp });
  const confirmEnv = buildBrc100(
    params.identitySk,
    params.identityPk,
    new TextEncoder().encode(confirmBody),
  );
  let confirmResp: OperatorResponse;
  try {
    confirmResp = await operator.enrollmentConfirm(brc100ToWire(confirmEnv));
  } catch (e) {
    return {
      ok: false,
      error: {
        kind: 'NETWORK_FAILURE',
        detail: (e as Error).message,
        cachedEnvelope: built.envelope,
      },
    };
  }
  const confirmErr = mapConfirmError(confirmResp);
  if (confirmErr) {
    return { ok: false, error: confirmErr };
  }
  const confirmRespBody = confirmResp.body as { enrolledAt: number };

  return {
    ok: true,
    value: {
      envelope: built.envelope,
      enrolledAt: confirmRespBody.enrolledAt,
      operatorDomain: operator.config.displayDomain,
    },
  };
}

/**
 * Enroll a recovery envelope that was already built at wallet creation.
 * This is the preferred v0.4 path: createWallet() creates the recovery
 * envelope locally, persists it, and Plexus enrollment only mirrors that
 * existing encrypted envelope to the operator. No recovery seed or raw
 * challenge answers are needed here.
 */
export async function enrollCachedEnvelope(
  operator: PlexusOperator,
  params: EnrollCachedParams,
): Promise<Result<EnrollResult, EnrollError>> {
  if (params.identitySk.length !== 32) {
    return { ok: false, error: { kind: 'INVALID_INPUT', reason: 'identitySk must be 32 bytes' } };
  }
  if (params.identityPk.length !== 33) {
    return { ok: false, error: { kind: 'INVALID_INPUT', reason: 'identityPk must be 33 bytes' } };
  }
  const identityKey = bytesToHex(params.identityPk);
  if (params.envelope.identityKey !== identityKey) {
    return {
      ok: false,
      error: { kind: 'INVALID_INPUT', reason: 'cached envelope identityKey does not match identityPk' },
    };
  }

  const bodyBytes = new TextEncoder().encode(JSON.stringify(params.envelope));
  const dispatchEnv = buildBrc100(params.identitySk, params.identityPk, bodyBytes);
  let dispatchResp: OperatorResponse;
  try {
    dispatchResp = await operator.enrollmentDispatch(brc100ToWire(dispatchEnv));
  } catch (e) {
    return {
      ok: false,
      error: {
        kind: 'NETWORK_FAILURE',
        detail: (e as Error).message,
        cachedEnvelope: params.envelope,
      },
    };
  }
  const dispatchErr = mapDispatchError(dispatchResp);
  if (dispatchErr) return { ok: false, error: dispatchErr };
  const dispatchBody = dispatchResp.body as { otpDeliveredTo: string; expiresInSeconds: number };

  const otp = await params.requestOtp({
    maskedEmail: dispatchBody.otpDeliveredTo,
    expiresInSeconds: dispatchBody.expiresInSeconds,
  });
  if (otp === null) {
    return { ok: false, error: { kind: 'OTP_CANCELLED' } };
  }

  const confirmBody = JSON.stringify({ identityKey: params.envelope.identityKey, otp });
  const confirmEnv = buildBrc100(
    params.identitySk,
    params.identityPk,
    new TextEncoder().encode(confirmBody),
  );
  let confirmResp: OperatorResponse;
  try {
    confirmResp = await operator.enrollmentConfirm(brc100ToWire(confirmEnv));
  } catch (e) {
    return {
      ok: false,
      error: {
        kind: 'NETWORK_FAILURE',
        detail: (e as Error).message,
        cachedEnvelope: params.envelope,
      },
    };
  }
  const confirmErr = mapConfirmError(confirmResp);
  if (confirmErr) return { ok: false, error: confirmErr };
  const confirmRespBody = confirmResp.body as { enrolledAt: number };

  return {
    ok: true,
    value: {
      envelope: params.envelope,
      enrolledAt: confirmRespBody.enrolledAt,
      operatorDomain: operator.config.displayDomain,
    },
  };
}

// ──────────────────────────────────────────────────────────────────────
// Recovery
// ──────────────────────────────────────────────────────────────────────

/**
 * Walk the recovery flow (per design §7.8). Steps:
 *   1. POST /recovery/initiate with email, get back a masked OTP target.
 *   2. Prompt the user for the OTP.
 *   3. POST /recovery/complete with OTP + locally-hashed answers.
 *   4. Plexus returns the stored envelope.
 *   5. Decrypt the recovery seed locally using the same answers.
 *   6. Surface seed + derivation metadata to the caller for rebuild.
 *
 * Plexus never sees the raw answers — they're SHA-hashed locally with the
 * stored salt before being shipped.
 *
 * Note: recovery requires a *second* round-trip to fetch the salt (we don't
 * know it until we get the envelope back). To keep step 3 atomic, the
 * dispatcher first does a "challenge fetch" via the same /recovery/complete
 * endpoint with empty `answerHashes` — the operator returns the salt+questions
 * as a 401 challenge, then the wallet hashes the answers and retries. This
 * mirrors design §7.8 step 6 ("Plexus presents stored challenge questions").
 *
 * MockPlexusOperator implements this single-shot: the wallet hashes against
 * a salt fetched out-of-band by `recoveryFetchChallenge`.
 */
export async function recover(
  operator: PlexusOperator,
  params: RecoverParams,
): Promise<Result<RecoverResult, RecoverError>> {
  if (!params.contactEmail.includes('@')) {
    return { ok: false, error: { kind: 'INVALID_INPUT', reason: 'bad email' } };
  }

  // 1. POST /recovery/initiate (no signature — we don't have an identity key
  //    yet on a fresh device).
  const initiateBody = JSON.stringify({ contactEmail: params.contactEmail });
  let initiateResp: OperatorResponse;
  try {
    initiateResp = await operator.recoveryInitiate(zeroSignedWire(initiateBody));
  } catch (e) {
    return { ok: false, error: { kind: 'NETWORK_FAILURE', detail: (e as Error).message } };
  }
  if (initiateResp.status === 429) {
    return { ok: false, error: { kind: 'RATE_LIMITED' } };
  }
  if (initiateResp.status !== 202) {
    return {
      ok: false,
      error: { kind: 'OPERATOR_REJECTED', status: initiateResp.status, detail: stringifyBody(initiateResp.body) },
    };
  }
  const initBody = initiateResp.body as { otpDeliveredTo: string; expiresInSeconds?: number };

  // 2. Prompt user for OTP.
  const otp = await params.requestOtp({
    maskedEmail: initBody.otpDeliveredTo,
    expiresInSeconds: initBody.expiresInSeconds ?? 600,
  });
  if (otp === null) {
    return { ok: false, error: { kind: 'OTP_CANCELLED' } };
  }

  // 3. Fetch the challenge (questions + salt) so we can hash answers locally.
  //    Per design §7.8 step 6 ("Plexus presents stored challenge questions").
  //    v0.1 mock-only — production needs an HTTP /recovery/challenge route
  //    that the design doc has not yet locked (tracked under §11 Q11
  //    follow-up: "operator-side challenge presentation").
  const challengeMeta = await recoveryFetchChallenge(operator, params.contactEmail, otp);
  if (!challengeMeta.ok) {
    return challengeMeta;
  }

  // 4. Prompt user for challenge answers.
  const answers = await params.requestAnswers(challengeMeta.value.questions);
  if (answers === null) {
    return { ok: false, error: { kind: 'CHALLENGE_CANCELLED' } };
  }
  if (answers.length !== challengeMeta.value.questions.length) {
    return { ok: false, error: { kind: 'CHALLENGE_FAILED' } };
  }

  // 5. Locally hash the answers under the operator-supplied salt.
  const answerHashes = answers.map((a) => hashAnswerHex(challengeMeta.value.salt, a));

  // 6. POST /recovery/complete with the hashes.
  const completeBody = JSON.stringify({
    contactEmail: params.contactEmail,
    otp,
    answerHashes,
  });
  let completeResp: OperatorResponse;
  try {
    completeResp = await operator.recoveryComplete(zeroSignedWire(completeBody));
  } catch (e) {
    return { ok: false, error: { kind: 'NETWORK_FAILURE', detail: (e as Error).message } };
  }
  const completeErr = mapRecoveryCompleteError(completeResp);
  if (completeErr) {
    return { ok: false, error: completeErr };
  }
  const respBody = completeResp.body as { envelope: PlexusRecoveryEnvelope };
  if (!respBody?.envelope) {
    return { ok: false, error: { kind: 'OPERATOR_REJECTED', status: completeResp.status, detail: 'no envelope' } };
  }

  // 7. Decrypt the recovery seed locally.
  const seed = await decryptRecoverySeed(respBody.envelope, answers);
  if (!seed) {
    return { ok: false, error: { kind: 'DECRYPT_FAILED' } };
  }
  // Wipe local copies of answers.
  for (let i = 0; i < answers.length; i++) answers[i] = '';

  return {
    ok: true,
    value: {
      envelope: respBody.envelope,
      recoveredSeed: seed,
      tierContexts: respBody.envelope.derivationContexts.map((c) => ({ ...c })),
      derivationStateSnapshot: {
        records: respBody.envelope.derivationStateSnapshot.records.map((r) => ({ ...r })),
        snapshotTimestamp: respBody.envelope.derivationStateSnapshot.snapshotTimestamp,
      },
    },
  };
}

/**
 * Single-shot challenge fetch. The wire here is "send OTP only, get
 * (salt, questions) back so we can hash". Mock implementation: query the
 * operator's enrollment store directly.
 *
 * For HTTP-mode this would call `POST /recovery/challenge` — that endpoint
 * isn't in the design's §8.1 table yet (only initiate / complete), so the
 * v0.1 implementation reaches into the mock for tests, and the production
 * HTTP path will gain a `recoveryChallenge` method on PlexusOperator once
 * the operator-side spec lands. Tracked as design §11 Q11 follow-up.
 */
async function recoveryFetchChallenge(
  operator: PlexusOperator,
  contactEmail: string,
  _otp: string,
): Promise<Result<{ salt: string; questions: string[] }, RecoverError>> {
  // The mock exposes its enrollments map. Detect duck-typed.
  const maybeMock = operator as unknown as {
    emailToIdentityKey?: Map<string, string>;
    enrollments?: Map<string, { envelope: PlexusRecoveryEnvelope }>;
  };
  if (maybeMock.emailToIdentityKey && maybeMock.enrollments) {
    const ik = maybeMock.emailToIdentityKey.get(contactEmail);
    if (!ik) return { ok: false, error: { kind: 'NO_ENROLLMENT' } };
    const stored = maybeMock.enrollments.get(ik);
    if (!stored) return { ok: false, error: { kind: 'NO_ENROLLMENT' } };
    return {
      ok: true,
      value: {
        salt: stored.envelope.challengeBundle.salt,
        questions: stored.envelope.challengeBundle.questions.slice(),
      },
    };
  }
  // HTTP fallback — operator must implement /recovery/challenge in v0.2.
  return {
    ok: false,
    error: {
      kind: 'OPERATOR_REJECTED',
      status: 501,
      detail: 'recoveryFetchChallenge: HTTP /recovery/challenge endpoint not implemented in v0.1',
    },
  };
}

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────

/** Convert a buildBrc100() result into the on-the-wire `Brc100Wire` shape. */
function brc100ToWire(env: ReturnType<typeof buildBrc100>): Brc100Wire {
  const bodyStr =
    typeof env.body === 'string' ? env.body : new TextDecoder().decode(env.body);
  return {
    headers: {
      'x-brc100-identitykey': env.identityKey,
      'x-brc100-nonce': env.nonce,
      'x-brc100-timestamp': String(env.timestamp),
      'x-brc100-signature': env.signature,
    },
    body: bodyStr,
  };
}

/**
 * For /recovery/* the wallet has no identity key (fresh device). We send a
 * placeholder wire shape with all-zero signatures — the operator does not
 * verify a signature on /recovery/initiate or the OTP path of /complete,
 * since no identity is bound yet. The signature is checked again at the
 * end of recovery once the wallet rederives an identity from the seed.
 */
function zeroSignedWire(body: string): Brc100Wire {
  // 33-byte all-zeros (invalid pubkey but operator accepts the shape).
  const zerosIdentity = bytesToHex(new Uint8Array(33));
  const zerosNonce = bytesToHex(new Uint8Array(32));
  const zerosSig = '00';
  return {
    headers: {
      'x-brc100-identitykey': zerosIdentity,
      'x-brc100-nonce': zerosNonce,
      'x-brc100-timestamp': String(Math.floor(Date.now() / 1000)),
      'x-brc100-signature': zerosSig,
    },
    body,
  };
}

function stringifyBody(body: unknown): string {
  if (body === null || body === undefined) return '';
  if (typeof body === 'string') return body;
  try {
    return JSON.stringify(body);
  } catch {
    return String(body);
  }
}

function mapDispatchError(resp: OperatorResponse): EnrollError | null {
  if (resp.status === 202) return null;
  const body = resp.body as { error?: string } | null;
  switch (resp.status) {
    case 429:
      return { kind: 'RATE_LIMITED' };
    case 400:
      if (body?.error === 'UNSUPPORTED_VERSION' || body?.error === 'UNSUPPORTED_ALGORITHM') {
        return { kind: 'UNSUPPORTED_VERSION' };
      }
      return {
        kind: 'OPERATOR_REJECTED',
        status: resp.status,
        detail: body?.error ?? 'bad request',
      };
    default:
      return {
        kind: 'OPERATOR_REJECTED',
        status: resp.status,
        detail: body?.error ?? `status ${resp.status}`,
      };
  }
}

function mapConfirmError(resp: OperatorResponse): EnrollError | null {
  if (resp.status === 200) return null;
  const body = resp.body as { error?: string; attemptsRemaining?: number } | null;
  switch (resp.status) {
    case 410:
      return { kind: 'OTP_EXPIRED' };
    case 423:
      return { kind: 'OTP_LOCKED' };
    case 401:
      return { kind: 'OTP_WRONG', attemptsRemaining: body?.attemptsRemaining ?? 0 };
    default:
      return {
        kind: 'OPERATOR_REJECTED',
        status: resp.status,
        detail: body?.error ?? `status ${resp.status}`,
      };
  }
}

function mapRecoveryCompleteError(resp: OperatorResponse): RecoverError | null {
  if (resp.status === 200) return null;
  const body = resp.body as { error?: string; attemptsRemaining?: number } | null;
  switch (resp.status) {
    case 401:
      if (body?.error === 'CHALLENGE_FAILED') return { kind: 'CHALLENGE_FAILED' };
      return { kind: 'OTP_WRONG', attemptsRemaining: body?.attemptsRemaining ?? 0 };
    case 410:
      return { kind: 'OTP_EXPIRED' };
    case 423:
      return { kind: 'OTP_LOCKED' };
    case 404:
      return { kind: 'NO_ENROLLMENT' };
    case 429:
      return { kind: 'RATE_LIMITED' };
    default:
      return {
        kind: 'OPERATOR_REJECTED',
        status: resp.status,
        detail: body?.error ?? `status ${resp.status}`,
      };
  }
}

// Small shim so the test files can ask for the bytes-to-hex helper without
// crossing the brc100 module boundary.
export { hexToBytes, bytesToHex };

```
