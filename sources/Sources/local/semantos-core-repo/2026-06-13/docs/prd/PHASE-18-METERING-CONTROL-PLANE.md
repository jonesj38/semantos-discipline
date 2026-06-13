---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-18-METERING-CONTROL-PLANE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.709738+00:00
---

# Phase 18 — Metering Control Plane (Channels as Governed Objects)

> Execute this phase after Phase 17 gate passes. Branch: `phase-18-metering-control-plane`

## Metadata

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | March 2026 |
| Status | Pending Phase 17 gate |
| Duration | 3 weeks (4-day buffer) |
| Prerequisites | Phase 17 merged, CashLanes prototype wallet architecture available |
| Master Document | PLEXUS-INTEGRATION-MAP.md |
| Branch | `phase-18-metering-control-plane` |

---

## Context

Phase 17 completed the identity layer with transfer and recovery. This phase integrates metered resource access into the loom. CashLanes is a prototype that implements payment channels (open, fund, transact, settle, close). This phase recognizes that a payment channel is not a special protocol — it is a semantic object with an FSM, governed by the same identity and capability system, audited by the same evidence chains.

The insight: if channels are semantic objects, then the loom becomes a universal metering control plane. Any resource (APIs, content, compute time, bandwidth, physical access) can be metered through the same object/flow/governance primitives. CashLanes provides the Bitcoin settlement rail. The loom provides everything else: identity-governed access, FSM state transitions, capability checks, dispute resolution, and audit trails.

---

## The Insight

CashLanes is a prototype. Its payment channel logic (open, fund, transact, settle, close) is an FSM. That FSM is no different from a job lifecycle (`draft → published → accepted → in_progress → completed`) or a governance proposal (`draft → voting → approved → implemented`). If the channel IS a semantic object, then:

- **Channel identity** is a Plexus-derived cert (the channel has an owner, counterparty, and capability set)
- **Channel state transitions** are FlowRunner steps with guards (minimum funding, time locks, counterparty signature)
- **Channel governance** uses the same Ballot/Dispute primitives (dispute resolution on contested settlements)
- **Channel audit trail** is an evidence chain (every payment is a witnessed patch)
- **Channel policy** is a Constitution-type RELEVANT object (fee schedules, dispute windows, settlement rules)

No separate `MeteringAdapter`. The PlexusAdapter + loom object system IS the metering control plane.

---

## Architecture

```
+------------------------------------------------------------------+
|  WORKBENCH                                                        |
|  PaymentChannel: LINEAR semantic object (one active state)       |
|  ChannelPolicy: RELEVANT semantic object (immutable rules)       |
|  ChannelFSM: flow definition in extension config                  |
|  Disputes: same Ballot/Dispute/Resolution objects                |
+------------------------------------------------------------------+
        |  PlexusAdapter (same interface)    |
        |  - deriveChild() → channel cert    |
        |  - createEdge() → counterparty     |
        |  - presentCapability() → metering  |
        v                                    v
+----------------------------+  +----------------------------+
|  PLEXUS SDK                |  |  CASHLANES PROTOTYPE       |
|  - Channel identity certs  |  |  - 2-of-2 multisig logic   |
|  - Metering domain keys    |  |  - Off-chain tx signing     |
|  - UTXO capability tokens  |  |  - Settlement broadcast     |
+----------------------------+  +----------------------------+
```

CashLanes handles the raw Bitcoin mechanics (multisig, off-chain signing, settlement broadcast). The loom handles everything above that: who can open a channel, what the rules are, how disputes resolve, what the audit trail looks like.

---

## Channel as Semantic Object

### PaymentChannel — LINEAR

