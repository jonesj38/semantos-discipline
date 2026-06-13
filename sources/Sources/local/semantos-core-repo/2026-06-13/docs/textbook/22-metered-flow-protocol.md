---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/22-metered-flow-protocol.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.651121+00:00
---

# Metered Flow Protocol

Part VI of this textbook covers Time, Recovery, and Metering — the substrate capabilities that become available during boot-sequence steps 12 through 14. Chapter 19 introduced the stack of hash chains that gives the substrate verifiable time. Chapter 21 walked through the four-phase recovery flow. This chapter completes Part VI by specifying MFP (Metered Flow Protocol): the 8-state finite-state machine that gates paid resource flows and settles them on-chain.

By the end of this chapter, boot-sequence step 14 — "Metered services open MFP cashlanes" — is unlocked.

---

## Overview

MFP is the substrate component that answers one operational question: how does a metered service know, with on-chain finality, that its counterparty has paid for what it consumed?

The answer is a payment channel. Two parties lock funds in a 2-of-2 multisig UTXO. As consumption proceeds, they exchange incrementally updated spending transactions — each signed by both parties, each assigning more of the locked balance to the service provider. When either party decides to close, the most recent transaction is broadcast. Miners accept it; the channel settles. No third party arbitrates. No central ledger intermediates. The chain is the judge.

MFP is Substrate component U10 in the architecture overview (Protocol Spec §2.1). Its 8-state channel FSM is model-checked in TLA+ (`proofs/tla/MeteringFSM.tla`), establishing that the state machine admits no invalid transitions under arbitrary concurrent conditions. The distributed invariant is:

> **Metering FSM**: The 8-state MFP FSM admits no invalid transitions.

That property is the load-bearing guarantee behind every statement in this chapter.

---

## Why payment channels for metering

The alternative approaches to metering all share a common failure mode: they require a trusted third party to arbitrate consumption. A central billing service records usage; a token contract tracks balances; a database tallies calls. Each approach introduces a party whose honesty is assumed rather than verified, and a failure point whose availability is required.

MFP replaces that assumption with a cryptographic invariant. The 2-of-2 multisig funding output means neither party can unilaterally redirect the locked funds. The `nSequence`-based state-update mechanism means that only the most recently agreed state can settle — a party cannot win by broadcasting a stale transaction because miners prefer the transaction with the highest `nSequence`. The tick proof format means that each metering event carries an HMAC under a channel-specific shared secret, binding the proof to the channel and to the cumulative balance at the time of measurement.

The substrate introduces one additional gate: participation in an MFP channel requires a `cap.metered_access` capability token. That token is a BRC-108 UTXO bound to the participant's BRC-52 certificate. Spending the token revokes participation rights permanently — capability tokens are LINEAR semantic resources (K1). The gate ensures that any party opening a channel has been positively credentialed within the governance domain that authorises the service.

Capability token verification at channel open is not optional. The Verifier Sidecar (§9.5 of the Protocol Spec) enforces the check at the adapter boundary before the FSM transitions from NEGOTIATING to FUNDED.

---

## The capability gate

Before the FSM can be entered, two protocol-level prerequisites must be satisfied.

### cap.metered_access

Each participant MUST hold an unspent `cap.metered_access` capability token. The token MUST be:

- Formatted per BRC-108 (Identity-Linked Token Protocol).
- Bound to the participant's BRC-52 certificate subject (33-byte compressed public key).
- Verified via SPV: a BUMP (BRC-74) merkle proof demonstrates the minting transaction is in a block; the spent/unspent status requires a UTXO liveness check (watchman pattern, liveness protocol, or direct UTXO query — SPV alone does not prove a token is unspent).
- Within any time-lock constraint encoded in the locking script.

The capability token is not consumed by opening the channel. It is the credential that authorises participation. The channel itself is the resource being metered. This distinction matters: a single `cap.metered_access` token can gate the opening of multiple channels over its lifetime, subject to the constraints encoded in the locking script at mint time.

### The BCA funding key

Each participant derives a BCA (Blockchain Channel Address) from their `cert_id`. The BCA is used as the channel-funding key for the 2-of-2 multisig output. BCA derivation is deterministic and cert-specific (Protocol Spec §4.3). The funding transaction commits both parties' BCAs to the multisig locking script; neither party can substitute a different key at settlement.

---

## The 8-state FSM

MFP channels progress through eight named states. The FSM is deterministic: given a current state and a trigger, exactly one target state is reachable. Invalid transitions — not represented in the table below — are rejected by the state machine and leave the channel state unchanged (the failure-atomicity property K4 applies at the protocol layer as well as the cell engine layer).

