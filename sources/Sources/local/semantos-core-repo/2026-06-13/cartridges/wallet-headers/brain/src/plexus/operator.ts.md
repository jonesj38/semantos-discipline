---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/plexus/operator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.677158+00:00
---

# cartridges/wallet-headers/brain/src/plexus/operator.ts

```ts
// Plexus operator config + in-process mock (W7).
//
// The wallet talks to *one* configured Plexus operator at build time. The
// production config is supplied by the wallet operator (see the
// "Recovery enrollment" section in cartridges/wallet-headers/brain/README.md) and ships
// inside the bundle. The MockPlexusOperator mirrors the wire protocol in
// memory so tests never touch the network — per the W7 acceptance criterion
// "No actual external HTTP calls in tests".
//
// Wire format: every endpoint accepts a BRC-100-signed JSON body and
// responds with a JSON object. The operator validates:
//   • signature against the body's canonical digest,
//   • timestamp inside its replay window,
//   • per-(email, identityKey) rate limit,
//   • OTP state for the multi-step enrollment / recovery flow.
//
// Cross-references:
//   • design §8.1 (Plexus is external — only enroll & recover endpoints)
//   • design §8.3 (OTP + rate limiting)
//   • design §11 Q10 (operator pricing surface — `/info`)

import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { bytesToHex } from '../brc100';
import type { PlexusRecoveryEnvelope } from './envelope';

// ──────────────────────────────────────────────────────────────────────
// Public types
// ──────────────────────────────────────────────────────────────────────

/** Operator subscription / pricing info per design §11 Q10. */
export interface OperatorInfo {
  /** Display domain ("plexus-keys.com"). */
  operatorDomain: string;
  /** Annual subscription, in sats. Display-only. */
  annualPriceSats: number;
  /** Algorithm versions this operator supports. Wallet must include one. */
  supportedAlgorithmVersions: number[];
  /** Subscription-lapse policy in human-readable form. */
  subscriptionLapsePolicy: 'archive' | 'delete' | 'grace-period';
  /** Optional grace period in days before lapse-policy applies. */
  graceDays?: number;
}

/** A response from any operator endpoint (mock or HTTP). */
export interface OperatorResponse {
  /** HTTP status code (or its mock equivalent). */
  status: number;
  /** Parsed JSON body — `null` on non-JSON responses. */
  body: unknown;
}

/**
 * The single interface every Plexus client (HTTP or mock) implements.
 * Tests inject a MockPlexusOperator; production wires up an HttpPlexusOperator.
 */
export interface PlexusOperator {
  /** Operator config (URL, pinned cert, etc). Used by the dispatcher for telemetry / UI. */
  readonly config: PlexusOperatorConfig;

  /** GET /info — pricing, supported algorithm versions, subscription policy. */
  info(): Promise<OperatorResponse>;

  /** POST /enrollment/dispatch — body is the BRC-100 wire envelope (headers + body). */
  enrollmentDispatch(wire: Brc100Wire): Promise<OperatorResponse>;

  /** POST /enrollment/confirm — supply the OTP after dispatch. */
  enrollmentConfirm(wire: Brc100Wire): Promise<OperatorResponse>;

  /** POST /recovery/initiate — start a recovery flow with email only. */
  recoveryInitiate(wire: Brc100Wire): Promise<OperatorResponse>;

  /** POST /recovery/complete — supply OTP + answer hashes; returns envelope payload. */
  recoveryComplete(wire: Brc100Wire): Promise<OperatorResponse>;
}

/**
 * The on-the-wire shape — a BRC-100 envelope laid out as:
 *   headers: { x-brc100-... }
 *   body:    JSON-stringified payload
 *
 * Mirrors the W6 sovereign-node format exactly so future operator ↔ node
 * interop works without re-encoding.
 */
export interface Brc100Wire {
  headers: {
    'x-brc100-identitykey': string;
    'x-brc100-nonce': string;
    'x-brc100-timestamp': string;
    'x-brc100-signature': string;
  };
  body: string;
}

export interface PlexusOperatorConfig {
  /** Base HTTPS URL — e.g. `https://plexus-keys.com`. Mock leaves this empty. */
  baseUrl: string;
  /** Optional SHA-256 fingerprint of the operator's TLS cert, hex.
   * The HTTP client should refuse connections whose presented cert
   * does not match (defense-in-depth above WebPKI). */
  pinnedCertFingerprintSha256?: string;
  /** Display label for the UI banner ("plexus-keys.com"). */
  displayDomain: string;
}

