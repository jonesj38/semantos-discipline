---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.753081+00:00
---

# A Two-IR Architecture for Verifiable Computation

**Paper A2 — Draft (revision 1)**
**Todd Price, Real Blockchain Solutions**
**Queensland, Australia**
**todd@realblockchainsolutions.com**
**April 2026**

> **Status:** Draft for review. Targeted at arXiv first; conference targets include OOPSLA, POPL. Cite alongside A1 (compression gradients). Pin to canon snapshot at submission.

---

## Abstract

We argue that a single intermediate representation is insufficient for language-driven computation that makes governance claims. A conventional compiler intermediate representation (IR) carries mechanism: named bindings, type-checked transformations, optimisation passes. What it does not carry is the vocabulary of who is authorised, under what legal relationship, and with what burden of proof. We present a two-IR architecture in which an upper IR — the Semantic IR (SIR) — carries jural category, taxonomy coordinates, governance context, and identity binding, while a lower IR — the Opcode IR (OIR) in administrative normal form (ANF) — carries the operational predicates the execution layer evaluates. The key property is that the `lowerSIR` pass from SIR to OIR is a function that may refuse: governance violations — a claim of authoritative status without a formal proof requirement, an emission of a disallowed opcode family, an unresolved delegation — are caught statically at the compilation boundary rather than at execution time or in application logic. We distinguish this architecture from conventional compiler-IR-as-optimisation work: the division here is not semantic vs syntactic, and not front-end vs back-end; it is between the layer at which governance meaning lives and the layer at which mechanical enforcement is expressed. A1 (Price 2026) established the compression-gradient discipline — the sequence of typed layers from natural language to bounded execution. A2 extends that discipline with the specific upper/lower IR shape that makes the governance claims of A1 structural rather than advisory.

**Keywords:** intermediate representations, jural categories, governance, static enforcement, ANF, linear types, substructural type systems, Hohfeld.

---

## 1. Introduction

### 1.1 The problem with a single IR

Compilers have used IRs for decades. The standard motivation is separation of concerns: a front-end that understands surface syntax, an IR that has a clean formal shape suitable for optimisation passes, and a back-end that maps the IR to a target architecture. ANF [Sabry & Felleisen 1992] is one well-studied example of such an IR: every intermediate result is named, no nested computation appears in operand position, and the resulting form is structurally simpler than the source while being semantically equivalent.

ANF is an excellent shape for the OIR — the layer that the cell engine will ultimately evaluate. The OIR bindings in the Semantos substrate (comparison, logical, capability, domainCheck, timeConstraint, hostCall, typeHashCheck, deref) are exactly the kind of mechanical predicates ANF was designed to host. The OIR is already built and golden-file tested.

The problem arises one layer above. A1 (Price 2026) established that the compression gradient from natural language to bounded execution requires each layer to have a validation rule — a predicate that can refuse, not just transform. At the OIR layer, the refusal capability covers type-check failures and binding-graph violations. But governance properties — the ones that distinguish an authoritative instrument from a cosmetic annotation, a formal proof from an unsubstantiated claim, a transfer from a mere observation — are not expressible in OIR binding kinds. A `capability` binding and a `domainCheck` binding are equally available to every OIR program regardless of the governance context of the expression that produced them.

This is not a defect in OIR. It is a correct observation that OIR is the wrong layer at which to enforce governance. A `transfer` of financial obligations and a `declaration` of system state both produce OIR programs containing identity checks and comparison bindings. The OIR cannot distinguish them. The enforcement of the difference must happen somewhere. The two-IR architecture makes it happen at the SIR boundary, structurally, during compilation.

### 1.2 The two-IR claim

The central claim of this paper is: **a two-IR architecture in which an upper IR carries jural and governance metadata and a lower IR carries operational predicates admits structural enforcement of governance properties at compile time.**

Three sub-claims follow from this:

1. The seven jural categories — declaration, obligation, permission, prohibition, power, condition, transfer — are the minimum vocabulary sufficient to type every semantic act the substrate performs, and they belong in the upper IR, not in application logic.

2. The `lowerSIR : SIR → Error + OIR` pass is the structural enforcement point. Its refusal conditions are not advisory checks; they are compilation errors that prevent the existence of a malformed OIR program.

3. The α-equivalence claim of A1 — that two surface expressions of the same semantic intent must produce α-equivalent OIR — is provable at the SIR layer, not at the surface layer. Two surface grammars that express the same intent must, when lowered to SIR, produce SIR programs with equivalent jural categories, governance contexts, and constraint structures. The OIR equivalence follows from the SIR equivalence.

### 1.3 Relation to A1

A1 presented the compression gradient as an architecture and evaluated it empirically. A2 is a structural argument about the shape of the IRs within that gradient — specifically, why one IR is insufficient and what the two-IR split buys. Where A1 asked "does the gradient work?", A2 asks "why does the gradient need two IRs rather than one?" The answer is the governance-enforcement argument above.

A2 inherits A1's notation (layer indices $L_0$ through $L_4$) and refines the structure of $L_1$ (SIR) and $L_2$ (OIR). All empirical claims in A2 build on the corpus and test suite described in A1.

---

## 2. Background

### 2.1 Compiler intermediate representations as optimisation stages

The standard motivation for IRs in compiler design is transformation hygiene: separate the concerns of surface-syntax comprehension, semantic analysis, optimisation, and code generation. A well-designed IR has a canonical form that is amenable to algebraic manipulation — constant folding, dead-code elimination, inlining, register allocation — without requiring knowledge of where the code came from or where it is going.

