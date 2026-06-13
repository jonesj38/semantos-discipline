---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-28-ISDA-CDM.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.717135+00:00
---

# Phase 28 — ISDA Common Domain Model Integration

**Version**: 1.0
**Date**: March 2026
**Status**: Exploratory — independent track (can start after Phase 17)
**Duration**: 8 weeks (with 40% buffer: 11.2 weeks)
**Prerequisites**: Phase 17 complete (transfer + recovery — chain-of-custody for LINEAR objects). Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry — host function dispatch for domain predicates). Phase 21 recommended (Lisp policy compiler for contract clause authoring). Phase 18 recommended (metering control plane for payment flows).
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-28-isda-cdm`

---

## Context

ISDA's Common Domain Model (CDM) is an open-source, machine-readable model for financial products and their lifecycle events. It defines how derivatives, securities, and lending transactions are represented, how lifecycle events (execution, clearing, settlement, novation, termination) transform those representations, and how regulatory reporting obligations attach to each event.

The CDM is already trying to be what Semantos IS: a universal semantic layer where objects carry their own type information, lifecycle rules, and audit trails. The difference is that CDM is a data model specification. Semantos is a runtime that enforces the model's constraints at the opcode level.

This phase maps CDM types onto Semantos semantic objects. The mapping is natural:

- **CDM Product** → Semantic object with taxonomy coordinates (WHAT = product type, HOW = lifecycle state, WHY = economic/regulatory purpose)
- **CDM Event** → State transition on a semantic object (opcode sequence on the 2-PDA)
- **CDM Party** → Identity facet (Phase 8.5) with capability tokens gating what actions each party can take
- **CDM Lineage** → Cell DAG (each event creates a new cell referencing the previous state)
- **CDM Qualification** → Lisp policy (Phase 21) that compiles to capability cells

The critical insight: CDM lifecycle events are **exactly** the state transitions that the cell engine already handles. A novation is a transfer of a LINEAR trade cell from one counterparty to another. A partial termination is an AFFINE consumption of a portion of the notional. A netting set is a collection of cells with a governance policy determining close-out behavior. The linearity modes aren't a metaphor — they map directly to how derivatives actually work.

### Three-Axis Taxonomy for Financial Products

```
WHAT (product type):         rates.swap.fixed-float
                             credit.cds.single-name
                             equity.option.vanilla.european
                             fx.forward.deliverable

HOW (lifecycle state):       proposed → executed → confirmed → cleared → settled → terminated
                             proposed → executed → novated → confirmed → ...
                             proposed → executed → defaulted → close-out → ...

WHY (regulatory/economic):   hedging.interest-rate
                             speculation.directional
                             reporting.cftc.part-43
                             reporting.emir.trade-repository
```

### The Compression Gradient (Financial Domain)

```
Legal counsel: "counterparty must post initial margin within T+1 for uncleared swaps"
    ↓ (policy authoring)
(define-policy initial-margin-posting
  :subject counterparty
  :action post-margin
  :constraint (and
    (= product-class "swap")
    (= clearing-status "uncleared")
    (time-before (+ execution-date "P1D")))
  :linearity LINEAR)
    ↓ (Lisp compiler)
"swap" "product-class-eq?" OP_CALLHOST "uncleared" "clearing-status?" OP_CALLHOST OP_EQUAL BOOLAND "execution-date" OP_LOADFIELD "P1D" DATE-ADD "time-before?" OP_CALLHOST BOOLAND VERIFY
    ↓ (cell engine)
2-PDA evaluates → margin call valid or rejected at opcode level
    ↓ (Plexus)
