---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/25-property-management-lexicon.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.648431+00:00
---

# Property management — leases, maintenance, dispatch envelopes

Property management is a domain where multiple principals — owner, rental tenant, property manager, tradie, regulator — hold overlapping claims over the same physical asset across time. The substrate's Hohfeldian vocabulary is designed for this kind of multi-party, multi-period entitlement landscape. This chapter walks the property-management lexicon from first principles: the economic problem it solves, its decomposition into the seven jural categories, the Lean code that registers the vocabulary, and a 30-minute runnable demo. The chapter closes by retelling the leaky-tap scenario from Whitepaper v3 §4 from the lexicon's perspective, mapping each step to a jural category and tracing how the dispatch envelope routes the work.

---

## Economic problem

A residential property under management is a bundle of time-indexed rights held by at least four principals simultaneously:

- The owner holds the freehold title and the right to receive rent, but during an active lease surrenders the right to exclusive occupation.
- The rental tenant holds the right to exclusive occupation for the lease term, but carries obligations to pay rent, maintain condition, and vacate at term-end.
- The property manager holds delegated power to act on behalf of the owner — triaging maintenance, issuing notices, disbursing rent — but only within the scope of the management agreement.
- The tradie (when dispatched) holds a permission to enter the property for a bounded period and purpose; that permission is created by the dispatch event and expires on completion.