```typescript
// PaymentChannel — LINEAR (one active state at a time, one owner)
interface PaymentChannelDef {
  typePath: string;            // "metering.channel"
  linearity: 'LINEAR';         // ownership matters, state is singular
  phases: [
    'prefunding',
    'funding',
    'active',
    'settling',
    'settled',
    'disputed',
    'closed'
  ];
  capabilities: {
    open: [2];                 // Create — initiate channel
    fund: [2, 8];              // Create + Stake — deposit initial balance
    transact: [3];             // Edit/Patch — record transaction
    settle: [9];               // Transfer — initiate settlement
    dispute: [6, 7];           // Govern (Vote + Propose) — raise dispute
    close: [4];                // Delete/Revoke — finalize closing
    admin: [10];               // Admin — force close, parameter change
  };
}
```

### ChannelPolicy — RELEVANT

```typescript
// ChannelPolicy — RELEVANT (immutable once published, always visible)
interface ChannelPolicyDef {
  typePath: string;            // "metering.policy"
  linearity: 'RELEVANT';       // rules don't change mid-channel
  visibility: 'published';     // always visible
  rules: {
    minFundingSatoshis: number;
    maxChannelDurationSeconds: number;
    disputeWindowSeconds: number;
    settlementFeePercent: number;
    meterUnit: string;         // "api_call" | "byte" | "second" | "request" | custom
    pricePerUnit: number;      // satoshis per unit
    autoSettleThreshold: number; // auto-settle when balance hits this
  };
}
```

---

## Channel FSM as Flow Definition

```
CHANNEL LIFECYCLE (FlowRunner flow):
  prefunding
    → funding         [guard: identity has Stake capability (8)]
    → cancelled       [guard: only owner, within cancellation window]
  funding
    → active          [guard: both parties funded, min threshold met]
    → expired         [guard: time > funding_deadline]
  active
    → active          [guard: each transaction is a patch with witness proof]
    → settling        [guard: either party initiates, or auto-settle threshold]
    → disputed        [guard: counterparty raises Dispute object]
  settling
    → settled         [guard: both signatures collected, broadcast to chain]
    → disputed        [guard: within dispute window]
  disputed
    → settling        [guard: Ballot resolves in favor of settlement]
    → closed          [guard: Ballot resolves in favor of force-close]
  settled
    → closed          [guard: settlement tx confirmed on-chain]
```

Every transition is a FlowRunner step. Every guard uses the same `FlowStepGuard` types. Disputes use the same Ballot/Resolution flow from `core.json`. Nothing new is invented — channels compose existing primitives.

---

## Source Files Table

| Alias | File | Relevance |
|-------|------|-----------|
| PlexusAdapter | `packages/loom/src/plexus/types.ts` | Derive channel cert, create counterparty edge, check metering capability |
| PlexusService | `packages/loom/src/plexus/PlexusService.ts` | Coordinate Plexus operations for channels |
| LoomStore | `packages/loom/src/services/LoomStore.ts` | Create PaymentChannel and ChannelPolicy objects |
| FlowRunner | `packages/loom/src/services/FlowRunner.ts` | Execute channel FSM transitions with guards |
| EvidenceChain | `packages/loom/src/types/evidence.ts` | Record transactions as patches |
| core.json | `configs/extensions/core.json` | Define PaymentChannel, ChannelPolicy, FSM, Dispute/Ballot flows |
| CashLanesService | `packages/loom/src/plexus/CashLanesService.ts` | Bridge to CashLanes: multisig, signing, broadcast |

---

## Deliverables

### D18.1: PaymentChannel Object Type

**PaymentChannel is a LINEAR semantic object with commerce phases mapped to channel lifecycle.**

Added to `core.json`:

```json
{
  "typePath": "metering.channel",
  "displayName": "Payment Channel",
  "description": "Metered resource access channel with settlement",
  "linearity": "LINEAR",
  "phases": [
    "prefunding",
    "funding",
    "active",
    "settling",
    "settled",
    "disputed",
    "closed"
  ],
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
}
```

---

### D18.2: ChannelPolicy Object Type

**ChannelPolicy is a RELEVANT semantic object with metering rules schema.**

Added to `core.json`:

