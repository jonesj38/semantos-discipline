---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/24-cdm-lexicon.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.648149+00:00
---

# CDM — Derivatives Lifecycle

Domain lexicons are the vocabulary layers that sit between the generic seven jural categories and the specific economic events of each industry. This chapter addresses the CDM lexicon: the terms, cell types, and lifecycle transitions that make derivatives expressible in the Semantos intermediate representation.

---

## Economic Problem

A derivatives trade between two counterparties is not a single act. It is a sequence of events over time — execution, confirmation, clearing, margining, settlement, and any number of intermediate steps (amendments, exercises, termination, novation) — each of which changes the legal and economic relationship between the parties and each of which generates distinct obligations to external parties (regulators, clearing houses, trade repositories).

The fundamental tension in derivatives infrastructure is that each of these events must be:

1. **Uniquely identifiable.** The ISDA Common Domain Model (CDM) assigns Unique Transaction Identifiers (UTIs) precisely because duplicate events — two parties reporting the same trade with inconsistent data — are among the costliest operational failures in post-trade processing.

2. **State-ordered.** A clearing event cannot precede a confirmation event. A novation cannot precede clearing (in some regimes). Settlement cannot precede all prior conditions. The events are not a bag; they are a sequence with defined preconditions.

3. **Party-bound.** Each event involves a defined set of parties with defined roles (buyer, seller, clearing member, central counterparty, calculation agent, reporting party). The rights and obligations at each step are role-specific.

4. **Regulatory-reportable.** Post-trade reporting regimes (CFTC, EMIR, MAS, JFSA, ASIC) require that lifecycle events be reported to approved trade repositories within defined windows. These reports are not optional and cannot be destroyed once filed.

5. **Economically final.** Settlement, in particular, is linear: the payment happens once. Novation transfers the position once. Close-out netting computes the net obligation once. These events are not reversible by re-running the same computation.

The CDM addresses points 1–3 through a shared schema for events, parties, and product taxonomy. It does not enforce the ordering constraints, the capability requirements, or the linearity of the underlying operations. A CDM JSON document describes what happened; it does not prevent invalid sequences or guarantee that a transfer happened exactly once.

The Semantos CDM lexicon fills that gap. It maps each lifecycle event type onto one or more of the seven jural categories, assigns linearity, and encodes the event as a cell that the 2-PDA cell engine enforces at the opcode level. Ordering constraints become conditions. Role requirements become permissions and obligations. The finality of settlement becomes LINEAR linearity — a cell the engine will refuse to consume twice.

---

## Hohfeldian Decomposition

The CDM lifecycle decomposes naturally across the seven jural categories. This section walks through each event type from the Lean lexicon's `CDMCategory` inductive type and maps it to its primary jural category (or categories, where the event is composite).

The mapping table from `docs/SEMANTIC-IR-ARCHITECTURE.md` § 3.4 is reproduced and annotated below:

| CDM Event | Primary Category | Secondary | Linearity | Economic reading |
|---|---|---|---|---|
| execution | power | — | LINEAR | Exercises authority to bring the trade into legal existence |
| confirmation | declaration | — | RELEVANT | Asserts that both parties agree to the recorded terms |
| clearing | power | — | LINEAR | Exercises the power to novate each leg to the CCP |
| settlement | transfer | — | LINEAR | Moves economic value from payer to receiver |
| novation | transfer | power | LINEAR | Transfers the position + exercises power to change the legal relationship |
| payment | transfer | — | LINEAR | Moves a defined cash amount |
| margin-call | obligation | — | LINEAR | Creates a duty to post collateral by a deadline |
| default | declaration | — | RELEVANT | Asserts that a failure-to-pay or other trigger event has occurred |
| close-out-netting | power | transfer | LINEAR | Exercises the contractual power to net; the net settlement is a transfer |
| rate-reset | condition | — | AFFINE | A temporal gate consumed when the reset is evaluated |
| partial-termination | power | — | LINEAR | Reduces notional; the residual trade continues |
| full-termination | power | — | LINEAR | Terminates the trade; the cell is consumed |