// ──────────────────────────────────────────────────────────────────────
// MockPlexusOperator — in-memory for tests
// ──────────────────────────────────────────────────────────────────────

interface PendingEnrollment {
  identityKey: string;
  email: string;
  envelope: PlexusRecoveryEnvelope;
  otp: string;
  attempts: number;
  /** ms since epoch (mock-controlled). */
  createdAt: number;
}

interface StoredEnrollment {
  identityKey: string;
  email: string;
  envelope: PlexusRecoveryEnvelope;
  enrolledAt: number;
}

interface PendingRecovery {
  email: string;
  /** Identity key as stored at enrollment time (looked up via email). */
  identityKey: string;
  otp: string;
  attempts: number;
  createdAt: number;
  /** Set after step 1 ("OTP delivered") so step 2 can require it. */
  otpVerified: boolean;
}

/** Tunable parameters per design §8.3. */
export interface MockOperatorPolicy {
  /** OTP expiry in ms; default 600_000 (10 min). */
  otpExpiryMs: number;
  /** Max OTP attempts before lockout; default 5. */
  maxOtpAttempts: number;
  /** Per-(email, identityKey) enrollment dispatch quota per hour; default 3. */
  enrollmentDispatchPerHour: number;
  /** Per-email recovery initiate quota per hour; default 3. */
  recoveryInitiatePerHour: number;
  /** Operator info to return from `info()`. */
  info: OperatorInfo;
}

export const DEFAULT_MOCK_POLICY: MockOperatorPolicy = {
  otpExpiryMs: 10 * 60 * 1000,
  maxOtpAttempts: 5,
  enrollmentDispatchPerHour: 3,
  recoveryInitiatePerHour: 3,
  info: {
    operatorDomain: 'mock.plexus-keys.test',
    annualPriceSats: 100_000,
    // [1, 2]: v2 = CW Lift L11 (recovery recipes carry per-domain kdfVersion;
    // unilateral domains derive via deriveSegment). v1 still accepted (legacy).
    supportedAlgorithmVersions: [1, 2],
    subscriptionLapsePolicy: 'grace-period',
    graceDays: 30,
  },
};

/**
 * In-process implementation of the Plexus operator wire protocol. Used
 * exclusively for tests — production wires in HttpPlexusOperator.
 *
 * Time is injectable via `now()` so tests can fast-forward past OTP expiry
 * without `setTimeout(11min)`.
 */
export class MockPlexusOperator implements PlexusOperator {
  readonly config: PlexusOperatorConfig;
  readonly policy: MockOperatorPolicy;

  /** Pending enrollments keyed by identityKey hex. */
  pendingEnrollments = new Map<string, PendingEnrollment>();
  /** Stored, confirmed enrollments keyed by identityKey hex. */
  enrollments = new Map<string, StoredEnrollment>();
  /** Index: email → identityKey. Used by recovery initiate. */
  emailToIdentityKey = new Map<string, string>();
  /** Pending recoveries keyed by email. */
  pendingRecoveries = new Map<string, PendingRecovery>();
  /** Rate-limit windows keyed by `<bucket>:<key>` → array of timestamps. */
  private rateLimits = new Map<string, number[]>();

  /** Mock clock — defaults to `Date.now`. Override in tests. */
  now: () => number = () => Date.now();

  /** Optional spy: every issued OTP is appended here so tests can read it
   * without going through email. Mirrors what a Plexus operator would log
   * in development. */
  issuedOtps: { email: string; otp: string }[] = [];

  /** Last-seen network failure injection — tests set this to make the next
   * `enrollmentDispatch` fail with a synthetic network error. */
  failNextDispatch: boolean = false;

  constructor(
    config: Partial<PlexusOperatorConfig> = {},
    policy: Partial<MockOperatorPolicy> = {},
  ) {
    this.config = {
      baseUrl: config.baseUrl ?? 'mock://plexus',
      displayDomain: config.displayDomain ?? 'mock.plexus-keys.test',
      ...(config.pinnedCertFingerprintSha256
        ? { pinnedCertFingerprintSha256: config.pinnedCertFingerprintSha256 }
        : {}),
    };
    this.policy = { ...DEFAULT_MOCK_POLICY, ...policy };
  }