ANF [Sabry & Felleisen 1992; Flanagan et al. 1993] achieves this by making every intermediate result explicit. No computation is nested in the argument position of another; every value has a name; continuations are sequential. The resulting form has the property that the evaluation order is fully determined by the structure of the program, not by any evaluation strategy the compiler must implement separately. This makes it easier to reason about, optimise, and compile to multiple targets.

The two-IR architecture in this paper is explicitly *not* motivated by optimisation. The split between SIR and OIR is not a front-end / back-end division in the sense of a C compiler's separation of parsing from register allocation. The split is between meaning and mechanism — between the layer at which the system represents what is being expressed and the layer at which the system represents how the cell engine enforces it. This is a different axis of concern, and it calls for a different justification.

### 2.2 Jural categories and Hohfeld's analytic framework

Hohfeld (1913) proposed a decomposition of legal relations into eight fundamental conceptions: right/duty, privilege/no-right, power/liability, immunity/disability. The claim is that every legal relation that can be asserted between two parties reduces to one of these eight atomic types, and that confusing them — treating a privilege as if it were a right, or a power as if it were an immunity — is the source of much legal error.

The jural categories used in the SIR are an adaptation of Hohfeld's framework for computational governance. The adaptation reduces the eight Hohfeldian conceptions to seven categories suited to the substrate's vocabulary:

- Declaration maps to the exercise of a claim-right: an assertion of fact that the system records.
- Obligation maps to duty: something that must happen, with a correlative liability on the obligated party.
- Permission maps to privilege: the absence of a duty not to act.
- Prohibition maps to the correlative no-right / duty-to-refrain: a constraint that an action must not occur.
- Power maps directly to Hohfeld's power: the authority to change legal or computational relations.
- Condition extends the temporal dimension that Hohfeld presupposed but did not formalise.
- Transfer is the exercise of power over economic relations: value, rights, or obligations moving between parties.

The adaptation is not merely terminological. The seven-category set is the minimum vocabulary sufficient to distinguish every act the substrate performs, across all domains: a derivatives-clearing event, a SCADA safety interlock, a governance ballot, a shell command. A1 §4.3 describes the extension; §3 of this paper demonstrates the structural consequence of placing these categories in the IR rather than in application logic.

### 2.3 Substructural types and linear resources

Wadler (1990) established that linear types — types that guarantee a resource is used exactly once — can express ownership, consumption, and non-duplication as type-theoretic properties rather than runtime invariants. The substrate's execution layer enforces substructural consumption at the bytecode gate: LINEAR cells are consumed exactly once (K1), AFFINE cells at most once, RELEVANT cells at least once.

The SIR carries linearity as a first-class field of the governance context (`linearity: LINEAR | AFFINE | RELEVANT | FUNGIBLE`). This is load-bearing: a `transfer` of a LINEAR resource (a capability token under BRC-108, a settlement UTXO) must lower to OIR in a way that the cell engine can enforce the single-consumption rule. A `declaration` of a RELEVANT resource (a regulatory report that cannot be destroyed) must lower differently. The SIR's governance context is not an annotation; it determines the shape of the lowered OIR.

The kernel invariant K1 (proved in Lean 4 in `LinearityK1.lean`) establishes that the cell engine enforces linearity at the bytecode gate. K2 (proved in `AuthSoundnessK2.lean`) establishes that any state-changing transition requires successful identity verification. K3 (proved in `DomainIsolationK3.lean`) establishes that `OP_CHECKDOMAINFLAG` is total and correct: a domain-flag mismatch is failure-atomic. K4 (proved in `FailureAtomicK4.lean`) establishes that failed Plexus opcodes leave the PDA state byte-for-byte unchanged. K5 (proved in `TerminationK5.lean`) establishes that every execution terminates within `opcountLimit` steps.

These invariants are the bottom of the enforcement stack. The SIR is the top. The two-IR architecture makes explicit the gap between them and installs a structural enforcement point at the SIR → OIR boundary.

### 2.4 Position relative to existing work

Prior work on jural analysis in computing is sparse. Hohfeld's framework has been applied in contract law formalisation and requirements engineering, but without a corresponding compilation architecture — the formal categories remain advisory labels rather than structural typing constraints. The novelty of the SIR layer is not the use of jural categories (that borrowing is straightforward) but the placement of those categories in a compilation IR where they generate refusals rather than annotations.

Prior work on trust-aware or policy-aware IRs exists in the security-types literature (e.g. information-flow type systems). These typically enforce confidentiality or integrity lattice properties at the type level. The SIR's governance context is structurally different: it enforces the combination of (a) the claimed jural category of the expression, (b) the trust class of the claim, (c) the proof requirement backing it, and (d) the linearity of the resource involved. This combination is, to our knowledge, novel as an IR design point.

---

## 3. The Two-IR Architecture

### 3.1 Structural overview

The two-IR architecture sits within the compression gradient established in A1. In A1's notation, $L_1$ is the SIR (the semantic layer) and $L_2$ is the OIR (the opcode layer in ANF). The gradient as a whole runs from $L_0$ (natural language) through $L_1$ (SIR) through $L_2$ (OIR) through $L_3$ (opcode bytes) to $L_4$ (bounded 2-PDA execution).