Signed transaction → regulatory reporting cell created automatically
```

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | Cell header types, linearity modes — map to CDM product lifecycle |
| `IDENTITY:FACET` | `packages/loom/src/services/identity/` | Identity facets — map to CDM Party roles |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Transfer protocol — map to CDM novation/assignment |
| `CAPABILITY:TYPES` | `src/types/capability.ts` | Capability tokens — map to CDM entitlements |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | Policy compiler — map to CDM qualification functions |
| `METERING:FSM` | `packages/metering/src/` | Payment channel FSM — map to CDM payment flows |
| `GOVERNANCE:TYPES` | `src/types/governance.ts` | Ballot/Dispute/Resolution — map to CDM dispute resolution |
| `TAXONOMY:TREE` | `packages/loom/src/services/IntentTaxonomy.ts` | Taxonomy structure — extend with financial product types |
| `DAG:PERSIST` | `packages/plexus-vendor-sdk/src/graph/` | DAG persistence — map to CDM event lineage |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry class — register CDM predicates for OP_CALLHOST dispatch |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |

---

## Deliverables

### D28.1 — CDM Type Mapping

**File**: `packages/cdm/src/types.ts`

Type definitions mapping CDM concepts to Semantos primitives:

```typescript
/** CDM Product mapped to a semantic object */
interface CDMProduct {
  cellId: string;                          // cell address
  productType: CDMProductType;             // rates.swap, credit.cds, etc.
  linearity: 'LINEAR';                    // trades are LINEAR — one instance, no duplication
  parties: CDMPartyRole[];                 // counterparties with identity facets
  economicTerms: EconomicTerms;            // notional, rate, dates, etc.
  lifecycleState: CDMLifecycleState;       // proposed, executed, confirmed, etc.
  regulatoryObligations: RegulatoryTag[];  // CFTC, EMIR, etc.
  previousEventCell?: string;              // DAG link to prior lifecycle state
}

/** CDM Product taxonomy — maps to WHAT axis */
type CDMProductType =
  | 'rates.swap.fixed-float'
  | 'rates.swap.basis'
  | 'rates.swap.ois'
  | 'rates.fra'
  | 'rates.cap-floor'
  | 'credit.cds.single-name'
  | 'credit.cds.index'
  | 'credit.cds.tranche'
  | 'equity.option.vanilla.european'
  | 'equity.option.vanilla.american'
  | 'equity.option.exotic.barrier'
  | 'equity.swap.total-return'
  | 'fx.forward.deliverable'
  | 'fx.forward.ndf'
  | 'fx.option.vanilla'
  | 'fx.swap';

/** CDM Lifecycle states — maps to HOW axis */
type CDMLifecycleState =
  | 'proposed'
  | 'executed'
  | 'confirmed'
  | 'cleared'
  | 'settled'
  | 'novated'
  | 'partially-terminated'
  | 'terminated'
  | 'defaulted'
  | 'close-out';

/** CDM Party role — maps to identity facet + capability */
interface CDMPartyRole {
  partyId: string;                         // identity facet ID
  role: 'buyer' | 'seller' | 'clearing-member' | 'ccp' | 'calculation-agent' | 'reporting-party';
  capabilities: number[];                  // capability tokens held by this party
}

/** CDM Lifecycle event — maps to state transition */
interface CDMLifecycleEvent {
  eventType: CDMEventType;
  timestamp: string;                       // ISO 8601
  effectiveDate: string;                   // business date
  parties: CDMPartyRole[];
  before: CDMLifecycleState;
  after: CDMLifecycleState;
  economicEffect?: EconomicEffect;         // notional change, rate reset, etc.
  regulatoryReport?: RegulatoryReport;     // auto-generated report cell
  policyCell?: string;                     // capability cell authorizing this event
}

type CDMEventType =
  | 'execution'
  | 'confirmation'
  | 'clearing'
  | 'settlement'
  | 'novation'
  | 'partial-termination'
  | 'full-termination'
  | 'rate-reset'
  | 'payment'
  | 'margin-call'
  | 'default'
  | 'close-out-netting';

