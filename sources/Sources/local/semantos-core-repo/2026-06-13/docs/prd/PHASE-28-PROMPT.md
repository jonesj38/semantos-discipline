---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-28-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.671037+00:00
---

# Phase 28 Execution Prompt — ISDA Common Domain Model Integration

> Paste this prompt into a fresh session to execute Phase 28.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 17 built the transfer protocol for LINEAR objects with chain-of-custody. Phase 18 built the metering control plane with payment channel FSMs, evidence chains, and dispute resolution via Ballot/Resolution. Phase 21 built the Lisp policy compiler. Phase 25.5 built the host function dispatch infrastructure — `OP_CALLHOST` (0xD0) in the Zig WASM engine and `HostFunctionRegistry` in TypeScript — so domain-specific predicates can be evaluated by the cell engine without adding opcodes. Phase 9.5 built governance types (Dispute, Ballot, Stake, Resolution).

This phase maps ISDA's Common Domain Model (CDM) onto Semantos semantic objects. CDM is an open-source, machine-readable model for financial products and their lifecycle events — how derivatives, securities, and lending transactions are represented, how lifecycle events transform them, and how regulatory reporting obligations attach.

CDM is already trying to be what Semantos IS: a universal semantic layer where objects carry their own type information, lifecycle rules, and audit trails. The difference is that CDM is a specification. Semantos is a runtime that enforces CDM's constraints at the opcode level.

The mapping is natural:

- **CDM Product** → Semantic object (LINEAR — a trade exists once, no duplication)
- **CDM Event** → State transition on a cell (opcode sequence on the 2-PDA)
- **CDM Party** → Identity facet (Phase 8.5) with capability tokens
- **CDM Lineage** → Cell DAG (each event creates a new cell referencing the previous)
- **CDM Qualification** → Lisp policy compiled to capability cell

The critical insight: a novation IS a Phase 17 transfer. A partial termination IS an AFFINE consumption. A netting set IS a collection of cells with a governance policy. The linearity modes map directly to how derivatives actually work — these aren't metaphors.

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRD — your requirements):
- `docs/prd/PHASE-28-ISDA-CDM.md` — Full spec with D28.1–D28.6, gate tests, completion criteria

**Read second** (the transfer and governance systems you build on):
- `src/kernel/transfer.ts` — Transfer protocol (novation maps to this)
- `src/types/governance.ts` — Ballot, Dispute, Resolution (dispute resolution maps to this)
- `src/types/capability.ts` — Capability tokens (party entitlements map to this)
- `packages/loom/src/types/evidence.ts` — Evidence chain (trade lineage maps to this)

**Read third** (the identity and flow systems):
- `packages/loom/src/services/identity/` — Identity facets (CDM parties map to these)
- `packages/loom/src/services/FlowRunner.ts` — Flow step execution with guards (lifecycle events)
- `packages/loom/src/services/FlowRegistry.ts` — Flow resolution (lifecycle flow registration)
- `packages/loom/src/config/extensionConfig.ts` — Object type definitions (add CDM product types here)

**Read fourth** (the host function dispatch and Lisp policy system):
- `packages/cell-engine/bindings/host-functions.ts` — HostFunctionRegistry class (register CDM-domain predicates here)
- `packages/cell-engine/bindings/builtin-host-functions.ts` — Built-in host functions (pattern for registering domain predicates)
- `packages/cell-engine/src/opcodes/hostcall.zig` — OP_CALLHOST implementation (0xD0)
- `packages/shell/src/lisp/compiler.ts` — LispCompiler (ISDA clauses compile through this; `(predicate?)` sugar compiles to `push "predicate?" OP_CALLHOST`)
- `packages/shell/src/lisp/packer.ts` — Capability cell packing

**Read fifth** (the DAG persistence layer):
- `packages/plexus-vendor-sdk/src/graph/` — DAG persistence (trade event history)

**Read sixth** (the metering system — payment flow patterns):
- `packages/metering/src/` — Payment channel FSM (margin posting, settlement patterns)

**Read seventh** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-28-isda-cdm`. Commits as `phase-28/D28.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. TRADES ARE LINEAR — NO EXCEPTIONS

A derivative trade is a LINEAR cell. It exists once. It cannot be duplicated. Novation is a transfer (Phase 17), not a copy. Termination is consumption. Partial termination is AFFINE partial consumption. If you create a CDMProduct that is not LINEAR, justify it in the errata or you have a bug.

### 2. REGULATORY REPORTS ARE RELEVANT — NO DELETION

