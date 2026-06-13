---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/cert-trust.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.036014+00:00
---

# runtime/session-protocol/src/cert-trust.ts

```ts
/**
 * Cert-trust layer — receiver-side validation of a SignedBundle's
 * signer identity against a registry of known certs.
 *
 * Slice 5a gave us cryptographic bundle signing; the receiver could
 * reject forged signatures. But the receiver still had to be
 * pre-configured with the exact `pubkeyHex` of every peer it trusted
 * (`expectedSignerPubkeyHex`). That's fine for a test but brittle in
 * the real OJT↔REA flow — new hats come and go, and the receiver
 * shouldn't need a code change per new sender.
 *
 * Slice 5b shifts trust from "known pubkey" to "known cert". The
 * receiver maintains a `KnownCertStore` mapping `certId → CertRecord`
 * and asks, on import, whether the bundle's advertised `certId`:
 *
 *   1. is in the store (known signer),
 *   2. is not revoked,
 *   3. matches the bundle's advertised `pubkeyHex` (prevents a
 *      signer from claiming someone else's cert),
 *   4. has a valid signature over the canonical preimage.
 *
 * The store is deliberately minimal — it's the receiver's
 * **allowlist**, not Plexus's full cert DAG. In production it'll be
 * populated by out-of-band cert exchange (shared config, QR code,
 * trust-on-first-use prompt) and/or by a Plexus fetch helper that
 * resolves unknown certIds to their records. Neither is in scope for
 * 5b — this slice is the trust primitive, not the distribution
 * mechanism.
 */

import { verifyBundle, type SignedBundle, type VerifyErrorCode } from "./bundle-envelope.js";
import type { Verifier } from "./signer.js";

// ── CertRecord — structural subset of PlexusCert ───────────────
//
// Session-protocol doesn't depend on @plexus/contracts. CertRecord
// declares the minimum shape a receiver needs to make a trust
// decision. A full `PlexusCert` from core/plexus-contracts/identity.ts
// is structurally assignable. Callers with richer metadata can cast
// or extend — these are the only fields the verifier reads.

export interface CertRecord {
  /** 32-byte hex SHA256 of the canonical cert preimage. */
  certId: string;
  /** 33-byte compressed secp256k1 public key, hex-encoded. */
  publicKeyHex: string;
  /** True when the receiver has marked this cert as revoked. */
  revoked?: boolean;
  /** Optional — parent cert id in the derivation chain. */
  parentCertId?: string | null;
  /** Optional — resource id this cert was derived for (e.g. "trades.job"). */
  resourceId?: string;
  /** Optional — domain flag associated with this cert. */
  domainFlag?: number;
}

// ── KnownCertStore interface + in-memory default ───────────────

export interface KnownCertStore {
  /** Return the stored CertRecord for certId, or null if unknown. */
  get(certId: string): Promise<CertRecord | null>;
  /** Add a trusted cert. Idempotent — re-adding an existing certId
      overwrites the record (use `revoke` to mark as untrusted). */
  add(cert: CertRecord): Promise<void>;
  /** Mark a cert as revoked. Subsequent `verifyBundleWithTrust`
      calls that resolve to this cert fail with `revoked_cert`. */
  revoke(certId: string): Promise<void>;
  /** True iff the certId is in the store (regardless of revoked status). */
  has(certId: string): Promise<boolean>;
  /** List all stored certs — useful for debugging / UI. */
  list(): Promise<CertRecord[]>;
}

export function createInMemoryKnownCertStore(
  initial: ReadonlyArray<CertRecord> = [],
): KnownCertStore {
  const store = new Map<string, CertRecord>();
  for (const cert of initial) store.set(cert.certId, { ...cert });
  return {
    async get(certId) {
      const cert = store.get(certId);
      return cert ? { ...cert } : null;
    },
    async add(cert) {
      store.set(cert.certId, { ...cert });
    },
    async revoke(certId) {
      const existing = store.get(certId);
      if (existing) store.set(certId, { ...existing, revoked: true });
    },
    async has(certId) {
      return store.has(certId);
    },
    async list() {
      return Array.from(store.values()).map((c) => ({ ...c }));
    },
  };
}

// ── verifyBundleWithTrust — the main entry point ───────────────

export type TrustVerifyErrorCode =
  | VerifyErrorCode
  | "missing_cert_id"
  | "unknown_signer"
  | "revoked_cert"
  | "pubkey_cert_mismatch";

export type TrustVerifyResult<T> =
  | {
      ok: true;
      payload: T;
      signer: SignedBundle<T>["signer"];
      signedAt: string;
      /** The resolved cert record that passed trust validation. */
      cert: CertRecord;
    }
  | { ok: false; code: TrustVerifyErrorCode; message: string };

export interface VerifyBundleWithTrustOptions {
  /**
   * When true (default), a bundle with no `signer.certId` is rejected
   * with `missing_cert_id`. Set to `false` only in transitional
   * flows where some bundles predate the cert era; production
   * receivers should leave this on.
   */
  requireCertId?: boolean;
  /**
   * Optional pubkey-based pre-check (inherited from Slice 5a's
   * `verifyBundle`). Passes through unchanged — if set, rejects
   * before any cert lookup when pubkeys don't match.
   */
  expectedSignerPubkeyHex?: string;
  /** Same as above, by BCA. */
  expectedSignerBca?: string;
  /**
   * Slice 5c recipient-address gates. Pass-through to the underlying
   * `verifyBundle` — when set, reject bundles not addressed to this
   * cert id / bca / pubkey hex.
   */
  expectedRecipientCertId?: string;
  expectedRecipientBca?: string;
  expectedRecipientPubkeyHex?: string;
  requireRecipient?: boolean;
}

/**
 * Verify a signed bundle against a trust registry.
 *
 * Flow:
 *   1. Check `signer.certId` is present (if `requireCertId`).
 *   2. Look it up in the store → reject with `unknown_signer` if missing.
 *   3. Reject with `revoked_cert` if the stored record is revoked.
 *   4. Verify the stored record's `publicKeyHex` matches the bundle's
 *      advertised `signer.pubkeyHex`; mismatch → `pubkey_cert_mismatch`.
 *      (An attacker in possession of a valid cert could not produce
 *      a valid signature for a different pubkey, but the pre-check
 *      short-circuits cleanly before doing the crypto work.)
 *   5. Delegate to `verifyBundle` for the actual ECDSA verification.
 *   6. On success, attach the resolved cert record to the result so
 *      downstream code (handoff policy, UI attribution, audit log)
 *      has the richer metadata without re-querying.
 *
 * Discriminated result; never throws.
 */
export async function verifyBundleWithTrust<T>(
  signed: SignedBundle<T>,
  verifier: Verifier,
  trustStore: KnownCertStore,
  options: VerifyBundleWithTrustOptions = {},
): Promise<TrustVerifyResult<T>> {
  const requireCertId = options.requireCertId ?? true;

  if (requireCertId && !signed.signer.certId) {
    return {
      ok: false,
      code: "missing_cert_id",
      message:
        "bundle has no signer.certId; cannot look up in trust store (set requireCertId: false to allow)",
    };
  }

  // If we have a certId, resolve + validate against the store BEFORE
  // the crypto work. Unknown-signer / revoked checks are cheap.
  let resolvedCert: CertRecord | null = null;
  if (signed.signer.certId) {
    resolvedCert = await trustStore.get(signed.signer.certId);

    if (!resolvedCert) {
      return {
        ok: false,
        code: "unknown_signer",
        message: `certId ${signed.signer.certId} is not in the trust store`,
      };
    }

    if (resolvedCert.revoked) {
      return {
        ok: false,
        code: "revoked_cert",
        message: `certId ${signed.signer.certId} has been revoked`,
      };
    }

    if (resolvedCert.publicKeyHex !== signed.signer.pubkeyHex) {
      return {
        ok: false,
        code: "pubkey_cert_mismatch",
        message:
          `bundle advertises pubkey ${signed.signer.pubkeyHex.slice(0, 12)}… ` +
          `but stored cert has ${resolvedCert.publicKeyHex.slice(0, 12)}…`,
      };
    }
  }

  // Now run the Slice-5a signature verification. Thread through the
  // optional signer/recipient gates unchanged.
  const inner = await verifyBundle(signed, verifier, {
    ...(options.expectedSignerPubkeyHex !== undefined
      ? { expectedSignerPubkeyHex: options.expectedSignerPubkeyHex }
      : {}),
    ...(options.expectedSignerBca !== undefined
      ? { expectedSignerBca: options.expectedSignerBca }
      : {}),
    ...(options.expectedRecipientCertId !== undefined
      ? { expectedRecipientCertId: options.expectedRecipientCertId }
      : {}),
    ...(options.expectedRecipientBca !== undefined
      ? { expectedRecipientBca: options.expectedRecipientBca }
      : {}),
    ...(options.expectedRecipientPubkeyHex !== undefined
      ? { expectedRecipientPubkeyHex: options.expectedRecipientPubkeyHex }
      : {}),
    ...(options.requireRecipient !== undefined
      ? { requireRecipient: options.requireRecipient }
      : {}),
  });
  if (!inner.ok) {
    return inner;
  }

  return {
    ok: true,
    payload: inner.payload,
    signer: signed.signer,
    signedAt: inner.signedAt,
    cert:
      resolvedCert ??
      // Only reached when requireCertId=false and signed.signer.certId is
      // absent. Synthesise a minimal record so the discriminated result
      // type stays uniform. Callers inspecting .cert should check for
      // presence of certId to know if this was a genuine trust-store
      // match or a "no-cert permitted" passthrough.
      {
        certId: "",
        publicKeyHex: signed.signer.pubkeyHex,
      },
  };
}

```
