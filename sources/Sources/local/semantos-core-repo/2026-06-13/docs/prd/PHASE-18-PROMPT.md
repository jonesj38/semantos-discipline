---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-18-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.710278+00:00
---

# Phase 18 Execution Prompt — Metering Control Plane

> Paste this prompt into a fresh session to execute Phase 18.

## Context

You are working in the `semantos-core` repo. Phase 17 is complete: objects have provable transfer histories, identities can recover from loss, and edges can be restored from backup.

Your task is Phase 18: turn the loom into a universal metering control plane. Payment channels are not an external protocol the loom bridges to — they ARE semantic objects with their own FSMs, governed by the same identity and capability system, audited by the same evidence chains.

After Phase 18, any resource (APIs, content, compute, bandwidth) can be metered through the same object/flow/governance primitives. CashLanes provides the Bitcoin settlement rail. The loom provides everything else: identity-governed access, FSM state transitions, capability checks, dispute resolution, and audit trails.

### The Goal

**Channel as Object**: Payment channels are LINEAR semantic objects with Plexus-derived identities, evidence chains, and flow-driven state machines.

**Channel Policy**: Fee schedules, dispute windows, and settlement rules are RELEVANT objects (immutable once published).

**Channel FSM**: Open, fund, transact, settle, close — all expressed as FlowRunner steps with guards. Disputes use the same Ballot primitives.

**Settlement**: CashLanes handles Bitcoin multisig and broadcast. The loom records transactions as evidence chain patches and settlement confirmation as final evidence.

**Universal Metering**: The meterUnit in ChannelPolicy is a string — not hardcoded to any specific resource type. Arbitrary meterUnits work through the same flow.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-18-METERING-CONTROL-PLANE.md` — Full spec with architecture diagram, D18.1–D18.9, gate tests T1–T12, completion criteria.

**Read second** (the integration map context):
- `docs/prd/PLEXUS-INTEGRATION-MAP.md` — Full architecture, what owns what, Plexus components, semantic-seed salvage strategy.

**Read third** (the types you extend):
- `configs/extensions/core.json` — Governance types (Dispute, Ballot, Resolution), flow definitions. You add PaymentChannel and ChannelPolicy here.
- `packages/loom/src/services/FlowRunner.ts` — Flow step execution and guard evaluation. You extend this to evaluate payment channel transitions.
- `packages/loom/src/plexus/types.ts` — PlexusAdapter interface. You already have all necessary methods; no new methods.

**Read fourth** (the services you integrate with):
- `packages/loom/src/services/IdentityStore.ts` — Identity state.
- `packages/loom/src/services/LoomStore.ts` — Object creation.
- `packages/loom/src/services/EdgeStore.ts` — Edge creation (channel edge is MESSAGING type).
- `packages/loom/src/types/evidence.ts` — Evidence chain. You add channel transaction and settlement patch types.

**Read fifth** (the UI framework):
- `packages/loom/src/ui/ObjectInspector.tsx` — Object inspector. You extend it to display channel-specific panels.

**Read sixth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-18-metering-control-plane`. Commits as `phase-18/D18.N:`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

Same rules as Phases 14–17. Plus:

### 1. NO SEPARATE METERINGADAPTER

Channels use the same PlexusAdapter. No new adapter interface. No new adapter modes. Everything goes through `adapter.deriveChild()`, `adapter.createEdge()`, `adapter.presentCapability()`. The entire metering system is composed from existing PlexusAdapter methods.

### 2. NO BITCOIN MECHANICS IN THE WORKBENCH

CashLanes handles multisig signing, UTXO management, transaction broadcast, and on-chain confirmation. The loom calls `CashLanesService` and receives callbacks. No Bitcoin script operations, no signing logic, no SPV checks in loom code.

### 3. CHANNEL FSM USES EXISTING FLOWRUNNER

No `ChannelStateMachine` class. No custom state machine. The channel lifecycle is a FlowRunner flow defined in `core.json`. FlowRunner.advanceFlow() executes transitions. No parallel implementations.

