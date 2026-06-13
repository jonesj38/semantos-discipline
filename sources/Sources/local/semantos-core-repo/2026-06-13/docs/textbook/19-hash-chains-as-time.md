---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/19-hash-chains-as-time.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.646976+00:00
---

# Time as a Stack of Hash Chains

Every persistent system needs a notion of time. The question is not whether to have one, but what kind. A single global clock demands coordination. A logical timestamp requires agreement on ordering. A hash chain requires neither: it provides verifiable, tamper-evident sequencing from nothing more than a cryptographic hash function and the discipline to compute it consistently.

The Semantos substrate uses hash chains as its primary mechanism for verifiable time. It does not use one chain — it uses several, each scoped to the granularity at which ordering actually matters. A cell's internal state history is one chain. A region's tick progression is another. A metered payment channel carries a third. A governance domain's key-derivation index maintains a fourth. These four chains coexist, operate independently, and compose under a formal morphism property (K9, *temporal morphism*) that ensures projections of finer-grained chains are consistent with coarser-grained ones.

This chapter explains what hash chains are, why the substrate uses a stack of them rather than one, and precisely which chain governs which kind of ordering. It ends by establishing which chains must be in place before boot-sequence step 12 is possible — the moment adapters subscribe to their event streams and transport and time compose into the substrate's live event model.

---

## The Structure of a Hash Chain

A hash chain is a sequence of states in which each state commits to its predecessor. The commitment is a cryptographic hash:

```
genesis:  prevStateHash = 0x00…00 (32 zero bytes)
state 1:  stateHash_1  = SHA-256(canonical_state_1)
          prevStateHash = 0x00…00
state 2:  stateHash_2  = SHA-256(canonical_state_2)
          prevStateHash = stateHash_1
state N:  stateHash_N  = SHA-256(canonical_state_N)
          prevStateHash = stateHash_{N-1}
```

An observer who holds `stateHash_N` and is given the full state sequence can verify that every link holds: each state's `prevStateHash` matches the predecessor's `stateHash`. Any tampering — inserting, deleting, or modifying a state — breaks at least one link and is detectable without reference to a trusted authority.

The protocol specification (§3.6) states the requirement in normative terms: every state transition MUST produce a new state snapshot with an incremented version, a typed patch recording the delta, a fresh `stateHash` as `SHA-256(canonical_serialised_state)`, and a `prevStateHash` set to the previous state's `stateHash`. A `prevStateHash` that does not match the predecessor's `stateHash` MUST trigger audit logging and state rollback. Violation indicates tampering.

This structure costs one hash computation per state transition. The verification cost is linear in the chain length. Neither figure depends on coordination with other nodes or chains.

### What a hash chain is not

A hash chain is not a clock. It does not measure elapsed wall time; it measures *event order* within a scope. Two independent chains can advance at entirely different rates. A chain with a thousand entries does not necessarily represent more elapsed time than a chain with ten.

A hash chain is also not a conflict-resolution mechanism. Two parties who each advance a chain independently have diverged; there is no automatic merge. The branching policies described later in this chapter are the substrate's answer to the question of what to do when chains diverge.

Finally, a hash chain is not a substitute for anchoring. Anchoring a state root on-chain via `OP_RETURN` provides an external, independently verifiable timestamp — a block header is a commitment to the chain tip that exists outside the substrate's own state. The internal hash chain is necessary but not sufficient for audit-grade provenance; the anchor is the bridge to the public record.

---

## Four Named Chain Scopes

The glossary entry for *hash chain* enumerates four distinct chain scopes:

> Several distinct hash chains co-exist at different scopes: per-cell (`prevStateHash` chain), per-region (Merkle root over entity hashes per WorldTick), per-channel (MFP `nSequence` progression), per-domain (BKDS monotonic `current_index`).

These four scopes are not interchangeable. Each governs a different kind of ordering, operates at a different rate, and has different branching semantics. The table below summarises the differences; the sections that follow explain each scope in depth.