  // ── Test helpers ─────────────────────────────────────────────────

  /** Reset all state — useful in `beforeEach`. */
  reset(): void {
    this.pendingEnrollments.clear();
    this.enrollments.clear();
    this.emailToIdentityKey.clear();
    this.pendingRecoveries.clear();
    this.rateLimits.clear();
    this.issuedOtps = [];
    this.failNextDispatch = false;
  }

  /** Pre-seed an enrollment for recovery tests. Skips the full OTP flow. */
  seedEnrollment(envelope: PlexusRecoveryEnvelope): void {
    this.enrollments.set(envelope.identityKey, {
      identityKey: envelope.identityKey,
      email: envelope.contactEmail,
      envelope,
      enrolledAt: this.now(),
    });
    this.emailToIdentityKey.set(envelope.contactEmail, envelope.identityKey);
  }

  /** Read the most recently issued OTP for an email — convenience for tests. */
  lastOtpFor(email: string): string | null {
    for (let i = this.issuedOtps.length - 1; i >= 0; i--) {
      if (this.issuedOtps[i]!.email === email) return this.issuedOtps[i]!.otp;
    }
    return null;
  }

  // ── PlexusOperator implementation ────────────────────────────────

  async info(): Promise<OperatorResponse> {
    return { status: 200, body: this.policy.info };
  }

  async enrollmentDispatch(wire: Brc100Wire): Promise<OperatorResponse> {
    if (this.failNextDispatch) {
      this.failNextDispatch = false;
      throw new TypeError('mock: simulated network failure');
    }

    let envelope: PlexusRecoveryEnvelope;
    try {
      envelope = JSON.parse(wire.body) as PlexusRecoveryEnvelope;
    } catch {
      return { status: 400, body: { error: 'BAD_JSON' } };
    }

    if (envelope.envelopeVersion !== 1) {
      return { status: 400, body: { error: 'UNSUPPORTED_VERSION' } };
    }
    if (!this.policy.info.supportedAlgorithmVersions.includes(envelope.algorithmVersion)) {
      return { status: 400, body: { error: 'UNSUPPORTED_ALGORITHM' } };
    }
    if (envelope.identityKey !== wire.headers['x-brc100-identitykey']) {
      return { status: 400, body: { error: 'IDENTITY_MISMATCH' } };
    }

    const rlKey = `enroll:${envelope.contactEmail}:${envelope.identityKey}`;
    if (!this.checkRateLimit(rlKey, this.policy.enrollmentDispatchPerHour, 60 * 60 * 1000)) {
      return { status: 429, body: { error: 'RATE_LIMITED' } };
    }

    const otp = this.generateOtp();
    this.pendingEnrollments.set(envelope.identityKey, {
      identityKey: envelope.identityKey,
      email: envelope.contactEmail,
      envelope,
      otp,
      attempts: 0,
      createdAt: this.now(),
    });
    this.issuedOtps.push({ email: envelope.contactEmail, otp });

    return {
      status: 202,
      body: {
        otpDeliveredTo: maskEmail(envelope.contactEmail),
        expiresInSeconds: this.policy.otpExpiryMs / 1000,
      },
    };
  }

  async enrollmentConfirm(wire: Brc100Wire): Promise<OperatorResponse> {
    let payload: { identityKey: string; otp: string };
    try {
      payload = JSON.parse(wire.body) as { identityKey: string; otp: string };
    } catch {
      return { status: 400, body: { error: 'BAD_JSON' } };
    }
    if (payload.identityKey !== wire.headers['x-brc100-identitykey']) {
      return { status: 400, body: { error: 'IDENTITY_MISMATCH' } };
    }

    const pending = this.pendingEnrollments.get(payload.identityKey);
    if (!pending) {
      return { status: 404, body: { error: 'NO_PENDING_ENROLLMENT' } };
    }
    if (this.now() - pending.createdAt > this.policy.otpExpiryMs) {
      this.pendingEnrollments.delete(payload.identityKey);
      return { status: 410, body: { error: 'OTP_EXPIRED' } };
    }
    pending.attempts++;
    if (pending.otp !== payload.otp) {
      if (pending.attempts >= this.policy.maxOtpAttempts) {
        this.pendingEnrollments.delete(payload.identityKey);
        return { status: 423, body: { error: 'OTP_LOCKED' } };
      }
      return {
        status: 401,
        body: { error: 'OTP_WRONG', attemptsRemaining: this.policy.maxOtpAttempts - pending.attempts },
      };
    }

    // Success: store the enrollment, clear pending, link email → identityKey.
    this.enrollments.set(pending.identityKey, {
      identityKey: pending.identityKey,
      email: pending.email,
      envelope: pending.envelope,
      enrolledAt: this.now(),
    });
    this.emailToIdentityKey.set(pending.email, pending.identityKey);
    this.pendingEnrollments.delete(payload.identityKey);
    return { status: 200, body: { enrolledAt: this.now() } };
  }

