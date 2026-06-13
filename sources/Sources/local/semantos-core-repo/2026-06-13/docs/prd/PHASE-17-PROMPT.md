---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-17-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.674133+00:00
---

# Phase 17 Execution Prompt — Transfer + Recovery

> Paste this prompt into a fresh session to execute Phase 17.

## Context

You are working in the `semantos-core` repo. Phase 16 is complete: edges and capability tokens are wired into the loom. Every identity operation flows through the PlexusAdapter, and every object creation stamps a Plexus-derived certificate.

Your task is Phase 17: implement chain-of-custody transfers (D17.1) and disaster recovery (D17.2–D17.4). After this phase, every object has a provable transfer history, every identity can recover from loss, and every edge can be restored from backup.

### The Goal

**Transfer**: When a LINEAR object changes owner, the adapter calls `transferNode()` in the Plexus Transfer Domain. The node migrates in the DAG, and the transfer is recorded as an evidence chain patch.

**Recovery**: The full 4-phase Plexus recovery flow (OTP → challenge → export → reconstruct) is exposed in identity settings. Recovery includes continuity attestation proving the recovered key material is linked to the original identity.

**Edge Recovery**: Revoked edges are preserved with timestamps. Edges created with `BACKUP_ON_CREATE` policy can be restored from backup. Edges with `PARENT_MANAGED` policy restore when the parent identity recovers.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-17-PLEXUS-TRANSFER.md` — Full spec with D17.1–D17.4, gate tests T1–T10, completion criteria.

**Read second** (the services you integrate with):
- `packages/loom/src/services/IdentityStore.ts` — Identity state. You wire recovery flows here.
- `packages/loom/src/services/LoomStore.ts` — Object mutation. You wire transfer on ownership changes.
- `packages/loom/src/services/EdgeStore.ts` — Edge lifecycle. You preserve edges on revocation.

**Read third** (the types and adapter):
- `packages/loom/src/plexus/types.ts` — `PlexusAdapter` interface. Add transfer and recovery methods.
- `packages/loom/src/plexus/PlexusService.ts` — Service implementation. Delegate to adapter.
- `packages/loom/src/types/evidence.ts` — Evidence chain. Add transfer and recovery patch types.

**Read fourth** (the extension configs):
- `configs/extensions/core.json` — Base types and flows. You add or extend identity recovery flow.

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-17-plexus-transfer`. Commits as `phase-17/D17.N:`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 14–16. Plus:

### 1. ALL 4 RECOVERY PHASES

Recovery is a complete 4-phase flow: OTP → challenge → export → reconstruct. If any phase is missing, you have failed. If recovery exits early without attestation, you have failed.

### 2. ATTESTATION IS NOT OPTIONAL

Every recovered identity MUST have a `recovery_attestation` patch in its evidence chain. The attestation MUST have a valid signature from the Plexus Recovery Service authority. Without attestation, the recovered identity is not provably continuous with the original.

### 3. TRANSFER IS LINEAR ONLY

RELEVANT objects cannot transfer. If you allow a RELEVANT object to transfer, you have broken the type system. Gate test T3 enforces this.

### 4. EDGES ARE NEVER DELETED

Revocation sets `revoked_at` timestamp. Queries must respect the `includeRevoked` filter. If you delete edges, you have broken the recovery path.

### 5. WITNESS HASHES IN EVERY TRANSFER AND RECOVERY PATCH

Transfer patches include `witnessHash: sha256(prevPatch || transferContent || transferrerCertId)`. Recovery attestation includes the Recovery Service's authority signature. No patches without witness proofs.

### 6. RECOVERY POLICY IS IMMUTABLE

Edge recovery policy is set at creation time (Phase 16). Do not change it during revocation or recovery. If you override recovery policy, you have broken the invariant.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify Phase 16 complete

Check that Phase 16 is merged into main:
```bash
git log --oneline main | grep "phase-16"
```

All of these must be present:
- `packages/loom/src/plexus/types.ts` with edge and capability methods
- `packages/loom/src/plexus/PlexusService.ts` with adapter delegation
- `packages/loom/src/services/EdgeStore.ts` with edge management
- Edge recovery policy enum

### 0.3 Create Phase 17 branch

```bash
git checkout -b phase-17-plexus-transfer
```

---

## Step 1: PlexusAdapter Interface Extensions (D17.1–D17.4)

Modify `packages/loom/src/plexus/types.ts`.