```json
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

---

### D18.3: Channel FSM as Flow Definition

**Channel FSM is a FlowRunner flow with full lifecycle and FlowStepGuard at every transition.**

Added to `core.json`:

```json
{
  "flowId": "metering.channel_lifecycle",
  "displayName": "Channel Lifecycle",
  "initialPhase": "prefunding",
  "phases": [
    {
      "phaseId": "prefunding",
      "displayName": "Prefunding",
      "transitions": [
        {
          "targetPhase": "funding",
          "displayName": "Fund Channel",
          "guard": {
            "type": "capability",
            "field": "identity.capabilities",
            "operator": "in",
            "value": [2, 8]
          }
        },
        {
          "targetPhase": "cancelled",
          "displayName": "Cancel",
          "guard": {
            "type": "relationship",
            "field": "object.owner",
            "operator": "eq",
            "value": "currentIdentity"
          }
        }
      ]
    },
    {
      "phaseId": "funding",
      "displayName": "Funding",
      "transitions": [
        {
          "targetPhase": "active",
          "displayName": "Activate",
          "guard": {
            "type": "value",
            "field": "object.fundingSatoshis",
            "operator": "gte",
            "value": "policy.minFundingSatoshis"
          }
        },
        {
          "targetPhase": "expired",
          "displayName": "Expire",
          "guard": {
            "type": "time",
            "field": "object.fundingDeadline",
            "operator": "lt",
            "value": "now()"
          }
        }
      ]
    },
    {
      "phaseId": "active",
      "displayName": "Active",
      "transitions": [
        {
          "targetPhase": "active",
          "displayName": "Transact",
          "guard": {
            "type": "capability",
            "field": "identity.capabilities",
            "operator": "in",
            "value": [3]
          }
        },
        {
          "targetPhase": "settling",
          "displayName": "Settle",
          "guard": {
            "type": "capability",
            "field": "identity.capabilities",
            "operator": "in",
            "value": [9]
          }
        },
        {
          "targetPhase": "disputed",
          "displayName": "Raise Dispute",
          "guard": {
            "type": "relationship",
            "field": "dispute.relatedObjectId",
            "operator": "eq",
            "value": "object.id"
          }
        }
      ]
    },
    {
      "phaseId": "settling",
      "displayName": "Settling",
      "transitions": [
        {
          "targetPhase": "settled",
          "displayName": "Settle",
          "guard": {
            "type": "contextual",
            "field": "settlement.signaturesCollected",
            "operator": "eq",
            "value": true
          }
        },
        {
          "targetPhase": "disputed",
          "displayName": "Dispute Settlement",
          "guard": {
            "type": "time",
            "field": "settlement.initiatedAt + policy.disputeWindowSeconds",
            "operator": "gte",
            "value": "now()"
          }
        }
      ]
    },
    {
      "phaseId": "disputed",
      "displayName": "Disputed",
      "transitions": [
        {
          "targetPhase": "settling",
          "displayName": "Resolve to Settlement",
          "guard": {
            "type": "contextual",
            "field": "ballot.resolution",
            "operator": "eq",
            "value": "settlement_approved"
          }
        },
        {
          "targetPhase": "closed",
          "displayName": "Force Close",
          "guard": {
            "type": "contextual",
            "field": "ballot.resolution",
            "operator": "eq",
            "value": "force_close"
          }
        }
      ]
    },
    {
      "phaseId": "settled",
      "displayName": "Settled",
      "transitions": [
        {
          "targetPhase": "closed",
          "displayName": "Close",
          "guard": {
            "type": "contextual",
            "field": "settlement.confirmedOnChain",
            "operator": "eq",
            "value": true
          }
        }
      ]
    },
    {
      "phaseId": "closed",
      "displayName": "Closed",
      "transitions": []
    }
  ]
}
```

---

### D18.4: Metering Domain Key Derivation

**Channel identity is a Plexus-derived cert via metering domain flag (0x0A).**

In `PlexusAdapter`:
- Add `deriveDomainKey(certId, domainFlag, rotationIndex)` method
- When creating a PaymentChannel, call `adapter.deriveChild(ownerCertId, 'metering.channel', 0x0A)` to derive the channel's cert ID
- Store the derived cert on the channel object's `channelCertId` field

```typescript
// In LoomStore.createObject()
if (object.typePath === 'metering.channel') {
  const channelCert = await plexusService.deriveChild(
    currentIdentity.facetCertId,
    'metering.channel',
    0x0A  // Metering domain flag
  );
  object.channelCertId = channelCert.certId;
}
```

---

### D18.5: Channel Edge

**Channel edge is a MESSAGING type with ECDH shared secret for counterparty communication.**

When a PaymentChannel is created with a `counterpartyCertId`, the adapter creates an edge:

```typescript
const edge = await adapter.createEdge({
  sourceCertId: channelCertId,
  targetCertId: counterpartyCertId,
  edgeType: 'MESSAGING',
  domainFlag: 0x0A,  // Metering domain
  recoveryPolicy: 'BACKUP_ON_CREATE'
});

