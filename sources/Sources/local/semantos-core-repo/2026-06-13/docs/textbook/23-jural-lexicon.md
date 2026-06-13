---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/23-jural-lexicon.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.651985+00:00
---

# Chapter 23 — Jural: the canonical lexicon

Part VII covers domain lexicons: the mechanism by which Semantos extends its
substrate vocabulary to a new subject area without touching the substrate itself.
The jural lexicon is the first and most fundamental. Every other lexicon in the
set — CDM, circuit, property management, risk assessment, bills of lading,
control systems — borrows the same registration pattern demonstrated here.

---

## Economic problem

Consider what a governance layer must minimally be able to say about any action in
a distributed system. An action either asserts something about the world
(a statement of fact), requires a party to do something (a duty), permits a
party to do something they would otherwise be unable to do (a licence), bars a
party from doing something (a ban), changes what norms apply going forward
(a restructuring act), depends on a precondition being true (a guard), or moves
a resource from one party to another (a handoff). That is seven concepts.

The economic problem is: if the substrate does not distinguish these seven, it
cannot enforce their differences. A system that conflates an obligation with a
permission cannot detect an authorisation violation at compile time. A system
that conflates a power with a declaration cannot enforce that only authorised
parties restructure norms. The costs accumulate silently: audit trails that do
not distinguish fact-assertions from duty-impositions, authorisation checks that
amount to naming conventions, compliance postures that rest on documentation
rather than structure.

The jural lexicon exists to eliminate those costs structurally. Once a cell
carries one of the seven jural categories as its type, the cell engine, the SIR
layer, and the formal proofs all treat that category as load-bearing. The
substrate can enforce — not just document — which actions are permissible, which
are obligatory, and which are exercises of power over the normative order itself.

The seven categories also provide the vocabulary for every other domain lexicon.
CDM derivation lifecycles, property management lease transitions, SCADA interlock
policies — all resolve to combinations of these seven. It is the canonical
foundation from which all others are built.

---

## Hohfeldian decomposition

### Hohfeld's original analysis

Wesley Newcomb Hohfeld, writing in 1913, observed that lawyers used the word
"right" to mean at least four distinct things. He separated them into eight
fundamental jural relations arranged in two tables of correlatives and opposites.

The four "rights" side:

| Jural relation | Correlative | Opposite |
|---|---|---|
| right (claim) | duty | no-right |
| privilege | no-right | duty |
| power | liability | disability |
| immunity | disability | liability |

The structural insight is that these eight categories are exhaustive: any
statement about what one party may, must, or cannot do with respect to another
party, or about who may alter the normative landscape, resolves to one of the
eight. The table of correlatives tells you what the other party holds when you
hold a given category; the table of opposites tells you what the negation of a
category is.

Hohfeld's analysis is the theoretical source for the jural lexicon. The
definitions above — the eight categories, their correlatives, their opposites —
are the foundation. The seven implemented categories in the SIR layer are the
computational adaptation of that foundation.

### From eight Hohfeldian relations to seven jural categories

The substrate uses seven jural categories, not eight. The reduction has a
precise rationale.

The Hohfeldian eight are: right (claim-right) and its correlative duty; privilege
(liberty) and its correlative no-right; power and its correlative liability;
immunity and its correlative disability. In governance computation, claims and
duties always appear together as two sides of a single relation — the substrate
never records just one side of a bilateral normative link without the other. A
right without a corresponding duty is unenforceable; a duty without a
corresponding right is a restriction with no beneficiary. Modelling them as
separate primitive categories in the lexicon would produce duplicate
representations of the same semantic content.

Similarly, liability and disability are derivative: liability is the condition of
being subject to having one's normative position altered by another's exercise of
power; disability is the absence of power. Neither requires a first-class
category in the computational vocabulary, because both are expressed structurally
— by the presence or absence of a power cell and by the governance-domain context
under which it was minted.

The resulting seven-category set preserves the full expressive range of Hohfeld's
analysis while eliminating redundancy that would complicate structural enforcement:

| Jural category | Hohfeldian source | What it asserts |
|---|---|---|
| declaration | right (claim) + duty fused | A fact-assertion about the world, carrying the normative weight of both the claim and the correlative duty to acknowledge it |
| obligation | duty (as a first-class directive) | A party is required to perform an act; the correlative claim-right is implied |
| permission | privilege (liberty) | A party has licence to act in a way they would otherwise be barred from acting |
| prohibition | duty-not (opposite of privilege) | A party is barred from an act; the correlative no-right is implied |
| power | power | A party has the capacity to alter the normative situation of another |
| condition | precondition guard | A predicate that must hold for a related act to take effect; models the gateway logic implicit in conditional Hohfeldian relations |
| transfer | exercise of power over a resource | Movement of a resource, right, or duty from one party to another; the most common materialisation of a power exercise |

The condition category has no direct single-word Hohfeldian counterpart; it is
the computational encoding of the conditionality that Hohfeld described through
qualifications on individual relations ("A has a right to X if P") — here made
explicit and first-class so the SIR layer can enforce preconditions structurally
rather than embedding them silently in predicates.

### Which categories appear in which domains

In practice, different domains draw on different subsets of the seven.
Document-centric workflows (contracts, leases, insurance policies) use
declaration, obligation, permission, prohibition, and transfer as their core
five, with condition as a guard and power only at lifecycle transition points.
Control systems are almost entirely obligation and prohibition, with condition
encoding interlock logic. Financial derivatives use power and transfer heavily,
with condition encoding event triggers. Identity and capability management uses
declaration and permission primarily, with transfer for delegation and power
for governance acts. The jural lexicon does not prescribe which categories a
domain must use; it defines the full vocabulary so any domain draws on exactly
the subset it needs.

---

## The Lean lexicon

### Registration contract

Every lexicon satisfies a four-step contract against the `Lexicon` typeclass in
`Semantos.Substrate.Lexicon`: (1) define a category enumeration as a Lean
`inductive` with `DecidableEq` and `BEq` derivations; (2) provide a `header`
function mapping each category to a canonical uppercase string; (3) prove
`headerInjective`; (4) register the `Lexicon` instance. No per-lexicon
re-proof of the substrate theorems — M1–M4, D1–D3, `renderCard_*` — is required;
those are proved once against the typeclass interface and specialise automatically.
The jural lexicon satisfies this contract in 51 lines of Lean 4.

### Full annotated file

The file is `proofs/lean/Semantos/Lexicons/Jural.lean`. Every line is
reproduced below with inline annotation.

```lean
-- Semantos Plane — Jural Lexicon
--
-- The legal/Hohfeldian discourse vocabulary: the seven categories that
-- classify jural relations between parties. First concrete instance of
-- `Semantos.Substrate.Lexicon`.
```

The module-level comment identifies this as the jural vocabulary and as the
first concrete instance of the `Lexicon` typeclass. "First" here means first
in the historical order of development; the other seven lexicons follow the
same pattern. The phrase "Hohfeldian discourse vocabulary" connects the
implementation to the theoretical source without embedding Hohfeld's original
eight-category system directly — the implementation uses the seven adapted
categories.

```lean
--
-- Proof obligation per lexicon:
--   1. Define the category enum (inductive).
--   2. Provide the header function.
--   3. Prove header injectivity.
--   4. Register the `Lexicon` instance.
--
-- Once registered, the substrate theorems (M1-M4, D1-D3, renderCard_*)
-- apply at `Patch JuralCategory` by specialisation — no per-lexicon
-- re-proof of those invariants is required.
```

This comment block is the registration contract stated verbatim in the source.
The reference to `Patch JuralCategory` is the type of a patch over a cell
whose category is `JuralCategory`. The substrate theorems are proved for any
type `α` satisfying `Lexicon α`; `JuralCategory` is one such `α`. The
specialisation at `Patch JuralCategory` is purely mechanical — Lean's instance
resolution handles it.

```lean
import Semantos.Substrate.Lexicon
```

The only import. The `Semantos.Substrate.Lexicon` module defines the `Lexicon`
typeclass, the `Patch` type, and the substrate theorems. The jural lexicon has
no dependency on any other lexicon and no dependency on any adapter or
application code. Dependency isolation at this boundary is structural: a lexicon
that imports application code would be unverifiable independently of the
application.