Add transfer and recovery methods to `PlexusAdapter` interface:

```typescript
// Transfer Domain
transferNode(
  sourceCertId: string,
  targetParentCertId: string,
  resourceId: string
): Promise<{ nodeId: string; newDerivationPath: string; transferred_at: number }>;

// Recovery Flow (4 phases)
initiateRecovery(email: string): Promise<{ sessionId: string; challengeCount: number }>;
submitChallengeAnswers(sessionId: string, answers: string[]): Promise<{ verified: boolean; exportPayload?: string }>;
reconstructIdentity(exportPayload: string, derivationSeed: string): Promise<{ certId: string; publicKey: string; derivationPath: string }>;

// Attestation
requestRecoveryAttestation(sessionId: string, recoveredCertId: string): Promise<{ attestationId: string; attestationSignature: string; continuityProof: string }>;

// Edge recovery
restoreEdge(edgeBackupId: string): Promise<{ edgeId: string; sharedSecret: string; restored_at: number }>;

// Query with filters
queryEdges(sourceCertId: string, filter?: { includeRevoked?: boolean; edgeType?: string }): Promise<Array<{ edgeId: string; targetCertId: string; edgeType: string; sharedSecret: string; revoked_at?: number }>>;
```

Commit: `phase-17/D17.1-D17.4: PlexusAdapter interface — transfer, recovery, attestation, edge restore`

---

## Step 2: Recovery Flow in core.json

Modify `configs/extensions/core.json`.

Add or extend the identity recovery flow definition:

```json
{
  "flowId": "identity.recovery",
  "displayName": "Identity Recovery",
  "description": "4-phase recovery: OTP → challenge → export → reconstruct",
  "initialPhase": "recovery_requested",
  "phases": [
    {
      "phaseId": "recovery_requested",
      "displayName": "Recovery Initiated",
      "transitions": [
        {
          "targetPhase": "otp_sent",
          "displayName": "Send OTP",
          "guard": {
            "type": "contextual",
            "field": "recovery_session.otp_issued",
            "operator": "eq",
            "value": true
          }
        }
      ]
    },
    {
      "phaseId": "otp_sent",
      "displayName": "OTP Sent",
      "transitions": [
        {
          "targetPhase": "challenges_presented",
          "displayName": "Present Challenges",
          "guard": {
            "type": "contextual",
            "field": "recovery_session.otp_verified",
            "operator": "eq",
            "value": true
          }
        }
      ]
    },
    {
      "phaseId": "challenges_presented",
      "displayName": "Challenges Ready",
      "transitions": [
        {
          "targetPhase": "export_unlocked",
          "displayName": "Unlock Export",
          "guard": {
            "type": "contextual",
            "field": "recovery_session.challenges_verified",
            "operator": "eq",
            "value": true
          }
        }
      ]
    },
    {
      "phaseId": "export_unlocked",
      "displayName": "Export Ready",
      "transitions": [
        {
          "targetPhase": "recovered",
          "displayName": "Reconstruct Identity",
          "guard": {
            "type": "contextual",
            "field": "recovery_session.attestation_valid",
            "operator": "eq",
            "value": true
          }
        }
      ]
    },
    {
      "phaseId": "recovered",
      "displayName": "Identity Recovered",
      "transitions": []
    }
  ]
}
```

Commit: `phase-17/core.json: Add identity recovery flow with 4-phase lifecycle`

---

## Step 3: PlexusService Implementation (D17.1–D17.4)

Modify `packages/loom/src/plexus/PlexusService.ts`.

Implement transfer and recovery methods:

```typescript
async transferNode(sourceCertId: string, targetParentCertId: string, resourceId: string) {
  const result = await this.adapter.transferNode(sourceCertId, targetParentCertId, resourceId);
  this.notifySubscribers();
  return result;
}

async initiateRecovery(email: string) {
  return await this.adapter.initiateRecovery(email);
}

async submitChallengeAnswers(sessionId: string, answers: string[]) {
  return await this.adapter.submitChallengeAnswers(sessionId, answers);
}

async reconstructIdentity(exportPayload: string, derivationSeed: string) {
  const result = await this.adapter.reconstructIdentity(exportPayload, derivationSeed);
  this.notifySubscribers();
  return result;
}

async requestRecoveryAttestation(sessionId: string, recoveredCertId: string) {
  return await this.adapter.requestRecoveryAttestation(sessionId, recoveredCertId);
}

async restoreEdge(edgeBackupId: string) {
  const result = await this.adapter.restoreEdge(edgeBackupId);
  this.notifySubscribers();
  return result;
}

async queryEdges(sourceCertId: string, filter?: { includeRevoked?: boolean; edgeType?: string }) {
  return await this.adapter.queryEdges(sourceCertId, filter);
}
```