### 4. DISPUTES USE EXISTING BALLOT/RESOLUTION

No `ChannelDisputeEngine`. When a dispute is raised, the loom creates a Dispute object and a Ballot object (both already exist in `core.json`). The same Ballot/Resolution flow from governance resolves the dispute. No special logic.

### 5. METERING IS GENERIC

The meterUnit in ChannelPolicy is a string. It can be "api_call", "byte", "second", "request", or any custom value. Guard evaluation and transaction recording must be generic. No hardcoded assumptions about what is being metered.

### 6. CHANNEL IDENTITY IS DERIVED, NOT CREATED

Channel cert comes from `adapter.deriveChild(owner, 'metering.channel', 0x0A)`. It is NOT generated or created. It is a Plexus-derived cert under the metering domain.

### 7. EVERY TRANSACTION IS A PATCH

Every payment/metered unit is an evidence chain patch. Patches have witness hashes: `sha256(prevHash || amount || channelCertId)`. No transactions outside the evidence chain.

### 8. NO SEPARATE CHANNEL UI

Use the existing loom object inspector. Extend it with channel-specific panels (status, funding, transaction history, policy rules, disputes). Do NOT create a separate channel view or dashboard.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify Phase 17 complete

Check that Phase 17 is merged into main:
```bash
git log --oneline main | grep "phase-17"
```

All of these must be present:
- `packages/loom/src/plexus/types.ts` with transfer and recovery methods
- `packages/loom/src/services/IdentityStore.ts` with recovery flow
- `packages/loom/src/services/LoomStore.ts` with transferObject()
- `packages/loom/src/services/EdgeStore.ts` with edge preservation and queryEdges()
- `packages/loom/src/types/evidence.ts` with transfer and recovery_attestation patch types

### 0.3 Verify CashLanes integration available

Check that CashLanes prototype is available (either as npm package or local):
```bash
npm list @cashlanes/client
# OR
ls packages/cashlanes-client/
```

### 0.4 Create Phase 18 branch

```bash
git checkout -b phase-18-metering-control-plane
```

---

## Step 1: PaymentChannel + ChannelPolicy in core.json (D18.1, D18.2)

Modify `configs/extensions/core.json`.

Add PaymentChannel and ChannelPolicy object types:

```json
{
  "typePath": "metering.channel",
  "displayName": "Payment Channel",
  "description": "Metered resource access channel with settlement",
  "linearity": "LINEAR",
  "phases": ["prefunding", "funding", "active", "settling", "settled", "disputed", "closed"],
  "initialPhase": "prefunding",
  "payloadSchema": {
    "counterpartyCertId": { "type": "string" },
    "fundingSatoshis": { "type": "number" },
    "fundingDeadline": { "type": "number" },
    "policyObjectId": { "type": "string" },
    "transactionLog": { "type": "array" },
    "balanceTracking": { "type": "object" }
  },
  "capabilities": {
    "open": [2],
    "fund": [2, 8],
    "transact": [3],
    "settle": [9],
    "dispute": [6, 7],
    "close": [4],
    "admin": [10]
  }
},
{
  "typePath": "metering.policy",
  "displayName": "Channel Policy",
  "description": "Metering rules for resource access",
  "linearity": "RELEVANT",
  "visibility": "published",
  "payloadSchema": {
    "minFundingSatoshis": { "type": "number" },
    "maxChannelDurationSeconds": { "type": "number" },
    "disputeWindowSeconds": { "type": "number" },
    "settlementFeePercent": { "type": "number" },
    "meterUnit": { "type": "string" },
    "pricePerUnit": { "type": "number" },
    "autoSettleThreshold": { "type": "number" }
  }
}
```

Commit: `phase-18/D18.1-D18.2: Add PaymentChannel and ChannelPolicy to core.json`

---

## Step 2: Channel FSM Flow Definition in core.json (D18.3)

Modify `configs/extensions/core.json`.