Each transition MUST be atomic and idempotent. Idempotency matters because network partitions can cause duplicate delivery of control messages; the FSM MUST produce the same next state regardless of how many times the triggering event is delivered.

### State definitions

| State              | Meaning                                                                                  |
|--------------------|------------------------------------------------------------------------------------------|
| NEGOTIATING        | Both parties have expressed intent to open a channel; funding transaction not yet signed |
| FUNDED             | Both parties have signed the funding transaction; it has not yet confirmed on-chain       |
| ACTIVE             | Funding transaction confirmed; channel is accepting metering ticks                       |
| PAUSED             | Either party has requested a temporary halt to metering; no ticks are accepted           |
| CLOSING_REQUESTED  | Either party has initiated the close sequence; the counterparty has not yet acknowledged |
| CLOSING_CONFIRMED  | Both parties have agreed on the final state; settlement transaction is ready to broadcast|
| SETTLED            | Settlement transaction confirmed on-chain; channel is permanently closed                 |
| DISPUTED           | A stale `nSequence` was detected; the channel is under active dispute resolution         |

SETTLED and DISPUTED are both terminal for normal channel operation. A channel that reaches SETTLED is closed with on-chain finality. A channel that reaches DISPUTED is resolved by broadcasting the highest-`nSequence` transaction; after resolution it collapses to an effective SETTLED state on-chain, even though the FSM records it as DISPUTED for audit purposes.

### Transition table

| From               | To                 | Trigger                                      | Notes                                                                   |
|--------------------|--------------------|----------------------------------------------|-------------------------------------------------------------------------|
| NEGOTIATING        | FUNDED             | Both parties sign the funding transaction     | The 2-of-2 multisig output is created; funds are locked                 |
| FUNDED             | ACTIVE             | Funding transaction confirmed on-chain        | Both parties receive SPV confirmation via BUMP proof                    |
| ACTIVE             | PAUSED             | Either party requests pause                   | A signed pause message; no tick proofs accepted in PAUSED               |
| PAUSED             | ACTIVE             | Both parties agree to resume                  | Mutual acknowledgement required; unilateral resume is not permitted      |
| ACTIVE             | CLOSING_REQUESTED  | Either party initiates close                  | Close initiator sets the final `nSequence` and proposes a settlement tx  |
| PAUSED             | CLOSING_REQUESTED  | Either party initiates close                  | Closing from PAUSED is permitted; the channel need not return to ACTIVE  |
| CLOSING_REQUESTED  | CLOSING_CONFIRMED  | Counterparty acknowledges close               | Counterparty countersigns the settlement transaction                     |
| CLOSING_CONFIRMED  | SETTLED            | Settlement transaction confirmed on-chain     | Final `nSequence` state settles; balance split is on-chain permanent     |
| (any non-terminal) | DISPUTED           | Fraud detected — stale `nSequence` broadcast  | Either party may trigger; the higher-`nSequence` tx is broadcast immediately |

The DISPUTED transition can originate from any non-terminal state. Its trigger is detection of a broadcast transaction carrying a lower `nSequence` than the most recent agreed state — evidence that the counterparty is attempting to roll back metering history.

```
[FIGURE — needs real graphic for layout pass]

State diagram (ASCII approximation):

  NEGOTIATING ──(both sign funding)──> FUNDED
                                          │
                                   (confirmed on-chain)
                                          │
                                          ▼
                          PAUSED <── ACTIVE ──> CLOSING_REQUESTED
                            │          │                │
                    (both agree)   (stale nSeq)  (counterparty ack)
                            │          │                │
                            └──> ACTIVE ▼                ▼
                                    DISPUTED      CLOSING_CONFIRMED
                                                         │
                                              (settlement confirmed)
                                                         │
                                                         ▼
                                                      SETTLED

  Any non-terminal state ──(stale nSequence detected)──> DISPUTED
```

---

## Tick proofs

Each metering event in an ACTIVE channel produces a tick proof — a compact, HMAC-authenticated record of resource consumption at a specific point in the channel's lifetime.

### Tick proof format

```
{
  tick:               uint32,
  hmac:               bytes(32),
  timestamp:          uint64,
  cumulativeSatoshis: uint64
}
```

The fields carry the following semantics:

- `tick` is a strictly monotonic counter starting at 1 for the first event in a channel. It is the MeteringTick — the per-channel discrete time advance. MeteringTick is distinct from WorldTick (the per-region 20 Hz counter used by World Host). The unqualified word "tick" is ambiguous; within the context of MFP the canonical form is MeteringTick.
- `hmac` is `HMAC-SHA-256(key = channel_shared_secret, message = tick || cumulativeSatoshis || timestamp)`. The channel shared secret is established during the NEGOTIATING phase via ECDH between the two parties' BCA-derived keys. It is never transmitted in any message.
- `timestamp` is milliseconds since epoch, carried as a uint64.
- `cumulativeSatoshis` is the running total of satoshis owed by the consumer to the provider as of this tick. The settlement transaction is constructed to pay exactly this amount to the provider; the remainder returns to the consumer.

### Dual signing

Tick proofs MUST be dual-signed — countersigned by both parties — before they can be used in a settlement transaction. The requirement prevents either party from unilaterally fabricating a metering record. Because the HMAC key is the channel shared secret (known only to the two parties), any forged tick would require knowledge of that secret; the dual-signing requirement adds a second layer by requiring the counterparty to explicitly endorse each record.

Verification of an HMAC MUST use constant-time comparison to prevent timing attacks (Protocol Spec §13.3).

### Tick proof as MeteringTick

The tick counter is the MFP channel's local hash-chain step. Each tick increments `nSequence` on the spending input of the settlement transaction. The `nSequence` field is a uint32, permitting approximately 4.3 billion state updates per channel input — sufficient for any operationally realistic metering period.

The relationship between tick proofs and `nSequence` is direct: `nSequence` at settlement equals the `tick` value of the most recent dual-signed tick proof. This linkage is what makes the fraud-detection mechanism work — a broadcast transaction with `nSequence` lower than the most recent tick is provably stale.

---

## nSequence settlement mechanism

Settlement uses Bitcoin's original `nSequence`-based payment-channel design. The mechanism is worth walking through in full because it is the foundation of the dispute-resolution guarantee.

### The funding output

When the channel transitions from NEGOTIATING to FUNDED, both parties co-sign a funding transaction that creates a 2-of-2 multisig output. The output is locked to both parties' BCA-derived public keys. Neither party can spend this output without the other's signature.

The amount locked in the funding output is the channel's maximum liability: the consumer commits enough satoshis to cover the maximum anticipated consumption. If the consumer exhausts the channel before the service period ends, the parties must either close and reopen, or negotiate an additional funding transaction.

### The settlement transaction

The settlement transaction spends the 2-of-2 multisig funding output. Its structure is fixed at the protocol level:

- Input: the funding output, signed by both parties.
- Output 0: `cumulativeSatoshis` to the service provider's address.
- Output 1: remaining balance to the consumer's address.
- `nSequence` on the input: the `tick` counter of the most recent dual-signed tick proof.

At any point in the channel lifecycle, both parties hold a valid settlement transaction reflecting the most recently agreed tick. Either party MAY broadcast this transaction at any time — there is no lockout. The consumer might broadcast because the service has failed to respond; the provider might broadcast because the consumer has disconnected. Either broadcast is legitimate.

### Why miners prefer higher `nSequence`

Miners accept the transaction with the highest `nSequence` on a given input. This is the original Satoshi payment-channel design. It means:

- If both parties hold settlement transactions for the same funding output, the one with the higher `nSequence` (more recent metering state) is the one miners will mine.
- A stale transaction (lower `nSequence`) that a party attempts to broadcast is superseded by the honest party broadcasting the latest settlement transaction.
- There is no need for a timelock or a dispute period — the correct transaction wins immediately by virtue of `nSequence` preference.

### Dispute resolution

If a party broadcasts a settlement transaction with a stale `nSequence`, the counterparty's response is straightforward: broadcast the settlement transaction with the highest known `nSequence`. Because miners prefer the higher value, the honest party's transaction settles. The FSM transitions to DISPUTED for audit purposes, but the on-chain outcome is identical to a clean SETTLED transition.

The dual-signed tick proof is the evidence. If the party that broadcast the stale transaction attempts to claim the broadcast was the most recent agreed state, the counterparty produces the tick proof — dual-signed by both parties — demonstrating that a later state was mutually agreed. The HMAC over the channel shared secret provides non-repudiation: the counterparty cannot deny having signed a tick proof they co-signed.

### A worked settlement sequence

