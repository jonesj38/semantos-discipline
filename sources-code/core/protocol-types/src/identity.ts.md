---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.837640+00:00
---

# core/protocol-types/src/identity.ts

```ts
/**
 * Canonical identity types for the Semantos/Plexus stack.
 *
 * This file is the canonical home for:
 *   - BRC-52 certificate types (promoted from @plexus/contracts in W1.5C-1)
 *   - The canonical `IdentityProvider` interface (W1.5C-1 unification)
 *   - The legacy `IdentityAdapter` (kernel gateway, unchanged)
 *
 * Spec source: docs/spec/protocol-v0.5.md §4 (Identity).
 * Canon discipline: aliases per docs/canon/glossary.yml.
 *   cert_id (snake_case) is the wire form; certId (camelCase) is TS convention.
 *
 * W1.5C-1 promoted these from core/plexus-contracts/src/identity.ts:
 *   Brc52Cert, CertIdPreimage, CertificatePreimage, PlexusCert,
 *   canonicalCertPreimage, computeCertId, CertRegistrationRequest,
 *   CertRegistrationResult, CertRegistrationErrorCode,
 *   Brc100Headers, SignedBundle<T>.
 *
 * Cross-language conformance: Elixir mirror at
 *   runtime/world-beam/apps/world_host/lib/world_host/identity.ex produces byte-identical
 *   canonicalCertPreimage output for all conformance vectors.
 *
 * @plexus/contracts re-exports everything below for backward compatibility.
 * New code should import directly from @semantos/protocol-types.
 */

// ── @bsv/sdk Hash — imported for canonicalCertPreimage / computeCertId ──────
// This is the ONLY vendor import in this file. @bsv/sdk is a zero-dependency
// SDK; the import is safe in core/ because the SDK ships no Node.js-only APIs.
import { Hash } from "@bsv/sdk";

// ── BRC-52 certificate (§4.2) ────────────────────────────────────────────────

/**
 * BRC-52 certificate as carried in the x-brc52-certificate header of a
 * SignedBundle (§12.1). Canonical term: cert (glossary id: brc-52).
 *
 * cert_id = SHA-256(canonical_preimage) where the canonical preimage
 * covers all fields *except* signature (§4.2 rule). The certId field
 * is itself excluded from its own preimage (it is the SHA-256 output).
 *
 * Wire field names: snake_case per §4.2; camelCase here per TS convention
 * (glossary id: cert-id — cert_id on wire, certId in TS).
 *
 * Note: `Brc52Certificate` is a backward-compatible alias for `Brc52Cert`
 * (used in apps/world-client D-A2). Prefer `Brc52Cert` in new code.
 *
 * Spec source: docs/spec/protocol-v0.5.md §4.2.
 */
export interface Brc52Cert {
  /** 32-byte hex: SHA-256 of the canonical preimage. Stable identity hash. */
  certId: string;
  /** 33-byte compressed secp256k1 public key of the subject, hex-encoded. */
  subjectPublicKey: string;
  /** 33-byte compressed public key of the certifier (parent cert key, or self for root), hex-encoded. */
  certifierPublicKey: string;
  /** Certificate type identifier (e.g. "plexus.identity.root", "plexus.identity.derived"). */
  type: string;
  /** Unique serial number for this certificate (hex-encoded SHA-256 of the derivation inputs). */
  serialNumber: string;
  /**
   * Application-defined fields (camelCase keys per Plexus spec §4.2).
   * Values are strings. Binary or base64 fields are stored as hex strings.
   * Do NOT include certId or signature here — they are not part of the preimage.
   */
  fields: Record<string, string>;
  /** Issuer ECDSA signature over the canonical issuer-signature preimage, DER hex-encoded. */
  signature: string;
}

/**
 * Backward-compatible alias for `Brc52Cert`.
 *
 * D-A2 (apps/world-client) defined `Brc52Certificate` as the local cert type.
 * W1.5C-1 promotes the canonical type to `Brc52Cert` here; `Brc52Certificate`
 * is kept as an alias so existing D-A2 callers compile without changes.
 *
 * Prefer `Brc52Cert` in new code.
 */
export type Brc52Certificate = Brc52Cert;

/**
 * The portion of a BRC-52 cert that forms the cert_id preimage.
 *
 * This is all fields except certId (circular — cert_id is the output of
 * SHA-256, not an input) and signature (explicitly excluded by §4.2).
 *
 * Canonical preimage: deterministic sorted-key JSON, UTF-8 encoded.
 * All nested object keys are also sorted (deep sort).
 *
 * The cert_id = SHA-256(UTF-8(deepSortedJSON(CertIdPreimage))).
 *
 * Spec source: docs/spec/protocol-v0.5.md §4.2.
 */
export interface CertIdPreimage {
  /** 33-byte compressed public key of the certifier, hex-encoded. */
  certifierPublicKey: string;
  /** Application-defined fields. All nested keys sorted. */
  fields: Record<string, string>;
  /** Unique serial number. */
  serialNumber: string;
  /** 33-byte compressed public key of the subject, hex-encoded. */
  subjectPublicKey: string;
  /** Certificate type identifier. */
  type: string;
}

/**
 * Older name kept for compatibility with existing code.
 * Prefer CertIdPreimage in new code.
 *
 * @deprecated Use CertIdPreimage
 */
export interface CertificatePreimage {
  /** 33-byte compressed public key of the subject, hex-encoded. */
  subjectPublicKey: string;
  /** 33-byte compressed public key of the certifier (parent or self for root), hex-encoded. */
  certifierPublicKey: string;
  /** Certificate type identifier. */
  type: string;
  /** Unique serial number for this certificate. */
  serialNumber: string;
  /** Application-defined fields (camelCase keys per Plexus spec). */
  fields: Record<string, string>;
}

// ── Canonical preimage functions ─────────────────────────────────────────────

/**
 * Deep-sort a plain object: recursively sort keys at every nesting level.
 *
 * Arrays are left in their original order (they are ordered by definition).
 * Primitives are returned as-is.
 *
 * This guarantees byte-identical JSON serialization regardless of insertion
 * order of keys into the object literal — required for cert_id determinism
 * across languages and runtimes.
 */
function deepSortObject(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(deepSortObject);
  }
  if (value !== null && typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      sorted[key] = deepSortObject((value as Record<string, unknown>)[key]);
    }
    return sorted;
  }
  return value;
}

/**
 * Produce the canonical cert_id preimage bytes for a BRC-52 cert.
 *
 * Per docs/spec/protocol-v0.5.md §4.2:
 *   cert_id = SHA-256(canonical_preimage)
 * where the canonical preimage covers all cert fields *except* signature.
 * The certId itself is also excluded — it is the SHA-256 output, not an input.
 *
 * Algorithm:
 *   1. Extract {certifierPublicKey, fields, serialNumber, subjectPublicKey, type}.
 *   2. Deep-sort all object keys (including nested field keys).
 *   3. JSON.stringify with no whitespace.
 *   4. Encode as UTF-8.
 *
 * This MUST match the Elixir implementation in
 * runtime/world-beam/apps/world_host/lib/world_host/identity.ex canonical_cert_preimage/1
 * and the verifier-sidecar brc52CertIdPreimage function in verifier.ts.
 *
 * No random nonces, timestamps, or other uniqueness sources appear here —
 * the preimage is 100% deterministic from the cert fields.
 *
 * @param cert - A BRC-52 cert (Brc52Cert) or any object with the required fields.
 */
export function canonicalCertPreimage(cert: Pick<Brc52Cert, "certifierPublicKey" | "fields" | "serialNumber" | "subjectPublicKey" | "type">): Uint8Array {
  const preimageObj: CertIdPreimage = {
    certifierPublicKey: cert.certifierPublicKey,
    fields: cert.fields,
    serialNumber: cert.serialNumber,
    subjectPublicKey: cert.subjectPublicKey,
    type: cert.type,
  };
  const sorted = deepSortObject(preimageObj);
  const json = JSON.stringify(sorted);
  return new TextEncoder().encode(json);
}

/**
 * Compute a BRC-52 cert_id from a cert.
 *
 * cert_id = lowercase hex(SHA-256(canonicalCertPreimage(cert)))
 *
 * Returns 64-char lowercase hex string (32 bytes).
 *
 * This is the canonical TS implementation. The Elixir mirror at
 * runtime/world-beam/apps/world_host/lib/world_host/identity.ex compute_cert_id/1 MUST
 * produce byte-identical output for all conformance vectors at
 * core/plexus-contracts/tests/vectors/cert_id_vectors.json.
 *
 * Uses @bsv/sdk Hash.sha256 — no new runtime dependencies.
 *
 * @param cert - A BRC-52 cert or preimage-compatible object.
 */
export function computeCertId(cert: Pick<Brc52Cert, "certifierPublicKey" | "fields" | "serialNumber" | "subjectPublicKey" | "type">): string {
  const preimageBytes = canonicalCertPreimage(cert);
  const digest = Hash.sha256(Array.from(preimageBytes)) as number[];
  return digest.map((b) => b.toString(16).padStart(2, "0")).join("");
}

// ── Cert registration flow envelope ─────────────────────────────────────────

/**
 * Cert registration request — sent from client to Plexus identity service
 * when enrolling a new BRC-52 certificate in the DAG.
 *
 * §4.2 issuance flow: parent signs child cert using CHILD_CREATION key
 * (domain flag 0x06); the signed cert plus metadata form this envelope.
 */
export interface CertRegistrationRequest {
  /**
   * The fully-formed BRC-52 cert (with certId already computed and signature
   * from the issuer already attached).
   */
  cert: Brc52Cert;
  /**
   * cert_id of the parent certificate. Null for root certs.
   * Matches cert.certifierPublicKey's cert_id in the DAG.
   */
  parentCertId: string | null;
  /**
   * Monotonic child index under the parent context (§4.2).
   * The server MUST reject enrollments where childIndex <= max existing
   * for this (parentCertId, type) pair to prevent index reuse.
   */
  childIndex: number;
  /**
   * Application namespace identifier (32-byte hex).
   * Scopes the cert within a particular app context (§4.4).
   */
  appId: string;
}

/**
 * Cert registration response from the Plexus identity service.
 */
export type CertRegistrationResult =
  | {
      ok: true;
      /** The enrolled cert_id (echoed for confirmation). */
      certId: string;
      /** Server-assigned enrollment timestamp (ms since epoch). */
      enrolledAt: number;
    }
  | {
      ok: false;
      code: CertRegistrationErrorCode;
      message: string;
    };

/**
 * Error codes for cert registration failures.
 */
export type CertRegistrationErrorCode =
  | "cert_id_mismatch"          // Computed cert_id differs from submitted cert.certId
  | "issuer_signature_invalid"  // Certifier signature over preimage is invalid
  | "child_index_reused"        // childIndex <= existing max for this parent
  | "parent_cert_not_found"     // parentCertId does not exist in the DAG
  | "subject_key_conflict"      // subjectPublicKey already enrolled under a different parent
  | "malformed_cert"            // Structural validation failed
  | "appId_unknown";            // appId is not registered

// ── BRC-100 verification headers (§12.1) ────────────────────────────────────

/**
 * BRC-100 signed-request verification headers.
 *
 * These are the five mandatory headers of a SignedBundle (§12.1).
 * Canonical term: SignedBundle (glossary id: signed-bundle).
 * BRC reference: BRC-100 — Wallet-to-Application Interface.
 *
 * All header names are lowercase — matching HTTP convention and the
 * constants in core/plexus-contracts/src/transport.ts.
 */
export interface Brc100Headers {
  /** 33-byte compressed secp256k1 pubkey, hex-encoded. Sender identity. */
  "x-brc100-identitykey": string;
  /** 32-byte anti-replay nonce, hex-encoded. */
  "x-brc100-nonce": string;
  /** Milliseconds since epoch. */
  "x-brc100-timestamp": string | number;
  /** ECDSA signature over the canonical BRC-100 preimage, DER hex-encoded. */
  "x-brc100-signature": string;
  /** Sender's BRC-52 cert, JSON-serialised. */
  "x-brc52-certificate": string;
}

// ── SignedBundle envelope (§12.1) ────────────────────────────────────────────

/**
 * Full SignedBundle<T> envelope — the mandatory wrapper for every
 * cross-process or cross-node message (§12.1).
 *
 * Canonical term: SignedBundle (glossary id: signed-bundle).
 * The canonical wire format is CBOR; JSON fallback is used where CBOR is
 * impractical (e.g. Phoenix WebSocket params — see D-V3).
 *
 * Type parameter T is the vertical-specific payload type.
 *
 * Spec source: docs/spec/protocol-v0.5.md §12.1.
 */
export interface SignedBundle<T = unknown> extends Brc100Headers {
  /** Vertical-specific payload, opaque to the Verifier Sidecar. */
  payload: T;
}

// ── Stored cert record (legacy / internal) ───────────────────────────────────

/**
 * Stored certificate record (internal persistence model).
 *
 * The cert_id is the SHA-256 of the canonical BRC-52 preimage (§4.2).
 * This is the record shape stored in the Plexus DAG database.
 *
 * @deprecated For wire-format use Brc52Cert. This type is kept for
 *   backward compat with existing Plexus SDK persistence code.
 */
export interface PlexusCert {
  /** 32-byte hex hash of the canonical BRC-52 certificate preimage. */
  certId: string;
  /** 33-byte compressed public key, hex-encoded. */
  publicKey: string;
  /** Email or name used during registration (root certs only). */
  email?: string;
  /** Parent cert_id (null for root identities). */
  parentCertId: string | null;
  /** Monotonic child index under the parent context. */
  childIndex: number;
  /** Resource identifier for this node (e.g., "Developer", "trades.job"). */
  resourceId?: string;
  /** 4-byte uint32 domain flag. */
  domainFlag?: number;
  /** Derivation path from root (e.g., "root" or "root/Developer:65538:0"). */
  derivationPath: string;
  /** Unix timestamp in milliseconds. */
  createdAt: number;
}

// ── Canonical IdentityProvider (W1.5C-1 unification) ────────────────────────

/**
 * Minimal cert handle returned by getCert() on both the signing surface
 * (D-A2 EphemeralIdentityProvider — returns a full Brc52Cert) and the
 * cert-manager surface (D-A3 IdentityStore — returns a HatCertSnapshot).
 *
 * Both shapes satisfy this structural minimum: `{ certId: string }`.
 * Wave-2 transport adapters (D-C2/D-C3) can narrow to `Brc52Cert` via
 * type guard `isBrc52Cert(cert)` when they need the full wire format.
 *
 * W1.5C-1: `Brc52Cert extends CertHandle` and `HatCertSnapshot extends
 * CertHandle`; the IdentityProvider interface uses this union to allow both
 * surfaces to implement the same interface without a structural break.
 */
export interface CertHandle {
  /** 32-byte hex SHA-256 of the canonical BRC-52 preimage. */
  certId: string;
}

/**
 * Type guard: true iff `cert` carries the full BRC-52 wire fields.
 *
 * Wave-2 transport code (D-C2/D-C3) should use this to distinguish a
 * full Brc52Cert (ready to embed in x-brc52-certificate) from a
 * HatCertSnapshot (cert_id only, must fetch the full cert separately).
 */
export function isBrc52Cert(cert: CertHandle): cert is Brc52Cert {
  return (
    "subjectPublicKey" in cert &&
    "certifierPublicKey" in cert &&
    "type" in cert &&
    "serialNumber" in cert &&
    "fields" in cert &&
    "signature" in cert
  );
}

/**
 * IdentityProvider — canonical interface for BRC-52 cert + BRC-42 signing.
 *
 * W1.5C-1 unifies two prior definitions:
 *   - D-A2 (apps/world-client/src/identity-provider.ts): getCert() returns
 *     a full Brc52Cert; sign() returns a DER-encoded hex signature.
 *   - D-A3 (runtime/services/src/services/IdentityStore.ts): getCert()
 *     returns a HatCertSnapshot (certId + publicKey + hatId);
 *     whenCertReady() resolves on first cert issuance.
 *
 * The unified interface subsumes both via the `CertHandle` union type.
 * Implementors that only manage cert-readiness (D-A3 IdentityStore) may
 * provide a `sign()` that throws `"not implemented"` — the D-A3 surface
 * is boot-readiness only, not request-signing.
 *
 * Design notes:
 *   - getCert() and getCertId() accept both sync and async forms.
 *   - sign() MUST return a DER-encoded ECDSA signature hex string for
 *     BRC-100 request-signing implementations (D-A2, future D-C2/D-C3).
 *   - getIdentityKeyHex() is optional — only required by WorldSocket (D-A2).
 *   - whenCertReady() is optional — only implemented by IdentityStore (D-A3).
 *
 * Spec source: docs/spec/protocol-v0.5.md §4 (Identity), §12.1 (SignedBundle).
 * BRC compliance: BRC-100 (signed-request standard), BRC-52 (cert format),
 *   BRC-42 (key derivation — delegated to the implementation).
 * Canon discipline: docs/canon/glossary.yml entries brc-52, cert-id,
 *   signed-bundle, brc-100, brc-42.
 */
export interface IdentityProvider {
  /**
   * Return the cert handle for this session, or null if not yet available.
   *
   * May be a full Brc52Cert (D-A2 signing surface) or a HatCertSnapshot
   * (D-A3 cert-manager surface). Use `isBrc52Cert(cert)` to narrow.
   *
   * May return synchronously or asynchronously.
   */
  getCert(): CertHandle | null | Promise<CertHandle | null>;

  /**
   * Return the cert_id of the active cert, or null if not yet available.
   *
   * Canonical wire field name: cert_id (per §12.1, D-A1 naming).
   */
  getCertId(): string | null | Promise<string | null>;

  /**
   * Sign arbitrary bytes using the session's BRC-42-derived private key.
   *
   * Per BRC-100 (§12.1): SHA-256(bytes) → ECDSA over secp256k1 → DER hex.
   * Matches `@bsv/sdk`'s `PrivateKey.sign(digest, 'hex', true)` convention.
   *
   * Cert-manager implementations (D-A3 IdentityStore) that do not hold
   * a private key SHOULD throw `new Error("sign() not available on cert-manager")`.
   */
  sign(bytes: Uint8Array): Promise<string> | string;

  /**
   * Return the 33-byte compressed secp256k1 public key, hex-encoded.
   *
   * This is the `x-brc100-identitykey` value; MUST match cert.subjectPublicKey.
   * Optional — only required by WorldSocket (D-A2).
   */
  getIdentityKeyHex?(): string;

  /**
   * Promise that resolves once a cert is available.
   *
   * Optional — only implemented by Helm/IdentityStore (D-A3). Boot-time
   * callers await this before issuing any authenticated backend call.
   */
  whenCertReady?(): Promise<CertHandle>;
}

// ── IdentityAdapter (kernel gateway, Phase 26A — unchanged) ─────────────────

/**
 * IdentityAdapter — the kernel's gateway to identity and capability validation.
 *
 * All kernel identity and graph operations flow through this interface.
 * No vendor types leak into the kernel. No vendor SDK imports outside
 * the adapter implementation files.
 *
 * Rule: All method signatures use ONLY primitive types (string, number,
 * boolean, Record<string, string>). No vendor-internal types cross this
 * boundary.
 */

// === Configuration ===

/** Determines which adapter implementation to use. */
export type IdentityMode = 'stub' | 'local' | 'cloud';

/** Configuration for adapter initialization. */
export interface IdentityConfig {
  mode: IdentityMode;
  /** Endpoint for local/cloud modes. Not used by stub. */
  endpoint?: string;
  /** Enable debug logging of adapter operations. */
  debugLogging?: boolean;
}

/**
 * Kernel-native error type for all identity operations.
 *
 * All identity errors are mapped to this type before surfacing to kernel code.
 * Never expose vendor-internal error types outside the adapter implementation.
 */
export interface IdentityError {
  /** Error code: CERT_NOT_FOUND, INVALID_DOMAIN, RECOVERY_FAILED, SESSION_NOT_FOUND, etc. */
  code: string;
  message: string;
  /** True if the operation can be retried. */
  recoverable: boolean;
}

/** Construct an IdentityError value. */
export function makeIdentityError(code: string, message: string, recoverable: boolean): IdentityError {
  return { code, message, recoverable };
}

/** Snapshot of adapter state for useSyncExternalStore. */
export interface IdentityState {
  currentIdentity?: {
    certId: string;
    email?: string;
  };
  identities: Map<string, {
    certId: string;
    publicKey: string;
    created: number;
  }>;
  edges: Map<string, {
    edgeId: string;
    initiator: string;
    responder: string;
  }>;
  lastOperation?: {
    method: string;
    timestamp: number;
    success: boolean;
  };
}

// === Adapter Interface ===

/**
 * IdentityAdapter — the kernel's only touchpoint to the identity/graph layer.
 *
 * In production, backed by a real identity SDK (cloud or local).
 * In dev/test, backed by StubIdentityAdapter.
 * The kernel never knows which implementation it's using.
 */
export interface IdentityAdapter {
  /**
   * Register a new identity.
   *
   * @param email - user email or name
   * @returns certId (unique identity certificate ID, hex-prefixed) and publicKey (PEM format)
   */
  registerIdentity(email: string): Promise<{
    certId: string;
    publicKey: string;
  }>;

  /**
   * Derive a child identity (hat) under an existing parent.
   *
   * Enforces monotonic child_index: once an index is used, it is never reused,
   * even if the child is deleted.
   *
   * @param parentCertId - cert_id of the parent identity
   * @param resourceId - unique identifier for the resource owned by this hat
   * @param domainFlag - domain flag (client-defined: 0x00010001=View, 0x00010002=Create, etc.)
   * @returns certId of the child, publicKey, child_index used
   */
  deriveChild(parentCertId: string, resourceId: string, domainFlag: number): Promise<{
    certId: string;
    publicKey: string;
    childIndex: number;
  }>;

  /**
   * Resolve an identity by cert_id to retrieve its state and children.
   *
   * @param certId - certificate ID to resolve
   * @returns cert metadata and tree structure
   */
  resolveIdentity(certId: string): Promise<{
    certId: string;
    publicKey: string;
    email?: string;
    created: number;
    updated: number;
    children?: Array<{ certId: string; childIndex: number; resourceId: string }>;
  }>;

  /**
   * Create an edge (authenticated connection) between two identities.
   *
   * Both parties must have their certs registered. The edge stores a shared secret
   * hash derived from both parties' keys.
   *
   * @param initiatorCertId - cert_id of the identity initiating the edge
   * @param responderCertId - cert_id of the identity receiving the edge
   * @returns edgeId and sharedSecret hash
   */
  createEdge(initiatorCertId: string, responderCertId: string): Promise<{
    edgeId: string;
    sharedSecret: string;
  }>;

  /**
   * Query a subtree rooted at a given cert_id, up to specified depth.
   *
   * @param rootCertId - cert_id of the root to query
   * @param depth - how many levels deep to traverse (1, 2, 3, etc.)
   * @returns tree structure with all descendants up to depth
   */
  querySubtree(rootCertId: string, depth: number): Promise<{
    root: string;
    children: Array<{
      certId: string;
      childIndex: number;
      resourceId: string;
      grandchildren?: Array<{
        certId: string;
        childIndex: number;
        resourceId: string;
      }>;
    }>;
  }>;

  /**
   * Present a capability to prove authorization for an operation.
   *
   * In stub mode, all capabilities are valid. In production, validates against
   * the Capability Domain.
   *
   * @param certId - cert_id presenting the capability
   * @param capabilityId - capability identifier
   * @returns validity result
   */
  presentCapability(certId: string, capabilityId: string): Promise<{
    valid: boolean;
    reason?: string;
  }>;

  /**
   * Initiate identity recovery flow.
   *
   * @param email - email of the identity to recover
   * @returns sessionId and challenge set
   */
  initiateRecovery(email: string): Promise<{
    sessionId: string;
    challengeCount: number;
    challenges?: Array<{ id: string; prompt: string }>;
  }>;

  /**
   * Submit recovery challenge answers.
   *
   * @param sessionId - from initiateRecovery()
   * @param answers - array of challenge answers
   * @returns verification result with optional export payload
   */
  submitChallengeAnswers(
    sessionId: string,
    answers: Array<{ challengeId: string; answer: string }>,
  ): Promise<{
    verified: boolean;
    exportPayload?: string;
  }>;

  /**
   * Send an authenticated message via identity transport.
   *
   * In stub mode, this is a no-op log. In production, routes through Network SDK.
   *
   * @param senderCertId - cert_id of the sender
   * @param receiverCertId - cert_id of the receiver
   * @param payload - JSON-serializable message
   * @returns messageId
   */
  sendAuthenticated(
    senderCertId: string,
    receiverCertId: string,
    payload: Record<string, string>,
  ): Promise<{ messageId: string }>;

  /**
   * Derive a child public key from a parent public key + an arbitrary
   * segment, WITHOUT registering the derived key as a hat / cert.
   *
   * This is the L11 (EP3259724B1) pubkey-side primitive made available
   * through the substrate-side adapter port. Cartridges that follow
   * the greenfield discipline (TESSERA-CARTRIDGE.md §0.1 #2 + the
   * tessera-adapter-consumption gate) cannot import `@plexus/vendor-sdk`
   * or `@bsv/sdk` directly; this method gives them access to the L11
   * derivation surface through the allowed `@semantos/protocol-types`
   * substrate seam.
   *
   * Mechanism (EP3259724B1, pubkey side):
   *
   *   child_pub = parent_pub + SHA-256(segment) * G
   *
   * where `G` is the secp256k1 generator. By curve linearity, this is
   * byte-equal to `deriveSegment(parentPriv, segment).toPublicKey()`
   * (proven in @plexus/vendor-sdk derive-segment tests). The caller
   * does NOT need access to the parent's private key — only the
   * parent's public key in 66-char hex SEC1 compressed form.
   *
   * Use cases:
   *   - Tessera per-cell owner pubkeys derived from an operator root
   *     (per-bottle, per-care-event, etc.) without registering each
   *     as a hat
   *   - Any cartridge that needs internal key trees but follows the
   *     no-@bsv/sdk-imports discipline
   *
   * Returns the derived child pubkey in the same 66-char hex SEC1
   * compressed form. The result is deterministic for the same
   * (parentPubKeyHex, segment) inputs.
   *
   * Caller contract:
   *   - parentPubKeyHex MUST be a 66-char lowercase hex SEC1
   *     compressed pubkey (starts with `02` or `03`).
   *   - segment MAY be either UTF-8 string or raw byte array.
   *   - Implementations MUST be deterministic.
   *
   * CW Lift L11 substrate-side port (docs/canon/cw-lift-matrix.yml).
   *
   * @param parentPubKeyHex 66-char hex SEC1 compressed parent pubkey
   * @param segment derivation segment (string is utf-8 encoded)
   * @returns derived child pubkey hex (same format as parent)
   */
  deriveSegmentPublicKey(
    parentPubKeyHex: string,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }>;

  /**
   * L11.5 — DOMAIN-SEPARATED public-key derivation (kdf-v3).
   *
   *   child_pub = parent_pub + SHA-256( u32_be(domainFlag) ‖ segment ) * G
   *
   * Folds the canonical u32 `domainFlag` into the derivation tweak as a
   * domain separator (the same flag the cell header carries and
   * `OP_CHECKDOMAINFLAG` asserts), binding the derived key to its declared
   * domain. Byte-equal to `deriveDomainSegment(parentPriv, domainFlag,
   * segment).toPublicKey()`. Additive companion to `deriveSegmentPublicKey`
   * (v2, bare segment) — new domain-bound consumers use this.
   *
   * @param parentPubKeyHex 66-char hex SEC1 compressed parent pubkey
   * @param domainFlag canonical u32 domain flag (big-endian tag)
   * @param segment derivation segment (string is utf-8 encoded)
   * @returns derived child pubkey hex (same format as parent)
   *
   * See docs/canon/domainflag-tag-unification.md.
   */
  deriveDomainSegmentPublicKey(
    parentPubKeyHex: string,
    domainFlag: number,
    segment: Uint8Array | string,
  ): Promise<{ childPubKeyHex: string }>;
}

```
