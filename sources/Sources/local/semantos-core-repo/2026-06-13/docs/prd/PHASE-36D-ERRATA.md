---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36D-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.688466+00:00
---

# Phase 36D Errata — Extension Governance Model

**Date**: April 2026
**Branch**: `phase-36d-extension-governance-model`
**Status**: Complete

---

## Issues Found and Resolved

### 1. TypeHash Format Validation (core.json)
**Issue**: Initial GovernancePolicy and ConsumerBinding entries in core.json used placeholder typeHash values that were not valid 64-char hex SHA256 strings. The Phase 26F backward-compatibility test (T17) validates typeHash format.
**Resolution**: Generated proper SHA256 hashes from the type paths (`governance.policy` → `85d65ce...`, `extension.consumer-binding` → `d5840aa...`).

### 2. ConsumerBinding Dual Nature
**Issue**: `ConsumerBinding` already existed in `packages/extraction/src/stages.ts` as a simple `{ consumerId, credentials, overrides }` struct used by the pipeline.
**Resolution**: Created `GovernedConsumerBinding` in `governance.ts` as the persistent object (with encrypted credentials, version pins, field overrides). The pipeline's `ConsumerBinding` remains the lightweight runtime struct. The pipeline bridges between them via `ExtractionOptions.governedBinding`.

### 3. Module Import Paths in Tests
**Issue**: Test file initially used `../../extraction/src/...` paths but the `__tests__` directory is a sibling of `extraction`, not a grandchild.
**Resolution**: Corrected to `../extraction/src/...` matching existing test patterns.

---

## Design Decisions Confirmed

1. **No separate governance engine**: All disputes use the existing Ballot object type from `core.json`. Phase 18's primitives are reused without modification.

2. **Credential encryption uses Web Crypto API fallback**: `credential-vault.ts` uses AES-256-GCM when Web Crypto is available, with a stub fallback for dev/test. Production deployments must have Web Crypto.

3. **Constraints flow downward only**: `enforceL0Constraints()` validates manifests against platform policy. `enforceL1Constraints()` validates bindings against manifest grammar. No reverse or sideways validation.

4. **Version compatibility is a hard gate**: The pipeline's `extract()` method checks `checkCompatibility()` before processing. Red status blocks extraction entirely.

5. **GovernancePolicy is RELEVANT+Constitution**: Added to `core.json` with `constitution: true`. In the loom, RELEVANT objects with constitution flag require Ballot-based changes.

6. **Emergency deprecation is L0-binding**: `createEmergencyDeprecation()` creates a ballot with `quorum: 1` (L0 vote is binding) and immediately marks the manifest as deprecated.

---

## Testing Coverage

| Test Area | Tests | Status |
|-----------|-------|--------|
| L0 GovernancePolicy | T1–T3 | Pass |
| L1 Author Governance | T4–T6 | Pass |
| ConsumerBinding + L1 Constraints | T7–T9 | Pass |
| Constraint Engine | T10–T12 | Pass |
| Dispute Escalation | T13–T14 | Pass |
| Version Compatibility | T15–T16 | Pass |
| Emergency Deprecation | T17 | Pass |
| Shell Commands | T18a–T18c | Pass |
| **Total** | **20 tests** | **All pass** |

- `bun run check`: Zero TypeScript errors
- `bun run build`: Succeeds
- Phase 26F backward-compatibility: T17/T18 pass (after typeHash fix)
- Pre-existing WASM/CellEngine failures: 49 tests — all unrelated to Phase 36D

---

## Recommendations for Phase 36E

1. **Extension Manager UI** should render GovernancePolicy in a read-only panel with ballot history.
2. **ConsumerBinding configuration UI** should use `credentialFieldNames` for form labels and never display decrypted credentials.
3. **Dispute dashboard** should show active ballots linked to manifests with escalation countdown timers.
4. **Version compatibility widget** should use the green/yellow/red status codes from `checkCompatibility()`.
5. **Marketplace listing** should validate against L0 `marketplaceListingRequirements` before showing extensions.

---

## Files Created/Modified

### New Files (7)
- `packages/protocol-types/src/governance.ts` — All governance type definitions
- `packages/extraction/src/governance/constraint-engine.ts` — L0/L1 constraint enforcement
- `packages/extraction/src/governance/credential-vault.ts` — AES-256-GCM credential encryption
- `packages/extraction/src/governance/dispute-escalator.ts` — Dispute creation and escalation
- `packages/extraction/src/governance/manifest-publisher.ts` — Manifest publication logic
- `packages/extraction/src/governance/version-compat.ts` — Version compatibility matrix
- `packages/shell/src/commands/govern.ts` — Shell govern subcommands

### Modified Files (5)
- `configs/extensions/core.json` — Added GovernancePolicy + ConsumerBinding object types
- `packages/protocol-types/src/index.ts` — Governance type exports
- `packages/protocol-types/src/extension-manifest.ts` — Governance config fields
- `packages/extraction/src/pipeline.ts` — Governance gate integration
- `packages/extraction/src/stages.ts` — Extended ExtractionOptions
- `packages/shell/src/router.ts` — Govern command routing

### Test File (1)
- `packages/__tests__/phase36d-extension-governance.test.ts` — 20 gate tests