Commit: `phase-17/D17.2-D17.4: PlexusService — transfer, recovery, edge restore implementation`

---

## Step 4: LoomStore Integration (D17.1)

Modify `packages/loom/src/services/LoomStore.ts`.

Add transfer method and wire it to ownership changes:

```typescript
async transferObject(objectId: string, newOwnerId: string) {
  const object = this.getObject(objectId);
  if (!object) throw new Error(`Object not found: ${objectId}`);

  // Verify LINEAR only
  const typeDefinition = this.config.getObjectTypeDefinition(object.typePath);
  if (typeDefinition?.linearity !== 'LINEAR') {
    throw new Error(`Cannot transfer ${typeDefinition?.linearity} object`);
  }

  // Check Transfer capability (9)
  const transferCapability = await this.plexusService.presentCapability(
    this.currentIdentity.facetCertId,
    9
  );
  if (!transferCapability.valid) {
    throw new Error('Transfer capability required');
  }

  // Transfer in Plexus
  const transfer = await this.plexusService.transferNode(
    object.ownerId,
    newOwnerId,
    object.typePath
  );

  // Record transfer patch
  const transferPatch = {
    type: 'transfer',
    fromOwner: object.ownerId,
    toOwner: newOwnerId,
    timestamp: Date.now(),
    transferCertId: this.currentIdentity.facetCertId
  };
  const witnessHash = sha256(
    object.evidenceChain[object.evidenceChain.length - 1]?.hash +
    JSON.stringify(transferPatch) +
    this.currentIdentity.facetCertId
  );

  // Update object
  const updatedObject = {
    ...object,
    ownerId: newOwnerId,
    evidenceChain: [
      ...object.evidenceChain,
      {
        type: 'transfer',
        content: transferPatch,
        hash: witnessHash,
        timestamp: Date.now()
      }
    ]
  };

  this.updateObject(objectId, updatedObject);
  return updatedObject;
}
```

Commit: `phase-17/D17.1: LoomStore.transferObject() — transfer with capability check and evidence patch`

---

## Step 5: IdentityStore Recovery Integration (D17.2–D17.3)

Modify `packages/loom/src/services/IdentityStore.ts`.

Add recovery flow methods:

```typescript
async initiateRecovery(email: string) {
  const result = await this.plexusService.initiateRecovery(email);
  return result; // { sessionId, challengeCount }
}

async submitChallengeAnswers(sessionId: string, answers: string[]) {
  return await this.plexusService.submitChallengeAnswers(sessionId, answers);
  // { verified: boolean; exportPayload?: string }
}

async reconstructIdentity(exportPayload: string, derivationSeed: string) {
  const recovered = await this.plexusService.reconstructIdentity(exportPayload, derivationSeed);

  // Request attestation
  const attestation = await this.plexusService.requestRecoveryAttestation(
    sessionId, // from context
    recovered.certId
  );

  // Store attestation on recovered identity's evidence chain
  const attestationPatch = {
    type: 'recovery_attestation',
    content: {
      attestationId: attestation.attestationId,
      originalCertId: this.rootIdentity.certId,
      recoveredCertId: recovered.certId,
      attestationSignature: attestation.attestationSignature,
      continuityProof: attestation.continuityProof
    },
    hash: sha256(attestation.attestationSignature),
    timestamp: Date.now()
  };

  // Update root identity with new cert and attestation
  this.rootIdentity = {
    ...this.rootIdentity,
    certId: recovered.certId,
    publicKey: recovered.publicKey,
    recoveredAt: Date.now(),
    evidenceChain: [
      ...(this.rootIdentity.evidenceChain || []),
      attestationPatch
    ]
  };

  this.notifySubscribers();
  return this.rootIdentity;
}
```

Commit: `phase-17/D17.2-D17.3: IdentityStore recovery — 4-phase flow with attestation`

---

## Step 6: EdgeStore Integration (D17.4)

Modify `packages/loom/src/services/EdgeStore.ts`.

Change revocation to preserve edge with timestamp:

```typescript
revokeEdge(edgeId: string) {
  const edge = this.edges.get(edgeId);
  if (!edge) throw new Error(`Edge not found: ${edgeId}`);

  // Do NOT delete. Set revoked_at.
  const revokedEdge = {
    ...edge,
    revoked_at: Date.now(),
    isActive: false
  };

  this.edges.set(edgeId, revokedEdge);
  this.notifySubscribers();
}

queryEdges(sourceCertId: string, filter?: { includeRevoked?: boolean; edgeType?: string }) {
  const allEdges = Array.from(this.edges.values()).filter(
    e => e.sourceCertId === sourceCertId
  );

  // Filter by revocation status (default: exclude revoked)
  const includeRevoked = filter?.includeRevoked ?? false;
  const results = allEdges.filter(
    e => includeRevoked || !e.revoked_at
  );

  // Filter by edge type if specified
  if (filter?.edgeType) {
    return results.filter(e => e.edgeType === filter.edgeType);
  }

  return results;
}

async restoreEdge(edgeBackupId: string) {
  // Delegate to adapter for shared secret recovery
  const restored = await this.plexusService.restoreEdge(edgeBackupId);

  // Mark edge as active again
  const edge = this.edges.get(edgeBackupId);
  if (!edge) throw new Error(`Edge backup not found: ${edgeBackupId}`);

  const restoredEdge = {
    ...edge,
    revoked_at: undefined,
    isActive: true,
    sharedSecret: restored.sharedSecret,
    restored_at: Date.now()
  };

  this.edges.set(edgeBackupId, restoredEdge);
  this.notifySubscribers();

  return restoredEdge;
}
```

Commit: `phase-17/D17.4: EdgeStore — preserve edges on revocation, implement queryEdges with filter, restoreEdge`

---

## Step 7: Evidence Chain Types (D17.1–D17.3)

Modify `packages/loom/src/types/evidence.ts`.

Add transfer and recovery patch types:

```typescript
export type EvidencePatchType =
  | 'transfer'
  | 'recovery_attestation'
  // ... existing types

export interface TransferPatch {
  type: 'transfer';
  fromOwner: string;
  toOwner: string;
  timestamp: number;
  transferCertId: string;
}

export interface RecoveryAttestationPatch {
  type: 'recovery_attestation';
  attestationId: string;
  originalCertId: string;
  recoveredCertId: string;
  attestationSignature: string;
  continuityProof: string;
  timestamp: number;
}
```

Commit: `phase-17/evidence.ts: Add transfer and recovery_attestation patch types`

---

## Step 8: StubPlexusAdapter Extensions

Modify `packages/loom/src/plexus/stub.ts`.

Implement transfer and recovery in the stub:

```typescript
// Stub transfer: update in-memory node parent
async transferNode(sourceCertId: string, targetParentCertId: string, resourceId: string) {
  const sourceNode = this.nodes.get(sourceCertId);
  const targetParent = this.nodes.get(targetParentCertId);
  if (!sourceNode || !targetParent) throw new PlexusError('Node not found', 'not_found', false);

  const updated = {
    ...sourceNode,
    parent_cert_id: targetParentCertId,
    transferred_at: Date.now()
  };
  this.nodes.set(sourceCertId, updated);

  return {
    nodeId: sourceCertId,
    newDerivationPath: `m/transfer/${targetParentCertId}`,
    transferred_at: Date.now()
  };
}

// Stub recovery: 4-phase flow
async initiateRecovery(email: string) {
  const sessionId = sha256(`recovery:${email}:${Date.now()}`);
  this.recoverySession = {
    sessionId,
    email,
    challengeCount: 3,
    challenges: ['What is your mother\'s name?', 'First pet name?', 'Birth city?'],
    isVerified: false
  };
  return { sessionId, challengeCount: 3 };
}

async submitChallengeAnswers(sessionId: string, answers: string[]) {
  if (!this.recoverySession || this.recoverySession.sessionId !== sessionId) {
    throw new PlexusError('Invalid session', 'invalid_session', false);
  }

  // Stub: accept any 3 answers (in production, verify against challenge set)
  const verified = answers.length === 3;

  if (verified) {
    const exportPayload = sha256(`export:${sessionId}:${Date.now()}`);
    return { verified: true, exportPayload };
  }
  return { verified: false };
}

async reconstructIdentity(exportPayload: string, derivationSeed: string) {
  const recoveredCertId = sha256(`recovered:${exportPayload}:${derivationSeed}`);
  return {
    certId: recoveredCertId,
    publicKey: sha256(`pubkey:${recoveredCertId}`),
    derivationPath: `m/recovery/${recoveredCertId}`
  };
}

async requestRecoveryAttestation(sessionId: string, recoveredCertId: string) {
  return {
    attestationId: sha256(`attestation:${sessionId}:${recoveredCertId}`),
    attestationSignature: sha256(`sig:${sessionId}:${recoveredCertId}`),
    continuityProof: sha256(`proof:${sessionId}:${recoveredCertId}`)
  };
}

async restoreEdge(edgeBackupId: string) {
  const edge = this.edges.get(edgeBackupId);
  if (!edge) throw new PlexusError('Edge not found', 'not_found', false);

  return {
    edgeId: edgeBackupId,
    sharedSecret: sha256(`restored:${edgeBackupId}:${Date.now()}`),
    restored_at: Date.now()
  };
}

async queryEdges(sourceCertId: string, filter?: { includeRevoked?: boolean; edgeType?: string }) {
  let results = Array.from(this.edges.values()).filter(
    e => e.sourceCertId === sourceCertId
  );

  if (!filter?.includeRevoked) {
    results = results.filter(e => !e.revoked_at);
  }

  if (filter?.edgeType) {
    results = results.filter(e => e.edgeType === filter.edgeType);
  }

  return results;
}
```

