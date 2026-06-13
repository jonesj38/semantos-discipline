---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/identity-ports/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.943075+00:00
---

# core/identity-ports/src/types.ts

```ts
/**
 * Application-facing port interfaces for the Plexus surface.
 *
 * These are **consumer-shaped** — semantos-core apps depend on these, not on
 * the underlying `@plexus/vendor-sdk` class. The binding adapter
 * (`vendor-sdk-binding.ts`) wires the vendor SDK into these shapes; the stub
 * binding (`stub-binding.ts`) implements them in-memory for tests + demos.
 *
 * Splitting attestation and capability from identity follows Plexus's own
 * domain decomposition (Identity Domain §9, Recovery Service §11 + Attestation
 * Authority natural byproduct, Capability Domain §7). Keeping them separate
 * matches the data-model boundary (authority_keys vs capability UTXOs) so the
 * eventual real bindings are 1:1 wraps.
 */

import type {
  ChallengeAnswer,
  ChallengeSpec,
  EdgeRecoveryPolicy,
  PlexusCert,
} from '@plexus/contracts';

// ─── identityPort ─────────────────────────────────────────────────────────

/**
 * Result of registering or resolving an identity.
 * `certId` is the 32-byte SHA-256 of the canonical BRC-52 preimage.
 * `publicKey` is the 33-byte compressed secp256k1 key, hex-encoded.
 */
export interface IdentityRegistration {
  readonly certId: string;
  readonly publicKey: string;
}

/** A single child node under a parent in the DAG. */
export interface ChildNodeRef {
  readonly certId: string;
  readonly childIndex: number;
  readonly resourceId: string;
}

/** Detailed identity record returned by `resolveIdentity`. */
export interface IdentityResolution extends IdentityRegistration {
  readonly email?: string;
  readonly created: number;
  readonly updated: number;
  readonly children: readonly ChildNodeRef[];
}

/** Result of a `deriveChild` call. */
export interface ChildDerivation extends IdentityRegistration {
  readonly childIndex: number;
}

/**
 * Result of an edge creation.
 *
 * Per Plexus §2.5.5: the ECDH shared secret is NEVER returned or stored at
 * any layer — not even as a hash. The client re-derives it locally from
 * `signingKeyIndex` (the BKDS invoiceNumber) when it needs it for messaging.
 */
export interface EdgeCreation {
  readonly edgeId: string;
  /**
   * BKDS signing key index (invoiceNumber). The sole persisted derivation
   * parameter — the client uses it to re-derive the ECDH shared secret
   * locally without ever exposing that secret to a server or storage layer.
   */
  readonly signingKeyIndex: number;
}

/** A traversed subtree returned by `querySubtree`. */
export interface SubtreeQuery {
  readonly root: string;
  readonly children: ReadonlyArray<
    ChildNodeRef & {
      readonly grandchildren?: readonly ChildNodeRef[];
    }
  >;
}

/**
 * `identityPort` — BRC-52 cert lifecycle + BRC-42 hierarchical derivation.
 *
 * Maps to Plexus's Identity Domain (§9) and the on-device subset of the Vendor
 * SDK (§5). All key derivation runs client-side; the port never returns or
 * accepts raw private keys.
 */
export interface IdentityPort {
  /**
   * Register a root identity (e.g. on first device or after recovery).
   * Idempotent per email — calling twice with the same email returns the
   * same `certId`.
   */
  registerIdentity(email: string): IdentityRegistration;

  /** Look up a cert by `certId`. Throws `CERT_NOT_FOUND` on miss. */
  resolveIdentity(certId: string): IdentityResolution;

  /**
   * BRC-42-derived child cert under a parent. `childIndex` is monotonic per
   * (parentCertId, resourceId, domainFlag) — same inputs always yield the
   * same `certId` (deterministic recovery contract).
   */
  deriveChild(
    parentCertId: string,
    resourceId: string,
    domainFlag: number,
  ): ChildDerivation;

  /**
   * Establish an ECDH edge between two existing certs. Returns the stable
   * `edgeId` and the BKDS `signingKeyIndex` needed to re-derive the ECDH
   * shared secret locally. Per §2.5.5 the raw secret (and any hash of it)
   * is never surfaced — callers that need it must re-derive from the index.
   * `edgeRecoveryPolicy` determines whether the edge is enrolled in the
   * Plexus recovery substrate (BACKUP_ON_CREATE) or kept ephemeral (NONE).
   */
  createEdge(
    initiatorCertId: string,
    responderCertId: string,
    edgeRecoveryPolicy?: EdgeRecoveryPolicy,
  ): EdgeCreation;

  /** Traverse the DAG breadth-first up to `depth` levels under `rootCertId`. */
  querySubtree(rootCertId: string, depth: number): SubtreeQuery;

  /**
   * Return the full BRC-52 cert record (parent chain, derivation path, etc.)
   * — used by host apps that need to render or audit the identity tree.
   * Returns `null` if the cert is unknown.
   */
  getCert(certId: string): PlexusCert | null;
}

// ─── recoveryPort ─────────────────────────────────────────────────────────

/** Snapshot returned when a recovery session is initiated. */
export interface RecoveryInitiation {
  readonly sessionId: string;
  readonly challengeCount: number;
  readonly challenges: readonly ChallengeSpec[];
}

/**
 * Outcome of submitting challenge answers. On success carries the
 * BRC-100-signed export payload (~3.4KB per Plexus §11) — base64-encoded
 * JSON the client decodes locally to reconstruct its key universe.
 */
export interface RecoveryVerdict {
  readonly verified: boolean;
  /** Present iff `verified === true`. */
  readonly exportPayload?: string;
}

/**
 * `recoveryPort` — the 4-phase Plexus recovery flow (§11):
 *
 *   Phase 1: Email OTP (omitted from this port — handled by the host app's
 *            email verification UI, then `initiateRecovery` is called).
 *   Phase 2: Challenge response — `initiateRecovery` + `submitChallengeAnswers`.
 *   Phase 3: Metadata export — returned in `RecoveryVerdict.exportPayload`.
 *   Phase 4: Client-side reconstruction — caller decodes the export and
 *            re-runs PBKDF2 + BRC-42 locally. The port does NOT execute
 *            key derivation server-side (Plexus zero-key-custody contract).
 */
export interface RecoveryPort {
  initiateRecovery(email: string): RecoveryInitiation;
  submitChallengeAnswers(
    sessionId: string,
    answers: readonly ChallengeAnswer[],
  ): RecoveryVerdict;
}

// ─── attestationPort ──────────────────────────────────────────────────────

/**
 * SPV-verifiable continuity proof signed by the Plexus RaaS entity's
 * ATTESTATION (0x05) domain key. Third parties verify via standard
 * BRC-52 / BRC-100 paths; the proof never carries raw private material.
 */
export interface SPVAttestation {
  /** Subject cert this attestation speaks about. */
  readonly certId: string;
  /** Statement type — 'continuity', 'edge_presence', or 'app_presence'. */
  readonly kind: 'continuity' | 'edge_presence' | 'app_presence';
  /** Hex-encoded ECDSA signature over the canonical preimage. */
  readonly signature: string;
  /** RaaS authority public key that signed this attestation (33-byte compressed hex). */
  readonly attestorPublicKey: string;
  /** Unix ms when the attestation was generated. */
  readonly generatedAt: number;
  /**
   * Verifier marker — production attestations are 'spv'; stubs return
   * 'stub' so consumers can detect a non-production binding without
   * type-casting.
   */
  readonly verified: 'spv' | 'stub';
}

/**
 * `attestationPort` — Plexus Recovery Service's natural byproduct (§11).
 * Plexus keeps Attestation Authority distinct from Capability Domain because
 * their data models differ (authority_keys vs capability UTXOs); we mirror
 * that separation here.
 */
export interface AttestationPort {
  /** Prove a cert existed and was active at attestation time. */
  proveContinuity(certId: string): Promise<SPVAttestation>;
  /** Prove an active edge of `edgeType` exists (BRC-94 zero-knowledge). */
  proveEdgePresence(certId: string, edgeType: string): Promise<SPVAttestation>;
  /** Prove a cert is registered against a given app/resource. */
  proveAppPresence(certId: string, resourceId: string): Promise<SPVAttestation>;
}

// ─── capabilityPort ───────────────────────────────────────────────────────

/**
 * Capability token types per Plexus §6. Each type maps to a specific
 * BRC-108 Identity-Linked Token UTXO bound to a BRC-52 cert.
 */
export type CapabilityType =
  | 'recovery'
  | 'permission'
  | 'data_access'
  | 'compute_delegation'
  | 'metered_access'
  | 'transfer';

/**
 * Result of a capability presentation/verification check. Production
 * implementations perform indexer-less SPV via BEEF; stubs return a
 * marker in `verifier` so consumers can detect the non-production case.
 */
export interface CapabilityCheck {
  readonly valid: boolean;
  readonly reason?: string;
  readonly verifier: 'spv' | 'stub';
}

/**
 * `capabilityPort` — Plexus Capability Domain (§7). Linear-by-default per
 * Plexus's 2-PDA evaluator classification (cap.transfer is AFFINE, not
 * exposed via this port — transfers are a separate flow).
 *
 * MVP shape: `present` only. Mint/consume/transfer are deferred until the
 * real Capability Domain is wired up in PR-C; stub binding throws
 * `NOT_IMPLEMENTED` for those today so downstream code that accidentally
 * depends on them fails loudly instead of silently doing nothing.
 */
export interface CapabilityPort {
  /**
   * Present a capability for verification. Production: SPV-checks a BRC-108
   * UTXO bound to `certId` is valid + unspent. Stub: looks up an in-memory
   * map.
   */
  present(certId: string, capabilityId: string): CapabilityCheck;
}

// ─── economicPort ─────────────────────────────────────────────────────────

/**
 * Signed-spend artifact returned by `economicPort.signSpend`. The shape is
 * intentionally minimal: a `txAnchor` (typically a hex tx-id or
 * BEEF-rooted reference) that downstream code can lift into a `PAYS`
 * relation via `createRelation({ kind: 'PAYS', extra: { txAnchor } })`.
 *
 * Production bindings perform real BRC-100 wallet signing through the
 * Plexus Wallet Domain (§13). Stubs return a deterministic anchor
 * suitable for tests + demos.
 */
export interface SignedSpend {
  /** Hex-encoded tx-id (or BEEF root) the relation can reference. */
  readonly txAnchor: string;
  /** Smallest-unit amount actually committed by this spend. */
  readonly amount: number;
  /** Currency code that matches the relation's currency. */
  readonly currency: string;
  /**
   * Verifier marker — production spends are 'spv'; stub bindings return
   * 'stub' so consumers can detect a non-production binding without
   * type-casting.
   */
  readonly verifier: 'spv' | 'stub';
}

/** Input shape for `signSpend`. */
export interface SignSpendInput {
  readonly payerCertId: string;
  readonly targetId: string;
  readonly amount: number;
  readonly currency: string;
  /** Optional caller-supplied memo; opaque to the port. */
  readonly memo?: string;
}

/** Outcome of `verifyPayment`. */
export interface PaymentVerification {
  readonly valid: boolean;
  /** Present when invalid — short machine-readable reason. */
  readonly reason?: string;
  readonly verifier: 'spv' | 'stub';
}

/**
 * `economicPort` — the money-bearing surface for SCG relations (RM-062).
 *
 * Two narrow operations:
 *   - `signSpend`: the wallet authors a spend. Returns the `txAnchor`
 *     the caller threads into `createRelation({ kind: 'PAYS', ... })`.
 *   - `verifyPayment`: given an existing `(txAnchor, amount, currency)`,
 *     does the on-chain (or stubbed) state confirm the payment?
 *
 * This port is the seam between SCG's typed payment relations and the
 * actual wallet substrate. The access-gate at
 * `@semantos/scg-relations::requirePaymentRelation` consults *relation
 * rows*, not this port — anchoring verification is a separate concern
 * the gate's caller orchestrates by handing the relation's `txAnchor`
 * to `verifyPayment` (or `@semantos/anchor-attestation::verifyAnchor`).
 */
export interface EconomicPort {
  signSpend(input: SignSpendInput): Promise<SignedSpend>;
  verifyPayment(input: {
    readonly txAnchor: string;
    readonly amount: number;
    readonly currency: string;
  }): Promise<PaymentVerification>;
}

```