```
[FIGURE — needs real graphic for layout pass]

Natural language / voice / shell / API / scheduler
    │
    ▼  (producer adapter — eight producer kinds)
    │
    L₁  SEMANTIC IR (SIR)
    │   ┌──────────────────────────────────────────────┐
    │   │  JuralCategory  (declaration | obligation |  │
    │   │                  permission  | prohibition |  │
    │   │                  power       | condition   |  │
    │   │                  transfer)                    │
    │   │                                              │
    │   │  TaxonomyCoordinates  (what / how / why /    │
    │   │                        where)                │
    │   │                                              │
    │   │  GovernanceContext                           │
    │   │    trustClass     (cosmetic | interpretive   │
    │   │                    | authoritative)          │
    │   │    proofRequirement (none | attestation      │
    │   │                      | formal)               │
    │   │    executionAuthority (local_facet |         │
    │   │                        hat_scoped |          │
    │   │                        delegated)            │
    │   │    linearity      (LINEAR | AFFINE |         │
    │   │                    RELEVANT | FUNGIBLE)      │
    │   │    allowedEmitOps (optional OIR whitelist)   │
    │   │    domainBinding  (optional governance       │
    │   │                    domain)                   │
    │   │                                              │
    │   │  SIRIdentity    (subject hat, cert ref)      │
    │   │  SIRConstraint  (typed predicate tree)       │
    │   │  SIRProvenance  (source, confidence,         │
    │   │                  trustAtExpression)          │
    │   └──────────────────────────────────────────────┘
    │
    │  lowerSIR() — structural enforcement point
    │
    ▼
    L₂  OPCODE IR (OIR, ANF)
    │   ┌──────────────────────────────────────────────┐
    │   │  IRBinding[]  (ordered, topological)         │
    │   │  Each binding:                               │
    │   │    name:  "$0", "$1", ...                    │
    │   │    kind:  comparison | logical_and |          │
    │   │           logical_or | logical_not |          │
    │   │           capability | domainCheck |          │
    │   │           timeConstraint | hostCall |         │
    │   │           typeHashCheck  | deref              │
    │   │    operands: names of prior bindings          │
    │   └──────────────────────────────────────────────┘
    │
    │  emit()
    │
    ▼
    L₃  Opcode bytes (0x4C–0xD0 Plexus extension range)
    │
    ▼
    L₄  Cell engine (bounded 2-PDA, K1–K5 enforced)
```

The critical observation is that nothing in OIR or below can encode a jural category, a trust class, or a proof requirement. Those are SIR concepts. Once the program crosses the SIR → OIR boundary, the governance metadata is gone — it was used to shape the OIR, not preserved within it. This is analogous to the way type information in a typed language is used to check and transform the program but need not be preserved in machine code.

### 3.2 Why the split belongs here

A common response to the two-IR design is: why not enforce governance in a separate governance layer, outside the compilation pipeline? The answer is that governance enforcement outside the pipeline allows half-enforcement: the governance layer might check before the operation begins, but if the compiler is also consulted, and if a code path reaches the compiler without going through the governance check, the enforcement is defeated. The SIR → OIR boundary is the one place in the pipeline where every expression of intent must pass. There is no path from a surface grammar to OIR that bypasses the SIR.

A second response is: why not just add governance annotations to OIR? The answer is that OIR's canonical form is already doing load-bearing work — it is the form over which α-equivalence is defined and tested. Polluting OIR with governance metadata would make α-equivalence more complex (two OIR programs would be α-equivalent only if they agreed on governance metadata, which is a category error: governance metadata is the SIR's concern, not the OIR's). Keeping governance in SIR and mechanics in OIR keeps both IRs clean.

A third consideration is the `allowedEmitOps` whitelist. Without a two-IR architecture, whitelisting "allowed opcode families" would mean checking against raw bytes or opcode numbers — the wrong level of abstraction. With the two-IR architecture, `allowedEmitOps` on a SIR node whitelists against OIR binding kinds. A SCADA interlock policy that should only emit `comparison` and `logical_not` bindings cannot accidentally emit a `hostCall` binding, regardless of how the surface grammar is written. This is enforceable because the SIR has the semantic vocabulary to describe what kinds of OIR bindings are appropriate for this expression's purpose.

### 3.3 The seven jural categories as SIR primitives

The TypeScript type definition from `core/semantos-sir/src/types.ts` is the canonical encoding:

```typescript
export type JuralCategory =
  | 'declaration'    // assertion of fact or state
  | 'obligation'     // duty that must be fulfilled
  | 'permission'     // authorisation to act
  | 'prohibition'    // constraint that action must not occur
  | 'power'          // authority to change relations
  | 'condition'      // temporal or state-dependent trigger
  | 'transfer';      // movement of value, rights, or obligations
```

Each category carries a distinct semantics for the `lowerSIR` pass:

- Declaration lowers to an identity check plus field assertions plus VERIFY. The constraint must hold for the assertion to be recorded.
- Obligation lowers to a temporal gate (the deadline), a capability check (the metering capability for economic action), and VERIFY. Failure to fulfill before the deadline is a default event.
- Permission lowers to a single capability check. This is the simplest lowering: a permission assertion *is* a capability predicate.
- Prohibition lowers to a constraint check, a logical negation, and VERIFY. The predicate must be false for the action to proceed — the prohibition expresses what must not hold.
- Power lowers to an identity check, a capability check, a type-hash check, and VERIFY. Power over relations requires identity proof, authority, and the right type of target.
- Condition lowers inline as a temporal or state predicate gating its containing expression. It is not a standalone verification; it is a gate that the containing category's lowering incorporates.
- Transfer lowers to a sender identity check, a receiver identity check, a transfer capability check, a metering capability check, and VERIFY. A transfer must identify both parties, the authority to transfer, and the economic capacity.

These lowering patterns are not arbitrary. They follow from the Hohfeldian semantics of each category: an obligation carries a correlative liability that matures at a deadline; a prohibition is the negation of a permitted condition; a power requires an actor with the authority to change relations; a transfer is the canonical exercise of power over economic value.

### 3.4 Governance context as a first-class IR field