/** Economic terms — the payload of the product cell */
interface EconomicTerms {
  notional: { amount: number; currency: string };
  effectiveDate: string;
  terminationDate: string;
  fixedRate?: number;
  floatingRateIndex?: string;              // e.g., "SOFR", "EURIBOR"
  paymentFrequency?: string;               // e.g., "3M", "6M", "1Y"
  dayCountConvention?: string;             // e.g., "ACT/360", "30/360"
  businessDayConvention?: string;          // e.g., "MODFOLLOWING"
}
```

**Critical constraints**:
- CDMProduct is a **view** over a cell, just like GameEntity in Phase 26. The cell IS the product.
- Trades are always LINEAR. A swap exists once. It cannot be duplicated. Novation is a transfer, not a copy.
- Lifecycle events create new cells referencing previous cells. The trade's history is an immutable DAG.
- Party roles map to identity facets with capability tokens. The calculation agent has capabilities the buyer doesn't.

---

### D28.2 — Lifecycle Event Engine

**File**: `packages/cdm/src/lifecycle.ts`

State machine for CDM lifecycle events, built on the cell engine:

```typescript
class CDMLifecycleEngine {
  private cellEngine: GameCellEngine;      // reuses Phase 26 wrapper (or direct WASM)

  /** Execute a lifecycle event — validates policy, transitions state, creates audit cell */
  executeEvent(
    product: CDMProduct,
    event: CDMLifecycleEvent,
    authorization: Uint8Array              // capability cell proving party has rights
  ): Result<CDMProduct, LifecycleError>;

  /** Novation — transfer trade from one counterparty to another */
  novate(
    product: CDMProduct,
    oldParty: CDMPartyRole,
    newParty: CDMPartyRole,
    novationAgreement: Uint8Array          // signed capability cell
  ): Result<CDMProduct, NovationError>;

  /** Partial termination — reduce notional (AFFINE partial consume) */
  partialTerminate(
    product: CDMProduct,
    reductionAmount: number,
    authorization: Uint8Array
  ): Result<CDMProduct, TerminationError>;

  /** Close-out netting — compute net obligations across a portfolio */
  closeOutNet(
    products: CDMProduct[],
    defaultingParty: CDMPartyRole,
    valuationAgent: CDMPartyRole
  ): Result<CloseOutResult, CloseOutError>;

  /** Get event history — traverse the cell DAG */
  eventHistory(product: CDMProduct): CDMLifecycleEvent[];
}
```

**Event execution flow**:
1. Validate the authorization capability cell (does the party hold the right token?)
2. Evaluate the event's policy (compiled Lisp → opcodes → 2-PDA)
3. Execute the state transition on the product cell
4. Create a new product cell referencing the previous state (DAG append)
5. If regulatory reporting required: create a report cell and link it
6. Return the updated product

**Novation flow** (maps to Phase 17 transfer protocol):
1. Old counterparty signs a transfer authorization (capability cell)
2. New counterparty signs acceptance (capability cell)
3. Cell engine executes atomic transfer: product cell's party reference changes
4. New cell created with updated party roster and DAG link to pre-novation state
5. Both parties receive confirmation cells

---

### D28.3 — Regulatory Reporting Cells

**File**: `packages/cdm/src/regulatory.ts`

Auto-generated reporting objects for trade lifecycle events:

```typescript
/** Regulatory report as a semantic object */
interface RegulatoryReport {
  cellId: string;
  regime: 'CFTC' | 'EMIR' | 'MAS' | 'JFSA' | 'ASIC';
  reportType: 'trade-report' | 'valuation-report' | 'margin-report' | 'position-report';
  uti: string;                             // Unique Transaction Identifier
  usi?: string;                            // Unique Swap Identifier (CFTC)
  leiReportingParty: string;               // Legal Entity Identifier
  leiCounterparty: string;
  productTaxonomy: string;                 // ISDA product taxonomy string
  eventTimestamp: string;
  effectiveDate: string;
  economicTermsSummary: Record<string, unknown>;
  sourceEventCell: string;                 // cell ID of the lifecycle event that triggered this report
  linearity: 'RELEVANT';                   // reports must be kept, cannot be destroyed
}

class RegulatoryReportGenerator {
  /** Generate reports for a lifecycle event based on applicable regimes */
  generate(event: CDMLifecycleEvent, product: CDMProduct): RegulatoryReport[];

