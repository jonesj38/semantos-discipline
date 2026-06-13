---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.690657+00:00
---

# Phase 36D — Extension Governance Model (Hierarchical Step-Down)

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 3 weeks (with 4-day buffer)
**Prerequisites**: Phase 36A complete (Extension Grammar Schema). Phase 18 operational (Ballot, Dispute, Resolution, Constitution governance primitives). Phase 8.5 complete (identity facets, Plexus certs). Phase 30F.2 (CAS storage).
**Master Document**: `PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md`
**Branch**: `phase-36d-extension-governance-model`

---

## Context

Semantos extensions live in a marketplace where Semantos governs the meta-schema and platform safety, third-party developers govern their own extension grammars, and consumers configure local bindings. Governance must flow downward (L0 constrains L1 constrains L2) while disputes flow upward (L2→L1→L0). The critical insight: extension grammars are themselves semantic objects with linearity, provenance, patches, and evidence chains. Governance over extensions uses the same Ballot/Dispute/Resolution system from core.json — no separate governance engine needed.

### Hierarchical Step-Down Model

**Level 0 (Kernel/Platform)**: Semantos governs the Extension Grammar meta-schema, platform safety policies, marketplace rules, and capability requirements. A Constitution-type RELEVANT object (GovernancePolicy) defines meta-schema version contracts, required capabilities whitelists, taxonomy namespace reservations, and breaking-change ballot quorum thresholds. Changes require formal ballot with quorum > 66%.

**Level 1 (Extension Author)**: Each extension author governs their extension's grammar evolution — field mappings, object type definitions, taxonomy coordinates, versioning strategy. They control patch acceptance policy (author-only, contributor ballot, or open ballot), version bump rules, contributor facet lists, and deprecation timelines. An ExtensionManifest (AFFINE in draft, RELEVANT when published) carries governance config. Author governance is constrained by L0 policy.

**Level 2 (Consumer Binding)**: Each consumer who installs an extension creates a ConsumerBinding (AFFINE, scoped to their node) where they configure API credentials, field overrides, custom taxonomy mappings, and version pinning. Bindings are constrained by L1 grammar — they cannot remove required fields, cannot override taxonomy beyond the grammar's namespace, and must use a supported grammar version range.

Constraints flow downward only. Disputes flow upward via escalation.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│ L0: PLATFORM GOVERNANCE                               │
│ GovernancePolicy (RELEVANT, Constitution)              │
│ - Meta-schema version requirements                    │
│ - Required capabilities whitelist                     │
│ - Taxonomy namespace reservation rules                │
│ - Marketplace listing requirements                    │
│ - Breaking change ballot quorum (>66%)                │
│ - Emergency deprecation process                       │
│ Governed by: Semantos core team (multi-sig facet)    │
├──────────────────────────────────────────────────────┤
│ L1: EXTENSION AUTHOR GOVERNANCE                       │
│ ExtensionManifest (AFFINE → RELEVANT)                 │
│ - Grammar JSON (versioned, patched)                   │
│ - Author governance config:                           │
│   - Patch acceptance policy                          │
│   - Version bump rules                               │
│   - Contributor facet list                           │
│   - Deprecation timeline                             │
│ Constrained by: L0 GovernancePolicy                  │
│ Governed by: Extension author facet(s)               │
├──────────────────────────────────────────────────────┤
│ L2: CONSUMER BINDING GOVERNANCE                       │
│ ConsumerBinding (AFFINE, node-scoped)                │
│ - API credentials (encrypted)                         │
│ - Field overrides (add local fields)                 │
│ - Taxonomy mapping overrides                         │
│ - Version pin (semver range)                         │
│ - Auto-update preference                            │
│ Constrained by: L1 ExtensionManifest                 │
│ Governed by: Consumer node identity                  │
└──────────────────────────────────────────────────────┘
```

---

## Deliverables

### D36D.1 — GovernancePolicy Object Type (L0)

**File**: Update `configs/extensions/core.json`

Add a new object type `governance.policy` with linearity RELEVANT and Constitution-type designation. This object is immutable once created; changes require ballot.

```typescript
interface GovernancePolicy {
  typePath: "governance.policy";
  linearity: "RELEVANT";
  constitution: true;
  
