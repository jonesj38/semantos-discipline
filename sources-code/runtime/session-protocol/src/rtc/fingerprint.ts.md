---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/rtc/fingerprint.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.040941+00:00
---

# runtime/session-protocol/src/rtc/fingerprint.ts

```ts
/**
 * Fingerprint pin — RTC axis A, the distinguishing property.
 *
 * The differentiator the matrix exists to defend: a call is authenticated by
 * the contacts/PKI, not by trust in the signalling server. The mechanism:
 *
 *   1. The Jingle session-initiate / session-accept rides as the payload of a
 *      SignedBundle, so the sender's cert chain SIGNS OVER the SDP — including
 *      its DTLS `a=fingerprint`. The carrier (the merged XMPP node) verifies
 *      the bundle's signature + cert chain before this layer ever sees it.
 *   2. On arrival, S1 records (pins) that fingerprint, bound to the peer's
 *      cert id and the call's sid.
 *   3. When the real DTLS handshake happens in S3 (rtc.media), the certificate
 *      it presents has a fingerprint. Media proceeds ONLY if that observed
 *      fingerprint equals the pinned value.
 *
 * A tampered relay therefore cannot substitute its own media endpoint: it does
 * not hold the peer's cert key (so it cannot forge step 1's signature), and
 * any endpoint it inserts presents a different DTLS fingerprint (so step 3
 * rejects it). The brain is a relay it cannot MITM.
 *
 * This module owns steps 2 + 3. Step 1's bundle verification stays in the
 * carrier / brain (`runtime/semantos-brain/src/signed_bundle.zig`); S3's real
 * DTLS observation is a later slice. The verify gate is exposed now so S3 wires
 * straight into it.
 *
 * Cross-reference: docs/prd/RTC-ROADMAP.md §3 (the pin), docs/canon/rtc-matrix.yml
 * row S1 axis A + the access-grant convergence note in cross-matrix-index.md
 * (this is the *authentication* half of axis A; the *authorization* half is the
 * engine-checked access.grant).
 */

import type { DtlsFingerprint } from './jingle';

/** A recorded commitment: this peer's media endpoint must present this FP. */
export interface FingerprintPin {
  /** Call session id this pin belongs to. */
  sid: string;
  /** The peer cert id whose signed offer/answer carried the fingerprint. */
  peerCertId: string;
  /** The committed DTLS fingerprint. */
  fingerprint: DtlsFingerprint;
  /** When pinned (epoch ms) — injected clock, for deterministic tests. */
  pinnedAt: number;
}

/** Normalise a fingerprint for comparison (hash lowercase, value upper, no ws). */
function canon(fp: DtlsFingerprint): { hash: string; value: string } {
  return {
    hash: fp.hash.trim().toLowerCase(),
    value: fp.value.trim().toUpperCase().replace(/\s+/g, ''),
  };
}

/**
 * Compare an observed DTLS fingerprint (from the real handshake) against a pin.
 * Hash algorithm AND value must match; setup role is not part of identity.
 */
export function fingerprintsMatch(pinned: DtlsFingerprint, observed: DtlsFingerprint): boolean {
  const a = canon(pinned);
  const b = canon(observed);
  return a.hash === b.hash && a.value === b.value && a.value.length > 0;
}

/**
 * The per-node store of pins, keyed by sid. One pin per call: the peer commits
 * its endpoint fingerprint exactly once (in the offer if it is the initiator,
 * in the answer if the responder). A second, DIFFERENT commitment for the same
 * sid is a tamper signal and is rejected.
 */
export class FingerprintPinStore {
  private readonly pins = new Map<string, FingerprintPin>();
  private readonly now: () => number;

  constructor(opts: { now?: () => number } = {}) {
    this.now = opts.now ?? (() => Date.now());
  }

  /**
   * Pin the peer's fingerprint for a call. Idempotent if the same value is
   * re-committed (retransmit). Throws on a conflicting re-commit (tamper).
   */
  pin(sid: string, peerCertId: string, fingerprint: DtlsFingerprint): FingerprintPin {
    const existing = this.pins.get(sid);
    if (existing) {
      if (existing.peerCertId !== peerCertId) {
        throw new Error(
          `FingerprintPin: sid ${sid} already pinned to ${existing.peerCertId}, refusing re-pin to ${peerCertId}`,
        );
      }
      if (!fingerprintsMatch(existing.fingerprint, fingerprint)) {
        throw new Error(`FingerprintPin: conflicting fingerprint re-commit for sid ${sid} (tamper signal)`);
      }
      return existing;
    }
    const rec: FingerprintPin = { sid, peerCertId, fingerprint, pinnedAt: this.now() };
    this.pins.set(sid, rec);
    return rec;
  }

  /** The pin for a call, if any. */
  get(sid: string): FingerprintPin | undefined {
    return this.pins.get(sid);
  }

  /**
   * The media admission gate. Returns true iff a fingerprint was pinned for
   * this call AND the observed DTLS fingerprint matches it. A call with no pin
   * is rejected (fail-closed) — we never let an unauthenticated endpoint
   * through.
   */
  verify(sid: string, observed: DtlsFingerprint): boolean {
    const pin = this.pins.get(sid);
    if (!pin) return false;
    return fingerprintsMatch(pin.fingerprint, observed);
  }

  /** Drop a pin (call ended). */
  clear(sid: string): void {
    this.pins.delete(sid);
  }
}

```
