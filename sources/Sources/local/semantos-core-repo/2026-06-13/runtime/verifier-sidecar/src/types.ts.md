---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.084811+00:00
---

# runtime/verifier-sidecar/src/types.ts

```ts
/**
 * Verifier Sidecar — public interface types.
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5 (Verifier Sidecar),
 *              §12.1 (SignedBundle envelope), §4 (Identity protocol).
 * Textbook citation: docs/textbook/14-verifier-sidecar.md.
 *
 * Canonical term: Verifier Sidecar (per docs/canon/glossary.yml id: verifier-sidecar).
 * D-V1 deliverable — Phase 0.5 (blocks D-V3).
 *
 * Key invariant: K2 — any state-changing transition requires successful
 * identity verification.  The Verifier Sidecar is the mechanism that makes
 * K2's assumption true at the system level (boundary check before kernel).
 *
 * BRC compliance:
 *   BRC-100  — signed-request standard (every cross-process/cross-node message)
 *   BRC-52   — certificate format (identity binding, cert_id = SHA-256(preimage))
 *   BRC-42   — key derivation (child keys derived under parent cert)
 *   BRC-74   — BUMP merkle proof (SPV: minting transaction in a block)
 *   BRC-95   — atomic-BEEF (SPV: transaction ancestry)
 *   BRC-108  — capability token (LINEAR UTXO bound to a BRC-52 cert subject)
 */

// ── Raw SignedBundle envelope headers (from §12.1) ──────────────────────────

/**
 * Raw wire envelope as it arrives at an adapter boundary.
 * Matches §12.1 header table exactly.
 *
 * Canonical type name: SignedBundle (glossary id: signed-bundle).
 */
export interface RawSignedBundle {
  /** 33-byte compressed secp256k1 public key, hex-encoded. BRC-100 field. */
  "x-brc100-identitykey": string;
  /** 32-byte anti-replay nonce, hex-encoded. BRC-100 field. */
  "x-brc100-nonce": string;
  /** Milliseconds since epoch. BRC-100 field. */
  "x-brc100-timestamp": string | number;
  /** ECDSA signature over canonical preimage, DER hex-encoded. BRC-100 field. */
  "x-brc100-signature": string;
  /** Sender's BRC-52 cert, JSON-serialised. BRC-52 field. */
  "x-brc52-certificate": string;
  /** Vertical-specific payload, opaque to the sidecar. */
  payload: unknown;
}

// ── BRC-52 certificate (from §4.2) ─────────────────────────────────────────

/**
 * BRC-52 certificate as carried in x-brc52-certificate.
 * cert_id = SHA-256(canonical_preimage over all fields except signature).
 *
 * Canonical term: cert (glossary id: brc-52).
 * Wire field name: cert_id (snake_case); camelCase certId in TS per convention.
 */
export interface Brc52Certificate {
  /** 32-byte hex: SHA-256 of the canonical preimage. Stable identity hash. */
  certId: string;
  /** 33-byte compressed public key of the subject, hex-encoded. */
  subjectPublicKey: string;
  /** 33-byte compressed public key of the certifier (parent or self), hex-encoded. */
  certifierPublicKey: string;
  /** Certificate type identifier. */
  type: string;
  /** Unique serial number for this certificate. */
  serialNumber: string;
  /** Application-defined fields. */
  fields: Record<string, string>;
  /** Issuer signature over canonical preimage, DER hex-encoded. */
  signature: string;
}

// ── Capability UTXO (BRC-108) ───────────────────────────────────────────────

/**
 * Capability token reference carried in a SignedBundle when the action
 * requires a capability authority check.
 *
 * Canonical term: capability token (glossary id: capability-token).
 * BRC-108 — Identity-Linked Token Protocol.
 * SPV check: BUMP (BRC-74) + atomic-BEEF (BRC-95) + liveness.
 */
export interface CapabilityTokenRef {
  /** Transaction ID of the minting output, hex. */
  txId: string;
  /** Output index of the capability UTXO. */
  vout: number;
  /**
   * BUMP (BRC-74) merkle proof bytes, hex-encoded.
   * Proves the minting transaction is in a block.
   */
  bumpHex?: string;
  /**
   * Atomic-BEEF (BRC-95) transaction envelope, hex-encoded.
   * Proves transaction ancestry.
   */
  beefHex?: string;
}

// ── Verification result ─────────────────────────────────────────────────────

/**
 * Outcome of a single Verifier Sidecar check.
 * Discriminated union: ok:true carries verified identity; ok:false carries
 * an error code and human-readable message.
 *
 * Never throws — callers MUST handle both branches explicitly.
 */
export type VerificationResult =
  | {
      ok: true;
      /** Verified cert_id (32-byte hex). */
      certId: string;
      /** Verified 33-byte compressed public key (hex) matching certificate.subject. */
      identityKey: string;
    }
  | {
      ok: false;
      code: VerificationErrorCode;
      message: string;
    };

/**
 * Error codes emitted by the Verifier Sidecar.
 *
 * Fail-fast ordering (cheapest first per textbook §14):
 *   brc100_*     — Phase 1 (signature)
 *   brc52_*      — Phase 2 (certificate authenticity + identity binding)
 *   capability_* — Phase 3 (capability UTXO SPV + liveness)
 *   envelope_*   — structural / malformed input
 */
export type VerificationErrorCode =
  // Phase 1 — BRC-100 signature
  | "brc100_missing_field"
  | "brc100_bad_encoding"
  | "brc100_invalid_signature"
  | "brc100_timestamp_out_of_window"
  | "brc100_replay_detected"
  // Phase 2 — BRC-52 cert authenticity + identity binding
  | "brc52_malformed_cert"
  | "brc52_cert_id_mismatch"
  | "brc52_issuer_signature_invalid"
  | "brc52_identity_binding_mismatch"
  | "brc52_subject_key_mismatch"
  // Phase 3 — capability UTXO SPV + liveness
  | "capability_spv_invalid"
  | "capability_utxo_spent"
  | "capability_liveness_expired"
  // Structural
  | "envelope_malformed"
  | "envelope_payload_missing";

// ── Verifier interface ──────────────────────────────────────────────────────

/**
 * The Verifier Sidecar interface.
 *
 * Canonical term: Verifier Sidecar (glossary id: verifier-sidecar).
 * Implements the three-phase verification pipeline:
 *   Phase 1 — BRC-100 signature check (fail-fast)
 *   Phase 2 — BRC-52 cert authenticity + identity binding
 *   Phase 3 — capability UTXO SPV + liveness (when envelope cites a capability)
 *
 * Every adapter that receives external messages MUST call verify() before
 * dispatching to any handler that would mutate state (K2 boundary guarantee).
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5.
 */
export interface Verifier {
  /**
   * Verify a raw SignedBundle envelope.
   *
   * Runs the three-phase pipeline.  On ok:true, the returned certId and
   * identityKey are safe to pass into the cell engine (K2 guarantee).
   * On ok:false, the envelope MUST NOT be processed.
   *
   * @param envelope  - Raw SignedBundle headers + payload.
   * @param capToken  - Optional capability token reference; triggers Phase 3
   *                    when present.
   */
  verify(
    envelope: RawSignedBundle,
    capToken?: CapabilityTokenRef,
  ): Promise<VerificationResult>;
}

// ── SPV provider interface ──────────────────────────────────────────────────

/**
 * Interface the BrcVerifier delegates to for capability UTXO liveness.
 *
 * Three liveness mechanisms are documented in textbook §14:
 *   1. UTXO overlay query (most accurate, requires network)
 *   2. Watchman pattern (latency depends on propagation)
 *   3. Signed timestamp (bounded expiry window)
 *
 * This interface abstracts over all three. Implementations inject
 * their chosen mechanism at construction time (dependency injection).
 *
 * Canonical term: SPV (glossary id: spv).
 * BRC-74 (BUMP) + BRC-95 (atomic-BEEF) prove inclusion; liveness is separate.
 */
export interface SpvProvider {
  /**
   * Check whether a given capability UTXO is unspent and its SPV proof valid.
   *
   * Returns true iff:
   *   - The BUMP proof (when provided) verifies correctly.
   *   - The UTXO has not been consumed (liveness check passes).
   *
   * @param capToken - Capability token reference with txId, vout, and
   *                   optional BUMP/BEEF proofs.
   */
  isUnspent(capToken: CapabilityTokenRef): Promise<boolean>;
}

// ── Nonce cache interface ───────────────────────────────────────────────────

/**
 * Anti-replay nonce cache (§14 textbook — "nonce and timestamp replay
 * prevention").
 *
 * The sidecar MUST maintain a nonce cache with a time-bounded expiry window.
 * An envelope whose nonce has already been seen MUST be rejected.
 *
 * Implementors: InMemoryNonceCache (bundled) or any persistent store.
 */
export interface NonceCache {
  /**
   * Check whether the nonce was seen before.  Returns true if it is a
   * replay (already consumed); false if fresh.
   *
   * MUST be called before the nonce is recorded.
   */
  hasNonce(nonce: string): boolean;
  /**
   * Record a nonce as consumed.  Called only after the signature check
   * passes so we don't fill the cache with junk from bad envelopes.
   *
   * @param nonce    - The hex nonce string.
   * @param expireMs - Absolute expiry time (Date.now() + window).
   */
  setNonce(nonce: string, expireMs: number): void;
}

// ── Configuration ───────────────────────────────────────────────────────────

/**
 * BrcVerifier construction options.
 *
 * All fields are optional; reasonable defaults are provided for
 * development/test use.  Production deployments SHOULD set all fields.
 */
export interface BrcVerifierOptions {
  /**
   * Maximum age of an envelope timestamp in milliseconds before it is
   * considered stale and rejected.  Default: 300_000 (5 minutes).
   */
  timestampWindowMs?: number;
  /**
   * SPV + liveness provider for capability UTXO checks.
   * When absent, capability checks are skipped (development default).
   * Production deployments MUST supply a real provider.
   */
  spvProvider?: SpvProvider;
  /**
   * Nonce cache.  Defaults to InMemoryNonceCache with a 10-minute TTL.
   */
  nonceCache?: NonceCache;
  /**
   * Clock override for deterministic tests.  Defaults to Date.now.
   */
  nowMs?: () => number;
}

```