  payload: {
    /** Minimum meta-schema version for new grammars */
    metaSchemaVersion: string;           // e.g., "1.0.0"
    
    /** Capabilities required or recommended for all extensions */
    requiredCapabilitiesWhitelist: string[];  // e.g., ["network.outbound", "storage.write"]
    
    /** Taxonomy namespaces reserved by platform */
    taxonomyNamespaceReservations: {
      namespace: string;                 // e.g., "what.platform"
      reason: string;                    // why reserved
    }[];
    
    /** Requirements for marketplace listing */
    marketplaceListingRequirements: {
      minAuthorGlowWeight: number;
      minObjectCount: number;
      requiresAudit: boolean;
      auditFrequencyDays: number;
    };
    
    /** Quorum threshold for breaking-change ballots */
    breakingChangeBallotQuorum: number;  // percentage, e.g., 66
    
    /** Emergency deprecation policy */
    emergencyDeprecationPolicy: {
      requiresVote: boolean;
      minDaysNotice: number;             // minimum deprecation notice period
      escalationThreshold: string;       // e.g., "critical-security-vulnerability"
    };
    
    /** When this policy was established */
    effectiveDate: string;               // ISO 8601
    
    /** Governed by facet */
    governedByFacetId: string;           // Semantos core team multi-sig
  };
}
```

**Capability Gating**: Only Semantos core team facet (or delegated admin facet from L0 policy) can create or patch GovernancePolicy objects.

**Ballot Requirement**: Changes to an existing GovernancePolicy require a Ballot with quorum > the current breakingChangeBallotQuorum threshold.

**Version History**: All patches are preserved in evidence chain as immutable records.

### D36D.2 — ExtensionManifest Governance Extension

**File**: Update `packages/protocol-types/src/extension-manifest.ts`

Extend the existing ExtensionManifest type to include governance configuration fields:

```typescript
interface ExtensionManifest {
  // ... existing fields (id, version, displayName, etc.) ...
  
  /** Governance configuration — controls how this extension evolves */
  governanceConfig?: {
    /** Who can propose patches to the grammar */
    patchAcceptancePolicy: 'author_only' | 'contributor_ballot' | 'open_ballot';
    
    /** Who can bump each semver component */
    versionBumpRules: {
      major: 'author_only' | 'contributor_ballot';   // major bumps always require vote if policy is ballot-based
      minor: 'author_only' | 'contributor_ballot';   // minor can be author-only
      patch: 'author_only';                           // patches are author-only
    };
    
    /** Facet IDs allowed to propose patches (for ballot-based policies) */
    contributorFacets: string[];
    
    /** Minimum days notice before deprecation takes effect */
    deprecationTimelineMinDays: number;
    
    /** Current deprecation status */
    deprecationStatus?: {
      isDeprecated: boolean;
      deprecatedDate?: string;           // ISO 8601
      sunsetDate?: string;               // when removal happens
      replacementExtensionId?: string;   // if migrating to new extension
      migrationNotes?: string;
    };
  };
  
  /** Grammar linearity — AFFINE (draft) → RELEVANT (published) */
  linearity: 'AFFINE' | 'RELEVANT';
  
