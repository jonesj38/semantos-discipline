---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-32-BILLS-OF-LADING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.705868+00:00
---

# Phase 32 — Bills of Lading Extension Grammar

**Version**: 0.1 (draft)
**Date**: April 2026
**Status**: Exploratory — independent track (can start after Phase 29.5; parallel to Phase 28 CDM and Phase 29 SCADA)
**Duration**: 8 weeks (with 40% buffer: 11.2 weeks)
**Prerequisites**: **Phase 29.5 complete (kernel enforcement sweep — without it, every "rejected at the opcode level" claim below is aspirational).** Phase 17 complete (transfer + recovery — chain-of-custody for LINEAR objects, which *is* negotiable-BoL endorsement). Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry — host function dispatch for domain predicates like `port-code?`, `hs-code?`, `sanctions-ok?`, `ucp600-clean?`). Phase 21 recommended (Lisp policy compiler for contractual / UCP / Hague-Visby clause authoring). Phase 18 recommended (metering control plane for freight and L/C payment flows).
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-32-bills-of-lading`
**Sibling phases**: Phase 28 (ISDA CDM) · Phase 29 (SCADA) · Phase 29.5 (kernel enforcement sweep, hard prerequisite)

---

## Context

A bill of lading (BoL) is three legal objects fused into one piece of paper: a receipt for goods received by a carrier, a contract of carriage, and — for the negotiable variant — a document of title whose possession IS possession of the cargo. For five centuries the shipping industry has solved the "document of title" problem the same way Semantos solves LINEAR objects: by making the instrument physically unique. One original, endorsed from holder to holder, destroyed on delivery. The reason trade finance still runs on couriered paper in 2026 is that no general-purpose digital substrate has been able to enforce single-instance ownership the way a signed physical document does.

Semantos already does this. The negotiable bill of lading is not a new problem for the runtime — it is arguably the cleanest possible fit for LINEAR cell semantics. Where CDM gave us trades as LINEAR cells and SCADA gave us control commands as LINEAR cells, bills of lading give us *title itself* as a LINEAR cell. Endorsement is novation. Presentation is consumption. Delivery is terminal consumption. Letter-of-credit compliance is a Phase-21 policy against the cell's payload. The IMO/IATA/WCO regulatory layer is the WHY axis.

This phase defines a single extension grammar — `@semantos/bol` — with an abstract core covering every variant of BoL, and mode dialects for ocean, inland (truck/rail), air (AWB), and multimodal (FIATA FBL). The dialects share a state machine, a policy bundle, and a bridge surface; they differ only in their WHAT-axis leaves and a handful of mode-specific fields.

This is not a data-modelling exercise. UN/CEFACT has a data model. DCSA has a data model. IATA ONE Record has a data model. The thing *none* of them have is a runtime that enforces single-instance ownership at the opcode level. That is the deliverable — but only once Phase 29.5 lands, because until then the enforcement happens in a TypeScript shim mirroring the intended opcode semantics, not in the 2-PDA itself.

### Three-Axis Taxonomy for Bills of Lading

```
WHAT (document type):      transport.bol.ocean.negotiable        (to-order, endorsable)
                           transport.bol.ocean.straight          (named consignee, non-negotiable)
                           transport.bol.ocean.seaway            (sea waybill, purely a receipt)
                           transport.bol.ocean.charter-party     (subject to charter terms)
                           transport.bol.inland.truck.straight   (road, PRO number, NMFC)
                           transport.bol.inland.rail             (rail waybill)
                           transport.bol.air.awb.master          (MAWB — carrier to forwarder)
                           transport.bol.air.awb.house           (HAWB — forwarder to shipper)
                           transport.bol.multimodal.fiata-fbl    (FIATA negotiable FBL)
                           transport.bol.abstract                (mode-agnostic core)

HOW (lifecycle state):     drafted → issued → shipped-on-board → in-transit → presented
                                   → discharged → delivered → closed
                           branches: claused · amended · surrendered · telex-released
                                   · lost · disputed · litigated · close-out

WHY (purpose / regime):    commerce.title-transfer               (negotiable instrument)
                           commerce.collateral                   (L/C / trade finance pledge)
                           commerce.insurance                    (marine cargo policy evidence)
                           compliance.customs.export
                           compliance.customs.import
                           compliance.sanctions.ofac
                           compliance.sanctions.eu
                           compliance.imo.imdg                   (maritime dangerous goods)
                           compliance.iata.dgr                   (air dangerous goods)
                           compliance.wco.ahtn                   (WCO harmonised codes)
                           compliance.ucp600                     (letter of credit rules)
                           compliance.hague-visby
                           compliance.hamburg-rules
                           compliance.rotterdam-rules
```

### The Compression Gradient (Trade Domain)

```
Shipping lawyer: "An original bill of lading must be presented at the discharge port
                  before the carrier may release the cargo, unless a telex release has
                  been issued under dual authority of the named holder and carrier."
    ↓ (policy authoring)
(policy present-before-deliver
  :subject carrier
  :action deliver-cargo
  :constraint (or
    (and (holder-presented-original?)
         (= holder-identity (current-endorsee)))
    (and (telex-release-issued?)
         (dual-auth holder carrier)))
  :linearity LINEAR)
    ↓ (Lisp compiler)
"holder-presented-original?" OP_CALLHOST "current-endorsee" OP_LOADFIELD HOLDER-EQ BOOLAND
"telex-release-issued?" OP_CALLHOST "dual-auth" OP_CALLHOST BOOLAND BOOLOR VERIFY
    ↓ (cell engine — Phase 29.5 PolicyRuntime)
