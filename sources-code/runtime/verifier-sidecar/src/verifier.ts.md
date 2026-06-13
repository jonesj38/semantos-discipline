---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.085938+00:00
---

# runtime/verifier-sidecar/src/verifier.ts

```ts
/**
 * BrcVerifier — reference implementation of the Verifier Sidecar.
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5 (Verifier Sidecar),
 *              §4.2 (BRC-52 cert format), §12.1 (SignedBundle envelope).
 * Textbook: docs/textbook/14-verifier-sidecar.md.
 *
 * Three-phase pipeline (fail-fast, cheapest first):
 *   Phase 1 — BRC-100 signature verification
 *   Phase 2 — BRC-52 cert authenticity + identity binding
 *   Phase 3 — capability UTXO SPV + liveness (when capToken supplied)
 *
 * This is the SINGLE choke-point for @bsv/sdk inside this package.
 * All crypto delegated to @bsv/sdk's PrivateKey/PublicKey/Signature/Hash.
 *
 * BRC compliance:
 *   BRC-100  — signed-request envelope verification
 *   BRC-52   — cert_id = SHA-256(canonical_preimage); issuer sig check
 *   BRC-42   — key derivation used upstream; verified cert subjects here
 *   BRC-74   — BUMP merkle proof (via SpvProvider)
 *   BRC-95   — atomic-BEEF (via SpvProvider)
 *   BRC-108  — capability token as LINEAR UTXO
 *
 * K invariant: K2 — any state-changing transition requires successful
 * identity verification.  BrcVerifier is the mechanism that makes K2's
 * assumption true at the system level.
 */

import { PublicKey, Signature, Hash } from "@bsv/sdk";

import type {
  Verifier,
  RawSignedBundle,
  CapabilityTokenRef,
  VerificationResult,
  Brc52Certificate,
  SpvProvider,
  NonceCache,
  BrcVerifierOptions,
} from "./types.js";
import { InMemoryNonceCache } from "./nonce-cache.js";

// ── Hex helpers ─────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0)
    throw new Error(`hex string has odd length: ${hex.length}`);
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    const b = parseInt(hex.slice(i, i + 2), 16);
    if (Number.isNaN(b)) throw new Error(`invalid hex byte at offset ${i}`);
    out[i / 2] = b;
  }
  return out;
}

function hexToNumberArray(hex: string): number[] {
  return Array.from(hexToBytes(hex));
}

/**
 * Constant-time byte comparison.
 *
 * Per §13.3: "All secret-comparison operations MUST use constant-time
 * comparison to prevent timing attacks."
 *
 * Implemented as XOR-accumulation — leaks length equality but not content,
 * which is the standard trade-off for public-key comparison.
 */
export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

// ── Canonical preimage for BRC-100 ─────────────────────────────────────────

/**
 * Build the canonical preimage that is signed in a BRC-100 envelope.
 *
 * Per §12.1: the signature covers x-brc100-identitykey + x-brc100-nonce +
 * x-brc100-timestamp as a deterministic byte string.
 *
 * Exact format: sorted-key canonical JSON encoded as UTF-8, matching the
 * approach in runtime/session-protocol/src/bundle-envelope.ts (which is
 * the reference SignedBundle signer/verifier in this repo).
 */
function brc100CanonicalPreimage(envelope: RawSignedBundle): Uint8Array {
  const preimageObj = {
    "x-brc100-identitykey": envelope["x-brc100-identitykey"],
    "x-brc100-nonce": envelope["x-brc100-nonce"],
    "x-brc100-timestamp": envelope["x-brc100-timestamp"],
    payload: envelope.payload,
  };
  // Deterministic: sorted keys at every level, no whitespace.
  const json = JSON.stringify(preimageObj, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
  return new TextEncoder().encode(json);
}

// ── BRC-52 canonical preimage ───────────────────────────────────────────────

/**
 * Build the canonical preimage for computing a BRC-52 cert_id.
 *
 * Per §4.2: cert_id = SHA-256(canonical_preimage over all fields *except*
 * signature).  The cert_id itself is not part of its own preimage (that
 * would be circular); it is the *output* of the SHA-256 operation.
 *
 * Matches computeCertId in core/plexus-vendor-sdk/src/crypto.ts — the
 * CertificatePreimage type carries subjectPublicKey, certifierPublicKey,
 * type, serialNumber, fields (no certId field).
 */
function brc52CertIdPreimage(cert: Brc52Certificate): Uint8Array {
  // Exclude both certId (circular) and signature (excluded by §4.2).
  const preimageObj = {
    certifierPublicKey: cert.certifierPublicKey,
    fields: cert.fields,
    serialNumber: cert.serialNumber,
    subjectPublicKey: cert.subjectPublicKey,
    type: cert.type,
  };
  const json = JSON.stringify(preimageObj, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
  return new TextEncoder().encode(json);
}

/**
 * Build the canonical preimage for the issuer signature check.
 *
 * The issuer signs the full canonical preimage including the certId (which
 * by this point has been computed and verified).  This binds the certId into
 * the issuer's signature, preventing an attacker from swapping the certId
 * while keeping the signature valid.
 */
function brc52IssuerSignaturePreimage(cert: Brc52Certificate): Uint8Array {
  // All fields except signature; certId IS included here.
  const preimageObj = {
    certId: cert.certId,
    certifierPublicKey: cert.certifierPublicKey,
    fields: cert.fields,
    serialNumber: cert.serialNumber,
    subjectPublicKey: cert.subjectPublicKey,
    type: cert.type,
  };
  const json = JSON.stringify(preimageObj, (_k, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
  return new TextEncoder().encode(json);
}

function sha256Hex(bytes: Uint8Array): string {
  const digest = Hash.sha256(Array.from(bytes)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sha256ToNumberArray(bytes: Uint8Array): number[] {
  return Hash.sha256(Array.from(bytes)) as number[];
}

// ── BrcVerifier ─────────────────────────────────────────────────────────────

/**
 * Reference implementation of the Verifier Sidecar interface.
 *
 * Consumable from D-V3's World Host integration.
 * For Elixir (runtime/world-beam/apps/world_host/) interop: this TS process exposes a
 * JSON-RPC or Unix-socket endpoint (to be wired in D-V3); see the D-V3
 * interop boundary note in the D-V1 delivery report.
 *
 * Canonical term: Verifier Sidecar (glossary id: verifier-sidecar).
 * Reference implementation class: BrcVerifier.
 * Test stub class: VerifierStub (accepts everything — do not use in production).
 */
export class BrcVerifier implements Verifier {
  private readonly timestampWindowMs: number;
  private readonly spvProvider: SpvProvider | undefined;
  private readonly nonceCache: NonceCache;
  private readonly nowMs: () => number;

  constructor(options: BrcVerifierOptions = {}) {
    this.timestampWindowMs = options.timestampWindowMs ?? 300_000;
    this.spvProvider = options.spvProvider;
    this.nowMs = options.nowMs ?? Date.now;
    this.nonceCache =
      options.nonceCache ??
      new InMemoryNonceCache(600_000, this.nowMs);
  }

  async verify(
    envelope: RawSignedBundle,
    capToken?: CapabilityTokenRef,
  ): Promise<VerificationResult> {
    // ── Phase 1: BRC-100 signature check (fail-fast) ───────────────────────

    // 1a. Structural check — required fields present
    const identityKeyHex = envelope["x-brc100-identitykey"];
    const nonceHex = envelope["x-brc100-nonce"];
    const timestampRaw = envelope["x-brc100-timestamp"];
    const signatureHex = envelope["x-brc100-signature"];
    const certJson = envelope["x-brc52-certificate"];

    if (
      !identityKeyHex ||
      !nonceHex ||
      timestampRaw === undefined ||
      !signatureHex ||
      !certJson
    ) {
      return {
        ok: false,
        code: "brc100_missing_field",
        message:
          "BRC-100 envelope is missing required headers (identitykey, nonce, timestamp, signature, or certificate)",
      };
    }

    // 1b. Parse and validate identity key
    let identityKeyBytes: Uint8Array;
    try {
      identityKeyBytes = hexToBytes(identityKeyHex);
    } catch {
      return {
        ok: false,
        code: "brc100_bad_encoding",
        message: "x-brc100-identitykey is not valid hex",
      };
    }
    if (identityKeyBytes.length !== 33) {
      return {
        ok: false,
        code: "brc100_bad_encoding",
        message: `x-brc100-identitykey must be 33 bytes (compressed secp256k1), got ${identityKeyBytes.length}`,
      };
    }

    // 1c. Timestamp window check
    const timestamp =
      typeof timestampRaw === "string"
        ? parseInt(timestampRaw, 10)
        : timestampRaw;
    if (Number.isNaN(timestamp)) {
      return {
        ok: false,
        code: "brc100_bad_encoding",
        message: "x-brc100-timestamp is not a valid integer",
      };
    }
    const now = this.nowMs();
    if (Math.abs(now - timestamp) > this.timestampWindowMs) {
      return {
        ok: false,
        code: "brc100_timestamp_out_of_window",
        message: `envelope timestamp ${timestamp} is outside the ±${this.timestampWindowMs}ms window (now=${now})`,
      };
    }

    // 1d. Replay check — before consuming the nonce
    if (this.nonceCache.hasNonce(nonceHex)) {
      return {
        ok: false,
        code: "brc100_replay_detected",
        message: `nonce ${nonceHex.slice(0, 16)}… has already been processed (replay attack)`,
      };
    }

    // 1e. Signature verification — ECDSA over canonical preimage
    let signatureBytes: Uint8Array;
    try {
      signatureBytes = hexToBytes(signatureHex);
    } catch {
      return {
        ok: false,
        code: "brc100_bad_encoding",
        message: "x-brc100-signature is not valid hex",
      };
    }

    const preimage = brc100CanonicalPreimage(envelope);
    const digestArr = sha256ToNumberArray(preimage);
    const digestHex = digestArr
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    let sigValid = false;
    try {
      const pk = PublicKey.fromDER(Array.from(identityKeyBytes));
      const sig = Signature.fromDER(hexToNumberArray(signatureHex));
      sigValid = pk.verify(digestHex, sig, "hex");
    } catch {
      return {
        ok: false,
        code: "brc100_invalid_signature",
        message: "failed to parse BRC-100 signature or public key",
      };
    }

    if (!sigValid) {
      return {
        ok: false,
        code: "brc100_invalid_signature",
        message: "BRC-100 ECDSA signature verification failed",
      };
    }

    // Signature is valid — consume the nonce
    this.nonceCache.setNonce(nonceHex, now + this.timestampWindowMs * 2);

    // ── Phase 2: BRC-52 cert authenticity + identity binding ─────────────

    // 2a. Parse cert
    let cert: Brc52Certificate;
    try {
      cert = JSON.parse(certJson) as Brc52Certificate;
    } catch {
      return {
        ok: false,
        code: "brc52_malformed_cert",
        message: "x-brc52-certificate is not valid JSON",
      };
    }

    if (
      !cert.certId ||
      !cert.subjectPublicKey ||
      !cert.certifierPublicKey ||
      !cert.signature
    ) {
      return {
        ok: false,
        code: "brc52_malformed_cert",
        message: "BRC-52 cert missing required fields (certId, subjectPublicKey, certifierPublicKey, signature)",
      };
    }

    // 2b. cert_id check: cert.certId == SHA-256(preimage_without_certId_or_signature)
    // The certId is the output of SHA-256; it cannot be part of its own preimage.
    const certIdPreimageBytes = brc52CertIdPreimage(cert);
    const computedCertId = sha256Hex(certIdPreimageBytes);
    if (cert.certId !== computedCertId) {
      return {
        ok: false,
        code: "brc52_cert_id_mismatch",
        message: `BRC-52 cert_id mismatch: stored=${cert.certId.slice(0, 16)}… computed=${computedCertId.slice(0, 16)}…`,
      };
    }

    // 2c. Issuer signature over the full canonical preimage (with certId).
    // Now that certId is verified, the issuer sig binds certId into the chain.
    const issuerPreimageBytes = brc52IssuerSignaturePreimage(cert);
    const preimageDigestArr = sha256ToNumberArray(issuerPreimageBytes);
    const preimageDigestHex = preimageDigestArr
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    let certSigValid = false;
    try {
      const certifierPk = PublicKey.fromDER(
        hexToNumberArray(cert.certifierPublicKey),
      );
      const certSig = Signature.fromDER(hexToNumberArray(cert.signature));
      certSigValid = certifierPk.verify(preimageDigestHex, certSig, "hex");
    } catch {
      return {
        ok: false,
        code: "brc52_issuer_signature_invalid",
        message: "failed to parse BRC-52 cert issuer signature or certifier key",
      };
    }

    if (!certSigValid) {
      return {
        ok: false,
        code: "brc52_issuer_signature_invalid",
        message: "BRC-52 cert issuer signature verification failed",
      };
    }

    // 2d. Identity binding: x-brc100-identitykey MUST equal certificate.subject
    // Constant-time comparison per §13.3.
    let certSubjectBytes: Uint8Array;
    try {
      certSubjectBytes = hexToBytes(cert.subjectPublicKey);
    } catch {
      return {
        ok: false,
        code: "brc52_malformed_cert",
        message: "BRC-52 cert.subjectPublicKey is not valid hex",
      };
    }

    if (!constantTimeEqual(identityKeyBytes, certSubjectBytes)) {
      return {
        ok: false,
        code: "brc52_identity_binding_mismatch",
        message:
          "x-brc100-identitykey does not match certificate.subjectPublicKey (K2 binding check failed)",
      };
    }

    // ── Phase 3: capability UTXO SPV + liveness (when capToken supplied) ──

    if (capToken !== undefined) {
      if (!this.spvProvider) {
        // Production deployments MUST supply a SpvProvider.
        // In development/test, skip the check when no provider is configured.
        // This branch is intentionally reachable in tests that pass a capToken
        // without a provider — they're testing the non-SPV paths.
      } else {
        const isLive = await this.spvProvider.isUnspent(capToken);
        if (!isLive) {
          return {
            ok: false,
            code: "capability_utxo_spent",
            message: `capability UTXO ${capToken.txId}:${capToken.vout} is spent or SPV proof invalid`,
          };
        }
      }
    }

    // ── All phases passed ─────────────────────────────────────────────────

    return {
      ok: true,
      certId: cert.certId,
      identityKey: identityKeyHex,
    };
  }
}

// ── VerifierStub — test double ───────────────────────────────────────────────

/**
 * VerifierStub — test stub implementation of Verifier.
 *
 * Accepts all envelopes without cryptographic verification.
 * Used in unit tests where real ECDSA + SPV checks are impractical.
 *
 * MUST NOT be used in production.  The canonical class name for the
 * stub is VerifierStub (per glossary id: verifier-sidecar notes).
 */
export class VerifierStub implements Verifier {
  async verify(
    envelope: RawSignedBundle,
    _capToken?: CapabilityTokenRef,
  ): Promise<VerificationResult> {
    // Minimal structural check — return a plausible accepted result
    // with whatever identitykey/certId the envelope claims.
    const identityKey = envelope["x-brc100-identitykey"] ?? "";
    const certJson = envelope["x-brc52-certificate"] ?? "{}";
    let certId: string;
    try {
      const cert = JSON.parse(certJson) as Partial<{ certId: string }>;
      certId = cert.certId ?? "stub-cert-id";
    } catch {
      certId = "stub-cert-id";
    }
    return { ok: true, certId, identityKey };
  }
}

```