  /** Grammar content (the actual JSON schema) */
  grammar: ExtensionGrammar;
}
```

**Linearity Transitions**: An ExtensionManifest begins as AFFINE (author is developing, can patch freely). Publication to marketplace transitions it to RELEVANT (immutable, changes create new versions). Downgrade back to AFFINE requires author action.

**Publication Requirements**: Before transitioning AFFINE→RELEVANT:
1. `validateExtensionGrammar()` must pass (grammar is well-formed)
2. Grammar must meet all L0 `GovernancePolicy` requirements (meta-schema version, required capabilities, namespace constraints)
3. Author facet must have valid identity (Plexus cert with sufficient Glow weight per marketplace rules)
4. Author governance config must be declared

**Major Version Governance**: If `patchAcceptancePolicy` is 'contributor_ballot' or 'open_ballot', a major version bump triggers an automatic Ballot on the ExtensionManifest object. Minor and patch bumps can be published directly by the author.

### D36D.3 — ConsumerBinding Object Type (L2)

**File**: Add to `configs/extensions/core.json`

New object type `extension.consumer-binding` with linearity AFFINE, node-scoped (each node has its own bindings for each extension it installs).

```typescript
interface ConsumerBinding {
  typePath: "extension.consumer-binding";
  linearity: "AFFINE";
  scope: "node";  // node-scoped, not transferable
  
  payload: {
    /** ID of the ExtensionManifest this binding is for */
    extensionManifestId: string;
    
    /** Pinned grammar version range (semver) */
    grammarVersionPinned: string;        // e.g., "^1.2.0" or "1.2.3"
    
    /** API credentials (encrypted, never in evidence chain plaintext) */
    credentialsEncrypted: {
      encryptedBlob: string;             // base64-encoded encrypted ciphertext
      encryptionKeyId: string;           // reference to node's encryption key
      credentialFieldNames: string[];    // which fields are encrypted (for UI labels)
    };
    
    /** Local field additions (consumer adds to grammar) */
    fieldOverrides?: {
      objectType: string;                // e.g., "property.maintenance-request"
      localFields: {
        fieldName: string;
        sourceType: string;              // 'string' | 'number' | 'boolean' | etc.
        description?: string;
        required: boolean;
      }[];
    }[];
    
    /** Local taxonomy mapping overrides */
    taxonomyOverrides?: {
      objectType: string;
      taxonomy: {
        what?: string;
        how?: string;
        why?: string;
        where?: string;
      };
    }[];
    
    /** Whether to auto-update grammar when new versions are published */
    autoUpdateGrammar: boolean;
    
    /** Last time this binding was used to extract data */
    lastExtractionTimestamp?: string;   // ISO 8601
    
    /** Binding status */
    status: 'active' | 'paused' | 'deprecated';
  };
}
```

**Credential Storage**: API credentials are encrypted at rest using the consumer's node identity key. The encrypted blob is stored in the ConsumerBinding, but the plaintext credentials are NEVER serialized into patches or evidence chains. A separate credential store (secured in the node's vault) holds the actual credentials; the binding references them by ID only.

**Constraint Enforcement**: At binding creation and every extraction:
1. `fieldOverrides` are validated — cannot remove required fields from grammar, can only add new fields
2. `taxonomyOverrides` must stay within the grammar's declared `taxonomyNamespace`
3. `grammarVersionPinned` must be within manifest's supported version range
4. All constraints from L1 ExtensionManifest are checked via constraint engine

### D36D.4 — Constraint Enforcement Engine

**File**: `packages/extraction/src/governance/constraint-engine.ts`

Three functions for hierarchical constraint checking:

```typescript
interface ConstraintViolation {
  level: 'L0' | 'L1';  // which level's constraint was violated
  rule: string;        // e.g., "required-capability-missing"
  message: string;
  details?: unknown;
}

interface ConstraintResult {
  valid: boolean;
  violations: ConstraintViolation[];
}

/**
 * Enforce L0 constraints on an ExtensionManifest.
 * Checked at: manifest creation, publication (AFFINE→RELEVANT), breaking-change ballot.
 */
export function enforceL0Constraints(
  manifest: ExtensionManifest,
  policy: GovernancePolicy
): ConstraintResult;

/**
 * Enforce L1 constraints on a ConsumerBinding.
 * Checked at: binding creation, version update, every extraction pipeline run.
 */