The governance context carried on every SIR node is not metadata for documentation; it is the input to the `lowerSIR` enforcement logic:

```typescript
export interface GovernanceContext {
  trustClass: 'cosmetic' | 'interpretive' | 'authoritative';
  proofRequirement: 'none' | 'attestation' | 'formal';
  executionAuthority: 'local_facet' | 'hat_scoped' | 'delegated';
  linearity: 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';
  allowedEmitOps?: string[];
  maxElaborationDepth?: number;
  domainBinding?: DomainBinding;
}
```

The trust class (`cosmetic | interpretive | authoritative`) is the epistemic tier of the claim. Cosmetic claims affect presentation only; they generate no OIR with economic effect. Interpretive claims affect state but require explicit user ratification before committing. Authoritative claims affect state with the full force of a formally-backed assertion; they require a `formal` proof requirement in the governance context, or `lowerSIR` refuses to compile them.

The proof requirement (`none | attestation | formal`) specifies the evidentiary burden. A `formal` proof requirement means the expression is backed by a cryptographic proof or mechanically-verified attestation — not just an assertion. The combination of `trustClass: authoritative` with `proofRequirement: formal` is the only configuration that permits an expression to have full economic effect in the substrate. Any other configuration is either advisory (cosmetic) or gated by human ratification (interpretive with attestation).

The linearity field connects the SIR's governance context to the cell engine's substructural enforcement. A `transfer` with `linearity: LINEAR` lowers to OIR in a way that the LINEAR resource is consumed exactly once; K1 enforces this at the bytecode gate. The SIR node declares the linearity; the OIR pattern reflects it; the cell engine enforces it — three independent enforcement points for the same property.

### 3.5 The domain-binding extension

The governance context carries an optional `domainBinding` field that scopes the expression to a governance domain — a sovereign scope in which a coherent set of governance rules apply, backed by a domain flag that the cell engine enforces via `OP_CHECKDOMAINFLAG` (K3). When a SIR node carries a `domainBinding`, the `lowerSIR` pass emits the `OP_CHECKDOMAINFLAG` instruction for that domain's flag, and if the binding specifies a `parentFlag` (for sub-domain hierarchies), emits checks for both.

This is what connects the human-readable vocabulary of governance domains — trust, estate, realm, corporate, cooperative — to the four bytes in the cell header that the Zig 2-PDA checks at the bytecode level. The SIR is where the meaning lives. The cell engine is where the enforcement lives. The `lowerSIR` pass is the bridge.

---

## 4. SIR → OIR Lowering

### 4.1 The lowering function

The `lowerSIR` pass is a function from a SIR program to either an error or an OIR program. In the formal model of A1, it is $\mathsf{emit}_1 : L_1 \to \mathsf{Error} + L_2$. Its type signature in the canonical TypeScript encoding is:

```typescript
export type LoweringResult =
  | { ok: true; program: IRProgram }
  | { ok: false; code: string; message: string };
```

The refusal conditions are static. They are checked before any OIR binding is emitted:

1. A node with `trustClass: authoritative` and `proofRequirement` other than `formal` is refused — the claim of authoritative status is unsupported.
2. A node whose emitted OIR bindings would include a kind not in `allowedEmitOps` (when that field is set) is refused — the expression is attempting to use an opcode family outside its declared scope.
3. A node with `executionAuthority: delegated` for a vertical that has not configured delegation is refused — there is no delegation chain, so the authority cannot be exercised.
4. An action verb not in the active extension's vocabulary is refused — the expression references an unknown action.
5. A constraint field reference that does not resolve in the active extension's field schema is refused — the constraint references a field that does not exist in this domain.

These refusals are compile-time errors. They happen before any opcode bytes exist. They cannot be bypassed by routing around the governance plane, because the governance context is in the IR itself, not in a separate system.

### 4.2 Category-by-category lowering

Each jural category has a canonical lowering pattern. The patterns are stated here in pseudo-IR form; the production implementation is in `packages/semantos-sir/src/lower-sir.ts`.

**Declaration** — asserts fact, must be supported by identity and field evidence:

```
SIR: declaration(subject=S, action=confirm, trust=interpretive)
OIR:
  $0 = domainCheck(S.domainFlag)
  $1 = comparison(status, =, "executed")
  $2 = logical_and($0, $1)
  result: $2
```

**Obligation** — duty that matures at a deadline, requires metering authority:

```
SIR: obligation(subject=S, action=margin-post, deadline=T,
                trust=authoritative, proof=formal)
OIR:
  $0 = domainCheck(S.domainFlag)
  $1 = timeConstraint(timeBefore, T)
  $2 = capability(METERING)
  $3 = logical_and($0, $1, $2)
  result: $3
```

**Permission** — the simplest lowering; a permission assertion is a capability predicate:

```
SIR: permission(subject=S, action=valve.open)
OIR:
  $0 = capability(N)       -- N is the capability number for this action
  result: $0
```

**Prohibition** — constraint check with logical negation; the prohibited condition must not hold:

```
SIR: prohibition(action=valve.open, constraint=interlock(pressure > 150))
OIR:
  $0 = comparison(pressure, >, 150)
  $1 = logical_not($0)
  result: $1
```

**Power** — identity, capability, and type-hash checks compose; the actor must be the right party with the right authority over the right type of target:

```
SIR: power(subject=governor, action=publish, trust=interpretive)
OIR:
  $0 = domainCheck(governor.domainFlag)
  $1 = capability(PUBLISH)
  $2 = typeHashCheck(<manifest-type-hash>)
  $3 = logical_and($0, $1, $2)
  result: $3
```

