---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-17-PLEXUS-TRANSFER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.720933+00:00
---

# Phase 17 — Transfer + Recovery

> Execute this phase after Phase 16 gate passes. Branch: `phase-17-plexus-transfer`

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | March 2026 |
| Status | Pending Phase 16 gate |
| Duration | 1.5 weeks (2-day buffer) |
| Prerequisites | Phase 16 merged |
| Master Document | PLEXUS-INTEGRATION-MAP.md |
| Branch | `phase-17-plexus-transfer` |

---

## Context

Phase 16 wired edges and capability tokens into the loom. Every identity operation and object creation now flows through the PlexusAdapter. This phase completes the Plexus domain integration with two critical capabilities:

1. **Chain-of-Custody Transfers**: When a LINEAR semantic object changes owner, the adapter calls `transferNode()` which migrates the node's position in the Plexus DAG to the new parent's subtree. The ownership change is recorded as a witnessed patch in the evidence chain.

2. **Disaster Recovery**: The full 4-phase Plexus recovery flow (OTP → challenge → export → reconstruct) is exposed through the loom identity settings UI, allowing users to recover identity access if a device is lost or compromised. Identity recovery includes continuity attestation proving the recovered key material is linked to the original identity.

After Phase 17, every object has a provable chain of custody, every identity has a recovery path, and every edge can be restored from backup.

---

## Source Files Table

| Alias | File | Relevance |
|-------|------|-----------|
| PlexusAdapter | `packages/loom/src/plexus/types.ts` | Interface defining all adapter methods including transfer and recovery |
| PlexusService | `packages/loom/src/plexus/PlexusService.ts` | Service orchestrating adapter calls |
| IdentityStore | `packages/loom/src/services/IdentityStore.ts` | Identity state and facet lifecycle — wires recovery flows |
| LoomStore | `packages/loom/src/services/LoomStore.ts` | Object creation and mutation — wires transfer on ownership changes |
| EvidenceChain | `packages/loom/src/types/evidence.ts` | Patch recording for transfer and recovery attestations |
| EdgeStore | `packages/loom/src/services/EdgeStore.ts` | Edge lifecycle and revocation tracking |

---

## Deliverables

### D17.1: Transfer Flow

**Transfer of LINEAR objects triggers Plexus Transfer Domain path migrations.**

When a semantic object changes owner (e.g., a job is handed off to a new creator), the loom calls `adapter.transferNode(sourceNodeCertId, targetParentCertId, resourceId)`. The adapter:

1. Looks up the source node in the Plexus DAG
2. Verifies the source node is LINEAR (only LINEAR objects transfer; RELEVANT objects are not transferable)
3. Calls `transferNode()` in the Plexus Transfer Domain, which migrates the node from the old parent's subtree to the new parent's subtree
4. Returns the updated node state with the new derivation path

The loom records the transfer as an evidence chain patch on the object:
- **Patch content**: `{ type: 'transfer', fromOwner: <old certId>, toOwner: <new certId>, timestamp, witnessHash }`
- **Witness hash**: `sha256(prevPatchHash || transferContent || transferrerCertId)` — proves the transfer was initiated by a specific identity
- **Guard**: Only facets with Transfer capability (9) on the source identity can initiate the transfer

**Files modified**:
- `LoomStore.ts`: Add `transferObject(objectId, newOwnerId)` method
- `EvidenceChain.ts`: Add transfer patch type
- Gate test T1–T2 verify transfer mechanics

---

### D17.2: Recovery Flow

**Full 4-phase Plexus recovery flow (OTP → challenge → export → reconstruct) accessible from loom identity settings.**

The recovery flow is exposed in the identity settings UI with clear progress indication:

1. **Phase 1 — OTP**: User enters email, receives one-time passcode to verify account ownership
2. **Phase 2 — Challenge**: User answers security questions established during identity registration (stored as challenge set in Plexus Identity Domain)
3. **Phase 3 — Export**: Upon correct challenge answers, Plexus returns an encrypted export payload containing key recovery material
4. **Phase 4 — Reconstruct**: Client-side key reconstruction uses the export payload to derive new signing key material from the original seed