> **Worked example — settlement after 500 metering ticks**
>
> 1. NEGOTIATING: Both parties negotiate channel terms. Consumer holds a `cap.metered_access` capability token verified by the Verifier Sidecar. Both parties derive channel keys from their BCAs.
>
> 2. FUNDED: Both co-sign a funding transaction locking 10 000 satoshis in a 2-of-2 output. Transaction is broadcast and enters the mempool.
>
> 3. ACTIVE (on-chain confirmation): Both parties receive a BUMP proof confirming the funding transaction is in a block. Channel transitions to ACTIVE.
>
> 4. Ticks 1–500: The consumer accesses the metered service. Each access produces a tick proof `{ tick: N, hmac: HMAC(secret, N || cumSats || ts), timestamp: T, cumulativeSatoshis: C }`. Both parties countersign each proof. The settlement transaction is updated to reflect the new `nSequence = N` and new output values.
>
> 5. CLOSING_REQUESTED: After tick 500, the consumer initiates close. The consumer proposes the settlement transaction with `nSequence = 500` and `cumulativeSatoshis = 4 750`.
>
> 6. CLOSING_CONFIRMED: The provider countersigns. Both parties now hold an identical settlement transaction.
>
> 7. Either party broadcasts the settlement transaction. Miners confirm it. Output 0: 4 750 satoshis to the provider. Output 1: 5 250 satoshis to the consumer.
>
> 8. SETTLED: On-chain confirmation received. Channel is permanently closed.

At no point did a third party decide the balance. At no point was the channel's internal state transmitted to anyone outside the two parties. The tick proofs are kept locally (or in the recovery substrate, encrypted, accessible only to the two parties). The chain sees only the funding transaction and the final settlement transaction.

---

## Integration with the substrate

### The session skeleton's metering hook

MFP integrates with the mesh's six-piece session skeleton via the Metering Hook — the optional sixth piece that emits MeteringTicks on FSM transitions in a running session. Verticals that require metered access attach the Metering Hook to their `StateMachine<Event, State>` implementation. The hook intercepts state transitions, generates a tick proof for any transition that constitutes a billable event, and submits it to both parties for countersigning.

This design means MFP is transparent to the vertical's state machine logic. The vertical defines what counts as a billable event (a domain-specific concern); the Metering Hook handles tick proof construction, countersigning, and `nSequence` advancement.

### Domain flags and metering authority

Metering operations are gated by domain flag `0x0A` (METERING). `OP_CHECKDOMAINFLAG` enforces this at the bytecode layer — a cell engine opcode that reads bytes 24–27 of the cell header as a uint32 and compares against the expected flag value. The enforcement is total and correct (K3, proved in `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`).

A cell that carries metering-related state — tick proofs, channel records, settlement transactions — MUST carry domain flag `0x0A`. The cell engine will refuse to execute metering opcodes against cells carrying a different domain flag. This structural enforcement prevents metering-related operations from leaking across governance domain boundaries.

### Capability tokens as channel credentials

The `cap.metered_access` capability token is verified once at channel open, during the NEGOTIATING-to-FUNDED transition. The Verifier Sidecar checks:

1. The BUMP proof: the minting transaction for the token is in a block.
2. The identity binding: the token's `ownerCertId` matches the participant's BRC-52 certificate.
3. The liveness check: the UTXO is unspent (via watchman, liveness protocol, or direct query).
4. Any time-lock constraints encoded in the locking script.

If any check fails, the FUNDED transition is refused. The channel remains in NEGOTIATING until a valid token is presented, or the negotiation times out.

The token is not consumed by the channel open. Its LINEAR nature (K1) means it will eventually be consumed when the participant's metering authority is explicitly revoked — but that is a governance action, not a channel event. An individual channel opening is a credential check, not a capability consumption.

---

## Operational properties

### Atomicity and idempotency

Every FSM transition MUST be atomic: it either completes fully or leaves the channel state unchanged. Failed transitions MUST NOT leave the channel in a partial state. This property mirrors K4 (failure atomicity) at the cell engine level — protocol-layer atomicity and kernel-layer atomicity are the same invariant applied at different scopes.

Every FSM transition MUST be idempotent. Receiving the same triggering event twice — possible under network partition and retry — MUST produce the same next state as receiving it once. The implementation achieves idempotency by storing the most recently reached state and comparing the incoming trigger against the allowed transition set for that state; duplicate triggers for a transition already taken are silently accepted.

### No external arbitration

MFP channels require no external arbitration service. The entire dispute-resolution mechanism is encoded in the `nSequence` preference rule. A honest party that holds the most recent dual-signed tick proof always wins a dispute by broadcasting the corresponding settlement transaction.