```lean
namespace Semantos.Lexicons

open Semantos.Substrate
```

The lexicon lives in the `Semantos.Lexicons` namespace. Opening `Semantos.Substrate`
makes the `Lexicon` typeclass and related identifiers available without
qualification. All eight domain lexicons share this namespace structure; they are
peers.

```lean
inductive JuralCategory where
  | declaration
  | obligation
  | permission
  | prohibition
  | power
  | condition
  | transfer
  deriving Repr, DecidableEq, BEq
```

The `JuralCategory` type is a closed enumeration with seven constructors. Lean's
`inductive` keyword produces a sum type; each constructor is a distinct value
with no fields. The `deriving` clause produces three instances automatically:

- `Repr` for pretty-printing in interactive proofs and the Lean infoview.
- `DecidableEq` for decidable equality — the substrate's invariant proofs
  require the ability to decide `c₁ = c₂` for any two categories at compile
  time rather than at runtime.
- `BEq` for boolean equality — used by the rendering layer when pattern-matching
  headers against known values.

The order of constructors — declaration, obligation, permission, prohibition,
power, condition, transfer — is conventional, not semantic. No numeric encoding
is derived from this order in the current implementation.

```lean
def juralHeader : JuralCategory → String
  | .declaration => "DECLARATION"
  | .obligation  => "OBLIGATION"
  | .permission  => "PERMISSION"
  | .prohibition => "PROHIBITION"
  | .power       => "POWER"
  | .condition   => "CONDITION"
  | .transfer    => "TRANSFER"
```

The `juralHeader` function maps each category to an uppercase ASCII string.
These strings are what the substrate writes into the header field of a packed
cell when the cell's lexicon is jural. Three properties of these strings matter:

First, they are uppercase throughout. The header field in a packed cell is
case-sensitive; uppercase is the convention for the entire substrate. A cell
whose header field reads `"permission"` (lowercase) would not be recognised as
a jural-permission cell by the runtime.

Second, each string is distinct. This is necessary for `headerInjective` to be
provable; the proof below exploits exactly this distinctness.

Third, the strings are identical to the constructor names in uppercase. This
identity is a choice, not a requirement. The header strings are external-facing
(they appear on the wire); the constructor names are internal-facing (they
appear in Lean code). Keeping them aligned reduces the cognitive cost of
reading packed cells.

```lean
theorem juralHeader_injective : ∀ c₁ c₂ : JuralCategory,
    juralHeader c₁ = juralHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [juralHeader]
```

The injectivity theorem states: if two categories produce the same header string,
they are the same category. The proof proceeds by exhaustive case analysis.

`intro c₁ c₂ h` introduces the two categories and the hypothesis that their
headers are equal.

`cases c₁ <;> cases c₂` generates all 49 cases (7 × 7) by splitting on each
possible value of `c₁` and, for each, on each possible value of `c₂`.

`simp_all [juralHeader]` discharges all 49 cases simultaneously. For the seven
diagonal cases (where `c₁ = c₂`), the goal is trivially `c = c`, which `rfl`
handles. For the 42 off-diagonal cases, the hypothesis `h` reduces — after
unfolding `juralHeader` — to a statement like `"DECLARATION" = "OBLIGATION"`,
which is false by string literal distinctness, and `simp_all` closes the goal
via contradiction.

The proof is seven lines including the theorem statement. The brevity is
deliberate: the substrate's design ensures that the injectivity proof for any
well-formed lexicon is always this short. A lexicon that required a longer
injectivity proof would have a header function that was either non-injective or
defined over a type with more structure than an enumeration, which would be a
design error.

```lean
instance : Lexicon JuralCategory where
  header          := juralHeader
  header_injective := juralHeader_injective

end Semantos.Lexicons
```

The final four lines register the instance and close the namespace. After this
`instance` declaration, `JuralCategory` satisfies `Lexicon JuralCategory`, and
the substrate theorems M1–M4 and D1–D3 specialise automatically to `Patch JuralCategory`.

