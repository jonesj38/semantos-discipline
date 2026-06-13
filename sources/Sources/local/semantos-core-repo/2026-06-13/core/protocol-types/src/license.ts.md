---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/license.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.843888+00:00
---

# core/protocol-types/src/license.ts

```ts
/**
 * Phase 35B.1 — License primitive.
 *
 * A `License` authorises a holder pubkey to run a Semantos node and use
 * specific services (session, media, …). It is signed by an issuer's
 * secp256k1 key; nodes refuse to start without a valid license in their
 * config.
 *
 * Design constraints:
 *
 *   - This module is pure TypeScript. It never imports `@bsv/sdk` so the
 *     G35A.12 single-choke-point invariant in `runtime/session-protocol/
 *     src/signer.ts` keeps holding. Signature verification is delegated to
 *     an injected `LicenseVerifier` — consumers pass `BsvSdkVerifier`.
 *
 *   - Wire format is a fixed-order CBOR array so canonical bytes are
 *     deterministic regardless of TypeScript object iteration order:
 *
 *       [ pubkey, issuer, expiry | null, services, meta | null, issuerSig ]
 *
 *     The issuer signs over a 5-element body (the sig slot omitted) to
 *     avoid self-reference. See `canonicalLicenseBodyForSigning`.
 *
 *   - `licenseCertId` hashes the full 6-element encoded tuple with SHA-256
 *     and prefixes `"sha256:"`. Different signatures over the same body
 *     produce different cert-ids, which is what we want for the
 *     /.well-known/semantos-node advertisement.
 */

import { Encoder, Decoder } from "cbor-x";
import { createHash } from "node:crypto";

// Using shared Encoder/Decoder instances with `useRecords: false` so plain
// arrays/objects serialize as standard CBOR tuples rather than cbor-x's
// tagged record format — critical for interop and canonical bytes.
const encoder = new Encoder({ useRecords: false });
const decoder = new Decoder({ useRecords: false });

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * A signed authorisation for a Semantos node holder pubkey.
 */
export interface License {
  /** 33-byte compressed secp256k1 pubkey — the authorised node identity. */
  pubkey: Uint8Array;
  /** 33-byte compressed secp256k1 pubkey — the issuer. */
  issuer: Uint8Array;
  /** DER-encoded ECDSA over `canonicalLicenseBodyForSigning(this)`. */
  issuerSig: Uint8Array;
  /** Optional unix seconds expiry. Absent = never expires. */
  expiry?: number;
  /** Service ids this license authorises, e.g. `["session", "media"]`. */
  services: string[];
  /** Issuer-defined auxiliary fields. Not interpreted here. */
  meta?: Record<string, unknown>;
}

/**
 * Structural contract for signature verification. `runtime/session-protocol`'s
 * `Verifier` interface satisfies this — consumers can pass `BsvSdkVerifier`
 * directly and rely on TypeScript's structural typing.
 */
export interface LicenseVerifier {
  verify(
    pubkey: Uint8Array,
    bytes: Uint8Array,
    sig: Uint8Array,
  ): Promise<boolean>;
}

/**
 * Result of `verifyLicense`. Either ok, or a tagged failure reason — callers
 * route on `reason` rather than parsing strings.
 */
export type LicenseVerdict =
  | { ok: true }
  | {
      ok: false;
      reason: "invalid-signature" | "expired" | "malformed";
      detail?: string;
    };

// ---------------------------------------------------------------------------
// Dev-issuer constants
// ---------------------------------------------------------------------------

/**
 * Seed string used to derive the dev issuer's private key for local testing.
 *
 * Derivation: `PrivateKey.fromHex(sha256("semantos-dev-issuer"))` — the
 * derivation lives in `runtime/session-protocol` where `@bsv/sdk` is
 * permitted (G35A.12).
 *
 * Production nodes MUST accept only Plexus-issued licenses. The dev issuer
 * is gated behind `SEMANTOS_DEV_MODE=1` at the boot policy layer in
 * `runtime/node/src/daemon.ts`.
 */
export const DEV_ISSUER_PRIVKEY_SEED = "semantos-dev-issuer";

// ---------------------------------------------------------------------------
// Encode / decode
// ---------------------------------------------------------------------------

/**
 * Encode a license to canonical CBOR bytes (full 6-element tuple incl. sig).
 *
 * Use this for on-disk storage, wire transmission, and cert-id derivation.
 * For signing, use `canonicalLicenseBodyForSigning` which excludes the sig.
 */
export function encodeLicense(l: License): Uint8Array {
  const tuple = [
    l.pubkey,
    l.issuer,
    l.expiry ?? null,
    l.services,
    l.meta ?? null,
    l.issuerSig,
  ];
  return new Uint8Array(encoder.encode(tuple));
}

/**
 * Decode canonical CBOR bytes back into a `License` object.
 *
 * Throws a descriptive `Error` prefixed with `"malformed license:"` on any
 * shape or content violation — callers can either catch or wrap in a
 * `LicenseVerdict`.
 */
export function decodeLicense(bytes: Uint8Array): License {
  let decoded: unknown;
  try {
    decoded = decoder.decode(bytes);
  } catch (e) {
    throw new Error(`malformed license: ${(e as Error).message}`);
  }

  if (!Array.isArray(decoded)) {
    throw new Error(`malformed license: expected CBOR array, got ${typeof decoded}`);
  }
  if (decoded.length !== 6) {
    throw new Error(
      `malformed license: expected 6-element tuple, got ${decoded.length}`,
    );
  }

  const [pubkey, issuer, expiry, services, meta, sig] = decoded;

  return {
    pubkey: toUint8(pubkey, "pubkey"),
    issuer: toUint8(issuer, "issuer"),
    expiry: expiry == null ? undefined : Number(expiry),
    services: toStringArray(services, "services"),
    meta: meta == null ? undefined : (meta as Record<string, unknown>),
    issuerSig: toUint8(sig, "issuerSig"),
  };
}

/**
 * Encode the 5-element body (everything except `issuerSig`) — the bytes the
 * issuer signs over, and the bytes a verifier re-hashes. Deterministic for a
 * given license content regardless of what's in the sig field.
 */
export function canonicalLicenseBodyForSigning(l: License): Uint8Array {
  const body = [
    l.pubkey,
    l.issuer,
    l.expiry ?? null,
    l.services,
    l.meta ?? null,
  ];
  return new Uint8Array(encoder.encode(body));
}

// ---------------------------------------------------------------------------
// Verify
// ---------------------------------------------------------------------------

/**
 * Verify a license's expiry + issuer signature.
 *
 * Expiry is checked first; expired licenses short-circuit without calling
 * the verifier. Otherwise the sig is checked against the canonical body
 * bytes using the injected `LicenseVerifier`.
 */
export async function verifyLicense(
  l: License,
  verifier: LicenseVerifier,
  opts: { now?: number } = {},
): Promise<LicenseVerdict> {
  if (l.expiry != null) {
    const now = opts.now ?? Math.floor(Date.now() / 1000);
    if (l.expiry < now) {
      return {
        ok: false,
        reason: "expired",
        detail: `expiry ${l.expiry} < now ${now}`,
      };
    }
  }

  const body = canonicalLicenseBodyForSigning(l);
  const sigOk = await verifier.verify(l.issuer, body, l.issuerSig);
  if (!sigOk) {
    return { ok: false, reason: "invalid-signature" };
  }

  return { ok: true };
}

// ---------------------------------------------------------------------------
// Cert id
// ---------------------------------------------------------------------------

/**
 * Derive a stable identifier for this exact signed license: the SHA-256 of
 * the full encoded 6-tuple (body + sig), prefixed `"sha256:"`.
 *
 * Advertised via `/.well-known/semantos-node` so peers can pin the specific
 * license cert without trusting the claimed BCA alone.
 */
export function licenseCertId(l: License): string {
  const full = encodeLicense(l);
  const hex = createHash("sha256").update(full).digest("hex");
  return `sha256:${hex}`;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function toUint8(x: unknown, field: string): Uint8Array {
  if (x instanceof Uint8Array) {
    // Buffer is a Uint8Array subclass — copy to a plain Uint8Array so
    // downstream code that uses `instanceof Uint8Array` / strict buffer
    // comparisons behaves predictably.
    return x.constructor === Uint8Array ? x : new Uint8Array(x);
  }
  throw new Error(
    `malformed license: field "${field}" expected byte string, got ${typeof x}`,
  );
}

function toStringArray(x: unknown, field: string): string[] {
  if (!Array.isArray(x)) {
    throw new Error(
      `malformed license: field "${field}" expected array, got ${typeof x}`,
    );
  }
  return x.map((el, i) => {
    if (typeof el !== "string") {
      throw new Error(
        `malformed license: ${field}[${i}] expected string, got ${typeof el}`,
      );
    }
    return el;
  });
}

```