// Store edge on channel object
object.counterpartyEdgeId = edge.edgeId;
object.sharedSecret = edge.sharedSecret;
```

---

### D18.6: Transaction-as-Patch

**Each metered unit is an evidence chain patch with witness hash `sha256(prevPatch || amount || channelCertId)`.**

Every payment/transaction on the channel is recorded as an evidence chain patch:

```typescript
interface TransactionPatch {
  type: 'channel_transaction';
  from: string;         // payer certId
  to: string;           // payee certId
  amount: number;       // satoshis or units
  meterUnit: string;    // from policy
  timestamp: number;
  previousPatchHash: string;  // for chaining
  witnessHash: string;  // sha256(prevHash || amount || channelCertId)
}

// In FlowRunner when advancing 'active' → 'active' with transact guard:
const transaction = {
  type: 'channel_transaction',
  from: payerCertId,
  to: payeeCertId,
  amount: txAmount,
  meterUnit: channelPolicy.meterUnit,
  timestamp: Date.now(),
  previousPatchHash: channelObject.evidenceChain[channelObject.evidenceChain.length - 1]?.hash
};

const witnessHash = sha256(
  transaction.previousPatchHash +
  JSON.stringify(transaction.amount) +
  channelObject.channelCertId
);

const patch = {
  type: 'channel_transaction',
  content: transaction,
  hash: witnessHash,
  timestamp: Date.now()
};

channelObject.evidenceChain.push(patch);
channelObject.payload.balanceTracking[payeeCertId] += txAmount;
```

---

### D18.7: Dispute Bridge

**Contested settlement triggers Dispute object creation, resolved via existing Ballot flow.**

When a party raises a dispute during the settling phase, the loom:

1. Creates a Dispute object linked to the channel
2. Creates a Ballot with options (approve_settlement | force_close)
3. Uses existing governance flow to resolve

```typescript
// When transitioning active → disputed or settling → disputed:
const dispute = await loomStore.createObject('core.dispute', {
  subject: `Payment Channel Settlement Dispute: ${channelId}`,
  relatedObjectId: channelId,
  initiator: currentIdentity.facetCertId,
  description: `Settlement disputed on channel ${channelId}`
});

const ballot = await loomStore.createObject('core.ballot', {
  proposalId: dispute.id,
  title: `Resolve: ${dispute.subject}`,
  options: ['settle', 'force_close'],
  votingWindow: channelPolicy.disputeWindowSeconds,
  quorum: 50,
  stakeWeighted: true
});

// Dispute resolution is evaluated via the existing Ballot flow
// When Ballot completes, the channel FSM advances based on resolution
if (ballot.resolution === 'settle') {
  await flowRunner.advanceFlow(channel, 'settling');
} else if (ballot.resolution === 'force_close') {
  await flowRunner.advanceFlow(channel, 'closed');
}
```

---

### D18.8: Channel Inspector

**Payment channel status, transaction history, and policy rules surfaced in loom object inspector.**

Extend the object inspector UI to display channel-specific information:

```typescript
interface ChannelInspectorPanel {
  // Status section
  channelStatus: {
    phase: string;
    owner: string;
    counterparty: string;
    certId: string;
  };