From this point, any code or proof in the substrate that is polymorphic over
`Lexicon α` can be instantiated at `α = JuralCategory` without any further
proof work. The lexicon registration is the entire extension surface.

### What the substrate theorems provide for free

Once `Lexicon JuralCategory` is registered, the following hold without
per-lexicon proof:

**M1 (monotone update):** A patch that respects linearity leaves the cell's
category unchanged — a declaration cell cannot be patched into an obligation
cell without a power exercise.

**M2 (category conservation):** The category of a cell is read-only after
packing (see K7).

**M3 (header round-trip):** Packing then unpacking a cell returns the same
category — the minimal correctness property for the serialisation layer.

**M4 (patch composition):** Two category-preserving patches composed also
preserve category — multi-step workflows cannot silently migrate a cell's
category through intermediate states.

**D1, D2, D3 (domain isolation variants):** Patches minted under one governance
domain cannot alter the category of cells minted under a different governance
domain; the domain flag partitions the authority surface structurally.

---

## 30-minute demo

This demo requires a running substrate kernel with the Lean proof layer loaded
and the jural lexicon registered. The demo is a read-eval-print loop over the
SIR compiler; no on-chain transaction is required. The entire session fits in the
pre-step-8 feasibility regime (steps 1–7 of the boot sequence are sufficient;
no BRC-100 verification is required for local proof execution).

### Setup

```text
$ semantos repl --lexicon jural
Semantos REPL v0.5 — jural lexicon loaded
JuralCategory instances: declaration, obligation, permission, prohibition,
                         power, condition, transfer
Type :help for commands. ^D to exit.
jural>
```

The REPL loads the `JuralCategory` type and exposes the SIR compiler at the
jural lexicon. Categories are available by their lowercase names as REPL
identifiers.

### Step 1 — inspect the header mapping

```text
jural> :headers
declaration  => DECLARATION
obligation   => OBLIGATION
permission   => PERMISSION
prohibition  => PROHIBITION
power        => POWER
condition    => CONDITION
transfer     => TRANSFER
```

The `:headers` command calls `juralHeader` for each constructor and prints the
mapping. The output is the exact content of the `juralHeader` function in
`Jural.lean`.

### Step 2 — verify injectivity

```text
jural> :check-injective
juralHeader_injective: ✓ (proven, 7×7 case matrix, all 42 off-diagonal cases
                         closed by contradiction)
```

The `:check-injective` command re-runs the proof kernel against
`juralHeader_injective` and reports the result. This is a check against the
compiled proof term, not a re-execution of the tactic proof; it completes in
under one millisecond.

### Step 3 — encode a Hohfeldian relation as a SIR program

The scenario: a property manager (hat: `pm-alice`) has the power to grant
a tenant (hat: `tenant-bob`) permission to sublet their unit. The manager
exercises that power. The result is a new permission cell held by the tenant.

This scenario involves two jural categories: first a power (the manager's
capacity to alter the tenant's normative position), then a permission (the
result of exercising that power). The SIR program encodes the power exercise;
the resulting permission is the output cell.

```text
jural> :encode
(sir-program
  :category power
  :actor    "pm-alice"
  :target   "tenant-bob"
  :subject  "unit-42-sublet"
  :produces
    (sir-cell
      :category   permission
      :holder     "tenant-bob"
      :subject    "unit-42-sublet"
      :condition  (sir-cell
                    :category  condition
                    :predicate "lease-active AND rent-current"
                    :expires   "2027-06-30T00:00:00Z"))
  :governance
    (governance-context
      :trust-class       "estate"
      :proof-requirement "brc-100-signed"
      :execution-authority "pm-alice"
      :linearity         "LINEAR"))
```

Walk through each field:

`:category power` — the outer SIR node is a power exercise. The actor is
asserting their capacity to alter the normative situation of the target. This
maps to the Hohfeldian power relation: pm-alice holds a power over tenant-bob
with respect to the sublet permission.

`:actor "pm-alice"` — the hat exercising the power. In the running system, this
would be a BRC-52 cert reference; in the demo REPL, a string label suffices.