Each phase is a FlowRunner step in the `core.json` identity recovery flow:

```
Identity Recovery Flow:
  recovery_requested
    → otp_sent        [guard: email verified, OTP issued]
    → challenges_presented [guard: OTP valid, challenge set loaded]
    → export_unlocked  [guard: challenge answers verified]
    → recovered        [guard: keys reconstructed client-side, continuity attestation valid]
```

API methods:
- `adapter.initiateRecovery(email)` → returns `{ sessionId: string; challengeCount: number }`
- `adapter.submitChallengeAnswers(sessionId, answers: string[])` → returns `{ verified: boolean; exportPayload?: string }`
- `adapter.reconstructIdentity(exportPayload, derivationSeed)` → returns new `{ certId, publicKey, derivationPath }`

**Files modified**:
- `IdentityStore.ts`: Add recovery flow methods
- `packages/loom/src/ui/SettingsPanel.tsx`: Add recovery UI component with 4-phase progress
- Gate test T5–T7 verify recovery flow completion and answer validation

---

### D17.3: Attestation

**Identity continuity proofs generated via Plexus Recovery Service attestation authority.**

When an identity is recovered, the Plexus Recovery Service issues a signed attestation proving continuity between the old key material and the new key material:

```typescript
interface RecoveryAttestation {
  attestationId: string;         // unique attestation ID
  originalCertId: string;        // the original identity cert
  recoveredCertId: string;       // the new identity cert after recovery
  recoverySessionId: string;     // the recovery session that produced this
  attestationTimestamp: number;  // when attestation was issued
  attestingAuthority: string;    // the Recovery Service authority pubkey
  attestationSignature: string;  // BRC-52 signature proof
  continuityProof: string;       // cryptographic proof linking original → recovered
}
```

The attestation is stored as an evidence chain patch on the recovered identity:
- **Patch content**: The full RecoveryAttestation object
- **Patch type**: `'recovery_attestation'`
- **Witness**: The Recovery Service's authority signature

This patch is immutable and permanent — it proves that the recovered identity is cryptographically linked to the original, protecting against identity substitution attacks.

**Files modified**:
- `IdentityStore.ts`: Store attestation on recovered identity's evidence chain
- `EvidenceChain.ts`: Add `recovery_attestation` patch type
- Gate test T8 verifies attestation is present after recovery

---

### D17.4: Edge Recovery

**Revoked edges preserved with `revoked_at` timestamp; backup recipes retained per recovery policy.**

Edges created during Phase 16 have an associated recovery policy set at creation time:

```typescript
enum EdgeRecoveryPolicy {
  BACKUP_ON_CREATE = 'backup_on_create',   // edge backup stored immediately
  PARENT_MANAGED = 'parent_managed',        // restored via parent's recovery
  NO_RECOVERY = 'no_recovery'              // lost if revoked
}
```

When an edge is revoked (e.g., a connection between two objects is deleted):

1. **Preserve the record**: Instead of deleting the edge, set `revoked_at` timestamp and mark as inactive
2. **Query invariant**: `adapter.queryEdges(sourceCertId, filter: { includeRevoked: true })` returns all edges, including revoked ones with timestamps
3. **Restore from backup**: If the edge has `BACKUP_ON_CREATE` policy, `adapter.restoreEdge(edgeBackupId)` reconstructs the ECDH shared secret and recovers the connection
4. **Parent restoration**: If the edge has `PARENT_MANAGED` policy, restoring the parent node's identity via D17.2 recovery automatically restores edges under that parent

**Files modified**:
- `EdgeStore.ts`: Never delete edges; always set `revoked_at` on revocation
- `PlexusAdapter` (interface): Add `queryEdges(..., filter)` and `restoreEdge()` methods
- `PlexusService.ts`: Implement edge query and restore methods
- Gate test T9–T10 verify revocation timestamps and backup restoration

---

## Gate Tests