  // Funding section
  fundingStatus: {
    targetSatoshis: number;
    currentSatoshis: number;
    percentFunded: number;
    deadline: number;
  };

  // Transaction history section
  transactions: Array<{
    timestamp: number;
    from: string;
    to: string;
    amount: number;
    meterUnit: string;
    witnessHash: string;
  }>;

  // Policy section
  policyRules: {
    minFunding: number;
    maxDuration: number;
    disputeWindow: number;
    settlementFee: number;
    meterUnit: string;
    pricePerUnit: number;
  };

  // Dispute section (if disputed)
  dispute?: {
    disputeId: string;
    ballotId: string;
    votes: Array<{ voter: string; choice: string }>;
    resolution?: string;
  };
}
```

---

### D18.9: CashLanes Bridge Service

**Thin translation layer delegating Bitcoin mechanics (multisig, signing, broadcast) to CashLanes prototype.**

Create `packages/loom/src/plexus/CashLanesService.ts`:

```typescript
export class CashLanesService {
  constructor(private cashlanes: CashLanesClient, private plexusService: PlexusService) {}

  // Prepare settlement for broadcast
  async prepareCashLanesSettlement(channelId: string, channel: PaymentChannel) {
    // CashLanes prepares 2-of-2 multisig inputs/outputs
    const settlementTx = await this.cashlanes.prepareSplitTx({
      channelId,
      ownerAmount: channel.payload.balanceTracking[channel.ownerId],
      counterpartyAmount: channel.payload.balanceTracking[channel.payload.counterpartyCertId],
      feePerByte: channel.policyObjectId.payload.rules.settlementFeePercent
    });

    return settlementTx;
  }

  // Collect signatures from both parties
  async collectCashLanesSignatures(channelId: string, settlementTx: SettlementTx) {
    // Obtain owner's signature
    const ownerSig = await this.plexusService.signWithFacet(
      channelId,  // use channel cert for signing
      settlementTx.unsignedTx
    );

    // Request counterparty signature (via shared secret edge)
    const counterpartySig = await this.cashlanes.requestCounterpartySignature(
      channelId,
      settlementTx.unsignedTx
    );

    return { ownerSig, counterpartySig };
  }