Add the channel lifecycle flow with FlowStepGuard at every transition. Include all phases and transitions as specified in the PRD section "Channel FSM as Flow Definition".

Commit: `phase-18/D18.3: Add channel FSM flow definition with guards to core.json`

---

## Step 3: LoomStore Integration (D18.1, D18.4, D18.5)

Modify `packages/loom/src/services/LoomStore.ts`.

Add channel creation logic:

```typescript
async createObject(typePath: string, payload: any) {
  // ... existing creation logic ...

  // If creating a payment channel, derive channel cert and edge
  if (typePath === 'metering.channel') {
    // Derive channel cert via metering domain (0x0A)
    const channelCert = await this.plexusService.deriveChild(
      this.currentIdentity.facetCertId,
      'metering.channel',
      0x0A
    );

    object.channelCertId = channelCert.certId;

    // Create MESSAGING edge to counterparty
    const counterpartyEdge = await this.plexusService.createEdge({
      sourceCertId: channelCert.certId,
      targetCertId: payload.counterpartyCertId,
      edgeType: 'MESSAGING',
      domainFlag: 0x0A,
      recoveryPolicy: 'BACKUP_ON_CREATE'
    });

    object.counterpartyEdgeId = counterpartyEdge.edgeId;
    object.sharedSecret = counterpartyEdge.sharedSecret;
  }

  return object;
}
```

Commit: `phase-18/D18.4-D18.5: LoomStore derives channel cert and creates counterparty edge`

---

## Step 4: Transaction-as-Patch in Evidence Chain (D18.6)

Modify `packages/loom/src/types/evidence.ts`.

Add channel transaction and settlement patch types:

```typescript
export interface ChannelTransactionPatch {
  type: 'channel_transaction';
  from: string;
  to: string;
  amount: number;
  meterUnit: string;
  timestamp: number;
}

export interface ChannelSettlementPatch {
  type: 'channel_settlement';
  txid: string;
  broadcastTime: number;
  status: 'broadcast' | 'confirmed';
}

export type EvidencePatchType =
  | 'channel_transaction'
  | 'channel_settlement'
  // ... existing types
```

Modify `packages/loom/src/services/FlowRunner.ts`.

When advancing an 'active' phase with a transact step, record the transaction as a patch:

```typescript
async advanceFlow(object: LoomObject, nextPhaseId: string, stepData?: any) {
  // ... existing phase transition logic ...

  // If channel transaction
  if (object.typePath === 'metering.channel' && nextPhaseId === 'active' && stepData?.transaction) {
    const prevPatch = object.evidenceChain[object.evidenceChain.length - 1];
    const transaction = {
      type: 'channel_transaction',
      from: stepData.transaction.from,
      to: stepData.transaction.to,
      amount: stepData.transaction.amount,
      meterUnit: stepData.transaction.meterUnit,
      timestamp: Date.now()
    };

    const witnessHash = sha256(
      (prevPatch?.hash || '') +
      JSON.stringify(transaction.amount) +
      object.channelCertId
    );

    object.evidenceChain.push({
      type: 'channel_transaction',
      content: transaction,
      hash: witnessHash,
      timestamp: Date.now()
    });

    // Update balance tracking
    object.payload.balanceTracking[stepData.transaction.to] =
      (object.payload.balanceTracking[stepData.transaction.to] || 0) + stepData.transaction.amount;
  }

  return object;
}
```

Commit: `phase-18/D18.6: FlowRunner records transactions as evidence chain patches`

---

## Step 5: Dispute Bridge (D18.7)

Modify `packages/loom/src/services/FlowRunner.ts`.

When transitioning to 'disputed' phase, create Dispute and Ballot objects:

```typescript
async advanceFlow(object: LoomObject, nextPhaseId: string, stepData?: any) {
  // ... existing logic ...

  // If channel disputed
  if (object.typePath === 'metering.channel' && nextPhaseId === 'disputed') {
    const dispute = await loomStore.createObject('core.dispute', {
      subject: `Payment Channel Settlement Dispute: ${object.id}`,
      relatedObjectId: object.id,
      initiator: this.currentIdentity.facetCertId,
      description: `Settlement disputed on channel ${object.id}`
    });

    const policy = await loomStore.getObject(object.payload.policyObjectId);
    const ballot = await loomStore.createObject('core.ballot', {
      proposalId: dispute.id,
      title: `Resolve: ${dispute.subject}`,
      options: ['settle', 'force_close'],
      votingWindow: policy.payload.rules.disputeWindowSeconds,
      quorum: 50,
      stakeWeighted: true
    });

    object.payload.disputeId = dispute.id;
    object.payload.ballotId = ballot.id;
  }

  return object;
}
```

When a Ballot resolves, transition the channel:

```typescript
// In IdentityStore or elsewhere that monitors ballot resolution
onBallotResolved(ballot: LoomObject) {
  const channel = loomStore.getObject(ballot.payload.proposalId);
  if (!channel || channel.typePath !== 'metering.channel') return;

  if (ballot.phase === 'approved') {
    if (ballot.resolution === 'settle') {
      flowRunner.advanceFlow(channel, 'settling');
    } else if (ballot.resolution === 'force_close') {
      flowRunner.advanceFlow(channel, 'closed');
    }
  }
}
```

Commit: `phase-18/D18.7: FlowRunner creates Dispute and Ballot on channel dispute`

---

## Step 6: Channel Inspector UI (D18.8)

Create `packages/loom/src/ui/ChannelInspectorPanel.tsx`.

Extend the object inspector to display channel-specific information:

```typescript
export function ChannelInspectorPanel({ object, policyObject }: {
  object: LoomObject;
  policyObject?: LoomObject;
}) {
  return (
    <div className="channel-inspector">
      {/* Status section */}
      <ChannelStatusSection
        phase={object.phase}
        owner={object.ownerId}
        counterparty={object.payload.counterpartyCertId}
        certId={object.channelCertId}
      />

      {/* Funding section */}
      <ChannelFundingSection
        targetSatoshis={object.payload.fundingSatoshis}
        percentFunded={calculatePercentFunded(object)}
        deadline={object.payload.fundingDeadline}
      />

      {/* Transaction history section */}
      <ChannelTransactionHistorySection
        transactions={extractTransactionPatches(object.evidenceChain)}
        balanceTracking={object.payload.balanceTracking}
      />

      {/* Policy rules section */}
      {policyObject && (
        <ChannelPolicySection
          rules={policyObject.payload.rules}
        />
      )}

      {/* Dispute section (if disputed) */}
      {object.phase === 'disputed' && (
        <ChannelDisputeSection
          disputeId={object.payload.disputeId}
          ballotId={object.payload.ballotId}
        />
      )}
    </div>
  );
}
```

Integrate into ObjectInspector:

```typescript
// In ObjectInspector.tsx
if (object.typePath === 'metering.channel') {
  const policyObject = loomStore.getObject(object.payload.policyObjectId);
  return <ChannelInspectorPanel object={object} policyObject={policyObject} />;
}
```

Commit: `phase-18/D18.8: Add ChannelInspectorPanel to display channel status, funding, transactions, and disputes`

---

## Step 7: CashLanes Bridge Service (D18.9)

Create `packages/loom/src/plexus/CashLanesService.ts`.

Implement settlement flow:

```typescript
import { CashLanesClient } from '@cashlanes/client';
import { PlexusService } from './PlexusService';

export class CashLanesService {
  constructor(
    private cashlanes: CashLanesClient,
    private plexusService: PlexusService
  ) {}

  async prepareCashLanesSettlement(
    channelId: string,
    channel: LoomObject,
    policy: LoomObject
  ) {
    const ownerBalance = channel.payload.balanceTracking[channel.ownerId] || 0;
    const counterpartyBalance = channel.payload.balanceTracking[channel.payload.counterpartyCertId] || 0;
    const fee = Math.floor(
      (ownerBalance + counterpartyBalance) * (policy.payload.rules.settlementFeePercent / 100)
    );

    const settlementTx = await this.cashlanes.prepareSplitTx({
      channelId,
      ownerAmount: ownerBalance - (fee / 2),
      counterpartyAmount: counterpartyBalance - (fee / 2),
      feePerByte: 1
    });

    return settlementTx;
  }

  async collectCashLanesSignatures(
    channelId: string,
    channelCertId: string,
    settlementTx: any
  ) {
    // Owner signs
    const ownerSig = await this.plexusService.signWithFacet(
      channelCertId,
      settlementTx.unsignedTx
    );

    // Request counterparty signature
    const counterpartySig = await this.cashlanes.requestCounterpartySignature(
      channelId,
      settlementTx.unsignedTx
    );

    return { ownerSig, counterpartySig };
  }

  async broadcastCashLanesSettlement(
    channelId: string,
    settlementTx: any,
    signatures: { ownerSig: string; counterpartySig: string }
  ) {
    const signedTx = settlementTx.addSignatures(signatures);
    const txid = await this.cashlanes.broadcast(signedTx);

    return {
      txid,
      broadcastTime: Date.now(),
      status: 'broadcast'
    };
  }

  async awaitCashLanesConfirmation(txid: string, confirmations: number = 6) {
    const confirmation = await this.cashlanes.awaitConfirmation(txid, confirmations);
    return {
      confirmed: true,
      blockHeight: confirmation.blockHeight,
      timestamp: confirmation.timestamp
    };
  }
}
```

In FlowRunner, wire settlement:

```typescript
async advanceFlow(object: LoomObject, nextPhaseId: string, stepData?: any) {
  // ... existing logic ...

  // If channel settling → settled
  if (object.typePath === 'metering.channel' && nextPhaseId === 'settled') {
    const policy = await loomStore.getObject(object.payload.policyObjectId);

    // Prepare settlement
    const settlementTx = await cashlaneService.prepareCashLanesSettlement(
      object.id,
      object,
      policy
    );

    // Collect signatures
    const sigs = await cashlaneService.collectCashLanesSignatures(
      object.id,
      object.channelCertId,
      settlementTx
    );

    // Broadcast
    const settlement = await cashlaneService.broadcastCashLanesSettlement(
      object.id,
      settlementTx,
      sigs
    );

    // Record settlement patch
    const settlementPatch = {
      type: 'channel_settlement',
      txid: settlement.txid,
      broadcastTime: settlement.broadcastTime,
      status: settlement.status
    };

    const witnessHash = sha256(
      (object.evidenceChain[object.evidenceChain.length - 1]?.hash || '') +
      settlement.txid +
      object.channelCertId
    );

    object.evidenceChain.push({
      type: 'channel_settlement',
      content: settlementPatch,
      hash: witnessHash,
      timestamp: Date.now()
    });

    // Await confirmation
    await cashlaneService.awaitCashLanesConfirmation(settlement.txid);
    object.payload.settlementConfirmed = true;
  }

  return object;
}
```

Commit: `phase-18/D18.9: Implement CashLanesService for settlement preparation, signing, broadcast, confirmation`

---

## Step 8: Stub Implementation (No CashLanes Backend Required)

Update `packages/loom/src/plexus/stub.ts`.

Stub the CashLanes methods so channels work without a CashLanes backend:

```typescript
// In StubPlexusAdapter or CashLanesService stub mode
async prepareCashLanesSettlement() {
  return {
    unsignedTx: sha256(`settlement:${Date.now()}`)
  };
}

async collectCashLanesSignatures() {
  return {
    ownerSig: sha256('owner_sig'),
    counterpartySig: sha256('counterparty_sig')
  };
}

async broadcastCashLanesSettlement() {
  return {
    txid: sha256(`txid:${Date.now()}`),
    broadcastTime: Date.now(),
    status: 'broadcast'
  };
}

async awaitCashLanesConfirmation() {
  return {
    confirmed: true,
    blockHeight: 12345,
    timestamp: Date.now()
  };
}
```

