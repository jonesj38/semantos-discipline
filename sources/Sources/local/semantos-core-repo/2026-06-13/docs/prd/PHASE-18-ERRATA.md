---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-18-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.718461+00:00
---

# Phase 18 — Metering Control Plane — Errata

> Adversarial review completed after all T1–T12 gate tests pass.

## Findings

### E1: PaymentChannel is LINEAR — correct (LOW)

**Check**: Can two active states exist simultaneously?
**Finding**: PaymentChannel has `linearity: "LINEAR"` in core.json. The `consumeObject()` method in LoomStore enforces single-use: attempting to consume a LINEAR object twice throws `ALREADY_CONSUMED`. The FSM enforces singular state via FlowRunner's `transitionPhase()` which validates the current phase before allowing transitions. No concurrent state issue.
**Severity**: Info — working as designed.

### E2: ChannelPolicy is RELEVANT — correct (LOW)

**Check**: Can published policies be modified?
**Finding**: ChannelPolicy has `linearity: "RELEVANT"`. RELEVANT objects in the loom cannot have their linearity transitioned back. There is no `visibility` config on ChannelPolicy (unlike Dispute which has `publishTransition`), meaning it starts as draft and stays draft — or if a visibility config is added later, publishing transitions to RELEVANT which is immutable. The absence of visibility config means policies are created as draft RELEVANT objects and their payload fields are accessible but not formally published. This is adequate for the current phase.
**Severity**: Low — consider adding explicit visibility config in a future iteration.

### E3: FSM guard correctness — verified (INFO)

**Check**: Does every transition respect its guard?
**Finding**: All 9 phases and their transitions have guards. FlowRunner's `evaluateGuard()` handles 6 operator types (eq, gte, gt, lt, lte, includes_all, in). Tests T6 verify guard evaluation functionally. The `transitionPhase()` method returns `{ ok: false, reason }` when guards fail.
**Severity**: Info — working as designed.

### E4: Transaction recording — verified (INFO)

**Check**: Is every metered unit recorded as an evidence patch?
**Finding**: `recordChannelTransaction()` creates `channel_transaction` patches with witness hash `sha256(prevPatchHash + amount + channelCertId)`. The witness hash chains each transaction to the previous patch, creating a tamper-evident sequence. Balance tracking is updated per-transaction.
**Severity**: Info — working as designed.

### E5: Dispute flow — verified (INFO)

**Check**: Does disputed channel create Dispute and Ballot correctly?
**Finding**: `advanceChannelPhase()` calls `createDisputeForChannel()` when `targetPhase === 'disputed'`. This creates Dispute (category: governance.dispute) and Ballot (category: governance.ballot) objects. Both IDs are stored on the channel's payload (disputeId, ballotId).
**Severity**: Info — working as designed.

### E6: Settlement confirmation — verified (INFO)

**Check**: Is the settlement txid recorded in the evidence chain?
**Finding**: `recordSettlement()` creates a `channel_settlement` patch with `txid`, `broadcastTime`, and `status` in the delta. After `awaitCashLanesConfirmation()`, `settlementConfirmed` is set to true on the payload.
**Severity**: Info — working as designed.

### E7: Stub independence — verified (INFO)

**Check**: Does the stub work without CashLanes?
**Finding**: CashLanesService is fully stubbed using Web Crypto API SHA-256 for deterministic results. No external dependencies. All settlement methods return valid stub data. Tests T7 verify functional correctness.
**Severity**: Info — working as designed.

### E8: Generic metering — verified (INFO)

**Check**: Can meterUnit be any string?
**Finding**: Both PaymentChannel and ChannelPolicy have `meterUnit` as a `string` field (not enum). No hardcoded meterUnit values appear in lifecycle guards. The `recordChannelTransaction()` method passes `meterUnit` through without validation against a fixed list.
**Severity**: Info — working as designed.

### E9: No separate adapter — verified (INFO)

**Check**: Does the entire system use only the existing PlexusAdapter?
**Finding**: LoomStore imports `getPlexusService()` and calls `deriveChild()` and `createEdge()` — both existing PlexusAdapter methods. No new adapter interface or methods were added. CashLanesService is a separate concern (Bitcoin settlement) that doesn't extend PlexusAdapter.
**Severity**: Info — working as designed.

### E10: No Bitcoin logic in loom — verified (INFO)

**Check**: Are there any signing, SPV, or UTXO operations in loom code?
**Finding**: CashLanesService contains no Bitcoin script operations, no signing logic, no SPV checks. It delegates all Bitcoin mechanics to the stub (which returns deterministic hashes). The test T12 verifies absence of OP_CHECKMULTISIG, scriptPubKey, UTXO, and PrivateKey strings.
**Severity**: Info — working as designed.

### E11: channelLifecycle as top-level key (LOW)

**Check**: channelLifecycle is a top-level key in core.json, not nested in flows array.
**Finding**: The channel lifecycle flow definition is structurally different from conversation flows (it has phases with transitions and guards, not linear steps). It was added as `channelLifecycle` at the top level rather than in the `flows` array. This is intentional — conversation flows and lifecycle FSMs serve different purposes. The `validateVerticalConfig()` function in verticalConfig.ts does not reject unknown top-level keys.
**Severity**: Low — the approach is sound but a future refactor could unify flow types under a common schema.

### E12: PlexusService graceful degradation (LOW)

**Check**: What happens if PlexusService is not initialized when creating a channel?
**Finding**: `createPaymentChannel()` wraps `getPlexusService()` in a try/catch. If PlexusService is not initialized, channel creation succeeds but without `channelCertId` and `counterpartyEdgeId`. This is correct for test/dev scenarios where Plexus may not be available.
**Severity**: Low — working as designed for current phase.

---

## Summary

| ID | Finding | Severity |
|----|---------|----------|
| E1 | PaymentChannel LINEAR enforcement correct | Info |
| E2 | ChannelPolicy RELEVANT, no explicit visibility config | Low |
| E3 | All FSM guards evaluated correctly | Info |
| E4 | Transaction patches form valid witness hash chain | Info |
| E5 | Dispute bridge creates Dispute + Ballot correctly | Info |
| E6 | Settlement txid recorded as evidence patch | Info |
| E7 | Stub works without CashLanes backend | Info |
| E8 | meterUnit is generic string, not hardcoded | Info |
| E9 | No separate MeteringAdapter, uses PlexusAdapter | Info |
| E10 | No Bitcoin logic in loom code | Info |
| E11 | channelLifecycle is top-level key, not in flows array | Low |
| E12 | Graceful degradation when PlexusService unavailable | Low |

**All findings are Low or Info severity. No blockers found.**
