---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/13-lean-tla-walkthrough.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.641740+00:00
---

# Chapter 13: Lean 4 + TLA+ Walkthrough

Part IV of this textbook — Verification — opened in Chapter 12 with a survey of
invariants K1 through K10. That chapter named each invariant and stated what it
rules out. This chapter descends one level: it opens the proof files themselves,
walks through the structure of one machine-checked Lean 4 proof in detail, and
tours the TLA+ model-checking specification that covers the concurrent-replay
scenario. The goal is to give a reader who has never opened either tool a working
mental model of how the proofs are organized, what they establish, and — critically
— what they do not establish.

Boot step 8 activates the verifier sidecar, which presents cryptographic
attestations of the binary's integrity against the WASM hash anchored on-chain.
The machine-checked proofs described here are the abstract-model layer underneath
that sidecar: they establish that the invariants hold in the formal model, not that
any particular binary matches that model. The relationship between the abstract
proofs and the concrete binary is described in the Limitations section at the end
of this chapter.

---

## The Three-Layer Architecture

The formal verification strategy divides proof work across three layers, each
using the tool that matches the problem's shape.

**Layer 2 — Lean 4 kernel proofs.** The abstract 2-PDA model is defined in Lean 4.
Lean is a dependently-typed proof assistant: every definition is a type-checked
term, and every theorem is a type that must be inhabited by a proof term before the
file compiles. When the Lean file compiles without errors, the theorem is verified
— the type checker has confirmed that every step of the argument is logically
valid. The K1 family of theorems (linearity: no duplication while live, no
unauthorized discard, unique occurrence across stacks) lives here.

**Layer 3 — TLA+ protocol model.** TLA+ (Temporal Logic of Actions) models
distributed protocols as state machines: a set of variables, an initial predicate,
and a set of labeled transitions. The TLC model checker exhausts all reachable
states within a bounded configuration and reports whether a safety or liveness
property holds in every reachable state. The replay prevention specification — K6,
hash-chain integrity, and the multi-actor consumption race — lives here.

**Layer 1 — Implementation conformance.** This layer is empirical, not
machine-checked. It consists of the 240+ Zig conformance tests, property-based
fuzzing harnesses, mutation testing, and differential testing between the Lean
model and the Zig implementation. Layer 1 is the weakest link in the chain; the
Limitations section returns to this.

The rest of this chapter works through Layer 2 and Layer 3 in turn.

---

## K1: Linearity in Lean 4

K1 (Linearity) states: a LINEAR cell is never duplicated while live, never
discarded without authorized consumption, and once consumed cannot reappear unless
a distinct cell is created.

The Lean file at `proofs/lean/Semantos/Theorems/LinearityK1.lean` proves this in
three sub-theorems.

### What the Model Defines

The proof file imports `Semantos.Executor`, which in turn models the abstract 2-PDA
execution environment. The key definitions are:

- `Cell` — a value with a typed header, including a `linearity` field that ranges
  over `linear | affine | relevant | debug`.
- `PDA` — two bounded stacks (`mainStack` and `auxStack`), a program counter, and
  an opcount limit.
- `StackOp` — an enumeration of operation classes: `duplicate`, `discard`,
  `consume`, `swap`, `inspect`.
- `linearityPermits : Linearity → StackOp → Bool` — the gate function. It maps a
  linearity class and an operation class to a boolean. For a LINEAR cell:
  `linearityPermits .linear .duplicate = false` and
  `linearityPermits .linear .discard = false`.
- `ExecutorState` — bundles a PDA, a script (the sequence of opcode bytes), a
  program counter, an opcount, and a `linearityEnforced` flag.
- `ExecutorState.step` — the single-step function. Given a host-provided cell
  fetch function, it advances the executor by one opcode.

The `linearityPermits` table encodes the rules:

```lean
def linearityPermits (l : Linearity) (op : StackOp) : Bool :=
  match l, op with
  | .linear,   .duplicate => false   -- K1: cannot duplicate LINEAR
  | .linear,   .discard   => false   -- K1: cannot discard LINEAR
  | .affine,   .duplicate => false
  | .relevant, .discard   => false
  | _,         _          => true
```

All other combinations return `true`. The LINEAR cell is the most restricted:
neither duplication nor discard is permitted. An AFFINE cell may be discarded but
not duplicated. A RELEVANT cell may be duplicated but not discarded. A DEBUG cell
has no restrictions (it is used only in non-production build configurations).