| Scope | Name | Carrier | Advance trigger | Rate | Branch policy |
|-------|------|---------|----------------|------|---------------|
| Cell | `prevStateHash` chain | Cell header offset 128 | Any state-changing patch | Per action | Tree-of-chains (document surfaces) or immutable (finalised cells) |
| Region | WorldTick Merkle root | World Host region supervisor | 20 Hz timer | ~20 Hz | Linear; no user branching |
| Channel | MFP `nSequence` | Bitcoin UTXO spending input | Each metering tick | Per resource unit | Linear; state is the latest `nSequence` |
| Domain | BKDS `current_index` | Plexus Recovery payload | Key derivation event | Sparse | Linear; monotonic by construction |

[FIGURE — needs real graphic for layout pass]

The chain scopes form a partial order by granularity: the cell chain is the finest-grained (one entry per patch to one cell), and the domain chain is the coarsest (one entry per significant derivation event). Region and channel chains sit between them, each at a rate appropriate to their operational domain.

---

## The Cell Chain

### Structure

Every cell header carries two hash fields relevant to its state chain (protocol spec §3.2):

- `ParentHash` (offset 96, 32 bytes): SHA-256 of the parent cell — the structural ancestor in the cell tree, not the state predecessor.
- `PrevStateHash` (offset 128, 32 bytes): SHA-256 of the previous state of *this same cell* — the temporal predecessor.

The `PrevStateHash` field is the chain pointer. For a genesis cell (its first state), `PrevStateHash` is 32 zero bytes. Every subsequent state transition writes the hash of the previous state into this field.

The cell header is read-only after packing (K7, *cell immutability*). This means the chain pointer, once written, cannot be modified by any opcode in the instruction set. The only way to advance the chain is to produce a new cell with the updated state. K7 ensures the chain is append-only by construction at the cell level.

### What the cell chain orders

The cell chain orders the sequence of state patches applied to a single cell. It does not order actions across cells, and it does not provide a cross-cell timestamp. Two cells in the same region can have chains of different lengths with no implication about which advanced more recently.

The canonical form is: each state transition produces one new entry on the cell's chain. The cell engine's `verifyStateChain(chainPtr, chainLen)` export validates that the chain is well-formed — that each `prevStateHash` matches the predecessor's `stateHash`, and that the genesis entry has `prevStateHash = 0x00…00`.

### Branching at the cell scope

The branching policy for cells depends on the surface. For document-editing surfaces (the markdown editor, D-E-md), the resolved policy is tree-of-chains: each branch is its own hash chain, forked from a parent commit. Merge nodes carry two parent hashes. The document's history is a directed tree of independent chains. This matches the user's mental model of collaborative editing and makes branching explicit.

For cells whose state is final — outcome cells, ratified contract cells, finalised capability UTXOs — there is no branching. The chain is a single linear sequence.

The governance question for the markdown editor (Q4, resolved 2026-04-26): "Documents in the markdown editor adopt tree-of-chains branching semantics. Each branch is its own hash chain forked from a parent commit; merge nodes have two parent-hashes." This resolution is normative for D-E-md and for any adapter that models document-like state.

---

## The Region Chain

### Structure

The World Host maintains a per-region chain that advances at approximately 20 Hz. Each WorldTick produces a Merkle root computed over the hashes of all entity states in the region at that tick. That root is the tick's state commitment.

The region chain is not stored in a cell header. It is maintained by the region's OTP supervisor and periodically snapshotted as a kernel snapshot cell for recovery purposes. The chain's semantic payload is: at tick N, the region's aggregate state was committed under root R_N, and the previous tick's root was R_{N-1}.

Formally:

```
WorldTick N:  region_root_N   = MerkleRoot({ entity_stateHash_i : i in region })
              prevRegionRoot  = region_root_{N-1}
```

The region chain is the substrate's answer to the question "in what order did events happen within a region?" Two entity-state transitions that fall within the same WorldTick are unordered with respect to each other. Transitions that fall in different ticks are ordered by tick number.

### What the region chain orders

The region chain provides ordering at the granularity of WorldTicks. It does not order individual entity actions within a tick; those are unordered. It does not order events across regions; cross-region ordering requires a higher-level coordination mechanism.

