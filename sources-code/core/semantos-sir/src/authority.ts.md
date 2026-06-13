---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-sir/src/authority.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.812461+00:00
---

# core/semantos-sir/src/authority.ts

```ts
/**
 * Lexicon authority — cryptographic binding between an extension's domain
 * grammar and the BRC-52 cert held by its issuer/maintainer.
 *
 * D-A6 (matrix cell A7×A): Extensions that mint capabilities or define
 * lexicons MUST do so under a BRC-52-anchored authority cert. The active
 * extension's domain grammar (per `runtime/intent` pipeline) is signed by
 * that cert's keypair. `lowerSIR` refuses to lower a `SIRProgram` whose
 * declared authority cert fails verification, and the lowering binds the
 * authority `cert_id` into the OIR result so capability scopes do not
 * leak across authorities.
 *
 * Spec source:
 *   - docs/spec/protocol-v0.5.md §4 (Identity / BRC-52 cert)
 *   - docs/spec/protocol-v0.5.md §5 (Capability tokens)
 *
 * Canon discipline: authority cert (cert-id glossary entry); grammar
 * signature is a separate provenance field — not a cert_id, not a cap
 * token. The "trusted issuer" string field that older code paths used
 * is replaced by `authority` here; consumers MUST drop that field.
 */

// ── Brc52CertRef — structural subset of @plexus/contracts Brc52Cert ──
//
// Defined locally so semantos-sir keeps its narrow dependency surface
// (@semantos/semantos-ir only). Any caller passing a full
// @plexus/contracts Brc52Cert is structurally compatible — the strict
// superset assigns to this subset by TypeScript's structural rules.

/**
 * The fields of a BRC-52 cert that the lowering pass needs to identify
 * an authority and route verification.
 *
 * For the canonical, fully-typed cert see `@plexus/contracts`'s
 * `Brc52Cert` — passing one of those satisfies this shape.
 */
export interface Brc52CertRef {
  /** 32-byte hex SHA-256 of the cert's canonical preimage. */
  certId: string;
  /** 33-byte compressed secp256k1 public key, hex-encoded. */
  subjectPublicKey: string;
}

// ── LexiconAuthority — what an extension declares ───────────────────

/**
 * Declared authority for an extension's lexicon and capability minting.
 *
 * Replaces any pre-D-A6 "trusted issuer" string. The cert binds the
 * extension to a real BRC-52 identity; the grammar signature binds the
 * declared grammar bytes to the authority's key.
 *
 * Authorities are scoped by `cert.certId`: two extensions with distinct
 * certIds operate in disjoint capability scopes. The lowering pass
 * threads the certId into the OIR so a kernel-side scope check can
 * refuse cross-authority capability mints.
 */
export interface LexiconAuthority {
  /**
   * The BRC-52 cert held by the extension's maintainer. Either a full
   * `@plexus/contracts` `Brc52Cert` or any object structurally
   * implementing `Brc52CertRef`.
   */
  cert: Brc52CertRef;
  /**
   * Hex-encoded ECDSA signature over the extension's domain-grammar
   * bytes, signed by the keypair behind `cert.subjectPublicKey`.
   * Verified at extension load time.
   */
  grammarSignature: string;
  /**
   * Bytes of the canonical grammar that were signed. Carried alongside
   * the signature so verifiers don't have to recompute or fetch them.
   * Exposed as an opaque blob — the verifier hashes them.
   */
  grammarBytes: Uint8Array;
}

// ── Authority verification result ───────────────────────────────────

export type AuthorityVerificationResult =
  | { ok: true; certId: string }
  | { ok: false; code: AuthorityErrorCode; message: string };

/**
 * Failure codes for `verifyLexiconAuthority`. Mirrors the cert/identity
 * failure shape used by `runtime/verifier-sidecar` so callers can route
 * uniformly.
 */
export type AuthorityErrorCode =
  | 'authority_missing'           // No `authority` declared on a program/extension that mints
  | 'authority_cert_invalid'      // Cert failed structural or signature check
  | 'grammar_signature_missing'   // No signature provided
  | 'grammar_signature_invalid';  // Signature did not verify against cert.subjectPublicKey

// ── Authority verifier interface ────────────────────────────────────

/**
 * Minimal interface the lowering pass calls to verify an authority.
 *
 * The reference implementation is `runtime/verifier-sidecar`'s
 * `BrcVerifier` (D-V1) — its `verify()` method covers the cert
 * authenticity check. Adapters may inject any Verifier-shaped object;
 * tests use a stub. Keeping the interface narrow lets `semantos-sir`
 * stay free of a `runtime/` dep at the package level.
 */
export interface AuthorityVerifier {
  /**
   * Verify the authority cert's authenticity (structural fields,
   * cert_id derivation, issuer signature) and the grammar signature
   * over `grammarBytes` by `cert.subjectPublicKey`.
   *
   * Implementations MUST NOT throw — every failure surfaces as
   * `{ ok: false }`.
   */
  verifyAuthority(authority: LexiconAuthority): Promise<AuthorityVerificationResult> | AuthorityVerificationResult;
}

// ── Reference verifier (test/dev) ───────────────────────────────────

/**
 * Permissive verifier — accepts any well-formed authority. Useful in
 * unit tests where ECDSA + cert chain checks are impractical. MUST NOT
 * be used in production: the BrcVerifier from `runtime/verifier-sidecar`
 * is the only acceptable production binding.
 *
 * The check still enforces structural minimums so a missing-cert or
 * missing-signature case fails the same way the real verifier would.
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
        message: 'authority is missing grammarBytes (nothing to verify against)',
      };
    }
    return { ok: true, certId: authority.cert.certId };
  }
}

/**
 * Always-rejects verifier — the SIR layer's default when no verifier
 * is injected. Refusing by default is K2-aligned: the lowering pass
 * MUST NOT silently accept an authority whose verification path was
 * never wired up. Callers that legitimately have no authority (e.g.
 * the Lisp identity seam in `compileToSIR`) leave `authority`
 * undefined; the lowering pass skips verification entirely in that
 * case. The reject-by-default verifier only fires when an authority
 * IS declared and no verifier was injected — that's a config bug.
 */
export class RejectAuthorityVerifier implements AuthorityVerifier {
  verifyAuthority(_authority: LexiconAuthority): AuthorityVerificationResult {
    return {
      ok: false,
      code: 'authority_cert_invalid',
      message:
        'no AuthorityVerifier was injected into the lowering pass; ' +
        'declared authority cannot be trusted',
    };
  }
}

```