### K1a: No Duplication While Live

The first sub-theorem comes in two variants. The first is a one-line
definitional theorem:

```lean
theorem k1a_linear_no_duplicate :
    linearityPermits .linear .duplicate = false := rfl
```

`rfl` means "by reflexivity" — both sides of the equation reduce to the same
normal form after unfolding the definition of `linearityPermits`. Lean's type
checker verifies this by computation. There is no deductive proof to construct: the
claim is true by definition.

The second variant is more interesting. It establishes that the executor step
function returns an error — rather than a modified state — when a duplicate
operation is attempted on a LINEAR cell:

```lean
theorem k1a_executor_rejects_dup (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (cell : Cell)
    (h_enforced : state.linearityEnforced = true)
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit)
    (h_op : classifyOp (state.script[state.pc]'(by omega)) = .duplicate)
    (h_top : state.pda.speek = .ok cell)
    (h_lin : cell.header.linearity = .linear) :
    ∃ e, state.step hostFetch = .error e := by
  ...
```

This theorem has a richer statement. It is parameterized by:

- `state` — any executor state (universally quantified)
- `hostFetch` — the host cell-fetch callback (treated as an opaque function; the
  proof does not care what it does)
- `cell` — the cell at the top of the stack
- Five hypotheses (`h_enforced` through `h_lin`) — the conditions under which the
  theorem fires

The conclusion `∃ e, state.step hostFetch = .error e` asserts that there exists
some error value `e` such that the step function returns it. In other words: under
these conditions, the step always fails with an error; it never returns `.ok`.

### Reading the K1a Proof Line by Line

For a reader who has never opened Lean, the proof tactic block (`by ...`) is the
part that deserves attention. Each line is a proof step that transforms the current
goal.

```lean
  simp only [ExecutorState.step]
```

This unfolds the definition of `ExecutorState.step` in the current goal, replacing
the opaque call with its body. After this step, the goal refers to the concrete
`if`-`then`-`else` branches of the step function rather than its name.

```lean
  have h1 : ¬(state.opcount ≥ state.opcountLimit) := by omega
  have h2 : ¬(state.pc ≥ state.script.length) := by omega
```

These two lines derive auxiliary facts from the hypotheses `h_ops` and `h_pc`.
`omega` is a decision procedure for linear arithmetic over natural numbers. Given
`state.opcount < state.opcountLimit`, it immediately concludes
`¬(state.opcount ≥ state.opcountLimit)`. These auxiliary facts are needed to
discharge the bounds-checking guards inside the step function.

```lean
  rw [if_neg h1]
```

The step function begins with an opcount-limit check. `if_neg h1` rewrites an
`if P then ... else ...` expression where `P` is false (by `h1`) into its `else`
branch. This eliminates the "halt because opcount exceeded" branch from the goal:
we are in the case where the opcount has not been exhausted.

```lean
  simp only [h2, dite_false]
```

`dite` is Lean's dependent `if`-`then`-`else` (the `d` stands for "dependent" —
the branches may depend on the proof of the condition). `dite_false` rewrites a
dependent conditional whose condition is false into its false branch. After this
line, the step function's second bounds check (on `state.pc`) is also resolved,
leaving only the linearity-checking branch of the code in the goal.

```lean
  have h_cond : (state.linearityEnforced &&
    classifyOp state.script[state.pc] != StackOp.consume &&
    classifyOp state.script[state.pc] != StackOp.swap &&
    classifyOp state.script[state.pc] != StackOp.inspect) = true := by
    rw [h_enforced, h_op]; decide
```

This derives the key condition for entering the linearity-checking branch. The step
function checks whether linearity enforcement is on and whether the current
operation is one of the three exempt classes (`consume`, `swap`, `inspect` — these
are always allowed regardless of linearity class). We know `h_enforced` says
enforcement is on, and `h_op` says the operation is `.duplicate`, which is not in
the exempt set. After rewriting with these two facts, `decide` closes the goal: it
is a concrete boolean computation over finite types, and Lean can evaluate it.

```lean
  rw [if_pos h_cond]
```

Having proved the condition is true, we enter the `then` branch of the linearity
gate — the branch that checks `linearityPermits`. This removes the outer `if` from
the goal.

```lean
  simp [h_top]
```

The step function peeks at the top of stack with `state.pda.speek`. `h_top` tells
us what it returns (`.ok cell`). This `simp` call substitutes that fact, reducing
the goal to something that depends on whether `linearityPermits` returns `true` or
`false` for this cell.