2-PDA evaluates → delivery authorized or rejected at opcode level
    ↓ (Plexus — Phase 29.5 AnchorEmitter)
Delivery receipt cell created automatically — BoL LINEAR cell consumed, chain terminated,
anchor tx broadcast with idempotency key sha256(deliveryCellBytes)
```

The same compression pipeline that Phase 28 uses for an ISDA Master Agreement clause and Phase 29 uses for a safety interlock applies without modification here. The BoL phase adds **no new machinery** — it adds only grammar. But the "2-PDA evaluates" and "anchor tx broadcast" arrows are only real once Phase 29.5 has rewired CDM and SCADA onto the kernel path. Until then, BoL would ship with the same TS-shim seam the other two currently carry.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `TYPES:PROTO` | `packages/protocol-types/src/index.ts` | Cell header types, linearity modes — map to BoL / custody / delivery cells |
| `IDENTITY:FACET` | `packages/loom/src/services/identity/` | Identity facets — map to shipper / consignee / carrier / bank roles |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Transfer protocol — maps **exactly** to endorsement of a negotiable BoL |
| `CAPABILITY:TYPES` | `src/types/capability.ts` | Capability tokens — map to "entitled to endorse", "entitled to present", "entitled to surrender" |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | Policy compiler — targets UCP 600, Hague-Visby, IMDG, sanctions clauses |
| `POLICY:RUNTIME` | `packages/policy-runtime/src/` | **Phase 29.5 deliverable — the only code path that runs compiled policies at runtime** |
| `ANCHOR:EMIT` | `packages/policy-runtime/src/anchor-emitter.ts` | **Phase 29.5 deliverable — terminal-event anchor broadcast** |
| `METERING:FSM` | `packages/metering/src/` | Payment channel FSM — map to L/C drawdown + freight settlement |
| `GOVERNANCE:TYPES` | `src/types/governance.ts` | Ballot / Dispute / Resolution — map to GA/demurrage/laytime disputes |
| `TAXONOMY:TREE` | `packages/loom/src/services/IntentTaxonomy.ts` | Taxonomy structure — extend with `transport.bol.*` branches |
| `DAG:PERSIST` | `packages/plexus-vendor-sdk/src/graph/` | DAG persistence — map to endorsement chain + custody trail |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry class — register BoL predicates |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |
| `CDM:TYPES` | `packages/cdm/src/types.ts` | Prior-art reference — cell mapping idiom |
| `CDM:LIFECYCLE` | `packages/cdm/src/lifecycle.ts` | Prior-art reference — transition table idiom |
| `SCADA:TYPES` | `packages/scada/src/types.ts` | Prior-art reference — role capability table, multi-linearity cell family |
| `SCADA:INTERLOCKS` | `packages/scada/src/policies/interlocks.ts` | Prior-art reference — Lisp policy compilation + packing |

---

## Package Layout

```
packages/bol/
├── src/
│   ├── index.ts                       Barrel export
│   ├── types.ts                       Core abstract cell types + factories + type hash
│   ├── lifecycle.ts                   Event engine — delegates all enforcement to PolicyRuntime
│   ├── endorsement.ts                 Negotiable-BoL endorsement chain (wraps Phase 17 transfer)
│   ├── regulatory.ts                  Customs / sanctions / DG declaration cell builders
│   ├── modes/
│   │   ├── ocean.ts                   Ocean BoL specialisation (vessel, ports, containers)
│   │   ├── inland.ts                  Truck / rail specialisation (PRO, NMFC, carrier SCAC)
│   │   ├── air.ts                     Air waybill specialisation (IATA fields, MAWB/HAWB link)
│   │   └── multimodal.ts              FIATA FBL specialisation (leg list)
│   ├── policies/
│   │   ├── compiler.ts                Loads .policy files and compiles via Phase 21
│   │   ├── host-functions.ts          registerBoLHostFunctions(registry) — Phase 29.5 shape
│   │   ├── single-negotiable-instance.policy
│   │   ├── order-bill-endorsement.policy
│   │   ├── straight-bill-no-transfer.policy
│   │   ├── present-before-deliver.policy
│   │   ├── surrender-dual-auth.policy
│   │   ├── letter-of-credit-ucp600.policy
│   │   ├── sanctions-screen.policy
│   │   ├── dangerous-goods-imdg.policy
│   │   ├── dangerous-goods-iata-dgr.policy
│   │   └── clean-on-board.policy
│   ├── bridge/
│   │   ├── edifact.ts                 UN/EDIFACT IFTMIN · IFTMBF · IFTMBC · IFTMCS · CUSDEC
│   │   ├── dcsa.ts                    DCSA eBL 3.0 API (ocean)
│   │   ├── iata-one-record.ts         IATA ONE Record (air)
│   │   ├── fiata-fbl.ts               FIATA FBL negotiable form
│   │   ├── un-cefact-mmt.ts           UN/CEFACT Multi-Modal Transport RDM
│   │   └── x12.ts                     ANSI ASC X12 (204/211/214/304/315/322/110)
│   └── cli/
│       └── commands.ts                Parse-and-route BoL CLI commands
├── demo.ts
├── demo-kernel.ts                     Phase 29.5-style demo printing 2-PDA trace + anchor txid
├── package.json
└── tsconfig.json
```

The same shape as `packages/cdm/` and `packages/scada/`. The only new subdirectory is `modes/` — because BoL is a family of related documents, not a single document. Treating each mode as a dialect of a shared core is the "extension grammar" piece.

---

## Deliverables

### D32.1 — Abstract BoL Core Types

**File**: `packages/bol/src/types.ts`

Six cell families, each carrying its natural linearity. The abstract core is mode-agnostic; `modes/ocean.ts` etc. extend these with additional fields.

```typescript
/** A bill of lading as a LINEAR semantic cell.
 *  Negotiable BoLs: exactly one instance exists at any time; endorsement transfers it.
 *  Straight BoLs: still LINEAR (a named consignee still represents a unique claim).
 *  Sea waybills: reclassify to AFFINE because they are pure receipts with no title. */