`:target "tenant-bob"` — the party whose normative position is being altered.
Tenant-bob holds a liability (in the Hohfeldian sense) corresponding to
pm-alice's power; after the exercise, that liability resolves into the
permission below.

`:subject "unit-42-sublet"` — the object of the normative relation. What the
power is about.

`:produces (sir-cell :category permission ...)` — the power exercise produces
an output cell of category permission. This is the computational encoding of
the Hohfeldian correlative structure: a power exercise produces a change in the
target's normative position, here from "no permission to sublet" to "permission
to sublet".

`:holder "tenant-bob"` — the cell is held by the tenant. In the substrate, this
maps to the owner field of the packed cell.

`:condition (sir-cell :category condition ...)` — the permission is conditional.
It applies only when the lease is active and rent is current. This is the
jural condition category in use: a predicate guard that must hold for the
permission to be operative. The condition cell is a child of the permission cell
in the cell hierarchy.

`:expires "2027-06-30T00:00:00Z"` — the condition cell carries a temporal
bound. When this timestamp passes, the condition is no longer satisfiable and
the permission lapses. This is encoded in the cell's temporal constraint field
in the governance context, not in the condition predicate itself.

`:governance` — the governance context specifies:

- `trust-class "estate"`: the governance domain is of the estate kind (a
  property-management governance scope, per the five named kinds in
  `docs/SEMANTIC-IR-ARCHITECTURE.md §10`).
- `proof-requirement "brc-100-signed"`: the cell must be signed with a
  BRC-100 envelope by pm-alice's key to be accepted by the substrate.