The region chain is the time axis that adapters subscribe to at boot-sequence step 12. When an adapter subscribes to its region's PubSub topic for tick deltas, it receives a stream of `(tick_number, root, delta)` triples. The adapter can verify the chain — each new root links to the previous — without trusting the World Host's assertions. Verification is O(1) per tick given the previous root.

### Branching at the region scope

The region chain does not branch under normal operation. Authority in a World Host region is exclusive: exactly one OTP supervisor commits state for a given entity at a time. Cross-region entity migration uses a 2-phase commit that preserves the per-entity hash chain through the handoff, but the region chain itself remains linear.

If a region supervisor crashes and is restarted from a snapshot, the chain resumes from the snapshot state. The gap in the chain (ticks between the last committed state and the restart) is recorded in the kernel snapshot. Auditors can identify the gap and request the recovery payload for that period.

---

## The Channel Chain

### Structure

MFP (Metered Flow Protocol) channels use Bitcoin's `nSequence` field as the chain pointer. Each metering tick increments `nSequence` on the spending input of the channel's 2-of-2 multisig UTXO:

```
tick 0:  nSequence = 0x00000001, HMAC_0 = HMAC-SHA-256(key, 0 || satoshis_0 || ts_0)
tick 1:  nSequence = 0x00000002, HMAC_1 = HMAC-SHA-256(key, 1 || satoshis_1 || ts_1)
tick N:  nSequence = 0x0000000N, HMAC_N = HMAC-SHA-256(key, N || satoshis_N || ts_N)
```

The tick proof format (protocol spec §11.2) is:

```
{
  tick:               uint32,
  hmac:               bytes(32),
  timestamp:          uint64,
  cumulativeSatoshis: uint64
}
```

The chain here is not a sequence of hashes of state; it is a sequence of `nSequence` increments paired with HMAC-authenticated proofs. The ordering guarantee comes from Bitcoin's consensus rule: miners accept the transaction with the highest `nSequence`. Only the most recent state can settle.

### What the channel chain orders

The channel chain orders the sequence of metering ticks on a specific payment channel. It does not order ticks across channels. Two channels running concurrently can advance at different rates and their tick sequences are entirely independent.

The channel chain answers the question "how many resource units have been consumed on this channel, and in what order?" It provides the substrate's metering axis — the chain of evidence that a paid service was actually delivered. K6 (*hash-chain integrity*: `prevStateHash` chain is append-only) applies to this chain in its TLA+ model-checked form: the `nSequence` progression is an instance of the general append-only property proved at the distributed level.

### Branching at the channel scope

MFP channels do not branch. The 8-state FSM (protocol spec §11.1) admits no state transitions that fork the channel. If one party broadcasts a stale `nSequence`, the counterparty broadcasts the latest tick's transaction with the higher `nSequence`; miners choose the higher. Dispute resolution is anti-branching by design: the protocol resolves divergence by preferring the higher sequence number, not by allowing both branches to persist.

This is a deliberate property. A payment channel that could branch would require a merge protocol for determining which branch represents the actual liability. Bitcoin's `nSequence` mechanism sidesteps this entirely: there is always a canonical latest state.

---

## The Domain Chain

### Structure

The Plexus Key Derivation Substrate (BKDS) maintains a monotonic `current_index` per domain per resource. This index advances each time a key is derived or rotated within the domain. It is carried in the recovery payload's `derivationStates` field:

```yaml
derivationStates:
  - resourceId:        "..."
    domainFlag:        0x0A      # METERING
    currentIndex:      47
    algorithmVersion:  1
```

The domain chain is not a sequence of hash-linked state snapshots. It is a monotonic integer that serves as a version counter for the key universe within a domain. Its chain-like property is weaker than the cell or region chains: it guarantees that key derivation is monotonically increasing, which prevents key reuse and rollback attacks, but it does not provide hash-linked tamper evidence of the derivation events themselves.

The monotonic guarantee (protocol spec §13.2) is explicit: child indices, rotation indices, and state versions MUST be strictly monotonic. They MUST only increase and MUST never be reused. Any attempt to use a previous `childIndex` or `stateVersion` MUST be rejected as a cryptographic-integrity violation.

### What the domain chain orders

The domain chain orders the sequence of key derivation events within a governance domain. It does not order events across domains; two domains can be at entirely different `current_index` values with no implication about relative timing.

