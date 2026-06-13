---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36D-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.691870+00:00
---

# Phase 36D Execution Prompt — Extension Governance Model (Hierarchical Step-Down)

> Paste this prompt into a fresh session to execute Phase 36D.

## Context

You are working in the `semantos-core` repo — the TypeScript application layer and shell for Semantos nodes (npm: `@semantos/core`). The kernel (cell engine, linearity, capability validation) is Zig/WASM in the sibling `semantos` repo; this repo holds the type system, protocol adapters, conversational shell, and loom UI.

Phases 36A (Extension Grammar Schema) and 36B (Semantic Extraction Pipeline) define how extensions connect external APIs to semantic objects. Phase 18 (Metering Control Plane) established that governance primitives — Ballot, Dispute, Resolution, Constitution — apply to any semantic object, not just payment channels. Phase 36D extends this insight: extension grammars are semantic objects, so governance over them uses the same Ballot/Dispute/Resolution system. Three levels of governance:

- **L0 (Platform)**: Semantos governs the Extension Grammar meta-schema, capability requirements, and marketplace rules via a Constitution-type GovernancePolicy object
- **L1 (Author)**: Each extension author governs their grammar's evolution via governance config in ExtensionManifest
- **L2 (Consumer)**: Each consumer configures their binding via a ConsumerBinding object, constrained by L1 and L0

Constraints flow downward; disputes escalate upward. No separate governance engine — reuse Phase 18's primitives.

Your task is Phase 36D: implement the three-level governance model, constraint enforcement, dispute escalation, and version compatibility checking.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below. These are the real implementations you are extending.

**Read first** (the PRD and architecture):
- `docs/prd/PHASE-36D-EXTENSION-GOVERNANCE-MODEL.md` — Phase 36D spec with complete deliverables D36D.1–D36D.7, architecture diagram, gate tests T1–T18, completion criteria
- `docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md` — Context on L0/L1/L2 hierarchy, why hierarchical governance, cross-cutting concerns (evidence chains, capability gating)
- `docs/prd/PHASE-36A-EXTENSION-GRAMMAR-SCHEMA.md` — ExtensionGrammar structure; what constraint engine must validate against

