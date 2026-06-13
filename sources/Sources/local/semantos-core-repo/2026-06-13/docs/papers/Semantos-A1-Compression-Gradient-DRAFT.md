---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.753433+00:00
---

# Compression Gradients for Deterministic Semantic Execution

**Paper A1 — Draft (revision 2)**
**Todd Price, Real Blockchain Solutions**
**Queensland, Australia**
**todd@realblockchainsolutions.com**
**April 2026**

> **Status:** Draft for review. Targeted at arXiv first; conference targets include OOPSLA, PLDI, EMNLP industry track. Pin to canon snapshot at submission.

---

## Abstract

Large language model (LLM) systems that translate natural-language input into executable action — agent frameworks, voice interfaces, conversational tooling — fail in production by misinterpretation, hallucination, and unauthorised action. The standard architecture treats this as an alignment problem: better prompts, more careful tool descriptions, more rigorous output validation. We argue the failure is structural. The standard architecture asks a model to make a single jump from text to action with no inspectable, ratifiable, type-checked intermediate forms. There is nothing for the system to refuse, no place for a human to ratify, no surface a regulator can audit.

We present **compression gradients**: a discipline that progressively reduces the entropy of input through a sequence of typed transformations, each of which has a canonical form, a validation rule, an explicit loss boundary, and an emit pass to the next layer. The gradient enforces that high-entropy human input becomes low-entropy executable form only after passing through layers the system can stop at. We give a small formal model, present an implementation in the Semantos substrate covering five gradient layers (natural language → semantic intermediate representation → opcode intermediate representation → opcode bytes → bounded execution), and report empirical results from a working pipeline that lowers voice input through eight domain lexicons to cryptographically anchored cells. The substrate's static-enforcement points refuse four of six well-formedness violations at compile time rather than at runtime, and a byte-identical α-equivalence property allows multiple surface grammars to lower into the same opcode form. On a canonical example, the pipeline compresses approximately ninety-five bytes of natural language (or roughly four hundred and eighty bytes of structured semantic IR) to a four-byte opcode sequence. We argue compression gradients are the missing front-end discipline for any reliable language-driven execution system, and that the LLM should *participate in* the gradient rather than execute through it.

**Keywords:** intermediate representations, semantic execution, LLM tool use, substructural type systems, compression, formal methods.

---

## 1. Introduction

The promise of language-driven computing — that a user can speak or write what they want and the machine will do it — has driven thirty years of research and three years of intense industrial deployment. The current generation of LLM-based agent systems (function-calling, tool use, planner-executor architectures) advances the user experience meaningfully. They also fail in characteristic ways: a model invents a function call that does not exist; a model executes a destructive action when the user intended a query; a model takes an action whose authorisation has not been verified; a model produces output that is internally consistent but factually wrong; the same prompt produces different actions on different runs.

These failure modes are typically treated as *alignment* problems — better prompts, more careful tool descriptions, output validation, a second model checking the first. The community has produced sophisticated mitigations: structured output schemas, constrained decoding, multi-pass verification, retrieval-grounded responses. Each helps. None of them changes the structural shape of the system: a model is asked to produce, in one inference pass, an output that will be executed against external state. The model is the gradient. There is nothing between "what the user said" and "what happens next" that the system can independently inspect, refuse, or ratify.

We argue this is the wrong shape. The right shape — the shape that compilers, type systems, and formally-verified pipelines have used for decades — is a *gradient*: a sequence of typed transformations, each consuming the output of the previous and producing a more constrained form, with explicit validation at every layer boundary and explicit semantic preservation across them. The end of the gradient is execution; the layers between the user and the execution are where the system thinks.

This paper makes three contributions:

1. We give a small formal model of the **compression gradient** as a sequence of layers, each with a canonical form, a validation predicate, a loss boundary, and an emit function, with a semantic-preservation property across layers.

2. We present an implemented gradient — the Semantos substrate's five-layer pipeline from natural language through a semantic intermediate representation (SIR), an opcode intermediate representation (OIR) in administrative normal form (ANF), opcode bytes, and a deterministic bounded two-stack pushdown automaton (2-PDA). We describe how each layer is constructed and what it enforces.

3. We report empirical results from the working pipeline. Eight Lean-formalised domain lexicons demonstrate that the gradient generalises across domains; live tests against a production LLM show that ambiguous voice input either compresses cleanly into a typed semantic intent or is refused at a specific named layer with a specific structured reason. We measure the byte-budget of one canonical example across all five layers, observe a compression of approximately twenty-four to one hundred and twenty times depending on the layer compared, and report a byte-identical α-equivalence property that permits multiple surface grammars to target the same intermediate form.

### 1.1 The pipeline at a glance

Before the related-work tour, the table below previews the five-layer gradient. The "refusal capability" column is the structural claim of the paper: each layer catches a distinct class of failure that direct text-to-action lowering cannot. Section 3 formalises the gradient; section 4 describes the implementation; section 5 evaluates it.

| Layer | Form                                  | What it adds                                                            | Refusal capability                                                                                              |
|-------|---------------------------------------|-------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------|
| $L_0$ | Natural language (text or voice)      | Raw user intent                                                          | n/a (the input)                                                                                                  |
| $L_1$ | Semantic IR (jural-typed)             | Meaning: jural category, taxonomy, governance, identity binding         | Trust-tier mismatch; allowed-emit-op violation; identity-cap mismatch                                           |
| $L_2$ | Opcode IR (ANF)                       | Mechanism: named bindings, explicit data flow, decomposable predicates  | Type-check failures; binding-graph violations                                                                    |
| $L_3$ | Opcode bytes (`0x4C`–`0xD0`)          | Concrete executable: byte-level instruction stream                       | Encoding errors; byte-budget overflows                                                                           |
| $L_4$ | 2-PDA execution                       | Bounded deterministic execution with substructural enforcement          | Linearity violations; failed authorisation; capability-not-held; domain-flag mismatch                            |