The domain chain answers the question "which version of the key universe is authoritative for this domain?" A recovering device uses the `current_index` ceiling from the recovery payload to validate that it has reconstructed the correct number of keys — no more, no fewer. If the reconstructed key count falls below the ceiling, the recovery is incomplete; if it exceeds it, something has gone wrong.

The `current_index` is also the protection against replay: a recovered device that attempts to re-derive key 47 in a context where the ceiling is 52 cannot impersonate the pre-recovery state. The domain chain's monotonicity is the substrate's third-layer defence against rollback, after the cell chain's `PrevStateHash` requirement and the region chain's tick ordering.

### Branching at the domain scope

Domain chains do not branch. The `current_index` is a global ceiling per domain; there is no mechanism to fork a domain's key universe. This is intentional: a domain with two concurrent derivation paths would require a merge protocol for the key universe, which would violate the cryptographic isolation guarantee (K3, *domain isolation*). The domain chain is the most rigid of the four chains precisely because key material is the most sensitive resource.

---

## K6 and K9: The Formal Chain Properties

### K6 — Hash-chain integrity

K6 states: the `prevStateHash` chain is append-only. This is model-checked in TLA+ against the distributed execution model (`ReplayPrevention.tla` and related specs). The model covers concurrent append operations from multiple writers, network partitions, and crash-recovery scenarios.

K6 does not distinguish between the four chain scopes. It is a general property that applies to any hash chain in the substrate: once a state is committed with a given `prevStateHash`, no future operation can change that hash, insert a state before it, or remove it. The only valid transition is appending a new state that points to the current tip.

The TLA+ model checks K6 under bounded interleavings. The model is not a proof in the Lean sense — it does not cover infinite executions — but it covers all reachable states within the model's state space, which is sufficient for the operational invariants the substrate requires.

### K9 — Temporal morphism

K9 states: hash chains compose under projection. The formal statement is `TemporalMorphismK9.lean` in the Lean proof layer. In operational terms, this means that if you project a finer-grained chain (say, the cell chain) onto a coarser-grained chain (say, the region chain), the projections are consistent: the ordering imposed by the finer chain is preserved by the coarser.

Concretely: if cell A's state at patch M preceded cell B's state at patch N within the same WorldTick, the region chain does not invert that ordering when it commits the tick root. The tick root is a commitment to the aggregate state that includes both patches; the relative order within the tick is preserved in the Merkle structure.

K9 is the property that makes "a stack of hash chains" a coherent model rather than a collection of unrelated sequences. Without K9, a coarser chain could represent a state that contradicts the finer chains it is supposed to summarise. With K9, the chains are guaranteed to compose into a consistent picture of time at multiple granularities.

The temporal morphism applies across all four chain scopes: cell chains project consistently onto region chains; region chains project consistently onto on-chain anchors; domain chains project consistently onto the recovery payload that summarises them. Each projection preserves the ordering properties of the source chain.

---

## When Chains Diverge

Chains diverge in three distinct situations. The substrate's response differs by scope.

### Divergence at the cell scope

Two hat holders editing the same document simultaneously produce divergent cell chains: each author's patches advance the chain from the same parent, creating two branches. The tree-of-chains policy (Q4) names this divergence explicitly — each branch is its own chain, and the merge node has two parent hashes. Divergence is expected and allowed.

Resolution is the document adapter's responsibility. The substrate provides the mechanism (two parent hashes in the merge cell header); the policy (whose branch is authoritative, or how to merge semantically) is a hat-scoped governance decision. The substrate does not impose a merge strategy; it only requires that the merge node links both ancestors.

### Divergence at the region scope

Region chains do not diverge under normal operation. If a partition separates the World Host supervisor from some of its entity processes, the supervisor's tick progression continues but the isolated entities cannot advance their state. When connectivity resumes, the isolated entities re-synchronise by replaying the missed ticks. The region chain remains linear throughout; the gap is a known period with no committed state, not a competing chain.

### Divergence at the channel scope

