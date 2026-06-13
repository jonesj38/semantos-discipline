---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/compression-gradient-as-teachback.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.632686+00:00
---

# The compression gradient as teachback

**Status:** canonical. Fourth in the cybernetic-canon set. Companion to `kernel-composition.md`, `mnca-as-pask-federation.md`, and `cybernetic-orders.md`.

**Sources:** Pask (1976) *Conversation, Cognition and Learning*; `docs/textbook/08-surface-to-ast.md`; `docs/textbook/09-semantic-ir.md`; `docs/textbook/10-opcode-ir-and-emit.md`; `docs/textbook/11-2pda-cell-engine.md`; `docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md`; `core/semantos-sir/src/`; `packages/semantos-ir/`; `core/cell-engine/src/opcodes/plexus.zig`; `docs/canon/cybernetic-orders.md`.

---

## The structural claim

> **The Semantos compression gradient — source → AST → SIR → OIR → bytecode → action → outcome — is Pask's teachback criterion compiled into a static-analysis pipeline. The substrate cannot perform an action without first explaining the action to itself in successive layers of refinement, each carrying strictly more constrained information than the layer above. The two-IR architecture (SIR carrying meaning, OIR carrying mechanism) is not a compilation convenience; it is the structural condition that makes teachback formally enforceable. Failure at any step in the gradient halts the action before any state is touched (K4). Successful traversal of the gradient is the substrate's proof that it has understood the action well enough to perform it.**

This sentence is canonical alongside the other three cybernetic-canon docs. The four together describe the substrate's cybernetic structure; this one names the mechanism by which the structure becomes operational.

---

## Pask's teachback criterion, in one paragraph

Gordon Pask's *Conversation Theory* (1976) makes a strong claim about learning: a participant has not genuinely learned something unless they can demonstrate that understanding back to another participant in a way that establishes mutual comprehension. Knowing a fact is not learning. Restating a fact verbatim is not learning. *Reformulating the fact in terms the questioner can verify against their own model* is learning. This is the teachback criterion, and Pask was unusually formal about it: a teaching exchange is a sequence of turns in which each participant must repeatedly prove they have built a model of the other's model. Without teachback, you have transmission of data; you do not have learning. With it, you have the formal condition for agreement.

The teachback criterion is asymmetric and constructive. The questioner asks not "do you know X?" but "show me how you know X in your own terms" — and the answer must be reformulable against a model the questioner can recognise. Mere recall fails the test; only reformulation in compatible terms passes.

---

## How the gradient compiles teachback into a pipeline

The substrate's compression gradient runs eight stages, each annotated with the cell's `phase` byte (header offset 94, values `0x00`–`0x07`):

```
0x00  source     —  raw evidence; not yet reflected upon
0x01  parse      —  AST; structural extraction of the surface
0x02  ast        —  accumulated state; the substrate now has a structural object
0x03  typecheck  —  classification scores; jural category attributed
0x04  optimise   —  SIR program; meaning carried in typed annotations
0x05  codegen    —  OIR + bytecode emission; mechanism produced from meaning
0x06  action     —  cell engine executes; the bytecode is run
0x07  outcome    —  the result, which becomes new source for the next pass
```

At each transition, the substrate refuses to advance unless the previous layer has been demonstrated against the next layer's expectations. This is structural teachback:

**source → AST.** The surface grammar (Lisp, Ricardian, EDI, SCADA-DSL) is parsed into a typed AST. Failure to parse means the substrate could not extract structure — the surface did not "say" anything the substrate could recognise. K4 atomicity at this stage means a parse failure leaves no trace; the surface is treated as uninterpreted.