Regulatory report cells are RELEVANT linearity. They MUST be kept. They CANNOT be destroyed. Attempting to consume a RELEVANT cell is rejected by the cell engine at the opcode level. This is not a business rule you enforce — it's a cell engine property.

### 3. LIFECYCLE EVENTS GO THROUGH THE CELL ENGINE

A lifecycle event (execution, novation, termination) is NOT a method call that mutates an object. It is a state transition executed on the 2-PDA. The cell engine evaluates the authorization policy, transitions the state, and produces a new cell. Your code orchestrates; the cell engine enforces.

### 4. NOVATION IS A PHASE 17 TRANSFER

Do NOT implement a separate novation protocol. Novation IS `transfer()` from Phase 17 with CDM-specific metadata. The counterparty changes. The capability chain updates. The DAG records the event. Same protocol, different domain.

### 5. DISPUTES USE EXISTING BALLOT/RESOLUTION

Do NOT implement a `CDMDisputeEngine`. When a trade is disputed, create a Dispute object and a Ballot object using the existing Phase 9.5 governance types. Same flow as payment channel disputes in Phase 18.

### 6. POLICIES ARE ISDA CLAUSES, NOT CODE

ISDA Master Agreement clauses (Section 2(a)(iii), Section 5, Section 6, Section 11, CSA margin rules) are Lisp policies that compile to capability cells. They are NOT TypeScript if-statements. The Lisp compiler (Phase 21) handles compilation. The cell engine handles evaluation.

### 6.5. DOMAIN PREDICATES USE HOST FUNCTIONS — NOT HARDCODED LOGIC

CDM-domain predicates like `counterparty-in-default?`, `payment-overdue?`, `clearing-status?`, `credit-rating-below-threshold?` are **host functions** registered via Phase 25.5's `HostFunctionRegistry`. In Lisp policies, bare symbols ending in `?` compile to `push "name" OP_CALLHOST`. Do NOT hardcode CDM-specific logic in TypeScript if-statements. Do NOT add new opcodes. Register predicates with `registry.register("counterparty-in-default?", fn)` and the cell engine dispatches them via `OP_CALLHOST` (0xD0).

### 7. CDM JSON IS NOT THE SOURCE OF TRUTH

CDM JSON is an import/export format. The source of truth is the cell. `importProduct()` creates cells from CDM JSON. `exportProduct()` reads cells and produces CDM JSON. The cells are authoritative. CDM JSON is a view.

### 8. DO NOT IMPLEMENT PRICING OR RISK

No Black-Scholes, no Monte Carlo, no Greeks, no VaR. This phase handles product structure and lifecycle. Valuation is a separate concern entirely.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify prerequisites

```bash
# Phase 17 transfer protocol exists
ls src/kernel/transfer.ts

# Phase 9.5 governance types exist
ls src/types/governance.ts

# Phase 8.5 identity facets exist
ls packages/loom/src/services/identity/

# Phase 25.5 host function dispatch exists
ls packages/cell-engine/bindings/host-functions.ts
ls packages/cell-engine/src/opcodes/hostcall.zig

# Phase 21 Lisp compiler exists
ls packages/shell/src/lisp/compiler.ts
ls packages/shell/src/lisp/packer.ts

# Phase 18 metering types exist (pattern reference)
ls packages/metering/src/

# Evidence chain types exist
ls packages/loom/src/types/evidence.ts

# DAG persistence exists
ls packages/plexus-vendor-sdk/src/graph/

# FlowRunner exists
ls packages/loom/src/services/FlowRunner.ts

# Full build passes
bun run check
bun run build
```

All must exist and pass. If anything fails, STOP.

### 0.3 Create Phase 28 branch

```bash
git checkout -b phase-28-isda-cdm
```

---

## Step 1: CDM Type Mapping (D28.1)

Create `packages/cdm/src/types.ts`.

**Requirements**:

Map CDM concepts to Semantos primitives:

- `CDMProduct` — semantic object with taxonomy coordinates:
  - WHAT axis: `CDMProductType` (rates.swap.fixed-float, credit.cds.single-name, equity.option.vanilla.european, fx.forward.deliverable, etc.)
  - HOW axis: `CDMLifecycleState` (proposed, executed, confirmed, cleared, settled, novated, partially-terminated, terminated, defaulted, close-out)
  - WHY axis: regulatory tags (CFTC, EMIR, hedging, speculation, etc.)
  - Linearity: always `LINEAR`

- `CDMLifecycleEvent` — state transition specification:
  - `CDMEventType` (execution, confirmation, clearing, settlement, novation, partial-termination, full-termination, rate-reset, payment, margin-call, default, close-out-netting)
  - before/after lifecycle states
  - authorization capability cell reference
  - auto-generated regulatory report cell reference