export function enforceL1Constraints(
  binding: ConsumerBinding,
  manifest: ExtensionManifest
): ConstraintResult;

/**
 * Check field override validity.
 * Called by enforceL1Constraints for each fieldOverride.
 */
function validateFieldOverride(
  override: ConsumerBinding['payload']['fieldOverrides'][0],
  manifest: ExtensionManifest
): ConstraintViolation[];

/**
 * Check taxonomy override validity.
 * Called by enforceL1Constraints for each taxonomyOverride.
 */
function validateTaxonomyOverride(
  override: ConsumerBinding['payload']['taxonomyOverrides'][0],
  manifest: ExtensionManifest,
  policy: GovernancePolicy
): ConstraintViolation[];
```

**Enforcement Points**:
- **Manifest publication**: `enforceL0Constraints()` before AFFINE→RELEVANT transition
- **Binding creation**: `enforceL1Constraints()` before ConsumerBinding is committed
- **Grammar version update**: `enforceL1Constraints()` when binding's version pin changes
- **Extraction pipeline startup**: `enforceL1Constraints()` before extraction begins
- **Ballot creation**: `enforceL0Constraints()` when author proposes major version bump

Returns detailed `ConstraintViolation[]` so UI can explain why binding cannot be created or why extraction is blocked.

### D36D.5 — Dispute Escalation Flow

**File**: `packages/extraction/src/governance/dispute-escalator.ts`

Disputes use existing Ballot/Dispute/Resolution objects from core.json:

**L2 → L1 Dispute** (consumer disputes author decision):
1. Consumer creates a Dispute object linked to an ExtensionManifest
2. Reason examples: "grammar version bump breaks my workflow", "required field removal makes extension unusable", "author rejected my patch without justification"
3. Dispute is voted on using existing Ballot mechanics
4. If author + voters reach consensus, dispute is resolved; otherwise escalates to L0 after `disputeWindowSeconds` (default 7 days)

**L1 → L0 Dispute** (author disputes platform policy):
1. Author creates a Dispute linked to the GovernancePolicy object
2. Reason example: "platform's required-capabilities whitelist prevents legitimate use case"
3. Semantos core team votes using L0 ballot mechanism
4. Decision is binding (cannot be appealed further)

**Auto-Escalation**:
```typescript
interface DisputeEscalationRule {
  fromLevel: 'L1' | 'L2';
  toLevel: 'L2' | 'L0';
  triggerCondition: 'unresolved_after_window' | 'manifest_deprecation' | 'critical_security';
  escalationDelaySeconds: number;        // e.g., 604800 for 7 days
  notificationRequired: boolean;
}
```

If a dispute remains unresolved after `disputeWindowSeconds`, it automatically escalates:
- L2→L1 disputes that don't resolve escalate to L0 (Semantos platform)
- An author can manually escalate an L1→L0 dispute anytime

**Emergency Deprecation** (L0 only):
Semantos core team can force-deprecate an extension if it poses platform risk:
1. L0 creates a Dispute on the ExtensionManifest with `reason: "emergency-deprecation"`
2. Dispute is automatically resolved in L0's favor
3. Manifest is marked with `deprecationStatus.isDeprecated = true` and `sunsetDate`
4. Existing consumers receive notification; new installs are blocked
5. Evidence chain preserves the full deprecation record with facet provenance

### D36D.6 — Version Compatibility Matrix

**File**: `packages/extraction/src/governance/version-compat.ts`

```typescript
interface CompatibilityResult {
  compatible: boolean;
  status: 'green' | 'yellow' | 'red';  // green=compatible, yellow=update-available, red=incompatible
  manifestVersion: string;              // latest available version
  consumerVersionPin: string;           // what consumer is pinned to
  availableVersions: string[];
  migrationPath?: {
    fromVersion: string;
    toVersion: string;
    migrationRules: MigrationRule[];
  };
  message: string;                       // human-readable status
}

/**
 * Check if a ConsumerBinding is compatible with its ExtensionManifest.
 * Called before extraction pipeline starts.
 */