| ID | Test |
|----|------|
| T1 | Transfer of LINEAR object migrates node position in Plexus DAG — source and target cert IDs are different after transfer |
| T2 | Transfer records chain-of-custody as evidence chain patch with witness hash — evidence chain on transferred object has `type: 'transfer'` with `witnessHash` |
| T3 | Transfer fails for non-LINEAR objects — attempting to transfer a RELEVANT object throws error |
| T4 | Transfer requires Transfer capability (9) on source identity — calling `transferObject()` without capability fails with `PlexusError` |
| T5 | Recovery initiation returns sessionId and correct challengeCount — `initiateRecovery(email)` returns `{ sessionId, challengeCount: 3 }` |
| T6 | Correct challenge answers return verified: true with exportPayload — `submitChallengeAnswers(sessionId, answers)` with correct answers returns `{ verified: true, exportPayload }` |
| T7 | Incorrect challenge answers return verified: false — `submitChallengeAnswers(sessionId, answers)` with wrong answers returns `{ verified: false }` |
| T8 | Recovered identity has continuity attestation in evidence chain — after recovery, identity object has evidence patch with `type: 'recovery_attestation'` and valid `attestationSignature` |
| T9 | Revoked edges retain revoked_at timestamp and are queryable — `queryEdges(sourceCertId, { includeRevoked: true })` includes edges with `revoked_at` set |
| T10 | BACKUP_ON_CREATE edges can be restored after recovery — calling `restoreEdge(edgeBackupId)` after revoking an edge with `BACKUP_ON_CREATE` policy recovers the ECDH shared secret |

---

## Completion Criteria

- [ ] `LoomStore.transferObject(objectId, newOwnerId)` implemented and delegates to `adapter.transferNode()`
- [ ] Transfer requires Transfer capability (9) and guards checked before calling adapter
- [ ] Transfer patch recorded on evidence chain with `type: 'transfer'` and witness hash
- [ ] LINEAR-only transfer enforcement (RELEVANT objects cannot transfer)
- [ ] `IdentityStore` implements 4-phase recovery flow (OTP → challenge → export → reconstruct)
- [ ] Recovery UI component in SettingsPanel with clear phase progress indication
- [ ] `adapter.initiateRecovery()`, `submitChallengeAnswers()`, `reconstructIdentity()` all implemented in PlexusService
- [ ] Recovery attestation stored on recovered identity's evidence chain
- [ ] EdgeStore never deletes edges; all revocations set `revoked_at` timestamp
- [ ] `adapter.queryEdges(..., { includeRevoked: true })` returns revoked edges with timestamps
- [ ] `adapter.restoreEdge(edgeBackupId)` recovers ECDH shared secret for `BACKUP_ON_CREATE` edges
- [ ] Tests T1–T10 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-17-ERRATA.md`
- [ ] All commits follow `phase-17/D17.N:` naming convention
- [ ] Branch is `phase-17-plexus-transfer`

---

## What NOT to Do

- **Don't implement partial recovery**: All 4 phases must complete or the recovery must fail atomically. No recovery with missing OTP. No attestation without challenge answers.
- **Don't skip attestation**: Every recovered identity MUST have a recovery attestation in the evidence chain. Without it, the recovered identity is not provably continuous with the original.
- **Don't allow RELEVANT object transfers**: Only LINEAR objects can transfer. RELEVANT objects (policies, constitutions, taxonomies) are immutable and pinned to their original owner. If this is attempted, throw `PlexusError` with a clear message.
- **Don't delete revoked edges**: Set `revoked_at` and mark as inactive. Queries must respect `includeRevoked: false` by default (do not return revoked edges unless explicitly requested).
- **Don't hardcode recovery policy**: Edge recovery policy is set at creation time (Phase 16). Do not change or override it during revocation.

---

## Next Phase

Phase 18 turns the loom into a universal metering control plane. Payment channels are not an external thing the loom bridges to — they ARE semantic objects with their own FSMs, governed by the same identity and capability system, audited by the same evidence chains. The transfer and recovery mechanisms in Phase 17 provide the foundation: objects now have provable ownership histories and identity continuity proofs.