- `CDMPartyRole` — maps to identity facet + capability set:
  - Roles: buyer, seller, clearing-member, ccp, calculation-agent, reporting-party
  - Each role has a capability number set (what actions they can authorize)

- `EconomicTerms` — product payload:
  - notional, effectiveDate, terminationDate, fixedRate, floatingRateIndex, paymentFrequency, dayCountConvention, businessDayConvention

- `RegulatoryReport` — RELEVANT cell for compliance:
  - regime, reportType, UTI, USI, LEI, product taxonomy, event reference

Create `packages/cdm/package.json` with name `@semantos/cdm`, dependencies on `@semantos/protocol-types`, `@semantos/constants`, loom services.

**Commit**: `phase-28/D28.1: CDM type mapping — products, events, parties, economics, regulatory reports`

---

## Step 2: Lifecycle Event Engine (D28.2)

Create `packages/cdm/src/lifecycle.ts`.

**Requirements**:

- `CDMLifecycleEngine` class:
  - `executeEvent(product, event, authorization)` — validates capability, evaluates policy, transitions state, creates audit cell, generates regulatory report
  - `novate(product, oldParty, newParty, novationAgreement)` — wraps Phase 17 `transfer()` with CDM semantics
  - `partialTerminate(product, reductionAmount, authorization)` — AFFINE partial consumption of notional
  - `closeOutNet(products, defaultingParty, valuationAgent)` — compute net obligations across a portfolio
  - `eventHistory(product)` — traverse the cell DAG to reconstruct lifecycle

**Event execution flow** (implement exactly):
1. Validate authorization capability cell (does the party hold the right token?)
2. Load and evaluate the event's compiled Lisp policy on the 2-PDA
3. Execute the state transition on the product cell
4. Create new product cell referencing previous state (DAG append)
5. Call RegulatoryReportGenerator for applicable regimes
6. Return updated product with new cellId and event history link

**Novation flow** (maps directly to Phase 17 transfer):
1. Old counterparty signs transfer authorization (capability cell)
2. New counterparty signs acceptance (capability cell)
3. Call `transfer()` from `src/kernel/transfer.ts` — product cell's party roster changes
4. New cell created with updated parties and DAG link to pre-novation state
5. Both parties receive confirmation cells (evidence chain patches)

**Commit**: `phase-28/D28.2: lifecycle event engine with novation, partial termination, close-out netting`

---

## Step 3: Regulatory Reporting (D28.3)

Create `packages/cdm/src/regulatory.ts`.

**Requirements**:

- `RegulatoryReportGenerator` class:
  - `generate(event, product)` — produces report cells for each applicable regime
  - `applicableRegimes(product)` — determines which regimes apply based on party jurisdictions
  - `format(report, regime)` — regime-specific output (CFTC Part 43, EMIR SFTR, etc.)

- `RegulatoryReport` cell properties:
  - Linearity: `RELEVANT` — cannot be destroyed
  - Links to source event cell (verifiable audit trail)
  - UTI generation following ISDA standard format
  - LEI references for reporting party and counterparty

**Regime determination logic**:
- USD-denominated with US counterparty → CFTC
- EUR-denominated or EU counterparty → EMIR
- SGD or Singapore counterparty → MAS
- JPY or Japan counterparty → JFSA
- AUD or Australia counterparty → ASIC
- Multiple regimes can apply to one event

**Commit**: `phase-28/D28.3: regulatory report generator with RELEVANT cells, UTI, regime determination`

---

## Step 4: ISDA Master Agreement Policies (D28.4)

Create `packages/cdm/src/policies/`.

**Requirements**:

Write Lisp policies for key ISDA Master Agreement clauses:

- `payment-condition-precedent.policy` — Section 2(a)(iii): no payment if counterparty in default
- `failure-to-pay-default.policy` — Section 5: failure to pay within grace period triggers default
- `close-out-netting.policy` — Section 6: non-defaulting party can close out upon default
- `transfer-consent.policy` — Section 11: no novation without prior consent
- `variation-margin.policy` — CSA: variation margin within T+1

Each policy:
1. Is authored as a `.policy` Lisp file
2. Compiles via Phase 21 `LispCompiler.compilePolicy()`
3. Packs via `packCapabilityCell()`
4. Binds to CDM product types in the extension config

Create `packages/cdm/src/policies/compiler.ts` — thin wrapper that loads `.policy` files and compiles them to capability cells.