```lean
  have h_perm : ¬(linearityPermits cell.header.linearity
      (classifyOp state.script[state.pc]) = true) := by
    rw [h_lin, h_op]; decide
```

This derives the key algebraic fact: `linearityPermits .linear .duplicate` is not
`true`. After rewriting with `h_lin` (the cell is LINEAR) and `h_op` (the
operation is `.duplicate`), `decide` evaluates the table and confirms the result is
`false`.

```lean
  simp [h_perm]
```

The final `simp` closes the goal. With `linearityPermits` returning `false`, the
step function returns an error, and the goal `∃ e, ... = .error e` is satisfied by
the specific error the step function constructs.

The entire proof mechanically traces a single execution path through the step
function, discharging each branch condition in order. There is no creative
mathematical insight: the proof is a structured case analysis over the function's
control flow. This is typical of verified executor proofs — the theorem is
architecturally significant (the gate always fires), but the proof itself is
routine.

### K1b: No Unauthorized Discard

The structure of K1b is identical to K1a, with `.discard` substituted for
`.duplicate` throughout. The definitional sub-theorem is:

```lean
theorem k1b_linear_no_discard :
    linearityPermits .linear .discard = false := rfl
```

And the executor version carries the same shape:

```lean
theorem k1b_executor_rejects_drop (state : ExecutorState)
    (hostFetch : Cell → Option Cell)
    (cell : Cell)
    (h_enforced : state.linearityEnforced = true)
    (h_pc : state.pc < state.script.length)
    (h_ops : state.opcount < state.opcountLimit)
    (h_op : classifyOp (state.script[state.pc]'(by omega)) = .discard)
    (h_top : state.pda.speek = .ok cell)
    (h_lin : cell.header.linearity = .linear) :
    ∃ e, state.step hostFetch = .error e := by
  ...
```

The proof body is mechanically parallel to K1a's, substituting `.discard` for
`.duplicate` at each point. The same `omega`, `rw`, `simp`, and `decide` tactic
sequence closes the goal.

K1a and K1b together establish that the only way a LINEAR cell can leave the stacks
is through a `consume`-classified operation. The step function permits `consume` on
a LINEAR cell (it is in the exempt set at the linearity gate). What `consume`
requires — authorization, proof of identity, domain flag matching — is covered by
K2 and K3.

### K1c: Unique Occurrence Across Stacks

The third sub-theorem establishes that a LINEAR cell appears at most once across
both stacks at any reachable state in a valid execution trace. Two helper
definitions set up the bookkeeping:

```lean
def allStackCells (pda : PDA) : List Cell :=
  pda.mainStack.items ++ pda.auxStack.items

def countCell (c : Cell) (cells : List Cell) : Nat :=
  (cells.filter (· == c)).length
```

`allStackCells` concatenates both stacks' cell lists into one. `countCell` counts
occurrences of a specific cell in a list using structural equality.

The theorem is:

```lean
theorem k1c_linear_unique_on_stacks
    (cell : Cell)
    (_h_lin : cell.header.linearity = .linear)
    (state : ExecutorState)
    (_h_enf : state.linearityEnforced = true)
    (hostFetch : Cell → Option Cell)
    (state' : ExecutorState)
    (h_step : state.step hostFetch = .ok state')
    (h_count : countCell cell (allStackCells state.pda) ≤ 1) :
    countCell cell (allStackCells state'.pda) ≤ 1 := by
  have h_pda := step_preserves_pda state state' hostFetch h_step
  rw [allStackCells, h_pda]
  exact h_count
```

This relies on a helper theorem, `step_preserves_pda`, which establishes that a
successful step (`state.step hostFetch = .ok state'`) leaves the PDA unchanged:
only `pc`, `opcount`, and `linearityEnforced` are modified by a step that returns
`.ok`. In the current model, successful steps are control-flow advances; stack
mutations (pushes and pops) are modeled as returning errors or new states in a
richer step relation (the full executor models this; the present proof focuses on
the linearity gate specifically).

Given that the PDA is preserved (`state'.pda = state.pda`), the cell count across
the stacks is the same before and after the step. If the count was at most 1 before
the step (`h_count`), it is at most 1 after. The proof body rewrites `allStackCells
state'.pda` into `allStackCells state.pda` using the PDA preservation lemma, then
closes by the hypothesis.

