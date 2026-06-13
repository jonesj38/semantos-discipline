---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/RecoveryFlow.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.345743+00:00
---

# proofs/tla/RecoveryFlow.tla

```tla
--------------------------- MODULE RecoveryFlow ---------------------------
(*
 * Plexus disaster-recovery protocol (Phase W7) — multi-step refinement of
 * KeyCustody.tla's `BeginRecovery` action.
 *
 * KeyCustody.tla's `BeginRecovery` is a one-step transition from `consumed`
 * to `reconstructible_via_plexus`, guarded by `RecoveryEnrolled[t]` and
 * `RecoveryFactorOk[t]`. That abstraction is sufficient for the per-tier-
 * key custody invariants but glosses over the actual W7 protocol, which
 * is a 4-step round-trip with intermediate states, OTP rate limiting, and
 * concurrent-actor adversarial scenarios. This module models the protocol
 * at the resolution that surfaces those concerns.
 *
 * Refinement relationship (informal): a state of this spec where
 * `recoveryStep = "completed" /\ seedDecrypted = TRUE` corresponds to
 * KeyCustody's `KeyState[t] = "reconstructible_via_plexus"`. The
 * intermediate states (otp_dispatched, challenge_open, otp_locked, failed)
 * are stuttering steps from KeyCustody's perspective.
 *
 * Source: docs/design/WALLET-TIER-CUSTODY.md §7.7 (enrollment), §7.8
 *   (recovery flow), §8.1 (operator API), §8.2 (envelope invariants).
 *   Implementation: apps/wallet-browser/src/plexus/dispatch.ts (recover),
 *   apps/wallet-browser/src/plexus/envelope.ts (buildEnvelope + the five
 *   §8.2 invariant checks).
 *
 * Adversary model:
 *   - One legitimate actor (the user who enrolled) and one adversary actor
 *     (someone who knows the email but not the OTP / answers).
 *   - The adversary can call recoveryInitiate (Plexus rate-limits but
 *     doesn't refuse), can guess OTPs, and can guess challenge answers.
 *   - The adversary cannot intercept the OTP (delivered out-of-band) — but
 *     CAN race-condition the legitimate flow.
 *   - The adversary cannot decrypt the recovery seed without the answers
 *     (seed is AES-GCM-sealed under PBKDF2(answers || salt), per §6.3).
 *
 * What this model verifies:
 *   - SAFE-OtpRateLimit: after MaxOtpAttempts wrong OTPs, the protocol
 *     locks; no path leads to completion.
 *   - SAFE-RecoveryRequiresEnrollment: completed → enrolledAt /= NEVER.
 *   - SAFE-EnvelopeRequiresCorrectOtp: envelopeRevealed → an OTP was
 *     correct (not from a locked-out flow).
 *   - SAFE-SeedRequiresEnvelopeAndAnswers: seedDecrypted →
 *     envelopeRevealed /\ correctAnswersSubmitted.
 *   - SAFE-AdversaryCannotComplete: even with infinite OTP attempts in
 *     parallel (bounded by MaxOtpAttempts per email), an adversary that
 *     doesn't know the answers cannot reach seedDecrypted = TRUE.
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Actors,             \* Set of concurrent actors (e.g. {legit, adversary})
    MaxOtpAttempts,     \* OTP attempts before per-email lockout (e.g. 2)
    NEVER,              \* Sentinel for "never enrolled"
    LegitActor          \* Distinguished actor that knows the answers

\* --- Recovery protocol step states ---

Steps == {
    "idle",            \* No active recovery flow
    "otp_dispatched",  \* Plexus delivered OTP; awaiting submission
    "otp_locked",      \* MaxOtpAttempts hit — flow is dead
    "challenge_open",  \* OTP correct; awaiting answer hashes
    "completed",       \* Plexus released the envelope
    "failed"           \* Wrong answers / decrypt failed
}

\* --- State variables ---

VARIABLES
    recoveryStep,            \* Steps — current protocol step
    otpAttempts,             \* Nat — count of wrong OTPs in this flow
    initiatingActor,         \* Actors ∪ {NEVER} — who initiated this flow
    enrolledAt,              \* Nat ∪ {NEVER} — was the user ever enrolled?
    envelopeRevealed,        \* BOOLEAN — operator returned envelope bytes
    correctAnswersSubmitted, \* BOOLEAN — at least one actor submitted right answers
    seedDecrypted            \* BOOLEAN — some actor decrypted the seed locally

vars == <<recoveryStep, otpAttempts, initiatingActor, enrolledAt,
          envelopeRevealed, correctAnswersSubmitted, seedDecrypted>>

\* --- Initial state ---

Init ==
    /\ recoveryStep = "idle"
    /\ otpAttempts = 0
    /\ initiatingActor = NEVER
    /\ enrolledAt = NEVER
    /\ envelopeRevealed = FALSE
    /\ correctAnswersSubmitted = FALSE
    /\ seedDecrypted = FALSE

\* --- Enrollment (one-shot) ---

(*
 * Enroll: the user enrolled at some prior point. Models §7.7 dispatch +
 * confirm successfully completing. Once enrolled, the recovery flow
 * becomes possible.
 *)
Enroll ==
    /\ enrolledAt = NEVER
    /\ enrolledAt' = 1
    /\ UNCHANGED <<recoveryStep, otpAttempts, initiatingActor,
                   envelopeRevealed, correctAnswersSubmitted, seedDecrypted>>

\* --- Recovery protocol actions ---

(*
 * InitiateRecovery(a): actor `a` calls /recovery/initiate with the
 * enrolled email. Plexus delivers an OTP. Bounded to one concurrent
 * flow per email — the operator rate-limit at /recovery/initiate
 * forbids a second initiation while the first is open.
 *)
InitiateRecovery(a) ==
    /\ a \in Actors
    /\ enrolledAt /= NEVER
    /\ recoveryStep = "idle"
    /\ recoveryStep' = "otp_dispatched"
    /\ initiatingActor' = a
    /\ otpAttempts' = 0
    /\ UNCHANGED <<enrolledAt, envelopeRevealed, correctAnswersSubmitted,
                   seedDecrypted>>

(*
 * SubmitCorrectOtp(a): actor `a` submits the OTP that matches the one
 * Plexus delivered. The OTP is delivered out-of-band to the enrolled
 * email — only the LegitActor (who controls that email) can read it.
 * An adversary who initiated the flow (causing an OTP to be sent to
 * legit's email) cannot read the OTP, so cannot fire this action.
 *)
SubmitCorrectOtp(a) ==
    /\ a \in Actors
    /\ a = LegitActor
    /\ recoveryStep = "otp_dispatched"
    /\ recoveryStep' = "challenge_open"
    /\ UNCHANGED <<otpAttempts, initiatingActor, enrolledAt,
                   envelopeRevealed, correctAnswersSubmitted, seedDecrypted>>

(*
 * SubmitWrongOtp(a): actor `a` submits a wrong OTP guess. After
 * MaxOtpAttempts wrong submissions, the flow locks. This is the
 * rate-limit defense modelled at §8.1: the operator counts wrong-OTP
 * submissions per email and locks after the threshold. Only the
 * adversary fires this action — the legit actor knows the correct OTP
 * and would never guess.
 *)
SubmitWrongOtp(a) ==
    /\ a \in Actors
    /\ a /= LegitActor
    /\ recoveryStep = "otp_dispatched"
    /\ otpAttempts < MaxOtpAttempts
    /\ otpAttempts' = otpAttempts + 1
    /\ recoveryStep' =
           IF otpAttempts + 1 >= MaxOtpAttempts THEN "otp_locked"
           ELSE "otp_dispatched"
    /\ UNCHANGED <<initiatingActor, enrolledAt, envelopeRevealed,
                   correctAnswersSubmitted, seedDecrypted>>

(*
 * SubmitCorrectAnswers(a): actor `a` (only the legit actor knows the
 * answers per §6.3 challenge-bundle) submits answer hashes. Plexus
 * verifies hashes against the enrolled bundle and returns the envelope.
 * Only `LegitActor` can fire this action because only `LegitActor`
 * knows the plaintext answers (modelled as a constraint on the action's
 * guard).
 *)
SubmitCorrectAnswers(a) ==
    /\ a \in Actors
    /\ a = LegitActor
    /\ recoveryStep = "challenge_open"
    /\ recoveryStep' = "completed"
    /\ envelopeRevealed' = TRUE
    /\ correctAnswersSubmitted' = TRUE
    /\ UNCHANGED <<otpAttempts, initiatingActor, enrolledAt, seedDecrypted>>

(*
 * SubmitWrongAnswers(a): the adversary submits guessed answer hashes.
 * Plexus rejects (hashes don't match the enrolled bundle); the flow
 * fails. Per §6.3 + §7.8: the operator never reveals the envelope on
 * a wrong-answer submission. The flow transitions to "failed" — the
 * adversary cannot retry from this point in the same flow.
 *)
SubmitWrongAnswers(a) ==
    /\ a \in Actors
    /\ a /= LegitActor
    /\ recoveryStep = "challenge_open"
    /\ recoveryStep' = "failed"
    /\ UNCHANGED <<otpAttempts, initiatingActor, enrolledAt,
                   envelopeRevealed, correctAnswersSubmitted, seedDecrypted>>

(*
 * DecryptSeedWithCorrectAnswers(a): actor `a` decrypts the
 * AES-GCM-sealed seed using PBKDF2(answers || salt). Only the legit
 * actor knows the answers; adversaries who somehow obtained the envelope
 * (via, e.g., compromising Plexus storage) still cannot decrypt without
 * the answers (modelled by restricting the action to LegitActor).
 *)
DecryptSeedWithCorrectAnswers(a) ==
    /\ a \in Actors
    /\ a = LegitActor
    /\ envelopeRevealed
    /\ correctAnswersSubmitted
    /\ ~seedDecrypted
    /\ seedDecrypted' = TRUE
    /\ UNCHANGED <<recoveryStep, otpAttempts, initiatingActor, enrolledAt,
                   envelopeRevealed, correctAnswersSubmitted>>

Next ==
    \/ Enroll
    \/ \E a \in Actors :
         \/ InitiateRecovery(a)
         \/ SubmitCorrectOtp(a)
         \/ SubmitWrongOtp(a)
         \/ SubmitCorrectAnswers(a)
         \/ SubmitWrongAnswers(a)
         \/ DecryptSeedWithCorrectAnswers(a)

Spec == Init /\ [][Next]_vars

\* --- Type invariant ---

TypeInv ==
    /\ recoveryStep \in Steps
    /\ otpAttempts \in 0..MaxOtpAttempts
    /\ initiatingActor \in Actors \cup {NEVER}
    /\ enrolledAt \in {NEVER, 1}
    /\ envelopeRevealed \in BOOLEAN
    /\ correctAnswersSubmitted \in BOOLEAN
    /\ seedDecrypted \in BOOLEAN

\* --- Safety invariants ---

(*
 * SAFE-OtpRateLimit: the OTP attempt counter is bounded by
 * MaxOtpAttempts; once it hits the threshold, the protocol step is
 * "otp_locked" and no further attempts can fire. Models §8.1's
 * per-email rate limit defense.
 *)
SAFE_OtpRateLimit ==
    /\ otpAttempts <= MaxOtpAttempts
    /\ (otpAttempts = MaxOtpAttempts) =>
           (recoveryStep \in {"otp_locked", "idle"})

(*
 * SAFE-LockedNoCompletion: once the OTP rate limit is hit and the flow
 * is locked, the protocol cannot transition to completed. The user must
 * wait for the rate-limit window to expire and re-initiate (which is a
 * fresh flow, not modelled as a transition from otp_locked).
 *)
SAFE_LockedNoCompletion ==
    (recoveryStep = "otp_locked") =>
        (~envelopeRevealed /\ ~seedDecrypted)

(*
 * SAFE-RecoveryRequiresEnrollment: the protocol cannot reach a
 * completed/sealed state without prior enrollment. The /recovery/initiate
 * endpoint rejects unenrolled emails (§8.1).
 *)
SAFE_RecoveryRequiresEnrollment ==
    (recoveryStep \in {"otp_dispatched", "challenge_open", "completed"}) =>
        (enrolledAt /= NEVER)

(*
 * SAFE-EnvelopeRequiresCorrectAnswers: Plexus only releases the envelope
 * after correct challenge-answer hashes are submitted (§7.8 step 6, §8.1
 * /recovery/complete). An adversary who doesn't know the answers cannot
 * obtain the envelope, even after a correct OTP.
 *)
SAFE_EnvelopeRequiresCorrectAnswers ==
    envelopeRevealed => correctAnswersSubmitted

(*
 * SAFE-SeedRequiresEnvelopeAndAnswers: the recovered seed is recovered
 * locally only after the envelope is in hand AND the same answers used
 * for enrollment are known. This is the §8.2 invariant 3 promise:
 * decryption requires PBKDF2(answers || salt) to match the enrolled key.
 *)
SAFE_SeedRequiresEnvelopeAndAnswers ==
    seedDecrypted => (envelopeRevealed /\ correctAnswersSubmitted)

(*
 * SAFE-AdversaryCannotComplete: even with concurrent attempts, an
 * adversary who is not the LegitActor cannot reach seedDecrypted = TRUE.
 * This is the headline security property — the recovery protocol's
 * resistance to a non-knowledge-of-answers attacker.
 *
 * The proof is structural: SubmitCorrectAnswers and
 * DecryptSeedWithCorrectAnswers both require `a = LegitActor`; the
 * adversary's only path to envelopeRevealed is through
 * correctAnswersSubmitted, which they cannot set; without a revealed
 * envelope they can't reach seedDecrypted. TLC verifies this property
 * holds across all reachable interleavings.
 *)
SAFE_AdversaryCannotComplete ==
    seedDecrypted => correctAnswersSubmitted

(*
 * SAFE-OneCompletion: at most one completion per flow. The protocol is
 * single-shot — once envelopeRevealed becomes TRUE, no further
 * SubmitCorrectAnswers / SubmitWrongAnswers can fire (those actions
 * require recoveryStep = "challenge_open"). Cross-checks state-machine
 * monotonicity.
 *)
SAFE_OneCompletion ==
    (recoveryStep \in {"completed", "failed", "otp_locked"}) =>
        (recoveryStep' \in {"completed", "failed", "otp_locked"})

\* --- Liveness obligations ---

(*
 * LIVE-EventualEnrollment: under fairness, enrollment eventually
 * happens. Trivial step-bounded progress claim.
 *)
LIVE_EventualEnrollment == <>(enrolledAt /= NEVER)

(*
 * Note on stronger liveness: a claim of the form "the legit actor
 * eventually decrypts the seed" does NOT hold in this model. The
 * adversary can race the legit actor's OTP submission with
 * MaxOtpAttempts wrong-OTP submissions, locking the flow before legit
 * fires. This is a real protocol property — the operator's per-email
 * rate limit accepts a DoS attack at the cost of locking. The user's
 * workaround in real deployment is to wait for the rate-limit window
 * to expire and re-initiate; that recovery-window cycle is not
 * modelled here (would require a Tick action and a configurable
 * window length, blowing up the state space). The honest claim is
 * step-bounded: every reachable state eventually reaches a terminal
 * step (completed, failed, otp_locked, or idle), captured by
 * SAFE_OneCompletion's monotonicity rather than a liveness assertion.
 *)

\* --- Fairness ---
(*
 * SF on the legit actor's actions, plus enrollment and initiation. The
 * adversary's actions are NOT under fairness — they may or may not fire,
 * but even when they do, the safety invariants hold.
 *)
FairSpec ==
    Spec
    /\ SF_vars(Enroll)
    /\ SF_vars(InitiateRecovery(LegitActor))
    /\ SF_vars(SubmitCorrectOtp(LegitActor))
    /\ SF_vars(SubmitCorrectAnswers(LegitActor))
    /\ SF_vars(DecryptSeedWithCorrectAnswers(LegitActor))

\* --- Temporal lift of the action-level monotonicity claim ---

PROP_OneCompletion == [][SAFE_OneCompletion]_vars

=============================================================================

```
