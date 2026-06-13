---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/identity-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.825699+00:00
---

# archive/apps-world-client/src/identity-provider.ts

```ts
/**
 * IdentityProvider — pluggable interface for BRC-52 cert + BRC-42 signing.
 *
 * Spec source:   docs/spec/protocol-v0.5.md §4 (Identity), §12.1 (SignedBundle).
 * Canonical terms: cert (glossary id: brc-52), signed-bundle (glossary id:
 *   signed-bundle), BRC-100 (glossary id: brc-100), BRC-42 (glossary id: brc-42).
 *
 * W1.5C-1: The canonical `IdentityProvider` interface and `Brc52Cert` type are
 * now defined in @semantos/protocol-types. This file:
 *   1. Re-exports them for backward compat (callers importing from this module
 *      still compile without changes).
 *   2. Provides `EphemeralIdentityProvider` — the D-A2 development/fallback
 *      implementation that generates an ephemeral secp256k1 keypair.
 *
 * BRC compliance:
 *   BRC-100 — signed-request standard (every cross-process message)
 *   BRC-52  — certificate format (cert_id = SHA-256(canonical_preimage))
 *   BRC-42  — key derivation (D-A3 will derive the signing child key)
 */

import { PrivateKey, Hash, Signature } from "@bsv/sdk";
import type { IdentityProvider, Brc52Cert } from "@semantos/protocol-types";

// ── Re-exports from canonical home ────────────────────────────────────────────
// Backcompat: callers that `import type { IdentityProvider } from "./identity-provider"`
// continue to resolve the same type (structurally identical, same canonical source).

export type {
  IdentityProvider,
  Brc52Cert,
  /** @deprecated Use Brc52Cert — canonical alias exported from @semantos/protocol-types */
  Brc52Certificate,
} from "@semantos/protocol-types";

// ── Shared crypto helpers ──────────────────────────────────────────────────────

/** SHA-256 a Uint8Array; returns as a lowercase hex string. */
function sha256Hex(data: Uint8Array): string {
  const digest = Hash.sha256(Array.from(data)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** SHA-256 a UTF-8 string; returns as a lowercase hex string. */
function sha256String(s: string): string {
  return sha256Hex(new TextEncoder().encode(s));
}

/**
 * Compute the BRC-52 cert_id from the canonical preimage.
 *
 * Per §4.2: cert_id = SHA-256(canonical JSON of {certifierPublicKey, fields,
 * serialNumber, subjectPublicKey, type} — sorted keys, no certId or signature).
 *
 * Note: the canonical implementation is now `computeCertId` from
 * @semantos/protocol-types. This local helper is kept for use inside
 * EphemeralIdentityProvider to avoid a circular dependency.
 */
export function computeBrc52CertId(
  subjectPublicKey: string,
  certifierPublicKey: string,
  type: string,
  serialNumber: string,
  fields: Record<string, string>,
): string {
  const preimageObj = {
    certifierPublicKey,
    fields,
    serialNumber,
    subjectPublicKey,
    type,
  };
  // Deterministic: sorted keys at every level, no whitespace.
  const json = JSON.stringify(preimageObj, (_k, v: unknown) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const key of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[key] = (v as Record<string, unknown>)[key];
      }
      return sorted;
    }
    return v;
  });
  return sha256Hex(new TextEncoder().encode(json));
}

/**
 * Compute the BRC-52 issuer preimage for signing (includes certId).
 *
 * Per §4.2: the certifier signs the canonical JSON of
 * {certId, certifierPublicKey, fields, serialNumber, subjectPublicKey, type}.
 */
export function computeBrc52IssuerPreimage(
  certId: string,
  subjectPublicKey: string,
  certifierPublicKey: string,
  type: string,
  serialNumber: string,
  fields: Record<string, string>,
): Uint8Array {
  const preimageObj = {
    certId,
    certifierPublicKey,
    fields,
    serialNumber,
    subjectPublicKey,
    type,
  };
  const json = JSON.stringify(preimageObj, (_k, v: unknown) => {
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
 * Sign bytes with a PrivateKey using SHA-256 + ECDSA (canonical low-S).
 * Returns a DER-encoded signature as a hex string.
 */
function signWithKey(privKey: PrivateKey, bytes: Uint8Array): string {
  const digestArr = Hash.sha256(Array.from(bytes)) as number[];
  const digestHex = digestArr.map((b) => b.toString(16).padStart(2, "0")).join("");
  const sig: Signature = privKey.sign(digestHex, "hex", true);
  const der = sig.toDER() as number[];
  return der.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── EphemeralIdentityProvider ──────────────────────────────────────────────────

/**
 * EphemeralIdentityProvider — development/fallback implementation.
 *
 * Generates a fresh secp256k1 keypair on construction. Issues a self-certified
 * BRC-52 certificate (certifierPublicKey == subjectPublicKey).
 *
 * Implements the canonical `IdentityProvider` from @semantos/protocol-types.
 *
 * This MUST NOT be used in production — the cert has no Plexus attestation
 * chain and cannot be validated against the Plexus identity DAG.
 *
 * D-A3 (Helm) MUST replace this with a PlexusIdentityProvider that:
 *   - Sources the root key from PBKDF2 over the user's email + challenge set.
 *   - Derives a session child key via BRC-42 (`deriveChildKey`).
 *   - Uses a cert issued by the Plexus CA (certifierPublicKey = Plexus CA key).
 *
 * Spec source: docs/spec/protocol-v0.5.md §4, §12.1.
 * BRC compliance: BRC-42 (key derivation — ephemeral; D-A3 supplies real derivation).
 */
export class EphemeralIdentityProvider implements IdentityProvider {
  private readonly privKey: PrivateKey;
  private readonly cert: Brc52Cert;
  private readonly identityKeyHex: string;

  constructor() {
    // Generate a fresh ephemeral secp256k1 keypair.
    this.privKey = PrivateKey.fromRandom();
    const pubKey = this.privKey.toPublicKey();
    // 33-byte compressed DER public key as hex.
    const pubKeyHex = (pubKey.encode(true) as number[])
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
    this.identityKeyHex = pubKeyHex;

    // Serial: deterministic from the public key hex.
    const serialNumber = sha256String(`ephemeral:serial:${pubKeyHex}`);

    // cert_id = SHA-256 of canonical preimage (self-certified).
    const certId = computeBrc52CertId(
      pubKeyHex,
      pubKeyHex, // self-certified: certifier == subject
      "semantos.world-client.ephemeral",
      serialNumber,
      { role: "ephemeral-session" },
    );

    // Certifier signature over the issuer preimage (self-signed).
    const issuerPreimage = computeBrc52IssuerPreimage(
      certId,
      pubKeyHex,
      pubKeyHex,
      "semantos.world-client.ephemeral",
      serialNumber,
      { role: "ephemeral-session" },
    );
    const signature = signWithKey(this.privKey, issuerPreimage);

    this.cert = {
      certId,
      subjectPublicKey: pubKeyHex,
      certifierPublicKey: pubKeyHex,
      type: "semantos.world-client.ephemeral",
      serialNumber,
      fields: { role: "ephemeral-session" },
      signature,
    };
  }

  getCert(): Brc52Cert {
    return this.cert;
  }

  getCertId(): string {
    return this.cert.certId;
  }

  getIdentityKeyHex(): string {
    return this.identityKeyHex;
  }

  sign(bytes: Uint8Array): string {
    return signWithKey(this.privKey, bytes);
  }
}

```