K1c is proved by induction over individual steps: the base case is provided by the
initial state (a LINEAR cell is loaded at most once), and the inductive step is
provided by this theorem. The full trace invariant follows by applying this theorem
at each step of any execution.

---

## K6: Replay Prevention in TLA+

K6 (hash-chain integrity) states that prevStateHash links form an append-only
chain, externally anchored. Tampering is detectable by any party with SPV access.

K6 is model-checked, not theorem-proved. The TLA+ specification at
`proofs/tla/ReplayPrevention.tla` addresses one specific instantiation of K6: the
replay attack scenario, in which an adversary attempts to consume a LINEAR resource
a second time by replaying a valid consumption proof from a prior transaction.

### Module Structure

The module opens with its CONSTANTS declaration:

```tla
CONSTANTS
    Actors,        \* Set of concurrent actors (model values)
    Resources,     \* Set of resource identifiers (model values)
    TxIds,         \* Set of transaction identifiers (model values)
    NULL           \* Distinguished null value
```

`Actors`, `Resources`, and `TxIds` are left abstract in the specification; the
model checker instantiates them with concrete finite sets (for example,
`Actors = {a1, a2}`, `Resources = {r1, r2}`, `TxIds = {t1, t2, t3}`) in a
configuration file. `NULL` is a distinguished value used to represent "not yet
set" fields.

### State Variables and Type Definitions

```tla
LinearState == [
    type            : {"LINEAR"},
    consumed        : BOOLEAN,
    consumedBy      : Actors \cup {NULL},
    consumptionTxId : TxIds \cup {NULL}
]

AffineState == [
    type         : {"AFFINE"},
    acknowledged : BOOLEAN,
    discarded    : BOOLEAN
]

VARIABLES
    objects,       \* Function: Resources -> object state
    consumeCount   \* Function: Resources -> Nat
```

`LinearState` records whether a resource has been consumed, by whom, and under
which transaction. `AffineState` records the two mutually exclusive termination
states for AFFINE resources. The `objects` variable maps each resource identifier
to its current state. `consumeCount` is an auxiliary variable — it tracks the total
number of successful consumptions for each resource, allowing the safety property to
be stated without quantifying over history.

### Actions

The module defines four actions.

`ConsumeLinear` models a legitimate consumption of a LINEAR resource:

```tla
ConsumeLinear(r, actor, txId) ==
    /\ objects[r].type = "LINEAR"
    /\ ~objects[r].consumed
    /\ objects' = [objects EXCEPT ![r] = [
           objects[r] EXCEPT
               !.consumed = TRUE,
               !.consumedBy = actor,
               !.consumptionTxId = txId
       ]]
    /\ consumeCount' = [consumeCount EXCEPT ![r] = consumeCount[r] + 1]
```

The guard is `~objects[r].consumed` — the resource must not already be consumed.
The effect sets `consumed` to true, records the actor and transaction ID, and
increments the counter. This directly models the `validateConsumption` function in
`src/compiler/validator.ts` (lines 62–82 of that file).

`AcknowledgeAffine` and `DiscardAffine` model the two termination paths for AFFINE
resources. Their guards enforce mutual exclusion: `AcknowledgeAffine` requires the
resource not to have been discarded, and `DiscardAffine` requires it to have been
neither acknowledged nor discarded.

`ReplayAttack` is the adversary action:

```tla
ReplayAttack(r, adversary, capturedTxId) ==
    /\ objects[r].type = "LINEAR"
    /\ ~objects[r].consumed
    /\ objects' = [objects EXCEPT ![r] = [
           objects[r] EXCEPT
               !.consumed = TRUE,
               !.consumedBy = adversary,
               !.consumptionTxId = capturedTxId
       ]]
    /\ consumeCount' = [consumeCount EXCEPT ![r] = consumeCount[r] + 1]
```

The structure of `ReplayAttack` is intentionally identical to `ConsumeLinear`. The
model makes no distinction between a legitimate actor replaying a valid proof and
an adversary doing the same — from the guard's perspective, both are identical. The
specification comment makes this explicit: the `consumed` flag is the only defense.
An adversary who has captured a valid transaction ID gets no advantage, because the
guard checks the resource's consumed state, not the proof's provenance.

### Safety Properties

The module states four safety properties.

```tla
NoDoubleConsume ==
    \A r \in Resources :
        objects[r].type = "LINEAR" => consumeCount[r] <= 1
```

