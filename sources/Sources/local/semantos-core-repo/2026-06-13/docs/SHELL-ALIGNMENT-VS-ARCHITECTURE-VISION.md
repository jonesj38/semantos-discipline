---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SHELL-ALIGNMENT-VS-ARCHITECTURE-VISION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.331642+00:00
---

# Semantic Shell — Alignment Audit vs. Architecture Vision

**Date**: 2026-04-17 (revised)
**Scope**: What the recent shell PRs have landed, where they match the "Paskian / governed-grammars / voice-to-economic-execution" architecture, where the code runs behind the vision, why this architecture is structurally powerful, and what order the remaining work should land in.

---

## 1. The vision, compressed

From the architecture conversation, the intended stack is:

```
voice / text / legacy data / signals
    │
    ▼
expression layer       (voice, text, UI skins, local shorthand)
    │
    ▼
interpretation layer   (parsers, inferred extension grammars, structure induction)
    │
    ▼
governance layer       (domain flags, ID certs, capability checks, trust-class gates,
                        optional Lean validation on authoritative patches)
    │
    ▼
execution layer        (canonical IR → ScriptWords → 2PDA predicates → economic effect)
```

Three control laws sit on top of that stack:

1. **Anything may be proposed. Only some things may be interpreted. Fewer may affect semantics. Very few may execute economically.** Trust tiers: cosmetic → interpretive → authoritative.
2. **Inference may suggest syntax. Governance must ratify meaning.** The Paskian plane proposes; the governance plane adjudicates; canonicalisation compiles; the 2PDA executes.
3. **Grammars are a form of power.** An extension grammar is not neutral syntax. It is a scoped authority to turn tokens into ScriptWords, fenced by `opcheckdomainflag`, `checkID`, and `ophascapability`.

What follows is a read of the codebase against that frame.

---

## 2. What the recent work actually landed

### 2.1 The compression gradient is now explicit

