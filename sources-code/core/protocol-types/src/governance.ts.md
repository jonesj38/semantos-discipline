---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/governance.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.852950+00:00
---

# core/protocol-types/src/governance.ts

```ts
/**
 * Extension Governance — hierarchical step-down model types.
 *
 * Three governance levels:
 *   L0 (Platform): GovernancePolicy — RELEVANT+Constitution, ballot-gated changes
 *   L1 (Author):   ExtensionManifest.governanceConfig — controls grammar evolution
 *   L2 (Consumer): GovernedConsumerBinding — node-scoped binding with encrypted credentials
 *
 * Constraints flow downward (L0→L1→L2). Disputes escalate upward via Ballot objects.
 * No separate governance engine — reuses Phase 18 Ballot/Dispute/Resolution from core.json.
 *
 * Cross-references:
 *   extension-manifest.ts       → ExtensionManifest.governanceConfig
 *   extension-grammar.ts        → ExtensionGrammar, MigrationRule
 *   configs/extensions/core.json → Ballot, Dispute, Resolution object types
 *   governance/constraint-engine.ts  → enforceL0Constraints, enforceL1Constraints
 *   governance/credential-vault.ts   → encryptCredentials, decryptCredentials
 *   governance/version-compat.ts     → checkCompatibility
 *   governance/dispute-escalator.ts  → createDisputeL2toL1, escalateDispute
 */

import type { MigrationRule } from './extension-grammar';

// ── L0: GovernancePolicy ───────────────────────────────────────

/** Platform-level governance policy (RELEVANT, Constitution). */
export interface GovernancePolicy {
  /** Object type path. */
  typePath: 'governance.policy';

  /** Linearity — always RELEVANT (immutable without ballot). */
  linearity: 'RELEVANT';

  /** Constitution flag — changes require ballot. */
  constitution: true;

  payload: GovernancePolicyPayload;
}

export interface GovernancePolicyPayload {
  /** Minimum meta-schema version for new grammars. */
  metaSchemaVersion: string;

  /** Capabilities required or recommended for all extensions. */
  requiredCapabilitiesWhitelist: string[];

  /** Taxonomy namespaces reserved by the platform. */
  taxonomyNamespaceReservations: TaxonomyNamespaceReservation[];

  /** Requirements for marketplace listing. */
  marketplaceListingRequirements: MarketplaceListingRequirements;

  /** Quorum threshold for breaking-change ballots (percentage, e.g. 66). */
  breakingChangeBallotQuorum: number;

  /** Emergency deprecation policy. */
  emergencyDeprecationPolicy: EmergencyDeprecationPolicy;

  /** When this policy was established (ISO 8601). */
  effectiveDate: string;

  /** Hat ID of the governing entity (Semantos core team multi-sig). */
  governedByHatId: string;
}

export interface TaxonomyNamespaceReservation {
  namespace: string;
  reason: string;
}

export interface MarketplaceListingRequirements {
  minAuthorReputationScore: number;
  minObjectCount: number;
  requiresAudit: boolean;
  auditFrequencyDays: number;
}

export interface EmergencyDeprecationPolicy {
  requiresVote: boolean;
  minDaysNotice: number;
  escalationThreshold: string;
}

// ── L1: Manifest Governance Config ─────────────────────────────

/** Governance configuration embedded in ExtensionManifest. */
export interface ManifestGovernanceConfig {
  /** Who can propose patches to the grammar. */
  patchAcceptancePolicy: 'author_only' | 'contributor_ballot' | 'open_ballot';

  /** Who can bump each semver component. */
  versionBumpRules: VersionBumpRules;

  /** Hat IDs allowed to propose patches (for ballot-based policies). */
  contributorHats: string[];

  /** Minimum days notice before deprecation takes effect. */
  deprecationTimelineMinDays: number;

  // ── Phase 38: Trust-tier fields ─────────────────────────────
  // Optional on the type, required at publication (enforced by
  // manifest-publisher). Omission is treated as "unpublishable until
  // declared." See governance/constraint-engine.ts for enforcement.

  /**
   * Trust tier for patches produced under this manifest's grammar.
   *   'cosmetic'      — no structural/semantic impact (UI, copy)
   *   'interpretive'  — semantic shift, needs hat attestation chain
   *   'authoritative' — authoritative economic claim, requires formal proof
   */
  trustClass?: 'cosmetic' | 'interpretive' | 'authoritative';

  /**
   * Proof obligation the trust class imposes on promotion.
   *   'none'        — cosmetic patches, no formal proof needed
   *   'attestation' — interpretive, requires hat attestation chain
   *   'formal'      — authoritative, requires Lean theorem reference (Window 7)
   *
   * Conservative-by-default enforcement (constraint-engine) rejects any
   * manifest with trustClass='authoritative' whose proofRequirement is
   * not 'formal', until Window 7 prover hookup exists.
   */
  proofRequirement?: 'none' | 'attestation' | 'formal';

  /**
   * Who/what can trigger execution on objects under this manifest.
   *   'local_hat' — only the owning hat (default, most conservative)
   *   'hat_scoped'  — any hat with the right hat cert (V2E model)
   *   'delegated'   — future federation, not implemented
   *
   * 'delegated' is rejected by the constraint engine until the federation
   * model is designed.
   */
  executionAuthority?: 'local_facet' | 'hat_scoped' | 'delegated';
}

export interface VersionBumpRules {
  major: 'author_only' | 'contributor_ballot';
  minor: 'author_only' | 'contributor_ballot';
  patch: 'author_only';
}

/** Deprecation status for a manifest or grammar version. */
export interface DeprecationStatus {
  isDeprecated: boolean;
  deprecatedDate?: string;
  sunsetDate?: string;
  replacementExtensionId?: string;
  migrationNotes?: string;
}

// ── L2: Governed Consumer Binding ──────────────────────────────

/**
 * Governance-level consumer binding (persistent object).
 *
 * Distinguished from the pipeline-level ConsumerBinding in stages.ts:
 * - This is the AFFINE object stored in the node's object store
 * - The pipeline binding is a lightweight runtime struct with decrypted credentials
 * - The pipeline constructs its binding from this + vault decryption
 */
export interface GovernedConsumerBinding {
  /** Object type path. */
  typePath: 'extension.consumer-binding';

  /** Linearity — AFFINE (mutable, node-scoped). */
  linearity: 'AFFINE';

  /** Scope — each node has its own bindings. */
  scope: 'node';

  payload: GovernedConsumerBindingPayload;
}

export interface GovernedConsumerBindingPayload {
  /** ID of the ExtensionManifest this binding is for. */
  extensionManifestId: string;

  /** Pinned grammar version range (semver, e.g. "^1.2.0" or "1.2.3"). */
  grammarVersionPinned: string;

  /** Encrypted API credentials — plaintext NEVER in evidence chains. */
  credentialsEncrypted: EncryptedCredentials;

  /** Local field additions (consumer adds to grammar). */
  fieldOverrides?: FieldOverride[];

  /** Local taxonomy mapping overrides. */
  taxonomyOverrides?: TaxonomyOverride[];

  /** Whether to auto-update grammar when new versions are published. */
  autoUpdateGrammar: boolean;

  /** Last time this binding was used to extract data (ISO 8601). */
  lastExtractionTimestamp?: string;

  /** Binding status. */
  status: 'active' | 'paused' | 'deprecated';
}

/** Encrypted credentials stored in the binding — plaintext never serialized. */
export interface EncryptedCredentials {
  /** Base64-encoded encrypted ciphertext. */
  encryptedBlob: string;
  /** Reference to the node's encryption key. */
  encryptionKeyId: string;
  /** Which fields are encrypted (for UI labels, not decryption). */
  credentialFieldNames: string[];
}

export interface FieldOverride {
  objectType: string;
  localFields: LocalField[];
}

export interface LocalField {
  fieldName: string;
  sourceType: string;
  description?: string;
  required: boolean;
}

export interface TaxonomyOverride {
  objectType: string;
  taxonomy: {
    what?: string;
    how?: string;
    why?: string;
    where?: string;
  };
}

// ── Constraint Engine Types ────────────────────────────────────

export interface ConstraintViolation {
  /** Which governance level's constraint was violated. */
  level: 'L0' | 'L1';
  /** Rule identifier (e.g. "required-capability-missing"). */
  rule: string;
  /** Human-readable message. */
  message: string;
  /** Optional structured details. */
  details?: unknown;
}

export interface ConstraintResult {
  valid: boolean;
  violations: ConstraintViolation[];
}

// ── Version Compatibility Types ────────────────────────────────

export interface CompatibilityResult {
  compatible: boolean;
  status: 'green' | 'yellow' | 'red';
  manifestVersion: string;
  consumerVersionPin: string;
  availableVersions: string[];
  migrationPath?: {
    fromVersion: string;
    toVersion: string;
    migrationRules: MigrationRule[];
  };
  message: string;
}

// ── Dispute Escalation Types ───────────────────────────────────

export interface DisputeEscalationRule {
  fromLevel: 'L1' | 'L2';
  toLevel: 'L0' | 'L1';
  triggerCondition: 'unresolved_after_window' | 'manifest_deprecation' | 'critical_security';
  escalationDelaySeconds: number;
  notificationRequired: boolean;
}

/** Ballot descriptor for governance disputes (uses core.json Ballot object type). */
export interface GovernanceBallot {
  /** Ballot motion text describing the dispute. */
  motion: string;
  /** Quorum required for resolution. */
  quorum: number;
  /** Related object ID (manifest ID or policy ID). */
  relatedObjectId: string;
  /** Hat ID of the dispute initiator. */
  initiatorHatId: string;
  /** Dispute reason. */
  reason: string;
  /** Governance level of the dispute. */
  disputeLevel: 'L2_to_L1' | 'L1_to_L0';
  /** Timestamp when the dispute was created. */
  createdAt: string;
  /** Deadline for resolution before auto-escalation (ISO 8601). */
  escalationDeadline?: string;
}

// ── Publication Types ──────────────────────────────────────────

export interface PublicationResult {
  success: boolean;
  manifestId?: string;
  errors: string[];
  warnings: string[];
}

```
