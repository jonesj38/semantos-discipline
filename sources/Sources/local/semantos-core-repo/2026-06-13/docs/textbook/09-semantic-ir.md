---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/09-semantic-ir.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.650240+00:00
---

# Semantic IR (SIR)

Part III of this textbook covers the pipeline — the sequence of transformations that takes a surface expression and produces bytecode for the cell engine. Chapter 8 traced the Lisp surface syntax through parsing into an abstract syntax tree. This chapter covers the next layer: the Semantic IR (SIR), which is where the system acquires a vocabulary for what an expression *means*, as opposed to how it will be enforced.

The SIR is boot-step-7 infrastructure. It sits above the Opcode IR (OIR) — which already exists and is tested — and carries the information the OIR deliberately discards: jural category, taxonomy coordinates, governance context, and identity binding. Those four annotation kinds are the subject of this chapter.

---

## 1. Why a Semantic Layer

The Opcode IR operates on mechanism primitives: comparison, logical, capability, domainCheck, timeConstraint, hostCall, typeHashCheck, deref. These answer one question: how does the machine check this? They do not answer: what is being said?

Consider two OIR programs that both resolve to a capability check followed by a domain check followed by a logical conjunction. One enforces that a clearing member has posted margin before a deadline. The other enforces that a SCADA shift supervisor has authority over a set of valves. At the OIR level, the two programs are structurally indistinguishable. At the cell engine level, they produce the same bytecode pattern. The governance plane can tell them apart by reading the manifest, but the IR itself carries no record of the distinction.

This matters because the system makes a specific architectural claim: a CDM novation, a SCADA emergency shutdown, a governance ballot, and a shell command are the same kind of thing at different abstraction levels. If the IR cannot represent what makes them different — not just how they are each enforced — then that claim remains assertion without a verification surface.

The SIR provides that surface. It is not a replacement for the OIR. It is a layer that sits above it, which every surface frontend — Lisp, Ricardian, EDI, domain-specific languages — targets before the OIR compilation pass begins.

### 1.1 The Two-IR Architecture

The compression gradient now runs through two intermediate representations:

```
Surface syntax
(Lisp, Ricardian, EDI, SCADA-DSL, ...)
        │
        ▼
┌───────────────────────────────────────┐
│           SEMANTIC IR (SIR)           │
│                                       │
│  Jural category + taxonomy            │
│  coordinates + governance context +  │
│  identity binding                     │
└───────────────────┬───────────────────┘
                    │  lower (SIR → OIR)
                    ▼
┌───────────────────────────────────────┐
│           OPCODE IR (OIR)             │
│                                       │
│  ANF bindings — comparison, logical,  │
│  capability, domainCheck,             │
│  timeConstraint, hostCall,            │
│  typeHashCheck, deref                 │
└───────────────────┬───────────────────┘
                    │  emit (OIR → bytes)
                    ▼
             Cell engine (Zig 2PDA)
```

The OIR is already built and golden-file tested in `packages/semantos-ir`. The SIR is the new upper layer; the lower pass from SIR to OIR is where semantic enforcement happens structurally, not just at the governance-plane boundary.

---

## 2. Jural Categories — The Semantic Primitives

Every meaningful expression in the system reduces to one of seven jural categories. These categories are the vocabulary the SIR uses to type its nodes.

The categories come from Hohfeld's 1913 analysis of fundamental legal conceptions — the standard decomposition of legal relations into atomic types — adapted for computational governance. The adaptation drops Hohfeld's original eight-position scheme (right/duty, privilege/no-right, power/liability, immunity/disability) in favour of seven categories that are the minimum set needed to distinguish everything the system does. The Hohfeldian positions remain the theoretical source, and the Lean Jural lexicon is grounded in them; what changes is the working vocabulary used in the SIR layer.

### 2.1 The Seven Categories

**Declaration** — an assertion of fact or state. A declaration says that something is the case; it is evidence, not command. Linearity: typically RELEVANT (a declaration cannot be destroyed; it becomes part of the evidence chain). Examples: a telemetry reading that asserts a sensor value; a CDM confirmation event; an attestation; a call to `semantos verify` that asserts an evidence chain is valid.

**Obligation** — a duty that must be fulfilled. An obligation exists once and must be consumed — either by fulfillment or by default. Linearity: LINEAR. Examples: a CDM margin call that must be met before a deadline; a SCADA alarm that must be acknowledged; a governance ballot deadline.