**AST → SIR.** The AST is annotated with four orthogonal kinds of meaning: jural category (declaration / obligation / permission / prohibition / power / condition / transfer), taxonomy coordinates (what / how / why / where), governance context (trustClass / proofRequirement / executionAuthority / linearity / allowedEmitOps), and identity binding (subject / certId / hat reference). This is the teachback move where the substrate has to *commit* to a reading of what the AST means. An AST with no plausible jural category is rejected; an AST whose taxonomy doesn't match any registered lexicon is rejected; an AST whose governance context is malformed (e.g. `trustClass: authoritative` without `proofRequirement: formal`) is rejected at compile time. **The SIR layer cannot exist without a defensible interpretation of the AST.** This is Pask's teachback: the substrate has to demonstrate it has built a model of what was said before it can act on it.

**SIR → OIR.** The `lowerSIR` pass — `core/semantos-sir/src/lowerSIR.ts` and the formal account in `docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md` — projects each SIR node onto a canonical pattern of OIR bindings (comparison, logical, capability, domainCheck, timeConstraint, hostCall, typeHashCheck, deref). This pass *enforces the governance context structurally*. An authoritative-trust SIR node without a formal proof requirement is rejected at compile time. A SIR node whose taxonomy demands a capability binding the extension manifest does not authorise is rejected. A delegated execution authority is rejected until that execution model is implemented. The lower pass refuses to produce OIR for any SIR program whose meaning the substrate cannot honestly translate into mechanism. **This is the strongest teachback gate in the gradient:** the substrate has to prove it can specify *how to check* the meaning it claimed to understand, before it is allowed to produce executable bytecode.

**OIR → bytecode.** The OIR's ANF bindings are emitted as opcode bytes. This is a near-mechanical translation — each binding kind has a small canonical opcode sequence — but it is still a teachback gate: the emitter refuses to produce bytecode for binding kinds the cell engine doesn't support (the opcode set is bounded), and the α-equivalence requirement (§7.4 of the protocol spec) guarantees that two SIR programs expressing the same meaning produce byte-identical bytecode. The substrate is forced to be honest about which mechanisms it actually has.

**bytecode → action.** The cell engine executes the bytecode. K1 (linearity), K3 (domain isolation), K4 (failure atomicity), K5 (termination), K6 (hash-chain integrity), K7 (cell immutability) are all enforced here. Any kernel invariant violation halts execution and rolls back via K4. **This is where the substrate's teachback is finally tested against the world**: did the mechanism actually do what the SIR claimed it would do? If not, the action fails atomically and the substrate's model has been falsified by the world, which is itself a Paskian outcome — the substrate has learned that its previous reading of the surface was wrong.

**action → outcome.** The result is a new cell at phase `0x07`, which carries the `prevStateHash` linking it to the action that produced it. This becomes new source for the next pass. The teachback loop closes.

---

## Why two IRs (and not one)

The two-IR architecture exists *because of* the teachback criterion. A single IR collapsing both meaning and mechanism would force the substrate to choose: either it carries meaning (and then the cell engine has to parse the meaning at runtime, breaking K5 termination) or it carries mechanism (and then the substrate has no record of what was meant, breaking the teachback chain).

The split is precisely calibrated:

- **SIR carries what the substrate has agreed an action *means*.** It is the artifact of the substrate's reading of the surface. It is the layer where lexicons live, where jural categories are attributed, where governance is asserted, where identity is bound. Two SIR programs expressing the same semantic intent should produce byte-identical OIR (α-equivalence); they may differ in metadata that records the surface they came from, but their mechanism is the same.

- **OIR carries the mechanism by which the substrate will *check* what the SIR claimed.** It is in administrative normal form (ANF). Each binding has a kind from a closed set. The cell engine's bytecode is emitted from OIR bindings via a small canonical mapping. The OIR is the layer where the substrate has translated its understanding into auditable, executable mechanism.

Lowering SIR to OIR is the formal teachback move — *"if the substrate truly understands this SIR, it must be able to specify exactly how to check it in OIR bindings drawn from the substrate's bounded set of mechanisms."* If the substrate cannot produce an OIR program that respects the SIR's governance context, the substrate has not understood; the lower pass refuses; the action does not proceed. This is teachback as a static-analysis pass: failed teachback returns a structured error, not a runtime exception.