The decomposition is not an arbitrary labelling. It reflects the actual legal character of each event.

### Why confirmation is a declaration (not a power)

Confirmation does not change the legal relationship — execution has already done that. Confirmation is an assertion of fact: that both parties agree the recorded terms match the agreed terms. Its linearity is RELEVANT because the confirmation record cannot be destroyed; it is evidence that the trade exists on agreed terms.

### Why novation is transfer + power

Novation replaces one counterparty with another. The position moves from the old counterparty to the new — that is a transfer. Novation also changes the legal relationship between the original counterparties and the replacing party, creating new rights and obligations where none existed — that is a power. The worked program in the 30-min demo encodes this combination as a two-node SIR program.

### Why margin-call is an obligation (not a transfer)

A margin call is a demand — a duty the called party must fulfil by posting collateral. The transfer of collateral is a separate event that fulfils the obligation. The obligation is LINEAR: it must be consumed exactly once, by either fulfilment or default.

### Why default is a declaration (not a power or obligation)

Default is an assertion of fact: that a defined trigger event has occurred (failure to pay, insolvency, breach of representation). It does not create new obligations or transfer value; those follow from the contractual close-out mechanism. The declaration is RELEVANT because the assertion cannot be retracted.

### Why rate-reset is a condition

A rate-reset re-prices a floating-rate leg at defined intervals. No value moves at reset. It is a temporal gate that, when consumed, produces a new effective rate for the next payment period. AFFINE linearity means the condition is consumed when evaluated and may be recreated for the next period by the rate schedule.

---

## The Lean Lexicon

The CDM lexicon is defined in `proofs/lean/Semantos/Lexicons/CDM.lean`. The file is reproduced in full with inline annotation.

```lean
-- Semantos Plane — CDM (Common Domain Model) Lexicon
--
-- ISDA-style lifecycle events for financial derivatives and structured
-- trades. The seven categories span trade confirmation through
-- settlement / termination:
--
--   confirmation — trade terms confirmed between counterparties
--   amendment    — modification of an existing trade's terms
--   allocation   — assignment of trade portions across accounts
--   exercise     — triggering a contractual optionality
--   termination  — early unwinding before maturity
--   novation     — transfer of a position to a new counterparty
--   settlement   — payment / delivery at maturity or exercise
--
-- These are the first-class lifecycle events in the ISDA CDM specification;
-- each generates distinct regulatory and accounting obligations, which is
-- why they warrant category-level status.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate
```

The `import` statement loads the `Lexicon` typeclass from the Semantos substrate. Any type that implements this typeclass can be used as a domain vocabulary in the governance plane. The `open` statement brings the substrate namespace into scope so that `Lexicon` can be referenced without qualification.

```lean
inductive CDMCategory where
  | confirmation
  | amendment
  | allocation
  | exercise
  | termination
  | novation
  | settlement
  deriving Repr, DecidableEq, BEq
```

`CDMCategory` is an inductive type with seven constructors — one per first-class lifecycle event in the ISDA CDM specification. The `deriving` clause generates `Repr` (string representation for logging), `DecidableEq` (compile-time equality, required by the `Lexicon` typeclass), and `BEq` (efficient runtime equality).

The seven constructors here are not the seven jural categories. The jural categories are the semantic primitives of the SIR; the CDM categories are the domain vocabulary. One CDM category may map to one or more jural categories, as the decomposition table shows. Events that generate distinct regulatory obligations are first-class constructors; sub-steps of a primary event are represented as transitions within the primary event's cell.

```lean
def cdmHeader : CDMCategory → String
  | .confirmation => "CONFIRMATION"
  | .amendment    => "AMENDMENT"
  | .allocation   => "ALLOCATION"
  | .exercise     => "EXERCISE"
  | .termination  => "TERMINATION"
  | .novation     => "NOVATION"
  | .settlement   => "SETTLEMENT"
```