Commit: `phase-18/stub: Stub CashLanes methods for dev/test without backend`

---

## Step 9: Gate Tests

Create `packages/__tests__/phase18-gate.test.ts`.

### Channel Object Tests (T1–T4)

```typescript
describe("PaymentChannel object", () => {
  // T1: Channel creation derives Plexus cert via metering domain
  // T2: Channel is LINEAR — cannot have two active states
  // T3: Channel policy is RELEVANT — patching published policy throws
  // T4: Channel FSM advances through full lifecycle
});
```

### Flow and Guard Tests (T5–T7)

```typescript
describe("Channel FSM and guards", () => {
  // T5: Each transition respects its guard
  // T6: Transaction patches form valid hash chain
  // T7: Disputed channel creates Dispute and Ballot
});
```

### Stub and Generic Tests (T8–T12)

```typescript
describe("Channel stub and generics", () => {
  // T8: Channel works without CashLanes backend
  // T9: Metering works for arbitrary meterUnit values
  // T10: Channel edge is MESSAGING type with ECDH shared secret
  // T11: ChannelPolicy rules enforced by guards
  // T12: Settlement confirmation creates evidence patch
});
```

Commit: `phase-18/T1-T12: full gate test suite — channels, FSM, guards, disputes, settlement`

---

## Step 10: Errata Sprint

After all tests pass, run the errata protocol in a fresh session:

1. Adversarial review: Is PaymentChannel really LINEAR? Can two states exist simultaneously?
2. Adversarial review: Is ChannelPolicy really RELEVANT? Can published policies be modified?
3. FSM correctness: Does every transition respect its guard?
4. Transaction recording: Is every metered unit recorded as an evidence patch?
5. Dispute flow: Does disputed channel create Dispute and Ballot correctly?
6. Settlement confirmation: Is the settlement txid recorded in the evidence chain?
7. Stub independence: Does the stub work without CashLanes?
8. Generic metering: Can meterUnit be any string, not hardcoded values?
9. No separate adapter: Does the entire system use only the existing PlexusAdapter?
10. No Bitcoin logic: Are there any signing, SPV, or UTXO operations in loom code?
11. Write errata doc as `docs/prd/PHASE-18-ERRATA.md`

---

## Completion Criteria

- [ ] `PaymentChannel` object type in `core.json` with LINEAR linearity
- [ ] `ChannelPolicy` object type in `core.json` with RELEVANT linearity
- [ ] Channel FSM flow defined in `core.json` with all phases and guarded transitions
- [ ] `LoomStore.createObject()` derives channel cert via metering domain (0x0A)
- [ ] Channel edge created with MESSAGING type and ECDH shared secret
- [ ] Transaction recording implemented — each metered unit is an evidence chain patch
- [ ] Witness hash calculation correct: `sha256(prevHash || amount || channelCertId)`
- [ ] Dispute bridge implemented — disputed channels create Dispute and Ballot objects
- [ ] ChannelInspectorPanel displays status, funding, transaction history, policy rules, disputes
- [ ] `CashLanesService` implements settlement preparation, signature collection, broadcast, confirmation
- [ ] Settlement recorded as evidence chain patch with txid and confirmation status
- [ ] Stub works without CashLanes backend — all settlement methods are stubbed
- [ ] FlowRunner evaluates all guards correctly for channel transitions
- [ ] Tests T1–T12 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-18-ERRATA.md`
- [ ] All commits follow `phase-18/D18.N:` naming convention
- [ ] Branch is `phase-18-metering-control-plane`

---

## Next Phase

After Phase 18, the Plexus integration track is complete. The loom is a universal control plane for identity-governed, evidence-chained, flow-driven semantic objects — including metered resource access channels.

Any resource can be metered through the same primitives. CashLanes provides the Bitcoin settlement rail. The loom provides everything else.