  /** Determine which regimes apply based on party jurisdictions */
  applicableRegimes(product: CDMProduct): Array<'CFTC' | 'EMIR' | 'MAS' | 'JFSA' | 'ASIC'>;

  /** Format report for submission (regime-specific XML/JSON) */
  format(report: RegulatoryReport, regime: string): string;
}
```

- Reports are RELEVANT cells — they must be kept and cannot be destroyed. This is linearity enforcement for regulatory compliance.
- Each report references the source event cell, creating a verifiable audit trail.
- UTI/USI generation follows ISDA's identifier standards.
- Report formatting is regime-specific but the semantic object is regime-agnostic.

---

### D28.4 — ISDA Master Agreement Policies (Lisp)

**File**: `packages/cdm/src/policies/`

Key ISDA Master Agreement clauses as compiled Lisp policies:

```lisp
;; Section 2(a)(iii) — Condition precedent to payment
;; No Event of Default has occurred with respect to the counterparty
(define-policy payment-condition-precedent
  :subject paying-party
  :action make-payment
  :constraint (and
    (not (= counterparty-default-status "defaulted"))
    (not (= counterparty-default-status "potential-default"))
    (time-before payment-due-date))
  :linearity LINEAR)

;; Section 5 — Events of Default
;; Failure to pay within grace period triggers default
(define-policy failure-to-pay-default
  :subject calculation-agent
  :action declare-default
  :constraint (and
    (= payment-status "overdue")
    (time-after (+ payment-due-date grace-period))
    (> overdue-amount threshold-amount))
  :linearity LINEAR)

;; Section 6 — Early Termination
;; Close-out netting upon default
(define-policy close-out-netting
  :subject non-defaulting-party
  :action close-out
  :constraint (and
    (= counterparty-default-status "defaulted")
    (has-capability 7))                    ;; capability 7 = "close-out rights"
  :linearity LINEAR)

;; Section 11 — Transfer
;; No transfer without prior written consent
(define-policy transfer-consent
  :subject transferring-party
  :action novate
  :constraint (and
    (has-capability 8)                     ;; capability 8 = "transfer consent"
    (not (= new-party-credit-rating "below-threshold")))
  :linearity LINEAR)

;; Credit Support Annex — Margin posting
;; Variation margin within T+1, initial margin per schedule
(define-policy variation-margin
  :subject posting-party
  :action post-margin
  :constraint (and
    (= margin-type "variation")
    (time-before (+ valuation-date "P1D"))
    (>= margin-amount margin-call-amount))
  :linearity LINEAR)
```

- Each policy compiles to capability cells via Phase 21
- Policies can be bound to product types in the extension config
- The calculation agent evaluates policies during lifecycle events
- Dispute resolution uses Phase 9.5's Ballot/Dispute objects

**Predicate model**: Policies use two forms:
1. **Simple field comparison**: `(= clearing-status "uncleared")` — compiles to `OP_LOADFIELD` + `OP_EQUAL`. Used when the check is a direct field value match.
2. **Host function predicate**: `(payment-overdue?)`, `(grace-period-expired?)` — compiles to `push "payment-overdue?" OP_CALLHOST`. Used when the check involves calculations, time comparisons, or complex state lookups.

Both forms read from the frozen evaluation context. Domain-specific host function predicates MUST be registered via `HostFunctionRegistry.register()` in `packages/cdm/src/host-functions.ts`.

**File**: `packages/cdm/src/host-functions.ts` (new)

Register CDM-domain predicates as host functions:

```typescript
export function registerCDMHostFunctions(registry: HostFunctionRegistry): void {
  registry.register('counterparty-in-default?', (ctx) =>
    ctx.counterpartyStatus === 'defaulted' || ctx.counterpartyStatus === 'potential-default' ? 1 : 0);
  registry.register('payment-overdue?', (ctx) =>
    isOverdue(ctx.paymentDueDate as string, ctx.currentDate as string) ? 1 : 0);
  registry.register('grace-period-expired?', (ctx) =>
    isGracePeriodExpired(ctx.paymentDueDate as string, ctx.gracePeriod as string, ctx.currentDate as string) ? 1 : 0);
  registry.register('clearing-status?', (ctx) =>
    ctx.clearingStatus as string === ctx._currentValue ? 1 : 0);
  registry.register('product-class-eq?', (ctx) =>
    ctx.productClass as string === ctx._currentValue ? 1 : 0);
  registry.register('credit-rating-below-threshold?', (ctx) =>
    isBelowThreshold(ctx.creditRating as string, ctx.ratingThreshold as string) ? 1 : 0);
}
```

Wire into `CDMLifecycleEngine` initialization and call `registry.setContext()` with trade state before each policy evaluation.

---

### D28.5 — CDM-FpML Bridge

**File**: `packages/cdm/src/bridge/`

Import/export between CDM's native format and Semantos cells:

```typescript
class CDMBridge {
  /** Import a CDM JSON product into a semantic cell */
  importProduct(cdmJson: Record<string, unknown>): CDMProduct;