MFP channels diverge when a party broadcasts a stale `nSequence`. This is a dispute event, not a branching event. The FSM enters `DISPUTED` state. Bitcoin's `nSequence` preference resolves the dispute in favour of the latest state. The channel then follows the single linear chain represented by the highest `nSequence` that was broadcast.

---

## Chain Scope Disambiguation Table

The four scopes answer four different questions. An adapter that needs to determine ordering must identify which question it is asking before selecting which chain to consult.

| Question | Authoritative chain | Field or mechanism | Branching allowed |
|----------|--------------------|--------------------|-------------------|
| In what order were patches applied to this cell? | Cell chain | `PrevStateHash` (header offset 128) | Yes (tree-of-chains for document surfaces) |
| In what order did entity-state transitions occur within a region? | Region chain | WorldTick Merkle root per tick | No |
| How many resource units have been consumed on this payment channel? | Channel chain | MFP `nSequence` | No (dispute resolves to highest `nSequence`) |
| Which version of the key universe is authoritative for this domain? | Domain chain | BKDS `current_index` per domain | No |

[FIGURE — needs real graphic for layout pass]

An adapter that conflates these scopes will reach wrong conclusions. A document editor that uses the WorldTick number as the authority for patch ordering will misorder concurrent patches from different ticks. A metering system that uses the cell chain instead of the `nSequence` to count resource units will not produce a settlement-ready proof. The disambiguation is load-bearing.

---

## Practical Chain Verification

### Verifying a cell chain

The cell engine exports `verifyStateChain(chainPtr, chainLen)`. Given a sequence of cell states in serialisation order, this function checks:

1. The genesis entry has `PrevStateHash = 0x00…00`.
2. For each subsequent entry, `PrevStateHash` equals `SHA-256(canonical_state_{i-1})`.
3. Version numbers are strictly monotonic.

A chain that passes this check is well-formed. It may still be a fork (if the same parent was advanced twice), but each branch is individually well-formed.

### Verifying a region chain

An adapter that has received the current region root and the previous root can verify the chain link:

```
assert: current_root.prevRegionRoot == SHA-256(previous_root_payload)
assert: current_root.tickNumber    == previous_root.tickNumber + 1
```

Verification of the full chain from genesis requires replaying all ticks from the kernel snapshot. In practice, adapters verify the incremental link per tick and trust the snapshot's commitment to the prior history.

### Verifying a channel chain

The counterparty in an MFP channel verifies each tick's HMAC:

```
assert: HMAC-SHA-256(channel_shared_secret, tick || cumulativeSatoshis || timestamp)
        == received_hmac
assert: received_nSequence == expected_nSequence
```

Settlement is verified by presenting the spending transaction to miners; the highest `nSequence` wins without further protocol involvement.

### Verifying a domain chain

The recovering device verifies the domain chain implicitly: after deriving keys from the recovery payload's `current_index` ceiling, it checks that the derived keys match the `derivationStates` entries. A mismatch indicates either tampering with the recovery payload or a bug in the derivation path. The BRC-100 signature on the recovery payload provides the outer integrity check; the `current_index` provides the inner ordering check.

---

## Ticks as Qualified Concepts

The glossary entry for *tick* carries a mandatory disambiguation note: "The unqualified word 'tick' should not be used in any artifact without disambiguation."

This chapter uses two specific kinds:

**WorldTick**: the per-region monotonic counter advancing at approximately 20 Hz. WorldTicks are the step events on the region chain. Each WorldTick produces a Merkle root that commits the region's aggregate entity state.

**MeteringTick**: the per-resource-flow advance of an MFP channel's `nSequence`. MeteringTicks are the step events on the channel chain. Each MeteringTick produces an HMAC-authenticated proof of resource consumption.

The two tick kinds operate at completely different rates and carry completely different proofs. WorldTicks are coordinated by the region supervisor; MeteringTicks are produced bilaterally by the channel participants. An adapter that uses WorldTick counts to gate metering decisions, or MeteringTick counts to drive region state, has crossed the chains in a way the substrate does not support.

---

## The Stack of Chains as a Time Model

The substrate's "time" is not one thing. It is a projection of the relevant chain onto the question at hand:

- "Did this cell change before or after that cell?" → project both cell chains onto a common ancestor or a shared region tick.
- "Did this region-level event happen before or after that one?" → compare WorldTick numbers.
- "Did this payment channel settle after this one started?" → compare `nSequence` values against block timestamps.
- "Is this key derivation using the correct version of the key universe?" → compare `current_index` against the recovery ceiling.

The four chains are a stack in the sense that they are layered by granularity: cell at the finest, domain at the coarsest, region and channel in between. Each layer is autonomous — it advances without coordinating with the others — but K9 guarantees that projections across layers are consistent.

This model is operationally cheaper than a global clock because no coordination is required to advance any individual chain. It is more trustworthy than a logical timestamp because each chain carries cryptographic evidence of its own integrity. And it is more honest than a single timeline: by making the scope of each ordering claim explicit, the substrate avoids the category error of asserting a global ordering that it cannot, in a distributed system, actually enforce.

---

## Boot-Sequence Step 12

Boot-sequence step 12 is:

> Adapters subscribe to: region tick deltas; Plexus identity event stream; capability UTXO change feed.

Step 12 is the moment transport and time compose. An adapter subscribing to region tick deltas receives a stream of WorldTick events, each carrying a Merkle root. The adapter can verify the region chain from the last snapshot forward. An adapter subscribing to the identity event stream receives edge and cert updates whose ordering is governed by the domain chain's `current_index`. An adapter subscribing to the capability UTXO change feed receives spend events whose ordering is determined by block timestamps and `nSequence`.

For step 12 to be possible, three prerequisites must hold:

1. The cell chain discipline must be in place: every state-changing operation on any cell must produce a well-formed `PrevStateHash` link. This is enforced by the cell engine (K6, K7) and is in place from boot-sequence step 7 onward.

2. The region chain must be running: the World Host region supervisor must be producing WorldTick events, each with a Merkle root. This requires step 9 (World Host starts authoritative regions) to have completed.

3. The transport must be in place: adapters subscribe to PubSub topics and the Plexus identity event stream via the mesh using `SignedBundle` envelopes. This requires steps 8 (Verifier Sidecar) and 10 (mesh adapter joins multicast) to have completed.

The channel chain and domain chain do not need to be active for step 12 to unlock. Channel chains are opened lazily when metered services begin (step 14). Domain chains are in place from step 3 (BRC-52 cert derivation) onward, but their role in step 12 is passive: the identity event stream carries cert and edge updates that advance the domain chain, but the adapter need only subscribe, not initiate derivations.

With these prerequisites satisfied, step 12 is unlocked. Each adapter subscribes to the same set of streams via the same `SignedBundle` envelope format carrying the same provenance metadata (BCA, `cert_id`, hash chain pointers). The region chain, cell chains, and domain chain all become visible to every subscribed adapter simultaneously. This is the unification roadmap's step-12 observation rendered concrete: "Step 12 is where transport (axis C) and time (axis E) compose — every adapter subscribes to the same set of streams via the same envelope format."

---

## Summary: Four Scopes, Four Chains, One Stack

The substrate's time model is a stack of four hash chains, each scoped to the granularity at which ordering actually matters:

| Scope | Chain | Governs | Branch policy |
|-------|-------|---------|---------------|
| Cell | `prevStateHash` | Patch order on a single cell | Tree-of-chains (document surfaces); immutable (finalised cells) |
| Region | WorldTick Merkle root | Event order within a region (~20 Hz) | None — linear by design |
| Channel | MFP `nSequence` | Resource unit count on a payment channel | None — `nSequence` preference resolves disputes |
| Domain | BKDS `current_index` | Key derivation version within a governance domain | None — monotonic by construction |

K6 (hash-chain integrity, TLA+ model-checked) establishes that each chain is append-only. K9 (temporal morphism, Lean-proved) establishes that projections across chain scopes are consistent. Together, they make the stack coherent: each chain is individually trustworthy, and the chains compose into a consistent picture of ordering at multiple granularities.

Boot-sequence step 12 — adapter subscription to tick deltas, identity events, and capability UTXO changes — is now unlocked. The cell chain, region chain, and domain chain are all in place. The channel chain will be opened when step 14 (metered services) begins. The adapter event model is ready to receive.
