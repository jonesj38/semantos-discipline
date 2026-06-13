---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.369487+00:00
---

# proofs/lean/Semantos/Theorems/CapabilityUtxoK15.lean

```lean
-- Semantos Plane — Theorem K15: Capability-UTXO Binding
--
-- K15 (Capability-UTXO binding, proposed in UNIFICATION-ROADMAP §11.2):
--   OP_CHECKCAPABILITY succeeds iff three conditions hold simultaneously:
--   (a) the capability's UTXO is unspent,
--   (b) the signing public key matches the capability holder's pubkey,
--   (c) the query domain flag matches the capability's domain flag.
--
-- This is a forward-looking spec — the runtime currently uses bearer
-- tokens (per memory `brain_auth_model_intent.md`); D-Dcap-engine
-- migrates OP_CHECKCAPABILITY to verify against on-chain UTXO state
-- via BRC-108 + BRC-115's 5-stage verification pipeline.
--
-- The theorem statements here pin the contract the implementation must
-- honor. Properties proved:
--   K15a — Correctness: capCheck succeeds iff the three conditions
--   K15b — Spent fails: capCheck on a spent UTXO always fails
--   K15c — Spend irreversibility: once spent, no transition restores
--          unspent (only minting a fresh capability does)
--   K15d — Wrong-cert fails: capCheck with non-matching pubkey fails
--   K15e — Wrong-domain fails: capCheck with non-matching domain fails
--
-- Per §11.6 GD8: BRC-108 token binding + BRC-103 mutual-auth
-- composition is unspecified upstream. This Lean spec implements the
-- composition explicitly: capCheck assumes a signing pubkey delivered
-- by an authenticated channel (BRC-103) and verifies the cap-UTXO
-- binding (BRC-108 + BRC-115).
--
-- Source target:
--   - core/cell-engine/src/opcodes/plexus.zig — OP_CHECKCAPABILITY (0xC3)
--   - runtime/verifier-sidecar/ — BRC-115 5-stage pipeline
--   - extensions/chain-broadcast/ — UTXO state via BEEF SPV

import Semantos.CryptoAxioms

namespace Semantos.Theorems

open Semantos.Crypto

-- ══════════════════════════════════════════════════════════════════════
-- Model
-- ══════════════════════════════════════════════════════════════════════

/-- UTXO state — binary spent/unspent for the purposes of capability
    binding. Real UTXOs carry more metadata; for K15 only the spent
    bit is load-bearing. -/
inductive UTXOState : Type where
  | unspent
  | spent
  deriving DecidableEq

/-- A capability binds three things:
    - a UTXO (whose state must be tracked on-chain)
    - a holder pubkey (the BRC-52 cert subject)
    - a domain flag (per `core/plexus-contracts/src/domain-flags.ts`'s
      partition; § 8 Q2 of UNIFICATION-ROADMAP)
    The capability itself is identified by its UTXO id. -/
structure Capability where
  utxoId       : Bytes
  utxoState    : UTXOState
  holderPubKey : PubKey
  domainFlag   : Nat

/-- The kernel-side check that OP_CHECKCAPABILITY (0xC3) must implement
    after D-Dcap-engine lands. Three conjuncts, all required:
    (a) UTXO is unspent
    (b) signing pubkey == capability holder pubkey
    (c) query domain == capability domain

    Returns a Prop so we can reason about it without DecidableEq on
    PubKey (which CryptoAxioms.lean leaves opaque). -/
def capCheck (cap : Capability) (sigBy : PubKey) (queryDomain : Nat) : Prop :=
  cap.utxoState = UTXOState.unspent ∧
  sigBy = cap.holderPubKey ∧
  queryDomain = cap.domainFlag

-- ══════════════════════════════════════════════════════════════════════
-- K15a — Correctness: the check is exactly the three-conjunct contract
-- ══════════════════════════════════════════════════════════════════════

/-- K15a — capCheck succeeds iff all three conditions hold. This is
    the contract OP_CHECKCAPABILITY must implement: no shortcut,
    no extra check, no missing check. -/
theorem k15a_capability_check_correctness
    (cap : Capability) (sigBy : PubKey) (q : Nat) :
    capCheck cap sigBy q ↔
      (cap.utxoState = UTXOState.unspent ∧
       sigBy = cap.holderPubKey ∧
       q = cap.domainFlag) := by
  unfold capCheck
  exact Iff.rfl

-- ══════════════════════════════════════════════════════════════════════
-- K15b — Spent UTXOs always fail
-- ══════════════════════════════════════════════════════════════════════

/-- K15b — if the UTXO is spent, capCheck cannot succeed regardless of
    the signing key or query domain. This is the "spending a capability
    revokes it" property. -/
theorem k15b_spent_utxo_fails
    (cap : Capability) (sigBy : PubKey) (q : Nat)
    (h : cap.utxoState = UTXOState.spent) :
    ¬ capCheck cap sigBy q := by
  unfold capCheck
  intro ⟨h_unspent, _, _⟩
  rw [h] at h_unspent
  exact UTXOState.noConfusion h_unspent

-- ══════════════════════════════════════════════════════════════════════
-- K15c — Spend irreversibility
-- ══════════════════════════════════════════════════════════════════════

/-- A spend operation on a capability: transitions utxoState from
    unspent to spent. The proof argument `_h` is a precondition that
    prevents calling spendCapability on an already-spent capability;
    the body doesn't reference it but its presence on the signature
    makes the function partial-by-precondition. -/
def spendCapability (cap : Capability) (_h : cap.utxoState = UTXOState.unspent) : Capability :=
  { cap with utxoState := UTXOState.spent }

/-- K15c — once a capability is spent, capCheck on it is permanently
    false. There is no "unspend" operation; the only way to obtain a
    successful capCheck is by minting a fresh capability with a
    new UTXO.

    Combined with K15b, this gives the operational property: the cell
    engine cannot reach a state where a previously-spent capability
    re-succeeds. The capability lifecycle is strictly unspent → spent,
    one-way. -/
theorem k15c_spend_irreversibility
    (cap : Capability) (h_unspent : cap.utxoState = UTXOState.unspent)
    (sigBy : PubKey) (q : Nat) :
    ¬ capCheck (spendCapability cap h_unspent) sigBy q := by
  apply k15b_spent_utxo_fails
  unfold spendCapability
  rfl

-- ══════════════════════════════════════════════════════════════════════
-- K15d — Wrong cert fails
-- ══════════════════════════════════════════════════════════════════════

/-- K15d — capCheck with a signing pubkey that doesn't match the
    capability's holder pubkey fails, even when the UTXO is unspent
    and the domain matches.

    Operational interpretation: stealing the UTXO outpoint isn't
    enough — the attacker also needs the holder's private key (which
    they need to be able to sign as the holder pubkey). -/
theorem k15d_wrong_cert_fails
    (cap : Capability) (sigBy : PubKey) (q : Nat)
    (h : sigBy ≠ cap.holderPubKey) :
    ¬ capCheck cap sigBy q := by
  unfold capCheck
  intro ⟨_, h_sig, _⟩
  exact h h_sig

-- ══════════════════════════════════════════════════════════════════════
-- K15e — Wrong domain fails
-- ══════════════════════════════════════════════════════════════════════

/-- K15e — capCheck with a query domain that doesn't match the
    capability's bound domain flag fails.

    Operational interpretation: a capability minted under one domain
    flag (e.g. `0x01 EDGE_CREATION` per `core/plexus-contracts/src/
    domain-flags.ts`) cannot be used under a different domain
    (e.g. `0x0a METERING`). The K3 (domain isolation) invariant
    composes with K15 here — both checks must pass simultaneously. -/
theorem k15e_wrong_domain_fails
    (cap : Capability) (sigBy : PubKey) (q : Nat)
    (h : q ≠ cap.domainFlag) :
    ¬ capCheck cap sigBy q := by
  unfold capCheck
  intro ⟨_, _, h_dom⟩
  exact h h_dom

-- ══════════════════════════════════════════════════════════════════════
-- Composite K15
-- ══════════════════════════════════════════════════════════════════════

/-- K15 main statement (formal version of §11.2's informal claim).
    capCheck implements the conjunction of three required predicates.
    Equivalent to K15a by construction; provided as the canonical
    public-facing statement. -/
theorem k15_capability_utxo_binding
    (cap : Capability) (sigBy : PubKey) (q : Nat) :
    capCheck cap sigBy q ↔
      (cap.utxoState = UTXOState.unspent ∧
       sigBy = cap.holderPubKey ∧
       q = cap.domainFlag) :=
  k15a_capability_check_correctness cap sigBy q

end Semantos.Theorems

```