`cdmHeader` maps each constructor to a canonical string. This is the wire-format identifier for the category. The governance plane uses this string when it records events in the cell DAG. The choice of all-caps strings matches ISDA message format conventions, making the lexicon readable alongside legacy FpML and CDM JSON messages.

```lean
theorem cdmHeader_injective : ∀ c₁ c₂ : CDMCategory,
    cdmHeader c₁ = cdmHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [cdmHeader]
```

This theorem proves that `cdmHeader` is injective — no two distinct constructors map to the same string. The proof proceeds by case analysis: for all 49 pairs (7 × 7), `simp_all` reduces to either a trivial identity or a contradiction. The theorem is required for the `Lexicon` typeclass instance.

Injectivity matters because the cell engine uses the header string to identify the event type in cell metadata bytes. If two event types shared a header string, the engine could not distinguish them structurally. The Lean proof is a compile-time guarantee, not a runtime check.

```lean
instance : Lexicon CDMCategory where
  header          := cdmHeader
  headerInjective := cdmHeader_injective

end Semantos.Lexicons
```

The `Lexicon` instance wires `CDMCategory` into the substrate's typeclass system. Any code that accepts a `Lexicon α` can now accept `CDMCategory`. This pattern — inductive type, injective string header, Lean-proven injectivity, typeclass instance — is canonical across all Semantos lexicons.

### What the Lean file does not contain

The Lean lexicon is intentionally minimal. It proves the vocabulary is unambiguous; everything else lives at the TypeScript and SIR layers:

- The transition table lives in `lifecycle/trade-events.ts` and in the SIR as condition nodes with `requiredPhase` gates.
- Party role requirements are encoded as permission nodes in the SIR and capability checks in the OIR.
- Economic effects (`EconomicTerms`, `EconomicEffect`) are in the TypeScript extension.
- Regulatory reporting obligations are RELEVANT declaration cells generated as a side effect of each transition.

---

## The Extension Vocabulary

The `extensions/cdm/` directory provides the runtime implementation that corresponds to the Lean lexicon. Reading the directory listing reveals the structure:

```
extensions/cdm/
  demo.ts                        # 30-minute demo entry point
  demo-kernel.ts                 # kernel bootstrap for the demo
  package.json
  tsconfig.json
  src/
    types.ts                     # CDMProduct, CDMLifecycleEvent, party roles, economic terms
    lifecycle.ts                 # public lifecycle API (re-exports)
    regulatory.ts                # regulatory report generation
    bridge/
      cdm-json.ts                # CDM JSON ↔ Semantos cell translation
      fpml.ts                    # FpML ↔ Semantos cell translation
      index.ts
    lifecycle/
      cell-builder.ts            # assembles cells from lifecycle events
      event-reducer.ts           # applies events to produce updated state
      trade-events.ts            # transition table + valid-event guards
      novation.ts                # novation flow (transfer + power)
      termination.ts             # termination flow (power)
      increase.ts / decrease.ts  # notional changes (power)
      persistence.ts             # cell DAG anchoring
      policy-gate.ts             # capability and domain flag checks
      lifecycle-facade.ts        # unified public API
    policies/
      close-out-netting.policy   # compiled policy for close-out netting
      failure-to-pay-default.policy
      payment-condition-precedent.policy
      transfer-consent.policy
      variation-margin.policy
```

The vocabulary maps directly to the Hohfeldian decomposition: `policy-gate.ts` enforces permission (capability checks) and prohibition (domain flag checks); `novation.ts` implements transfer + power; `termination.ts` implements power; `event-reducer.ts` encodes the state machine (conditions govern valid transitions); `regulatory.ts` generates RELEVANT declaration cells; the `.policy` files are compiled prohibition and condition expressions. The bridge modules (`cdm-json.ts`, `fpml.ts`) translate external CDM and FpML representations into Semantos cells.

---

## 30-Minute Runnable Demo

