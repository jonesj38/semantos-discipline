---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/TierEscalation.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.341594+00:00
---

# proofs/tla/TierEscalation.tla

```tla
--------------------------- MODULE TierEscalation ---------------------------
(*
 * Tier classification + cooldown — Wave 8 of the wallet tiered-custody design.
 * Models the system-level guarantee that every spend is signed at the correct
 * tier given the policy ceilings, that the per-tier auth factor is presented
 * before signing, and that consecutive Tier-3 spends respect the configured
 * cooldown.
 *
 * Source: docs/design/WALLET-TIER-CUSTODY.md
 *   - sec 3 (tier schedule + ceilings)
 *   - sec 4.4 (Tier-3 cooldown — host clock v0.1, nSequence v0.2)
 *   - sec 6.3 (POLICY cell layout: tierN_ceiling_sats, tierN_factor_kind,
 *     tier3_cooldown_seconds)
 *   - sec 9.2 (TLA+ obligations: tier classification + cooldown)
 *
 * Lean K1-K13 covers per-opcode soundness; this module covers the
 * BETWEEN-opcode policy enforcement that spans (a) classification of an
 * amount into a tier, (b) auth-factor matching of the configured factor_kind,
 * and (c) the rate-limit envelope on Tier-3.
 *
 * Abstractions:
 *   - Time is modeled as a monotonically-increasing Nat (sec README).
 *   - Amounts are modeled as a small Nat domain bucketed by ceilings; only
 *     the tier classification function matters.
 *   - Factor kinds are abstract symbols ("PIN", "BIO", "VAULT") whose
 *     identity matters for the FactorMatchesTier invariant.
 *   - Rather than tracking the entire history of spends (which blows up
 *     the state space), we keep the two most-recent tier-3 spend
 *     timestamps (sufficient to prove the cooldown invariant for any
 *     consecutive pair, since the engine guards every transition) and
 *     the tier+factor of the most recent ANY spend (sufficient to prove
 *     INV_FactorMatchesTier).
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    MaxAmount,           \* Largest amount the model considers (Nat)
    MaxNow,              \* Cooldown clock horizon (Nat)
    Tier1Ceiling,        \* Policy: tier-1 spend ceiling (sats)
    Tier2Ceiling,        \* Policy: tier-2 spend ceiling (sats)
    Tier3Ceiling,        \* Policy: tier-3 spend ceiling (sats)
                         \* (any amount >= Tier3Ceiling is tier-3)
    Tier3Cooldown,       \* Policy: cooldown between tier-3 spends (seconds)
    Tier1Factor,         \* Policy: factor_kind required for tier-1 (e.g. "PIN")
    Tier2Factor,         \* Policy: factor_kind required for tier-2
    Tier3Factor,         \* Policy: factor_kind required for tier-3
    NEVER                \* Sentinel for "no tier-3 spend has occurred"

\* --- Tier domain (matches sec 3) ---

Tiers == {0, 1, 2, 3}

\* --- Factor-kind domain (abstract; matches sec 6.3) ---

FactorKinds == {"PIN", "BIO", "VAULT", "NONE"}

\* --- Tier classification function (sec 3) ---

Classify(amount) ==
    IF amount < Tier1Ceiling THEN 0
    ELSE IF amount < Tier2Ceiling THEN 1
    ELSE IF amount < Tier3Ceiling THEN 2
    ELSE 3

\* --- Required factor kind for a tier (sec 6.3) ---

RequiredFactor(tier) ==
    CASE tier = 0 -> "NONE"
      [] tier = 1 -> Tier1Factor
      [] tier = 2 -> Tier2Factor
      [] tier = 3 -> Tier3Factor

\* --- State variables ---

VARIABLES
    Now,                       \* monotonic clock (Nat)
    LastTier3Spend,            \* timestamp of most recent successful tier-3
                               \* spend; NEVER = no tier-3 spend yet
    PrevTier3Spend,            \* timestamp of the second-most-recent tier-3
                               \* spend, or NEVER. Together with
                               \* LastTier3Spend this is sufficient to prove
                               \* the cooldown invariant for any consecutive
                               \* pair (since spends are monotone in time).
    PresentedFactor,           \* Tiers -> FactorKinds — current request
                               \* scope's presented factor (NONE = absent)
    Tier0Witness,              \* BOOLEAN — has at least one tier-0 spend
                               \* completed without prompting? (liveness)
    LastSignedTier,            \* tier of the most recent successful Sign,
                               \* or NEVER if no Sign has occurred yet
    LastSignedFactor           \* factor recorded on the most recent
                               \* successful Sign

vars == <<Now, LastTier3Spend, PrevTier3Spend, PresentedFactor,
          Tier0Witness, LastSignedTier, LastSignedFactor>>

\* --- Initial state ---

Init ==
    /\ Now = 0
    /\ LastTier3Spend = NEVER
    /\ PrevTier3Spend = NEVER
    /\ PresentedFactor = [t \in Tiers |-> "NONE"]
    /\ Tier0Witness = FALSE
    /\ LastSignedTier = NEVER
    /\ LastSignedFactor = "NONE"

\* --- Environmental actions ---

(*
 * AdvanceClock: time moves forward. Bounded by MaxNow for finite checking.
 *)
AdvanceClock ==
    /\ Now < MaxNow
    /\ Now' = Now + 1
    /\ UNCHANGED <<LastTier3Spend, PrevTier3Spend, PresentedFactor,
                   Tier0Witness, LastSignedTier, LastSignedFactor>>

(*
 * PresentCorrectFactor(tier): user supplies the tier's required factor.
 * Models the local-OS auth flow (sec 4.1). Guard: the slot must be empty
 * (NONE) — this prevents unbounded re-presentation and keeps the model
 * finite without weakening the invariants. Tier 0 needs no factor.
 *)
PresentCorrectFactor(tier) ==
    /\ tier \in Tiers
    /\ tier > 0
    /\ PresentedFactor[tier] = "NONE"
    /\ PresentedFactor' = [PresentedFactor EXCEPT
                              ![tier] = RequiredFactor(tier)]
    /\ UNCHANGED <<Now, LastTier3Spend, PrevTier3Spend, Tier0Witness,
                   LastSignedTier, LastSignedFactor>>

(*
 * PresentWrongFactor(tier): adversary supplies an incorrect factor kind
 * for a tier. Sign's guard rejects subsequent attempts. Bounded to one
 * witness per tier so the state space stays finite.
 *)
PresentWrongFactor(tier, k) ==
    /\ tier \in Tiers
    /\ tier > 0
    /\ k \in FactorKinds
    /\ k /= RequiredFactor(tier)
    /\ k /= "NONE"
    /\ PresentedFactor[tier] = "NONE"
    /\ PresentedFactor' = [PresentedFactor EXCEPT ![tier] = k]
    /\ UNCHANGED <<Now, LastTier3Spend, PrevTier3Spend, Tier0Witness,
                   LastSignedTier, LastSignedFactor>>

\* --- Wallet sign action ---

(*
 * Sign(amount): the wallet executes a spend. The tier is classified from
 * the amount; the spend succeeds only if the presented factor matches the
 * policy's required factor_kind for that tier; for tier-3 the cooldown
 * must have elapsed.
 *
 * NOTE: this is the system-level Sign — the actual OP_SIGN opcode-level
 * proof is K11 in Lean. Here we only model the policy gate.
 *)
Sign(amount) ==
    LET tier   == Classify(amount)
        factor == IF tier = 0 THEN "NONE" ELSE PresentedFactor[tier] IN
    /\ amount <= MaxAmount
    /\ \/ tier = 0
       \/ /\ tier > 0
          /\ PresentedFactor[tier] = RequiredFactor(tier)
    /\ IF tier = 3 /\ LastTier3Spend /= NEVER
       THEN Now - LastTier3Spend >= Tier3Cooldown
       ELSE TRUE
    /\ LastSignedTier' = tier
    /\ LastSignedFactor' = factor
    /\ Tier0Witness' = (Tier0Witness \/ tier = 0)
    /\ LastTier3Spend' =
           IF tier = 3 THEN Now ELSE LastTier3Spend
    /\ PrevTier3Spend' =
           IF tier = 3 THEN LastTier3Spend ELSE PrevTier3Spend
    /\ UNCHANGED <<Now, PresentedFactor>>

\* --- Adversary actions ---

(*
 * AttemptSignWithoutFactor: try to sign at tier >= 1 without presenting
 * the correct factor. The Sign action's guard prevents this — modeled
 * here as a no-op so TLC exercises the failed-path enable check.
 *)
AttemptSignWithoutFactor(amount) ==
    LET tier == Classify(amount) IN
    /\ amount <= MaxAmount
    /\ tier > 0
    /\ PresentedFactor[tier] /= RequiredFactor(tier)
    /\ UNCHANGED vars

(*
 * AttemptTier3WithinCooldown: try to fire tier-3 inside the cooldown
 * window. Blocked by the Sign guard.
 *)
AttemptTier3WithinCooldown(amount) ==
    LET tier == Classify(amount) IN
    /\ amount <= MaxAmount
    /\ tier = 3
    /\ LastTier3Spend /= NEVER
    /\ Now - LastTier3Spend < Tier3Cooldown
    /\ UNCHANGED vars

Next ==
    \/ AdvanceClock
    \/ \E t \in Tiers : PresentCorrectFactor(t)
    \/ \E t \in Tiers, k \in FactorKinds : PresentWrongFactor(t, k)
    \/ \E amt \in 0..MaxAmount : Sign(amt)
    \/ \E amt \in 0..MaxAmount : AttemptSignWithoutFactor(amt)
    \/ \E amt \in 0..MaxAmount : AttemptTier3WithinCooldown(amt)

Spec == Init /\ [][Next]_vars

\* --- Fairness for liveness ---

FairSpec ==
    Spec
    /\ SF_vars(AdvanceClock)
    /\ SF_vars(PresentCorrectFactor(1))
    /\ SF_vars(PresentCorrectFactor(2))
    /\ SF_vars(PresentCorrectFactor(3))
    /\ SF_vars(Sign(0))                  \* tier-0 micropayment witness

\* --- Type invariant ---

TypeInv ==
    /\ Now \in 0..MaxNow
    /\ LastTier3Spend \in (0..MaxNow) \cup {NEVER}
    /\ PrevTier3Spend \in (0..MaxNow) \cup {NEVER}
    /\ PresentedFactor \in [Tiers -> FactorKinds]
    /\ Tier0Witness \in BOOLEAN
    /\ LastSignedTier \in Tiers \cup {NEVER}
    /\ LastSignedFactor \in FactorKinds

\* --- Safety invariants (design sec 9.2) ---

(*
 * INV-FactorMatchesTier: the most recent successful Sign(tier, amount)
 * had a factor matching the policy's required factor_kind for that tier
 * (or "NONE" for tier 0). Phrased on the most-recent spend rather than
 * the full history, but equivalent in steady state because every Sign
 * that ever fires must satisfy the same guard at its firing time —
 * TLC checks the invariant after every state transition, so a violation
 * at any single spend would surface as a counterexample.
 *)
INV_FactorMatchesTier ==
    \/ LastSignedTier = NEVER
    \/ /\ LastSignedTier = 0
       /\ LastSignedFactor = "NONE"
    \/ /\ LastSignedTier > 0
       /\ LastSignedFactor = RequiredFactor(LastSignedTier)

(*
 * INV-Tier3CooldownRespected: between any two consecutive successful
 * tier-3 spends (the most recent and the one before it), at least
 * Tier3Cooldown seconds elapsed. v0.1 host-clock semantics — Now plays
 * the role of the host clock. The v0.2 nSequence path is structurally
 * identical (relative locktime in script vs host-side check) and so
 * the same abstract invariant applies.
 *)
INV_Tier3CooldownRespected ==
    \/ PrevTier3Spend = NEVER
    \/ LastTier3Spend = NEVER
    \/ /\ PrevTier3Spend /= NEVER
       /\ LastTier3Spend /= NEVER
       /\ LastTier3Spend - PrevTier3Spend >= Tier3Cooldown

(*
 * INV-MonotonicAuthFriction: the classification function is monotone in
 * the amount — increasing the spend amount never decreases the required
 * tier. Constant-level (depends only on Classify and the ceilings).
 *)
INV_MonotonicAuthFriction ==
    \A a1, a2 \in 0..MaxAmount :
        a1 <= a2 => Classify(a1) <= Classify(a2)

(*
 * INV-ClassifyRange: every classified tier is in {0,1,2,3}.
 *)
INV_ClassifyRange ==
    \A a \in 0..MaxAmount : Classify(a) \in Tiers

(*
 * INV-LastTier3Ordered: the previous tier-3 timestamp never exceeds the
 * latest one (when both are set). Sanity check on the variable rotation
 * inside Sign.
 *)
INV_LastTier3Ordered ==
    \/ PrevTier3Spend = NEVER
    \/ LastTier3Spend = NEVER
    \/ PrevTier3Spend <= LastTier3Spend

\* --- Liveness obligations (design sec 9.2) ---

(*
 * LIVE-Tier0NoPrompt: a tier-0 spend below ceiling can complete without
 * any factor prompt. Under FairSpec, AdvanceClock and Sign(0) fire
 * fairly, so eventually Tier0Witness is set.
 *)
LIVE_Tier0NoPrompt == <>(Tier0Witness = TRUE)

(*
 * LIVE-MonotonicTime: the clock keeps advancing under fairness. Models
 * the basic temporal-progress assumption that real wallets have a
 * forward-moving clock.
 *)
LIVE_MonotonicTime == <>(Now = MaxNow)

=============================================================================

```