**Permission** — authorisation to perform an action. A permission persists until revoked; it is the standing right to act, not the act itself. Linearity: RELEVANT. Examples: a capability grant expressed as `has-capability N`; an operator's shift capability token; the listing of what the active hat may do.

**Prohibition** — a constraint that an action must not occur. Like a permission, a prohibition persists. Linearity: RELEVANT. Examples: an interlock policy compiled to bytecode and enforced before every valve command; the allowedEmitOps whitelist that prevents certain opcodes from appearing in a given program; conservative-by-default enforcement that treats delegated execution as prohibited.

**Power** — authority to change legal or economic relations. A power may be exercised once (LINEAR) or may be a standing authority (RELEVANT). Examples: `semantos publish`, which transitions a cell from AFFINE to RELEVANT; a CDM novation, which transfers a financial obligation to a new counterparty; a governance ballot vote.

**Condition** — a temporal or state-dependent trigger. A condition is consumed when evaluated; it may be recreated. Linearity: AFFINE. Examples: `(time-after "2026-04-22")` — a temporal gate; a CDM lifecycle prerequisite requiring that a trade is confirmed before it can be cleared; a SCADA mode prerequisite requiring MANUAL mode before an override is permitted.

**Transfer** — movement of value, rights, or obligations between parties. A transfer happens once; duplication would be double-spending. Linearity: LINEAR. Examples: `semantos transfer <objectId> --to <hatId>`; a CDM settlement event; a SCADA shift handover in which capability tokens change hands.

### 2.2 Why These Seven

These categories are not chosen for jurisprudential correctness as an end in itself. They are chosen because they are the minimum set that distinguishes everything the system does.

A CDM novation and a SCADA alarm acknowledgment are both exercises of power in the general sense — both change relations. But one is a transfer-power over financial obligations operating at the interpretive trust class, and the other is a consume-power over a safety event operating at the authoritative trust class. The SIR makes this distinction first-class. The OIR cannot.

The mapping between Hohfeld's original positions and the seven adapted categories is:

| Seven-category (SIR) | Hohfeldian source (theoretical) |
|---|---|
| declaration | claim-right exercised as assertion |
| obligation | duty (correlative of a right) |
| permission | privilege (absence of duty to refrain) |
| prohibition | no-right / duty-to-refrain |
| power | power (ability to change legal relations) |
| condition | temporal dimension Hohfeld assumed but did not formalise |
| transfer | canonical exercise of power over economic relations |

### 2.3 Shell Verbs and Domain Types

The jural categories give a systematic vocabulary for the system's shell verbs and domain types. Selected mappings:

| Shell verb | Primary category | Notes |
|---|---|---|
| `new` | power | Creates an object — exercises the power to bring something into existence |
| `patch` | declaration | Asserts new facts about an existing object |
| `publish` | power | Transitions AFFINE → RELEVANT; changes legal status |
| `sign` | declaration | Attestation — asserts identity binding |
| `verify` | declaration | Asserts chain validity |
| `transfer` | transfer | Movement of ownership |
| `settle` | transfer | Settlement of economic value |
| `vote` | power | Exercises governance power |
| `dispute` | power + condition | Initiates escalation, conditional on dispute window |
| `infer approve` | power | Ratifies inferred grammar |
| `infer reject` | prohibition + declaration | Rejects and asserts the reason |
| `compile` | — | Pure computation; not a jural act |
| `eval` | — | Pure computation; not a jural act |

`compile` and `eval` have no jural category. They are mechanism, not meaning.

CDM lifecycle events decompose naturally:

| CDM EventType | Category | Linearity |
|---|---|---|
| execution | power | LINEAR |
| confirmation | declaration | RELEVANT |
| clearing | power | LINEAR |
| settlement | transfer | LINEAR |
| novation | transfer + power | LINEAR |
| payment | transfer | LINEAR |
| margin-call | obligation | LINEAR |
| default | declaration | RELEVANT |
| close-out-netting | power + transfer | LINEAR |
| rate-reset | condition | AFFINE |

SCADA operations decompose correspondingly:

| SCADA action | Category | Linearity |
|---|---|---|
| Telemetry reading | declaration | AFFINE |
| valve.open / motor.start | power | LINEAR |
| emergency.shutdown | power + prohibition | LINEAR |
| alarm.acknowledge | power (consume) | LINEAR |
| Interlock evaluation | prohibition | RELEVANT |
| Shift handover | transfer | LINEAR |

---

## 3. The SIR Node Structure

A SIR node is a typed representation of a single meaningful expression. Every surface frontend lowers to SIR nodes; the SIR→OIR lower pass then compiles each node to ANF bindings.

### 3.1 The Four Annotation Kinds

Every SIR node carries exactly four annotation kinds:

**Jural category** — one of the seven values above. This is what is being expressed. It determines the canonical lowering pattern (which OIR binding kinds the lower pass will emit) and the required linearity.

**Taxonomy coordinates** — a four-field record that locates the expression in semantic space:

- `what` — the domain and object type (e.g. `rates.swap.fixed-float`, `sensor.pressure.gauge`)
- `how` — the operation within that domain (e.g. `lifecycle.settlement`, `command.valve.open`)
- `why` — the purpose or intent (e.g. `obligation-fulfillment`, `safety-interlock`)
- `where` (optional) — spatial or jurisdictional coordinate (e.g. `au.qld`, `scada.zone-3`)

The taxonomy coordinates are what give the SIR its domain-specific identity beyond the jural category. Two expressions with the same jural category but different taxonomy coordinates are semantically distinct — a `transfer` in the CDM domain and a `transfer` in the SCADA shift-handover domain have the same category but completely different operational semantics.

**Governance context** — the trust and execution envelope within which the expression is valid:

- `trustClass` — one of `cosmetic`, `interpretive`, `authoritative`
- `proofRequirement` — one of `none`, `attestation`, `formal`
- `executionAuthority` — one of `local_facet`, `hat_scoped`, `delegated`
- `linearity` — one of `LINEAR`, `AFFINE`, `RELEVANT`, `FUNGIBLE`
- `allowedEmitOps` (optional) — the whitelist of OIR binding kinds this node is permitted to produce

The governance context is not advisory. The SIR→OIR lower pass enforces it structurally: an authoritative expression without a formal proof requirement is rejected at the IR level, not just at the governance-plane boundary. An expression with a delegated execution authority is rejected until that execution model is implemented. An expression whose lowering would produce an OIR binding kind not in its allowedEmitOps whitelist is rejected. The enforcement is in the compilation pipeline.

**Identity binding** — who is expressing this and under what authority:

- `subject` — a role, a domain flag reference, or a certificate pattern
- `facetId` (optional, transitional) — the hat's identifier
- `certId` (optional) — the BRC-52 certificate identifier

### 3.2 The Full SIR Node Shape

In TypeScript terms (from `packages/semantos-sir/src/types.ts`):

```typescript
interface SIRNode {
  id: string;                    // counter-based: "$s0", "$s1", ...
  category: JuralCategory;       // the seven
  taxonomy: TaxonomyCoordinates; // what / how / why / where
  identity: SIRIdentity;         // who is expressing this
  governance: GovernanceContext; // trust class, proof req, exec auth, linearity
  action: string;                // maps to shell verb or domain event
  constraint: SIRConstraint;     // typed semantic constraint
  target?: SIRTarget;            // object, equipment, product
  transferTo?: SIRIdentity;      // for transfers: the receiving party
  gate?: SIRGate;                // for conditions: temporal or state gate
  fulfillment?: SIRFulfillment;  // for obligations: deadline + criteria
  provenance: SIRProvenance;     // source, confidence, timestamp, trust tier
}
```

A SIR program is a collection of these nodes with a designated primary node and a program-level governance context:

```typescript
interface SIRProgram {
  nodes: SIRNode[];
  primaryNodeId: string;
  programGovernance: GovernanceContext;
}
```

### 3.3 Typed Constraints

The SIR carries constraints as typed structures, not as raw predicates. This is the key difference from the OIR. An OIR binding might say `comparison(pressure, >, 150)`. A SIR constraint says `{ kind: 'interlock', policyId: 'P-001', policyName: 'pressure-ceiling' }`. The OIR carries the mechanism; the SIR carries the meaning.

The constraint kinds available in a SIR node:

```typescript
type SIRConstraint =
  | { kind: 'capability'; required: number; name: string }
  | { kind: 'domain'; flag: number | string }
  | { kind: 'identity'; ref: IdentityRef }
  | { kind: 'temporal'; op: 'before' | 'after'; iso: string }
  | { kind: 'value'; field: string; op: ComparisonOp; value: number | string }
  | { kind: 'state'; requiredPhase: string }
  | { kind: 'interlock'; policyId: string; policyName: string }
  | { kind: 'composite'; op: 'and' | 'or' | 'not'; children: SIRConstraint[] };
```

The `composite` kind lets constraints compose: an interlock policy that requires both a pressure check and a mode prerequisite is a single composite constraint in the SIR, even though it lowers to multiple OIR bindings.

---

## 4. The Lower Pass: SIR → OIR

The lower pass is where each jural category becomes a canonical pattern of OIR bindings. The pattern is determined by the category; the specific bindings are determined by the node's constraint and governance context.

### 4.1 Canonical Lowering Patterns

**Declaration** lowers to identity verification plus field assertions:

```
SIR: declaration
     subject=buyer, action=confirm
     taxonomy=rates.swap/lifecycle.confirmation

OIR: $0 = domainCheck(buyer-flag)
     $1 = comparison(status, =, "executed")
     $2 = logical_and($0, $1)
     → VERIFY
```

**Obligation** lowers to a temporal gate plus capability check — the deadline is structural, not advisory:

```
SIR: obligation
     subject=clearing-member, action=margin-post
     deadline="2026-04-22T17:00:00Z"

OIR: $0 = domainCheck(clearing-member-flag)
     $1 = timeConstraint(timeBefore, 1745341200)
     $2 = capability(METERING)
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

**Permission** lowers to a capability check — the simplest lowering, because a permission in the SIR maps directly to a capability predicate in the OIR:

```
SIR: permission
     subject=shift-supervisor, action=operate-valves

OIR: $0 = capability(3)
     → VERIFY
```

**Prohibition** lowers to a negated constraint — the predicate must be false for the action to proceed:

```
SIR: prohibition
     action=valve.open
     constraint=interlock(pressure > 150)

OIR: $0 = comparison(pressure, >, 150)
     $1 = logical_not($0)
     → VERIFY
```

**Power** lowers to identity check plus capability check plus domain check:

```
SIR: power
     subject=governor, action=publish
     governance.trustClass=interpretive

OIR: $0 = domainCheck(governor-flag)
     $1 = capability(PUBLISH)
     $2 = typeHashCheck(<manifest-type-hash>)
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

**Condition** lowers inline as a gate on the containing expression:

```
SIR: condition
     gate=temporal(after="2026-04-22")

OIR: $0 = timeConstraint(timeAfter, 1745280000)
```

**Transfer** lowers to sender identity check plus capability checks — both transfer and metering capabilities are required for an economically effective action:

```
SIR: transfer
     from=seller, to=buyer, action=settlement

OIR: $0 = domainCheck(seller-flag)
     $1 = capability(TRANSFER)
     $2 = capability(METERING)
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

### 4.2 Trust-Tier Enforcement in the Lower Pass

The lower pass does not merely read the governance context — it enforces it by refusing to produce OIR if the context is violated. The enforcement is structural.

Specifically: an authoritative expression that does not carry a formal proof requirement is rejected at the IR level. A delegated execution authority is rejected until that execution model is implemented. An expression whose lowering would produce an OIR binding kind not in its allowedEmitOps whitelist is rejected, binding by binding.

This means the system has two independent enforcement points for governance properties. The governance plane checks trust tiers before lowering is attempted. The lower pass checks them again, independently, by reading the trust tier and proof requirement carried in the IR itself. Half-enforcement — trusting only one of these — is worse than no enforcement: it creates the illusion of a check without the structural guarantee.

### 4.3 The Epistemic Dimension

The SIR carries `provenance.source` and `provenance.confidence` as first-class fields. This is where the hard/soft predicate distinction becomes structural:

- `trustAtExpression: 'authoritative'` and `proofRequirement: 'formal'` — hard predicate. The lower pass emits OIR nodes that can participate in economic execution.
- `trustAtExpression: 'interpretive'` and `proofRequirement: 'attestation'` — checked predicate. The lower pass emits OIR nodes gated by attestation verification.
- `trustAtExpression: 'cosmetic'` and `source: 'inferred'` — soft predicate. The lower pass either emits advisory-only nodes with no economic effect, or refuses to lower entirely, depending on the allowedEmitOps whitelist.

The provenance source field records where the expression originated: `manual`, `inferred`, `voice`, `api`, `scheduler`, or `monitor`. An inferred expression that has not been ratified by governance carries `source: 'inferred'` and `confidence: 0.7`; the governance plane can see this and route the expression for human review before lowering is permitted.

---

## 5. Governance Domains in the SIR

The SIR's governance context can carry a domain binding — a record that locates the expression within a named governance domain. A governance domain is a sovereign scope within which a coherent set of governance rules apply, backed by a domain flag namespace that the cell engine enforces at the bytecode level via `OP_CHECKDOMAINFLAG`.

The domain binding shape:

```typescript
interface DomainBinding {
  flag: number;         // from the client sovereignty namespace
  domainType: 'trust' | 'estate' | 'realm' | 'corporate' | 'cooperative' | 'personal';
  instrumentId?: string; // the governing instrument (trust deed, articles, etc.)
  realm?: string;        // jurisdictional scope → maps to taxonomy 'where'
  parentFlag?: number;   // if this is a sub-domain
  delegation?: DelegationChain;
}
```

When the lower pass encounters a node with a domain binding, it emits the domain flag check for that domain. If the domain has a parent flag, it emits checks for both — the hierarchy is enforced structurally, not by application logic.

Every type of governance structure — trust, estate, realm, corporate entity, cooperative — decomposes into the same seven jural categories. A discretionary trust has declarations (the trust deed), obligations (fiduciary duties), permissions (trustee powers to invest and distribute), prohibitions (no commingling, no self-dealing), powers (power to appoint or remove beneficiaries), conditions (vesting conditions), and transfers (distributions). The seven categories are sufficient vocabulary for any governance structure.

---

## 6. What the SIR Enables

### 6.1 Peer-Frontend Equivalence

With the SIR, two surface frontends can be compared at the semantic level. A Lisp expression and a Ricardian clause that express the same obligation should produce the same SIR node — same category, same taxonomy, same governance context — even if they produce slightly different OIR because parsers differ in their metadata attachment. The golden-file conformance suite extends from OIR (byte-identical opcodes) to SIR (semantically equivalent nodes, modulo provenance).

### 6.2 Inference Classification

When InferenceAgent proposes a grammar from an unfamiliar API, the SIR gives it a vocabulary for what the grammar means, not just what fields it has. The inference output can carry `SIRNode[]` with jural categories: this entity looks like a transfer, that one looks like an obligation, this field is a condition gate. The taxonomy mapper can then verify that the proposed categories align with the domain coordinates before governance ratification.

### 6.3 Allowable-Emit Enforcement at the Right Level

The allowedEmitOps field on a SIR node whitelists against OIR binding kinds — comparison, logical, capability, domainCheck, and so on. This is the correct abstraction level. A SCADA interlock policy that should only emit comparisons and negations cannot accidentally emit a hostCall or a transfer binding. The whitelist operates on the mechanism layer, not on raw opcode bytes, which would be the wrong level.

An earlier approach to this problem considered whitelisting at the opcode-byte level — specifying which raw instruction bytes a given policy is allowed to produce. That approach is unworkable: a prohibit-on-pressure-threshold policy legitimately emits a push-number opcode and a comparison opcode, but those same opcodes appear in every other constraint program. You cannot distinguish a safety interlock from a financial capability check at the opcode level without carrying the semantic context. The OIR binding kind is the right granularity because it names the mechanism intent (`capability`, `domainCheck`, `timeConstraint`) rather than the encoding.

### 6.4 Sequencing: When the SIR Is Built

The SIR types and the lower pass are Window 3 work, running in parallel with the Phase 38 OIR extraction. The sequence is:

- Window 3: define `packages/semantos-sir/src/types.ts` (the SIR types), implement `lower-sir.ts` (the SIR→OIR lower pass with trust-tier enforcement), and write golden-file tests covering one representative node per jural category. The Lisp compiler is not modified in this window; the existing Lisp → OIR → bytes path continues to function. The purpose of Window 3 is to prove the shape.
- Window 4: rewire `LispCompiler.compilePolicy()` to route through Lisp → SIR → OIR → bytes. Extend the golden-file suite to verify that Lisp and any second frontend produce the same SIR for the same semantic expression.
- Window 5: additional surface frontends target the SIR directly. A Ricardian parser produces SIR nodes whose jural categories correspond to the clause types of the contract — recitals are declarations, performance clauses are obligations, licences are permissions, restrictive covenants are prohibitions, termination clauses are powers, conditions precedent are conditions, payment clauses are transfers. The SIR is what makes a Ricardian contract machine-executable without losing the human-readable legal structure.

None of this work touches the OIR. The OIR is already built and tested. The SIR is a new upstream layer that feeds it.

---

## 7. A Worked SIR Program

The following program represents a CDM margin call scenario. It is a three-node SIR program: one node for each jural category involved — an obligation (the margin call itself), a condition (the temporal deadline gate), and a prohibition (the interlock that prevents settlement if the margin call has not been met). All four annotation kinds — jural category, taxonomy, governance context, and identity binding — are illustrated in each node.

```lisp
;; SIR program: CDM margin-call obligation with deadline condition
;; and settlement-prohibition pending fulfillment
;;
;; Primary node: $s0 (the obligation)