export function checkCompatibility(
  binding: ConsumerBinding,
  manifest: ExtensionManifest
): CompatibilityResult;
```

**Compatibility Checks**:
1. **Version Range**: Is binding's `grammarVersionPinned` within manifest's available versions?
2. **Meta-Schema**: Does manifest's grammar declare a `metaSchemaVersion` compatible with the node's current meta-schema?
3. **Migration Path**: If consumer is pinned to old version and new version is available, are `MigrationRule`s defined to guide upgrade?
4. **Deprecation Status**: Is the pinned version deprecated? If so, provide sunset date and recommended next version.

**Status Codes**:
- **green**: consumer version is compatible, latest available
- **yellow**: update available but consumer's binding is stable; consumer can manually update
- **red (incompatible)**: consumer version is no longer available or unsupported; extraction cannot proceed until binding is updated
- **red (deprecated)**: consumer version is deprecated; extraction proceeds but warns of upcoming sunset date

### D36D.7 — Shell Commands: `semantos govern`

**File**: Update `packages/shell/src/` (add `govern.ts` subcommand)

```bash
# Display current L0 GovernancePolicy
semantos govern policy show

# Display extension's governance configuration
semantos govern manifest <id> show
semantos govern manifest <id> show --json    # JSON output

# Propose a grammar patch (creates ballot if needed per author's policy)
semantos govern manifest <id> propose-patch <grammar-file>
semantos govern manifest <id> propose-patch <grammar-file> --reason "reason text"

# Start deprecation process (L1 or L0)
semantos govern manifest <id> deprecate --days 90 --message "migration path"

# Display consumer binding configuration
semantos govern binding <id> show

# Pin binding to a specific version (respects manifest constraints)
semantos govern binding <id> pin <version>

# Add local field override to binding
semantos govern binding <id> override-field --object-type "property.maintenance-request" \
  --field-name "localNotes" --type "string"

# Create a dispute (L2→L1 or L1→L0)
semantos govern dispute create --manifest-id <id> --reason "reason text"
semantos govern dispute create --policy-id <id> --reason "reason text"

# Escalate dispute to next level
semantos govern dispute escalate <dispute-id>

# List all disputes for a manifest or policy
semantos govern dispute list --manifest-id <id>
semantos govern dispute list --policy-id <id>

# View compatibility status of a binding
semantos govern binding <id> compat