  // Broadcast settlement to chain
  async broadcastCashLanesSettlement(
    channelId: string,
    settlementTx: SettlementTx,
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

  // Await on-chain confirmation
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

When the channel FSM transitions `settling → settled`, the loom:

1. Calls `cashLanesService.prepareCashLanesSettlement(channelId, channel)`
2. Calls `cashLanesService.collectCashLanesSignatures(...)`
3. Calls `cashLanesService.broadcastCashLanesSettlement(...)`
4. Awaits confirmation and records settlement patch on evidence chain

```typescript
const settlement = await cashlaneService.broadcastCashLanesSettlement(channelId, settlementTx, sigs);

// Record settlement patch
const settlementPatch = {
  type: 'channel_settlement',
  txid: settlement.txid,
  broadcastTime: settlement.broadcastTime,
  status: settlement.status
};

channel.evidenceChain.push({
  type: 'channel_settlement',
  content: settlementPatch,
  hash: sha256(JSON.stringify(settlementPatch) + channel.channelCertId),
  timestamp: Date.now()
});

// Await confirmation, then transition to settled → closed
const confirmation = await cashlaneService.awaitCashLanesConfirmation(settlement.txid);
channel.payload.settlementConfirmed = true;
await flowRunner.advanceFlow(channel, 'closed');
```

---

## Gate Tests

| ID | Test |
|----|------|
| T1 | PaymentChannel object creation derives Plexus cert for channel identity via metering domain flag (0x0A) |
| T2 | PaymentChannel is LINEAR — cannot have two active states (verify linearity constraint enforced) |
| T3 | ChannelPolicy is RELEVANT — attempting to patch published policy throws error |
| T4 | Channel FSM flow advances through full lifecycle (prefunding → funding → active → settling → settled → closed) |
| T5 | Each flow transition respects its guard (capability check, time window, threshold check) |
| T6 | Transaction patches form valid hash chain — each references previous hash in witness |
| T7 | Disputed channel creates Dispute + Ballot, resolvable via existing governance flow |
| T8 | Channel works against stub (no CashLanes backend required) — metering logic is loom-native |
| T9 | Metering works for arbitrary meterUnit values (not hardcoded to api_call, byte, second, etc.) |
| T10 | Channel edge is MESSAGING type with ECDH shared secret for counterparty communication |
| T11 | ChannelPolicy rules are enforced by FlowStepGuards (min funding, time windows, thresholds) |
| T12 | Settlement confirmation creates evidence chain patch with txid and on-chain confirmation |

---

## Completion Criteria

- [ ] `PaymentChannel` object type added to `core.json` with LINEAR linearity and full capabilities map
- [ ] `ChannelPolicy` object type added to `core.json` with RELEVANT linearity and metering rules schema
- [ ] Channel FSM flow defined in `core.json` with all phases and transitions with FlowStepGuard
- [ ] `LoomStore.createObject('metering.channel')` derives channel cert via Plexus metering domain (0x0A)
- [ ] `LoomStore` creates channel edge with MESSAGING type and ECDH shared secret
- [ ] Transaction-as-patch implemented — each metered unit recorded with witness hash
- [ ] Dispute bridge implemented — disputed channels create Dispute + Ballot objects
- [ ] Channel inspector UI component displays status, funding, transaction history, policy rules, and disputes
- [ ] `CashLanesService` implemented with settlement preparation, signature collection, broadcast, confirmation
- [ ] Settlement transitions recorded as evidence chain patches with txid and on-chain confirmation
- [ ] FlowRunner guards evaluate correctly for all channel transitions
- [ ] Stub adapter works without CashLanes backend (settlement tx preparation is stubbed)
- [ ] Tests T1–T12 all pass
- [ ] `bun run check` passes (zero TypeScript errors)
- [ ] `bun run build` succeeds
- [ ] Errata sprint complete with `docs/prd/PHASE-18-ERRATA.md`
- [ ] All commits follow `phase-18/D18.N:` naming convention
- [ ] Branch is `phase-18-metering-control-plane`

---

## What NOT to Do

- **Don't build a separate MeteringAdapter**: Channels use the same PlexusAdapter. No new adapter interface. No new adapter modes. Everything goes through the existing PlexusAdapter.
- **Don't hardcode meterUnit values**: The meterUnit is a string in ChannelPolicy. It can be "api_call", "byte", "second", "request", or any custom value. Guard evaluation must be generic.
- **Don't bypass governance for disputes**: Disputes use the same Ballot/Dispute/Resolution objects from core.json. No custom dispute engine.
- **Don't implement Bitcoin mechanics in the loom**: CashLanes handles multisig signing, UTXO management, and transaction broadcast. The loom calls CashLanesService and receives callbacks. No Bitcoin details in loom code.
- **Don't create channel-specific UI patterns**: Use the existing loom object inspector. Extend it, don't create a separate channel UI.
- **Don't allow RELEVANT policy updates**: Once a ChannelPolicy is published, it is immutable. Attempting to patch it throws an error.
- **Don't allow two concurrent channel states**: PaymentChannel is LINEAR. The FSM enforces singular state at all times. No simultaneous prefunding + funding.

---

## Post-Phase 18

After Phase 18, the Plexus integration track is complete. The loom is a universal control plane for identity-governed, evidence-chained, flow-driven semantic objects — including metered resource access channels.

Any resource can be metered through the same primitives:
- **Identity-governed**: Objects have Plexus-derived certs and capability-gated operations
- **Evidence-chained**: Every mutation is a witnessed patch with hash continuity
- **Flow-driven**: State machines are expressed as FlowRunner flows with guards
- **Governed**: Disputes and policy changes use the same Ballot/Constitution primitives
- **Recoverable**: Objects transfer ownership with chain-of-custody proofs, identities recover with attestations, edges restore from backup

CashLanes provides the Bitcoin settlement rail. The loom provides everything else.