export interface BillOfLadingCell {
  cellId: string;
  bolNumber: string;                     // carrier-assigned BL number
  bolType: BoLType;                      // WHAT-axis leaf
  negotiability: 'negotiable' | 'straight' | 'non-negotiable';
  issuer: string;                        // carrier identity facet
  issueDate: string;                     // ISO 8601
  issuePlace: string;                    // UN/LOCODE or IATA code
  parties: BoLPartyRole[];               // shipper, consignee, notify-party, holder, etc.
  cargoManifestCell: string;             // ref to RELEVANT manifest cell
  carrierReceiptCell: string;            // ref to RELEVANT receipt cell
  contractOfCarriageCell: string;        // ref to RELEVANT contract terms cell
  currentHolder?: string;                // identity facet of present endorsee
  endorsementChain: string[];            // ordered list of endorsement cells
  custodyTrail: string[];                // ordered list of custody-event cells
  clausingAnnotations: string[];         // list of claused-annotation cells
  lifecycleState: BoLLifecycleState;     // HOW-axis coordinate
  regulatoryObligations: BoLRegulatoryTag[];
  previousEventCell?: string;            // DAG link to prior lifecycle cell
  typeHashHex: string;
  uti: string;                           // Unique Transport Identifier (see §D32.5)
  linearity: 'LINEAR' | 'AFFINE';       // AFFINE ONLY for sea waybills
  _modeExtensions?: Record<string, unknown>;  // ocean/air/inland/mm specific fields
  _extensions?: Record<string, unknown>;      // preserve unknown fields from imports
}

/** The carrier's acknowledgement that cargo was received. RELEVANT —
 *  a receipt cannot be un-issued. Consumption of this cell is a kernel-level error. */
export interface CarrierReceiptCell {
  cellId: string;
  bolNumber: string;
  receivedAt: string;                    // ISO 8601
  receivedPlace: string;
  condition: 'apparent-good-order' | 'claused';
  claused?: string[];                    // list of claused remarks
  carrierSignature: Uint8Array;
  linearity: 'RELEVANT';
}

/** Description of the goods. RELEVANT — the manifest is schema-like and
 *  never consumed. Updates create a new manifest cell linked back via prevStateHash. */
export interface CargoManifestCell {
  cellId: string;
  items: CargoItem[];
  totalWeight: { amount: number; unit: 'KG' | 'LB' };
  totalVolume?: { amount: number; unit: 'M3' | 'FT3' };
  dangerousGoods?: DGDeclaration[];
  marksAndNumbers?: string;
  linearity: 'RELEVANT';
}

export interface CargoItem {
  description: string;
  hsCode?: string;                       // WCO harmonised code
  packageCount: number;
  packageType: string;                   // UN Recommendation on Packaging codes
  weight: { amount: number; unit: 'KG' | 'LB' };
  volume?: { amount: number; unit: 'M3' | 'FT3' };
  value?: { amount: number; currency: string };
  containerRef?: string;                 // for ocean FCL
}

/** The contract of carriage terms. RELEVANT — terms are schema, not consumed. */
export interface ContractOfCarriageCell {
  cellId: string;
  incoterms: Incoterms2020;              // FOB, CIF, EXW, DAP, ...
  freightTerms: 'prepaid' | 'collect';
  applicableRegime: 'hague-visby' | 'hamburg' | 'rotterdam' | 'cmr' | 'cim' | 'montreal' | 'warsaw';
  jurisdiction: string;
  arbitrationClause?: string;
  chartePartyRef?: string;              // for charter-party BoLs
  governingTermsHash: string;            // hash of the full terms document
  linearity: 'RELEVANT';
}

/** A single event in the physical custody trail. AFFINE — a discharge
 *  event can be acknowledged but not duplicated. */
export interface CustodyEventCell {
  cellId: string;
  bolCellId: string;
  eventType: CustodyEventType;
  location: string;                      // UN/LOCODE or IATA code or GPS
  timestamp: string;
  actor: string;                         // carrier identity facet at that leg
  equipmentRef?: string;                 // vessel IMO / truck registration / flight number
  previousEventCell?: string;
  linearity: 'AFFINE';
}

/** A BoL endorsement — one link in the chain of title. LINEAR —
 *  endorsing creates a new endorsement cell and consumes the prior holder's claim. */
export interface EndorsementCell {
  cellId: string;
  bolCellId: string;
  fromHolder: string;                    // identity facet being endorsed away
  toHolder: string;                      // identity facet receiving title
  endorsementType: 'blank' | 'special' | 'restrictive' | 'qualified';
  timestamp: string;
  signature: Uint8Array;                 // fromHolder's signature
  previousEndorsementCell?: string;
  linearity: 'LINEAR';
}

