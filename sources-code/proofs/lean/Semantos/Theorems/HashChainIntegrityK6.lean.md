---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/lean/Semantos/Theorems/HashChainIntegrityK6.lean
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.370069+00:00
---

# proofs/lean/Semantos/Theorems/HashChainIntegrityK6.lean

```lean
-- Semantos Plane — Theorem K6: Hash-Chain Integrity
--
-- K6 (Hash-chain integrity): prevStateHash links form an append-only
-- chain, externally anchored. Tampering is detectable by any party
-- with SPV access to the chain tip.
--
-- This is the one K-invariant that historically lived only in TLA+
-- model checks. This file adds the Lean-side proof, closing the
-- one acknowledged Lean gap in docs/PROOF-COVERAGE.md.
--
-- Source: Craig Wright, hash-chain semantics; docs/textbook/19-hash-
-- chains-as-time.md; docs/FORMAL-VERIFICATION-STRATEGY.md line 47.
--
-- Proof target:
--   - semantic-objects.ts — patch chain construction
--   - cellPacker — prevStateHash header field (offset 128, 32 bytes)
--   - BSV anchor — externally-verifiable tip commitment
--
-- Theorem strategy:
--   - K6a (step injectivity) — single chain step preserves distinctness
--     of inputs in the output hash. Follows from concat injectivity
--     and SHA-256 collision resistance.
--   - K6 (main) — tip hash is a faithful witness for the genesis: if
--     two chains have the same patch sequence and the same tip, they
--     must have had the same genesis. Contrapositive: tampering with
--     genesis is detectable from the tip.

import Semantos.CryptoAxioms

namespace Semantos.Theorems

open Semantos.Crypto

-- ══════════════════════════════════════════════════════════════════════
-- Model: hash chain of patches
-- ══════════════════════════════════════════════════════════════════════

/-- A patch is a piece of state-change data committed at a chain
    position. Its `commit` is the bytes that get hashed into the chain
    (in production this is the patch payload hash; we abstract over
    the payload-hashing layer and treat `commit` as the prepared input
    to the chain-step concat). -/
structure Patch where
  commit : Bytes

/-- A chain is a sequence of patches plus a genesis hash.
    Linear, append-only: each patch's hash inputs are the previous
    tip hash composed with the patch's own commit bytes. -/
structure Chain where
  genesis : Bytes
  patches : List Patch

namespace Chain

/-- Step function input: combine the previous tip hash with the next
    patch's commit bytes. In production the input to SHA-256 at each
    chain step is the concatenation of the previous hash and the
    patch payload hash. We axiomatize concat and assume injectivity
    in the joint argument; the security argument depends only on
    collision-resistance of SHA-256 over the resulting byte string. -/
axiom concat : Bytes → Bytes → Bytes

/-- Concat is injective in the joint argument: distinct (prev, commit)
    pairs produce distinct concatenated bytes. Justified by the wire
    format — `prev` is fixed-width 32 bytes and `commit` follows, so
    decoding is unambiguous. -/
axiom concat_injective :
  ∀ (a₁ a₂ b₁ b₂ : Bytes),
    (a₁ ≠ a₂ ∨ b₁ ≠ b₂) → concat a₁ b₁ ≠ concat a₂ b₂

/-- The tip hash of a chain, computed by folding the step function
    over the patch list starting from the genesis hash. Noncomputable
    because `sha256` is an axiom (no code generator). -/
noncomputable def tipHash : Chain → Bytes
  | ⟨g, []⟩         => g
  | ⟨g, p :: rest⟩  =>
    tipHash ⟨sha256 (concat g p.commit), rest⟩

/-- Convenience: tip hash after appending one patch on top of a base
    tip. Same as one step of `tipHash` starting from the base. -/
noncomputable def stepTip (prev : Bytes) (p : Patch) : Bytes :=
  sha256 (concat prev p.commit)

end Chain

open Chain

-- ══════════════════════════════════════════════════════════════════════
-- K6a: Step injectivity
-- ══════════════════════════════════════════════════════════════════════

/-- K6a — single-step tampering detection: if either the input prev-hash
    differs or the patch differs, the resulting step-tip hash differs.
    Follows directly from concat injectivity + SHA-256 collision
    resistance (both axiomatized in `Semantos.Crypto`). -/
theorem k6a_step_injective
    (prev₁ prev₂ : Bytes) (p₁ p₂ : Patch)
    (h : prev₁ ≠ prev₂ ∨ p₁.commit ≠ p₂.commit) :
    stepTip prev₁ p₁ ≠ stepTip prev₂ p₂ := by
  unfold stepTip
  intro h_eq
  have h_concat : concat prev₁ p₁.commit ≠ concat prev₂ p₂.commit :=
    concat_injective prev₁ prev₂ p₁.commit p₂.commit h
  exact sha256_collision_free _ _ h_concat h_eq

-- ══════════════════════════════════════════════════════════════════════
-- K6 main theorem: tip hash determines genesis (for fixed patch list)
--
-- Statement: if two chains share the same patch sequence and produce
-- the same tip hash, they must have had the same genesis hash.
--
-- Contrapositive: tampering with the genesis is detectable from the
-- tip, even when the rest of the patch sequence matches.
-- ══════════════════════════════════════════════════════════════════════

/-- K6 — hash-chain integrity main theorem.

    If two chains share the same patch sequence and produce the same
    tip hash, their genesis hashes must have been the same. Equivalently
    (contrapositive): given equal patches, distinct genesis hashes
    produce distinct tip hashes.

    Proof: induction on the patch list. The base case (empty patches)
    is direct — the tip is just the genesis. The inductive case uses
    the contrapositive of `k6a_step_injective`: equal step outputs
    imply equal step inputs, so the recursion is grounded in the same
    new "genesis" for the suffix on both sides, and the IH closes it.
 -/
theorem k6_hash_chain_integrity :
    ∀ (patches : List Patch) (g₁ g₂ : Bytes),
      Chain.tipHash ⟨g₁, patches⟩ = Chain.tipHash ⟨g₂, patches⟩ →
      g₁ = g₂ := by
  intro patches
  induction patches with
  | nil =>
    intro g₁ g₂ h_tip
    simp [Chain.tipHash] at h_tip
    exact h_tip
  | cons p rest ih =>
    intro g₁ g₂ h_tip
    simp [Chain.tipHash] at h_tip
    -- After unfolding: tipHash ⟨sha256(concat g₁ p.commit), rest⟩
    --                = tipHash ⟨sha256(concat g₂ p.commit), rest⟩.
    -- Apply IH at the new genesis pair to get the SHAs equal.
    have h_sha_eq :
        sha256 (concat g₁ p.commit) = sha256 (concat g₂ p.commit) :=
      ih (sha256 (concat g₁ p.commit)) (sha256 (concat g₂ p.commit)) h_tip
    -- From equal SHA outputs, infer equal inputs (contrapositive of
    -- collision-freeness); then equal `concat g₁ _ = concat g₂ _`
    -- gives equal genesis hashes via concat injectivity.
    -- Use Classical.em rather than by_contra (avoids Mathlib dep).
    rcases Classical.em (g₁ = g₂) with h_eq | h_g_ne
    · exact h_eq
    · exfalso
      have h_concat_ne :
          concat g₁ p.commit ≠ concat g₂ p.commit :=
        concat_injective g₁ g₂ p.commit p.commit (Or.inl h_g_ne)
      exact sha256_collision_free _ _ h_concat_ne h_sha_eq

-- ══════════════════════════════════════════════════════════════════════
-- Contrapositive form: distinct genesis ⇒ distinct tip
-- ══════════════════════════════════════════════════════════════════════

/-- K6 (contrapositive form): two chains with the same patch sequence
    but distinct genesis hashes produce distinct tip hashes. This is
    the operationally useful form — "given access to the tip on chain,
    you can detect tampering of the genesis." -/
theorem k6_genesis_tampering_detectable
    (patches : List Patch) (g₁ g₂ : Bytes) (h : g₁ ≠ g₂) :
    Chain.tipHash ⟨g₁, patches⟩ ≠ Chain.tipHash ⟨g₂, patches⟩ := by
  intro h_eq
  exact h (k6_hash_chain_integrity patches g₁ g₂ h_eq)

end Semantos.Theorems

```
