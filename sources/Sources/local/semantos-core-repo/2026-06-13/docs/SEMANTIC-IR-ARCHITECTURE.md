---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SEMANTIC-IR-ARCHITECTURE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.328960+00:00
---

# Semantic IR — A Linguistic Foundation for the Semantos Intermediate Representation

**Date**: 2026-04-17
**Status**: Architectural proposal
**Precondition**: `semantos-ir` (opcode IR, ANF, golden-file tested) merged via PR #80.

---

## 1. The Problem

The compression gradient — NL → CLI → Lisp → IR → opcodes → economic effect — is the architecture's central claim. But the current IR (`packages/semantos-ir`) sits between `ConstraintExpr` and opcode bytes. By the time meaning reaches it, every linguistic, legal, and economic category has been erased. What remains is mechanism: push a number, compare a field, check a capability, boolean-and, verify.

This matters because the system makes a stronger claim than "we can compile constraints." It claims that a CDM novation, a SCADA emergency shutdown, a governance ballot, a Ricardian contract clause, and "kill the process on port 9000" are **the same kind of thing at different abstraction levels**. If the IR cannot represent what makes them different — not just how they're enforced — then that claim is architectural intention without a verification surface.

The lisp compiler is correct for what it does. But it expresses the *enforcement grammar* of the system, not the *semantic grammar*. The types available — comparison, logical, capability, domainCheck, timeConstraint, hostCall, typeHashCheck, deref — are the mechanism primitives of the cell engine. They answer "how does the machine check this?" They don't answer "what is being said?" A capability check for a CDM clearing and a capability check for a SCADA valve command use the same opcode. The IR cannot distinguish them. The governance plane can (it reads the manifest), but the IR itself is semantically flat.

This document proposes a **Semantic IR** (SIR) that sits above the opcode IR (OIR), grounded in the categories of meaning that matter for legal instruments, economic execution, and governed computation. The SIR is what all surface frontends — Lisp, Rúnar, Lean-ish, LaTeX, Ricardian, EDI — should target. The OIR remains the compilation target for the cell engine.

---

## 2. The Two-IR Architecture

The revised compression gradient:

```
NL / voice / signals / legacy data
    │
    ▼
expression layer          (voice, text, UI skins, API responses)
    │
    ▼
surface syntax            (Lisp, Rúnar, Lean-ish, LaTeX, Ricardian, EDI, SCADA-DSL)
    │                      ↑
    ▼                      │  InferenceAgent proposes; governance ratifies
    │                      │
┌───▼──────────────────────┴───────────────────────────────────┐
│                    SEMANTIC IR (SIR)                          │
│                                                              │
│  Jural categories    + taxonomy coordinates  + governance    │
│  (declaration,         (what/how/why/where)    context       │
│   obligation,                                 (trust class,  │
│   permission,                                  proof req,    │
│   prohibition,                                 exec auth,    │
│   power,                                       linearity)    │
│   condition,                                                 │
│   transfer)                                                  │
└──────────────────────────┬───────────────────────────────────┘
                           │
                    lower (SIR → OIR)
                           │
┌──────────────────────────▼───────────────────────────────────┐
│                    OPCODE IR (OIR)                            │
│                                                              │
│  ANF bindings   (comparison, logical, capability,            │
│                  domainCheck, timeConstraint, hostCall,       │
│                  typeHashCheck, deref)                        │
│                                                              │
│  packages/semantos-ir — already merged, golden-file tested   │
└──────────────────────────┬───────────────────────────────────┘
                           │
                        emit (OIR → bytes)
                           │
                    ┌──────▼──────┐
                    │ Cell Engine  │
                    │ (Zig 2PDA)  │
                    └─────────────┘
```

**SIR** captures *what is being expressed* — the jural category, the domain taxonomy, the governance context, the linearity, the trust tier. It is the representation that makes the compression gradient's "same thing at different levels" claim verifiable.

**OIR** captures *how the machine enforces it* — the computational predicates in ANF that the cell engine evaluates. It is already built and tested.

The **lower** pass from SIR to OIR is where semantic enforcement happens. This is the critical contribution: a transfer with `trust_class: "authoritative"` lowers differently than a transfer with `trust_class: "cosmetic"`. The enforcement is structural, not an external check.

---

## 3. Jural Categories — The Semantic Primitives

The fundamental claim: every meaningful expression in the system — every shell command, every grammar patch, every lifecycle event, every interlock policy, every contract clause — reduces to a small number of **jural categories**. These categories come from Hohfeldian analysis (the standard decomposition of legal relations into atomic types) extended for computational governance.

### 3.1 The Seven Categories

**Declaration** — an assertion of fact or state. Linearity: typically RELEVANT (evidence cannot be destroyed). Examples:

- A telemetry reading (`TelemetryCell` in SCADA — AFFINE because it can be superseded, but the reading itself is a declaration)
- A CDM confirmation event (`CDMLifecycleEvent` with `eventType: 'confirmation'`)
- An attestation (`PlexusStandardFlags.ATTESTATION`)
- `semantos verify <objectId>` — a declaration that the evidence chain is valid
- A regulatory report (`RegulatoryReport` — RELEVANT, cannot be destroyed)

**Obligation** — a duty that must be fulfilled. Linearity: LINEAR (the obligation exists once and must be consumed by fulfillment or default). Examples:

- A CDM payment event due on a date (`CDMLifecycleEvent` with `eventType: 'payment'`, gated by `time-before`)
- A SCADA alarm requiring acknowledgment (`AlarmCell` — LINEAR, MUST be consumed)
- A margin call (`CDMLifecycleEvent` with `eventType: 'margin-call'`)
- A governance ballot deadline (`GovernanceBallot.escalationDeadline`)

**Permission** — authorisation to perform an action. Linearity: RELEVANT (the permission persists until revoked). Examples:

- A capability grant (`has-capability N` — the opcode enforcement of permission)
- An operator's shift capability token (`SCADACapabilityToken`)
- A facet's `capabilities: number[]` array
- `semantos capabilities` — listing what the active facet may do

**Prohibition** — a constraint that an action must NOT occur. Linearity: RELEVANT (the prohibition persists). Examples:

- An interlock policy (`InterlockPolicy` — compiled to bytes, enforced before command execution)
- A SCADA safety constraint (pressure > threshold → prohibit valve.open)
- The `allowedEmitOps` whitelist (§4.3 of the alignment memo) — a prohibition on certain opcodes
- `enforceL0Constraints` rejecting `authoritative` without `formal` proof
- The trust-tier conservative-by-default enforcement: `delegated` execution is prohibited

**Power** — authority to change legal or economic relations. Linearity: varies (the exercise of a power may be LINEAR — a one-shot action — or RELEVANT — a standing authority). Examples:

- `semantos publish <objectId>` — the power to transition AFFINE → RELEVANT
- CDM novation (`eventType: 'novation'` — transfers legal relation to a new party)
- CDM close-out netting (`eventType: 'close-out-netting'` — exercises the power to net obligations)
- `semantos govern propose-patch` — the power to propose grammar changes
- `semantos govern dispute create` — the power to escalate from L2 → L1
- A governance ballot vote (`semantos vote`)
- `host.exec` — the power to execute a whitelisted host handler (gated by `HOST_EXEC`)

**Condition** — a temporal or state-dependent trigger. Linearity: AFFINE (the condition is consumed when evaluated, though it may be re-created). Examples:

- `(time-after "2026-04-22")` — a temporal gate
- `(time-before "2026-04-22")` — a deadline condition
- A `TransitionGuard` on a commerce phase FSM (`guard.type: 'time' | 'value' | 'relationship' | 'contextual'`)
- CDM lifecycle state prerequisite (must be `confirmed` before `cleared`)
- SCADA mode prerequisite (must be `MANUAL` before `override`)

**Transfer** — movement of value, rights, or obligations between parties. Linearity: LINEAR (the transfer happens once; duplication would be double-spending). Examples:

- `semantos transfer <objectId> --to <facetId>`
- `semantos settle` — BSV settlement via the border-router aggregator
- CDM settlement event (`eventType: 'settlement'` — transfer of economic value)
- SCADA shift handover (`ShiftHandoverReceipt` — transfer of capability tokens)
- `HostCommand` execution with economic effect (the publish-then-execute semantics are a transfer of execution authority)

### 3.2 Why These Categories

These aren't arbitrary. Hohfeldian jural relations (right/duty, privilege/no-right, power/liability, immunity/disability) have been the standard decomposition in legal theory since 1913. The seven categories above are Hohfeld adapted for computational governance:

- **Declaration** maps to Hohfeld's "claim-right" exercised as assertion (I have the right to state this fact)
- **Obligation** maps to "duty" (the correlative of someone's right)
- **Permission** maps to "privilege" (absence of duty not to)
- **Prohibition** maps to "no-right" / duty-to-refrain
- **Power** maps directly to Hohfeld's "power" (ability to change legal relations)
- **Condition** extends the temporal dimension Hohfeld assumed but didn't formalise
- **Transfer** is the canonical exercise of power over economic relations

The point is not jurisprudential correctness for its own sake. The point is that these categories are **the minimum set needed to distinguish everything the system does**. A CDM novation and a SCADA alarm acknowledgment are both exercises of power (they change relations), but one is a transfer-power over financial obligations and the other is a consume-power over a safety event. The SIR makes this distinction first-class. The OIR cannot.

### 3.3 Mapping Existing System Verbs to Categories

| Shell verb | Primary category | Secondary | Notes |
|---|---|---|---|
| `new` | Power | — | Creates a new object (exercises power to bring something into existence) |
| `patch` | Declaration | — | Asserts new facts about an existing object |
| `publish` | Power | — | Transitions AFFINE → RELEVANT (changes the object's legal status) |
| `revoke` | Power | Prohibition | Revokes a published object (exercises power + establishes prohibition on future use) |
| `sign` | Declaration | — | Attestation (asserts identity binding) |
| `verify` | Declaration | — | Asserts chain validity |
| `transfer` | Transfer | Power | Movement of ownership |
| `settle` | Transfer | — | BSV settlement |
| `stake` | Transfer | Obligation | Locks value (transfer into escrow + creates obligation to participate) |
| `vote` | Power | — | Exercises governance power |
| `dispute` | Power | Condition | Initiates escalation (conditional on dispute window) |
| `govern propose-patch` | Power | — | Proposes grammar change |
| `govern approve` | Power | — | Ratifies proposed change |
| `host.exec` | Power | Transfer | Executes host command (exercises execution authority) |
| `infer` | Declaration | — | Proposes inferred structure (assertion, not yet ratified) |
| `infer approve` | Power | — | Ratifies inferred grammar |
| `infer reject` | Prohibition | Declaration | Rejects + asserts reason |
| `flow` | Condition | — | Triggers a multi-step conditional process |
| `compile` | — | — | Pure computation, not a jural act |
| `eval` | — | — | Pure computation |

Note: `compile` and `eval` are not jural acts — they are the mechanism layer. The SIR doesn't represent them because they don't express meaning; they implement it.

### 3.4 Mapping Existing Domain Types to Categories

**CDM lifecycle events:**

| CDM EventType | Category | Linearity | Taxonomy (what/how/why) |
|---|---|---|---|
| `execution` | Power | LINEAR | product-type / lifecycle.execution / economic-intent |
| `confirmation` | Declaration | RELEVANT | product-type / lifecycle.confirmation / compliance |
| `clearing` | Power | LINEAR | product-type / lifecycle.clearing / risk-mitigation |
| `settlement` | Transfer | LINEAR | product-type / lifecycle.settlement / obligation-fulfillment |
| `novation` | Transfer + Power | LINEAR | product-type / lifecycle.novation / relationship-change |
| `payment` | Transfer | LINEAR | product-type / lifecycle.payment / obligation-fulfillment |
| `margin-call` | Obligation | LINEAR | product-type / lifecycle.margin / risk-mitigation |
| `default` | Declaration | RELEVANT | product-type / lifecycle.default / failure |
| `close-out-netting` | Power + Transfer | LINEAR | product-type / lifecycle.close-out / portfolio-resolution |
| `rate-reset` | Condition | AFFINE | product-type / lifecycle.reset / contractual-mechanism |
| `partial-termination` | Power | LINEAR | product-type / lifecycle.termination / partial-unwinding |
| `full-termination` | Power | LINEAR | product-type / lifecycle.termination / full-unwinding |

**SCADA operations:**

| SCADA action | Category | Linearity | Notes |
|---|---|---|---|
| Telemetry reading | Declaration | AFFINE | Sensor asserts a measurement |
| `valve.open` / `motor.start` | Power | LINEAR | Exercise authority over equipment |
| `emergency.shutdown` | Power + Prohibition | LINEAR | Exercise authority + prohibit all further operations |
| `setpoint.change` | Power | LINEAR | Change operational parameter |
| `alarm.acknowledge` | Power (consume) | LINEAR | Consumes the alarm obligation |
| Interlock evaluation | Prohibition | RELEVANT | Standing constraint, persists |
| Shift handover | Transfer | LINEAR | Capability tokens change hands |
| Equipment commissioning | Power | RELEVANT | Brings equipment into service permanently |

---

## 4. SIR Type Definitions

### 4.1 The SIR Node

```typescript
/**
 * Semantic IR node — the canonical representation of a meaningful
 * expression in the Semantos system.
 *
 * Every surface frontend (Lisp, Rúnar, Lean-ish, LaTeX, Ricardian, EDI)
 * lowers into SIRProgram. The OIR (packages/semantos-ir) lowers from here.
 */

/** The seven jural categories. */
type JuralCategory =
  | 'declaration'    // assertion of fact or state
  | 'obligation'     // duty that must be fulfilled
  | 'permission'     // authorisation to act
  | 'prohibition'    // constraint that action must not occur
  | 'power'          // authority to change relations
  | 'condition'      // temporal or state-dependent trigger
  | 'transfer';      // movement of value, rights, or obligations

/** Taxonomy coordinates (what/how/why/where). */
interface TaxonomyCoordinates {
  what: string;           // e.g. "rates.swap.fixed-float", "sensor.pressure.gauge"
  how: string;            // e.g. "lifecycle.settlement", "command.valve.open"
  why: string;            // e.g. "obligation-fulfillment", "safety-interlock"
  where?: string;         // optional spatial/jurisdictional coordinate
}

/** Governance context — carried through the IR, enforced at lowering. */
interface GovernanceContext {
  trustClass: 'cosmetic' | 'interpretive' | 'authoritative';
  proofRequirement: 'none' | 'attestation' | 'formal';
  executionAuthority: 'local_facet' | 'hat_scoped' | 'delegated';
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';

  /** Opcode families this expression is allowed to emit. */
  allowedEmitOps?: string[];
  /** Maximum elaboration depth for nested expressions. */
  maxElaborationDepth?: number;
}

/** Identity binding — who is expressing this. */
interface SIRIdentity {
  subject: IdentityRef;   // role | domainFlag | certPattern
  facetId?: string;
  certId?: string;
}

/** The core SIR node. */
interface SIRNode {
  /** Unique node ID (counter-based, like OIR: "$s0", "$s1", ...) */
  id: string;

  /** What jural category is being expressed. */
  category: JuralCategory;

  /** What domain this expression operates in. */
  taxonomy: TaxonomyCoordinates;

  /** Who is expressing this and under what authority. */
  identity: SIRIdentity;

  /** Governance context — determines how this node lowers to OIR. */
  governance: GovernanceContext;

  /** The action being expressed (maps to shell verb or domain event). */
  action: string;

  /** The constraint that must hold for this expression to be valid. */
  constraint: SIRConstraint;

  /** Target of the expression (object ID, equipment ID, product ID, etc.). */
  target?: SIRTarget;

  /** For transfers: the receiving party. */
  transferTo?: SIRIdentity;

  /** For conditions: the temporal or state gate. */
  gate?: SIRGate;

  /** For obligations: the deadline and fulfillment criteria. */
  fulfillment?: SIRFulfillment;

  /** Source provenance (inference run, manual entry, voice, etc.). */
  provenance: SIRProvenance;
}
```

### 4.2 Supporting Types

```typescript
/** SIR constraint — a typed semantic constraint, not raw predicates. */
type SIRConstraint =
  | { kind: 'capability'; required: number; name: string }
  | { kind: 'domain'; flag: number | string }
  | { kind: 'identity'; ref: IdentityRef }
  | { kind: 'temporal'; op: 'before' | 'after'; iso: string }
  | { kind: 'value'; field: string; op: ComparisonOp; value: number | string }
  | { kind: 'state'; requiredPhase: string }
  | { kind: 'interlock'; policyId: string; policyName: string }
  | { kind: 'composite'; op: 'and' | 'or' | 'not'; children: SIRConstraint[] };

/** What the expression targets. */
interface SIRTarget {
  objectId?: string;
  typePath?: string;
  typeHash?: string;
  equipmentId?: string;     // SCADA
  productCellId?: string;   // CDM
}

/** Temporal or state gate for conditions. */
interface SIRGate {
  type: 'temporal' | 'state' | 'value';
  /** For temporal: ISO timestamp */
  deadline?: string;
  /** For state: required phase */
  requiredPhase?: string;
  /** For value: threshold */
  threshold?: { field: string; op: ComparisonOp; value: number };
}

/** Fulfillment criteria for obligations. */
interface SIRFulfillment {
  /** What event fulfills this obligation */
  fulfilledBy: string;
  /** Deadline for fulfillment */
  deadline?: string;
  /** What happens on default */
  defaultAction?: string;
}

/** Provenance — where did this expression come from. */
interface SIRProvenance {
  source: 'manual' | 'inferred' | 'voice' | 'api' | 'scheduler' | 'monitor';
  /** If inferred: confidence score (0.0–1.0) */
  confidence?: number;
  /** If inferred: the inference run ID */
  inferenceRunId?: string;
  /** Timestamp of expression */
  expressedAt: string;
  /** Trust tier at time of expression */
  trustAtExpression: 'cosmetic' | 'interpretive' | 'authoritative';
}

/** A complete SIR program — one or more nodes with a designated result. */
interface SIRProgram {
  nodes: SIRNode[];
  /** The primary node (what the program "does"). */
  primaryNodeId: string;
  /** Governance context for the whole program. */
  programGovernance: GovernanceContext;
}
```

### 4.3 The Epistemic Dimension

The SIR carries `provenance.source` and `provenance.confidence` as first-class fields. This is where the hard/soft predicate distinction from §4.4 of the alignment memo becomes structural:

- `trustAtExpression: 'authoritative'` + `proofRequirement: 'formal'` → hard predicate. The lower pass emits OIR nodes that can participate in economic execution.
- `trustAtExpression: 'interpretive'` + `proofRequirement: 'attestation'` → checked predicate. The lower pass emits OIR nodes gated by attestation verification.
- `trustAtExpression: 'cosmetic'` + `source: 'inferred'` → soft predicate. The lower pass either emits advisory-only nodes (no economic effect) or refuses to lower entirely, depending on the `allowedEmitOps` whitelist.

This is the defence-in-depth the alignment memo calls for. The governance plane checks trust tiers before lowering. The SIR → OIR lower pass **also** checks, because the trust tier is carried in the IR itself. Two independent enforcement points.

---

## 5. The Lower Pass: SIR → OIR

The lower pass is where semantic categories become computational predicates. Each jural category has a canonical lowering pattern.

### 5.1 Lowering Rules

**Declaration** → identity check + field assertions + VERIFY

```
SIR: declaration(subject=buyer, action=confirm, taxonomy=rates.swap/lifecycle.confirmation)
OIR: $0 = domainCheck(buyer-flag)
     $1 = comparison(status, =, "executed")   // must be in executed state to confirm
     $2 = logical_and($0, $1)
     → VERIFY
```

**Obligation** → temporal gate + capability check + VERIFY (the temporal gate is the deadline; VERIFY fails if missed)

```
SIR: obligation(subject=clearing-member, action=margin-post, deadline="2026-04-22T17:00:00Z")
OIR: $0 = domainCheck(clearing-member-flag)
     $1 = timeConstraint(timeBefore, 1745341200)    // deadline
     $2 = capability(METERING)                       // metering cap for economic action
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

**Permission** → capability check (the simplest lowering — a permission IS a capability predicate)

```
SIR: permission(subject=shift-supervisor, action=operate-valves)
OIR: $0 = capability(3)    // capability 3 = operate valves (SCADA role map)
     → VERIFY
```

**Prohibition** → constraint check + NOT + VERIFY (the predicate must be FALSE for the action to proceed)

```
SIR: prohibition(action=valve.open, constraint=interlock(pressure > 150))
OIR: $0 = comparison(pressure, >, 150)
     $1 = logical_not($0)        // prohibition: the dangerous condition must NOT hold
     → VERIFY
```

**Power** → identity check + capability check + domain check + VERIFY

```
SIR: power(subject=governor, action=publish, trustClass=interpretive)
OIR: $0 = domainCheck(governor-flag)
     $1 = capability(PUBLISH)
     $2 = typeHashCheck(<manifest-type-hash>)
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

**Condition** → temporal or state predicate (lowered inline as a gate on the containing expression)

```
SIR: condition(gate=temporal(after="2026-04-22"))
OIR: $0 = timeConstraint(timeAfter, 1745280000)
```

**Transfer** → identity check (sender) + identity check (receiver) + capability check + VERIFY

```
SIR: transfer(from=seller, to=buyer, action=settlement)
OIR: $0 = domainCheck(seller-flag)           // sender must be the seller
     $1 = capability(TRANSFER)                // must have transfer capability
     $2 = capability(METERING)                // economic action requires metering
     $3 = logical_and($0, $1, $2)
     → VERIFY
```

### 5.2 Trust-Tier Enforcement in the Lower Pass

The lower pass inspects `governance.trustClass` and `governance.proofRequirement` to gate what OIR nodes can be emitted:

```typescript
function lowerNode(node: SIRNode): IRProgram {
  // Trust-tier enforcement — structural, not just governance-plane
  if (node.governance.trustClass === 'authoritative' &&
      node.governance.proofRequirement !== 'formal') {
    throw new LoweringError(
      `Cannot lower authoritative expression without formal proof requirement. ` +
      `Node ${node.id} (${node.category}/${node.action}) rejected at IR level.`
    );
  }

  if (node.governance.executionAuthority === 'delegated') {
    throw new LoweringError(
      `Delegated execution authority not yet implemented. ` +
      `Node ${node.id} rejected at IR level.`
    );
  }

  // AllowedEmitOps whitelist enforcement
  if (node.governance.allowedEmitOps) {
    // The emitted OIR nodes must be within the whitelist
    const emitted = lowerCategory(node);
    for (const binding of emitted.bindings) {
      if (!node.governance.allowedEmitOps.includes(binding.kind)) {
        throw new LoweringError(
          `OIR node kind '${binding.kind}' not in allowedEmitOps for ${node.id}. ` +
          `Whitelist: [${node.governance.allowedEmitOps.join(', ')}]`
        );
      }
    }
    return emitted;
  }

  return lowerCategory(node);
}
```

This is the answer to Todd's pushback: half-enforcement is worse than no field. The SIR lower pass doesn't just read the fields — it structurally refuses to produce OIR if the governance context is violated. The enforcement is in the compilation pipeline, not just the publication check.

### 5.3 AllowedEmitOps Becomes Meaningful

§4.3 of the alignment memo noted that `allowedEmitOps` would whitelist against opcode bytes without an IR, which is "enforceability at the wrong level of abstraction." With the two-IR architecture, `allowedEmitOps` on a SIR node whitelists against **OIR binding kinds** (comparison, logical, capability, domainCheck, etc.) — the right abstraction level. A SCADA interlock policy that should only emit comparisons and prohibitions cannot accidentally emit a hostCall or a transfer opcode.

---

## 6. What This Unlocks

### 6.1 Peer-Frontend Equivalence (the Rúnar methodology, properly)

With the SIR, two surface frontends can be compared at the semantic level, not just at the opcode level. A Lisp expression and a Ricardian clause that express the same obligation should produce the same SIR node (same category, same taxonomy, same governance context) even if they produce slightly different OIR (because the Ricardian parser might add additional human-readable metadata). The golden-file conformance suite extends from OIR (byte-identical opcodes) to SIR (semantically equivalent nodes).

### 6.2 Inferred Grammar Classification

When `InferenceAgent` proposes a grammar from an unfamiliar API, the SIR gives it a vocabulary for what the grammar **means**, not just what fields it has. The `StructureAnalyzer` currently outputs `EntityGraph` with nodes and edges. With the SIR, it can output `SIRNode[]` with jural categories — "this entity looks like a Transfer, that one looks like an Obligation, this field is a Condition gate." The taxonomy mapper can then verify that the proposed categories align with the taxonomy coordinates.

### 6.3 DomainRiskTier Enforcement

The SCADA sequencing problem from §4.10 of the alignment memo — that a SCADA grammar could be promoted through the same pipeline as a CDM grammar — becomes enforceable at the SIR level. A `DomainRiskTier` on the `SIRProgram.programGovernance` determines what lowering patterns are permitted. An `extreme`-risk SIR program requires multi-sig approval before lowering. A `cosmetic`-risk one can lower freely.

### 6.4 The Continuous Paskian Monitor Gets a Type System

When the Paskian plane becomes a continuous service (§4.8 of the alignment memo), it proposes grammar patches. Those patches are currently untyped — they're `ExtensionGrammar` objects with field schemas. With the SIR, the monitor proposes **semantically typed** patches: "I observed a new entity that behaves like an Obligation with a temporal Condition." The governance plane can then evaluate whether the proposed semantic category is appropriate for the domain risk tier, whether the trust class is adequate, and whether the implied lowering pattern falls within allowed emit ops — all before a human reviewer sees it.

### 6.5 Ricardian Contracts Become Natural

A Ricardian contract is human-readable legal prose with machine-executable clauses. The seven jural categories **are** the clause types of a contract:

- Recitals → Declarations
- Performance clauses → Obligations
- Licences → Permissions
- Restrictive covenants → Prohibitions
- Termination / amendment / assignment clauses → Powers
- Conditions precedent → Conditions
- Payment / delivery clauses → Transfers

A Ricardian parser that produces SIRNodes maps directly onto the jural categories. The legal surface grammar and the machine IR share a vocabulary. This is what "instruments at their highest expression" means concretely — the IR speaks the language of instruments.

---

## 7. Sequencing

This fits into the existing window structure from the implementation plan:

**Window 3 (parallel with Phase 38B/C/G):**
- Define `packages/semantos-sir/src/types.ts` — the SIR types from §4
- Implement `lower-sir.ts` — SIR → OIR lowering with trust-tier enforcement
- Write golden-file tests: representative SIR nodes for each jural category, verify they produce correct OIR
- Do NOT modify `lisp/compiler.ts` yet — prove the shape first

**Window 4 (after IR extraction):**
- Rewire `LispCompiler.compilePolicy()` to go Lisp → SIR → OIR → bytes
- Rewire Rúnar frontend to target SIR (not OIR directly)
- Extend golden-file suite: Lisp and Rúnar producing same SIR for same semantics

**Window 5 (peer frontends):**
- Ricardian parser → SIR
- Lean-ish frontend → SIR
- Semantos TeX Profile → SIR
- EDI adapter → SIR (via InferenceAgent proposing SIR-typed grammars)

**Window 6 (continuous monitor):**
- InferenceAgent proposes SIR-typed grammar patches
- DomainRiskTier enforcement on SIR programs
- AllowedEmitOps enforcement at SIR → OIR boundary

---

## 8. What This Document Does NOT Do

1. **Does not replace the OIR.** `packages/semantos-ir` stays. It is correct and tested. The SIR sits above it.
2. **Does not require rewriting the lisp compiler.** The existing path (Lisp → ConstraintExpr → OIR → bytes) continues to work. The SIR is a parallel path that proves the semantic shape. Lisp gets rewired through SIR in Window 4.
3. **Does not define the Ricardian parser.** That's Window 5 work. This document defines the IR it would target.
4. **Does not add post-quantum signatures.** The WOTS+/SLH-DSA work from the Rúnar analysis is orthogonal.
5. **Does not redesign the governance plane.** The existing L0/L1/L2 hierarchy is correct. The SIR carries governance context; it doesn't replace the governance engine.

---

## 9. The Compression Gradient, Completed

With both IRs, the full compression gradient becomes:

```
"kill the process on port 9000"                    ← natural language
    │
    ▼
semantos host.exec process.killByPort --port 9000  ← CLI
    │
    ▼
(policy                                             ← Lisp surface syntax
  :subject operator
  :action host.exec
  :constraint (and
    (has-capability 11)
    (check-domain 0x0d))
  :linearity LINEAR)
    │
    ▼
SIRNode {                                           ← Semantic IR
  category: 'power',
  taxonomy: { what: 'host.process', how: 'exec.kill', why: 'operational' },
  governance: { trustClass: 'interpretive', proofRequirement: 'attestation',
                executionAuthority: 'hat_scoped', linearity: 'LINEAR' },
  identity: { subject: { type: 'role', name: 'operator' } },
  action: 'host.exec',
  constraint: { kind: 'composite', op: 'and', children: [
    { kind: 'capability', required: 11, name: 'HOST_EXEC' },
    { kind: 'domain', flag: 0x0d }
  ]},
  provenance: { source: 'voice', trustAtExpression: 'interpretive' }
}
    │
    ▼
IRProgram {                                         ← Opcode IR (ANF)
  bindings: [
    { name: '$0', kind: 'capability', capabilityNumber: 11 },
    { name: '$1', kind: 'domainCheck', domainFlag: 0x0d },
    { name: '$2', kind: 'logical_and', operands: ['$0', '$1'] }
  ],
  result: '$2'
}
    │
    ▼
[01 0b C3 01 0d C6 9A 69]                          ← cell engine bytes
    │
    ▼
HostCommand { exitCode: 0, stdout: "killed 12345" } ← economic effect
```

Every level is the same operation. The SIR is where you can see *what it means*. The OIR is where you can see *how it's enforced*. The bytes are what the machine runs. The effect is what the world does.

That is the compression gradient, and the Semantic IR is the layer that was missing from it.

---

## 10. Governance Domain Model — Domain Flags as Sovereign Boundaries

The kernel enforces domain isolation at the bytecode level: `OP_CHECKDOMAINFLAG` (0xC6) reads bytes 24–27 from the cell header as a u32, compares against the expected flag, and the Lean K3 proof suite guarantees totality — mismatch is failure-atomic (K3a), match succeeds (K3b), every cell is checked (K3c). This is the strongest isolation guarantee in the system. It doesn't depend on application logic, governance configuration, or access control lists. It's structural.

But the kernel doesn't know what a domain flag *means*. Flag `0x00010010` is four bytes. The cell engine enforces that only operations carrying that flag can touch cells stamped with it. What the kernel cannot express is: "this flag represents a discretionary trust governed by Queensland law, with three trustees, two beneficiaries, a duty of impartiality, and a prohibition on commingling trust property with personal assets." That meaning lives in the governance layer — and right now, the governance layer doesn't have the vocabulary for it.

This section defines how governance domains, realms, estates, trusts, and similar legal structures connect to the domain flag system through the SIR, and identifies what's missing.

### 10.1 The Enforcement Chain (What Already Works)

The path from kernel isolation to shell-level governance is complete for single-domain checks:

```
Cell header bytes 24-27        ← u32 domain flag stamped on the cell
        │
        ▼
OP_CHECKDOMAINFLAG (0xC6)     ← Zig 2PDA opcode, Lean K3-proven
        │
        ▼
PlexusCert.domainFlag          ← Optional u32 on identity certificates
        │                         derivationPath tracks descent
        ▼
domain-flags.ts                ← Namespace boundaries:
        │                         Plexus reserved:  0x01–0xFFFF
        │                         Client sovereign: 0x10000–0xFFFFFFFF
        ▼
SIR constraint                 ← { kind: 'domain', flag: 0x0001000b }
        │
        ▼
OIR binding                    ← { kind: 'domainCheck', domainFlag: 0x0001000b }
        │
        ▼
Lisp surface                   ← (check-domain 0x0001000b)
        │
        ▼
Emitted bytes                  ← [encodePushNumber(flag), 0xC6]
```

Every layer in this chain exists and is tested. The SIR carries the domain constraint as a typed object (`{ kind: 'domain', flag }`) rather than a raw number, which means the lower pass can validate the flag against the governance context before emitting the opcode. But the chain assumes a flat model: one flag, one check, one domain. Real governance structures are not flat.

### 10.2 What a Governance Domain Actually Is

A governance domain is a **sovereign scope** — a bounded region within which a coherent set of governance rules apply, backed by a domain flag namespace that the kernel enforces. In the real world, governance domains take several forms:

**Trust** — a fiduciary arrangement where a trustee holds and manages property for the benefit of beneficiaries, subject to duties and restrictions. In Semantos terms: a domain flag namespace where the trustee's hat identity carries the flag, all trust-scoped cells are stamped with it, and the governance rules encode fiduciary duties as Obligations, trustee authorities as Powers, and restrictions on trust property as Prohibitions.

**Estate** — a bundle of rights over a collection of resources under unified governance. This is what a domain flag namespace *already is* at the kernel level — all cells carrying the same flag form an estate. What's missing is the governance metadata: what kind of estate, what rights are bundled, who governs.

**Realm** — a jurisdictional scope that determines which external legal framework applies to operations within the domain. A realm adds a `where` coordinate to the taxonomy: operations in realm `au.qld` are subject to Queensland trust law; operations in realm `uk.ew` are subject to English & Welsh equity.

**Corporate entity** — a domain where governance is exercised through constitutional documents (articles, bylaws), with officers acting under delegated authority. The existing L1 governance config (`patchAcceptancePolicy`, `versionBumpRules`, `contributorFacets`) is already a simplified version of this.

**Cooperative / DAO** — a domain where governance is exercised through collective decision-making (ballots, votes, proposals). The existing Ballot, Dispute, and Resolution objects in `core.json` support this, but they're not scoped to a domain flag.

Each of these structures decomposes naturally into the seven jural categories:

```
Trust:
  Declaration  — trust deed (asserts the terms, parties, and purpose)
  Obligation   — fiduciary duties (duty of care, loyalty, impartiality)
  Permission   — trustee powers (invest, distribute, manage)
  Prohibition  — restrictions (no commingling, no self-dealing, no ultra vires)
  Power        — trustee authority to manage, power to appoint/remove)
  Condition    — vesting conditions, distribution triggers
  Transfer     — distributions to beneficiaries, settlements

Estate:
  Declaration  — title registration (asserts ownership and encumbrances)
  Obligation   — maintenance duties, tax obligations
  Permission   — usage rights (easements, licences)
  Prohibition  — restrictive covenants, zoning restrictions
  Power        — power to subdivide, mortgage, dispose
  Condition    — planning approvals, regulatory prerequisites
  Transfer     — conveyance, assignment, sub-lease

Realm:
  Declaration  — jurisdictional assertion (which law applies)
  Obligation   — regulatory compliance duties
  Permission   — licences to operate within jurisdiction
  Prohibition  — jurisdictional restrictions (cross-border controls)
  Power        — regulatory authority, judicial authority
  Condition    — jurisdictional triggers (nexus, situs, domicile)
  Transfer     — cross-realm movements (require both realms' consent)
```

### 10.3 The GovernanceContext Extension

The SIR's `GovernanceContext` (§4.1) currently carries `trustClass`, `proofRequirement`, `executionAuthority`, `linearity`, and `allowedEmitOps`. To support governance domains, it needs a `domainBinding`:

```typescript
/** Extended GovernanceContext with domain binding. */
interface GovernanceContext {
  trustClass: 'cosmetic' | 'interpretive' | 'authoritative';
  proofRequirement: 'none' | 'attestation' | 'formal';
  executionAuthority: 'local_facet' | 'hat_scoped' | 'delegated';
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  allowedEmitOps?: string[];
  maxElaborationDepth?: number;

  /** Domain flag binding — which governance domain this expression belongs to. */
  domainBinding?: DomainBinding;
}

/** Binds a SIR node to a governance domain. */
interface DomainBinding {
  /** The domain flag value (from client sovereignty namespace). */
  flag: number;

  /** What kind of governance structure this domain represents. */
  domainType: 'trust' | 'estate' | 'realm' | 'corporate' | 'cooperative' | 'personal';

  /** The governing instrument (trust deed, articles, constitution, etc.). */
  instrumentId?: string;

  /** Realm — jurisdictional scope, maps to taxonomy 'where' coordinate. */
  realm?: string;

  /** Parent domain flag, if this is a sub-domain (e.g. sub-trust). */
  parentFlag?: number;

  /** Delegation chain — who delegated authority and under what terms. */
  delegation?: DelegationChain;
}

/** Authority delegation chain within a governance domain. */
interface DelegationChain {
  /** The delegating identity (grantor / settlor / parent trustee). */
  delegator: IdentityRef;

  /** The delegated identity (delegate / sub-trustee / officer). */
  delegate: IdentityRef;

  /** What powers are delegated (subset of the delegator's powers). */
  delegatedPowers: string[];

  /** Restrictions on the delegation (prohibitions the delegate must honour). */
  restrictions: string[];

  /** Whether the delegate can further sub-delegate. */
  canSubDelegate: boolean;

  /** Expiry — when the delegation lapses. */
  expiry?: string;
}
```

When the SIR→OIR lower pass encounters a node with a `domainBinding`, it emits the `OP_CHECKDOMAINFLAG` for that domain's flag. If the domain has a `parentFlag`, the lower pass emits checks for both — the child domain flag AND the parent domain flag — enforcing the hierarchy structurally. The delegation chain determines which identity checks to emit alongside the domain check: the delegate's identity must match, and the delegated powers must be sufficient for the action's jural category.

### 10.4 Standing Up a Trust Digitally

Concrete example: a discretionary family trust under Australian law.

**1. Allocate the domain flag.** The settlor (or their governance agent) allocates a flag from the client sovereignty namespace — say `0x00020001`. All cells belonging to this trust carry this flag in bytes 24–27. The kernel now enforces that only operations carrying `0x00020001` can touch trust property. This is structural, bytecode-level, Lean-proven.

**2. Register the trust deed as a Declaration.** The trust deed itself is a SIR Declaration node with `domainBinding: { flag: 0x00020001, domainType: 'trust', realm: 'au.qld' }`. Its linearity is RELEVANT — a trust deed cannot be destroyed, only varied by the proper exercise of power.

```
SIRNode {
  category: 'declaration',
  taxonomy: { what: 'trust.discretionary.family',
              how: 'instrument.trust-deed',
              why: 'estate-planning',
              where: 'au.qld' },
  governance: {
    trustClass: 'authoritative',
    proofRequirement: 'formal',
    executionAuthority: 'hat_scoped',
    linearity: 'RELEVANT',
    domainBinding: {
      flag: 0x00020001,
      domainType: 'trust',
      realm: 'au.qld',
      instrumentId: '<trust-deed-cell-id>'
    }
  },
  action: 'declare',
  ...
}
```

**3. Encode fiduciary duties as Obligations.** Each duty the trustee owes (care, loyalty, impartiality, accounting) is a LINEAR Obligation node scoped to the trust domain. The obligation must be fulfilled (duty performed) or defaulted (breach). The SIR carries both the duty specification and the fulfillment criteria.

**4. Encode trustee powers as Powers.** The power to invest, distribute, appoint/remove beneficiaries, vary the trust — each is a Power node. The lower pass emits domain flag check + capability check + identity check for each. A distribution to a beneficiary is a Transfer node gated by the trustee's Power, scoped to the trust domain.

**5. Encode restrictions as Prohibitions.** No commingling (trust property cells cannot carry any other domain flag simultaneously). No self-dealing (trustee identity cannot appear as both sender and recipient in a Transfer). These are Prohibition nodes whose lowering emits structural guards — the cell engine enforces them at the opcode level.

**6. Cross-domain operations require both domains' consent.** If the trust needs to settle a CDM obligation (the trust is a counterparty to a derivatives trade), the Transfer crosses domain boundaries. The SIR node carries both domain flags — the trust's `0x00020001` and the CDM domain's flag — and the lower pass emits `OP_CHECKDOMAINFLAG` for both. This is where K3's single-check isolation extends: each check is independently proven total, and the `logical_and` composition ensures both must pass.

### 10.5 What's Missing (The Gaps)

The kernel isolation and the SIR categories are sufficient to *model* these structures. What doesn't yet exist is:

**1. Fiduciary object types.** No extension grammar defines a trust, a trustee role, a beneficiary class, or a fiduciary duty. This would be a new `trust-ops` extension (like `host-ops.json`) with object types for `TrustDeed` (RELEVANT, declaration), `FiduciaryDuty` (LINEAR, obligation), `TrusteeAppointment` (RELEVANT, power), and `Distribution` (LINEAR, transfer). Each carries `domainBinding` in its governance config.

**2. Estate and bundle-of-rights construct.** A domain flag namespace implicitly defines an estate (all cells with that flag), but there's no object type that declares the estate explicitly — its boundaries, its governance rules, its constituent rights. An `estate-ops` extension would formalize this.

**3. Realm metadata on taxonomy namespaces.** The `TaxonomyNamespaceReservation` in L0 policy reserves namespace strings but carries no jurisdictional metadata. Adding a `realm?: string` field (and the associated enforcement — operations in namespace X must comply with realm X's rules) is a governance-plane change.

**4. Delegation and succession chains.** `PlexusCert` has a `derivationPath` that tracks key descent, but the governance layer doesn't interpret this as authority delegation. When a trustee delegates investment authority to a fund manager, the delegation should be a Power node that creates a new `PlexusCert` with a derived domain flag, inheriting a subset of the trustee's powers. The `DelegationChain` type above captures the structure; the implementation requires the cert infrastructure to support it.

**5. Cross-domain agreements.** When two governance domains interact (trust A settles an obligation with corporate entity B), both domains' governance rules must be satisfied. The SIR can carry multiple domain constraints via `{ kind: 'composite', op: 'and', children: [domain-A-check, domain-B-check] }`, and the lower pass emits both `OP_CHECKDOMAINFLAG` instructions. But there's no protocol-level construct for a bilateral agreement between domains — a "memorandum of understanding" that both domains have ratified to permit cross-domain operations of specified jural categories.

**6. K3 extension for multi-hop DAG isolation.** K3 currently proves single-check totality (one flag, one cell, one result). When governance involves hierarchical domains (parent trust → sub-trust → delegate), the isolation proof must cover the DAG — showing that a domain check at depth N implies all ancestor checks also hold. This is a Lean extension for Window 7.

### 10.6 Sequencing

This work layers onto the existing window structure:

**Window 3 (parallel with SIR type definition):** Add `DomainBinding` and `DelegationChain` to the SIR types. Add `domainBinding` to `GovernanceContext`. Update the lower pass to emit multi-flag checks when `domainBinding.parentFlag` is present. No new extension grammars yet — prove the type shape first.

**Window 4 (after IR extraction):** Design and implement `trust-ops` extension grammar as the reference governance domain grammar. Same pattern as `host-ops.json` — object types, capabilities, governance config — but modelling fiduciary structures instead of host commands. This is the trust equivalent of `process.killByPort`: one reference implementation that proves the pattern.

**Window 5 (peer frontends):** `estate-ops`, `realm-ops` extension grammars. Ricardian parser targeting SIR with `domainBinding`. Cross-domain agreement protocol.

**Window 7 (Lean gating):** K3 extension for hierarchical domain isolation. Proof that delegation chains preserve the trust-tier invariant (a delegate cannot exceed the delegator's trust class).

### 10.7 The Deeper Point

The domain flag is four bytes in a cell header. But those four bytes are, in principle, sufficient to represent any governance structure that has ever existed in equity law — trusts, estates, corporations, partnerships, cooperatives, foundations, waqf, fideicommissum — because the kernel's guarantee is structural isolation, and the SIR's jural categories are the minimum set needed to express any instrument. The flag is the *enforcement*. The SIR is the *meaning*. The governance layer connects them.

What Semantos does that no other system does is make the connection formal: the same domain flag that the Zig 2PDA checks at the bytecode level is the same flag that the SIR carries in its `GovernanceContext`, which is the same flag that the governance layer binds to a trust deed or articles of incorporation. There is one source of truth for "which domain owns this," and it runs all the way from the kernel to King's English.

---

## 10. Governance Domain Model — Domain Flags as Sovereign Boundaries

The kernel enforces domain isolation at the bytecode level: `OP_CHECKDOMAINFLAG` (0xC6) reads bytes 24–27 from the cell header as a u32, compares against the expected flag, and the Lean K3 proof suite guarantees totality — mismatch is failure-atomic (K3a), match succeeds (K3b), every cell is checked (K3c). This is the strongest isolation guarantee in the system. It doesn't depend on application logic, governance configuration, or access control lists. It's structural.

But the kernel doesn't know what a domain flag *means*. Flag `0x00010010` is four bytes. The cell engine enforces that only operations carrying that flag can touch cells stamped with it. What the kernel cannot express is: "this flag represents a discretionary trust governed by Queensland law, with three trustees, two beneficiaries, a duty of impartiality, and a prohibition on commingling trust property with personal assets." That meaning lives in the governance layer — and right now, the governance layer doesn't have the vocabulary for it.

This section defines how governance domains, realms, estates, trusts, and similar legal structures connect to the domain flag system through the SIR, and identifies what's missing.

### 10.1 The Enforcement Chain (What Already Works)

The path from kernel isolation to shell-level governance is complete for single-domain checks:

```
Cell header bytes 24-27        ← u32 domain flag stamped on the cell
        │
        ▼
OP_CHECKDOMAINFLAG (0xC6)     ← Zig 2PDA opcode, Lean K3-proven
        │
        ▼
PlexusCert.domainFlag          ← Optional u32 on identity certificates
        │                         derivationPath tracks descent
        ▼
domain-flags.ts                ← Namespace boundaries:
        │                         Plexus reserved:  0x01–0xFFFF
        │                         Client sovereign: 0x10000–0xFFFFFFFF
        ▼
SIR constraint                 ← { kind: 'domain', flag: 0x0001000b }
        │
        ▼
OIR binding                    ← { kind: 'domainCheck', domainFlag: 0x0001000b }
        │
        ▼
Lisp surface                   ← (check-domain 0x0001000b)
        │
        ▼
Emitted bytes                  ← [encodePushNumber(flag), 0xC6]
```

Every layer in this chain exists and is tested. The SIR carries the domain constraint as a typed object (`{ kind: 'domain', flag }`) rather than a raw number, which means the lower pass can validate the flag against the governance context before emitting the opcode. But the chain assumes a flat model: one flag, one check, one domain. Real governance structures are not flat.

### 10.2 What a Governance Domain Actually Is

A governance domain is a **sovereign scope** — a bounded region within which a coherent set of governance rules apply, backed by a domain flag namespace that the kernel enforces. In the real world, governance domains take several forms:

**Trust** — a fiduciary arrangement where a trustee holds and manages property for the benefit of beneficiaries, subject to duties and restrictions. In Semantos terms: a domain flag namespace where the trustee's hat identity carries the flag, all trust-scoped cells are stamped with it, and the governance rules encode fiduciary duties as Obligations, trustee authorities as Powers, and restrictions on trust property as Prohibitions.

**Estate** — a bundle of rights over a collection of resources under unified governance. This is what a domain flag namespace *already is* at the kernel level — all cells carrying the same flag form an estate. What's missing is the governance metadata: what kind of estate, what rights are bundled, who governs.

**Realm** — a jurisdictional scope that determines which external legal framework applies to operations within the domain. A realm adds a `where` coordinate to the taxonomy: operations in realm `au.qld` are subject to Queensland trust law; operations in realm `uk.ew` are subject to English & Welsh equity.

**Corporate entity** — a domain where governance is exercised through constitutional documents (articles, bylaws), with officers acting under delegated authority. The existing L1 governance config (`patchAcceptancePolicy`, `versionBumpRules`, `contributorFacets`) is already a simplified version of this.

**Cooperative / DAO** — a domain where governance is exercised through collective decision-making (ballots, votes, proposals). The existing Ballot, Dispute, and Resolution objects in `core.json` support this, but they're not scoped to a domain flag.

Each of these structures decomposes naturally into the seven jural categories:

```
Trust:
  Declaration  — trust deed (asserts the terms, parties, and purpose)
  Obligation   — fiduciary duties (duty of care, loyalty, impartiality)
  Permission   — trustee powers (invest, distribute, manage)
  Prohibition  — restrictions (no commingling, no self-dealing, no ultra vires)
  Power        — trustee authority to manage, power to appoint/remove)
  Condition    — vesting conditions, distribution triggers
  Transfer     — distributions to beneficiaries, settlements

Estate:
  Declaration  — title registration (asserts ownership and encumbrances)
  Obligation   — maintenance duties, tax obligations
  Permission   — usage rights (easements, licences)
  Prohibition  — restrictive covenants, zoning restrictions
  Power        — power to subdivide, mortgage, dispose
  Condition    — planning approvals, regulatory prerequisites
  Transfer     — conveyance, assignment, sub-lease

Realm:
  Declaration  — jurisdictional assertion (which law applies)
  Obligation   — regulatory compliance duties
  Permission   — licences to operate within jurisdiction
  Prohibition  — jurisdictional restrictions (cross-border controls)
  Power        — regulatory authority, judicial authority
  Condition    — jurisdictional triggers (nexus, situs, domicile)
  Transfer     — cross-realm movements (require both realms' consent)
```

### 10.3 The GovernanceContext Extension

The SIR's `GovernanceContext` (§4.1) currently carries `trustClass`, `proofRequirement`, `executionAuthority`, `linearity`, and `allowedEmitOps`. To support governance domains, it needs a `domainBinding`:

```typescript
/** Extended GovernanceContext with domain binding. */
interface GovernanceContext {
  trustClass: 'cosmetic' | 'interpretive' | 'authoritative';
  proofRequirement: 'none' | 'attestation' | 'formal';
  executionAuthority: 'local_facet' | 'hat_scoped' | 'delegated';
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  allowedEmitOps?: string[];
  maxElaborationDepth?: number;

  /** Domain flag binding — which governance domain this expression belongs to. */
  domainBinding?: DomainBinding;
}

/** Binds a SIR node to a governance domain. */
interface DomainBinding {
  /** The domain flag value (from client sovereignty namespace). */
  flag: number;

  /** What kind of governance structure this domain represents. */
  domainType: 'trust' | 'estate' | 'realm' | 'corporate' | 'cooperative' | 'personal';

  /** The governing instrument (trust deed, articles, constitution, etc.). */
  instrumentId?: string;

  /** Realm — jurisdictional scope, maps to taxonomy 'where' coordinate. */
  realm?: string;

  /** Parent domain flag, if this is a sub-domain (e.g. sub-trust). */
  parentFlag?: number;

  /** Delegation chain — who delegated authority and under what terms. */
  delegation?: DelegationChain;
}

/** Authority delegation chain within a governance domain. */
interface DelegationChain {
  /** The delegating identity (grantor / settlor / parent trustee). */
  delegator: IdentityRef;

  /** The delegated identity (delegate / sub-trustee / officer). */
  delegate: IdentityRef;

  /** What powers are delegated (subset of the delegator's powers). */
  delegatedPowers: string[];

  /** Restrictions on the delegation (prohibitions the delegate must honour). */
  restrictions: string[];

  /** Whether the delegate can further sub-delegate. */
  canSubDelegate: boolean;

  /** Expiry — when the delegation lapses. */
  expiry?: string;
}
```

When the SIR→OIR lower pass encounters a node with a `domainBinding`, it emits the `OP_CHECKDOMAINFLAG` for that domain's flag. If the domain has a `parentFlag`, the lower pass emits checks for both — the child domain flag AND the parent domain flag — enforcing the hierarchy structurally. The delegation chain determines which identity checks to emit alongside the domain check: the delegate's identity must match, and the delegated powers must be sufficient for the action's jural category.

### 10.4 Standing Up a Trust Digitally

Concrete example: a discretionary family trust under Australian law.

**1. Allocate the domain flag.** The settlor (or their governance agent) allocates a flag from the client sovereignty namespace — say `0x00020001`. All cells belonging to this trust carry this flag in bytes 24–27. The kernel now enforces that only operations carrying `0x00020001` can touch trust property. This is structural, bytecode-level, Lean-proven.

**2. Register the trust deed as a Declaration.** The trust deed itself is a SIR Declaration node with `domainBinding: { flag: 0x00020001, domainType: 'trust', realm: 'au.qld' }`. Its linearity is RELEVANT — a trust deed cannot be destroyed, only varied by the proper exercise of power.

```
SIRNode {
  category: 'declaration',
  taxonomy: { what: 'trust.discretionary.family',
              how: 'instrument.trust-deed',
              why: 'estate-planning',
              where: 'au.qld' },
  governance: {
    trustClass: 'authoritative',
    proofRequirement: 'formal',
    executionAuthority: 'hat_scoped',
    linearity: 'RELEVANT',
    domainBinding: {
      flag: 0x00020001,
      domainType: 'trust',
      realm: 'au.qld',
      instrumentId: '<trust-deed-cell-id>'
    }
  },
  action: 'declare',
  ...
}
```

**3. Encode fiduciary duties as Obligations.** Each duty the trustee owes (care, loyalty, impartiality, accounting) is a LINEAR Obligation node scoped to the trust domain. The obligation must be fulfilled (duty performed) or defaulted (breach). The SIR carries both the duty specification and the fulfillment criteria.

**4. Encode trustee powers as Powers.** The power to invest, distribute, appoint/remove beneficiaries, vary the trust — each is a Power node. The lower pass emits domain flag check + capability check + identity check for each. A distribution to a beneficiary is a Transfer node gated by the trustee's Power, scoped to the trust domain.

**5. Encode restrictions as Prohibitions.** No commingling (trust property cells cannot carry any other domain flag simultaneously). No self-dealing (trustee identity cannot appear as both sender and recipient in a Transfer). These are Prohibition nodes whose lowering emits structural guards — the cell engine enforces them at the opcode level.

**6. Cross-domain operations require both domains' consent.** If the trust needs to settle a CDM obligation (the trust is a counterparty to a derivatives trade), the Transfer crosses domain boundaries. The SIR node carries both domain flags — the trust's `0x00020001` and the CDM domain's flag — and the lower pass emits `OP_CHECKDOMAINFLAG` for both. This is where K3's single-check isolation extends: each check is independently proven total, and the `logical_and` composition ensures both must pass.

### 10.5 What's Missing (The Gaps)

The kernel isolation and the SIR categories are sufficient to *model* these structures. What doesn't yet exist is:

**1. Fiduciary object types.** No extension grammar defines a trust, a trustee role, a beneficiary class, or a fiduciary duty. This would be a new `trust-ops` extension (like `host-ops.json`) with object types for `TrustDeed` (RELEVANT, declaration), `FiduciaryDuty` (LINEAR, obligation), `TrusteeAppointment` (RELEVANT, power), and `Distribution` (LINEAR, transfer). Each carries `domainBinding` in its governance config.

**2. Estate and bundle-of-rights construct.** A domain flag namespace implicitly defines an estate (all cells with that flag), but there's no object type that declares the estate explicitly — its boundaries, its governance rules, its constituent rights. An `estate-ops` extension would formalize this.

**3. Realm metadata on taxonomy namespaces.** The `TaxonomyNamespaceReservation` in L0 policy reserves namespace strings but carries no jurisdictional metadata. Adding a `realm?: string` field (and the associated enforcement — operations in namespace X must comply with realm X's rules) is a governance-plane change.

**4. Delegation and succession chains.** `PlexusCert` has a `derivationPath` that tracks key descent, but the governance layer doesn't interpret this as authority delegation. When a trustee delegates investment authority to a fund manager, the delegation should be a Power node that creates a new `PlexusCert` with a derived domain flag, inheriting a subset of the trustee's powers. The `DelegationChain` type above captures the structure; the implementation requires the cert infrastructure to support it.

**5. Cross-domain agreements.** When two governance domains interact (trust A settles an obligation with corporate entity B), both domains' governance rules must be satisfied. The SIR can carry multiple domain constraints via `{ kind: 'composite', op: 'and', children: [domain-A-check, domain-B-check] }`, and the lower pass emits both `OP_CHECKDOMAINFLAG` instructions. But there's no protocol-level construct for a bilateral agreement between domains — a "memorandum of understanding" that both domains have ratified to permit cross-domain operations of specified jural categories.

**6. K3 extension for multi-hop DAG isolation.** K3 currently proves single-check totality (one flag, one cell, one result). When governance involves hierarchical domains (parent trust → sub-trust → delegate), the isolation proof must cover the DAG — showing that a domain check at depth N implies all ancestor checks also hold. This is a Lean extension for Window 7.

### 10.6 Sequencing

This work layers onto the existing window structure:

**Window 3 (parallel with SIR type definition):** Add `DomainBinding` and `DelegationChain` to the SIR types. Add `domainBinding` to `GovernanceContext`. Update the lower pass to emit multi-flag checks when `domainBinding.parentFlag` is present. No new extension grammars yet — prove the type shape first.

**Window 4 (after IR extraction):** Design and implement `trust-ops` extension grammar as the reference governance domain grammar. Same pattern as `host-ops.json` — object types, capabilities, governance config — but modelling fiduciary structures instead of host commands. This is the trust equivalent of `process.killByPort`: one reference implementation that proves the pattern.

**Window 5 (peer frontends):** `estate-ops`, `realm-ops` extension grammars. Ricardian parser targeting SIR with `domainBinding`. Cross-domain agreement protocol.

**Window 7 (Lean gating):** K3 extension for hierarchical domain isolation. Proof that delegation chains preserve the trust-tier invariant (a delegate cannot exceed the delegator's trust class).

### 10.7 The Deeper Point

The domain flag is four bytes in a cell header. But those four bytes are, in principle, sufficient to represent any governance structure that has ever existed in equity law — trusts, estates, corporations, partnerships, cooperatives, foundations, waqf, fideicommissum — because the kernel's guarantee is structural isolation, and the SIR's jural categories are the minimum set needed to express any instrument. The flag is the *enforcement*. The SIR is the *meaning*. The governance layer connects them.

What Semantos does that no other system does is make the connection formal: the same domain flag that the Zig 2PDA checks at the bytecode level is the same flag that the SIR carries in its `GovernanceContext`, which is the same flag that the governance layer binds to a trust deed or articles of incorporation. There is one source of truth for "which domain owns this," and it runs all the way from the kernel to King's English.