  /** Export a semantic cell as CDM JSON */
  exportProduct(product: CDMProduct): Record<string, unknown>;

  /** Import a FpML document into semantic cells */
  importFpML(fpmlXml: string): CDMProduct[];

  /** Export semantic cells as FpML */
  exportFpML(products: CDMProduct[]): string;

  /** Import a CDM lifecycle event */
  importEvent(cdmEventJson: Record<string, unknown>): CDMLifecycleEvent;

  /** Export a lifecycle event as CDM JSON */
  exportEvent(event: CDMLifecycleEvent): Record<string, unknown>;
}
```

- CDM JSON follows the ISDA CDM schema (Rosetta DSL output)
- FpML is the older XML standard — still widely used for trade confirmation
- Import creates cells; export reads cells. Round-trip fidelity is required.
- Unknown fields in CDM JSON are preserved in the cell's metadata payload.

---

### D28.6 — Shell Integration

**File**: `packages/cdm/src/cli/`

Shell commands for CDM operations via the semantic shell:

```bash
semantos cdm import trade.json
  → Imports CDM JSON, creates product cell, returns cell ID

semantos cdm event execute --product <cellId> --type confirmation
  → Executes lifecycle event, validates policies, returns new state

semantos cdm novate --product <cellId> --from <partyA> --to <partyB>
  → Executes novation, transfers ownership, returns new cell ID

semantos cdm report --product <cellId> --regime CFTC
  → Generates regulatory report cell, returns report

semantos cdm history --product <cellId>
  → Shows lifecycle event DAG

semantos cdm portfolio --party <partyId>
  → Lists all products for a party with current states

semantos cdm netting --party <defaultingParty> --portfolio <ids...>
  → Computes close-out netting across a portfolio
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Product Cell Creation (TypeScript)

```typescript
describe("D28.1 — CDM product cells", () => {
  test("fixed-float swap creates LINEAR cell with correct taxonomy", () => {});
  test("economic terms round-trip through serialize/deserialize", () => {});
  test("party roles map to identity facets with capabilities", () => {});
  test("product taxonomy string matches ISDA classification", () => {});
});
```

### Test 2: Lifecycle Events (TypeScript)

```typescript
describe("D28.2 — Lifecycle transitions", () => {
  test("execution event transitions proposed → executed", () => {});
  test("confirmation event transitions executed → confirmed", () => {});
  test("novation transfers product to new counterparty", () => {});
  test("partial termination reduces notional (AFFINE partial consume)", () => {});
  test("full termination destroys product cell (LINEAR consume)", () => {});
  test("event without authorization capability is rejected", () => {});
  test("event history is traversable DAG from latest to execution", () => {});
});
```

### Test 3: Regulatory Reporting (TypeScript)

```typescript
describe("D28.3 — Regulatory reports", () => {
  test("CFTC report generated for USD swap execution", () => {});
  test("EMIR report generated for EUR swap with EU counterparty", () => {});
  test("report is RELEVANT linearity — cannot be destroyed", () => {});
  test("report references source event cell", () => {});
  test("UTI format follows ISDA standard", () => {});
});
```