This property is operationally significant: the channel remains functional under network partition between the two parties and any external service. As long as both parties have local copies of the most recent tick proofs, the channel can be settled correctly regardless of the availability of any third-party infrastructure.

### Settlement finality

Settlement finality is on-chain. The SETTLED state is reached when the settlement transaction is confirmed in a block. From that point, the balance split is immutable — no subsequent action can alter it. The channel's metering history (tick proofs) may be retained by either party for audit purposes, but they have no further protocol effect once the settlement transaction is confirmed.

### Channel-level hash chain

The sequence of tick proofs within a channel constitutes a hash chain at the channel scope. Each tick's `hmac` field binds the proof cryptographically to the channel shared secret and to the cumulative balance at that point in time — making it impossible to insert, delete, or reorder ticks without invalidating all subsequent HMACs. This property is the channel-scope analogue of K6 (hash-chain integrity: the `prevStateHash` chain is append-only at the cell level). The distinction between the per-cell `prevStateHash` chain and the per-channel tick HMAC chain is one of scope, not of mechanism: both are cryptographically-linked progressions of state that give the substrate verifiable time at their respective scopes.

The tick chain terminates with the final settlement transaction. The settlement transaction's `nSequence` field encodes the tick count; the outputs encode the cumulative balance. The on-chain record is the compressed summary of the tick chain — a single transaction that commits the outcome without committing the full history.

### Pause semantics

The PAUSED state exists to handle operational conditions where metering should be suspended temporarily without closing the channel. Examples include: a maintenance window, a consumer-side interruption that both parties agree to wait out, or a renegotiation of channel terms that requires a temporary halt to tick production.

The key constraint on PAUSED is that the transition back to ACTIVE requires mutual agreement — both parties must signal readiness to resume. A unilateral resume attempt by one party is not a valid trigger. This asymmetry is deliberate: the party that requested the pause may have done so to prevent the other party from accumulating tick debt during a period when the consumer cannot actively monitor consumption. Requiring mutual agreement to resume protects both parties from unintended charges.

During PAUSED, the settlement transaction remains valid. Either party may still broadcast it, transitioning to SETTLED or (via the CLOSING_REQUESTED path) to an orderly close. The PAUSED state does not prevent settlement; it only stops tick production.

### Channel capacity and channel chaining

An MFP channel's financial capacity is bounded by the amount locked in the 2-of-2 multisig funding output. When `cumulativeSatoshis` approaches the locked amount — leaving insufficient headroom for further consumption — the parties have two options:

1. Close the current channel cleanly (CLOSING_REQUESTED → CLOSING_CONFIRMED → SETTLED) and open a new channel with a fresh funding transaction.
2. Negotiate a top-up: a second funding transaction that adds to the channel's spendable balance. This requires both parties' co-operation and is treated as a new negotiation step within the existing channel.

Channel chaining — closing one and opening another — is the simpler approach. The second channel opens immediately after the first settles, with a new funding output, new BCA keys (derived deterministically from the same `cert_id`s but with an incremented channel index), and a fresh tick counter starting at 1. The continuity of service is a layer-above concern; from the MFP perspective, each channel is an independent state machine.

---

## The 8-state FSM — complete enumeration

The following is the normative statement of all FSM states and transitions, drawn from Protocol Spec §11.1. This section is the canonical reference for any implementation of the MFP FSM.

### States (8 total)

```
NEGOTIATING
FUNDED
ACTIVE
PAUSED
CLOSING_REQUESTED
CLOSING_CONFIRMED
SETTLED
DISPUTED
```

SETTLED and DISPUTED are terminal states. All others are non-terminal.

### Transitions (9 named transitions + 1 universal)

```
[FIGURE — needs real graphic for layout pass]

FSM state diagram — see ASCII approximation in the 8-state FSM section above.
```

| # | From               | To                 | Trigger                                         | Direction   |
|---|--------------------|--------------------|--------------------------------------------------|-------------|
| 1 | NEGOTIATING        | FUNDED             | Both parties sign the funding transaction        | Progressive |
| 2 | FUNDED             | ACTIVE             | Funding transaction confirmed on-chain           | Progressive |
| 3 | ACTIVE             | PAUSED             | Either party requests pause                      | Lateral     |
| 4 | PAUSED             | ACTIVE             | Both parties agree to resume                     | Lateral     |
| 5 | ACTIVE             | CLOSING_REQUESTED  | Either party initiates close                     | Progressive |
| 6 | PAUSED             | CLOSING_REQUESTED  | Either party initiates close                     | Progressive |
| 7 | CLOSING_REQUESTED  | CLOSING_CONFIRMED  | Counterparty acknowledges close                  | Progressive |
| 8 | CLOSING_CONFIRMED  | SETTLED            | Settlement transaction confirmed on-chain        | Terminal    |
| 9 | (any non-terminal) | DISPUTED           | Fraud detected — stale `nSequence` broadcast     | Terminal    |