Commit: `phase-17/stub: Implement transfer, recovery, edge restore in StubPlexusAdapter`

---

## Step 9: Gate Tests

Create `packages/__tests__/phase17-gate.test.ts`.

### Unit Tests (T1–T4: Transfer)

```typescript
describe("Transfer Domain", () => {
  // T1: Transfer of LINEAR object migrates node position in DAG
  // T2: Transfer records chain-of-custody as evidence chain patch with witness hash
  // T3: Transfer fails for non-LINEAR objects
  // T4: Transfer requires Transfer capability (9)
});
```

### Unit Tests (T5–T8: Recovery)

```typescript
describe("Recovery Flow", () => {
  // T5: Recovery initiation returns sessionId and correct challengeCount
  // T6: Correct challenge answers return verified: true with exportPayload
  // T7: Incorrect challenge answers return verified: false
  // T8: Recovered identity has continuity attestation in evidence chain
});
```

### Unit Tests (T9–T10: Edge Recovery)

```typescript
describe("Edge Recovery", () => {
  // T9: Revoked edges retain revoked_at timestamp and are queryable
  // T10: BACKUP_ON_CREATE edges can be restored after recovery
});
```

Commit: `phase-17/T1-T10: full gate test suite — transfer, recovery, edge recovery`

---

## Step 10: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review of every transfer method — does it validate LINEAR-only?
2. Adversarial review of recovery flow — can it exit early without attestation?
3. Edge preservation — are revoked edges really never deleted?
4. Witness hash correctness — does every transfer and recovery patch include hash?
5. Attestation validity — is the Recovery Service signature verified?
6. Recovery policy immutability — is BACKUP_ON_CREATE policy respected?
7. Write errata doc as `docs/prd/PHASE-17-ERRATA.md`

---

## Completion Criteria

- [ ] `PlexusAdapter` interface has transfer, recovery, attestation, edge restore methods
- [ ] `PlexusService` implements all new methods with state notifications
- [ ] `LoomStore.transferObject()` guards with Transfer capability (9) and LINEAR-only check
- [ ] Transfer patch recorded on evidence chain with witness hash
- [ ] `IdentityStore` implements full 4-phase recovery (OTP → challenge → export → reconstruct)
- [ ] Recovery attestation stored on recovered identity's evidence chain
- [ ] `EdgeStore.revokeEdge()` sets `revoked_at`, never deletes
- [ ] `EdgeStore.queryEdges()` respects `includeRevoked` filter
- [ ] `EdgeStore.restoreEdge()` recovers ECDH shared secret
- [ ] `StubPlexusAdapter` implements all transfer and recovery methods
- [ ] Tests T1–T10 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-17-ERRATA.md`
- [ ] All commits follow `phase-17/D17.N:` naming convention
- [ ] Branch is `phase-17-plexus-transfer`

---

## Next Phase

Phase 18 turns the loom into a universal metering control plane. Payment channels are semantic objects with their own FSMs, governed by the same identity and capability system, audited by the same evidence chains. The transfer and recovery mechanisms in Phase 17 provide the foundation.