(sir-program
  :primary "$s0"
  :program-governance
    { trustClass: "authoritative"
      proofRequirement: "formal"
      executionAuthority: "hat_scoped"
      linearity: "LINEAR" }

  :nodes [

    ;; Node $s0 — OBLIGATION
    ;; The clearing member owes margin before the deadline.
    ;; Linearity: LINEAR — the obligation exists once and must be
    ;; consumed by fulfillment or default.
    (sir-node
      :id "$s0"

      ;; Annotation 1 — jural category
      :category obligation

      ;; Annotation 2 — taxonomy coordinates
      :taxonomy
        { what:  "rates.swap.fixed-float"
          how:   "lifecycle.margin-call"
          why:   "risk-mitigation"
          where: "au.asx" }

      ;; Annotation 3 — governance context
      :governance
        { trustClass:          "authoritative"
          proofRequirement:    "formal"
          executionAuthority:  "hat_scoped"
          linearity:           "LINEAR"
          allowedEmitOps:      ["domainCheck" "timeConstraint"
                                "capability"  "logical_and"] }

      ;; Annotation 4 — identity binding
      :identity
        { subject: { type: "role", name: "clearing-member" }
          certId:  "cert-id-clearing-member-alpha" }

      :action "margin-post"

      :constraint
        { kind: "composite"
          op:   "and"
          children: [
            { kind: "domain"
              flag: 0x00020010 }         ;; CDM domain flag
            { kind: "capability"
              required: 4
              name:     "METERING" }
          ] }

      :fulfillment
        { fulfilledBy:   "lifecycle.margin-receipt"
          deadline:      "2026-04-22T17:00:00Z"
          defaultAction: "lifecycle.margin-default" }

      :provenance
        { source:             "api"
          expressedAt:        "2026-04-21T09:00:00Z"
          trustAtExpression:  "authoritative" })


    ;; Node $s1 — CONDITION
    ;; Temporal gate: the margin call is only active before the deadline.
    ;; Linearity: AFFINE — consumed when evaluated.
    (sir-node
      :id "$s1"

      ;; Annotation 1 — jural category
      :category condition

      ;; Annotation 2 — taxonomy coordinates
      :taxonomy
        { what:  "rates.swap.fixed-float"
          how:   "lifecycle.deadline-gate"
          why:   "risk-mitigation"
          where: "au.asx" }

      ;; Annotation 3 — governance context
      :governance
        { trustClass:          "authoritative"
          proofRequirement:    "formal"
          executionAuthority:  "hat_scoped"
          linearity:           "AFFINE"
          allowedEmitOps:      ["timeConstraint"] }

      ;; Annotation 4 — identity binding
      :identity
        { subject: { type: "domainFlag", flag: 0x00020010 } }

      :action "time-gate"

      :constraint
        { kind: "temporal"
          op:   "before"
          iso:  "2026-04-22T17:00:00Z" }

      :gate
        { type:     "temporal"
          deadline: "2026-04-22T17:00:00Z" }

      :provenance
        { source:             "api"
          expressedAt:        "2026-04-21T09:00:00Z"
          trustAtExpression:  "authoritative" })


    ;; Node $s2 — PROHIBITION
    ;; Settlement is prohibited while the margin obligation is outstanding.
    ;; Linearity: RELEVANT — the prohibition persists until the obligation
    ;; is fulfilled.
    (sir-node
      :id "$s2"

      ;; Annotation 1 — jural category
      :category prohibition

      ;; Annotation 2 — taxonomy coordinates
      :taxonomy
        { what:  "rates.swap.fixed-float"
          how:   "lifecycle.settlement-gate"
          why:   "risk-mitigation"
          where: "au.asx" }

      ;; Annotation 3 — governance context
      :governance
        { trustClass:          "authoritative"
          proofRequirement:    "formal"
          executionAuthority:  "hat_scoped"
          linearity:           "RELEVANT"
          allowedEmitOps:      ["domainCheck" "comparison"
                                "logical_not" "logical_and"] }

      ;; Annotation 4 — identity binding
      :governance-domain
        { flag:         0x00020010
          domainType:   "corporate"
          instrumentId: "cdm-clearing-agreement-cell-id"
          realm:        "au.asx" }

      :identity
        { subject: { type: "role", name: "clearing-house" } }

      :action "prohibit-settlement"

      :constraint
        { kind: "composite"
          op:   "and"
          children: [
            { kind: "domain"
              flag: 0x00020010 }
            { kind: "state"
              requiredPhase: "margin-fulfilled" }
          ] }

      :provenance
        { source:             "api"
          expressedAt:        "2026-04-21T09:00:00Z"
          trustAtExpression:  "authoritative" })

  ])