**Read second** (Phase 18 governance primitives — the model we're reusing):
- `docs/prd/PHASE-18-METERING-CONTROL-PLANE.md` — Read the full file: Ballot, Dispute, Resolution, Constitution objects, FSM state transitions, capability checks (sections 70–100+ of the metering doc)
- `packages/protocol-types/src/governance.ts` — Ballot, Dispute, Resolution type definitions; facet-based voting; quorum mechanics

**Read third** (identity system — facets are the access control mechanism):
- `packages/protocol-types/src/identity.ts` — Plexus certs, facet derivation, Glow weight
- `docs/prd/PHASE-8.5-IDENTITY-FACETS.md` — Facet hierarchy, multi-sig, delegation

**Read fourth** (existing extension infrastructure):
- `packages/protocol-types/src/extension-manifest.ts` — Current ExtensionManifest; extend with governanceConfig
- `packages/protocol-types/src/extension-grammar.ts` — ExtensionGrammar, MigrationRule structure
- `packages/protocol-types/src/index.ts` — Barrel exports; ensure new types are exported

**Read fifth** (config and object types — where L0/L1/L2 objects live):
- `configs/extensions/core.json` — Current object types; add GovernancePolicy and ConsumerBinding here
- `packages/loom/src/config/extensionConfig.ts` — How configs are loaded and validated

**Read sixth** (shell and CLI):
- `packages/shell/src/router.ts` — How subcommands are routed
- `packages/shell/src/repl.ts` — REPL structure and help system

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. GOVERNANCE USES PHASE 18 PRIMITIVES ONLY

**No new governance engine.** Ballot, Dispute, Resolution, and Constitution are already defined in Phase 18. Extension governance disputes are Ballot objects linked to ExtensionManifest or GovernancePolicy.

Violations that fail gate tests:
- Building a custom voting mechanism instead of using Ballot
- Storing dispute state outside of Dispute/Resolution objects
- Implementing custom quorum calculation instead of using Ballot's quorum logic

### 2. CREDENTIALS NEVER IN EVIDENCE CHAINS

**Plaintext API credentials are never serialized into patches or evidence chains.** Credentials are encrypted at rest using the consumer node's identity key and stored in a separate vault. The ConsumerBinding contains:
- An `encryptedBlob` (the encrypted credentials)
- An `encryptionKeyId` (reference to the node's encryption key)
- `credentialFieldNames` (which fields are encrypted, for UI labels)

The ConsumerBinding's evidence chain records the *structure* of the binding but never the plaintext credentials.

Violations that fail gate tests:
- Storing plaintext credentials in `binding.payload.credentials`
- Serializing credentials into evidence chain patches
- Using weak encryption or hardcoded keys

### 3. CONSTRAINTS FLOW DOWNWARD ONLY

**Hierarchy is strict: L0 → L1 → L2. Downward only.**

- L0 GovernancePolicy constrains what L1 ExtensionManifest can declare (e.g., required capabilities, reserved taxonomy namespaces)
- L1 ExtensionManifest constrains what L2 ConsumerBinding can configure (e.g., allowed field overrides, version ranges)
- **L2 cannot circumvent L1. L1 cannot circumvent L0.**

If a consumer binding violates L1 constraints, the `enforceL1Constraints()` function must return violations and block extraction.

Violations that fail gate tests:
- ConsumerBinding allowing field removals (only additions)
- ConsumerBinding allowing taxonomy overrides outside the grammar's namespace
- ConsumerBinding allowing version pins outside manifest's supported range
- Binding creation or extraction proceeding despite constraint violations

### 4. DISPUTES USE EXISTING BALLOT SYSTEM

**Disputes are Ballot objects.** An L2→L1 dispute is a Ballot linked to an ExtensionManifest. An L1→L0 dispute is a Ballot linked to a GovernancePolicy.

```typescript
// Don't invent custom dispute state:
// ✗ interface Dispute { level: 'L1' | 'L2'; status: 'open' | 'resolved'; ... }

// Use the Phase 18 Ballot object instead:
// ✓ A Dispute IS a Ballot { relatedObjectId: manifestId, facetId: consumerId, ... }
```

Escalation: if an L2→L1 Ballot doesn't resolve within `disputeWindowSeconds`, it escalates to L0 by creating a new Ballot on the GovernancePolicy with the original dispute details.

Violations that fail gate tests:
- Custom Dispute type instead of Ballot
- Storing dispute state in a separate table
- Not using Ballot's quorum and voting mechanics

### 5. L0 GOVERNANCE CHANGES REQUIRE BALLOTS

**GovernancePolicy is RELEVANT (immutable) with Constitution designation.** Changes require a Ballot with quorum > current policy's `breakingChangeBallotQuorum` (e.g., 66%).

Don't allow GovernancePolicy to be patched directly:
```typescript
// ✗ patch(governancePolicyId, { breakingChangeBallotQuorum: 75 }) → succeeds

// ✓ patch(governancePolicyId, ...) checks Constitution and requires Ballot:
// if (policy.constitution) { require(ballot); }
```

Violations that fail gate tests:
- GovernancePolicy patched without ballot
- Ballot quorum calculation wrong
- Constitution flag ignored

### 6. VERSION COMPATIBILITY IS A HARD GATE

**Every extraction pipeline run must call `checkCompatibility(binding, manifest)`.** If status is red, extraction cannot proceed.

```typescript
// Before extraction pipeline starts:
const compat = checkCompatibility(binding, manifest);
if (compat.status === 'red') {
  throw new ExtractionError(`Binding incompatible with manifest. Message: ${compat.message}`);
}
```

`checkCompatibility()` returns:
- **green**: consumer version is available and compatible
- **yellow**: update available but consumer is stable
- **red (incompatible)**: consumer version no longer available
- **red (deprecated)**: consumer version deprecated; provides sunset date

Violations that fail gate tests:
- Extraction proceeding with red status
- Version compatibility not checked before extraction
- Missing deprecation status in compatibility check

### 7. LINEARITY TRANSITIONS ARE EXPLICIT

**ExtensionManifest transitions from AFFINE (draft) to RELEVANT (published).**

Before AFFINE→RELEVANT:
1. Grammar must pass `validateExtensionGrammar()`
2. Grammar must meet L0 constraints: `enforceL0Constraints(manifest, policy)` must return valid
3. Author facet must have sufficient Glow weight (per marketplace rules)
4. Author must have declared governance config

Once RELEVANT:
- Manifest is immutable (no direct patching)
- Changes create new versions (major.minor.patch)
- Major bumps trigger ballots per `patchAcceptancePolicy`

Violations that fail gate tests:
- Direct patching of RELEVANT manifest
- AFFINE→RELEVANT transition without validation
- Publication succeeding without L0 constraint check

### 8. GIT HYGIENE IS MANDATORY

- Branch: `phase-36d-extension-governance-model`
- Commit convention: `phase-36d/D36D.N:` (e.g., `phase-36d/D36D.1: add GovernancePolicy object type`)
- Never `git add .` — stage files explicitly
- Never amend commits — create new commits if hook failures occur
- Preserve file history with `git mv` for renames

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd /Users/toddprice/projects/semantos-core
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

Stage files explicitly. Discard stale files. Ignore `.claude/worktrees/`.

### 0.3 Verify prerequisites are complete

Phase 36A (Extension Grammar Schema) and Phase 18 (Metering Control Plane) must be complete.

```bash
# These files must exist
ls packages/protocol-types/src/extension-grammar.ts
ls packages/protocol-types/src/extension-manifest.ts
ls packages/protocol-types/src/governance.ts
ls configs/extensions/core.json
```

All files must exist. If any are missing, prerequisites are incomplete — STOP and report.

### 0.4 Create Phase 36D branch

```bash
git checkout -b phase-36d-extension-governance-model
```

---

## Step 1: GovernancePolicy Object Type (D36D.1)

### 1.1 Update core.json

Add `governance.policy` object type to `configs/extensions/core.json`:
- Linearity: RELEVANT
- Constitution: true (immutable, requires ballot for changes)
- Payload schema: metaSchemaVersion, requiredCapabilitiesWhitelist, taxonomyNamespaceReservations, marketplaceListingRequirements, breakingChangeBallotQuorum, emergencyDeprecationPolicy
- Initial object must be created by Semantos core team (facet ID hardcoded or loaded from config)

### 1.2 Update ExtensionManifest type

In `packages/protocol-types/src/extension-manifest.ts`:
- Import GovernancePolicy type or define inline
- Add optional `governanceConfig` field to ExtensionManifest
- Ensure type exports from barrel

### 1.3 Verify

```bash
bun run check 2>&1 | head -20
```

Commit: `phase-36d/D36D.1: add GovernancePolicy object type (L0 governance)`

---

## Step 2: ExtensionManifest Governance Extension (D36D.2)

### 2.1 Extend ExtensionManifest

In `packages/protocol-types/src/extension-manifest.ts`:
- Add `governanceConfig` field: `patchAcceptancePolicy`, `versionBumpRules`, `contributorFacets`, `deprecationTimelineMinDays`
- Add `linearity` field: AFFINE or RELEVANT
- Add `grammar` field: ExtensionGrammar object
- Add optional `deprecationStatus` field

### 2.2 Implement publication logic

Create `packages/extraction/src/governance/manifest-publisher.ts`:
- `publishExtensionManifest(manifest: ExtensionManifest, policy: GovernancePolicy): PublicationResult`
- Validates grammar: `validateExtensionGrammar(manifest.grammar)`
- Enforces L0 constraints: `enforceL0Constraints(manifest, policy)`
- Checks author facet Glow weight
- Transitions manifest from AFFINE→RELEVANT
- Returns success or validation errors

### 2.3 Verify

```bash
bun run check 2>&1 | grep -i "manifest\|governance" | head -20
```

Commit: `phase-36d/D36D.2: extend ExtensionManifest with governance config`

---

## Step 3: ConsumerBinding Object Type (D36D.3)

### 3.1 Update core.json

Add `extension.consumer-binding` object type to `configs/extensions/core.json`:
- Linearity: AFFINE
- Scope: node (each node has its own bindings)
- Payload schema: extensionManifestId, grammarVersionPinned, credentialsEncrypted, fieldOverrides, taxonomyOverrides, autoUpdateGrammar, lastExtractionTimestamp, status

### 3.2 Update ExtensionManifest type

In `packages/protocol-types/src/extension-manifest.ts`, define or import `ConsumerBinding` type.

### 3.3 Implement credential encryption

Create `packages/extraction/src/governance/credential-vault.ts`:
- `encryptCredentials(creds: Record<string, string>, nodeKey: CryptoKey): EncryptedBlob`
- `decryptCredentials(blob: EncryptedBlob, nodeKey: CryptoKey): Record<string, string>`
- Store encrypted blobs in separate vault, not in evidence chains
- Reference by ID in ConsumerBinding

### 3.4 Verify

```bash
bun run check 2>&1 | grep -i "binding\|consumer"
```

Commit: `phase-36d/D36D.3: add ConsumerBinding object type (L2 governance) + credential encryption`

---

## Step 4: Constraint Enforcement Engine (D36D.4)

### 4.1 Create constraint-engine.ts

File: `packages/extraction/src/governance/constraint-engine.ts`

Implement three functions:
- `enforceL0Constraints(manifest: ExtensionManifest, policy: GovernancePolicy): ConstraintResult`
- `enforceL1Constraints(binding: ConsumerBinding, manifest: ExtensionManifest): ConstraintResult`
- Helper functions for specific validations

### 4.2 L0 Constraint Rules

L0 validates that ExtensionManifest meets platform policy:
- Grammar's declared `metaSchemaVersion` matches or is compatible with current meta-schema
- All required capabilities in policy's `requiredCapabilitiesWhitelist` are declared in grammar
- Taxonomy extensions don't conflict with reserved namespaces in policy
- Marketplace listing requirements are met (author Glow weight, etc.)

### 4.3 L1 Constraint Rules

L1 validates that ConsumerBinding respects manifest's grammar:
- `fieldOverrides` cannot remove required fields from any grammar object type
- `fieldOverrides` can only add new fields, not replace existing ones
- `taxonomyOverrides` stay within manifest's declared `taxonomyNamespace`
- `grammarVersionPinned` is a valid semver range within manifest's supported versions
- No circular or conflicting overrides

### 4.4 Integration Points

Add constraint checks to:
- `publishExtensionManifest()` — call `enforceL0Constraints()` before AFFINE→RELEVANT
- ConsumerBinding creation — call `enforceL1Constraints()` before commit
- Extraction pipeline startup — call `enforceL1Constraints()` before fetch stage
- Version update — call `enforceL1Constraints()` when binding version pin changes

### 4.5 Verify

```bash
bun run check
```

Commit: `phase-36d/D36D.4: implement constraint enforcement engine (L0 + L1 checks)`

---

## Step 5: Dispute Escalation Flow (D36D.5)

### 5.1 Create dispute-escalator.ts

File: `packages/extraction/src/governance/dispute-escalator.ts`

Implement:
- `createDisputeL2toL1(binding: ConsumerBinding, manifest: ExtensionManifest, reason: string): Ballot`
- `createDisputeL1toL0(manifest: ExtensionManifest, policy: GovernancePolicy, reason: string): Ballot`
- `escalateDispute(ballot: Ballot, toLevel: 'L0' | 'L2'): Ballot` (creates new ballot at higher level)
- `checkEscalationDue(ballot: Ballot, rule: DisputeEscalationRule): boolean` (auto-escalation logic)

### 5.2 Dispute Ballot Linking

L2→L1 Ballot:
- `ballot.relatedObjectId` = ExtensionManifest ID
- `ballot.facetId` = Consumer facet ID
- `ballot.reason` = dispute reason (e.g., "breaking change breaks workflow")
- Voting is by manifest author + community (per `patchAcceptancePolicy`)

L1→L0 Ballot:
- `ballot.relatedObjectId` = GovernancePolicy ID
- `ballot.facetId` = Extension author facet ID
- `ballot.reason` = dispute reason (e.g., "platform whitelist prevents legitimate use")
- Voting is by Semantos core team only

### 5.3 Emergency Deprecation

L0 can force-deprecate an extension:
- L0 creates a Dispute Ballot on ExtensionManifest with `reason: "emergency-deprecation"`
- Ballot is automatically approved (L0 vote is binding)
- Manifest marked with `deprecationStatus.isDeprecated = true` and `sunsetDate`
- Consumers notified; new installs blocked

### 5.4 Verify

```bash
bun run check
```

Commit: `phase-36d/D36D.5: implement dispute escalation flow (L2→L1→L0)`

---

## Step 6: Version Compatibility Matrix (D36D.6)

### 6.1 Create version-compat.ts

File: `packages/extraction/src/governance/version-compat.ts`

Implement:
- `checkCompatibility(binding: ConsumerBinding, manifest: ExtensionManifest): CompatibilityResult`

Returns:
```typescript
{
  compatible: boolean;
  status: 'green' | 'yellow' | 'red';
  manifestVersion: string;
  consumerVersionPin: string;
  availableVersions: string[];
  migrationPath?: { fromVersion, toVersion, migrationRules };
  message: string;
}
```

### 6.2 Compatibility Checks

- **Version Range**: Is consumer's pinned version within manifest's available versions?
- **Meta-Schema**: Does grammar's declared metaSchemaVersion work with node's current meta-schema?
- **Migration Path**: If old version pinned and new version available, are MigrationRules defined?
- **Deprecation**: Is consumer's pinned version deprecated? Provide sunset date and recommended next version.

### 6.3 Status Codes

- **green**: compatible, latest available
- **yellow**: compatible but update available
- **red (incompatible)**: version not available; extraction blocked
- **red (deprecated)**: version deprecated with sunset date; extraction proceeds with warning

### 6.4 Integration

Add check to extraction pipeline startup:
```typescript
const compat = checkCompatibility(binding, manifest);
if (compat.status === 'red') {
  throw new ExtractionError(`Binding incompatible: ${compat.message}`);
}
```

### 6.5 Verify

```bash
bun run check
```

Commit: `phase-36d/D36D.6: implement version compatibility matrix`

---

## Step 7: Shell Commands (D36D.7)

### 7.1 Create govern.ts subcommand

File: `packages/shell/src/govern.ts`

Implement subcommands:
- `semantos govern policy show` — display L0 GovernancePolicy
- `semantos govern manifest <id> show` — display manifest and governance config
- `semantos govern manifest <id> propose-patch <file>` — propose grammar patch
- `semantos govern manifest <id> deprecate --days N` — start deprecation
- `semantos govern binding <id> show` — display binding config
- `semantos govern binding <id> pin <version>` — pin version
- `semantos govern binding <id> override-field --object-type ... --field-name ... --type ...` — add override
- `semantos govern dispute create --manifest-id ... --reason ...` — create dispute
- `semantos govern dispute escalate <id>` — escalate dispute
- `semantos govern dispute list --manifest-id ...` — list disputes
- `semantos govern binding <id> compat` — show compatibility status
- `semantos govern manifest <id> versions` — show available versions

### 7.2 Update router.ts

In `packages/shell/src/router.ts`:
- Add `'govern'` command route to govern subcommand handler
- Register help text for all govern subcommands

### 7.3 Verify

```bash
semantos govern policy show    # Should work
semantos govern manifest --help # Should show subcommand help
```

Commit: `phase-36d/D36D.7: add 'semantos govern' shell subcommand`

---

## Step 8: Gate Tests (D36D.8)

### 8.1 Create test file

File: `packages/__tests__/phase36d-extension-governance.test.ts`

### 8.2 Implement tests T1–T18

**T1–T3**: L0 Governance
- T1: GovernancePolicy created as RELEVANT, Constitution
- T2: Direct patch blocked (requires ballot)
- T3: Ballot with >66% quorum succeeds

**T4–T6**: L1 Author Governance
- T4: ExtensionManifest created AFFINE with governance config
- T5: Publish blocked if grammar invalid
- T6: Publish succeeds if valid + meets L0

**T7–T9**: ConsumerBinding + L1 Constraints
- T7: ConsumerBinding created, credentials encrypted, separate from evidence
- T8: enforceL1Constraints() blocks invalid bindings
- T9: Field overrides and taxonomy overrides validated

**T10–T12**: Constraint Engine
- T10: enforceL0Constraints() detects missing capabilities
- T11: enforceL0Constraints() detects namespace violations
- T12: enforceL1Constraints() detects field removals and version mismatches

**T13–T14**: Dispute Escalation
- T13: Consumer creates L2→L1 dispute
- T14: L1→L0 dispute auto-escalates after window

**T15–T16**: Version Compatibility
- T15: checkCompatibility() returns green/yellow/red correctly
- T16: Red status blocks extraction

**T17**: Emergency Deprecation
- T17: L0 force-deprecation works

**T18**: Shell Commands
- T18: All `semantos govern` commands work

### 8.3 Run tests

```bash
bun test packages/__tests__/phase36d-extension-governance.test.ts
```

All 18 tests must pass.

Commit: `phase-36d/D36D.8: add Phase 36D gate tests (T1–T18)`

---

## Step 9: Final Verification

### 9.1 Type check and build

```bash
bun run check
bun run build
```

Both must succeed.

### 9.2 Full test suite

```bash
bun test
```

All tests must pass, including T1–T18 and all existing gate tests.

### 9.3 Codebase scan

```bash
# Verify no credential leakage
grep -rn "plaintext\|password\|secret" packages/extraction/src/governance/ --include="*.ts" | grep -v "// plaintext never"

# Verify constraint checks in pipeline
grep -rn "enforceL0Constraints\|enforceL1Constraints\|checkCompatibility" packages/extraction/ --include="*.ts" | grep -v test
```

### 9.4 Shell command check

```bash
semantos govern policy show
semantos govern manifest --help
semantos govern binding --help
semantos govern dispute --help
```

All must return meaningful output.

Commit: `phase-36d/D36D.9: final verification complete`

---

## Step 10: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. **Adversarial review**: Read every file you wrote. Check for missed constraints, unhandled edge cases, missing error messages.
2. **Credential audit**: Grep for any plaintext credentials in evidence chains or patches.
3. **Constraint audit**: Verify `enforceL0Constraints()` and `enforceL1Constraints()` are called at every integration point (manifest publish, binding create, extraction startup, version update).
4. **Dispute audit**: Verify disputes use Ballot objects, not custom state; verify escalation window logic is correct.
5. **Version compat audit**: Verify `checkCompatibility()` returns red for incompatible versions; verify extraction blocks on red.
6. **Shell command audit**: Test each govern command with realistic inputs; check error messages.
7. **Documentation audit**: Ensure JSDoc comments are complete; update README.md with Phase 36D entry.
8. **Final grep**: Scan for "TODO", "FIXME", "XXX" or other incomplete markers.

Write errata summary as `docs/prd/PHASE-36D-ERRATA.md` with:
- Issues found and resolved
- Design decisions confirmed
- Testing coverage notes
- Recommendations for Phase 36E

---

## Completion Criteria

- [ ] GovernancePolicy object type in `configs/extensions/core.json`, RELEVANT + Constitution
- [ ] ExtensionManifest extended with `governanceConfig` fields (patchAcceptancePolicy, versionBumpRules, contributorFacets, deprecationTimelineMinDays)
- [ ] ConsumerBinding object type in `configs/extensions/core.json`, AFFINE, node-scoped
- [ ] Credential encryption implemented; plaintext never in evidence chain
- [ ] `constraint-engine.ts` with `enforceL0Constraints()` and `enforceL1Constraints()` functions
- [ ] Constraint checks integrated: manifest publication, binding creation, extraction startup, version update
- [ ] `dispute-escalator.ts` with L2→L1→L0 escalation using Ballot objects
- [ ] Emergency deprecation flow (L0 force-deprecation)
- [ ] `version-compat.ts` with `checkCompatibility()` returning green/yellow/red
- [ ] Version compatibility check gates extraction (red status blocks pipeline)
- [ ] `semantos govern` subcommand with 8+ subcommands (policy, manifest, binding, dispute, compat, versions)
- [ ] Tests T1–T18 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] All existing gate tests still pass
- [ ] All commits follow `phase-36d/D36D.N:` naming convention
- [ ] Branch is `phase-36d-extension-governance-model`
- [ ] Errata sprint complete with `docs/prd/PHASE-36D-ERRATA.md`

---

## Next Phase

Phase 36E builds the Extension Manager UI (loom panel): browse marketplace, install/update/remove extensions, view governance state, configure bindings, vote on disputes, monitor version compatibility.
