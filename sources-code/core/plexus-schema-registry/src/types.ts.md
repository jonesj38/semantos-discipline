---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.946769+00:00
---

# core/plexus-schema-registry/src/types.ts

```ts
/**
 * Plexus Schema Registry — RM-012 / Phase H §4.1.
 *
 * A `DomainSchema` describes how a cell's payload bytes are laid out for
 * a given `(domain_flag, version)`. Header reads `domainPayloadRoot`
 * (32B SHA-256 over the encoded payload) at a fixed offset; the
 * payload itself is decoded off-kernel using the schema's
 * `FieldDescriptor[]`.
 *
 * Versioning rules (H §6.4) — enforced at `register()`:
 *   - Appending a field requires a NEW version + NEW typeHash.
 *   - Reordering / removing / changing the type or size of any existing
 *     field is a BREAKING change. Register as a new domain (new flag).
 *   - Fields are packed in declared order; offsets are explicit.
 */

/** Field primitive types — little-endian for numerics. */
export type FieldType =
  | 'u8'
  | 'u16'
  | 'u32'
  | 'u64'
  | 'u256'
  | 'bytes'
  | 'utf8';

export const FIELD_SIZE: Record<Exclude<FieldType, 'bytes' | 'utf8'>, number> = {
  u8: 1,
  u16: 2,
  u32: 4,
  u64: 8,
  u256: 32,
};

/** A field within a domain schema's payload. */
export interface FieldDescriptor {
  /** Field name (snake_case canonical). */
  readonly name: string;
  /** Byte offset within the payload region (not the cell header). */
  readonly offset: number;
  /** Field width in bytes. For `u*` types must match `FIELD_SIZE`; for
   *  `bytes` / `utf8` is the declared maximum width. */
  readonly size: number;
  /** Field primitive type. */
  readonly type: FieldType;
}

/** How the header binds payload bytes to the cell. */
export type CommitmentMode = 'payload-digest' | 'merkle-root';

/**
 * Brc52CertRef — structural subset of `@plexus/contracts::Brc52Cert`.
 * Mirrored inline so this package stays free of cross-package runtime
 * deps beyond the workspace skeleton.
 */
export interface Brc52CertRef {
  readonly certId: string;
  readonly subjectPublicKey: string;
}

/**
 * SchemaAuthority — cryptographic binding between a registered schema
 * and the issuer's BRC-52 cert. Mirrors `LexiconAuthority` from
 * `@semantos/semantos-sir::authority` (RM-003 decided to reuse the
 * pattern) but is named distinctly so the two concerns don't collide.
 */
export interface SchemaAuthority {
  readonly cert: Brc52CertRef;
  /** Hex-encoded ECDSA signature over the canonical schema bytes,
   *  signed by the keypair behind `cert.subjectPublicKey`. */
  readonly schemaSignature: string;
  /** Canonical encoded bytes of the schema that were signed. The
   *  registry recomputes these via `encodeSchema(schema)` and verifies
   *  byte-equality before accepting the signature. */
  readonly schemaBytes: Uint8Array;
}

/** A registered domain schema. */
export interface DomainSchema {
  readonly domainFlag: number;
  readonly version: number;
  readonly fields: ReadonlyArray<FieldDescriptor>;
  readonly commitmentMode: CommitmentMode;
  /** Optional cryptographic authority. Schemas with no authority are
   *  accepted only in test/dev — production registries should refuse
   *  unsigned schemas (the policy is set by the consumer). */
  readonly authority?: SchemaAuthority;
}

/** Lookup key — `(domainFlag, version)` pair. */
export interface SchemaLookupKey {
  readonly domainFlag: number;
  readonly version: number;
}

// ── Result types ─────────────────────────────────────────────────────

export type RegisterResult =
  | { ok: true; key: SchemaLookupKey }
  | { ok: false; code: RegisterErrorCode; message: string };

export type RegisterErrorCode =
  | 'INVALID_SCHEMA'        // structural validation failed
  | 'BREAKING_CHANGE'       // would re-register an existing (flag, version) with different fields
  | 'INVALID_AUTHORITY'     // authority verification refused
  | 'DUPLICATE_VERSION';    // identical (flag, version) already registered

export type VerifyResult =
  | { ok: true }
  | { ok: false; code: RegisterErrorCode; message: string };

// ── Authority verifier interface (mirrors semantos-sir) ───────────────

export type SchemaAuthorityVerification =
  | { ok: true; certId: string }
  | { ok: false; code: 'authority_cert_invalid' | 'schema_signature_invalid' | 'schema_signature_missing'; message: string };

export interface SchemaAuthorityVerifier {
  verifyAuthority(
    authority: SchemaAuthority,
    schemaBytes: Uint8Array,
  ): SchemaAuthorityVerification | Promise<SchemaAuthorityVerification>;
}

/** Permissive verifier for tests/dev. Accepts any well-formed
 *  authority whose `schemaBytes` matches the canonical encoding. */
export class StubSchemaAuthorityVerifier implements SchemaAuthorityVerifier {
  verifyAuthority(
    authority: SchemaAuthority,
    canonicalBytes: Uint8Array,
  ): SchemaAuthorityVerification {
    if (!authority.cert?.certId || !authority.cert?.subjectPublicKey) {
      return {
        ok: false,
        code: 'authority_cert_invalid',
        message: 'authority cert missing certId or subjectPublicKey',
      };
    }
    if (!authority.schemaSignature) {
      return {
        ok: false,
        code: 'schema_signature_missing',
        message: 'authority is missing schemaSignature',
      };
    }
    if (
      authority.schemaBytes.byteLength !== canonicalBytes.byteLength ||
      !authority.schemaBytes.every((b, i) => b === canonicalBytes[i])
    ) {
      return {
        ok: false,
        code: 'schema_signature_invalid',
        message:
          'authority schemaBytes do not match the canonical encoding of the supplied schema',
      };
    }
    return { ok: true, certId: authority.cert.certId };
  }
}

/** Strict default verifier — refuses every authority. K2-aligned: a
 *  registry given a signed schema with no real verifier wired up MUST
 *  reject, never silently accept. */
export class RejectSchemaAuthorityVerifier implements SchemaAuthorityVerifier {
  verifyAuthority(): SchemaAuthorityVerification {
    return {
      ok: false,
      code: 'authority_cert_invalid',
      message:
        'no SchemaAuthorityVerifier was wired up; signed schema cannot be trusted',
    };
  }
}

```