The Lean-formalised `lowerSIR : SIR → Error + OIR` function (per paper A2) is the formal artifact of this teachback gate. The function's totality — every well-formed SIR either lowers to OIR or returns a structured error — is the substrate's commitment to never silently advance an action it did not understand.

---

## What this rules in

1. **Every action in the substrate has a recoverable explanation chain.** Given a cell at phase `0x06` (action), the substrate can produce the SIR that authorised it, the lexicon that named it, the governance context that permitted it, and the identity that signed it — by walking back through the `prevStateHash` chain to the cell's source and through the gradient. This is what makes the substrate auditable.

2. **The substrate refuses to act on what it doesn't understand.** A SIR whose jural category cannot be attributed, an OIR whose binding kind isn't supported, a bytecode that violates a K-invariant — all fail at compile time or at the bytecode gate, with K4 atomicity guaranteeing no state advance. The substrate's silence is informative: if no action occurred, the substrate either rejected the surface or has not yet acted.

3. **Lexicons are the substrate's vocabulary for teachback.** A lexicon is the formal artifact of a community having learned (in Pask's sense) what the actions in their domain mean. The Lean-proved `headerInjective` obligation per lexicon is the formal condition that the lexicon's category names are mutually distinguishable — without that, the substrate's teachback would be ambiguous, and the SIR couldn't carry meaning. Every lexicon is therefore a 3rd-order teachback artifact (per `cybernetic-orders.md`).

4. **The compression gradient is the only sanctioned path from surface to action.** No deliverable should bypass it. A "fast path" that goes from surface bytes directly to bytecode without producing SIR is structurally a violation of teachback — it would mean the substrate executed an action it had not explained to itself.

---

## What this rules out

1. **No surface that bypasses SIR.** Every adapter, every grammar, every input mode must produce SIR before bytecode. Helm voice, Helm typing, EDI ingestion, API endpoints — all go through the gradient. If a surface cannot be compiled to SIR, the substrate cannot act on it. This is not a usability constraint; it is the cybernetic property.

2. **No runtime SIR interpretation.** SIR is a compile-time artifact. The cell engine sees only bytecode. SIR is the *evidence* the substrate produced before emitting bytecode; the cell engine is not a SIR interpreter. Building a "runtime SIR evaluator" would collapse the two-IR architecture and break K5.

3. **No "best-effort" lowering.** The lower pass is total: every SIR either produces OIR or produces a structured error. A "lower with warnings" mode that emits OIR despite governance-context violations would silently advance unverified actions. Refused.

4. **No teachback at the wrong layer.** A common temptation is to perform meaning-aware checks at the OIR or bytecode layer ("if the cell has type X and the actor has hat Y, allow Z"). This is wrong: meaning-aware checks belong at the SIR layer, where they are statically enforceable. The bytecode layer is mechanism-only; encoding meaning into mechanism breaks the architectural separation. K3 (domain isolation) at the bytecode gate is mechanism, not meaning — it checks a 4-byte flag, not a semantic predicate.

5. **No claim that "the substrate understood it" without a SIR.** When debugging, when auditing, when explaining what the substrate did, the SIR is the answer. A description that does not include the SIR is incomplete.

---

## The compression gradient as Pask's specific contribution

It is worth being explicit about what this doc claims about Pask. He did not invent compilation pipelines. He did not invent IRs. What he did was insist — formally, against the prevailing cognitivist consensus of his era — that learning *is* the construction and demonstration of layered models, where each layer is a refinement of and accountable to the layer above. He gave teachback its formal status as the condition for agreement.

The substrate takes this seriously by building it into the action path. Every action is, in Pask's sense, a learned move: the substrate has constructed a model of the surface (AST), interpreted that model in terms of community vocabulary (SIR), specified how to check the interpretation (OIR), translated to mechanism (bytecode), executed under invariant enforcement (cell engine), and recorded the outcome (cell at phase `0x07`). The entire path is reflective; the entire path is teachback-shaped; the entire path is auditable.