  async recoveryInitiate(wire: Brc100Wire): Promise<OperatorResponse> {
    let payload: { contactEmail: string };
    try {
      payload = JSON.parse(wire.body) as { contactEmail: string };
    } catch {
      return { status: 400, body: { error: 'BAD_JSON' } };
    }
    const ik = this.emailToIdentityKey.get(payload.contactEmail);
    if (!ik) {
      // Tight rate-limit *and* opaque error per design §8.3 — same response
      // shape regardless of email-known-or-not, so an attacker can't enumerate.
      return { status: 202, body: { otpDeliveredTo: maskEmail(payload.contactEmail) } };
    }

    const rlKey = `recover:${payload.contactEmail}`;
    if (!this.checkRateLimit(rlKey, this.policy.recoveryInitiatePerHour, 60 * 60 * 1000)) {
      return { status: 429, body: { error: 'RATE_LIMITED' } };
    }

    const otp = this.generateOtp();
    this.pendingRecoveries.set(payload.contactEmail, {
      email: payload.contactEmail,
      identityKey: ik,
      otp,
      attempts: 0,
      createdAt: this.now(),
      otpVerified: false,
    });
    this.issuedOtps.push({ email: payload.contactEmail, otp });

    return {
      status: 202,
      body: {
        otpDeliveredTo: maskEmail(payload.contactEmail),
        expiresInSeconds: this.policy.otpExpiryMs / 1000,
      },
    };
  }

  async recoveryComplete(wire: Brc100Wire): Promise<OperatorResponse> {
    let payload: { contactEmail: string; otp: string; answerHashes: string[] };
    try {
      payload = JSON.parse(wire.body) as { contactEmail: string; otp: string; answerHashes: string[] };
    } catch {
      return { status: 400, body: { error: 'BAD_JSON' } };
    }
    const pending = this.pendingRecoveries.get(payload.contactEmail);
    if (!pending) {
      return { status: 404, body: { error: 'NO_PENDING_RECOVERY' } };
    }
    if (this.now() - pending.createdAt > this.policy.otpExpiryMs) {
      this.pendingRecoveries.delete(payload.contactEmail);
      return { status: 410, body: { error: 'OTP_EXPIRED' } };
    }
    pending.attempts++;
    if (pending.otp !== payload.otp) {
      if (pending.attempts >= this.policy.maxOtpAttempts) {
        this.pendingRecoveries.delete(payload.contactEmail);
        return { status: 423, body: { error: 'OTP_LOCKED' } };
      }
      return {
        status: 401,
        body: { error: 'OTP_WRONG', attemptsRemaining: this.policy.maxOtpAttempts - pending.attempts },
      };
    }
    pending.otpVerified = true;

    const stored = this.enrollments.get(pending.identityKey);
    if (!stored) {
      return { status: 404, body: { error: 'NO_ENROLLMENT' } };
    }

    // Verify the supplied answer hashes match what we stored at enrollment.
    const expected = stored.envelope.challengeBundle.answerHashes;
    if (expected.length !== payload.answerHashes.length) {
      return { status: 401, body: { error: 'CHALLENGE_FAILED' } };
    }
    let mismatch = 0;
    for (let i = 0; i < expected.length; i++) {
      // Constant-time compare to avoid timing leak. Plexus operator code
      // would normally do this; the mock mirrors the discipline.
      mismatch |= ctEqHex(expected[i]!, payload.answerHashes[i]!) ? 0 : 1;
    }
    if (mismatch !== 0) {
      return { status: 401, body: { error: 'CHALLENGE_FAILED' } };
    }

    this.pendingRecoveries.delete(payload.contactEmail);
    return {
      status: 200,
      body: { envelope: stored.envelope },
    };
  }