**CRITICAL**: Create `packages/cdm/src/host-functions.ts` and register all CDM-domain predicates with `HostFunctionRegistry.register()`. The evaluation context (set via `registry.setContext()` before each policy evaluation) carries current trade state: counterparty status, payment dates, clearing status, economic terms, etc. Predicates read from this frozen context and return 0/1.

Simple field comparisons (`= clearing-status "uncleared"`) compile to `OP_LOADFIELD` + `OP_EQUAL` and are handled by the existing compiler. Complex predicates that involve calculations or time logic (`payment-overdue?`, `grace-period-expired?`) MUST be host functions.

**Commit**: `phase-28/D28.4: ISDA Master Agreement policies — Sections 2(a)(iii), 5, 6, 11, CSA`

---

## Step 5: CDM-FpML Bridge (D28.5)

Create `packages/cdm/src/bridge/`.

**Requirements**:

- `CDMBridge` class:
  - `importProduct(cdmJson)` — creates semantic cells from CDM JSON
  - `exportProduct(product)` — reads cells, produces CDM JSON
  - `importFpML(fpmlXml)` — creates cells from FpML XML (subset: vanilla IRS, CDS, FX forwards)
  - `exportFpML(products)` — reads cells, produces FpML XML
  - `importEvent(cdmEventJson)` — creates lifecycle event from CDM event JSON
  - `exportEvent(event)` — reads event, produces CDM JSON

**Round-trip fidelity**: `exportProduct(importProduct(json))` must produce JSON that validates against the CDM schema and preserves all fields. Unknown fields in CDM JSON are preserved in the cell's metadata payload (not silently dropped).

FpML support is a subset — vanilla interest rate swaps, single-name CDS, and deliverable FX forwards. Not full FpML.

**Commit**: `phase-28/D28.5: CDM-FpML bridge with import/export and round-trip fidelity`

---

## Step 6: Shell Integration (D28.6)

Create `packages/cdm/src/cli/`.

**Requirements**:

Wire CDM commands into the semantic shell:

```bash
semantos cdm import trade.json              → import CDM JSON, create product cell
semantos cdm event execute --product <id> --type confirmation  → lifecycle event
semantos cdm novate --product <id> --from <partyA> --to <partyB>  → novation
semantos cdm report --product <id> --regime CFTC   → generate regulatory report
semantos cdm history --product <id>          → lifecycle event DAG
semantos cdm portfolio --party <partyId>     → all products for a party
semantos cdm netting --party <id> --portfolio <ids...>  → close-out netting
```

Each command uses the `CDMLifecycleEngine` and `CDMBridge` — no direct cell manipulation in the CLI layer.