Other AI systems of the substrate's era make a different choice: they treat actions as functions of learned weights, with no recoverable explanation chain. The substrate's choice is older and stricter. It is the choice Pask made when he said: *no agreement without teachback*.

---

## Open questions

1. **Should the lower pass become a Lean theorem (K-numbered)?** The totality of `lowerSIR : SIR → Error + OIR` is currently formalised in paper A2 but not in `proofs/lean/Semantos/Theorems/`. Promoting it to K-status (e.g., as K11 — *teachback totality*) would put the gradient's formal property on equal footing with K1–K10. Open.

2. **What does teachback look like for outcomes?** A successful action produces an outcome cell at phase `0x07`. Whether the substrate should also produce a *teachback summary cell* — a SIR-like artifact that describes "what just happened in the substrate's terms" — is open. It would make Pask's full conversational loop explicit, but adds a phase to the gradient.

3. **Cross-extension teachback.** When extension A produces a SIR that references a type defined by extension B's lexicon, the substrate currently validates the type via the type-hash registry. Whether the lower pass should additionally require a *teachback witness* from extension B (a signed assertion that the type means what extension A is claiming) is open. This would make 3rd-order teachback explicit at extension boundaries.

4. **Pask kernel + gradient interaction.** Currently, the Pask kernel observes interactions but does not directly observe gradient stages. Whether `pask_interact_run` should be invoked at phase boundaries (e.g., on every successful SIR-to-OIR lowering) — making the substrate's own gradient traversal a first-class learning signal — is open.

---

## Cross-references

- `docs/canon/kernel-composition.md` — the cell engine + Pask kernel composition; the cell engine executes the bytecode this gradient produces.
- `docs/canon/mnca-as-pask-federation.md` — the federation; gradient-produced cells flow through the federation as the canonical form.
- `docs/canon/cybernetic-orders.md` — the three-order framing; the gradient is where the orders converse.
- `docs/textbook/08-surface-to-ast.md` — the source-to-AST step.
- `docs/textbook/09-semantic-ir.md` — the SIR layer in detail.
- `docs/textbook/10-opcode-ir-and-emit.md` — the OIR + emit step.
- `docs/textbook/11-2pda-cell-engine.md` — the cell engine that executes the bytecode.
- `docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md` — the formal account of `lowerSIR : SIR → Error + OIR`.
- `core/semantos-sir/src/` — SIR implementation.
- `packages/semantos-ir/` — OIR implementation.
- `proofs/lean/Semantos/Lexicons/` — the formal lexicon coherence proofs that make 3rd-order teachback possible.

---

## Summary

The compression gradient is not "the compilation pipeline." It is the substrate's teachback mechanism — Pask's 1976 criterion for learning, compiled into a static-analysis pass. Every action is forced to be explained in successive layers (AST → SIR → OIR → bytecode) before it is allowed to execute, and every failure to explain is structural rejection at compile time, not runtime. The two-IR architecture exists to keep meaning (SIR) and mechanism (OIR) separately verifiable, with the lower pass as the formal teachback gate between them. Lexicons are the 3rd-order vocabulary that makes teachback possible across communities; the SIR governance context is the 2nd-order surface where the substrate's own commitments to its reading are recorded; the bytecode is the 1st-order mechanism the cell engine actually runs.

The substrate's silence in the face of unintelligible surfaces is informative — it has refused to act on what it has not understood. The substrate's actions, when they happen, are recoverable: every action carries a complete explanation chain back through the gradient to its source. This is what makes the substrate auditable, what makes federated learning meaningful, and what makes the cybernetic property hold end-to-end.

Pask insisted: *no agreement without teachback*. The substrate insists: *no action without the gradient*. They are the same insistence.