# View available versions for a manifest
semantos govern manifest <id> versions
```

---

## Source Files / References

| Alias | Path | What to read |
|-------|------|--------------|
| `TYPES:GOVERNANCE` | `packages/protocol-types/src/governance.ts` | Ballot, Dispute, Resolution, Constitution types from Phase 18 |
| `TYPES:MANIFEST` | `packages/protocol-types/src/extension-manifest.ts` | ExtensionManifest — updated with governance config |
| `TYPES:GRAMMAR` | `packages/protocol-types/src/extension-grammar.ts` | ExtensionGrammar — MigrationRule, version structure |
| `TYPES:IDENTITY` | `packages/protocol-types/src/identity.ts` | Plexus certs, facets, Glow weight |
| `CFG:CORE` | `configs/extensions/core.json` | Ballot, Dispute, Resolution object types; update with GovernancePolicy and ConsumerBinding |
| `METERING` | `packages/protocol-types/src/metering.ts` | PaymentChannel governance model — reference for constraint hierarchy |
| `SHELL:GOVERN` | `packages/shell/src/govern.ts` | New shell subcommand file |
| `MASTER:36` | `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` | L0/L1/L2 hierarchy diagram, cross-cutting concerns |

---

## Gate Tests

**File**: `packages/__tests__/phase36d-extension-governance.test.ts`

### L0 Governance (T1–T3)
- **T1**: `GovernancePolicy` created as RELEVANT, Constitution type
- **T2**: Attempt to patch existing `GovernancePolicy` without ballot fails
- **T3**: Ballot with >66% quorum successfully updates `GovernancePolicy`

### L1 Author Governance (T4–T6)
- **T4**: `ExtensionManifest` created as AFFINE, governance config recorded
- **T5**: Publish (AFFINE→RELEVANT) blocked if grammar fails `validateExtensionGrammar()`
- **T6**: Publish succeeds if grammar passes validation + meets L0 constraints

### ConsumerBinding + L1 Constraints (T7–T9)
- **T7**: `ConsumerBinding` created, credentials encrypted, stored separately from evidence chain
- **T8**: `enforceL1Constraints()` blocks binding creation if binding violates grammar constraints
- **T9**: Binding validates field overrides and taxonomy overrides against grammar

### Constraint Engine (T10–T12)
- **T10**: `enforceL0Constraints()` detects missing required capabilities
- **T11**: `enforceL0Constraints()` detects taxonomy namespace violations
- **T12**: `enforceL1Constraints()` detects field removals and version incompatibilities

### Dispute Escalation (T13–T14)
- **T13**: Consumer creates L2→L1 dispute; dispute is linked to manifest
- **T14**: L1→L0 dispute auto-escalates after `disputeWindowSeconds` if unresolved

### Version Compatibility (T15–T16)
- **T15**: `checkCompatibility()` returns green for compatible version, yellow for update-available
- **T16**: `checkCompatibility()` returns red for incompatible or deprecated versions; blocks extraction

### Emergency Deprecation (T17)
- **T17**: L0 force-deprecation marks manifest as deprecated, prevents new installs, notifies consumers

### Shell Commands (T18)
- **T18**: All `semantos govern` commands execute successfully; output is correctly formatted

---

## Completion Criteria

- [ ] `GovernancePolicy` object type added to `configs/extensions/core.json`, RELEVANT + Constitution
- [ ] `ExtensionManifest` extended with `governanceConfig` fields
- [ ] `ConsumerBinding` object type added to `configs/extensions/core.json`, AFFINE, node-scoped
- [ ] Credential encryption/storage implemented (plaintext never in evidence chain)
- [ ] `constraint-engine.ts` with `enforceL0Constraints()` and `enforceL1Constraints()` functions
- [ ] Constraint checks integrated into manifest publication, binding creation, extraction startup
- [ ] Dispute escalation flow implemented using existing Ballot/Dispute/Resolution
- [ ] `version-compat.ts` with `checkCompatibility()` returning green/yellow/red status
- [ ] `semantos govern` shell subcommand fully operational (8+ subcommands)
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36d/D36D.N:` naming convention
- [ ] Branch is `phase-36d-extension-governance-model`

---

## What NOT to Do

- **Don't build a separate governance engine.** Use existing Ballot, Dispute, Resolution, Constitution objects from Phase 18. Governance is just semantic objects with ballots.
- **Don't store credentials in evidence chains.** Credentials are encrypted separately, referenced by ID in the ConsumerBinding. Evidence chains preserve the reference but never the plaintext.
- **Don't allow L2 to override L1 constraints.** The hierarchy is strict: L0 constrains L1, L1 constrains L2. Downward only. No sideways, no L2 circumventing L1.
- **Don't skip version compatibility checks.** Every extraction run must validate that binding's pinned version is available and compatible. `checkCompatibility()` is a hard gate.
- **Don't make L0 changes easy.** Platform governance changes (GovernancePolicy updates) require a high-quorum ballot. This is intentional — stability.
- **Don't allow direct patching of RELEVANT manifests.** Major version bumps create new manifests. Field changes create new versions. Old versions are immutable (evidence chain).
- **Don't implement custom dispute logic.** Disputes are Ballot objects. Use existing voting, escalation, and resolution mechanics from core.json.

---

## Next Phase

Phase 36E builds the Extension Manager UI (loom panel) that renders the governance state: which extensions are installed, what permissions they have, which bindings are active, how to configure them, and how to vote on disputes.