/** Terminal delivery receipt. LINEAR — consumed on delivery, terminates the BoL chain. */
export interface DeliveryReceiptCell {
  cellId: string;
  bolCellId: string;                     // the BoL cell consumed by this delivery
  deliveredTo: string;                   // identity facet that took delivery
  deliveredAt: string;
  place: string;
  conditionOnDelivery: 'apparent-good-order' | 'damaged' | 'short' | 'claused';
  exceptions?: string[];
  signature: Uint8Array;
  linearity: 'LINEAR';
}
```

```typescript
// ── Taxonomy (WHAT axis) ──────────────────────────────────────
export type BoLType =
  | 'transport.bol.ocean.negotiable'
  | 'transport.bol.ocean.straight'
  | 'transport.bol.ocean.seaway'
  | 'transport.bol.ocean.charter-party'
  | 'transport.bol.inland.truck.straight'
  | 'transport.bol.inland.rail'
  | 'transport.bol.air.awb.master'
  | 'transport.bol.air.awb.house'
  | 'transport.bol.multimodal.fiata-fbl'
  | 'transport.bol.abstract';

// ── Lifecycle (HOW axis) ──────────────────────────────────────
export type BoLLifecycleState =
  | 'drafted'
  | 'issued'
  | 'shipped-on-board'
  | 'in-transit'
  | 'presented'
  | 'discharged'
  | 'delivered'
  | 'closed'
  | 'claused'
  | 'amended'
  | 'surrendered'
  | 'telex-released'
  | 'lost'
  | 'disputed'
  | 'litigated';

// ── Events ────────────────────────────────────────────────────
export type BoLEventType =
  | 'draft'
  | 'issue'
  | 'shipped-on-board-annotate'
  | 'clause'
  | 'amend'
  | 'endorse'
  | 'present'
  | 'surrender'
  | 'telex-release'
  | 'custody-transfer'
  | 'discharge'
  | 'deliver'
  | 'declare-lost'
  | 'raise-dispute'
  | 'resolve-dispute';

// ── Regulatory tags (WHY axis) ────────────────────────────────
export type BoLRegulatoryTag =
  | 'commerce.title-transfer'
  | 'commerce.collateral'
  | 'commerce.insurance'
  | 'compliance.customs.export'
  | 'compliance.customs.import'
  | 'compliance.sanctions.ofac'
  | 'compliance.sanctions.eu'
  | 'compliance.imo.imdg'
  | 'compliance.iata.dgr'
  | 'compliance.wco.ahtn'
  | 'compliance.ucp600'
  | 'compliance.hague-visby'
  | 'compliance.hamburg-rules'
  | 'compliance.rotterdam-rules';

// ── Party roles ───────────────────────────────────────────────
export type BoLPartyRoleType =
  | 'shipper'                  // consignor / exporter
  | 'consignee'                // named party (straight) or "to order of ..." (negotiable)
  | 'notify-party'             // informational only
  | 'carrier'                  // the issuer
  | 'master'                   // vessel master for ocean
  | 'freight-forwarder'        // NVOCC or OTI
  | 'issuing-bank'             // L/C issuer
  | 'presenting-bank'          // L/C negotiating bank
  | 'current-holder'           // present endorsee
  | 'customs-broker'
  | 'customs-authority';

export interface BoLPartyRole {
  partyId: string;
  role: BoLPartyRoleType;
  capabilities: number[];
  facetCertId?: string;
  lei?: string;                 // LEI for corporates
  eori?: string;                // EU Economic Operator Registration and Identification
  jurisdiction?: string;
  sanctionsChecked?: boolean;
  sanctionsCheckedAt?: string;
}

// ── Capability numbers ────────────────────────────────────────
// Mirrors SCADA's ROLE_CAPABILITIES idiom.
export const BOL_CAPABILITIES = {
  READ_BOL:              1,
  DRAFT_BOL:             2,
  ISSUE_BOL:             3,   // carrier only — signs as carrier
  ENDORSE_BOL:           4,   // only the current holder
  PRESENT_BOL:           5,   // any holder / presenting bank
  SURRENDER_BOL:         6,   // dual-auth: holder + carrier
  TELEX_RELEASE:         7,   // carrier side of dual-auth
  AMEND_BOL:             8,   // carrier + holder dual-auth
  CLAUSE_BOL:            9,   // carrier only — add adverse remarks
  DECLARE_LOST:          10,  // holder of record
  APPROVE_DG:            11,  // DG expert / carrier
  CUSTOMS_CLEAR:         12,  // licensed broker
  OVERRIDE_SANCTIONS:    13,  // compliance officer — dual-auth only
} as const;