The substrate is implemented in a polyglot research codebase under continuous engineering at scale (~200 000 lines across Zig, TypeScript, Elixir, Lean 4, and TLA+); the gradient is the part of the system that turns user intent into something the substrate can act upon.

The structural claim is the headline: **LLMs should not execute tasks. They should participate in a compression pipeline that produces executable truth.** What follows is a description of what that pipeline looks like in practice and why each of its layers earns its keep.

---

## 2. Background and related work

### 2.1 LLM tool use and the standard architecture

Modern LLM systems that take action in the world generally follow a *function-calling* architecture: the model is given a list of available tools (with names, parameter schemas, and natural-language descriptions), receives a user request, and emits a structured tool invocation that the host runtime executes. Variants include planner-executor (a separate model produces a plan that subsequent calls execute), reflexive (the model verifies its own output before commit), and retrieval-augmented (relevant context is fetched and re-prompted). Across all variants, the core shape is the same: the model produces, in one or a small number of generations, an executable artefact.

The mitigations layered on top of this shape are well-studied. Structured output (JSON schema constraints during decoding) prevents malformed outputs. Type-checked tool wrappers reject ill-typed invocations. Confirmation turns ("are you sure you want to delete X?") gate destructive actions. Multi-model verification ("does another model think this is right?") catches some hallucinations. None of these change the architectural fact that *the model is the front-end of the execution pipeline*. The intermediate forms it produces are not first-class citizens of the runtime — they are not typed by the host language, not subject to formal verification, not verifiable across runs, and not separable from the model's other outputs. They are prompts and completions.

### 2.2 Compiler intermediate representations

The compiler community settled this question decades ago. A modern compiler does not lower source code to machine code in one pass. It passes through a sequence of intermediate representations — abstract syntax tree, three-address code, single-static-assignment form, register-allocated assembly — each of which has a precisely defined shape, a set of well-formedness rules, and a transformation pass to the next layer. Optimisations are not "make the model better at producing assembly"; they are passes over the IR that preserve semantics while changing syntax. Verification (when applied) operates on the IRs, not on the source or the target.

The administrative-normal-form (ANF) [Sabry & Felleisen 1992; Flanagan et al. 1993] is a particularly clean example: every intermediate computation is named, every continuation is explicit, and the resulting form is structurally simpler than the source — easier to optimise, easier to verify, easier to compile to multiple back-ends. ANF is one of the layers in our pipeline.

### 2.3 Semantic parsing

Semantic parsing has a long tradition in NLP [Zelle & Mooney 1996; Liang 2016] of mapping natural language to structured logical forms — Prolog-like representations, lambda calculus, SQL, or domain-specific declarative languages. The output is then executed against a knowledge base or database. Modern executable-semantic-parsing systems (Spider, WikiSQL, TableQA, etc.) have made remarkable progress on the syntactic accuracy of the lowering.

Compression gradients differ from classical semantic parsing in two ways. First, the intermediate form is not a single layer (a logical form executed against a database) but a *sequence* of layers, each more constrained than the last. Second, the discipline is normative — every layer has a well-formedness rule that can refuse, not just produce. Semantic parsing has historically focused on accuracy; we focus on *enforceable correctness* — the ability of a layer to say "no" with a structured reason.

### 2.4 Substructural type systems and proof-carrying code

The lowest layer of our gradient is a substructural execution model in which resources are typed *linearly* (consumed exactly once), *affinely* (consumed at most once), or *relevantly* (used at least once) [Wadler 1990]. Capability tokens, payment-channel state, and semantic objects of certain kinds are typed in this discipline; the kernel enforces consumption rules at the bytecode gate. This permits a class of correctness arguments — replay impossibility, capability soundness, double-spend prevention — that linear types make natural.

Proof-carrying code [Necula 1997] establishes that a binary can ship with a proof of its safety properties checkable by the recipient. Our pipeline's verification posture is structurally similar — kernel invariants are mechanically proved in Lean 4, the implementation is empirically validated against the abstract model, and the production binary's hash is anchored on a public timestamping layer.

### 2.5 Position relative to existing work

To our knowledge, no prior system combines: (a) an LLM front-end, (b) a typed semantic intermediate representation grounded in jural / domain-modelling vocabulary, (c) a lower-IR in ANF with byte-identical α-equivalence under alternate surface grammars, (d) a substructural opcode-byte target executed in a bounded deterministic automaton, and (e) mechanically-proved kernel invariants over the execution model. Each of (a)–(e) has prior art individually. The compression-gradient claim is that combining them into a single pipeline is what makes language-driven execution reliable. The remainder of the paper substantiates that claim by describing the implementation and its observed properties.

---

## 3. The Compression Gradient

We define a compression gradient as an ordered sequence of layers $L_0, L_1, \ldots, L_n$ where each $L_i$ has four properties:

1. **A canonical form.** Some structural shape that distinguishes well-formed members of $L_i$ from ill-formed strings. The canonical form is checkable in time bounded by the size of the input — typing rules, grammars, or schema constraints.

2. **A validation rule.** A predicate that decides, for a candidate $x$ at layer $L_i$, whether $x$ is well-formed at $L_i$. The validation rule answers: *is this acceptable input to the next layer?*

3. **A loss boundary.** An explicit statement of what information from $L_{i-1}$ is preserved at $L_i$, what is normalised away, and what is irretrievable. The loss boundary is the system's contract with the user about what the layer is permitted to discard.