`NoDoubleConsume` is the core property. For every LINEAR resource, the total number
of successful consumptions is at most 1. This is a universal quantification over
all resources in every reachable state. TLC checks this by exploring all reachable
states of the system — with the given CONSTANTS instantiation — and verifying the
predicate holds at each one.

```tla
SingleConsumption ==
    \A r \in Resources :
        objects[r].type = "LINEAR" =>
            (objects[r].consumed =>
                /\ objects[r].consumedBy /= NULL
                /\ objects[r].consumptionTxId /= NULL)
```

`SingleConsumption` adds the structural guarantee: a consumed LINEAR resource
always has both proof fields set. This corresponds to the postcondition of
`validateConsumption` (lines 74–79 in the validator source).

```tla
AffineExclusion ==
    \A r \in Resources :
        objects[r].type = "AFFINE" =>
            ~(objects[r].acknowledged /\ objects[r].discarded)
```

`AffineExclusion` enforces that an AFFINE resource cannot simultaneously be
acknowledged and discarded. The guards on `AcknowledgeAffine` and `DiscardAffine`
make this structurally impossible, but model checking confirms that no sequence of
interleaved actions can reach a violating state.

```tla
ConsumedImpliesProof ==
    \A r \in Resources :
        objects[r].type = "LINEAR" =>
            (objects[r].consumed =>
                /\ objects[r].consumedBy \in Actors
                /\ objects[r].consumptionTxId \in TxIds)
```

`ConsumedImpliesProof` strengthens `SingleConsumption`: the proof fields must not
only be non-null but must actually be elements of the declared CONSTANTS sets.

### The Spec and How TLC Checks It

The module closes with:

```tla
Spec == Init /\ [][Next]_vars
```

This is standard TLA+ temporal formula syntax. `Init` is the initial predicate.
`[][Next]_vars` means: in every step of every behavior, either `Next` is enabled
and taken, or the variables are unchanged (a stuttering step). TLC checks that
every behavior satisfying `Spec` also satisfies the four safety properties.

The model checker works by breadth-first search over the reachable state space. For
a configuration with 2 actors, 2 resources, and 3 transaction IDs, the state space
is finite and small. For the bounding values used in the verification strategy
(Section 4.3 of the formal verification document: 3–5 objects, 3 certs, up to 10
evidence chain items), the state space stays under 10^9 states — checkable in
hours. TLC reports a counterexample trace if any reachable state violates a safety
property, or "No error has been found" if all states satisfy it.

The `ReplayAttack` action is the key test. Because its guard is identical to
`ConsumeLinear`'s guard, the model checker must evaluate all interleavings of
legitimate consumptions and replay attempts. In every such interleaving, once
`ConsumeLinear` fires for resource `r`, `objects[r].consumed` becomes `TRUE`. Any
subsequent `ReplayAttack` on the same `r` is blocked by its own guard
(`~objects[r].consumed`), so it cannot fire. `consumeCount[r]` therefore stays at
1. `NoDoubleConsume` holds in all reachable states.

---

## The Wallet TLA+ Models (Phase W1 + W3 + W8)

The replay prevention module covers the kernel-layer concurrency story for LINEAR
resources. Three additional TLA+ specs cover the wallet's tier-key custody and
spending semantics — properties that span multiple opcode invocations across
multiple browser tabs or sovereign-node sessions, which neither the per-opcode Lean
proofs nor the single-cell replay prevention spec capture.

Each spec follows the same shape as `ReplayPrevention.tla`: a state machine with
named actions, a set of safety invariants checked across all reachable states,
optional liveness obligations under fairness assumptions, and a `.cfg` file that
binds the specification's CONSTANTS to small finite sets so TLC's bounded search
terminates.

### KeyCustody.tla — multi-actor key lifecycle

The custody spec models the per-tier-key state machine across concurrent actors.
Each tier-N base key (N ∈ {1, 2}) carries a state from the set:

```
{ encrypted_at_rest, decrypted_in_engine, consumed, reconstructible_via_plexus }
```