### Test 4: ISDA Policies (TypeScript)

```typescript
describe("D28.4 — ISDA Master Agreement policies", () => {
  test("payment blocked when counterparty in default (Section 2(a)(iii))", () => {});
  test("failure to pay triggers default after grace period (Section 5)", () => {});
  test("close-out netting requires non-defaulting party capability (Section 6)", () => {});
  test("novation blocked without transfer consent capability (Section 11)", () => {});
  test("variation margin must be posted within T+1 (CSA)", () => {});
});
```

### Test 5: CDM Bridge (TypeScript)

```typescript
describe("D28.5 — Import/export", () => {
  test("CDM JSON round-trip preserves all fields", () => {});
  test("FpML import creates correct product cells", () => {});
  test("unknown CDM fields preserved in metadata", () => {});
  test("exported CDM JSON validates against ISDA schema", () => {});
});
```

### Test 6: Full Trade Lifecycle (Integration)

```typescript
describe("D28 — Full lifecycle: vanilla IRS", () => {
  test("execute → confirm → clear → settle → terminate — 5 event cells in DAG", () => {
    // Creates a vanilla interest rate swap
    // Executes 5 lifecycle events
    // Verifies DAG contains 5 event cells + 1 initial product cell
    // Verifies each event has regulatory report cells
    // Verifies terminated product cell is consumed (LINEAR)
    // Verifies all reports still accessible (RELEVANT linearity)
  });
});
```

---

## Phase Completion Criteria

You are **done with Phase 28** when ALL of the following are true:

1. `packages/cdm/` exists with types, lifecycle engine, regulatory reporting, policies, and bridge
2. CDM product types map to three-axis taxonomy coordinates
3. Lifecycle events are cell state transitions with DAG persistence
4. Novation uses Phase 17 transfer protocol (chain-of-custody)
5. ISDA Master Agreement clauses compile via Phase 21 Lisp compiler
6. Regulatory reports are RELEVANT cells (cannot be destroyed)
7. CDM JSON import/export round-trips correctly
8. Full trade lifecycle integration test passes (5 events, DAG, reports)
9. Shell commands work via `semantos cdm` verb
10. All gate tests pass: `bun test packages/__tests__/phase28-gate.test.ts`
11. `bun run check` passes
12. `bun run build` succeeds
13. No React imports in cdm package
14. Errata sprint complete with `docs/prd/PHASE-28-ERRATA.md`
15. All commits follow `phase-28/D28.N:` naming convention
16. Branch is `phase-28-isda-cdm`

---

## What NOT to Do

1. **Do NOT implement a pricing engine.** Valuation (Black-Scholes, Monte Carlo) is a separate concern. This phase handles lifecycle and structure.
2. **Do NOT implement real-time market data feeds.** Rate resets use static test data.
3. **Do NOT implement a full regulatory submission pipeline.** Report generation yes, submission to DTCC/trade repositories no.
4. **Do NOT implement a matching engine or order book.** Trade execution is assumed to have happened bilaterally.
5. **Do NOT implement a full FpML parser.** Support the subset needed for vanilla IRS, CDS, and FX forwards.
6. **Do NOT bypass the cell engine for lifecycle transitions.** Every event goes through the 2-PDA.
7. **Do NOT implement multi-currency netting.** Single-currency close-out netting only for now.
8. **Do NOT modify the cell engine or Lisp compiler.** The CDM package consumes existing infrastructure. Domain-specific predicates (e.g., `counterparty-in-default?`, `payment-overdue?`, `clearing-status?`) are registered as host functions via Phase 25.5's `HostFunctionRegistry` and dispatched through `OP_CALLHOST`. Do NOT add opcodes or modify the compiler.

---

## Next Phase

Phase 28 output feeds into future work on **smart legal contracts** (ISDA clauses as executable policies on-chain), **multi-party clearing** (CCP as a governance node in the Plexus DAG), and **real-time risk monitoring** (embedding-based anomaly detection on trade portfolios using Phase 23 infrastructure).