**Condition** — lowers inline as a gate; the condition is not a standalone verification but is consumed into the containing expression's lowering:

```
SIR: condition(gate=temporal(after=T))
OIR:  [inline, emitted as part of containing expression's bindings]
  $k = timeConstraint(timeAfter, T)
```

**Transfer** — sender and receiver must both be identified; transfer and metering capabilities must be held; economic action requires economic authority:

```
SIR: transfer(from=seller, to=buyer, action=settlement,
              linearity=LINEAR, trust=authoritative, proof=formal)
OIR:
  $0 = domainCheck(seller.domainFlag)
  $1 = domainCheck(buyer.domainFlag)
  $2 = capability(TRANSFER)
  $3 = capability(METERING)
  $4 = logical_and($0, $1, $2, $3)
  result: $4
```

### 4.3 Trust-tier enforcement in the lowering pass

The trust-tier enforcement is not a pre-pass check that is separate from lowering. It is interwoven with the lowering itself:

```typescript
function lowerNode(node: SIRNode): LoweringResult {
  // Trust-tier enforcement — structural, not an external check
  if (node.governance.trustClass === 'authoritative' &&
      node.governance.proofRequirement !== 'formal') {
    return {
      ok: false,
      code: 'TRUST_TIER_VIOLATION',
      message: `Cannot lower authoritative expression without formal proof ` +
               `requirement. Node ${node.id} (${node.category}/${node.action}) ` +
               `rejected at IR level.`
    };
  }

  if (node.governance.executionAuthority === 'delegated' &&
      !hasDelegationConfig(node)) {
    return {
      ok: false,
      code: 'DELEGATION_NOT_CONFIGURED',
      message: `Delegated execution authority not configured for this ` +
               `vertical. Node ${node.id} rejected at IR level.`
    };
  }

  const emitted = lowerCategory(node);

  // AllowedEmitOps enforcement — whitelist at IR-kind level
  if (node.governance.allowedEmitOps) {
    for (const binding of emitted.bindings) {
      if (!node.governance.allowedEmitOps.includes(binding.kind)) {
        return {
          ok: false,
          code: 'EMIT_OP_VIOLATION',
          message: `OIR binding kind '${binding.kind}' not in ` +
                   `allowedEmitOps for ${node.id}. ` +
                   `Whitelist: [${node.governance.allowedEmitOps.join(', ')}]`
        };
      }
    }
  }

  return { ok: true, program: emitted };
}
```

The consequence of this structure is that there is no OIR for a malformed SIR program. The `emit()` pass and the cell engine never see a program that violates the governance constraints, because the violation was caught before the program existed.

### 4.4 The α-equivalence property

Protocol specification §7.4 mandates: two SIR programs that express the same semantic intent must produce α-equivalent OIR programs. Under canonical variable naming, those OIR programs must emit byte-identical opcode bytes via `emit()`. The α-equivalence test corpus exercises this mandate across nine constraint kinds (capability, domainCheck, comparison, timeConstraint, logical combinators) and their compositions, covering all seven jural categories.

The test harness at `core/semantos-sir/src/__tests__/equivalence.test.ts` implements α-normalization by stripping counter-generated binding names and rewiring cross-binding references:

```typescript
function alphaNormalize(program: IRProgram): IRProgram {
  const rename = new Map<string, string>();
  program.bindings.forEach((b, i) => rename.set(b.name, `#${i}`));
  // ... rewire operand references
  return { ...program, bindings: renamed, rootBinding: rename.get(...) };
}
```

The test corpus covers a known non-equivalence: the `hostCall` kind. SIR's interlock constraint lowers to a `hostCall` binding with a function name prefixed by `"interlock:"` — a namespace convention that the direct `lower()` path does not apply. This is documented as a deliberate semantic difference surfaced by the SIR seam, not a bug. If a raw (un-namespaced) host call is needed, the SIR constraint vocabulary requires extension. The documentation of the non-equivalence is itself a product of the two-IR architecture: the seam makes the difference visible and attributable.

Two OIR binding kinds — `typeHashCheck` and `deref` — have no current SIR equivalent. The test corpus documents this with explicit `toThrow` assertions. This is an honest limitation; §7 addresses it.

---

## 5. Verification Properties

### 5.1 The three-layer argument

The substrate's formal verification argument has three layers: mechanised proof of the abstract model, empirical conformance testing of the implementation against the model, and structural enforcement at the compilation boundary. The two-IR architecture contributes primarily to the third layer, but it also clarifies what the first two layers are proving and testing.

The kernel invariants K1–K5 are proved in Lean 4 over the abstract 2-PDA model. K1 proves linearity enforcement. K2 proves authorisation soundness: any state-changing transition requires successful identity verification. K3 proves domain isolation: `OP_CHECKDOMAINFLAG` is total and correct. K4 proves failure atomicity: failed Plexus opcodes leave the PDA state byte-for-byte unchanged. K5 proves deterministic termination.

What these proofs establish is the correctness of the enforcement layer below OIR. They prove that *if* an OIR program is emitted with a capability check, *then* the cell engine will enforce that check correctly. They do not prove that the SIR → OIR lowering correctly reflects the jural intent of the SIR program. That property is addressed by the structural enforcement in `lowerSIR` and by the α-equivalence corpus.

### 5.2 Static refusals at the SIR boundary

The protocol specification §7.3 lists five refusal classes. A1 §5.5 reports that four of six malformed-input classes are refused statically at $L_1$:

| Refusal class | Refused at | Mechanism |
|---|---|---|
| Trust-tier escalation (`authoritative` without `formal` proof) | SIR | `lowerSIR` trust-tier enforcement |
| Allowed-emit-op violation (OIR binding kind outside whitelist) | SIR | `lowerSIR` emit-ops enforcement |
| Action verb not in extension vocabulary | SIR | confidence scoring + retry |
| Constraint field reference not resolvable | SIR | field-schema validation |
| Capability not held at runtime | Cell engine | `OP_CHECKCAPABILITY` (K2) |
| Linearity violation (LINEAR cell already consumed) | Cell engine | K1 gate in `linearity.zig` |

The significance of four-out-of-six refused statically is that static refusals are stronger than runtime refusals: they eliminate the class of error from existence, rather than detecting it at execution time. A trust-tier violation caught at the SIR boundary means no opcode bytes were ever emitted for the violating expression. No rollback is needed; no state was changed; no economic effect was produced. The expression was refused at the point where it attempted to cross from meaning to mechanism.

### 5.3 The lexicon layer

The substrate ships eight Lean-formalised domain lexicons: jural (the canonical reference), CDM (ISDA derivatives lifecycle), property management, project management, risk assessment, bills of lading, control systems (SCADA), and circuit commands. Each lexicon is a registration of a domain vocabulary as an instance of the `Lexicon` typeclass with header injectivity. Once registered, the substrate's M1–M4 and D1–D3 lemmas apply automatically.

The SIR interacts with lexicons at the `category` field of `SIRNode`. In the production code, `category` is of type `TaggedCategory` — a discriminated union that extends the core `JuralCategory` with lexicon-specific vocabulary (e.g. CDM event types are a sub-vocabulary of the power and transfer categories). This design keeps the jural categories as the primary vocabulary while permitting domain lexicons to refine them without forking the type system.

The implication for the two-IR architecture is that the governance-enforcement properties of `lowerSIR` apply uniformly across all lexicons. A CDM novation (tagged as `power + transfer` in the CDM lexicon) is subject to the same trust-tier enforcement as a SCADA emergency shutdown (tagged as `power + prohibition`). The enforcement is at the jural level, not the lexicon level. Lexicons refine; jural categories enforce.

### 5.4 Relation to the compression-gradient semantic-preservation property

A1 states the semantic-preservation property: two candidates at layer $L_i$ that are semantically equivalent must lower to candidates at $L_{i+1}$ that are operationally equivalent (A1 §3.1). The two-IR architecture makes this property precise at the SIR → OIR boundary.

Two SIR programs are semantically equivalent if and only if they share: the same jural category, the same governance context (trust class, proof requirement, execution authority, linearity), the same constraint structure (up to structural equivalence of the predicate tree), and the same action and target. Under this definition, the α-equivalence corpus tests the semantic-preservation property empirically for nine constraint kinds.

The definition has a consequence: two SIR programs with different trust classes or different proof requirements are *not* semantically equivalent, even if they express the same surface intent. A `permission` node with `trustClass: interpretive` and one with `trustClass: authoritative` are different semantic objects — the difference is in what the system commits to, not just in what it says. This is the right behaviour: the SIR is the layer at which governance claims are first-class, so governance differences must be reflected in semantic non-equivalence.

---

## 6. Related Work

### 6.1 IR design in verified compilers

Verified compilers (CompCert [Leroy 2009], seL4 [Klein et al. 2009], CertiKOS, Ironclad) use multiple IRs internally for separation of concerns. The verification argument typically follows the program through each IR pass, proving that each pass preserves semantic equivalence with respect to the language's denotational semantics. The SIR → OIR lowering is structurally similar: it is a pass that preserves operational semantics (the cell engine produces the same outcome for equivalent SIR programs) while eliminating the governance-metadata layer.

The difference is that verified compilers use multiple IRs to structure the *proof* of compiler correctness — the IRs are proof artefacts as much as they are compilation artefacts. The SIR is used for *enforcement*, not just for proof structure. The lowering pass is the enforcement point, not a proof lemma. This makes the two-IR architecture closer to a security-typed compilation scheme (where the type system enforces information-flow properties during compilation) than to a standard verified-compiler design.

### 6.2 Policy-enforcement architectures

Policy-enforcement architectures in operating systems (e.g. SELinux, AppArmor, mandatory-access-control systems) enforce governance rules at the syscall boundary — an analogue of the SIR → OIR boundary. The difference is that syscall-level enforcement is rule-based (an external policy database is consulted) rather than type-based (the program's own type structure generates the refusal). Type-based enforcement is strictly stronger: a type error cannot be bypassed by modifying the policy database, because the type is in the program itself.

The `allowedEmitOps` whitelist in the SIR governance context is the substrate's version of a mandatory-access-control policy, but implemented as a type constraint on the IR rather than as an external rule database. A SCADA interlock expression with `allowedEmitOps: ['comparison', 'logical_not']` cannot emit a `hostCall` binding regardless of what the surface grammar says, because the constraint is in the IR's type structure, not in a policy file.

### 6.3 Smart-contract languages and governance

Governance enforcement in programmable computation has been a focus of smart-contract language design (Formal verification of smart contract languages is a large literature; we refer to it categorically to avoid competitor naming). The general approach is to use a high-level language with restricted semantics that prevents certain classes of bug at the language level, then compile to a low-level bytecode. The governance is in the source language; the bytecode is unconstrained.

The two-IR architecture differs in that governance enforcement is in the IR, not the source language. A new surface grammar — a Ricardian contract parser, a LaTeX macro system, a domain-specific SCADA configuration language — can target the SIR without implementing its own governance enforcement. The governance enforcement comes from passing through the SIR → OIR boundary, which every surface grammar must do. This makes multi-surface-grammar support safe: any surface that produces a SIR program is subject to the same enforcement, regardless of what language it came from.

### 6.4 Hohfeld in formal systems

The application of Hohfeld's framework to computer science has primarily appeared in requirements engineering [Jones 1996; Sergot 2013] and normative multi-agent systems [Governatori & Rotolo 2004]. These formalisms typically model Hohfeldian relations as axioms in a deontic logic. The substrate's seven jural categories differ from this tradition in two ways: (a) they are reduced to seven rather than eight (the Condition category adds temporal structure not present in Hohfeld's original framework), and (b) they are embedded in a compilation IR rather than in a logical inference system. The consequence is that the categories generate operational behaviour (lowered OIR patterns) rather than logical entailments. The SIR is not a deontic-logic reasoner; it is a typed IR that uses jural categories to determine compilation outcomes.

---

## 7. Limitations

We present the limitations of the two-IR architecture as currently implemented, in the style established in A1 §7.

**The `typeHashCheck` and `deref` OIR binding kinds have no SIR equivalents.** The α-equivalence corpus documents this with explicit `toThrow` assertions. Expressions that need to lower to `typeHashCheck` or `deref` bindings must currently bypass the SIR layer and use the direct `lower()` path. The design decision to leave these unmodelled in the SIR is intentional — the correct SIR vocabulary for type-hash checking (is this a power? a permission? a condition?) is not yet settled — but it is a real gap. Until the SIR equivalents exist, a portion of the Lisp compiler's output cannot be expressed as a SIR program.

**The `hostCall` non-equivalence is a known seam artefact.** The SIR's interlock constraint lowers to a `hostCall` binding with a function name prefixed by `"interlock:"`. This is a deliberate namespace convention, but it means that a Lisp `hostCall("X")` expression does not round-trip through SIR as the same binding that the direct `lower()` path produces. This is documented as a semantic difference surfaced by the seam, not a bug. If a raw host call without the interlock framing is needed, the SIR constraint vocabulary requires a new `kind` and `lowerSIR` requires a corresponding pass-through lowering. The fix is straightforward; it has not yet been implemented because the use case (raw host calls in governance-typed expressions) is unclear.

**The SIR → OIR lowering is implemented but not yet wired into the primary compiler path.** As documented in `docs/PIPELINE.md`, the Lisp compiler currently skips the SIR and emits OIR (and then bytes) directly. The SIR and the `lowerSIR` pass are both fully implemented (`packages/semantos-sir/src/types.ts` and `lower-sir.ts`), and the α-equivalence corpus demonstrates that the two paths produce equivalent output for the supported subset of constraint kinds. Wiring the SIR into the Lisp compiler (Phase 3 of the restructuring plan) is the next engineering step. Until that wiring is complete, the trust-tier enforcement at the SIR boundary is exercised only through the SIR-first path, not through the primary Lisp-compilation path.

**The α-equivalence claim is tested across one surface grammar.** The equivalence corpus demonstrates α-equivalence between the direct `lower()` path and the SIR-then-lower path, for the supported constraint kinds. It does not yet test equivalence across two independent surface grammars (e.g. Lisp and a future Ricardian parser), because no second surface grammar exists yet. The architectural commitment — that every surface grammar must lower to SIR and that the SIR is the convergence point — is structural, not yet empirically demonstrated across multiple surfaces.

**The delegated execution authority path is not yet implemented.** The `executionAuthority: delegated` configuration causes `lowerSIR` to refuse with a `DELEGATION_NOT_CONFIGURED` error. The delegation chain type (`DelegationChain` in `GovernanceContext.domainBinding`) is defined in the SIR type system, but the verification logic (that the delegate's identity is certified, that the delegated powers are a subset of the delegator's, that the delegation has not expired) is not yet implemented. This means cross-domain governance delegation, while structurally described in the type system, cannot yet be exercised in production.

**The `lowerSIR` implementation conformance is tested but not formally proved.** The cell-engine kernel invariants K1–K5 are proved in Lean 4 over the abstract 2-PDA model. The SIR → OIR lowering does not yet have a corresponding Lean proof that the lowering correctly reflects the jural intent of each category. This proof would establish: if a SIR node has jural category `transfer` with `linearity: LINEAR`, then the emitted OIR bindings are sufficient to enforce single-consumption at the cell engine. Without this proof, the correctness of the lowering rests on the α-equivalence corpus and the golden-file test suite — strong empirical evidence, but not formal proof.

**The seven jural categories may be insufficient for some governance domains.** The seven-category set is motivated as the minimum vocabulary for the substrate's current domains. As new domains are added (bills of lading, insurance instruments, regulatory reporting), there may be semantic distinctions that the seven categories cannot express — relations that are neither a declaration, obligation, permission, prohibition, power, condition, nor transfer. The category set is designed to be extensible (via the `TaggedCategory` discriminated union), but extending the jural-category vocabulary requires extending the `lowerSIR` lowering patterns and the governance-enforcement logic. This is a governed extension point, not a fixed API.

---

## 8. Conclusion

We have argued that a two-IR architecture — upper IR carrying jural and governance metadata, lower IR carrying operational predicates — is the correct structure for a compilation pipeline that makes governance claims. The key properties are:

1. Governance enforcement is structural. It happens at the `lowerSIR` compilation boundary, not in application logic or an external governance check. A malformed governance claim cannot produce OIR because `lowerSIR` refuses.

2. The seven jural categories — declaration, obligation, permission, prohibition, power, condition, transfer — adapted from Hohfeld (1913) for computational governance, are the minimum vocabulary for typing every semantic act the substrate performs. They belong in the upper IR.

3. The OIR in ANF (A-normal form, following Sabry & Felleisen 1992) is the correct lower IR: structurally simple, amenable to multiple back-ends, and expressive of the mechanical predicates the cell engine evaluates.

4. Linear types (following Wadler 1990) are not a cell-engine-only concern. The linearity of a resource — LINEAR, AFFINE, RELEVANT — is part of the SIR governance context and shapes the lowered OIR. K1 enforces it at the bytecode gate, but the SIR declares it first.

5. The α-equivalence property — two surface expressions of the same semantic intent must produce α-equivalent OIR — is provable at the SIR layer. The SIR is the convergence point for multi-surface-grammar support.

The Semantos substrate implements this architecture. The SIR and OIR type definitions are in production code. The `lowerSIR` pass is fully implemented with trust-tier enforcement. The α-equivalence corpus covers nine constraint kinds across all seven jural categories. The cell-engine kernel invariants K1–K5 are mechanically proved in Lean 4. The limitations register in §7 identifies the gaps between this architecture and a fully-proved, fully-wired implementation.

A1 established that reliable language-driven computation requires a compression gradient — a sequence of typed layers, each with a validation rule that can refuse. A2 establishes the specific shape of the two central layers in that gradient: SIR above, OIR below, `lowerSIR` as the enforcement boundary between them. The architectural claim is that this shape is not incidental — it is the minimum structure needed to make governance claims verifiable at compile time.

---

## Formal Specification

The `lowerSIR` function is restated here as a formal-block, incorporating the trust-tier enforcement clause:

```
lowerSIR : SIRProgram → Error + OIRProgram