```

This program illustrates all four annotation kinds on each node. The jural categories are: obligation (`$s0`) — the margin call itself; condition (`$s1`) — the temporal deadline gate; and prohibition (`$s2`) — the settlement block pending fulfillment. A fourth category, transfer, would appear in the settlement node that this program gates, but that node belongs to a separate SIR program invoked after the obligation is fulfilled.

The taxonomy coordinates carry the `au.asx` jurisdictional scope in the `where` field and differentiate the three operations at the `how` level (`lifecycle.margin-call`, `lifecycle.deadline-gate`, `lifecycle.settlement-gate`) even though all three operate on the same instrument (`rates.swap.fixed-float` in the `what` field).

The governance context on `$s0` carries `allowedEmitOps: ["domainCheck", "timeConstraint", "capability", "logical_and"]`. The lower pass enforces this: if the lowering of `$s0` would produce a `hostCall` binding or a `comparison` binding, the lower pass rejects the program before any OIR is emitted. The SCADA prohibition in `$s2`'s `allowedEmitOps` permits `comparison` and `logical_not` — appropriate for a value-threshold interlock — but would not permit `hostCall`.

The identity binding on `$s0` carries a specific certificate identifier alongside the role reference. On `$s1`, the identity is expressed as a domain flag reference — the condition is owned by the domain itself, not by a named party. On `$s2`, the identity is the clearing house role. Each binding is appropriate to the category and action of its node.

---

## 8. Summary

The SIR is the layer at which the compression gradient acquires a vocabulary for meaning. The OIR, sitting below it, carries mechanism — the computational predicates that the cell engine evaluates. The SIR, sitting above, carries the four annotation kinds that give each expression its semantic identity: jural category (what kind of act is being performed), taxonomy coordinates (in which domain, under which operation, for what purpose, in which jurisdiction), governance context (at what trust class, under what proof requirement, with what execution authority, with what linearity, subject to what emit-op whitelist), and identity binding (who is performing the act and under what certificate authority).

The lower pass from SIR to OIR is where enforcement happens. Each of the seven jural categories has a canonical lowering pattern. The governance context is enforced structurally — an authoritative expression without formal proof is rejected at the IR level, not just at the governance-plane boundary. The allowedEmitOps whitelist operates at the OIR binding-kind level, which is the correct level of abstraction: a SCADA prohibition cannot accidentally lower to a transfer opcode.

The worked program above illustrates a CDM margin-call scenario with three nodes — obligation, condition, prohibition — each carrying all four annotation kinds. The settlement transfer that this program gates would be a fourth node in a separate SIR program, invoked only after the margin obligation is marked fulfilled.

For the formal treatment of the SIR → OIR lowering relation — the function `lowerSIR : SIR → Error + OIR`, the trust-tier enforcement clause, and the α-equivalence property — see paper A2 — A Two-IR Architecture for Verifiable Computation — for the formal lowering relation.