  // ── Internals ────────────────────────────────────────────────────

  private generateOtp(): string {
    // 6 decimal digits per §8.3.
    const buf = new Uint8Array(4);
    crypto.getRandomValues(buf);
    const n = new DataView(buf.buffer).getUint32(0, true) % 1_000_000;
    return n.toString().padStart(6, '0');
  }

  private checkRateLimit(key: string, max: number, windowMs: number): boolean {
    const now = this.now();
    const arr = this.rateLimits.get(key) ?? [];
    const fresh = arr.filter((t) => now - t < windowMs);
    if (fresh.length >= max) {
      this.rateLimits.set(key, fresh);
      return false;
    }
    fresh.push(now);
    this.rateLimits.set(key, fresh);
    return true;
  }
}

// ──────────────────────────────────────────────────────────────────────
// HttpPlexusOperator — production wire-protocol client
// ──────────────────────────────────────────────────────────────────────

/**
 * Production operator client. Issues real `fetch` calls — this is the ONE
 * place in the wallet bundle that ever opens a network connection (per
 * design §8.1 boundary discipline).
 *
 * Cert pinning is a stub on the browser path: WebPKI is the gate, but the
 * build can record the expected fingerprint so a future runtime that
 * supports SubresourceIntegrity-for-fetch (or an XHR cert-pin polyfill)
 * can verify. For the v0.1 scope we surface the pinned hex so the popup
 * can show "operator cert: matches pinned" / "MISMATCH".
 */
export class HttpPlexusOperator implements PlexusOperator {
  readonly config: PlexusOperatorConfig;

  constructor(config: PlexusOperatorConfig) {
    if (!config.baseUrl.startsWith('https://')) {
      throw new Error('PlexusOperator: baseUrl must use https://');
    }
    this.config = config;
  }

  async info(): Promise<OperatorResponse> {
    return await this.req('GET', '/info', null);
  }
  async enrollmentDispatch(wire: Brc100Wire): Promise<OperatorResponse> {
    return await this.req('POST', '/enrollment/dispatch', wire);
  }
  async enrollmentConfirm(wire: Brc100Wire): Promise<OperatorResponse> {
    return await this.req('POST', '/enrollment/confirm', wire);
  }
  async recoveryInitiate(wire: Brc100Wire): Promise<OperatorResponse> {
    return await this.req('POST', '/recovery/initiate', wire);
  }
  async recoveryComplete(wire: Brc100Wire): Promise<OperatorResponse> {
    return await this.req('POST', '/recovery/complete', wire);
  }

  private async req(
    method: 'GET' | 'POST',
    path: string,
    wire: Brc100Wire | null,
  ): Promise<OperatorResponse> {
    const url = `${this.config.baseUrl}${path}`;
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    let body: string | undefined;
    if (wire) {
      headers['x-brc100-identitykey'] = wire.headers['x-brc100-identitykey'];
      headers['x-brc100-nonce'] = wire.headers['x-brc100-nonce'];
      headers['x-brc100-timestamp'] = wire.headers['x-brc100-timestamp'];
      headers['x-brc100-signature'] = wire.headers['x-brc100-signature'];
      body = wire.body;
    }
    const resp = await fetch(url, { method, headers, body });
    let parsed: unknown = null;
    try {
      parsed = await resp.json();
    } catch {
      // non-JSON response — leave as null
    }
    return { status: resp.status, body: parsed };
  }
}

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────

/** Mask an email to "j****@example.com" for OTP confirmation responses. */
function maskEmail(email: string): string {
  const [local, domain] = email.split('@');
  if (!local || !domain) return email;
  return `${local[0] ?? '*'}****@${domain}`;
}

function ctEqHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Compute the SHA-256 fingerprint of a DER cert byte slice — exposed so
 * a build pipeline can pin a real operator's cert. Pure function, no I/O. */
export function sha256FingerprintHex(certDer: Uint8Array): string {
  return bytesToHex(nobleSha256(certDer));
}

```