lowerSIR(p) =
  let checkNode : SIRNode → Error + IRProgram =
    λn.
      -- Trust-tier invariant: authoritative claims require formal proof
      if n.governance.trustClass = authoritative ∧
         n.governance.proofRequirement ≠ formal
      then Error(TRUST_TIER_VIOLATION, n.id)

      -- Delegation invariant: delegated authority requires configured chain
      else if n.governance.executionAuthority = delegated ∧
              ¬hasDelegationConfig(n)
      then Error(DELEGATION_NOT_CONFIGURED, n.id)

      else
        let emitted = lowerCategory(n) in

        -- AllowedEmitOps invariant: emitted bindings within declared whitelist
        if n.governance.allowedEmitOps ≠ ∅ ∧
           ∃b ∈ emitted.bindings. b.kind ∉ n.governance.allowedEmitOps
        then Error(EMIT_OP_VIOLATION, n.id)

        else Ok(emitted)
  in

  -- Lower each node; collect errors or compose programs
  let results = map checkNode p.nodes in
  if ∃e ∈ results. e = Error(_, _)
  then first_error(results)
  else Ok(compose_programs(map unwrap_ok results))

-- Lowering patterns by jural category (all subject to the three invariants above):
lowerCategory(n) =
  match n.category with
  | declaration → identity_check(n) ++ field_assertions(n) ++ [VERIFY]
  | obligation  → temporal_gate(n) ++ [capability(METERING)] ++ [VERIFY]
  | permission  → [capability(n.constraint.required)]
  | prohibition → constraint_check(n) ++ [logical_not] ++ [VERIFY]
  | power       → identity_check(n) ++ [capability(n.constraint.required)]
                  ++ type_hash_check(n) ++ [VERIFY]
  | condition   → inline_gate(n)    -- consumed into containing expression
  | transfer    → identity_check(n.identity)
                  ++ identity_check(n.transferTo)
                  ++ [capability(TRANSFER), capability(METERING)]
                  ++ [VERIFY]