`docs/SHELL-SESSION-ARCHITECTURE.md` (landed in PR #72) says, verbatim:

> A single operation exists at four levels of abstraction simultaneously: natural language, CLI command, lisp policy constraint, and cell opcodes. The shell sits at the CLI layer but can accept input from NL and compile down to opcodes. The UI sits above NL. The kernel sits below opcodes. The shell is the bridge.

This is the architecture conversation, committed to the repo. Not only does it match, it's become the stated design philosophy of the shell rather than a sketch.

### 2.2 Lisp is the first working surface grammar

`packages/shell/src/lisp/` has `parser.ts`, `types.ts`, `compiler.ts`, `packer.ts`. It compiles an S-expression policy form (`PolicyForm` with `subject: IdentityRef`, `action`, `constraint`, `linearity`) through a typed `ConstraintExpr` AST down to packed opcode bytes for the Zig 2PDA. `IdentityRef` is already `role | domainFlag | certPattern`, and the constraint forms include `capability`, `domainCheck`, `timeConstraint`, `hostCall`, and `typeHashCheck`. That is exactly the "Lisp = raw symbolic power, lowers to ScriptWords" frontend we described, already operational.

### 2.3 The capability-gated kernel is real and proven

`packages/cell-engine/src/opcodes/plexus.zig` implements `opCheckDomainFlag`, `OP_CHECKIDENTITY` (0xC4), and the capability-check family. These are not just implemented — they have Lean proofs:

- `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean` — K3a (mismatch → failure-atomic error), K3b (match → deterministic success).
- `proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean` — identity check soundness.
- PR #67 (`feat/extended-opcodes-clean`) added K8 Demotion (21 theorems), K9 Temporal Morphism (11), K10 Turing Completeness (12) — **zero sorry/admit** — alongside 19 BSV-restored opcodes and 4 new Plexus ops (`OP_READHEADER`, `OP_CELLCREATE`, `OP_DEMOTE`, `OP_READPAYLOAD`).

So the "power-by-opcode" base with `opcheckdomainflag / checkID / ophascapability` exists, and it has formal backing rather than just code. This is the bedrock the rest of the vision rests on.

### 2.4 Hierarchical governance (L0/L1/L2) is committed

Phase 36D shipped. `configs/extensions/core.json` registers `governance.policy` as a RELEVANT Constitution-type object. `packages/extraction/src/governance/` contains `constraint-engine.ts` (L0 + L1 enforcement), `credential-vault.ts`, `dispute-escalator.ts`, `manifest-publisher.ts`, `version-compat.ts`. The shell has a `govern` verb with `policy | manifest | binding | dispute` subcommands, including `propose-patch`, `pin`, `override-field`, `compat`, `deprecate --days N`, and `dispute create/escalate/list` (L2→L1 and L1→L0).

Mapping onto the vision:

- L0 Constitution = platform meta-schema + required capability whitelist + taxonomy reservations + >66% ballot quorum
- L1 ExtensionManifest (AFFINE→RELEVANT) = author-governed grammar evolution
- L2 ConsumerBinding (AFFINE, node-scoped) = consumer config, credentials, field overrides, version pin

That is the "governance plane adjudicates" layer we argued for. Constraints flow down, disputes flow up — the exact cybernetic loop Pask would recognise.

### 2.5 Paskian-style structure induction runs, but as a manual CLI

Phase 36C shipped `packages/extraction/src/inference/` with `InferenceAgent`, `StructureAnalyzer`, `TaxonomyMapper`, `GrammarDiff`, `GrammarComposer`, and an `llm-client.ts`. The shell exposes `semantos infer <sample.json>` → `review` → `approve [--publish]` → `reject --reason`. Every inferred grammar is created as an **AFFINE draft** pending review. Approval attaches a patch (`grammar_approved`, with facet id and capabilities) to the evidence chain; `--publish` transitions AFFINE → RELEVANT.

That is a literal implementation of *inference proposes, governance ratifies, canonicalisation promotes*. The AFFINE-draft-until-approved discipline is the right default.

### 2.6 Domain coordination targets are seeded

- **CDM** — `packages/cdm/` has `lifecycle.ts`, `regulatory.ts`, `bridge/cdm-json.ts`, `bridge/fpml.ts`, and `.policy` files (`close-out-netting`, `failure-to-pay-default`, `payment-condition-precedent`, `transfer-consent`, `variation-margin`). Shell verb: `semantos cdm import | event | novate | report | history | portfolio | netting`.
- **SCADA** — `packages/scada/` has `authorization.ts`, `interlocks.ts`, `policies/`, typed sensor / equipment / command taxonomies with linearity mapping (TelemetryCell AFFINE, CommandCell LINEAR, AlarmCell LINEAR, EquipmentCell RELEVANT). Operational modes, quality flags, alarm severity — the actuator-safety surface is there.
- **Plexus contracts** — `packages/plexus-contracts/src/` has `domain-flags.ts` (Plexus-reserved vs client-defined namespaces), `identity.ts`, `recovery.ts`, `transport.ts`, `graph.ts`.

CDM and SCADA are the two hardest domains we called out (CDM is almost-direct semantic fit; SCADA is extreme-risk). Both now have a real package, real types, and a shell verb. Ricardian contracts are present in spirit (CDM `.policy` files + plexus-contracts) but not as a dedicated surface grammar yet.

### 2.7 Voice-to-Economic-Execution is drafted, not built

This is the single biggest in-flight gap. `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` + sub-phases 38A through 38G are written. They define:

- `HostCommand` object type + `HOST_EXEC` capability (38A)
- Handler registry + `process.killByPort` reference handler (38B)
- `host.exec` shell verb (38C) with publish-then-execute, capability gate, signed request cell
- Audit CLI `host audit <id>` (38D)
- Voice capture via Web Speech API (38E)
- NL → `ShellCommand` extractor via LLM (38F)
- Helm UI wiring: Talk input → approval card → Do/Transact receipt (38G)

The acceptance test is the exact sentence we had in mind: user says "kill the process on port 9000", a signed `HostCommand` appears with `hatId`, `signedBy: <certId>`, `exitCode`, `stdout` — and a second attempt without `HOST_EXEC` returns a structured error with no side effect. **Zero code for this phase has landed yet.** The PRDs are on `main`, the branch `phase-38-voice-to-execution` has not been cut.

The critical path here is also shorter than it looks. V2E is really: a new object type (`HostCommand`, LINEAR), a capability gate (`HOST_EXEC`) on an existing route-table entry, a handler that publishes-then-executes and returns a structured receipt, and UI wiring. Router, capability opcodes, StoreBridgeServer broadcast, and the object type registry already exist. This is a hookup exercise, not a foundation-laying exercise. Treating it as small and sharp is the right framing.

### 2.8 The 1-3-5 Pyramid UI is wired to the shell pipeline

PR #72 (`feat: wire 1-3-5 Pyramid UI to shell pipeline`) routes every Helm UI action through `parseCommand() → route() → capability gate`. `DoMode` has 5 context tabs (Transact / Manage / Create / Play / Offer), `TalkMode` has 5 (Self / Direct / Squad / Agent / Broadcast), `FindMode` has 5 (Memory / Market / Network / Value / Truth). The UI is no longer a bespoke handler; it's a thin client on top of the same route table the REPL uses. That's the "UI projects onto the shell" principle made concrete.

### 2.9 The narrative / learning Paskian layer (naming collision alert)

`packages/paskian/` currently hosts the **border-router aggregator / BSV anchor pipeline** (PR #55 — H3 settlement layer). Its `narrative-oracle.ts` is a typed stub for Claude prompt-caching bridge into a constraint graph. `configs/extensions/paskian-story.json` registers `paskian.graph.node`, `paskian.graph.edge`, and `paskian.graph.stable` as RELEVANT types.

This is not the "Paskian learning" of the conversation — which is really the *adaptive grammar-patch proposer*. The adaptive proposer currently lives in `packages/extraction/src/inference/` as `InferenceAgent`. **The name "paskian" is overloaded in the repo.** One package is the settlement plane + narrative oracle; the other is the induction engine. Anyone reading the codebase without the architecture conversation in their head will wire the wrong thing. This is cheap to fix now and expensive to fix after external contributors arrive, so the rename should happen early in the sequencing rather than be deferred.

---

## 3. Why this architecture is structurally powerful

Most shells are syntax over side effects — you express what you want, the system does it, trust is implicit in who's logged in. This architecture is different in kind, in a specific and worth-naming way.

**It separates the right to propose from the right to mean from the right to execute.** The trust-tier ladder (cosmetic → interpretive → authoritative) with formal backing at the authoritative tier means the system can accept input from untrusted or partially-trusted sources — inference agents, voice, external APIs, other organisations — without collapsing the trust boundary. Most systems achieve safety by restricting who can speak. This one restricts what speech can mean and do, independently. That is a different theory of what computation authority is.

**The compression gradient is a genuine insight, not a pipeline.** Voice → NL → CLI → Lisp → IR → opcodes → economic effect is not just stages in a build. It is a claim that all of these are the same operation at different levels of abstraction, and that the shell is the bridge that makes that identity real. That claim implies a CDM novation, a SCADA actuator command, and "kill the process on port 9000" are all the same kind of thing structurally. The system does not treat economic actions as special cases bolted onto a command interpreter. It treats the command interpreter as a projection of an economic execution engine.

**Formal proofs on the opcodes mean the bedrock is load-bearing.** The Lean theorems on domain isolation (K3), identity soundness (K2), failure atomicity (K4), demotion (K8), temporal morphism (K9), and Turing completeness (K10) are not documentation. They are a guarantee that governance-plane decisions propagate correctly down to execution. The system can be extended confidently because the floor is known to hold.

The most powerful thing is not any single component — it is the combination of:

1. **Inferred grammars** (Paskian / InferenceAgent watching the world, proposing structure)
2. **Governed promotion** (AFFINE → RELEVANT requiring ratification)
3. **Opcode-level enforcement** (ratified structure executes; unratified does not, structurally, not by convention)
4. **Continuous adaptation** (once the monitor is a service, not a CLI)

Applied to CDM and SCADA specifically, this is a system that can onboard a new financial instrument schema or a new sensor type by observing examples, proposing a grammar, routing it through domain experts for approval, and then executing against it with the same formal guarantees as the built-in opcodes. That is not something existing shells, workflow engines, or smart contract platforms do.

**The honest ceilings.** Two of them are worth naming because the architecture makes it easy to forget.

The first ceiling is governance quality. The Lean proofs prove the engine is correct, not that the grammars are wise. If the L0 Constitution is poorly designed, or the trust-tier ladder is gamed, or the induction agent is fed poisoned examples, the formal guarantees hold at the opcode level but the semantic level is compromised. The system is only as trustworthy as the humans who ratify grammars and design the Constitution — true of all governed systems, but especially worth stating here because the formal-methods layer can create false confidence about the epistemic layer above it.

The second ceiling is the IR extraction gap. Right now Lisp compiles straight to opcodes and there is no peer-frontend equivalence surface. Until that exists, the claim that "voice and LaTeX and Lean-ish propositions and CDM events are all the same thing at different abstraction levels" is architectural intention, not demonstrated fact. Once the IR exists and two or three surface grammars lower into it and produce equivalent ScriptWord bundles, the compression-gradient claim becomes verifiable. Section 5 is about how to cross that gap specifically.

---

## 4. Where the vision still runs ahead of the code

These are the concrete items from the conversation that do **not** have an obvious implementation yet. Ordered by how load-bearing they are.

### 4.1 Phase 38 V2E — the headline demo

Everything above converges on this sprint. The PRDs exist; the work has not started. Until this lands, the "voice/text → admissible semantics → economic execution" claim is documentation, not substrate. The hot path 38A → 38B → 38C → 38G should be prioritised. 38D/E/F parallelise behind it.

Hook points that already exist and want the 38 work to land on them:

- Route table (`packages/shell/src/router.ts`) gets a `host.exec` entry with `requiresCapability: HOST_EXEC`.
- Object type registry (`configs/extensions/host-ops.json`) gets `HostCommand` LINEAR.
- `StoreBridgeServer` already broadcasts; the `host audit` CLI just replays patches.
- Handler registry is pure allowlist; the threat model per handler goes in its PR body (per the PHASE-38 risk register).

### 4.2 The trust-tier ladder is load-bearing *now*, not later

We argued for `trust_class = cosmetic | interpretive | authoritative`, `proof_requirement = none | shape | equivalence | theorem`, and `execution_authority = none | advisory | bounded | full` on every patch. Today the patch/manifest/binding objects carry governance metadata but not those three fields explicitly.

The sequencing risk here is sharp: once `HOST_EXEC` lands, economic execution flows through a governance plane that does not structurally distinguish cosmetic from authoritative patches. The constraint engine will enforce what is declared, but nothing prevents an authoritative-intent patch from being submitted with only cosmetic-level proof obligations if the field does not exist yet. **These fields should land in the same window as `HostCommand` registration**, or at minimum before `host.exec` touches a non-dev environment. The opcode hardening (soft vs hard predicates) can wait; the manifest field cannot.

### 4.3 Allowed-emit-ops whitelist per grammar patch

Even with domain + identity + capability gating, a grammar could still be too expressive. Each patch should declare what IR nodes / opcodes it is allowed to emit. `constraint-engine.ts` today checks required-capability declarations (L0) and field-override additivity (L1) but does not enforce an opcode-emission whitelist.

The surface is: `GrammarPatch.allowedEmitOps: OpcodeSet`, `allowedIrKinds: string[]`, `forbiddenOpFamilies: string[]`, `maxElaborationDepth: number`, `introducesNewSymbols: boolean`. The compiler (`packages/shell/src/lisp/compiler.ts`) is the natural enforcement point today.

Note a dependency the earlier ordering missed: without an IR, `allowedEmitOps` would whitelist against opcode bytes emitted by the Lisp compiler rather than against a typed IR node set. That is enforceability at the wrong level of abstraction. The whitelist becomes properly meaningful *after* the IR extraction, which is why the sequencing in Section 6 pairs them.

### 4.4 Epistemic grammar: hard vs soft predicates

Once Paskian starts inferring API shapes, the system represents more than "asserted truth". It represents *observed / inferred / approximated / proposed / verified / rejected* structure, each with a confidence. The 2PDA must not confuse "must be true" with "likely true from compression-gradient induction".

Today there is one ScriptWord class. Everything that passes the gates executes as a hard predicate. There is no opcode-level distinction between:

- **Hard predicate** — authoritative, economically executable.
- **Soft predicate** — advisory, evaluated for search/recommendation, never directly economic.
- **Unresolved proposal** — a search object carrying its own provenance and confidence.

Either add an opcode tier (e.g. `OP_ASSERT_SOFT`, or a flag on the cell header), or add a linearity/visibility class that prevents a cell marked "inferred" from being consumed by an economic verb. The governance plane is the first line of defence, but a defence-in-depth opcode distinction is cheap and worth it.

### 4.5 Lean as a runtime gate on authoritative patches

Lean proofs today live in `proofs/lean/` and gate *the implementation* (opcode semantics, linearity, PDA). They do not gate *a user-submitted grammar patch* at admission time. The vision is selective: cosmetic/interpretive patches do not need Lean; authoritative ones do.

Hook point: `manifest-publisher.ts` (which moves an `ExtensionManifest` from AFFINE to RELEVANT) calls a new `enforceProofObligations(manifest, policy)` when `trust_class === 'authoritative'`. That function either takes a Lean file attached to the manifest and runs `lake build` in a sandbox, or checks an attached proof certificate hash against a trusted prover signature, or defers to a proof-oracle service. This is how "sometimes Lean, sometimes not" becomes a structural distinction rather than a cultural one.

### 4.6 LaTeX / Lean-ish frontends and the peer-grammar IR

Lisp is the only working surface grammar. Lean is proof-side, not input-side. LaTeX is absent. The conversation argued these should be **peer frontends** over a shared typed semantic IR so that a Lean-ish proposition, a Lisp-ish symbolic form, and a LaTeX inference rule all lower to the same normalised object and the same ScriptWord bundle.

Right now Lisp compiles *straight* to opcode bytes with no visible IR layer. Before adding Lean or LaTeX as frontends, pull a typed IR out of `lisp/compiler.ts` — `semantos-ir` — and make Lisp lower into it. Otherwise each new frontend duplicates the lowering logic and there is no equivalence-check surface between them.

The "Semantos TeX Profile" from the conversation comes next. Restricted symbol set (`\forall`, `\exists`, `\to`, `\mapsto`, `\vdash`, `\frac`, matrix envs, judgments, inference-rule environment), no macro expansion, no package land, deterministic lowering, bound to a domain flag and capability set. Valuable, but only after the IR is extracted. The Rúnar reference in Section 5 shapes how that extraction should be done.

### 4.7 Ricardian and EDI surface grammars

CDM and SCADA are packages. Ricardian contracts and EDI (EDIFACT / X12) are not. Both are natural next surface grammars. Ricardian is closer to Lean-ish / LaTeX-ish (human-legible legal form + machine-executable clauses) and benefits from the epistemic-grammar work in 4.4. EDI is closer to the schema-induction path — the Paskian / InferenceAgent already has the right shape for it (sample messages → inferred grammar → AFFINE draft → human review → RELEVANT).

Concrete: a `packages/edi` that plugs into `InferenceAgent` as a `SourceDeclaration.protocol: 'edifact'` adapter, producing `InferredGrammar` drafts. A `packages/ricardian` with a parser for the legal-prose-plus-predicate form, lowering into the same semantic IR.

### 4.8 The Paskian plane as a continuous monitor

`semantos infer <file>` runs on demand. The conversation described something more ambitious: a **continuous adaptive coordinator** that watches corpora / interfaces / usage / failures per org and agent, proposes patches, routes them for approval, tracks outcomes, retracts or refines. Today this is a human-invoked tool. The scaffolding is there — `InferenceAgent`, evidence-chained AFFINE drafts, approval/reject verbs — but nothing schedules it, nothing subscribes it to usage failures, nothing per-org-per-agent scopes its proposals.

The cleanest way to turn the CLI into a plane is a long-running service (same shape as the border-router-aggregator service) that consumes `StoreBridgeServer` events (especially error and capability-denied categories), periodically runs `InferenceAgent` against observed new shapes, and **publishes draft grammar patches into the same AFFINE → review → RELEVANT pipeline**. The governance surface does not change; only the trigger changes from human to observation.

This is the architecture's long-term character. Everything else is infrastructure. The continuous-monitor version is where the system becomes what the design document says it is — genuinely adaptive rather than a well-governed static shell. It should come last in the sequencing, not because it is low priority but because it is the component whose blast radius depends most on everything else being structurally sound.

### 4.9 Patch metadata that's still implicit

Most of the following fields are conceptually present but not structured:

- `target scope: user | org | agent | domain` — scoping happens via `ExtensionManifest` + `ConsumerBinding`, but `agent` is not a first-class scope.
- `intent: parse-only | transform | migration | extraction | execution` — implicit in the verb the patch participates in; making it an enum lets `constraint-engine` reject "execution-intent patches without authoritative trust class".
- `rollback recipe` — `deprecate --days N` gives a sunset timer, but no automated reverse migration.
- `aliases-only vs new-terms` — `override-field` today only adds; there is no explicit "this patch introduces a new canonical symbol" flag, which matters for namespace protection.
- `source evidence` per patch — the AFFINE draft carries evidence from the inference run, but once approved the link from ratified patch back to the original induction evidence (sample responses, LLM settings, confidence flags) is not structured for audit.

Small schema additions on top of existing governance objects. The governance engine already has the enforcement shape; it just needs richer input.

### 4.10 High-risk domain risk tiers are not declared, and SCADA has a sequencing problem

Domains are not equal risk: UI/spelling none, EDI medium, CDM high, Ricardian very high, SCADA extreme. Today SCADA ships with `authorization.ts` + `interlocks.ts` + policies, which is right. But there is no system-wide `DomainRiskTier` registry that maps an extension ID to a risk class and fans out the required gating (e.g. SCADA extreme → `HOST_EXEC`-equivalent capability, multi-sig approval, mandatory interlock validation, forbidden inferred-grammar auto-promotion).

The sequencing risk is specific: right now a SCADA grammar patch could in principle be inferred and promoted through the same AFFINE → RELEVANT pipeline as a CDM grammar patch, because the promotion path does not branch on risk tier. **A hard-block in `manifest-publisher.ts` preventing any inferred SCADA grammar from being promoted should land before the continuous Paskian monitor sees a single SCADA sample.** Even if that hard-block is temporarily "reject all SCADA auto-promotion", the hard-block matters more than the policy. The policy can be refined later; the absence of a block is the risk.

---

## 5. Rúnar as the IR reference implementation

The IR extraction is the unsexy unblocking dependency for most of Section 4. Everything from LaTeX frontends to allowed-emit-ops whitelists to Lean gating is cleaner once a typed IR sits between surface grammar and opcode emission. Rúnar — the TypeScript/Go/Rust/Solidity/Move-to-Bitcoin-Script compiler, BSV-targeted, open-source at `github.com/icellan/runar` — solved the exact problem of "multiple surface languages, one canonical IR, byte-identical output, differential testing" that Semantos needs to solve before the peer-frontend architecture is demonstrable. It is worth treating as the reference methodology.

### 5.1 What to import: methodology, not schema

The single most valuable contribution is the **verification methodology for peer-frontend equivalence**. Three independent compiler implementations producing byte-identical output against a canonical-JSON Administrative Normal Form IR with a golden-file conformance suite is how the architectural claim "Lisp, LaTeX, Lean-ish, Ricardian, and EDI all lower to the same thing" becomes checkable rather than aspirational. Frontends produce canonically serializable IR; two frontends that disagree produce different hashes; the conformance tests lock the boundary.

Specifically:

- **ANF** — every sub-expression gets a named temporary, no evaluation-order ambiguity.
- **Canonical JSON serialisation** (RFC 8785) — the IR is hashable and comparable, so differential testing is mechanical.
- **Six-pass nanopass pipeline** — Parse → Validate → Type-check → ANF Lower → Stack Lower → Emit, each pass a pure function small enough to audit. The current `lisp/compiler.ts` is doing parse-through-emit in one shot; pulling out the IR means splitting it into this shape.
- **Golden-file conformance tests** — committed with the IR, locking equivalence between frontends at an IR version.

When IR extraction happens, model the IR boundary on Rúnar's approach directly: define `semantos-ir` as ANF with canonical JSON serialisation, make Lisp lower into it with existing behaviour identical, write golden-file conformance tests against known Lisp inputs *before* adding any new frontend. By the time LaTeX or Lean-ish arrives, the conformance suite is already the equivalence check.

### 5.2 Structural analogies that are deeper than pattern-relevant

Rúnar's contract model maps onto Semantos semantic objects so closely that the vocabularies are almost interchangeable:

- `StatefulSmartContract` auto-injects sighash preimage verification on entry and state-continuation enforcement on exit — structurally identical to a LINEAR cell that can only be consumed once while producing its successor, with the continuation enforced by the script itself.
- Multi-method contracts compiled into `OP_IF/OP_ELSE/OP_ENDIF` branches, with the spending transaction pushing a method index, map onto transitions on a single Semantos object type.
- `this.addOutput()` for token splitting maps onto LINEAR cell splits where a multi-output spend produces multiple successor cells.

These are not analogies — they are the same patterns described in different idioms.

### 5.3 The highest-leverage integration: Rúnar as a fifth surface frontend

Rather than use Rúnar as a separate tool alongside Semantos, compile `.runar.ts` not to raw Bitcoin Script hex but to Semantos IR. The IR then lowers to ScriptWords with governance metadata (trust_class, domain_flag, capability set, allowed_emit_ops) layered on top. This gives:

- TypeScript / Go / Rust / Solidity / Move contract authoring for developers who already know those languages.
- The trust-tier ladder, `opcheckdomainflag / checkID / ophascapability` kernel gates, and Lean proofs on the execution layer.
- A closed loop from TypeScript class → ANF → Semantos IR → ScriptWords → 2PDA execution → BSV settlement via the existing Border Router in `packages/paskian`.

That is the full compression gradient demonstrated end-to-end with a real contract-authoring language, against a real blockchain, with the governance plane intact. It is also the cleanest way to *validate* the IR methodology, because Rúnar's own conformance suite exercises it.

### 5.4 What not to copy, and why

- **The schema is Bitcoin-Script-shaped.** Rúnar's ANF is tuned for a stack machine with no loops, single contract per file, restricted function calls. Semantos IR has to carry continuations that are not preimage-based, capability envelopes, domain-scoped symbols, epistemic tags (hard vs soft predicate), provenance links back to inducing sample responses for Paskian-originated patches. Take the shape — ANF with named intermediates, canonical JSON, six-pass nanopass — not the schema verbatim.
- **Rúnar's three compilers are locked to byte-identical output forever.** That effectively freezes their IR. Semantos IR is going to evolve as governance metadata grows (`execution_authority`, per-tier `proof_requirement`, soft-predicate evidence linkage). The golden-file conformance suite should therefore be **versioned** — it locks equivalence *between frontends at an IR version*, not equivalence of the IR across system evolution. Small discipline change, but matters for the next 3–5 years.
- **The lowering target is different.** Rúnar emits Bitcoin Script hex. Semantos emits ScriptWords for the 2PDA (19 BSV-restored + 4 Plexus ops, capability-gated, Lean-proved). The emit pass is Semantos-specific.

### 5.5 The orthogonal strategic prize

Rúnar ships WOTS+ and SLH-DSA (FIPS 205 / SPHINCS+) post-quantum signature verification compiled entirely into Bitcoin Script — ~10 KB and 200–900 KB respectively — using only existing opcodes. For a system that intends to be a long-term economic substrate (especially for SCADA and Ricardian cases where a 15-year-out compromise is catastrophic), having PQ verification available as ScriptWord-compilable primitives without protocol change means the option exists. Not immediate priority, but a line item worth holding open in the roadmap.

---

## 6. What needs to happen, in order

The main risk in the remaining work is **sequencing**, not scope. Specifically: landing economic execution before the manifest trust-tier field exists, and adding surface grammars before the IR layer exists. The windows below compress the earlier roadmap in light of that.

### Window 1 — same PR, non-negotiable pairing

- **Phase 38A** (`HostCommand` object type + `HOST_EXEC` capability + `host-ops` extension config).
- **Trust-tier fields on `ExtensionManifest.governanceConfig`**: `trust_class`, `proof_requirement`, `execution_authority`. Constraint engine branches on them.

These must land together. Shipping `HOST_EXEC` with trust-tier to follow means economic execution flows through a governance plane that cannot structurally distinguish cosmetic from authoritative patches. That is a defensible sequencing bug; do not do it.

### Window 2 — immediately after Window 1

- **Phase 38B** — handler registry + `process.killByPort` reference handler.
- **Phase 38C** — `host.exec` shell verb with publish-then-execute semantics, capability gate, signed request cell.
- **Phase 38G** — Helm UI wiring: Talk input → approval card → Do / Transact receipt.
- **Phase 38D/E/F** parallelise as their predecessors land.

This is the capability-demo milestone. Voice says "kill the process on port 9000"; a signed `HostCommand` appears with verifiable patch chain; absence of capability produces a structured error with no side effect. After Window 2, the architecture's headline claim is a running demo.

### Window 3 — pre-frontend hardening (parallel tracks)

- **IR extraction from `lisp/compiler.ts`** into `semantos-ir`, modelled on Rúnar's ANF + canonical JSON + six-pass nanopass + golden-file conformance methodology (Section 5). Existing Lisp behaviour preserved; golden tests lock the boundary.
- **`packages/paskian` rename.** Settlement layer (border-router aggregator + narrative oracle) gets one home (e.g. `packages/settlement` or `packages/border-router`); induction plane gets another (e.g. `packages/induction` housing what is today `packages/extraction/src/inference`). Before external contributors arrive, not after.
- **`DomainRiskTier` registry in the Constitution + hard-block in `manifest-publisher.ts`** so no inferred SCADA grammar can be promoted until risk-tier enforcement is wired. The hard-block matters more than the policy; a temporary "reject all SCADA auto-promotion" is fine, absence of the block is not.
- **`allowedEmitOps` whitelist on the grammar-patch schema**, meaningfully enforceable now that the IR exists. Enforcement point is the IR → ScriptWord emit pass, not the Lisp parser.

Window 3 can and should run in parallel with Window 2 where sessions allow. It is the foundation everything after depends on.

### Window 4 — validate the IR methodology with a real second frontend

- **Rúnar as the second surface frontend**, targeting Semantos IR rather than raw Bitcoin Script. This is what exercises the conformance suite, proves the peer-frontend architecture in practice, and yields TypeScript / Go / Rust contract authoring on top of Semantos governance with BSV settlement as a natural byproduct.

Only after Window 4 is the compression-gradient claim demonstrated rather than asserted.

### Window 5 — more frontends and domain surfaces

- **Lean-ish frontend** (third peer grammar) for theorem / proof authoring.
- **Semantos TeX Profile** — restricted LaTeX, bounded by `allowedEmitOps` and domain flag. No macro expansion, no package land, deterministic lowering.
- **`packages/ricardian`** — legal prose + machine-executable clauses. First real user of the LaTeX profile.
- **`packages/edi`** — EDIFACT / X12 adapter feeding `InferenceAgent` via `SourceDeclaration.protocol: 'edifact'`.

### Window 6 — continuous Paskian monitor

- **`InferenceAgent` promoted from CLI to long-running observation service.** Subscribes to `StoreBridgeServer` events (errors, capability-denied, unknown shapes). Runs per scope (`user | org | agent | domain`). Publishes draft grammar patches into the same AFFINE → review → RELEVANT pipeline.

This comes last not because it is low priority but because the governance plane needs to be structurally sound before the monitor starts proposing. Windows 1–5 are preconditions for Window 6 to operate safely. Phase D is where the system becomes what the design document says it is.

### Window 7 — optional Lean gating on authoritative patches

- **`enforceProofObligations(manifest, policy)`** invoked by `manifest-publisher.ts` when `trust_class === 'authoritative'`. Certificate-hash check against trusted prover signature first; sandboxed `lake build` later.

### Ongoing

- **Soft-predicate opcode distinction** (or cell-header flag). Defence-in-depth behind governance. Can land any time after Window 1 once the trust-tier schema exists.
- **Patch metadata refinements** (Section 4.9) — schema additions on top of existing governance objects.
- **Post-quantum primitives** (WOTS+ / SLH-DSA) as ScriptWord-compilable verifiers, following Rúnar's approach. Strategic optionality, not immediate priority.

---

## 7. Summary

The shell has grown into the instruction layer we described. The compression gradient is explicit, Lisp-to-opcode is live, the capability opcodes are proven in Lean, L0/L1/L2 governance is committed, AFFINE-draft-until-ratified discipline is enforced on inferred grammars, CDM and SCADA domain packages are in place, and the Pyramid UI is a thin client on `route()`. The architecture is genuinely powerful in a way that is not just "better tooling" — it is a governed semantic execution substrate that can grow its own vocabulary under human oversight, with formal guarantees at the base, and no existing system combines inferred-grammar induction with governed promotion with opcode-level enforcement in quite this way.

The gap between "could be" and "is" is sequencing, not scope. Land Phase 38A together with the manifest trust-tier fields in the same PR. Run the V2E demo path (38B/C/G) immediately after. Extract the IR before any new surface grammar is touched, modelled on Rúnar's ANF + canonical JSON + golden-file conformance methodology. Rename `packages/paskian` and install the SCADA hard-block before the continuous monitor sees a single sample. Integrate Rúnar as the second frontend to prove the peer-frontend architecture. Add LaTeX, Lean-ish, Ricardian, EDI against the established IR. Turn `InferenceAgent` into a continuous observation service only when the governance plane is structurally sound enough to handle what it proposes. Add Lean gating on authoritative patches when the field exists to gate against.

The architecture is coherent and the gaps are known. What remains is careful sequencing so that the economic execution layer does not outrun the governance plane that has to authorise it, and so that the IR exists before the frontends that depend on it.