**Commit**: `phase-28/D28.6: shell integration with cdm import, event, novate, report, history, portfolio, netting`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase28-gate.test.ts`.

### Product Cell Tests (T1–T4)

```typescript
describe("D28.1 — CDM product cells", () => {
  // T1: fixed-float swap creates LINEAR cell with taxonomy 'rates.swap.fixed-float'
  // T2: economic terms round-trip through serialize/deserialize
  // T3: party roles map to identity facets with correct capabilities
  // T4: product taxonomy string matches ISDA classification
});
```

### Lifecycle Event Tests (T5–T11)

```typescript
describe("D28.2 — Lifecycle transitions", () => {
  // T5: execution event transitions proposed → executed
  // T6: confirmation event transitions executed → confirmed
  // T7: novation transfers product to new counterparty via Phase 17 transfer
  // T8: partial termination reduces notional (AFFINE partial consume)
  // T9: full termination destroys product cell (LINEAR consume)
  // T10: event without authorization capability is rejected
  // T11: event history is traversable DAG from latest to execution
});
```

### Regulatory Reporting Tests (T12–T16)

```typescript
describe("D28.3 — Regulatory reports", () => {
  // T12: CFTC report generated for USD swap execution
  // T13: EMIR report generated for EUR swap with EU counterparty
  // T14: report is RELEVANT linearity — consume attempt rejected by engine
  // T15: report references source event cell via cellId
  // T16: UTI format follows ISDA standard
});
```

### ISDA Policy Tests (T17–T21)

```typescript
describe("D28.4 — ISDA policies", () => {
  // T17: payment blocked when counterparty in default (Section 2(a)(iii))
  // T18: failure to pay triggers default after grace period (Section 5)
  // T19: close-out netting requires non-defaulting party capability (Section 6)
  // T20: novation blocked without transfer consent capability (Section 11)
  // T21: variation margin must be posted within T+1 (CSA)
});
```

### Bridge Tests (T22–T25)

```typescript
describe("D28.5 — Import/export", () => {
  // T22: CDM JSON round-trip preserves all fields
  // T23: FpML import creates correct product cells
  // T24: unknown CDM fields preserved in metadata
  // T25: exported CDM JSON validates against ISDA schema structure
});
```

### Full Lifecycle Integration (T26)

```typescript
describe("D28 — Full lifecycle: vanilla IRS", () => {
  // T26: execute → confirm → clear → settle → terminate
  //   - Creates vanilla interest rate swap
  //   - Executes 5 lifecycle events
  //   - DAG contains 5 event cells + 1 initial product cell
  //   - Each event has regulatory report cells
  //   - Terminated product cell is consumed (LINEAR)
  //   - All reports still accessible (RELEVANT linearity)
});
```

### Anti-Lock Tests (T27–T28)

```typescript
describe("D28 — Anti-lock", () => {
  // T27: no React imports in cdm package
  // T28: no direct cell engine modifications (only consumes existing APIs)
});
```

**Commit**: `phase-28/T1-T28: full gate test suite — products, lifecycle, regulatory, ISDA policies, bridge, integration`

---

## Step 8: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Walk through a complete vanilla IRS lifecycle: execution → confirm → clear → rate reset → settle → terminate. Verify every event cell and report cell.
2. Walk through a novation: verify the product's counterparty actually changes and the DAG records both parties
3. Walk through a close-out netting: verify net obligation calculation across 5 trades
4. Verify that RELEVANT report cells truly cannot be consumed (cell engine rejects at opcode level)
5. Verify CDM JSON round-trip with a complex product (exotic option with multiple legs)
6. Verify FpML import with a real-world FpML sample (ISDA publishes these)
7. Check that policies reference real CDM field names (not made-up fields)
8. Check that novation uses Phase 17 transfer — not a separate implementation
9. Check that disputes use Phase 9.5 Ballot/Resolution — not a separate implementation
10. Check that all lifecycle events go through the cell engine — not TypeScript state mutation
11. Write errata doc as `docs/prd/PHASE-28-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/cdm/` exists with types, lifecycle engine, regulatory, policies, bridge, CLI
- [ ] CDM product types map to three-axis taxonomy coordinates
- [ ] Products are LINEAR cells — creation, novation, termination verified
- [ ] Lifecycle events are cell state transitions with DAG persistence
- [ ] Novation uses Phase 17 transfer protocol (not a separate implementation)
- [ ] ISDA Master Agreement clauses compile via Phase 21 Lisp compiler
- [ ] Regulatory reports are RELEVANT cells (consume attempt rejected by engine)
- [ ] CDM JSON import/export round-trips with full field fidelity
- [ ] FpML import works for vanilla IRS, CDS, FX forwards
- [ ] Full lifecycle integration test passes (5 events + reports)
- [ ] Shell commands work via `semantos cdm` verb
- [ ] Tests T1–T28 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in cdm package
- [ ] Errata sprint complete with `docs/prd/PHASE-28-ERRATA.md`
- [ ] All commits follow `phase-28/D28.N:` naming convention
- [ ] Branch is `phase-28-isda-cdm`

---

## What NOT to Do

1. Do NOT implement a pricing engine — no Black-Scholes, Monte Carlo, Greeks
2. Do NOT implement real-time market data feeds — use static test data
3. Do NOT implement a full regulatory submission pipeline — report generation only
4. Do NOT implement a matching engine or order book — bilateral execution assumed
5. Do NOT implement a full FpML parser — subset only (vanilla IRS, CDS, FX forwards)
6. Do NOT bypass the cell engine — every lifecycle event goes through the 2-PDA
7. Do NOT implement multi-currency netting — single-currency close-out only
8. Do NOT modify the cell engine, Lisp compiler, or transfer protocol. CDM-domain predicates are registered as host functions via Phase 25.5's `HostFunctionRegistry` — do NOT add opcodes or modify the compiler

---

## After Phase 28: Finance Is Semantic Objects

After Phase 28, a derivative trade is a semantic object with the same properties as every other Semantos object: typed identity, linearity enforcement, capability-gated actions, compiled policy evaluation, DAG-linked audit trail, and governance through ballots.

The compression gradient applies to finance the same way it applies to trades-services, games, or any other domain:

```
Legal counsel: "counterparty must post initial margin within T+1"
    ↓ (policy authoring)
(define-policy initial-margin ...)
    ↓ (Lisp compiler)
Forth words → capability cell
    ↓ (cell engine)
2-PDA evaluates → margin call valid or rejected
    ↓ (regulatory)
RELEVANT report cell created → immutable audit trail
```

Same intent. Same pipeline. Different domain. That's the thesis.