This section walks through a CDM novation end-to-end. The demo assumes the Semantos CDM extension is installed and the kernel is running (boot steps 1–7 complete). All code below is runnable from the project root with `bun extensions/cdm/demo.ts`.

The demo is structured in four steps: create a trade, confirm it, clear it, then novate the buyer leg to a new counterparty.

### Step 1 — Create and confirm a rates swap

```typescript
import { createCDMProduct, computeCDMTypeHash } from './extensions/cdm/src/types';
import type { CDMPartyRole, EconomicTerms } from './extensions/cdm/src/types';

// Define the two counterparties. Each party maps to an identity hat
// in the Semantos kernel. The capabilities array reflects what each
// hat is permitted to do (capability tokens per BRC-108).
const buyer: CDMPartyRole = {
  partyId:      'party-alpha',
  role:         'buyer',
  capabilities: [1, 2, 3],        // TRADE_EXEC, TRADE_CONFIRM, MARGIN_POST
  hatCertId:    'cert-alpha-001',
  lei:          'ALPHA0000000000001',
  jurisdiction: 'US',
};

const seller: CDMPartyRole = {
  partyId:      'party-beta',
  role:         'seller',
  capabilities: [1, 2, 3, 4],     // + REPORTING
  hatCertId:    'cert-beta-001',
  lei:          'BETA00000000000001',
  jurisdiction: 'GB',
};

const economicTerms: EconomicTerms = {
  notional:               { amount: 50_000_000, currency: 'USD' },
  effectiveDate:          '2026-04-28',
  terminationDate:        '2031-04-28',
  fixedRate:              0.042,
  floatingRateIndex:      'USD-SOFR',
  paymentFrequency:       '3M',
  dayCountConvention:     'ACT/360',
  businessDayConvention:  'MODFOLLOWING',
};

// createCDMProduct stamps the cell as LINEAR, assigns a UTI,
// and sets lifecycleState to 'proposed'.
const trade = createCDMProduct(
  'rates.swap.fixed-float',
  economicTerms,
  [buyer, seller],
  '2026-04-26',
  ['reporting.cftc', 'reporting.emir'],
);

console.log('Trade cell id:', trade.cellId);
console.log('UTI:', trade.uti);
console.log('Type hash:', trade.typeHashHex);
// → Trade cell id: <hex>
// → UTI: ALPHA000000_20260426<hash8>
// → Type hash: <sha256 of "cdm.rates.swap.fixed-float:lifecycle:inst.derivative.otc">
```

The type hash encodes the product taxonomy as a SHA-256 digest. The cell engine's `typeHashCheck` opcode verifies this hash — no event can claim to operate on a `rates.swap.fixed-float` unless the cell's recorded type hash matches. The trade cell is LINEAR from creation; the engine rejects any attempt to consume it twice.

### Step 2 — Apply the confirmation transition

```typescript
import { createLifecycleEvent } from './extensions/cdm/src/types';

// Confirmation: declaration, RELEVANT linearity.
// Both parties have confirmed (in practice, both must sign;
// here we model the event after both signatures are collected).
const confirmEvent = createLifecycleEvent(
  'confirmation',
  trade,
  '2026-04-26',        // effectiveDate
  'proposed',          // before state
  'confirmed',         // after state
  'cert-beta-001',     // actor (the confirming party's cert)
);

console.log('Confirmation event id:', confirmEvent.eventId);
console.log('State transition:', confirmEvent.before, '→', confirmEvent.after);
// → Confirmation event id: <hex>
// → State transition: proposed → confirmed
```

The confirmation event is recorded as a RELEVANT cell. The cell engine rejects any attempt to destroy it — the structural enforcement of the "declaration, RELEVANT" assignment in the decomposition table.

### Step 3 — Clear the trade