4. **An emit pass.** A function $L_i \to L_{i+1}$ that produces a candidate at the next layer. The emit pass may fail (refusing to produce output) when its input is ill-formed under the next layer's well-formedness rules.

Across layers, the gradient must satisfy a **semantic-preservation property**: two candidates $x_1, x_2 \in L_i$ that are semantically equivalent (under the layer's intended meaning) lower to candidates $y_1, y_2 \in L_{i+1}$ that are operationally equivalent. The canonical form of operational equivalence we use is *byte-identical α-equivalence at the opcode layer* — two SIR programs that express the same semantic intent must produce α-equivalent OIR programs (and, under canonical naming, byte-identical opcode output).

### 3.1 Formal model

The properties above admit a small formal definition. A compression gradient is a tuple $(\mathcal{L}, \mathsf{valid}, \mathsf{emit}, \approx)$ where:

- $\mathcal{L} = (L_0, L_1, \ldots, L_n)$ is a finite sequence of layer types.
- For each $i$, a validation predicate $\mathsf{valid}_i : L_i \to \mathsf{Bool}$ decides whether a candidate is well-formed at layer $i$.
- For each $i < n$, an emit function $\mathsf{emit}_i : L_i \to \mathsf{Error} + L_{i+1}$ either rejects the candidate with a structured error or produces a candidate at the next layer.
- For each $i$, a semantic equivalence relation ${\approx_i} \subseteq L_i \times L_i$ identifies pairs of candidates with the same intended meaning at layer $i$.

A compression gradient satisfies the **semantic preservation property** if, for all $i < n$ and all $x, y \in L_i$:

$$
x \approx_i y \;\wedge\; \mathsf{valid}_i(x) \;\wedge\; \mathsf{valid}_i(y) \;\implies\; \mathsf{emit}_i(x) \approx_{i+1} \mathsf{emit}_i(y)
$$

(modulo error: if either $\mathsf{emit}_i(x)$ or $\mathsf{emit}_i(y)$ is `Error`, both must be, and they must report the same error class.)

The validation predicate is the system's per-layer refusal capability. The semantic preservation property is the system's commitment that semantically equivalent inputs produce operationally equivalent outputs — including, importantly, equivalent refusals. Two paraphrases of the same intent must succeed together or fail together with the same error class; if they don't, either the equivalence relation $\approx_i$ is wrong or the emit function is doing something semantics-sensitive that it shouldn't.

In our implementation (§4), $L_0$ is natural language; $L_1$ is the semantic intermediate representation (SIR); $L_2$ is the opcode intermediate representation (OIR) in administrative normal form; $L_3$ is opcode bytes; $L_4$ is bounded execution. The equivalence relation $\approx_3$ at the opcode-bytes layer is byte-identical α-equivalence (equality up to canonical variable renaming); the relations at higher layers are weaker but each strictly refines the one above it.

### 3.2 Why each layer earns its keep

A gradient is not free. Each additional layer adds engineering cost (a new type system, new validation rules, a new emit pass), increases the surface area for bugs, and adds latency. A layer earns its keep only if it provides a property the layers around it cannot — a refusal capability, a representation gain, an alternative back-end, a verification target.

The layer table from §1.1 is the case-by-case argument that each of the five layers in our implementation earns its keep. Each refusal capability addresses a specific failure mode of direct text-to-action lowering. A trust-tier refusal at $L_1$ says "your intent claimed authoritative status without a formal proof — pick a weaker claim or supply a proof"; a model attempting to escalate privilege through ambiguous input cannot get past this check no matter how confidently it phrases the request. A linearity refusal at $L_4$ says "this LINEAR resource has already been consumed" — a model attempting a double-spend cannot succeed regardless of what its prompt looked like. The gradient's layers are not redundant; each catches a distinct class of error.

### 3.3 The structural argument against direct lowering

A direct text-to-action lowering ($L_0 \to L_4$ in one step) collapses all four refusal capabilities into a single check at execution time — the runtime either does the thing the model said to do, or it doesn't. The structured intermediate refusals are unavailable; the system either accepts the model's output and lives with the consequences, or refuses opaquely with a runtime error the user cannot diagnose.

This shape has consequences:

- **Diagnosability is destroyed.** A failure at any of the four refusal points appears as a single binary event ("the model failed") rather than a structured rejection ("the model proposed an authoritative claim with only attestation-level proof; ask for a stronger proof or weaken the claim").
- **The system cannot ratify partial input.** A model may produce correctly-typed jural intent but ambiguous mechanism — in a gradient, the SIR layer can be human-ratified before lowering to OIR. In direct lowering, no such partial-form is available.
- **Equivalent meaning produces non-equivalent action.** Two phrasings of the same intent may produce different model outputs. In a gradient, the byte-identical α-equivalence property of the OIR layer guarantees that semantically equivalent SIR programs produce operationally equivalent execution. In direct lowering, this is at best statistical.
- **Verification cannot apply.** Formal verification operates on intermediate forms. A gradient with named layers admits per-layer proofs. A single text-to-action transition admits no such proofs because there is no structural form to verify.

The compression gradient is the discipline that recovers these four properties. The remainder of the paper describes one implementation.

---

## 4. Implementation

### 4.1 Pipeline overview

The Semantos substrate implements a five-layer compression gradient. Surface input — natural language, voice, a UI button, a shell command, or an inbound network frame — is converted by a *producer adapter* into an `Intent` (a layer-$L_0/L_1$ boundary object). The Intent is passed to `processIntent`, which constructs a Semantic IR program (the SIR layer, $L_1$), lowers to an Opcode IR program in ANF (OIR, $L_2$), emits opcode bytes (`0x4C`–`0xD0` range, $L_3$), and executes them in a bounded two-stack pushdown automaton (2-PDA, $L_4$). The cell engine produces a typed cell, persists it through a storage adapter, and returns a cryptographic receipt.

Every stage boundary emits a structured event tagged with the same correlation identifier. A single user turn is one greppable trace from the producer adapter through every layer of the gradient.

### 4.2 The producer adapter ($L_0 \to L_1$)

Producer adapters convert source-specific input to the canonical `Intent` shape. Eight producers exist: natural-language LLM extraction, voice transcription, shell-command parsing, UI event handlers, host-command dispatch, network-frame ingest, governance flows, and scheduler triggers.

The natural-language producer uses an LLM with strict structured-output constraints. The system prompt is parameterised by the active extension's domain grammar — the LLM sees the available actions, the taxonomy, and the constraint shapes for *this* extension, not a hardcoded vocabulary. Output schema is generated from the TypeScript `Intent` type at build time. On schema-validation failure, one retry is attempted with the validation error in context; a second failure surfaces to the user as a clarification request.

Confidence is computed by the host, not self-reported by the model. The composite score draws on four signals: proportion of required fields the LLM populated, proportion of constraints that pass `validateConstraintFields` against the active extension's field schema, action-verb match against the extension's vocabulary, and taxonomy-path resolution against known nodes. A score ≥ 0.9 routes the Intent to the pipeline as `interpretive`; 0.6–0.9 requires a confirmation turn before execution; < 0.6 is rejected with a clarification request. The `authoritative` trust class is never set by the natural-language path — it is reserved for inputs that arrive with a real cryptographic proof (already-signed cells, host-command chains).

The implementation supports both brain-side and on-device LLM producers; the gradient's structural property is preserved across them. In the on-device path (D-O5m.followup-3 Phase 2), a 3B Q4-quantized model on the operator's phone runs grammar-constrained generation against a GBNF grammar derived from the `Intent` type, producing a structurally-valid candidate locally; the candidate ships in the multipart `sir_candidate` part and the brain skips L0→L1 while still running L2-L4 and the L1 trust-tier validation. The model's smaller capacity is compensated for by the grammar — the structural validity of the output is enforced at the token level rather than reasoned about by the model — and the host-side confidence score, computed identically on phone and brain, lets a small model's "good enough" Intent inherit the same trust-tier discipline as a brain-side extraction.

### 4.3 The Semantic IR ($L_1$)

The SIR carries jural meaning. Every SIR node is typed by a *jural category* — one of {declaration, obligation, permission, prohibition, power, condition, transfer} — derived from Hohfeld's analytic framework [Hohfeld 1913] and adapted for computational governance. The category is the minimum vocabulary sufficient to distinguish every act the system performs: a derivatives-clearing event and a safety-interlock acknowledgement are both exercises of *power*, but the SIR makes the difference structural — one is a transfer-power over financial obligations, the other is a consume-power over a safety event.

Beyond the category, every SIR node carries:

- **Taxonomy coordinates** (`what`, `how`, `why`, `where`) locating the node in the domain ontology;
- **Identity binding** (subject, optional facet, optional cert reference);
- **Governance context** (`trustClass` ∈ {cosmetic, interpretive, authoritative}, `proofRequirement` ∈ {none, attestation, formal}, `executionAuthority` ∈ {local_facet, hat_scoped, delegated}, `linearity` ∈ {LINEAR, AFFINE, RELEVANT, FUNGIBLE}, optional `allowedEmitOps` whitelist);
- **Provenance** (source: nl / voice / shell / ui / etc., confidence, optional inference-run identifier);
- **Constraint structure** (typed predicate tree over capabilities, domain flags, identity references, temporal gates, value comparisons, state phases, and interlock policies).

The SIR's canonical form is checkable in time linear in the size of the program. The validation rule (`lowerSIR.enforceTrustTier`, etc.) refuses to produce OIR for malformed claims:

- An `authoritative` claim without a `formal` proof requirement is refused at the SIR boundary, not at runtime.
- A node whose emitted OIR bindings would fall outside `allowedEmitOps` is refused.
- A `delegated` execution authority for a vertical that has not configured delegation is refused.

These refusals are static — they happen during compilation, before any opcode bytes exist. A natural-language prompt that successfully tricks the LLM into producing a syntactically valid SIR program with a misclassified trust tier still cannot reach execution.

### 4.4 The Opcode IR ($L_2$)

The OIR is administrative normal form. Each binding has a name (`$0`, `$1`, …) and a kind (one of: `comparison`, `logical`, `capability`, `domainCheck`, `timeConstraint`, `hostCall`, `typeHashCheck`, `deref`). The lowering pass `lowerSIR(SIRProgram → IRProgram)` translates each jural category into a canonical OIR pattern:

- **Declaration** lowers to identity check + field assertions + VERIFY.
- **Obligation** lowers to temporal gate (the deadline) + capability check (the metering capability for economic action) + VERIFY.
- **Permission** lowers to a single capability check.
- **Prohibition** lowers to constraint check + logical negation + VERIFY (the predicate must be false for the action to proceed).
- **Power** lowers to identity check + capability check + type-hash check + VERIFY.
- **Condition** lowers inline to a temporal or state predicate gating its containing expression.
- **Transfer** lowers to sender identity check + receiver identity check + transfer capability + metering capability + VERIFY.

The OIR's canonical form is structurally simpler than the SIR: no jural-category labels, no governance context, no provenance — only the mechanical predicates that the cell engine can evaluate. The compression from SIR to OIR is large for governance-rich nodes (a SIR program with full trust-tier metadata may lower to a four-binding OIR program) and modest for simple permissions (a SIR `permission` lowers to one OIR binding).

The OIR layer admits the **byte-identical α-equivalence property**: two SIR programs that express the same semantic intent must produce α-equivalent OIR programs, and under canonical variable naming, byte-identical opcode output. This is the property that makes alternative surface grammars commercially viable — a Lisp surface, a LaTeX surface, a Lean-ish surface, and a future Ricardian-contract parser can each lower to SIR independently, but if they express the same intent, they converge at the OIR layer to byte-identical output. The kernel does not need to know which surface produced the bytes.

### 4.5 The opcode emit pass ($L_2 \to L_3$)

`emit(IRProgram → bytes)` is the ANF-to-bytes lowering. Each binding kind maps to a fixed opcode pattern in the standard Bitcoin Script + Plexus extension range (`0x4C`–`0xD0`). Constants are pushed via `OP_PUSHDATA`; capabilities check with `OP_CHECKCAPABILITY` (`0xC3`); domain flags check with `OP_CHECKDOMAINFLAG` (`0xC6`); identities check with `OP_CHECKIDENTITY` (`0xC4`); linearity classes check with `OP_CHECKLINEARTYPE` (`0xC0`); temporal constraints check with `OP_CHECKLOCKTIMEVERIFY`; logical compositions use the standard Script `OP_BOOLAND` / `OP_BOOLOR`; a final `OP_VERIFY` aborts if the cumulative result is false.

The bytes are the system's commitment. They are golden-file tested across the lowering corpus — every Intent in the corpus produces bytes that have been stable across every release of the substrate.

### 4.6 The execution layer ($L_4$)

Bytes execute in the cell engine, a bounded deterministic two-stack pushdown automaton implemented in approximately 4 900 lines of Zig and compiled to WebAssembly. Two stacks (1 024 cells main, 256 cells auxiliary), no loops, no jumps, no garbage collection. Execution time is proportional to opcount.

The Plexus opcode range adds VM-level type enforcement: linearity checks at the gate (no `DUP` of a LINEAR cell; no `DROP` of a LINEAR cell), capability verification via SPV against an unspent BRC-108 UTXO, identity verification against the BRC-52 certificate's subject, domain-flag checks at byte offset 24 of the cell header. Failures leave the PDA state byte-for-byte unchanged (failure atomicity); the cell engine's `kernel_set_enforcement(1)` is the static configuration that turns these checks on, and there is no runtime mechanism to disable them.

Five kernel invariants are mechanically proved in Lean 4 over the abstract 2-PDA model: K1 (linearity — a LINEAR cell is consumed exactly once), K2 (authorisation soundness — state transitions require valid identity proof), K3 (domain isolation — `OP_CHECKDOMAINFLAG` is total and correct), K4 (failure atomicity — failed Plexus opcodes leave the PDA state unchanged), K5 (deterministic termination — bounded opcount, no loops). These invariants are the per-layer verification targets described in §3; they apply at the execution layer because that is where the substructural discipline is enforced.

### 4.7 Eight lexicons demonstrate generality

The pipeline is not specialised to a single domain. Eight Lean-formalised domain lexicons ship with the substrate today: jural (the canonical lexicon), CDM (ISDA derivatives lifecycle), property management, project management, risk assessment, bills of lading, control systems (SCADA), and circuit commands (firmware). Each is approximately forty lines of Lean: an `inductive` for the categories, a `header` function, a proof of header injectivity, and an `instance` registration over the generic `Lexicon` typeclass. Once registered, every substrate-level theorem (lexicon-substrate lemmas, render-card correctness) automatically applies — no per-lexicon re-proof of the substrate invariants is required.

The substrate's claim is that the gradient generalises: the same pipeline that lowers a derivatives-clearing event in CDM lowers a safety-interlock acknowledgement in SCADA, a maintenance request in property management, and a state transition in a multi-user world. The eight existing lexicons demonstrate this empirically across very different domains.

---

## 5. Evaluation

### 5.1 The byte budget across one canonical example

We measure the byte budget of a single canonical example through every layer of the gradient. The example is a property-management policy fragment expressing *"any party with the SIGNING capability for protocol 0x02 may perform this action"*:

| Layer | Form                             | Approximate size |
|-------|----------------------------------|------------------|
| $L_0$ | Natural language                 | ~14 words (≈ 95 bytes UTF-8) |
| $L_1^{\text{surface}}$ | Lisp surface         | 3 forms  (≈ 31 bytes) |
| $L_1$ | SIR program                      | 1 node (≈ 480 bytes JSON) |
| $L_2$ | OIR (ANF)                        | 1 binding (≈ 70 bytes JSON) |
| $L_3$ | Opcode bytes                     | 4 bytes (`0xC3 0x01 0x02 0xAC`) |

We observe substantial compression from natural language and SIR JSON to opcode bytes: the canonical example reduces from approximately ninety-five bytes of natural language, or roughly four hundred and eighty bytes of SIR JSON, to a four-byte opcode sequence — between twenty-four times and one hundred and twenty times depending on the comparison. The byte savings at the bottom of the gradient are what permit the cell engine to be small (185 KB full WASM profile, 29 KB embedded). The information-density gains at the top of the gradient — natural language to a single typed semantic node — are what make domain-specific surface grammars feasible without modifying the kernel.

The bytes are golden-file stable. Every release of the substrate emits the same bytes for this example.

### 5.2 The handyman intake

We thread one ambiguous natural-language input through the pipeline to demonstrate how each layer handles uncertainty. The user message is:

> *"need door fixed, kinda broken at the hinge, might need replacing idk"*

This is the kind of input that exposes the failure mode of direct text-to-action lowering. There is a clear primary intent (a door needs fixing), an entity reference (the door's hinge), and an explicit uncertainty marker ("might need replacing idk"). A direct lowering to action would either commit to "fix the hinge" prematurely (and have to roll back if the hinge is irreparable) or commit to "replace the door" prematurely (and over-spend if the hinge is repairable). The user did not authorise either commit — they reported a problem and acknowledged the system doesn't yet know which solution is correct.

The pipeline handles this in three steps:

1. **$L_0 \to L_1$ (LLM extraction).** The producer adapter's structured output reports an `Intent` with category `obligation`, action `report_issue`, taxonomy `services.trades.carpentry`, primary subject `door`, secondary attribute `hinge_damage`, and an explicit `uncertainty: { repair_or_replace: true }` flag. The confidence score is 0.91 — high enough to route to the pipeline as `interpretive`. Latency: 1.4 s against a production LLM. (Five live API tests, all passing on first run.)

2. **$L_1$ (SIR construction).** The SIR program carries the obligation category, the property-management taxonomy, the tenant's identity binding, and a governance context with `trustClass: interpretive` and `proofRequirement: attestation`. The constraint structure includes a typed temporal gate for response time and an explicit `uncertainty` field that the next layer will propagate.

3. **$L_2$ (lowering to OIR).** The lowering pass refuses to commit to either `repair` or `replace`. Instead, it lowers to an OIR program that records the report, holds the cell in `triaged` state, and produces a structured request for the next-step decision — to be made either by the property manager (a human ratification) or by an inspection visit. The system's commit is to *"this is a maintenance obligation in carpentry/hinge-damage with unresolved repair-or-replace uncertainty"*, not to either resolution.

The handyman intake is the canonical worked example for the gradient because the input has explicit ambiguity that the gradient surfaces and preserves rather than collapses. Direct lowering would have produced a single output (one action); the gradient produces a typed semantic intent with a named uncertainty and a structured request for ratification.

### 5.3 Live evaluation against a production LLM

We report empirical numbers from the substrate's intent-pipeline test suite, running against a production hosted LLM API.

| Scenario                                                            | Outcome      | Latency |
|---------------------------------------------------------------------|--------------|---------|
| "thanks, got it"                                                    | `no_intent`  | ~1.4 s  |
| "the kitchen tap has been dripping for three days"                  | `proposes`   | ~1.8 s  |
| Landlord "approved, proceed with the plumber" (with $850 quote)     | `ratifies`   | ~1.2 s  |
| "approved, proceed" with no pending proposals                       | NOT `ratifies` (disambiguates) | ~1.3 s |

The triage classifier separates inputs into three outcomes: no intent (a conversation patch only — no SIR, no IR, no kernel call), a proposed action (full pipeline runs), or a ratification (a signed pointer to an earlier proposal — skip the pipeline). The ratification path is what makes authoritative-tier attestation cheap at runtime: a landlord saying "approved" on a quote does not need a fresh SIR program; it needs a cryptographic signature pointing at the pending proposal patch.

Across the substrate's full intent-pipeline test surface, 100 unit tests pass without flake (60 in `runtime/intent`, 29 in the shell adapter, 8 architectural gates, 3 with real CellEngine deps); 5 additional live tests run against the production LLM API.

### 5.4 The α-equivalence claim

We claim that two SIR programs that express the same semantic intent must produce α-equivalent OIR programs and, under canonical naming, byte-identical opcode output. The substrate's golden-file corpus tests this claim across ten representative programs covering all seven jural categories. For every program in the corpus, `compile(src)` produces bytes that are byte-identical (or α-equivalent up to canonical variable naming) to `emit(lowerSIR(compileToSIR(src)))`. The equivalence is the contract that adding a new surface grammar (Lisp today; LaTeX, Lean-ish, Ricardian, EDI in design) cannot change observable behaviour for the existing corpus.

The α-equivalence claim is what licenses the architectural promise that *paid extension grammars* are commercially viable: the kernel does not care which surface produced the bytes. A Ricardian-contract parser can lower to SIR with full prose-clause provenance attached as metadata; the OIR will be α-equivalent to the OIR produced by a hand-written Lisp expression of the same intent; the kernel will execute the same bytes either way.

### 5.5 Static refusals at the SIR boundary

We exercise the SIR layer's static-enforcement refusals against six classes of malformed input. Four classes are refused at $L_1$ (compile-time); two are refused at $L_4$ (runtime, by the cell engine).

| Refusal class                                       | Refused at | Mechanism                                              |
|-----------------------------------------------------|------------|---------------------------------------------------------|
| Trust-tier escalation (claimed `authoritative` without `formal` proof) | $L_1$ | `lowerSIR.enforceTrustTier` |
| Allowed-emit-op violation (proposed OIR binding kind not in extension whitelist) | $L_1$ | `lowerSIR.enforceAllowedEmitOps` |
| Action verb not in extension vocabulary             | $L_1$ | confidence scoring + LLM retry loop                     |
| Constraint field references not resolvable          | $L_1$ | `validateConstraintFields`                              |
| Capability not held at runtime                      | $L_4$ | `OP_CHECKCAPABILITY`                                    |
| Linearity violation (LINEAR cell already consumed)  | $L_4$ | K1 gate in `linearity.zig`                              |

Four-of-six refused statically is the property the gradient buys that direct lowering cannot. The runtime refusals at $L_4$ are also strictly more verifiable than the equivalent in a direct-lowering system, because they are gated by mechanically-proved kernel invariants rather than by application logic.

### 5.6 Comparison framing

We do not present a head-to-head benchmark against existing LLM tool-use systems. The reason is methodological: there is no standard task corpus that probes the four refusal classes equally, and no standard metric that captures the difference between "the system said no with a structured reason" and "the system did the wrong thing." A meaningful comparison would require constructing such a corpus, which is future work. The empirical content of this paper is therefore confined to demonstrating that the substrate's pipeline functions end-to-end on representative inputs, that its claimed properties (byte-identical α-equivalence, trust-tier static enforcement, substantial compression) hold, and that the static-refusal capability addresses real failure modes of the direct-lowering architecture by construction.

---

## 6. Discussion

### 6.1 What the gradient enables

The compression gradient enables four classes of system property that direct text-to-action lowering does not:

**Per-layer ratification.** A SIR program can be inspected by a human (or another model) before it is permitted to lower. The `interpretive` trust class with a confirmation turn is exactly this: a partial commit to a typed semantic intent, awaiting explicit user ratification before the OIR layer executes. Direct lowering admits no such partial form.

**Structured refusal.** A failure at any layer produces a typed rejection — a class of error, a layer, a structured reason — rather than a binary "the model failed." This permits a UX in which the system says "I understand you want to do X but I cannot, because this property failed at this layer; here is what would change my answer." Direct lowering refuses opaquely or executes wrongly.

**Multi-surface convergence.** Multiple surface grammars (Lisp today; LaTeX, Lean-ish, Ricardian, EDI in design) can target the same SIR. The α-equivalence property guarantees they converge at the OIR layer. A user can choose the surface most appropriate for their context (a developer types Lisp; a lawyer drafts a Ricardian contract; an engineer writes Lean-ish predicates) and the kernel executes the same bytes regardless. Direct lowering ties the user to whatever surface the model happens to emit.

**Verification surface.** Each layer has a defined shape over which verification can apply. The kernel invariants (K1–K5, K7–K10) are mechanically proved over the execution layer. Trust-tier enforcement is a syntactic check at the SIR layer. Byte-identical golden-file tests anchor the OIR-to-bytes pass. Direct lowering offers no comparable verification surface — the model's output is not a structural form that can be verified.

### 6.2 The role of the LLM in a gradient pipeline

The LLM in our system is a *producer* — a function from natural-language input to a candidate $L_1$ object. It does not execute. It does not own the semantic vocabulary; the active extension's domain grammar parameterises its output schema. Its confidence is computed by the host, not self-reported. Its output is subject to retry-on-validation-failure with the validation error in context.

This is a deliberate inversion of the standard LLM-tool-use architecture. The model is upstream of the pipeline, not the pipeline itself. The model's job is to produce a typed candidate that the gradient will then validate, refine, refuse, or execute. The gradient's properties — refusal, ratification, equivalence, verification — apply regardless of what model produced the candidate; the substrate is model-agnostic by construction.

The slogan we have used elsewhere is: *LLMs should not execute tasks. They should participate in a compression pipeline that produces executable truth.* The substrate is one implementation of that participation.

### 6.3 The trust-tier discipline

The three-tier trust discipline (`cosmetic`, `interpretive`, `authoritative`) makes explicit a distinction the direct-lowering architecture leaves implicit. Cosmetic outputs do not affect economic state. Interpretive outputs may affect state but require explicit user ratification. Authoritative outputs require formal proof or cryptographic attestation. The natural-language path never produces `authoritative` claims directly — that tier is reserved for inputs arriving with a real proof.

This discipline addresses a class of failure that has been observed repeatedly in LLM agent systems: the model produces a confidently-phrased output that the host runtime treats as if it had been formally verified. The trust-tier discipline forces the host to know how strong its evidence is before it acts on the model's output. The static-enforcement at the SIR layer makes the discipline structural — a model output classified as `interpretive` cannot be reclassified to `authoritative` later in the pipeline without explicit cryptographic evidence.

---

## 7. Limitations

We present several explicit limitations of the work as currently implemented.

**Pipeline coverage is partial.** The implemented pipeline ships under continuous integration end-to-end through the SIR, OIR, opcode, and execution layers; the LLM producer is in production for one vertical (trades intake) with a live LLM API integration. Other producers (UI events, shell commands, host-command dispatch) are wired through the same pipeline but with different driver logic. The full eight-producer surface is not yet uniformly enforced under runtime BRC verification across every adapter; the substrate's *Unification Roadmap* tracks the integrative work that closes that gap.

**The α-equivalence claim is tested across one surface grammar.** The corpus exercises α-equivalence across the existing Lisp surface and the SIR-then-emit alternate path. Additional surface grammars (LaTeX, Lean-ish, Ricardian, EDI) are in design but not yet implemented. The architectural commitment that they will produce α-equivalent OIR is structural — it follows from the SIR being a genuine intermediate representation rather than a syntax-specific encoding — but the empirical validation across multiple surface grammars is future work.

**Cryptographic primitives are axiomatised, not verified.** The Lean 4 kernel proofs treat SHA-256, ECDSA, and HMAC as ideal functions under standard computational assumptions. This is standard practice in mechanised verification (used in seL4, CertiKOS, CompCert, Ironclad), but the gap between idealised axioms and computational definitions is a real assumption.

**Implementation conformance is empirical, not proved.** A verified compiler from Zig to WASM does not exist. We mitigate the implementation-vs-abstract-model gap with 240+ conformance tests, property-based fuzzing, differential testing against the Lean model, and a 100% mutation-kill target. These are strong empirical evidence; they are not formal proof of conformance in the same sense that the Lean theorems are.

**No head-to-head benchmark against existing systems.** As noted in §5.6, a meaningful comparison against direct-lowering LLM tool-use architectures requires a task corpus that probes structured refusal as a first-class property. Such a corpus does not exist; constructing one is future work. The empirical content of this paper is necessarily confined to validating the substrate's claimed properties on representative inputs.

**The gradient adds engineering cost.** Each additional layer adds typing rules, validation, and emit-pass implementation. We claim the cost is justified by the four refusal capabilities and the verification surface; we acknowledge that for systems that do not require those capabilities, a simpler architecture is appropriate. The compression gradient is the right discipline for *reliable* language-driven execution; it is overkill for systems where reliability is not load-bearing.

---

## 8. Conclusion

We have argued that reliable language-driven execution is structurally a compiler problem, not an alignment problem. The standard LLM-tool-use architecture asks a model to produce executable artefacts in a single inference pass, with no inspectable, ratifiable, type-checked intermediate forms. The model is the front-end of the pipeline. The system inherits whatever properties the model has, with no opportunity for typed refusal, ratification, or verification along the way.

The compression gradient is a discipline that recovers the missing structural properties: layered intermediate forms with canonical shapes and validation rules, explicit loss boundaries, semantic preservation under α-equivalence, and per-layer refusal capability. Each layer earns its keep by providing a property the layers around it cannot. The result is a pipeline in which an LLM can participate as a producer of typed candidates without ever being trusted to execute. The execution layer enforces the same invariants whether the input arrived from a model, a button click, or an inbound network frame.

The Semantos substrate is one implementation. Its five-layer gradient demonstrates byte-identical α-equivalence across surface grammars, substantial compression from natural language to opcode bytes (between twenty-four times and one hundred and twenty times depending on the layer compared), four-of-six static refusals against malformed input, and mechanised kernel-invariant proofs for the substructural execution layer. Eight Lean-formalised domain lexicons demonstrate that the discipline generalises across very different problem spaces. The substrate is implemented in a polyglot research codebase under continuous engineering at scale.

We invite the broader systems community to treat reliable language-driven execution as a compiler-construction problem and to apply the discipline that compiler construction settled decades ago. The model is upstream of the pipeline. The pipeline is what makes the model's output safe to act on.

---

## Appendix A — Notation

| Symbol | Meaning |
|---|---|
| $L_i$ | The $i$-th layer of a compression gradient |
| $L_0$ | Natural-language input |
| $L_1$ | Semantic intermediate representation (SIR) |
| $L_2$ | Opcode intermediate representation (OIR) in administrative normal form |
| $L_3$ | Opcode bytes (cell engine instruction stream) |
| $L_4$ | Two-stack pushdown automaton execution |
| $\mathsf{valid}_i$ | Validation predicate at layer $L_i$ |
| $\mathsf{emit}_i$ | Emit function $L_i \to \mathsf{Error} + L_{i+1}$ |
| ${\approx_i}$ | Semantic equivalence relation at layer $L_i$ |
| α-equivalence | Operational equivalence under canonical variable renaming |
| K1–K10 | Mechanised kernel invariants over the cell engine model |
| BRC-N | Bitcoin Request for Comments standard N (e.g. BRC-52 = identity certificates) |

## Appendix B — References

The substrate composes the following published work:

- **Hohfeld, W. N.** (1913). *Some Fundamental Legal Conceptions as Applied in Judicial Reasoning.* Yale Law Journal.
- **Sabry, A.; Felleisen, M.** (1992). Reasoning About Programs in Continuation-Passing Style. *Lisp and Symbolic Computation* 6.
- **Flanagan, C.; Sabry, A.; Duba, B. F.; Felleisen, M.** (1993). The Essence of Compiling with Continuations. *PLDI '93*.
- **Wadler, P.** (1990). Linear Types Can Change the World. In *Programming Concepts and Methods* (North-Holland).
- **Necula, G. C.** (1997). Proof-Carrying Code. *POPL '97*.
- **Zelle, J. M.; Mooney, R. J.** (1996). Learning to Parse Database Queries Using Inductive Logic Programming. *AAAI '96*.
- **Liang, P.** (2016). Learning Executable Semantic Parsers for Natural Language Understanding. *Communications of the ACM* 59(9).
- **Klein, G.; et al.** (2009). seL4: Formal Verification of an OS Kernel. *SOSP '09*.
- **Leroy, X.** (2009). Formal Verification of a Realistic Compiler. *Communications of the ACM* 52(7).

The substrate also depends on the BRC standard suite (BRC-42, BRC-43, BRC-52, BRC-53, BRC-62, BRC-69, BRC-74, BRC-85, BRC-94, BRC-95, BRC-100, BRC-103, BRC-108) and on the `@bsv/sdk` and `wallet-toolbox` reference implementations.

## Appendix C — Reproducibility

The substrate is implemented in a polyglot research codebase. The intent pipeline lives at `runtime/intent/` (60 unit tests). The shell adapter lives at `runtime/shell/src/intent-adapters/` (29 unit tests). The architectural gates live at `tests/gates/intent-pipeline*.test.ts` (8 + 3 tests). Live tests against the production LLM API live at `extensions/extraction/src/intent-adapters/` (5 tests, requires API credentials). The cell engine lives at `core/cell-engine/` (~4 900 LOC of Zig; `bun test` to exercise the conformance suite). The Lean theorem proofs live at `proofs/lean/Semantos/Theorems/`. The TLA+ specifications live at `proofs/tla/`.

The eight lexicon files live at `proofs/lean/Semantos/Lexicons/` (one file per lexicon, ≈ 40 lines each). The substrate's typeclass definition that these instances target lives at `proofs/lean/Semantos/Substrate/Lexicon.lean`.

A reproducibility artifact bundling the relevant subset (intent pipeline, lexicon files, golden-file corpus, gate tests, Lean theorems, TLA+ specs) accompanies the public release of this paper.

---

*Draft submitted for internal review prior to arXiv preprint posting.*