```

**Trust-tier enforcement clause (normative):** Any SIR node with `trustClass = authoritative` that does not carry `proofRequirement = formal` MUST be rejected by `lowerSIR` with `Error(TRUST_TIER_VIOLATION)`. No OIR binding may be emitted for such a node. This clause holds for all seven jural categories without exception. The corresponding runtime enforcement is K2 (authorisation soundness), but the compile-time enforcement at the SIR boundary is logically prior: K2 cannot be violated by an expression that was never compiled.

---

## References

- **Hohfeld, W. N.** (1913). *Some Fundamental Legal Conceptions as Applied in Judicial Reasoning.* Yale Law Journal 23(1).
- **Sabry, A.; Felleisen, M.** (1992). Reasoning About Programs in Continuation-Passing Style. *Lisp and Symbolic Computation* 6.
- **Flanagan, C.; Sabry, A.; Duba, B. F.; Felleisen, M.** (1993). The Essence of Compiling with Continuations. *PLDI '93*.
- **Wadler, P.** (1990). Linear Types Can Change the World. In *Programming Concepts and Methods* (North-Holland).
- **Leroy, X.** (2009). Formal Verification of a Realistic Compiler. *Communications of the ACM* 52(7).
- **Klein, G.; et al.** (2009). seL4: Formal Verification of an OS Kernel. *SOSP '09*.
- **Necula, G. C.** (1997). Proof-Carrying Code. *POPL '97*.
- **Jones, A. J. I.** (1996). On the Concept of Trust. *Decision Support Systems* 33(3).
- **Governatori, G.; Rotolo, A.** (2004). Defeasible Logic: Agency, Intention and Obligation. In *Deontic Logic in Computer Science*. Springer.
- **Price, T.** (2026). Compression Gradients for Deterministic Semantic Execution (Paper A1). Real Blockchain Solutions, Queensland, Australia.
- **Semantos Protocol Specification v0.5** (2026). Real Blockchain Solutions. `docs/spec/protocol-v0.5.md`.

---

*Draft submitted for internal review prior to arXiv preprint posting.*