- `execution-authority "pm-alice"`: only pm-alice can author this cell.
- `linearity "LINEAR"`: the power cell is LINEAR — it may be exercised
  exactly once. Exercising the power consumes the cell; to exercise the power
  again, a new power cell must be minted (which itself requires an upstream
  power over pm-alice's power).

### Step 4 — compile to packed cells and inspect the headers

```text
jural> :compile
  [power cell]    header: POWER       linearity: LINEAR (0)
  [permission]    header: PERMISSION  linearity: RELEVANT (2)
  [condition]     header: CONDITION   linearity: UNRESTRICTED (3)
Packed cells: 3   Total bytes: 3072   Header round-trip: ✓ (M3)
Injectivity: ✓ (juralHeader_injective)
```

The three cells are packed in dependency order: condition first, then
permission, then power. The permission cell is `RELEVANT` (at-least-once use)
— a permission is checked many times, not consumed. The power cell is `LINEAR`
— exercising it is a one-time normative act. The condition cell is
`UNRESTRICTED` — a predicate evaluated without semantic consequence on each
evaluation.

### Step 5 — verify injectivity at the packed level

```text
jural> :verify-headers
POWER       -> "POWER"       -> POWER       ✓
PERMISSION  -> "PERMISSION"  -> PERMISSION  ✓
CONDITION   -> "CONDITION"   -> CONDITION   ✓
juralHeader_injective holds for all three cells.
```

The session has loaded the jural lexicon, verified injectivity, encoded a
two-category Hohfeldian scenario as a SIR program, compiled it to three packed
cells, and confirmed the header round-trip for each.

---

## Extensions next

The jural lexicon is complete as a registration: all seven categories are defined,
the header function is injective, and the instance is registered. Extensions do
not modify the lexicon. They operate at one of three other levels.

### Category-combination rules

The jural lexicon defines the vocabulary but not the grammar. A `JuralGrammar`
extension could state, for example, that a transfer cell must have a power or
obligation parent, and that a condition cell may appear as a child of any
category but never as a root. Writing this requires a `JuralGrammar` type, a
validation function `checkGrammar : PatchTree JuralCategory → Bool`, and a
decidability proof. The D1–D3 theorems then provide domain-isolation guarantees
on the grammar check automatically.

### Domain-specific sublexicons

A sublexicon restricts the seven categories to a named subset and adds
refinement fields. For example, a contract sublexicon might restrict to
`{obligation, permission, condition, transfer}` and require a contract-period
field on every cell. The Lean encoding wraps `JuralCategory` in a structure
carrying the additional field, with a projection proof for soundness. Chapter 25
demonstrates this pattern: the property-management lexicon adds domain-specific
categories on top of the jural vocabulary.

### New lexicons over the jural categories

The most common extension is a new domain lexicon that maps domain concepts to
jural categories. Chapter 24 (CDM): a novation is `power + transfer`; a
confirmation is `declaration`. The CDM lexicon defines CDM-specific category
names and provides `toJural : CDMCategory → JuralCategory`, so jural-layer
enforcement applies to CDM events without modifying the jural lexicon. The
pattern: define the domain enumeration; provide `toJural`; prove it well-founded;
register `Lexicon CDMCategory` with `header := juralHeader ∘ toJural`. The
jural lexicon stays stable; domain extension is unlimited.

---

## Worked program: encoding one Hohfeldian relation as a SIR program

The worked program below encodes the obligation relation in full SIR syntax.
The scenario: a property manager's governance domain obliges a maintenance
contractor to respond to a service request within 24 hours. This is a pure
obligation: the contractor holds a duty; the manager holds the correlative
claim-right. No power exercise is involved — the obligation exists by virtue
of the contractual governance domain, not by a real-time act of norm-creation.

```text
(sir-program
  :id       "obligation-maintenance-response-24h"
  :category obligation
  :actor    "governance-domain:estate-42"
  :subject  "maintenance-request:req-2026-04-26-001"
  :target   "contractor-hat:maint-corp-primary"
  :content
    (obligation-body
      :act        "respond-to-request"
      :deadline   "PT24H"
      :from-event "request-created")
  :governance
    (governance-context
      :trust-class         "estate"
      :proof-requirement   "brc-100-signed"
      :execution-authority "governance-domain:estate-42"
      :linearity           "RELEVANT"
      :allowed-emit-ops    ["OP_CHECKOBLIGATION" "OP_CHECKDEADLINE"]))
```

Key points of this encoding:

`:category obligation` — the SIR node is an obligation. The substrate will
enforce that only actors with `execution-authority` in the estate governance
domain can author obligation cells of this type.

`:actor "governance-domain:estate-42"` — the obligation is not authored by a
human hat but by the governance domain itself, acting through its policy engine.
This is the standard pattern for standing obligations that exist by virtue of a
contractual or regulatory regime rather than by a moment-in-time act.

`:target "contractor-hat:maint-corp-primary"` — the obligated party is a hat
(the maintenance contractor's primary signing hat). The obligation is addressed
to the hat, not to a bare public key, because hat identity is what the
governance-domain enforcement layer tracks.

`:deadline "PT24H"` and `:from-event "request-created"` — ISO 8601 duration
and the triggering event. The condition cell that guards this obligation is
derived from these two fields by the SIR compiler's temporal constraint lowering
pass. The deadline is encoded as a `CONDITION` cell with a `timeConstraint`
predicate of the form `now < event_time + PT24H`.

`:linearity "RELEVANT"` — the obligation cell is RELEVANT (at-least-once).
The cell must be consulted at least once before the workflow closes; it cannot
be silently discarded. An obligation that is never checked is a compliance gap;
the RELEVANT linearity class surfaces it structurally.

`:allowed-emit-ops ["OP_CHECKOBLIGATION" "OP_CHECKDEADLINE"]` — the governance
context restricts which opcodes may be emitted when this SIR node is lowered.
Only two opcode kinds are permitted: the obligation-check opcode and the deadline-
check opcode. Any other opcode appearing in the lowered OIR for this node would
be a structural violation caught at the SIR → OIR lowering boundary before the
cell reaches the cell engine.

When this SIR program is compiled and the obligation cell is packed, its header
field reads `OBLIGATION`. Any runtime component inspecting the cell identifies
it as an obligation immediately, without consulting the cell's content fields.
The jural lexicon's header function is the mechanism that makes this identification
reliable: `juralHeader_injective` guarantees that no other jural category produces
the header string `"OBLIGATION"`.

This is the governance-enforcement value of the jural lexicon in one sentence:
the substrate can distinguish an obligation from a permission, a power from a
declaration, a transfer from a condition, not by documentation or convention but
by the provable injectivity of the header mapping that the lexicon registration
places under formal proof.