The transitions are: `Unlock(tier, actor)` (encrypted → decrypted, requires the
actor's local auth factor and no other actor currently holding the key);
`Sign(tier, actor)` (decrypted → consumed, only the unlocking actor); `LockSession`
(decrypted → encrypted, only the unlocking actor); `EnrollRecovery` (sets the
opt-in flag); `BeginRecovery` (consumed → reconstructible, requires enrollment +
OTP/challenge factors); `CompleteRecovery` (reconstructible → encrypted).

The five safety invariants — `INV_NoConcurrentDecrypt`,
`INV_DecryptionConsistency`, `INV_NoResurrection`,
`INV_RecoveryRequiresEnrollment`, `INV_TierFactorRespected` — are what TLC verifies
across every reachable interleaving. The most distinctive of these is
`INV_NoConcurrentDecrypt`: at most one actor holds a given tier key decrypted at
any time. This is the property that catches a multi-tab race in the unlock flow:
two browser tabs both calling `Unlock(tier=1, ...)` simultaneously cannot both
succeed, because the second invocation's guard (`DecryptedBy[t] = NULL`) is no
longer satisfied once the first one transitions the state.

```tla
INV_NoConcurrentDecrypt ==
    \A t \in Tiers :
        KeyState[t] = "decrypted_in_engine" => DecryptedBy[t] \in Actors
```

For `Tiers = {1, 2}`, `Actors = {tab1, tab2}`, TLC explores 2,704 distinct states
across nine actions and four state symbols, and reports `Model checking completed.
No error has been found.` Two liveness obligations under fairness — every tier
key eventually unlocks; every consumed-and-enrolled tier key eventually recovers —
are also discharged.

### TierEscalation.tla — policy enforcement over a sequence of spends

The tier-escalation spec models the wallet's policy gate: classify the spend
amount, require the matching factor, enforce the Tier-3 cooldown. The state
variables are sparse on purpose — instead of tracking a sequence of spends (which
explodes the state space), the spec keeps the two most recent Tier-3 timestamps
(`LastTier3Spend`, `PrevTier3Spend`) and the most recent successful sign's tier
and factor (`LastSignedTier`, `LastSignedFactor`). This is sufficient to verify the
cooldown invariant for any consecutive pair (since spends are monotone in time)
and the factor-match invariant for the most recent spend (since the same guard
fires on every sign, every state transition is checked).

The five safety invariants — `INV_FactorMatchesTier`, `INV_Tier3CooldownRespected`,
`INV_MonotonicAuthFriction`, `INV_ClassifyRange`, `INV_LastTier3Ordered` — are
what TLC verifies. The cooldown invariant is the most visible:

```tla
INV_Tier3CooldownRespected ==
    \/ PrevTier3Spend = NEVER
    \/ LastTier3Spend = NEVER
    \/ /\ PrevTier3Spend /= NEVER
       /\ LastTier3Spend /= NEVER
       /\ LastTier3Spend - PrevTier3Spend >= Tier3Cooldown
```

For `MaxAmount = 3`, `MaxNow = 3`, `Tier3Cooldown = 2`, TLC explores 1,664 distinct
states — fast, because the spec keeps state minimal.

The v0.1 spec models the cooldown as a host-clock comparison; the v0.2 refinement
will replace this with a `nSequence` / `CheckSequenceVerify` lock encoded in the
budget cell's UTXO output, making the cooldown miner-enforced rather than
host-enforced. The TLA+ spec's safety invariants are abstract enough to apply to
both refinements.

### ReplayPrevention.tla extension — OP_SIGN per-leaf uniqueness + monotonic-index allocator

The replay prevention module described above was extended in Wave 8 to cover two
additional concurrency claims specific to the wallet:

- **OP_SIGN per-leaf uniqueness.** The BRC-42 fresh-key-per-tx discipline says
  every signing leaf is used exactly once. The extension adds a `SignNonces` set
  tracking every successful `SignLeaf(leaf, msg, actor, txId)` action, and the
  invariants `NoSignReplay` (no two records share a leaf) and `SignFreshness` (no
  two records share a (leaf, msg) pair). The adversarial action
  `SignReplayAttack(leaf, ...)` is enabled iff some prior record carries the
  same leaf — its guard is the negation of `SignLeaf`'s guard, so it cannot fire
  on a fresh leaf. The replay attempt is structurally identical to a legitimate
  sign attempt; what distinguishes them is the leaf's history.

- **BRC-42 monotonic-index allocator atomicity.** The `DerivationStateStore.next_index`
  host import allocates the next index for a (protocol, counterparty) context
  atomically. The extension adds `derivationIndex : Contexts → Nat` and
  `issuedLeaves : SET (context, index)`, and the atomic `AllocateIndex(c, a)`
  action that increments the index and records the issuance in a single
  transition. The invariants `INV_NoIndexReuse` (no two records share a (context,
  index) pair) and `INV_IndexInRange` (issued indices stay within the current
  allocator state) are what TLC verifies under concurrent allocation by multiple
  actors. If the implementation weren't atomic, TLC would find an interleaving
  where two `AllocateIndex` calls read the same `derivationIndex[c]` before
  either updates, both succeed, and both records would have the same index. TLC
  explores 254,016 distinct states and reports no violation.

The `PROP_IndexMonotonic` temporal property — that the allocator index for any
context never decreases — is the action-level analogue, lifted via
`[][INV_IndexMonotonic]_vars`.

---

## Connecting the Layers

The proofs across Lean and TLA+ address different aspects of the kernel and the
wallet's signing semantics. Each layer catches a class of regression the others
cannot.

**The Lean proofs** establish properties of the abstract execution model. K1's
sub-theorems hold for any single step of the executor: if linearity enforcement is
on and the top-of-stack cell is LINEAR, a duplicate or discard operation returns
an error. K4's per-opcode inversion lemmas walk every match arm and if-branch of
each opcode definition, ensuring every reachable error path corresponds to an
enumerated structural condition. K11–K13 specialise this to the wallet's signing
opcodes, with K11b's cryptographic correctness conditional on the axiomatised
ECDSA oracle and the empirical bridge through the bsvz differential test.

**The TLA+ models** check properties of multi-actor protocols over many steps. The
replay prevention spec verifies that no LINEAR resource can be consumed more than
once across all reachable behaviors, including races and adversarial replays. The
KeyCustody spec verifies that no two browser tabs can decrypt the same tier key
concurrently, that a consumed key cannot resurrect without going through Plexus
recovery, and that recovery requires prior enrollment. The TierEscalation spec
verifies that the wallet's policy gate (factor matching + Tier-3 cooldown) holds
across every reachable sequence of spends. The ReplayPrevention extension verifies
that the BRC-42 monotonic-index allocator preserves uniqueness under concurrent
allocation.

**The Zig fuzz and differential tests** bridge the abstract proofs to the actual
binary. The `plexus_atomic_fuzz.zig` harness runs 50,000 adversarial iterations
across the wallet opcodes and asserts byte-for-byte stack preservation on every
error — which is K4's failure-atomicity property tested against the actual Zig
binary, not the Lean model. The `sign_conformance.zig` differential test compares
`host_sign`'s output against the `bsvz` audited secp256k1 implementation, which is
what makes K11b's axiomatised ECDSA assumption tractable: the axiom holds for the
binary because the binary's signing primitive matches an independent implementation
across millions of test vectors.

**The WASM hash anchor** ties the deployed binary to the source the proofs and
tests reference. Boot step 7 verifies `SHA-256(loaded_wasm) == anchored_hash`
against an on-chain `OP_RETURN` output. Without this layer, every other layer
becomes a claim about a different binary than the one running in the user's
browser.

The four layers — Lean per-opcode + TLA+ multi-step + Zig fuzz + WASM anchor —
are not redundant. Each catches a class of regression none of the others can. K4
is the clearest example: a regression in opcode shape breaks the Lean inversion
lemma; a regression in opcode implementation that the model didn't capture is
caught by the Zig fuzz; a swapped binary is caught only by the hash anchor. Lose
any one and a class of regression goes undetected.

---

## Limitations

The following gaps are explicit. They correspond to the assumption register in
Section 10 of the formal verification strategy.

- **Implementation conformance is not proved.** The Lean proofs hold for the
  abstract 2-PDA model. They do not establish that the Zig source code implements
  that model correctly, or that the compiled WASM binary matches the Zig source.
  No verified compiler for Zig or for Zig-to-WASM exists. Conformance is
  established by testing, fuzzing, differential test vectors, and structured code
  review — empirical evidence, not machine-checked proof. This is the weakest link
  in the chain.

- **TLA+ model checking is not exhaustive over all state spaces.** TLC performs
  exhaustive search over a bounded configuration. Properties that hold for 2 actors
  and 2 resources may not hold at scale if the model's bounds are too tight to
  expose a violation. The current bounds (3–5 objects, 3 certs, up to 10 evidence
  chain items) are calibrated to cover all structural interleavings while keeping
  the state space tractable. States outside this envelope are not verified by TLC.
  Symbolic model checking with Apalache can extend coverage, but completeness is
  not claimed.

- **Cryptographic assumptions are axiomatized, not proved.** The Lean proofs
  treat SHA-256 and ECDSA as ideal functions via axioms
  (`sha256_collision_free`, `ecdsa_existential_unforgeability`). The security of
  the real primitives rests on computational assumptions (EUF-CMA, collision
  resistance) that are not representable in Lean's type theory, which has no notion
  of polynomial-time adversaries. The idealized axioms are stronger than the
  computational definitions; the proofs hold conditionally on the real primitives
  behaving as their idealizations. This is standard practice in mechanized
  verification of cryptographic protocols.

- **Host import correctness is not verified.** The WASM binary imports
  `host_checksig`, `host_sha256`, and related functions from the TypeScript host
  runtime. The Lean proofs abstract these imports. If a host import is implemented
  incorrectly — for example, if `host_checksig` returns `true` for an invalid
  signature — then the authorization soundness proofs (K2) hold in the model but
  not in execution. Strengthening this layer requires a formally verified crypto
  library at the host boundary.

- **Side channels are out of scope.** The proofs address functional correctness:
  the step function returns the correct result for each input. Timing attacks,
  cache side channels, and power analysis are not modeled. Constant-time
  implementation of cryptographic operations is a separate engineering concern
  outside the scope of this proof layer.

- **Hardware correctness is assumed.** The proofs assume the CPU and operating
  system execute WASM instructions as specified. Hardware vulnerabilities (speculative
  execution side channels, memory corruption attacks) can violate any software
  property regardless of proof coverage. This assumption is shared by all software
  formal verification work.

- **BSV chain availability is assumed for K6 external anchoring.** The TLA+
  model checks that the prevStateHash chain is structurally consistent. The
  additional claim — that tampering is detectable by a third party with SPV access
  — depends on the BSV chain remaining available. Local hash-chain verification
  does not depend on chain availability, but the external detectability guarantee
  does. Tests that depend on external anchoring (3.3.1, P2.1, P3.1) carry this
  assumption explicitly.

- **Social engineering is out of scope.** The proofs prevent technical bypasses.
  An actor who voluntarily discloses their private key, or who is coerced into
  authorizing a consumption they would not otherwise authorize, is not within the
  model's threat scope. Non-repudiation holds only against technical forgery.

- **Application-layer routing is not enforced by the kernel.** Several compliance
  mappings (Section 6 of the formal verification strategy — tests 2.1, 2.3, 3.1,
  5.1) depend on the application routing all operations through the kernel's
  enforcement substrate. The kernel cannot prevent an application from writing
  directly to a backing store without creating a cell or advancing the hash chain.
  The compliance contribution in those rows is conditional on correct
  application-layer behavior.

- **The K1c uniqueness argument has a structural scope.** In the current model, the
  step function is proved to preserve the PDA unchanged on successful steps. This
  holds for the proof's model of the executor. The full executor implementation
  (including stack-mutating operations) is modeled in more detail in K1a and K1b,
  where the error-return path forecloses duplication. K1c is best read as: given
  a starting state where the count is at most 1, a single step that succeeds does
  not increase it. The full inductive argument over all reachable states requires
  combining K1a, K1b, and K1c across the complete opcode semantics.

---

## What Chapter 13 Establishes

After this chapter, the reader has seen:

- The structure of the verification architecture and where each tool fits — Lean
  per-opcode soundness, TLA+ multi-step concurrency, Zig fuzz/differential, WASM
  hash anchor.
- The complete K1 proof in Lean 4, including a line-by-line trace of the
  K1a executor rejection proof, with each tactic explained.
- The structure of the TLA+ replay prevention module, including the adversary model
  and how TLC checks the `NoDoubleConsume` property against all reachable states.
- The wallet TLA+ models — `KeyCustody.tla` (multi-actor key lifecycle),
  `TierEscalation.tla` (policy enforcement), and the `ReplayPrevention.tla`
  extension (OP_SIGN per-leaf uniqueness + BRC-42 monotonic-index allocator).
- An explicit register of what these proofs do not establish.

Chapter 14 (the Verifier Sidecar) describes the deployment-time mechanism that
presents attestations of the binary's integrity to external parties, completing
boot step 8. The sidecar's function is to make the abstract proofs described here
operationally relevant: it anchors the WASM binary's SHA-256 hash on-chain and
provides the external verification capability that turns the Layer 2 proofs into a
claim about a specific deployed binary (subject to the conformance gap identified
in the Limitations above).