```typescript
// Clearing: power, LINEAR linearity.
// The clearing event novates each leg to the CCP.
// Here we simplify: a single clearing event records the transition.
const clearingEvent = createLifecycleEvent(
  'clearing',
  { ...trade, lifecycleState: 'confirmed' },  // trade in confirmed state
  '2026-04-27',
  'confirmed',
  'cleared',
  'cert-ccp-001',      // the CCP's cert exercises the clearing power
);

console.log('Clearing event id:', clearingEvent.eventId);
console.log('State transition:', clearingEvent.before, '→', clearingEvent.after);
// → Clearing event id: <hex>
// → State transition: confirmed → cleared
```

The clearing event is a power exercised by the CCP. The `policy-gate.ts` module verifies that the actor holds `CLEARING_EXEC` capability before allowing this transition.

### Step 4 — Novate the buyer leg

This is the central worked example: a CDM novation encoded as a `power + transfer` SIR program.

```typescript
import { novateProduct } from './extensions/cdm/src/lifecycle/novation';

// The new counterparty replacing the original buyer.
const newBuyer: CDMPartyRole = {
  partyId:      'party-gamma',
  role:         'buyer',
  capabilities: [1, 2, 3],
  hatCertId:    'cert-gamma-001',
  lei:          'GAMMA0000000000001',
  jurisdiction: 'US',
};

const clearedTrade = {
  ...trade,
  lifecycleState: 'cleared' as const,
};

const novationResult = novateProduct(
  clearedTrade,
  buyer,            // oldParty: the leg being replaced
  newBuyer,         // newParty: the incoming counterparty
  'cert-alpha-001', // actorCertId: the outgoing party consents
  '2026-05-01',     // effectiveDate
);

if (!novationResult.ok) {
  throw new Error(novationResult.error);
}

const { product: novatedTrade, transferRecord, event: novationEvent } = novationResult.value;

console.log('Novated trade state:', novatedTrade.lifecycleState);
console.log('New buyer:', novatedTrade.parties.find(p => p.role === 'buyer')?.partyId);
console.log('Transfer record:', transferRecord.objectId);
console.log('Novation event:', novationEvent.eventType, novationEvent.before, '→', novationEvent.after);
// → Novated trade state: novated
// → New buyer: party-gamma
// → Transfer record: <hex>
// → Novation event: novation cleared → novated
```

The function returns three artefacts: `product` (the updated cell with `lifecycleState: 'novated'` and the party list updated), `transferRecord` (a substrate `TransferRecord` recording that `cert-alpha-001` transferred the cell to `cert-gamma-001` — the transfer jural category), and `event` (a `CDMLifecycleEvent` with `eventType: 'novation'` — the power jural category). Together they constitute the novation as a composite jural event.

### The novation as a SIR program

The two-node SIR program that encodes the novation above is:

```
SIRProgram {
  primaryNodeId: "$s1",
  programGovernance: {
    trustClass:         'authoritative',
    proofRequirement:   'formal',
    executionAuthority: 'hat_scoped',
    linearity:          'LINEAR',
    allowedEmitOps:     ['domainCheck', 'capability', 'typeHashCheck', 'logical_and']
  },
  nodes: [

    // Node $s0 — power: the authority to change the legal relationship.
    // The outgoing party (alpha) exercises its contractual right to exit.
    // The incoming party (gamma) exercises its contractual right to enter.
    SIRNode {
      id:       "$s0",
      category: "power",
      taxonomy: {
        what:  "rates.swap.fixed-float",
        how:   "lifecycle.novation",
        why:   "relationship-change"
      },
      identity: {
        subject: { type: "cert", certId: "cert-alpha-001" }
      },
      governance: {
        trustClass:         'authoritative',
        proofRequirement:   'formal',
        executionAuthority: 'hat_scoped',
        linearity:          'LINEAR'
      },
      action:     "novate",
      constraint: {
        kind:     'composite',
        op:       'and',
        children: [
          { kind: 'capability', required: 5, name: 'NOVATION_EXEC' },
          { kind: 'domain',     flag: 0x00010001 },
          { kind: 'state',      requiredPhase: 'cleared' }
        ]
      },
      target: { productCellId: "<clearedTrade.cellId>" },
      provenance: {
        source:             'api',
        expressedAt:        '2026-05-01T00:00:00Z',
        trustAtExpression:  'authoritative'
      }
    },

    // Node $s1 — transfer: the movement of the position.
    // The position (LINEAR cell) moves from cert-alpha-001 to cert-gamma-001.
    SIRNode {
      id:       "$s1",
      category: "transfer",
      taxonomy: {
        what:  "rates.swap.fixed-float",
        how:   "lifecycle.novation",
        why:   "relationship-change"
      },
      identity: {
        subject: { type: "cert", certId: "cert-alpha-001" }
      },
      governance: {
        trustClass:         'authoritative',
        proofRequirement:   'formal',
        executionAuthority: 'hat_scoped',
        linearity:          'LINEAR'
      },
      action:     "transfer",
      constraint: {
        kind:     'composite',
        op:       'and',
        children: [
          { kind: 'capability', required: 6, name: 'TRANSFER' },
          { kind: 'capability', required: 7, name: 'METERING' },
          { kind: 'domain',     flag: 0x00010001 }
        ]
      },
      target:     { productCellId: "<clearedTrade.cellId>" },
      transferTo: { subject: { type: "cert", certId: "cert-gamma-001" } },
      provenance: {
        source:             'api',
        expressedAt:        '2026-05-01T00:00:00Z',
        trustAtExpression:  'authoritative'
      }
    }
  ]
}
```

