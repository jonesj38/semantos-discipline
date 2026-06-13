---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/license-handshake.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.332141+00:00
---

# runtime/ws-node-adapter/src/license-handshake.ts

```ts
/**
 * license-handshake — exchange + verify logic for the first frame of a
 * WsNodeAdapter connection.
 *
 * Both ends of a connection send one `LicenseHandshakeFrame`. The
 * handshake proves:
 *
 *   1. The sender holds a valid license issued by an acceptable issuer.
 *   2. The sender actually controls the holder private key (not just
 *      replaying someone else's license bytes).
 *   3. The sender's self-declared BCA matches what's derivable from the
 *      license's holder pubkey.
 *
 * The module does NOT touch transport. It operates on frames and returns
 * verdicts. The per-peer connection class in `ws-peer-connection.ts`
 * wires that into the WebSocket state machine.
 */

import { randomBytes } from "node:crypto";
import type { Signer, Verifier } from "@semantos/session-protocol";
import {
  decodeLicense,
  verifyLicense,
  type License,
} from "@semantos/protocol-types/license";
import { handshakeSigPayload } from "./codec.js";
import { FRAME_KIND, type LicenseHandshakeFrame } from "./types.js";

// ---------------------------------------------------------------------------
// buildHandshakeFrame
// ---------------------------------------------------------------------------

export interface BuildHandshakeFrameParams {
  /** The holder's Signer. Signs the handshake payload. */
  signer: Signer;
  /** Encoded license bytes (output of `encodeLicense(license)`). */
  licenseBytes: Uint8Array;
  /**
   * The holder's self-declared BCA. The recipient cross-checks this
   * against a derivation of `license.pubkey` and drops mismatches.
   */
  claimedBca: string;
  /**
   * Optional explicit challenge bytes. Defaults to 32 fresh random bytes.
   * Tests override this to produce deterministic frames.
   */
  challenge?: Uint8Array;
}

/**
 * Construct a signed `LicenseHandshakeFrame`. The sender signs
 * `challenge || sha256(licenseBytes)` with the holder private key.
 */
export async function buildHandshakeFrame(
  params: BuildHandshakeFrameParams,
): Promise<LicenseHandshakeFrame> {
  const challenge = params.challenge ?? new Uint8Array(randomBytes(32));
  const payload = handshakeSigPayload(challenge, params.licenseBytes);
  const sig = await params.signer.sign(payload);
  return {
    kind: FRAME_KIND.LICENSE_HANDSHAKE,
    license: params.licenseBytes,
    sig,
    challenge,
    claimedBca: params.claimedBca,
  };
}

// ---------------------------------------------------------------------------
// verifyHandshakeFrame
// ---------------------------------------------------------------------------

export interface HandshakeVerifyConfig {
  /** ECDSA verifier — typically `BsvSdkVerifier` from session-protocol. */
  verifier: Verifier;
  /**
   * Expected BCA for a given holder pubkey. Called once per verification
   * with `license.pubkey`; the result must equal `frame.claimedBca` or
   * the verdict is `bca-mismatch`. Omit to skip the BCA check.
   */
  deriveBcaFromPubkey?: (pubkey: Uint8Array) => Promise<string>;
  /**
   * Production policy gate for which issuers are acceptable. Returning
   * `false` yields `issuer-rejected`. Omit to accept any cryptographically
   * valid issuer — useful when the gate is enforced upstream (e.g. in
   * runtime/node's boot policy).
   */
  isAcceptableIssuer?: (issuerPubkey: Uint8Array) => boolean;
  /** Override current time (unix seconds) for license expiry checks. */
  now?: number;
}

export type HandshakeVerdict =
  | {
      ok: true;
      license: License;
      peerBca: string;
      peerPubkey: Uint8Array;
    }
  | {
      ok: false;
      reason:
        | "malformed"
        | "license-invalid"
        | "license-expired"
        | "issuer-rejected"
        | "bca-mismatch"
        | "sig-invalid";
      detail?: string;
    };

/**
 * Check that a handshake frame is cryptographically valid, the license
 * meets policy, and the claimed BCA is consistent with the holder pubkey.
 *
 * Check order (fail-fast, low-cost → high-cost):
 *   1. Decode the license envelope.
 *   2. Verify license issuer sig + expiry (`verifyLicense`).
 *   3. Apply `isAcceptableIssuer` policy.
 *   4. Cross-check `claimedBca` against `deriveBcaFromPubkey(license.pubkey)`.
 *   5. Verify handshake sig was made by `license.pubkey` over
 *      `challenge || sha256(licenseBytes)`.
 */
export async function verifyHandshakeFrame(
  frame: LicenseHandshakeFrame,
  cfg: HandshakeVerifyConfig,
): Promise<HandshakeVerdict> {
  // 1. Decode the license.
  let license: License;
  try {
    license = decodeLicense(frame.license);
  } catch (e) {
    return {
      ok: false,
      reason: "malformed",
      detail: (e as Error).message,
    };
  }

  // 2. Verify the license itself.
  const lv = await verifyLicense(license, cfg.verifier, { now: cfg.now });
  if (!lv.ok) {
    if (lv.reason === "expired") {
      return { ok: false, reason: "license-expired", detail: lv.detail };
    }
    return { ok: false, reason: "license-invalid", detail: lv.detail };
  }

  // 3. Issuer acceptability policy.
  if (cfg.isAcceptableIssuer && !cfg.isAcceptableIssuer(license.issuer)) {
    return { ok: false, reason: "issuer-rejected" };
  }

  // 4. BCA binding.
  if (cfg.deriveBcaFromPubkey) {
    const derived = await cfg.deriveBcaFromPubkey(license.pubkey);
    if (derived !== frame.claimedBca) {
      return {
        ok: false,
        reason: "bca-mismatch",
        detail: `claimed ${frame.claimedBca}, derived ${derived}`,
      };
    }
  }

  // 5. Handshake sig: signed by license.pubkey over challenge||hash(license).
  const payload = handshakeSigPayload(frame.challenge, frame.license);
  const sigOk = await cfg.verifier.verify(license.pubkey, payload, frame.sig);
  if (!sigOk) {
    return { ok: false, reason: "sig-invalid" };
  }

  return {
    ok: true,
    license,
    peerBca: frame.claimedBca,
    peerPubkey: license.pubkey,
  };
}

```