Transitions 1, 2, 5, 6, 7, 8 are progressive (the channel cannot revert to an earlier progressive state). Transitions 3 and 4 are lateral (the channel can cycle between ACTIVE and PAUSED as many times as the parties agree). Transitions 8 and 9 are terminal (no further transitions are possible from SETTLED or DISPUTED).

### Invariants over the FSM

The TLA+ model check (`proofs/tla/MeteringFSM.tla`) establishes three properties over the FSM:

1. **No dead states.** Every non-terminal state has at least one outgoing transition. The channel cannot become stuck in a state from which no progress is possible.

2. **No invalid transitions.** The only reachable state pairs `(S, T)` are those listed in the transition table. An implementation that attempts any other transition MUST be treated as a protocol violation.

3. **Dispute always terminates.** From DISPUTED, the counterparty's broadcast of the highest-`nSequence` settlement transaction produces on-chain finality. The dispute cannot persist indefinitely.

---

## The nSequence settlement mechanism — protocol summary

For reference, the complete settlement mechanism stated as protocol rules:

1. Each MeteringTick increments the `tick` counter by 1 and produces a tick proof.
2. The tick proof MUST be dual-signed before it is accepted as a valid metering record.
3. The settlement transaction is updated after each dual-signed tick: `nSequence` is set to the current `tick`; Output 0 amount is set to `cumulativeSatoshis`; Output 1 amount is set to `fundingAmount - cumulativeSatoshis`.
4. Either party MAY broadcast the settlement transaction at any time.
5. If two competing settlement transactions reach miners, miners accept the one with the higher `nSequence`.
6. The honest party MUST respond to a stale-`nSequence` broadcast by immediately broadcasting the latest settlement transaction.
7. On-chain confirmation of the settlement transaction transitions the FSM to SETTLED (clean close) or confirms on-chain resolution of a DISPUTED channel.

These rules are sufficient to define MFP settlement completely. No additional protocol machinery is required.

---

## Conformance requirements

A conformant MFP implementation MUST satisfy the following:

- The FSM MUST implement all 9 named transitions and MUST reject any transition not in the table.
- The DISPUTED transition MUST be implementable from any non-terminal state.
- Each transition MUST be atomic and idempotent.
- Tick proofs MUST use HMAC-SHA-256 over the channel shared secret, with the canonical message format `tick || cumulativeSatoshis || timestamp`.
- Tick proof HMAC verification MUST use constant-time comparison.
- Tick proofs MUST be dual-signed before acceptance.
- The settlement transaction MUST carry `nSequence` equal to the `tick` of the most recent dual-signed tick proof.
- Channel open MUST be gated by a `cap.metered_access` capability token verified by the Verifier Sidecar.
- Metering cells MUST carry domain flag `0x0A` (METERING); the cell engine MUST enforce this via `OP_CHECKDOMAINFLAG` (K3).
- The MFP implementation SHOULD be verified by running the TLA+ model (`proofs/tla/MeteringFSM.tla`) as part of the conformance test suite.

---

## Boot-sequence step 14 is now unlocked

This chapter has covered MFP in full: the 8-state FSM with all transitions enumerated, the tick proof format, the `nSequence` settlement mechanism, the capability token gate, the domain flag enforcement, and the operational properties that follow from the TLA+ model check.

With MFP in place, boot-sequence step 14 — "Metered services open MFP cashlanes" — is unlocked. A sovereign node that has progressed through step 13 (recovery payload backed up to the Plexus Recovery Service) can now open MFP channels, accept metering ticks, and settle paid resource flows with on-chain finality. No external payment processor arbitrates. No central ledger tracks balances. The channel is self-contained between its two parties; the chain settles the final state.

Step 15 — "User is online, sovereign, federated" — follows immediately. It is not a protocol step but a consequential state: a node that has completed all fourteen preceding steps is, by definition, online with its own identity, connected to the mesh, capable of recovery, and able to meter and settle resource flows. The boot sequence is complete.

Part VI — Time, Recovery, and Metering — is complete. Part VII introduces the domain lexicon chapters, beginning with the jural lexicon that underlies the SIR's seven-category type system.