The power node `$s0` verifies `NOVATION_EXEC` capability, the governance domain flag, and the `cleared` state precondition. The transfer node `$s1` verifies `TRANSFER` and `METERING` capabilities and the domain flag. Together they lower to six OIR bindings (domain check, state check, two capability checks, identity check, `logical_and`) emitting approximately 24 bytes. The program is atomic: both nodes are evaluated before any state change is recorded.

### What the demo verifies

Running `bun extensions/cdm/demo.ts` produces: a trade cell with correct UTI and type hash; state transitions from `proposed` through `confirmed` → `cleared` → `novated`; a `NovationResult` with a `TransferRecord` linking the old and new hat certificates; a rejected attempt to novate a trade in `proposed` state (transition table guard); and the SIR program structure printed to stdout with both jural categories. The demo runs against the in-process kernel stub in `demo-kernel.ts` and does not require network connectivity. Boot steps 8–15 are out of scope.

---

## Extensions Next

The CDM lexicon in its current form covers the seven primary lifecycle event categories. Four categories of extension are tractable for a reader who wants to go further.

### 1. Add the remaining CDM event types as Lean constructors

The current `CDMCategory` inductive type has seven constructors. The TypeScript `CDMEventType` union in `extensions/cdm/src/types.ts` has twelve event types: the seven in the Lean type plus `payment`, `margin-call`, `default`, `close-out-netting`, and `rate-reset`. A reader can extend `CDMCategory` with these five additional constructors, add corresponding `cdmHeader` cases, verify that `cdmHeader_injective` still holds (the `simp_all` proof should extend automatically), and update the `Lexicon` instance.

Each new constructor should be mapped to its jural category in the accompanying documentation:

- `payment` → transfer, LINEAR
- `marginCall` → obligation, LINEAR (renaming to avoid the kebab-case which Lean does not permit)
- `default` → declaration, RELEVANT
- `closeOutNetting` → power + transfer, LINEAR
- `rateReset` → condition, AFFINE

### 2. Encode the transition table in Lean

The current transition table lives in TypeScript (`trade-events.ts`) as a JavaScript map. A more rigorous representation would encode the valid transitions as a Lean relation — a proposition `ValidTransition : CDMLifecycleState → CDMCategory → Prop` — and prove that the transition table is complete (every reachable state has at least one valid outgoing event) and acyclic (no sequence of events returns to the initial state).

The acyclicity proof would require defining `CDMLifecycleState` as a Lean inductive type (parallel to `CDMCategory`) and showing that the reachability relation is a DAG. This is feasible within Lean 4 and would provide a machine-checked specification of the CDM lifecycle state machine.