export const ROLE_CAPABILITIES: Record<BoLPartyRoleType, number[]> = {
  'shipper':             [1, 2, 11],
  'consignee':           [1, 5],
  'notify-party':        [1],
  'carrier':             [1, 3, 7, 8, 9, 11],
  'master':              [1, 9],
  'freight-forwarder':   [1, 2, 4, 5, 11],
  'issuing-bank':        [1, 5, 6],
  'presenting-bank':     [1, 5],
  'current-holder':      [1, 4, 5, 6, 10],
  'customs-broker':      [1, 12],
  'customs-authority':   [1, 12, 13],
};
```

### D32.2 — Lifecycle Engine

**File**: `packages/bol/src/lifecycle.ts`

A transition table following the CDM pattern, but with **every state transition gated by a PolicyRuntime.evaluate() call against the relevant compiled policy cell**. The transition table is a test-time static assertion, not runtime enforcement — per the Phase 29.5 architecture.

```typescript
const transitionTable: Record<BoLLifecycleState, Partial<Record<BoLEventType, BoLLifecycleState>>> = {
  'drafted': {
    'issue': 'issued',
    'amend': 'drafted',
  },
  'issued': {
    'shipped-on-board-annotate': 'shipped-on-board',
    'clause': 'claused',
    'amend': 'issued',
    'endorse': 'issued',                 // endorsement while issued is allowed
    'declare-lost': 'lost',
  },
  'shipped-on-board': {
    'custody-transfer': 'in-transit',
    'clause': 'claused',
    'endorse': 'shipped-on-board',
    'surrender': 'surrendered',
    'telex-release': 'telex-released',
    'declare-lost': 'lost',
  },
  'in-transit': {
    'custody-transfer': 'in-transit',
    'endorse': 'in-transit',
    'surrender': 'surrendered',
    'telex-release': 'telex-released',
    'discharge': 'discharged',
    'declare-lost': 'lost',
  },
  'discharged': {
    'present': 'presented',
    'raise-dispute': 'disputed',
  },
  'presented': {
    'deliver': 'delivered',
    'raise-dispute': 'disputed',
  },
  'delivered': {
    // terminal — the LINEAR BoL cell is consumed here. No outbound events.
  },
  'surrendered':    { 'deliver': 'delivered' },
  'telex-released': { 'deliver': 'delivered' },
  'claused':        { 'endorse': 'claused', 'present': 'presented', 'amend': 'claused' },
  'amended':        { 'issue': 'issued' },
  'lost':           { 'resolve-dispute': 'issued' },   // after LoI + carrier consent
  'disputed':       { 'resolve-dispute': 'in-transit' },
  'litigated':      { 'resolve-dispute': 'in-transit' },
  'closed':         {},
};
```

Every transition produces:
1. A `PolicyRuntime.evaluate()` call against each `.policy` cell relevant to the (state, event) pair. Rejection returns a structured `PolicyResult` with `rejectionCode`, `hostCalls` audit trail, and no state change.
2. On pass, a new DAG-linked cell with `prevStateHash` pointing to the prior BoL cell.
3. Where the event is an endorsement, a `TransferRecord` (Phase 17) wrapping the new holder.
4. Where the event is a delivery, consumption of the BoL LINEAR cell via the Phase 1 opcode path — and a new `DeliveryReceiptCell` that is itself LINEAR (terminal).
5. Where the event is a clausing, an `AFFINE` clausing-annotation cell appended to `clausingAnnotations`.
6. Where the event is terminal (issue, endorse, surrender, telex-release, deliver), an `AnchorEmitter.emit()` call that broadcasts a signed BSV anchor tx keyed by `sha256(cellBytes)` for idempotency.

### D32.3 — Policy Bundle

**File**: `packages/bol/src/policies/*.policy` (+ `compiler.ts`)

Following the CDM policy-compiler idiom exactly. Each `.policy` file is a Lisp s-expression, parsed by `parseExpression`, compiled by `LispCompiler`, and packed with `packCapabilityCell`.

```lisp
;; single-negotiable-instance.policy
;; At any time, exactly one LINEAR BoL cell exists for a given bolNumber.
;; Encoded as: issuance requires that no unconsumed prior BoL cell exists.
(policy
  :subject carrier
  :action issue-bol
  :constraint (and
    (not (exists-unconsumed-bol? current-bol-number))
    (has-capability 3))
  :linearity LINEAR)
```

```lisp
;; order-bill-endorsement.policy
;; Only the current holder may endorse. Endorsement chains must be continuous.
(policy
  :subject holder
  :action endorse
  :constraint (and
    (= endorser current-holder)
    (= endorsement-type "blank" "special" "restrictive" "qualified")
    (has-capability 4)
    (chain-continuous? endorsement-chain))
  :linearity LINEAR)
```

```lisp
;; straight-bill-no-transfer.policy
;; A straight BoL may not be endorsed.
(policy
  :subject holder
  :action endorse
  :constraint (not (= negotiability "straight"))
  :linearity LINEAR)
```

```lisp
;; present-before-deliver.policy
;; Carrier may only deliver against presentation (or valid telex release).
(policy
  :subject carrier
  :action deliver-cargo
  :constraint (or
    (and (holder-presented-original?)
         (= presenter current-holder))
    (and (telex-release-issued?)
         (dual-auth holder carrier))
    (and (surrender-endorsed?)
         (dual-auth holder carrier)))
  :linearity LINEAR)
```

```lisp
;; surrender-dual-auth.policy
;; Telex release / surrender requires both parties.
(policy
  :subject carrier
  :action telex-release
  :constraint (and
    (has-capability 7)
    (holder-has-capability 6)
    (not (sanctions-hit? consignee)))
  :linearity LINEAR)
```

```lisp
;; letter-of-credit-ucp600.policy
;; UCP 600 Article 20 — discrepancy rules for ocean BoLs presented under L/C.
(policy
  :subject presenting-bank
  :action present-to-lc
  :constraint (and
    (= port-of-loading lc-port-of-loading)
    (= port-of-discharge lc-port-of-discharge)
    (within? shipment-date lc-latest-shipment-date)
    (= (consignee-of bol) lc-consignee)
    (clean-on-board?)
    (not (contains-clausing? "damaged" "short" "unclean")))
  :linearity LINEAR)
```

```lisp
;; sanctions-screen.policy
;; No issue / endorse / deliver to a sanctioned party.
(policy
  :subject *
  :action (issue-bol endorse deliver-cargo)
  :constraint (and
    (not (sanctions-hit? shipper))
    (not (sanctions-hit? consignee))
    (not (sanctions-hit? current-holder))
    (not (sanctions-hit? notify-party))
    (not (vessel-sanctioned? vessel-imo)))
  :linearity LINEAR)
```

```lisp
;; dangerous-goods-imdg.policy
;; IMDG declaration required for any UN-number cargo on an ocean BoL.
(policy
  :subject shipper
  :action issue-bol
  :constraint (or
    (not (contains-un-number? cargo-manifest))
    (and (imdg-class-declared?)
         (imdg-packing-group-declared?)
         (imdg-shipper-declaration-signed?)
         (has-capability 11)))
  :linearity LINEAR)
```

```lisp
;; clean-on-board.policy
;; Transition to shipped-on-board requires no adverse clausing.
(policy
  :subject master
  :action shipped-on-board-annotate
  :constraint (and
    (= receipt-condition "apparent-good-order")
    (empty? clausing-annotations)
    (has-capability 9))
  :linearity LINEAR)
```

The bundle compiles the same way CDM's does:

```typescript
export const POLICY_NAMES = [
  'single-negotiable-instance',
  'order-bill-endorsement',
  'straight-bill-no-transfer',
  'present-before-deliver',
  'surrender-dual-auth',
  'letter-of-credit-ucp600',
  'sanctions-screen',
  'dangerous-goods-imdg',
  'dangerous-goods-iata-dgr',
  'clean-on-board',
] as const;
```

### D32.4 — Host Predicates

**File**: `packages/bol/src/policies/host-functions.ts`

Single entry point `registerBoLHostFunctions(registry: HostFunctionRegistry)`, matching the Phase 29.5 registration shape. These are the new predicates the Lisp compiler lowers to `OP_CALLHOST`:

| Predicate | Arity | Returns | Notes |
|-----------|-------|---------|-------|
| `port-code?` | 1 | bool | Valid UN/LOCODE or IATA code |
| `hs-code?` | 1 | bool | Valid WCO harmonised-system code |
| `un-number?` | 1 | bool | Valid UN dangerous-goods number |
| `imdg-class?` | 1 | bool | Valid IMDG hazard class |
| `iata-dg-class?` | 1 | bool | Valid IATA DGR class |
| `lei-valid?` | 1 | bool | ISO 17442 LEI check |
| `eori-valid?` | 1 | bool | EORI number check |
| `sanctions-hit?` | 1 | bool | Matches OFAC / EU consolidated list (via external feed cell) |
| `vessel-sanctioned?` | 1 | bool | IMO number against sanctioned-vessel list |
| `exists-unconsumed-bol?` | 1 | bool | Uniqueness check for single-negotiable-instance |
| `holder-presented-original?` | 0 | bool | Runtime-observed presentation event |
| `chain-continuous?` | 1 | bool | Endorsement chain continuity |
| `clean-on-board?` | 0 | bool | Receipt condition + clausing = empty |
| `contains-clausing?` | n | bool | Variadic — checks for any of N clausing keywords |
| `within-tolerance?` | 3 | bool | `(within-tolerance? date earliest latest)` |
| `dual-auth` | 2 | bool | Both facets have signed within the session |
| `incoterm?` | 1 | bool | Valid Incoterms 2020 code |

Shared predicates (`has-capability`, `check-domain`, `sanctions-hit?`, `dual-auth`, `chain-continuous?`) promote into `packages/cell-engine/bindings/builtin-host-functions.ts` per the Phase 29.5 plan, so CDM/SCADA/BoL all share one registration.

### D32.5 — Unique Transport Identifier (UTI)

Mirrors CDM's UTI (ISDA format). For BoLs we use the DCSA-proposed `tbl-ID` shape:

```
{ISSUING-CARRIER-SCAC-OR-IATA}_{issueDate:YYYYMMDD}_{bolNumber-sha8}
```

`generateUTI()` lives in `types.ts` alongside `computeBoLTypeHash()`, matching the CDM idiom.

### D32.6 — Bridge Layer

**Files**: `packages/bol/src/bridge/*.ts`

Import/export surfaces for every format the industry actually uses. Mirrors CDM's `bridge/cdm-json.ts` + `bridge/fpml.ts` split.

| Bridge | Standard | Direction |
|--------|----------|-----------|
| `edifact.ts` | UN/EDIFACT (IFTMIN · IFTMBF · IFTMBC · IFTMCS · CUSDEC · CUSRES) | import + export |
| `dcsa.ts` | DCSA eBL 3.0 (JSON) | import + export |
| `iata-one-record.ts` | IATA ONE Record (RDF/JSON-LD) | import + export |
| `fiata-fbl.ts` | FIATA FBL negotiable form | import + export |
| `un-cefact-mmt.ts` | UN/CEFACT Multi-Modal Transport RDM | import + export |
| `x12.ts` | ANSI X12 204/211/214/304/315/322/110 | import + export |

All bridges preserve unknown fields into `_extensions` exactly the way `bridge/cdm-json.ts` does for FpML. Round-trip fidelity is a gate test.

### D32.7 — Mode Dialects

**Files**: `packages/bol/src/modes/{ocean,inland,air,multimodal}.ts`

Each dialect extends the abstract core with mode-specific fields, and reuses everything else (lifecycle, policies, bridges where applicable).

```typescript
// modes/ocean.ts
export interface OceanBoLExtensions {
  vesselName: string;
  vesselImo: string;
  voyageNumber: string;
  portOfLoading: string;     // UN/LOCODE
  portOfDischarge: string;   // UN/LOCODE
  placeOfReceipt?: string;
  placeOfDelivery?: string;
  containers: ContainerRef[];
  charterPartyRef?: string;
  onBoardDate?: string;
}

export interface ContainerRef {
  containerNumber: string;   // ISO 6346
  sealNumber: string;
  sizeType: string;          // ISO 6346 size-type code
  weight: { amount: number; unit: 'KG' };
  fcl: boolean;              // full or less-than container
}

// modes/inland.ts
export interface InlandBoLExtensions {
  carrierScac: string;       // Standard Carrier Alpha Code
  proNumber: string;
  nmfcItems: NMFCItem[];
  freightClass: string;      // NMFC class 50-500
  equipmentType: 'dry-van' | 'reefer' | 'flatbed' | 'tanker' | 'intermodal';
  equipmentNumber?: string;
  pickupDate: string;
  deliveryDate?: string;
}

// modes/air.ts
export interface AirWaybillExtensions {
  awbPrefix: string;         // 3-digit IATA carrier prefix
  awbSerial: string;         // 8-digit
  flightNumber: string;
  flightDate: string;
  origin: string;            // IATA code
  destination: string;       // IATA code
  routingTransit?: string[];
  chargeableWeight: { amount: number; unit: 'KG' };
  masterAwbRef?: string;     // for HAWBs, the MAWB they roll up under
  houseAwbRefs?: string[];   // for MAWBs, the HAWBs under them
}

// modes/multimodal.ts
export interface MultimodalFBLExtensions {
  legs: TransportLeg[];      // sequential legs (road → ocean → rail → ...)
  fiataSerial: string;
  throughCarrier: string;    // the FFT/NVOCC acting as contractual carrier
}

export interface TransportLeg {
  mode: 'road' | 'rail' | 'ocean' | 'air' | 'inland-waterway';
  carrier: string;
  from: string;
  to: string;
  scheduledDeparture: string;
  scheduledArrival: string;
  equipmentRef?: string;
}
```

Mode extensions slot into `BillOfLadingCell._modeExtensions` at runtime. `mode/ocean.createOceanBoL()` is a thin factory that calls the abstract `createBoL()` and then populates `_modeExtensions` — the same way `createCDMProduct()` wraps lower-level cell creation.

### D32.8 — Demos

**Files**: `packages/bol/demo.ts` and `packages/bol/demo-kernel.ts`

`demo.ts` mirrors the existing CDM/SCADA demos: end-to-end scenario with printed state.

`demo-kernel.ts` is the Phase 29.5-style demo that prints a real 2-PDA trace and anchor txid per terminal event — the "seeing is believing" artifact. Both cover three scenarios:

1. **Negotiable ocean BoL happy path**: Carrier creates and issues a negotiable ocean BoL (Shanghai → Rotterdam). Master annotates `shipped-on-board`. Shipper endorses to consignee's issuing bank (L/C pledge). Bank endorses onward to buyer after payment. Vessel discharges in Rotterdam — custody events accumulate. Buyer presents original BoL at discharge. Carrier verifies chain, applies `present-before-deliver.policy`, delivers. DeliveryReceiptCell consumes the BoL. Regulatory cell (customs import) emitted as RELEVANT side-effect.
2. **Telex release**: No physical original, dual-auth surrender, delivery.
3. **Lost original → letter of indemnity → reissue.**

---

## Why an "Extension Grammar" and not Four Packages

Ocean, truck, air, and multimodal BoLs share:

1. The same linearity model (LINEAR document of title, RELEVANT receipts, AFFINE custody events).
2. The same state machine (draft → issue → ship → present → deliver, with identical branches).
3. The same party model (shipper / consignee / carrier / holder / banks).
4. The same policy bundle (present-before-deliver, single-negotiable-instance, sanctions-screen, UCP 600).
5. The same compression gradient (legal text → Lisp → opcodes → 2-PDA → Plexus).

They differ only in:

1. **WHAT-axis leaves** — a handful of taxonomy strings.
2. **Mode-specific fields** — vessel/container vs flight/AWB vs truck/PRO.
3. **Applicable carriage regime** — Hague-Visby vs Montreal vs CMR.
4. **Bridge formats** — DCSA eBL for ocean, IATA ONE Record for air, X12 for inland.

Four packages would duplicate the lifecycle, the policies, and the endorsement chain three extra times. A single `@semantos/bol` package with `modes/` subfolders is the minimum-grammar solution: one grammar, four dialects. This is exactly the shape an "extension grammar" wants to take.

---

## Testing Strategy

Mirrors Phase 28 and Phase 29.

| Test | Gate |
|------|------|
| `bol.core.types.test.ts` | Cell construction, type hash computation, UTI generation |
| `bol.lifecycle.test.ts` | Transition table exhaustiveness; negative tests for illegal transitions |
| `bol.endorsement.test.ts` | Endorsement chain continuity; transfer wrapping; negotiable vs straight |
| `bol.policies.test.ts` | Each `.policy` file compiles; compiled bytes match golden fixtures |
| `bol.host-functions.test.ts` | Each host predicate returns expected truth values against seed data |
| `bol.kernel.test.ts` | **Phase 29.5-style: every policy runs through `PolicyRuntime.evaluate` and hits the 2-PDA, no TS shim** |
| `bol.anchor.test.ts` | **Phase 29.5-style: terminal events emit idempotent anchor txs** |
| `bol.bridge.edifact.test.ts` | Round-trip IFTMIN · IFTMBF; unknown-field preservation |
| `bol.bridge.dcsa.test.ts` | Round-trip DCSA eBL 3.0 JSON |
| `bol.bridge.iata.test.ts` | Round-trip IATA ONE Record JSON-LD |
| `bol.modes.ocean.test.ts` | Vessel/container fields; UN/LOCODE validation |
| `bol.modes.air.test.ts` | AWB prefix/serial; MAWB↔HAWB linkage |
| `bol.modes.inland.test.ts` | SCAC, PRO, NMFC class |
| `bol.modes.multimodal.test.ts` | Leg ordering; per-leg regime attribution |
| `bol.demo.test.ts` | End-to-end: issue → endorse → present → deliver + regulatory emission |
| `phase32-gate.test.ts` | Integrates with existing phase gate suite |

---

## Open Questions

1. **Electronic bills of lading legal status.** MLETR (UNCITRAL Model Law on Electronic Transferable Records) has been adopted by the UK, Singapore, Bahrain, Abu Dhabi, and is gathering momentum elsewhere. The LINEAR-cell-as-title argument is strongest in MLETR jurisdictions. In non-MLETR jurisdictions, the BoL cell functions as a control instrument plus an off-chain paper fallback — the same hybrid mode DCSA eBL platforms operate in today. Worth a short legal-status section in the design doc.

2. **Sea waybills.** Already handled above by reclassifying them as AFFINE (a sea waybill is a receipt, not a title document). Worth confirming this is the right call before locking the types.

3. **Charter parties.** A charter-party BoL is "subject to" a charter contract that lives outside the BoL. Modelled here by pointing to `contractOfCarriageCell.chartePartyRef`. Worth asking whether charter parties themselves deserve their own extension grammar (Phase 33?).

4. **Container single-BoL vs groupage.** One BoL per container vs one BoL covering many containers vs many BoLs for one container (groupage / house BoLs under a master). The cargo manifest cell handles the first two cases. Groupage needs the master/house relationship already modelled in `modes/air.ts` — we should make sure the ocean side mirrors it.

5. **UTI uniqueness vs SCAC + BL-number.** DCSA uses `{carrier SCAC}{BL number}`. That's a natural primary key and already unique in the industry. The UTI format proposed here adds a date + hash fragment for extra safety; worth confirming the DCSA convention is sufficient.

6. **Integration with Phase 28 CDM for trade finance.** An L/C drawdown against a presented BoL is effectively a CDM payment event triggered by a BoL lifecycle event. Cross-package wiring should live in a `packages/trade-finance/` package in a later phase, not in `@semantos/bol`.

---

## Success Criteria

Phase 32 is complete when:

- [ ] A negotiable ocean BoL can be issued, endorsed through three holders, presented, and delivered — all through the cell engine via `PolicyRuntime.evaluate`, with the BoL LINEAR cell provably consumed at delivery.
- [ ] Attempting to double-spend a negotiable BoL (issue a second original for the same bolNumber) is rejected **at the opcode level via `ERR_POLICY_REJECT` from the 2-PDA**, not at the application layer.
- [ ] Attempting to deliver without presentation is rejected by the `present-before-deliver` policy running through the kernel.
- [ ] Attempting to endorse a straight BoL is rejected by `straight-bill-no-transfer`.
- [ ] A sanctioned-party issue/endorse/deliver is rejected by `sanctions-screen`.
- [ ] IMDG declaration is enforced on UN-numbered cargo.
- [ ] UCP 600 discrepancy detection runs automatically on L/C presentation.
- [ ] Round-trip import/export is bit-exact for DCSA eBL JSON and byte-stable for EDIFACT IFTMIN.
- [ ] Terminal events emit idempotent anchor txs via `AnchorEmitter` — re-running the demo does not double-broadcast.
- [ ] `demo-kernel.ts` prints a 2-PDA trace and an anchor txid for the happy-path scenario.
- [ ] The demo in D32.8 runs green against both the Bun test harness and a `bun run demo` invocation.
- [ ] Gate test `phase32-gate.test.ts` passes.
- [ ] The extension surfaces in the loom sidebar under `transport.bol.*`.

---

## Relationship to Prior Phases

| Prior phase | What we reuse |
|-------------|---------------|
| Phase 1 (cell packing) | Cell header + BCA derivation for BoL cells |
| Phase 8.5 (identity facets) | Shipper, consignee, carrier, bank, holder identities |
| Phase 17 (transfer) | `createTransferRecord()` is literally endorsement — no new kernel code |
| Phase 18 (metering) | L/C drawdowns, freight prepayment, demurrage clock |
| Phase 21 (Lisp compiler) | Every `.policy` file compiles via the same pipeline CDM uses |
| Phase 25.5 (OP_CALLHOST + registry) | New predicates registered the same way SCADA registers sensor-reading |
| Phase 28 (CDM) | Prior art — same architecture, financial domain |
| Phase 29 (SCADA) | Prior art — same architecture, industrial domain |
| **Phase 29.5 (kernel enforcement sweep)** | **`PolicyRuntime`, `AnchorEmitter`, real `HostFunctionRegistry` wiring — hard prerequisite** |

**Zero new kernel opcodes. Zero new linearity modes. Zero new FSM primitives.** Everything Phase 32 needs already exists. This phase is grammar on top of an existing runtime, which is the whole point of calling it an extension grammar. The only thing it cannot do until Phase 29.5 ships is honestly claim "rejected at the opcode level" — and that is exactly what Phase 29.5 is for.

---
