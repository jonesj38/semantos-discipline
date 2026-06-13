---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bundle-envelope.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.037667+00:00
---

# runtime/session-protocol/src/bundle-envelope.ts

```ts
/**
 * Signed-bundle envelope — a generic wrapper that lets any payload
 * travel across party boundaries with cryptographic provenance.
 *
 * The federation story from Slice 4 proved that a `DocumentBundle`
 * round-trip preserves per-patch lexicon attribution. But the bundle
 * itself arrived over an in-process JSON channel — nothing prevented
 * a receiver from inventing patches and claiming another party
 * authored them. `SignedBundle<T>` closes that gap: sign the payload
 * once at export time, verify at import time. Receivers who don't
 * trust the signer's identity reject the bundle before it touches
 * their state.
 *
 * This module is domain-neutral on purpose — `DocumentBundle`,
 * `SessionDescriptor`, the conversation-patch-chain federation bundle
 * from Slice 4, all ride this envelope. The payload type is
 * generic; the envelope only cares that it serialises to stable
 * canonical bytes.
 *
 * Wire format:
 *
 *   {
 *     version: 1,
 *     payload: <T>,
 *     signedAt: <ISO timestamp>,
 *     signer: { bca, pubkeyHex, certId? },
 *     signature: <hex DER-encoded ECDSA signature>,
 *   }
 *
 * Signed preimage:
 *
 *   canonicalJson({ payload, signedAt, signerPubkeyHex }) as UTF-8 bytes
 *
 * The signature excludes itself and the wrapper-version field.
 * Bumping `version` is a breaking change; receivers on version N must
 * reject N+1 bundles unless they've been upgraded.
 */

import type { Signer, Verifier } from "./signer.js";
import type { Identity } from "./types.js";

// ── Types ──────────────────────────────────────────────────────

/** The only bundle-envelope version currently defined. */
export const SIGNED_BUNDLE_VERSION = 1 as const;

export interface SignedBundle<T> {
  /** Envelope format version. Bumped only for breaking wire changes. */
  version: typeof SIGNED_BUNDLE_VERSION;
  /** The signed payload — opaque to the envelope. */
  payload: T;
  /** ISO 8601 timestamp, μs precision. Part of the signed preimage. */
  signedAt: string;
  /** Signer identity (Identity with hex-encoded pubkey for wire format). */
  signer: SignerIdentity;
  /**
   * Slice 5c: optional recipient the sender addressed this bundle to.
   * When set, it's part of the signed preimage — so a forger can't
   * retarget a bundle by swapping the recipient field. Receivers can
   * verify they're the intended audience via
   * `expectedRecipientCertId` / `expectedRecipientBca`.
   *
   * Leaving this field undefined produces a broadcast bundle (legacy
   * 5a/5b shape) — no address check runs.
   */
  recipient?: RecipientIdentity;
  /** Hex-encoded DER ECDSA signature over the canonical preimage. */
  signature: string;
}

/** Identity as it appears in a SignedBundle on the wire. Hex-encoded for JSON-friendliness. */
export interface SignerIdentity {
  /** IPv6 string derived from the pubkey. */
  bca: string;
  /** 33-byte compressed secp256k1 public key, hex-encoded. */
  pubkeyHex: string;
  /** Plexus cert SHA256 when available. */
  certId?: string;
}

/** Who the bundle is addressed to. At least one field must be set. */
export interface RecipientIdentity {
  /** Plexus cert SHA256 of the intended recipient. */
  certId?: string;
  /** IPv6 BCA of the intended recipient. */
  bca?: string;
  /** 33-byte compressed secp256k1 public key of the recipient, hex-encoded. */
  pubkeyHex?: string;
}

/** Result of verifying a signed bundle. Never throws — always returns a discriminated result. */
export type VerifyResult<T> =
  | {
      ok: true;
      payload: T;
      signer: SignerIdentity;
      signedAt: string;
      /** Slice 5c: present iff the bundle carried a `recipient` field. */
      recipient?: RecipientIdentity;
    }
  | { ok: false; code: VerifyErrorCode; message: string };

export type VerifyErrorCode =
  | "unsupported_version"
  | "bad_preimage"
  | "bad_signature_encoding"
  | "invalid_signature"
  | "pubkey_mismatch"
  | "expected_signer_mismatch"
  | "expected_recipient_mismatch"
  | "unaddressed_bundle";

// ── Canonical JSON ─────────────────────────────────────────────

/**
 * Deterministic JSON serialisation — sorted keys at every object
 * level, arrays in given order, no whitespace. Produces the exact
 * same bytes for the same logical value regardless of construction
 * order. Uint8Array fields that sneak into `T` will serialise as
 * arbitrary arrays — callers are responsible for converting bytes
 * to hex strings in their payload before signing (we do this for
 * the envelope's own `signer.pubkeyHex` field).
 */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(value, (_key, v) => {
    if (v && typeof v === "object" && !Array.isArray(v)) {
      const sorted: Record<string, unknown> = {};
      for (const k of Object.keys(v as Record<string, unknown>).sort()) {
        sorted[k] = (v as Record<string, unknown>)[k];
      }
      return sorted;
    }
    return v;
  });
}

function canonicalBytes(value: unknown): Uint8Array {
  return new TextEncoder().encode(canonicalJson(value));
}

// ── Hex helpers ────────────────────────────────────────────────

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error("hex string has odd length");
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    const byte = parseInt(hex.slice(i, i + 2), 16);
    if (Number.isNaN(byte)) throw new Error(`invalid hex at offset ${i}`);
    out[i / 2] = byte;
  }
  return out;
}

// ── Sign ───────────────────────────────────────────────────────

export interface SignBundleOptions {
  /**
   * ISO timestamp to stamp. Defaults to `new Date().toISOString()`.
   * Injected for deterministic tests.
   */
  now?: () => string;
  /**
   * Slice 5c: when set, the bundle is addressed to this recipient
   * and the recipient's identity is included in the signed
   * preimage. Receivers (or verifiers acting on their behalf) can
   * enforce `expectedRecipientCertId` / `expectedRecipientBca` to
   * reject bundles that were redirected at them. Omit for broadcast
   * bundles.
   */
  recipient?: RecipientIdentity;
}

/**
 * Wrap a payload in a signed envelope. The payload's canonical bytes
 * + signedAt + signer pubkey (+ recipient, when supplied) are hashed
 * and signed; the signature is attached alongside the unmodified
 * payload.
 */
export async function signBundle<T>(
  payload: T,
  signer: Signer,
  options: SignBundleOptions = {},
): Promise<SignedBundle<T>> {
  const identity = await signer.identity();
  const signerIdentity: SignerIdentity = {
    bca: identity.bca,
    pubkeyHex: bytesToHex(identity.pubkey),
    ...(identity.certId ? { certId: identity.certId } : {}),
  };
  const signedAt = options.now ? options.now() : new Date().toISOString();
  const recipient = options.recipient;
  const preimage = canonicalBytes({
    payload,
    signedAt,
    signerPubkeyHex: signerIdentity.pubkeyHex,
    // `recipient` is only part of the preimage when addressing the
    // bundle — its absence and its presence both need to be reflected
    // deterministically so the verifier reconstructs the same bytes.
    ...(recipient ? { recipient } : {}),
  });
  const signature = await signer.sign(preimage);
  return {
    version: SIGNED_BUNDLE_VERSION,
    payload,
    signedAt,
    signer: signerIdentity,
    ...(recipient ? { recipient } : {}),
    signature: bytesToHex(signature),
  };
}

// ── Verify ─────────────────────────────────────────────────────

export interface VerifyBundleOptions {
  /**
   * Optional — reject if the bundle's signer pubkey hex doesn't
   * match. Use this when the receiver already knows who the expected
   * signer is (cross-session continuation, handoff policy).
   */
  expectedSignerPubkeyHex?: string;
  /**
   * Optional — reject if the bundle's signer bca doesn't match.
   * Same use case as `expectedSignerPubkeyHex`, addressed by BCA
   * instead of pubkey.
   */
  expectedSignerBca?: string;
  /**
   * Slice 5c: when set, reject the bundle unless its
   * `recipient.certId` matches. Rejects broadcast bundles outright
   * when this is supplied — if you asked for a specific recipient,
   * an un-addressed bundle is a misroute.
   */
  expectedRecipientCertId?: string;
  /** Same, by recipient BCA. */
  expectedRecipientBca?: string;
  /** Same, by recipient pubkey hex. */
  expectedRecipientPubkeyHex?: string;
  /**
   * When true, require the bundle to carry a `recipient` field at
   * all. Use when a flow has reached the "addressed bundles only"
   * era and broadcast bundles should be rejected as misroutes.
   * Defaults to false — broadcast bundles are allowed unless one of
   * the `expectedRecipient*` fields is set.
   */
  requireRecipient?: boolean;
}

/**
 * Verify a signed-bundle envelope. Never throws; returns a
 * discriminated result so callers handle all failure modes
 * explicitly.
 *
 * Reconstructs the canonical preimage from the bundle's own fields
 * (payload + signedAt + signerPubkeyHex), converts the hex-encoded
 * signature back to bytes, and delegates to the verifier. The
 * receiver is responsible for deciding whether the signer identity
 * is trusted (cert chain validation, allowlist, etc.) — that's the
 * next slice's concern.
 */
export async function verifyBundle<T>(
  signed: SignedBundle<T>,
  verifier: Verifier,
  options: VerifyBundleOptions = {},
): Promise<VerifyResult<T>> {
  if (signed.version !== SIGNED_BUNDLE_VERSION) {
    return {
      ok: false,
      code: "unsupported_version",
      message: `expected version ${SIGNED_BUNDLE_VERSION}, got ${signed.version}`,
    };
  }

  // Identity-based gating (cheap pre-verify rejection).
  if (
    options.expectedSignerPubkeyHex !== undefined &&
    options.expectedSignerPubkeyHex !== signed.signer.pubkeyHex
  ) {
    return {
      ok: false,
      code: "expected_signer_mismatch",
      message: `expected pubkey ${options.expectedSignerPubkeyHex.slice(0, 12)}…, got ${signed.signer.pubkeyHex.slice(0, 12)}…`,
    };
  }
  if (
    options.expectedSignerBca !== undefined &&
    options.expectedSignerBca !== signed.signer.bca
  ) {
    return {
      ok: false,
      code: "expected_signer_mismatch",
      message: `expected bca ${options.expectedSignerBca}, got ${signed.signer.bca}`,
    };
  }

  // Slice 5c: recipient address gating. If the caller supplied any
  // `expectedRecipient*` or `requireRecipient`, the bundle must be
  // addressed and match.
  const wantsAddress =
    options.requireRecipient === true ||
    options.expectedRecipientCertId !== undefined ||
    options.expectedRecipientBca !== undefined ||
    options.expectedRecipientPubkeyHex !== undefined;

  if (wantsAddress && !signed.recipient) {
    return {
      ok: false,
      code: "unaddressed_bundle",
      message:
        "bundle has no recipient field but receiver required an addressed bundle",
    };
  }

  if (signed.recipient) {
    if (
      options.expectedRecipientCertId !== undefined &&
      options.expectedRecipientCertId !== signed.recipient.certId
    ) {
      return {
        ok: false,
        code: "expected_recipient_mismatch",
        message: `expected recipient certId ${options.expectedRecipientCertId}, bundle addressed to ${signed.recipient.certId ?? "(none)"}`,
      };
    }
    if (
      options.expectedRecipientBca !== undefined &&
      options.expectedRecipientBca !== signed.recipient.bca
    ) {
      return {
        ok: false,
        code: "expected_recipient_mismatch",
        message: `expected recipient bca ${options.expectedRecipientBca}, bundle addressed to ${signed.recipient.bca ?? "(none)"}`,
      };
    }
    if (
      options.expectedRecipientPubkeyHex !== undefined &&
      options.expectedRecipientPubkeyHex !== signed.recipient.pubkeyHex
    ) {
      return {
        ok: false,
        code: "expected_recipient_mismatch",
        message: `expected recipient pubkey ${options.expectedRecipientPubkeyHex.slice(0, 12)}…, bundle addressed to ${(signed.recipient.pubkeyHex ?? "(none)").slice(0, 12)}…`,
      };
    }
  }

  let pubkey: Uint8Array;
  let signatureBytes: Uint8Array;
  try {
    pubkey = hexToBytes(signed.signer.pubkeyHex);
    signatureBytes = hexToBytes(signed.signature);
  } catch (err) {
    return {
      ok: false,
      code: "bad_signature_encoding",
      message: err instanceof Error ? err.message : String(err),
    };
  }

  if (pubkey.byteLength !== 33) {
    return {
      ok: false,
      code: "pubkey_mismatch",
      message: `expected 33-byte compressed secp256k1 pubkey, got ${pubkey.byteLength} bytes`,
    };
  }

  const preimage = canonicalBytes({
    payload: signed.payload,
    signedAt: signed.signedAt,
    signerPubkeyHex: signed.signer.pubkeyHex,
    // Only include recipient in the preimage if the bundle itself
    // carries one — mirrors signBundle's behaviour. A forger can't
    // bolt a recipient onto an unaddressed bundle because that
    // changes the preimage they'd need to have signed.
    ...(signed.recipient ? { recipient: signed.recipient } : {}),
  });

  const valid = await verifier.verify(pubkey, preimage, signatureBytes);
  if (!valid) {
    return {
      ok: false,
      code: "invalid_signature",
      message:
        "ECDSA verification failed — bundle may have been tampered with or signed by a different key",
    };
  }

  return {
    ok: true,
    payload: signed.payload,
    signer: signed.signer,
    signedAt: signed.signedAt,
    ...(signed.recipient ? { recipient: signed.recipient } : {}),
  };
}

// ── Convenience — Identity → SignerIdentity ────────────────────

/** Convert a Signer's `Identity` into the hex-wire-form `SignerIdentity`. */
export function signerIdentityFromIdentity(identity: Identity): SignerIdentity {
  return {
    bca: identity.bca,
    pubkeyHex: bytesToHex(identity.pubkey),
    ...(identity.certId ? { certId: identity.certId } : {}),
  };
}

```