### 3. Write a close-out netting SIR program

Close-out netting is the other composite jural event in the CDM lifecycle: power (the contractual authority to net) + transfer (the net settlement). It operates across a portfolio of trades rather than a single trade, which makes it more complex than novation: the power node must reference multiple product cells, and the transfer node must reference the net settlement amount rather than a single cell.

The extension would require a `SIRProgram` with one power node per product in the netting set plus a single transfer node for the net amount. The governance context would carry a composite domain constraint checking that all product cells share the same CDM governance domain flag. The lower pass would emit an `OP_CHECKDOMAINFLAG` for each cell in the netting set, plus the capability and identity checks for the settlement.

### 4. Build the FpML bridge

The `extensions/cdm/src/bridge/fpml.ts` file provides a skeleton for translating FpML trade confirmation messages into Semantos cells. A complete bridge would:

- Parse an FpML `<dataDocument>` or `<trade>` element.
- Extract the product taxonomy (mapping FpML `<productType>` to `CDMProductType`).
- Extract party roles (mapping FpML `<partyTradeIdentifier>` to `CDMPartyRole`).
- Extract economic terms (mapping FpML leg definitions to `EconomicTerms`).
- Call `createCDMProduct` to produce the cell.
- Generate the initial confirmation event.

This bridge would make the CDM lexicon interoperable with the large installed base of FpML-capable systems, allowing existing trade confirmation workflows to generate Semantos cells without rewriting the front-end message production.

---

## Annotated Lexicon Code — Complete

For reference, the complete `CDM.lean` file with all annotations collapsed to inline comments:

```lean
-- Semantos Plane — CDM (Common Domain Model) Lexicon
-- Seven first-class lifecycle event categories for ISDA derivatives.
-- Each maps to one or more of the seven jural categories in the SIR.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

-- The CDM vocabulary: seven event categories, each with distinct
-- regulatory and accounting consequences.
inductive CDMCategory where
  | confirmation   -- declaration, RELEVANT — both parties attest agreement
  | amendment      -- power, LINEAR — modifies agreed terms
  | allocation     -- transfer, LINEAR — distributes trade across accounts
  | exercise       -- power, LINEAR — triggers contractual optionality
  | termination    -- power, LINEAR — unwinds the trade
  | novation       -- transfer + power, LINEAR — replaces a counterparty
  | settlement     -- transfer, LINEAR — moves value at maturity
  deriving Repr, DecidableEq, BEq

-- Wire-format identifiers. Matches ISDA message header conventions.
def cdmHeader : CDMCategory → String
  | .confirmation => "CONFIRMATION"
  | .amendment    => "AMENDMENT"
  | .allocation   => "ALLOCATION"
  | .exercise     => "EXERCISE"
  | .termination  => "TERMINATION"
  | .novation     => "NOVATION"
  | .settlement   => "SETTLEMENT"

-- Lean-proven: no two event types share a header string.
-- Guarantees unambiguous cell-engine opcode dispatch.
theorem cdmHeader_injective : ∀ c₁ c₂ : CDMCategory,
    cdmHeader c₁ = cdmHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [cdmHeader]

-- Register CDMCategory as a Semantos lexicon.
-- The typeclass instance makes this vocabulary available to the
-- governance plane, the SIR lower pass, and the cell-builder.
instance : Lexicon CDMCategory where
  header          := cdmHeader
  headerInjective := cdmHeader_injective

end Semantos.Lexicons
```

The 53-line file is the complete machine-verified vocabulary for the CDM domain. The worked novation program above shows how this vocabulary connects to the SIR: the `CDMCategory.novation` constructor corresponds to a two-node SIR program combining transfer and power, with the header string `"NOVATION"` appearing in the cell metadata bytes that the engine reads to route the event to the correct policy gate.

The Lean proof guarantees that this routing is injective: the string `"NOVATION"` uniquely identifies the novation event and cannot be confused with any other CDM category by any conformant implementation of the `Lexicon` typeclass.