The economic problem is that every event in the property lifecycle — lease execution, rent receipt, maintenance dispatch, inspection publication, violation notice, renewal, termination — changes the entitlement set of one or more of these principals. Most of these changes are conditional on prior events (a renewal cannot happen before the lease is active; a termination notice starts a clock that conditions the tenant's obligation to vacate). A substrate that cannot distinguish a rent-payment event from a violation-notice event from an inspection-report event cannot correctly gate those downstream conditions. Each event type must carry a distinct category label so the policy evaluator and the cell engine can enforce the right downstream clock.

That is the granularity rationale in the lexicon's header comment: residential-tenancy law treats these events differently, so the curator needs distinct cards per category. The seven categories in the property-management lexicon are not an exhaustive ontology of property law; they are the minimum vocabulary sufficient to represent every operational event that the substrate needs to classify.

The dispatch problem adds a second layer. The maintenance workflow crosses an organisational boundary: the property manager's record of the request, the owner's approval, and the tradie's completion are three distinct bodies of evidence held by three parties with different visibility requirements. Without a shared semantic object with per-hat visibility, this workflow degenerates into point-to-point integration with all the usual failure modes — duplicate records, reconciliation debt, contested state. The dispatch envelope is the substrate's answer to that problem.

---

## Hohfeldian decomposition

Hohfeld's 1913 analysis of jural relations identified four fundamental pairs: right/duty, privilege/no-right, power/liability, immunity/disability. The substrate's seven-category set adapts and extends that analysis for computational governance. Not all seven categories appear with equal frequency in property operations; the distribution is informative.

**Obligation** — the most common category. Rent payment, statutory repair duty, and notice service all impose a hat-bound duty with a deadline. An obligation cell carries a deadline constraint and a responsible-hat binding; only the bound hat can satisfy (patch to completion) the obligation.

**Declaration** — fact-recording acts that impose no duty and grant no permission. An inspection report, a tradie's completion note, a condition photograph — all are declarations. Declarations are RELEVANT cells: they enter the evidence chain and must be used at least once, but are not consumed by a single act.

**Power** — acts that create or modify the entitlements of another principal. Lease execution creates the tenant's right to occupy and the landlord's duty to allow quiet enjoyment. Owner approval of a cost estimate creates the PM's authority to dispatch. Powers are hat-scoped; the Verifier Sidecar confirms that the signing hat holds the capability to exercise the power before the cell is accepted.

**Transfer** — value movement between parties. Rent disbursement from trust to owner, invoice settlement between PM and tradie. The substrate routes transfers through the Metered Flow Protocol (MFP) when off-chain settlement is required; the MFP state machine advances by one tick per payment event.

**Permission** — time-bounded grants of access or action. The entry-access grant to the tradie authorises entry for the scope of the dispatched work; it expires on completion. Permissions are AFFINE at the policy layer — consumed by the access event and not re-exercisable.

**Prohibition** — constraints on action. The quiet-enjoyment clause prohibits unreasonable disturbance by the PM; a privacy requirement prohibits distribution of inspection photographs beyond approved principals. Prohibitions bind a specific hat and action category; the policy evaluator rejects violating patches.

**Condition** — events that gate downstream action without themselves being the rights or duties they enable. A lease-expiry date triggers the renewal-or-termination window without itself constituting either. An approval threshold gates maintenance dispatch: below the threshold, the condition evaluates true and dispatch proceeds automatically; above it, a power patch from the owner is required.

### Summary: category distribution

| Category | Property-management event |
|---|---|
| obligation | Rent payment, statutory repair, notice service |
| declaration | Inspection report, completion note, condition record |
| power | Lease execution, renewal, cost approval, dispatch authority |
| transfer | Rent disbursement, invoice settlement, bond lodgement |
| permission | Tradie entry access, PM inspection access |
| prohibition | Quiet enjoyment, privacy constraint on reports |
| condition | Lease-expiry trigger, approval-threshold gate, cure period |

The seven categories are jointly exhaustive over the domain's operational events. Every event the property-management vertical needs to classify maps to exactly one of the seven; no event requires a new category.

---

## The Lean lexicon

The property-management lexicon is registered in `proofs/lean/Semantos/Lexicons/PropertyManagement.lean`. The file is 54 lines. Its structure follows the four-step proof obligation that every lexicon must satisfy, established by the Jural lexicon as the canonical instance.

### The four-step obligation

The `Lexicon` typeclass requires:

1. An `inductive` type enumerating the categories.
2. A `header` function mapping each category to a canonical string label.
3. A proof that `header` is injective — distinct categories produce distinct strings.
4. A `Lexicon` instance registration combining the function and the proof.

Once registered, the substrate theorems M1–M4 and D1–D3 apply to `Patch PropertyManagementCategory` by typeclass specialisation. No per-lexicon re-proof of those invariants is required. This is the leverage point: paying the registration cost once gives the full substrate guarantee set for free.

### Annotated source

```lean
-- Semantos Plane — Property Management Lexicon
--
-- Rental-operations lifecycle for a property under management (distinct
-- from the sale-preparation narrative modelled in demo-estate-to-auction).
-- Each category corresponds to an operational event with its own
-- regulatory / tenancy-law consequences:
--
--   lease         — creation of a tenancy
--   maintenance   — repair / upkeep work on the property
--   inspection    — scheduled or incident-triggered condition check
--   rent          — payment obligation, collection, or arrears notice
--   violation     — breach notice (cure-or-quit, nuisance, etc.)
--   renewal       — extension or re-negotiation of tenancy terms
--   termination   — end of tenancy (notice, eviction, mutual surrender)
--
-- Granularity rationale: residential-tenancy law treats these events
-- differently (a rent-payment patch triggers different clocks to a
-- violation patch) so the curator needs distinct cards per category.

import Semantos.Substrate.Lexicon
```

The import brings in the `Lexicon` typeclass and the substrate's patch machinery. The comment block is the rationale register — it states why each category exists at this granularity, not merely what it is. For a compliance-facing deployment, this comment is the first line of a regulatory argument: "the system distinguishes these event types because tenancy law distinguishes them."

```lean
namespace Semantos.Lexicons

open Semantos.Substrate

inductive PropertyManagementCategory where
  | lease
  | maintenance
  | inspection
  | rent
  | violation
  | renewal
  | termination
  deriving Repr, DecidableEq, BEq
```

The `inductive` declares the category set. `DecidableEq` is required by the `Lexicon` typeclass — the substrate needs to decide equality of categories at type-check time. `BEq` is the computational equality used in the policy evaluator's pattern matching. `Repr` enables printing during development and testing. The seven constructors map directly to the seven operational event types identified in the rationale.

```lean
def propertyManagementHeader : PropertyManagementCategory → String
  | .lease       => "LEASE"
  | .maintenance => "MAINTENANCE"
  | .inspection  => "INSPECTION"
  | .rent        => "RENT"
  | .violation   => "VIOLATION"
  | .renewal     => "RENEWAL"
  | .termination => "TERMINATION"
```

The `header` function is a total function by construction — the pattern match is exhaustive over the `inductive`. The string labels are uppercase by convention; they appear verbatim in cell headers and in the structured log, making log analysis straightforward. A grep for `"MAINTENANCE"` in the structured log returns exactly the maintenance-event records and nothing else.

```lean
theorem propertyManagementHeader_injective : ∀ c₁ c₂ : PropertyManagementCategory,
    propertyManagementHeader c₁ = propertyManagementHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [propertyManagementHeader]
```

The injectivity theorem is the proof obligation that the substrate's M1–M4 theorems depend on. It states: if the header strings are equal, the categories are equal. The proof is by case analysis over all 49 ordered pairs of constructors (7 × 7). The `simp_all` tactic discharges all cases: for pairs where `c₁ = c₂` the goal is trivially true; for pairs where `c₁ ≠ c₂` the hypothesis `h` reduces to an equality of distinct string literals, which `simp_all` refutes by definitional unfolding of `propertyManagementHeader`. The proof is fully automated; no manual term construction is needed.

The injectivity proof is why header strings must be distinct. If two categories mapped to the same header, the theorem would be false and the `Lexicon` instance could not be registered. The uppercase convention plus distinct names guarantees distinctness at a glance, but the proof makes that guarantee machine-checkable.

```lean
instance : Lexicon PropertyManagementCategory where
  header          := propertyManagementHeader
  headerInjective := propertyManagementHeader_injective

end Semantos.Lexicons
```

The instance registration is the payoff. The typeclass field `header` is populated with the function; the field `headerInjective` is populated with the proof. From this point on, any substrate operation that is generic over `[Lexicon α]` applies to `PropertyManagementCategory` without further ceremony. The `namespace` closes cleanly; no definitions leak into the global scope.

### What the typeclass machinery provides

Once registered, the substrate's generic operations become available at `Patch PropertyManagementCategory`. M1 (category preservation) guarantees the `maintenance` category on a cell is immutable after creation. M2 (header determinism) makes the string label a deterministic function of the category. M3 (injectivity under composition) preserves category identity across patch merges. M4 (renderCard totality) guarantees every category renders to a well-formed card with no failure path. D1–D3 (dispatch lemmas) make the policy evaluator's dispatch table complete and consistent with the injectivity proof. None of these need to be proved again for the property-management lexicon; they follow from the instance registration.

---

## The leaky-tap demo (30 min)

This demo traces the leaky-tap scenario from first message to settled invoice, running against a local sovereign node. The scenario is the worked example from Whitepaper v3 §4, retold from the lexicon's perspective. Each numbered step maps to a jural category; each transition shows how the dispatch envelope routes the work.

### Prerequisites

A sovereign node booted to step 7 (`kernel_set_enforcement(1)` active). The property-management extension installed with a seed database containing one property record, one active lease, and three hats: `pm` (property manager), `tenant` (Sam's hat), and `tradie` (the plumbing subcontractor). The MFP channel between the `pm` hat and the `tradie` hat is open with a funded escrow.

### Step 1 — Sam's voice message arrives (obligation, MAINTENANCE category)

> Sam says: "there's a leak under the kitchen sink, photos taken now."
>
> The voice-input modality returns a transcript signed with Sam's BRC-52 certificate. The intent-extraction step returns an `Intent` with jural category `obligation` (the landlord has a statutory obligation to repair), taxonomy coordinate `property.maintenance.plumbing.leak`, and target `<property-id>`. The SIR program carries `linearity: LINEAR`, `domainBinding: { flag: 0x000200A1, domainType: 'estate' }`, and `trustClass: interpretive`. The cell engine executes: `OP_CHECKCAPABILITY` confirms Sam's `tenant.report` capability for this property; `OP_CHECKDOMAINFLAG` confirms the estate domain flag; `OP_CHECKLINEARTYPE` confirms LINEAR. The cell is written to the property's evidence chain with category header `"MAINTENANCE"`.

The lexicon category here is `maintenance`. The jural category inside the SIR program is `obligation`. These two classification levels operate at different layers: the lexicon category routes the cell through the property-management extension's policy table; the SIR's jural category carries the normative meaning — there is an obligation on the landlord, not merely a request from the tenant.

### Step 2 — Triage (condition, MAINTENANCE category)

> The triage classifier evaluates the maintenance request against the property's compliance record and the lease's `responsibleParty` rules. The question is: is this the landlord's obligation or the tenant's? The substrate models this as a `condition` SIR node: if the defect is structural plumbing, `responsibleParty = landlord`; if it is tenant-caused damage, `responsibleParty = tenant`. The triage result patches the maintenance cell with the evaluated condition.

The `condition` category here is the Hohfeldian condition — an event that gates downstream action. The triage step does not itself impose a duty; it resolves the conditional that determines which downstream obligation applies.

### Step 3 — Owner auto-approval (power, MAINTENANCE category)

> The PM reviews the triage result. The estimated repair cost is below the owner's `maintenanceApprovalThreshold` stored on the lease's owner record. The threshold condition evaluates to true; no explicit approval patch from the owner is required. The PM hat exercises its delegated power to approve: the maintenance cell advances to `approvalStatus: approved`. The cell engine writes an `obligation` patch (the PM's obligation to proceed with dispatch) to the property's evidence chain.

This is an exercise of the power held by the PM hat — a power delegated by the owner in the management agreement, itself a power-conferring act at lease execution. The substrate enforces that only the `pm` hat can write this patch; a `tenant` or `tradie` hat writing the same patch would be rejected by `OP_CHECKIDENTITY`.

### Step 4 — Dispatch envelope creation (power + declaration, cross-vertical)

> The PM hat creates the dispatch envelope. The envelope is a RELEVANT cell — it must appear on both the property-management evidence chain and the tradie's job-lead inbox. The creation act is typed as `power` in the SIR: it creates a new set of entitlements (the tradie's entry permission, the tradie's obligation to report completion, the PM's right to receive invoice). The envelope carries two categories of patches at creation:
>
> - RELEVANT patches (visible to both hats): property address, description, photos, urgency, taxonomy coordinate, PM contact, tenant contact for access coordination.
> - AFFINE patches (encrypted to the PM hat's key): owner's internal cost expectations, tenant's payment history, PM's internal notes.
>
> The cell engine writes the envelope with category header `"MAINTENANCE"` and linearity `RELEVANT`. The K8 kernel invariant (demotion safety) is not triggered here — the envelope starts RELEVANT; it can later acquire additional AFFINE patches without changing its base linearity class.

The dispatch envelope (canonical definition: a single semantic object referenced by multiple organisations, on which each participant attaches per-hat RELEVANT or AFFINE patches) is not a copy of the maintenance cell. It is a new semantic object that the maintenance cell's evidence chain references; both verticals reference the same cell ID.

### Step 5 — Tradie receives the envelope (permission, MAINTENANCE category)

> On the tradie's side, the envelope arrives in the job-lead inbox. The tradie hat's receipt of the envelope creates a time-bounded entry permission for the property. The permission is modelled as a `permission` SIR node: the tradie hat may enter the property at the scheduled time, for the purpose of the plumbing repair, during the window negotiated in the scheduling patch.
>
> The tradie quotes, schedules the visit, and patches the envelope with a `declaration` patch: "Scheduled for Thursday 09:00–11:00." This patch is RELEVANT — visible to the PM and, via the tenant-facing status update, to Sam.

The `permission` here is the Hohfeldian privilege — the absence of a duty to refrain from entering — not the BRC-108 capability token sense of the word. The glossary distinguishes them. In the SIR layer, "permission" as a jural category means the tradie is not in breach by entering the property during the authorised window.

### Step 6 — Repair and completion (declaration, MAINTENANCE category)

> The tradie completes the repair, attaches photos, and patches the envelope with a `declaration` patch: category `maintenance`, content: completion notes, photos, parts used. The declaration is RELEVANT. The PM sees it; the owner sees a summary. Sam sees: "Your maintenance request has been sorted. The plumber came on Thursday."
>
> The maintenance request on the PM side advances from `in_progress` to `completed`. The evidence chain records the completion with the tradie's hat signature. The correlation ID from step 1 is present on every patch; the entire turn — from Sam's voice message to the tradie's completion note — is one greppable trace in the structured log.

The `declaration` here records a fact without itself imposing further duties. It is not an obligation to the tradie (the obligation was discharged by the repair). It is a factual record that the obligation was satisfied.

### Step 7 — Invoice and settlement (transfer, MAINTENANCE → RENT boundary)

> The tradie patches the envelope with a `transfer` patch: invoice amount $280, parts and labour. The PM receives the invoice, reconciles it against the maintenance record, and creates a corresponding charge to the owner. The MFP channel between the PM hat and the tradie hat advances by one tick; the HMAC-authenticated tick proof is dual-signed. Settlement is off-chain until the channel closes; at close, the highest-`nSequence` transaction is broadcast and finalised on-chain via SPV.
>
> The maintenance cell on the PM side advances to `invoiced`, then `closed`. The owner sees: "Maintenance completed at [address]. Tap replaced. $280 labour + parts." The owner's approval is required if the invoice exceeds the threshold stored on the lease; in this scenario it does not, so the `closed` transition happens without a further power patch.

The `transfer` category is the lexicon's representation of value movement. The MFP settlement is the substrate's mechanism; the lexicon category is the semantic label that tells the policy evaluator this patch carries financial provenance and must route to the payment-tracking subsystem.

### Step 8 — Audit trail

> At any point after closure, a regulator with the appropriate hat can request the full evidence chain: Sam's obligation cell (step 1), the triage condition patch (step 2), the PM's approval power patch (step 3), the dispatch envelope creation (step 4), the tradie's scheduling and completion declarations (steps 5–6), and the transfer patch (step 7). Every patch carries hat provenance, timestamp, and jural category. The chain is append-only by K6 (hash-chain integrity); the correlation ID from step 1 is present on every patch. No patch can be selectively erased; no party's AFFINE patches are visible to another hat.

The dispatch envelope requires no separate audit log; the evidence chain is the audit log. The AFFINE linearity of the PM's internal notes ensures that the regulator sees the same factual record as the PM, minus the fields that are structurally inaccessible.

### Timing

The demo runs in approximately 30 minutes on a local machine with a pre-seeded database. The bottleneck is MFP channel setup, which requires one on-chain funding transaction; in a demo environment a test-network faucet handles this in under two minutes.

---

## Extensions next

The property-management lexicon ships with seven categories: lease, maintenance, inspection, rent, violation, renewal, termination. Three natural extensions follow.

**Compliance as a first-class category.** Smoke-alarm testing, electrical-safety certificate renewal, and pool-fence inspections trigger different regulatory clocks than maintenance events. Adding a `compliance` constructor costs the same four-step proof obligation — add the constructor, add the header arm, re-run `cases c₁ <;> cases c₂` (Lean handles the new pairs automatically), update the instance. Downstream policy rules are extension logic in the governance domain; the lexicon layer is unchanged otherwise.

**Strata management as a governance domain variant.** Strata management adds a third governance layer — the owners corporation — holding powers over common-property maintenance that no individual lot owner holds. This is not a new lexicon category; it is a new governance domain kind alongside the five already modelled (trust, estate, realm, corporate, cooperative). The lexicon categories remain the same; the hat structure and capability token topology change.

**The lease-renewal as a power chain.** A renewal is not one act but a sequence: notice of intention (declaration), terms offered (power), acceptance or counter-offer (power, possibly iterated), execution (power creating the new LINEAR lease cell). The current `renewal` category captures the sequence under one label. An extended implementation would track each step as a distinct cell — all labelled `renewal` but with distinct SIR jural categories — so the policy evaluator can enforce, for instance, that a counter-offer cannot occur after the tenant has accepted. This requires richer SIR constraint structure, not a new lexicon category; the lexicon provides the routing label and the SIR carries the normative logic.

---

## Worked example: the leaky tap, retold

The following blockquote retells the eight-step maintenance workflow as a single narrative, mapping each step to a lexicon category and jural category explicitly.

> Sam, a rental tenant, reports a leak under the kitchen sink. The substrate's voice modality captures the transcript, signs it with Sam's BRC-52 certificate, and routes it to the intent pipeline. The intent-extraction step infers jural category `obligation` (the landlord's statutory repair duty), taxonomy coordinate `property.maintenance.plumbing.leak`, and wraps the result in a SIR program with `linearity: LINEAR`. The cell engine executes the program, confirming Sam's `tenant.report` capability via `OP_CHECKCAPABILITY`, and writes the cell to the property's evidence chain. Lexicon category: `maintenance`.
>
> The triage step evaluates a `condition` SIR node: the defect is structural plumbing, so `responsibleParty = landlord`. The condition patches the maintenance cell and gates the next step.
>
> The PM reviews. The estimated cost falls below the owner's auto-approval threshold — itself a `condition` stored on the owner record. The PM hat exercises its delegated `power` to approve; the cell advances to `approvalStatus: approved`.
>
> The PM hat creates the dispatch envelope — a new RELEVANT cell, typed as `power` in the SIR (it creates the tradie's entry permission and the tradie's completion obligation). The envelope carries RELEVANT patches visible to all hats (address, description, photos, urgency) and AFFINE patches encrypted to the PM hat (cost expectations, internal notes). Lexicon category: `maintenance` on both sides of the vertical boundary.
>
> The tradie receives the envelope. A `permission` SIR node is evaluated: the tradie hat holds a time-bounded entry permission for the scope of the repair. The tradie patches the envelope with a `declaration` (scheduling), RELEVANT, visible to PM and tenant.
>
> On Thursday, the tradie repairs the tap, attaches photos, and writes a `declaration` patch: completion notes, parts used, time on site. RELEVANT. The maintenance cell on the PM side advances to `completed`.
>
> The tradie writes a `transfer` patch: invoice $280. The PM reconciles and forwards to the owner record. The MFP channel ticks once; the settlement proof is HMAC-authenticated and dual-signed. The maintenance cell advances to `invoiced`, then `closed`.
>
> The full evidence chain — seven patches, seven hat signatures, one correlation ID — is append-only, regulator-readable, and structurally inaccessible to parties whose hats are not bound to the respective AFFINE fields. The dispatch envelope is not a copy or a handoff; it is a single semantic object that both verticals reference, with per-hat visibility enforced at the byte level by the policy evaluator.

That is the dispatch envelope pattern in operation. The property-management lexicon provides the routing labels. The seven jural categories provide the normative structure. The dispatch envelope carries the result across the organisational boundary without point-to-point integration.
