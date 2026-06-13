---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/policy-runtime/src/authority.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.491033+00:00
---

# packages/policy-runtime/src/authority.ts

```ts
/**
 * Lexicon authority gate for PolicyRuntime.
 *
 * D-A6 (matrix cell A7×A): Extensions that mint capabilities or define
 * lexicons MUST do so under a BRC-52-anchored authority cert. This module
 * is the policy-runtime side of the gate; the SIR side lives in
 * `core/semantos-sir/src/authority.ts`. Both sides share the same
 * structural type for `Brc52CertRef`/`LexiconAuthority` so a verified
 * authority computed at extension-load time can be passed straight into
 * the SIR lowering pass without translation.
 *
 * Spec source:
 *   - docs/spec/protocol-v0.5.md §4 (Identity / BRC-52 cert)
 *   - docs/spec/protocol-v0.5.md §5 (Capability tokens)
 *
 * This file deliberately mirrors the SIR-side types rather than importing
 * them, because `packages/policy-runtime` and `core/semantos-sir` sit
 * in different tiers of the import graph. A caller that already has a
 * `LexiconAuthority` from the SIR side passes through structurally.
 */

// ── Brc52CertRef — structural subset ─────────────────────────────

/**
 * Minimum cert fields needed by the runtime gate. Structurally
 * compatible with `@plexus/contracts`'s full `Brc52Cert` and with the
 * SIR-side `Brc52CertRef`.
 */
export interface Brc52CertRef {
  /** 32-byte hex SHA-256 of the cert's canonical preimage. */
  certId: string;
  /** 33-byte compressed secp256k1 public key, hex-encoded. */
  subjectPublicKey: string;
}

// ── LexiconAuthority ─────────────────────────────────────────────

/**
 * Declared authority for an extension's lexicon and capability
 * minting. Two extensions with distinct `cert.certId` operate in
 * disjoint capability scopes — `PolicyRuntime` indexes per-cert-id at
 * load and refuses cross-authority host-call dispatch.
 */
export interface LexiconAuthority {
  cert: Brc52CertRef;
  /**
   * Hex-encoded ECDSA signature over the extension's canonical
   * grammar bytes, signed by `cert.subjectPublicKey`'s keypair.
   */
  grammarSignature: string;
  /**
   * Bytes of the canonical grammar that were signed. The verifier
   * hashes these and checks the signature.
   */
  grammarBytes: Uint8Array;
}

// ── Authority verifier interface + result ────────────────────────

export type AuthorityVerificationResult =
  | { ok: true; certId: string }
  | { ok: false; code: AuthorityErrorCode; message: string };

export type AuthorityErrorCode =
  | 'authority_missing'
  | 'authority_cert_invalid'
  | 'grammar_signature_missing'
  | 'grammar_signature_invalid';

/**
 * Verifier interface used at extension-load time. The reference
 * implementation is `runtime/verifier-sidecar`'s `BrcVerifier` — its
 * `verify()` covers cert authenticity. Adapters may inject any
 * Verifier-shaped object; tests use a stub.
 */
export interface AuthorityVerifier {
  verifyAuthority(
    authority: LexiconAuthority,
  ): Promise<AuthorityVerificationResult> | AuthorityVerificationResult;
}

// ── ExtensionLoadError ───────────────────────────────────────────

/**
 * Thrown when `PolicyRuntime.loadExtension` rejects an authority. The
 * caller MUST NOT proceed to evaluate any policy from this extension.
 */
export class ExtensionAuthorityError extends Error {
  constructor(
    message: string,
    public readonly code: AuthorityErrorCode,
    public readonly extensionId: string,
  ) {
    super(message);
    this.name = 'ExtensionAuthorityError';
  }
}

// ── Permissive stub for tests ────────────────────────────────────

/**
 * Permissive verifier — accepts any well-formed authority. MUST NOT be
 * used in production. The structural minimums still fail-fast, so
 * missing-cert / missing-signature paths exercise the same rejection
 * path the real verifier would.
 */
export class StubAuthorityVerifier implements AuthorityVerifier {
  verifyAuthority(authority: LexiconAuthority): AuthorityVerificationResult {
    if (!authority.cert?.certId || !authority.cert?.subjectPublicKey) {
      return {
        ok: false,
        code: 'authority_cert_invalid',
        message: 'authority cert missing certId or subjectPublicKey',
      };
    }
    if (!authority.grammarSignature) {
      return {
        ok: false,
        code: 'grammar_signature_missing',
        message: 'authority is missing grammarSignature',
      };
    }
    if (!authority.grammarBytes || authority.grammarBytes.byteLength === 0) {
      return {
        ok: false,
        code: 'grammar_signature_missing',
        message: 'authority is missing grammarBytes',
      };
    }
    return { ok: true, certId: authority.cert.certId };
  }
}

/**
 * Always-rejects verifier — the safe default if no verifier is
 * injected. K2-aligned: better to fail-fast than silently accept.
 */
export class RejectAuthorityVerifier implements AuthorityVerifier {
  verifyAuthority(_authority: LexiconAuthority): AuthorityVerificationResult {
    return {
      ok: false,
      code: 'authority_cert_invalid',
      message:
        'no AuthorityVerifier was injected into PolicyRuntime; ' +
        'declared authority cannot be trusted',
    };
  }
}

// ── Loaded extension record ──────────────────────────────────────

/**
 * The runtime's view of a successfully-loaded extension. Pinned to a
 * single verified authority cert; capability mints emitted while this
 * extension is active are scoped to `authorityCertId`. Cross-scope
 * leakage is structurally impossible — the registry indexes per-cert
 * and the host-call dispatch only sees the active extension's record.
 */
export interface LoadedExtensionAuthority {
  /** Extension identifier (e.g. "calendar", "trades"). */
  extensionId: string;
  /** The verified authority's cert_id. Capability scope key. */
  authorityCertId: string;
  /** Original LexiconAuthority record, retained for re-verification. */
  authority: LexiconAuthority;
}

```
