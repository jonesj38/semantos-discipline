---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/SEMANTOS-DOC-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.335741+00:00
---

# Semantos Documentation Plan

**Status:** Planning draft — output of the first scoping pass.
**Date:** 2026-04-26
**Audience for this doc:** Todd. Not a public artifact.

---

## 0. What this is

Three artifacts, sharing one technical kernel but written for different jobs:

| Artifact | Format | Audience | Job |
|---|---|---|---|
| **Reference Spec** | Versioned `.md` + `.docx`, frozen per release | Implementers, reviewers, regulators | The thing the textbook teaches and the papers cite |
| **Textbook** | Self-hosted GitBook on the Semantos node | Blockchain devs (depth path) + business leaders (intro+demo path) | Teach Semantos as a discipline; show what you can build |
| **Paper Portfolio** | arXiv first, conference targets later | PL theorists, formal-methods, blockchain, NLP | Stake claims, earn citations, recruit collaborators |

The kernel is shared: the same definitions, theorems, and worked examples appear in all three. They diverge only at the prose layer.

---

## 1. Gap analysis: what exists vs what's needed

### 1.1 What's in the codebase that's stronger than the docs imply

| Asset | Where | Status |
|---|---|---|
| 2-PDA cell engine in Zig (~4,900 LOC) | `core/cell-engine/src/` | Built, WASM full (185 KB) and embedded (29 KB) profiles |
| OIR (opcode IR, ANF) — `lower()` + `emit()` | `core/semantos-ir/` | Built, golden-file tested |
| SIR (semantic IR) with seven jural categories + governance | `core/semantos-sir/` | Built, golden-file tested, α-equivalence corpus |
| Lisp surface compiler | `runtime/shell/src/lisp/` | Built, wired |
| Intent pipeline (NL/voice/shell/UI/network → cell) | `runtime/intent/` | 100 tests passing, real Anthropic API integration |
| Lean 4 theorems K1, K2, K3, K4, K5, K7, K8, K9, K10 | `proofs/lean/Semantos/Theorems/` | Mechanized; K1 proves executor-state-machine claims, not just rules |
| 8 Lean lexicons (jural, CDM, circuit, project-mgmt, property-mgmt, risk-assessment, bills-of-lading, control-systems) | `proofs/lean/Semantos/Lexicons/` | Each registers a `Lexicon` instance with header injectivity |
| 9 TLA+ specs (cert revocation, demotion, evidence chain, metering FSM, partition resilience, replay prevention, semantic types, transaction DAG, zone boundary) | `proofs/tla/` | Specs + configs present |
| Plexus integration (BRC-42/43/52/100) | `extensions/`, runtime/ | Live |
| 10+ extension grammars (CDM, SCADA, navigation, metering, etc.) | `extensions/` | Most built |
| Real cells being signed and written end-to-end via shell | Slice 3b complete | Live |

### 1.2 What the existing whitepaper / spec gets right and where they're stale

**Whitepaper v2 (`docs/Semantos-Whitepaper-v2.docx`)** — the voice and core framing carry forward.

| Carry forward | Refresh / cut |
|---|---|
| "DNS for meaning" framing | "Currently in Forth, being ported to Zig" — done; now Zig→WASM |
| Three linearity classes with examples | Vertical taxonomy doesn't reflect actual 8-lexicon set |
| Plexus identity DAG explained | "Production verticals (Trades Bot, BREM Agent, RaaS)" — refresh against current portfolio |
| Three-layer architecture (semantic core / vertical grammar / vertical projections) | No mention of SIR/OIR pipeline (now central) |
| 1KB cell model | No mention of K1–K7 Lean proofs |
| Operationally-boring positioning | No mention of compression gradient as a stated principle |

**Protocol Spec v0.01 (`docs/Semantos-Protocol-Spec-v0.01.docx`)** — wire formats and lifecycle FSMs are still good; the IR and proof story need adding.

| Carry forward | Refresh / add / cut |
|---|---|
| 256-byte header + 1KB cell wire format | Opcode set listed as 0xC0–0xCF; current docs say 0x4C–0xD0 — needs reconciliation |
| Three linearity classes + enforcement | Section 4 (Identity Protocol = Plexus) should be replaced with reference to Plexus spec, not duplication |
| Pipeline phases byte (0x00–0x07) with default linearity | No SIR/OIR layer mentioned |
| 13 kernel macros (0xc0–0xcf) | No K1–K7 invariants stated as theorems |
| BRC suite mapping | No domain governance model (trust/estate/realm) |
| Recovery protocol | No 8-lexicon mention |
| Capability token lifecycle | Missing: HOST_EXEC (0x0B), session-protocol federation (Phase 35A/B) |
| Metered Flow Protocol 8-state FSM | Missing: anchor lifecycle was sketched but Section 6 needs the new BUMP/BEEF Phase 1/2/3 verification ordering documented in PROT v0.01 §3.4 — that one's OK |

### 1.3 Load-bearing technical docs already in `docs/`

Most chapters of the textbook can pull straight from these — they're more detailed and current than the whitepaper.

| Doc | Use as |
|---|---|
| `PIPELINE.md` | Backbone of textbook Part III (compilation pipeline) |
| `SEMANTIC-IR-ARCHITECTURE.md` | Backbone of Part IV (semantic IR + jural categories + governance domains). **Note: §10 is duplicated in the file — fix before we use it as source.** |
| `INTENT-PIPELINE.md` | Backbone of Part V (the universal intent substrate, slices 1–3) |
| `FORMAL-VERIFICATION-STRATEGY.md` | Backbone of Part VI (proofs) and the formal-methods paper |
| `PLATFORM-ARCHITECTURE.md` | Backbone of Part VII (verticals + cross-vertical dispatch). Voice is more business-y than the others — use directly for business-leader chapter intros |
| `EXTENSIONS-VS-TYPES.md` | Backbone of Part II (the four-tier model) |
| `prd/SOVEREIGN-NODE-PLAN.md` | Backbone of Part VIII (Building) — three engineering tracks (ContentStore / Compact NetworkAdapter / one-command installer) that take the substrate from "architecturally capable" to "curl one URL → running web3 OS." Provides the Adapter Matrix (IoT × VPS × Full Node by Storage / Identity / Anchor / Network) and the canonical commercial demo: `curl get.semantos.sh \| sh` produces a sovereign node on a $5 VPS in ≤5 minutes. |
| `prd/WORLD-PROTOCOL.md` | Backbone of chapter 16 (World Host). OTP/Elixir, Region as authoritative shard, WorldEntity = LoomObject + spatial, WorldTick at 20 Hz (≠ MeteringTick), client-side prediction via shared WASM kernel, cross-region 2-phase transfer. "Ready Player One"-class persistent 3D space as a finite delta on existing primitives. |
| `prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md` | Backbone of chapter 17 (the Mesh) and reorganises Part VII (Domains). The six-piece skeleton (Discovery / Formation / Runtime / Broadcast / Transport / Metering Hook) with `StateMachine` plug-in as the only domain-specific piece. **Frame:** every vertical is a state machine over a shared session skeleton — poker is one consumer, CDM lifecycle is another, SCADA is another. |
| `prd/PHASE-35B-NODE-AS-SERVICE.md` | Source for the federation chapter (29) and the commercial-tier table (managed hosting / peer-locator-as-service / NAT-relay). |
| `SHELL.md`, `SHELL-VERBS.md` | Reference appendix + Quickstart chapter |
| `BRANCHING-AND-CI-POLICY.md`, `PUBLISHING.md`, `RESTRUCTURING-PLAN.md` | Internal — not for the book |
| `prd/` and `prds/` | Internal — not for the book |

### 1.4 Things that exist nowhere yet

| Missing | Why we need it | Status |
|---|---|---|
| Single canonical glossary | Terms drift between docs (cell vs object, facet vs hat, capability vs permission, IR vs SIR vs OIR) | **Resolved by `docs/canon/glossary.yml`** (51 entries scaffolded; canonical decisions pending — see §9) |
| Versioning + freeze policy | "Slightly in flux" needs to become "v0.6 frozen, v0.7 in development" | Pending — see §4 |
| Plexus / Semantos boundary doc | Whitepaper conflates them; spec section 4 duplicates Plexus content | **Resolved** (§5: integrated stack under RBS) |
| End-to-end "build a thing in 30 minutes" walkthrough | The promised demo surface; currently scattered across PRDs | Pending — chapter 28 of textbook (kanban) + `docs/canon/examples/kanban-30min.{md,ts}` |
| Runnable example for every chapter | HTDP-style discipline requires this | Pending — `docs/canon/examples/` is the home; one canonical example per multi-chapter arc |

---

## 2. Textbook outline

**Working title:** *Semantos: Booting a Sovereign Node*
**Spine:** the **15-step boot sequence** from the Unification Roadmap §6. The book teaches one layer per boot step. By chapter 25 the reader has booted their own node end-to-end.
**Publication gate:** the boot sequence runs end-to-end under proper BRC enforcement (currently halts at step 9 in production form). When the Unification Matrix completes, the book ships.
**Running example:** the boot sequence itself, plus a kanban-as-adapter (chapter 26) as the "build your first surface" exercise.
**Format:** Self-hosted versioned-md system on the Semantos sovereign node (A4 of the unification matrix — the doc system is itself a Semantos surface). Chapters as published RELEVANT cells, edits as AFFINE patches on an evidence chain. Collapsible "for implementers" boxes for the dual-audience cut. Each chapter ends with: a working program, a Lean snippet (where applicable), and the boot-sequence step that the chapter unlocks.

Each part teaches the layer that one segment of the boot sequence depends on. The book IS the boot sequence, told slowly enough to teach.

### Part I — Why a Sovereign Node (chapters 1–3)

The book that earns its way down to the formal core.

1. **The naming problem.** DNS resolves location, databases record state, blockchains prove existence — none resolves *meaning*. Worked example: two systems with the same data and incompatible semantics. Pulls from Whitepaper §1.
2. **What goes wrong with LLM-driven systems.** The compression-gradient critique. Hallucination is what happens when you skip layers. Worked example: handyman intake gone right and wrong. Pulls from INTENT-PIPELINE.md §"Why this is the core primitive".
3. **The sovereign node, end-to-end.** The 15-step boot sequence as a single picture. By the end of this book, the reader has booted their own. The chapter does NOT explain how anything works yet; it just shows what a fully-booted node does. Voice in, semantic intent out, K1-enforced state transition, capability-gated authority, hash-chained time, recoverable identity, metered economic flow. Pulls from Unification Roadmap §6 + WORLD-PROTOCOL.md.

### Part II — Identity (chapters 4–6) — *Boot steps 1–6*

Root seed, BRC-52 cert, BCA, capability tokens, recovery substrate.

4. **Plexus and the identity DAG.** Root seed via PBKDF2, BRC-42 derivation, BRC-52 certificates, the directed-acyclic identity graph. The Recovery substrate (Plexus Tech §11, §16-§24): zero-knowledge identity reconstruction. **Boot steps 1-3.**
5. **Hats, facets, and capability tokens.** BRC-100 wallet interface. BRC-108 capability tokens as LINEAR semantic resources (consume = revoke). The Capability Domain. The four-tier model (extensions / types / contexts / helm) from EXTENSIONS-VS-TYPES.md. **Boot steps 4-6.**
6. **Domain flags as sovereign boundaries.** uint32 namespace partition (Plexus reserved / extended / client sovereign). Trust / estate / realm / corporate / cooperative governance domains from SEMANTIC-IR-ARCHITECTURE.md §10. The cross-domain agreement pattern.

### Part III — Cells & The Pipeline (chapters 7–11) — *Boot step 7*

The compression gradient as a stack of typed transformations.

7. **Cells, types, linearity.** The 1KB cell model. 256-byte header. LINEAR / AFFINE / RELEVANT with worked examples (consent, drug provenance, credentials). The pipeline-phase byte and its default linearity. Hash-chained state (`prevStateHash`).
8. **Surface to AST.** The Lisp surface. Parsing, `ConstraintExpr`. Why a Lisp first (smallest surface that proves the shape). Worked example: hand-write a constraint, see the AST.
9. **Semantic IR (SIR).** The seven jural categories. Hohfeldian roots. Taxonomy coordinates (what/how/why/where). Governance context (trust class, proof requirement, exec authority, linearity, allowed-emit-ops). Pulls from SEMANTIC-IR-ARCHITECTURE.md.
10. **Opcode IR (OIR), ANF, and emit.** Why ANF. The OIR binding kinds. Lowering rules per jural category. Worked example: trace one program through SIR → OIR → bytes.
11. **The 2-PDA cell engine.** Two stacks, bounded, no loops. Standard Bitcoin Script + Plexus opcodes (0x4C–0xD0). The three-phase verification pipeline (BUMP → BEEF → state envelope). `kernel_set_enforcement(1)`. **Boot step 7 lands here.**

### Part IV — Verification (chapters 12–14) — *Boot step 8*

Why this is provably what it claims.

12. **The K1–K10 invariants.** What each invariant says, what it rules out, where it's enforced in the code. Pulls from FORMAL-VERIFICATION-STRATEGY.md §1.
13. **Lean 4 + TLA+ walkthrough.** Open `LinearityK1.lean`, read the theorems alongside the prose. Show one proof step-by-step. Show one TLA+ spec to make the model-checking distinction. Honest limitations register (Section 10 of FORMAL-VERIFICATION-STRATEGY.md).
14. **The Verifier Sidecar.** How K1–K10 turn into a runtime gate. Three deployment topologies (per-surface in-process, per-node sidecar, edge gateway). BRC-100 enforcement. SPV checks for capability UTXOs. Lexicons as substrate-polymorphic types — Jural as the canonical 40-line example. **Boot step 8.**

### Part V — Adapters & The Mesh (chapters 15–18) — *Boot steps 9–11*

The substrate is mostly invisible until adapters consume it.

15. **The substrate / adapter distinction.** Unification Roadmap §2 read aloud: substrate components are ✓ by construction; adapters are where unification work concentrates. The 9 unification axes (Identity, Storage, Transport, D-sub/lex/form/cap, Time, Recovery, Metering).
16. **World Host and the Region model.** OTP/Elixir region servers. Per-region authoritative state. WORLD-PROTOCOL.md (after I've read it). **Boot step 9.**
17. **The Mesh: IPv6 multicast and the codec port.** Peer discovery via BCA, signed-bundle frames, the codec port from the Prompt 38 split. **Boot step 10.**
18. **Helm/Loom: the convergence surface.** The three-panel React workbench. Where every axis converges into a user surface. Voice as the input modality (placeholder per Roadmap A8). **Boot step 11.**

### Part VI — Time, Recovery & Metering (chapters 19–22) — *Boot steps 12–14*

Hash chains, recovery substrate, payment channels.

19. **Time as a stack of hash chains.** Per-cell, per-region, per-channel (MFP nSequence), per-domain (BKDS monotonic). The branching policy decisions (tree-of-chains vs single-DAG for docs; chain-through vs chain-forks for recurring rules). **Boot step 12.**
20. **Universal Intent and the evidence chain.** One Intent shape, eight producers (NL, voice, shell, UI, host-exec, network, governance, scheduler). Triage (no_intent / proposes / ratifies). Receipts and correlation IDs. The conversation-patch / authoritative-patch distinction. Pulls from INTENT-PIPELINE.md.
21. **Recovery substrate.** PBKDF2 root reconstruction. The recovery payload. Threshold recovery via Shamir Secret Sharing for high-security roots. Multi-party group recovery via bilateral edges. **Boot step 13.**
22. **Metered Flow Protocol.** The 8-state channel FSM. nSequence settlement. HMAC tick proofs. Capability UTXOs as the gate. **Boot step 14.**

### Part VII — Domains (chapters 23–26)

Four chapters, one per most-developed lexicon. Same template each time: the domain's economic problem; its Hohfeldian decomposition; the Lean lexicon code; a runnable demo; what extensions someone might write next. (The remaining four lexicons live in Appendix G, same template.)

23. **Jural** — the canonical lexicon; legal acts as semantic objects.
24. **CDM (derivatives)** — ISDA lifecycle as a state-machine; `extensions/cdm/`.
25. **Property management** — leases, maintenance, dispatch envelopes; PLATFORM-ARCHITECTURE.md.
26. **Control systems / SCADA** — telemetry, interlocks, alarms.

### Part VIII — Building (chapters 27–30)

The "prototype factory" promise made concrete.

27. **Boot a sovereign node.** Walk through all 15 boot steps on the reader's own machine. The canonical demo. Produces a running, federated, recoverable, metered, K1–K10-compliant node. **This is the chapter that ships when the Unification Matrix completes.**
28. **Build your first adapter: kanban in 30 minutes.** Universal worked example. Cards as semantic objects, columns as state machines, comments as patches, audit trail as evidence chain, multi-team boards as faceted visibility. By the end, the reader has a deployable kanban whose audit trail is regulator-grade.
29. **Cross-vertical dispatch and federation.** The dispatch envelope pattern (PM-tradie-tenant-owner case study). Phase 35A/B session protocol, peer locator, WS adapter. When to anchor, when not to.
30. **Compliance posture.** How to point a regulator at the K1–K10 + TLA+ + WASM-hash-on-chain story. Pulls from FORMAL-VERIFICATION-STRATEGY.md §6 + §11.

### Part IX — Verticals and the Grammar Layer (chapters 31–33)

The grammar system that connects external domains to the substrate. Written as of 2026-05-09. Source: `extensions/extraction/`, `core/protocol-types/src/extension-grammar*.ts`, `core/semantos-sir/src/lexicons.ts`, `runtime/intent/src/`.

31. **Extension Grammar.** The two grammar formats (`ExtensionGrammarSpec` for the LLM classifier and `ExtensionGrammar` JSON for the connector), the three-level governance model (L0 platform policy / L1 author config / L2 consumer binding), and how to author a minimum viable grammar from scratch. Boot step: registering a grammar activates a new vertical in the loom.

32. **The Trivium/Quadrivium Intent Reducer.** The seven-pass stepped compiler that closes the seam between LLM extraction output (`taggedFacts[]`) and the canonical `Intent` type. Each pass corresponds to one art of the classical trivium (Grammar → `taxonomy.what`, Logic → `taxonomy.how`, Rhetoric → `TaggedCategory` + `action`) and quadrivium (Arithmetic → value constraints, Geometry → `taxonomy.where`, Music → temporal constraints, Astronomy → `GovernanceContext`). Explains the rejection relay, the retry loop, and the full compression gradient made explicit. Tracking: `docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md`.

33. **Automated Grammar Synthesis.** The five-stage pipeline that generates an `ExtensionGrammar` draft from an API endpoint or Swagger/OpenAPI spec: structure analyzer → Pask TaxonomyMapper → GrammarDiffEngine → GrammarComposer → manifest wrapper. Explains how Pask's interact() propagation replaces name-similarity heuristics with corpus-backed semantic inference. Covers what automation replaces (mechanical scaffolding) and what it does not (governance decisions, transform authorship, novel taxonomy design). Tracking: `docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md`.

### Appendices

- A. Glossary (canonical; supersedes drift across docs)
- B. Opcode reference (full table, both standard and Plexus 0x4C–0xD0)
- C. BRC standards reference (full BRC suite from Plexus Tech §References)
- D. Wire format diagrams (256-byte header, 1KB cell, continuation cells, anchor envelope, signed bundle)
- E. Shell verb reference (from `SHELL-VERBS.md`)
- F. Plexus protocol reference (absorbed from Plexus Technical Requirements v1.3)
- G. Remaining lexicons (project mgmt, risk assessment, bills of lading, circuit commands)
- H. Unification Roadmap snapshot at publication date

**Total:** 33 chapters + 8 appendices.

---

## 3. Paper portfolio

13 papers across three clusters. Most reuse the same kernel (definitions, theorems, IR types). The order below is a recommended publish sequence, not a write order.

**Convention for each one-pager:** *Title* — claim — primary evidence already in repo — target venue/format — status.

### Cluster A — Theory (PL / formal methods)

**A1. Compression Gradients for Deterministic Semantic Execution**
*Claim:* Reliable language-driven execution requires a discipline of progressive entropy reduction through inspectable, verifiable intermediate forms — not direct text-to-action lowering.
*Evidence:* `INTENT-PIPELINE.md`, the live triage pipeline (60 unit tests + live Anthropic API tests), the eight-lexicon corpus.
*Target:* arXiv first; PLDI / OOPSLA / EMNLP industry track.
*Status:* Easiest first paper. Has empirical hooks. Critiques a problem everyone is annoyed by. Recommended first publication.

**A2. Semantos: A Two-IR Architecture for Verifiable Computation**
*Claim:* A semantic IR carrying jural category, taxonomy, identity, and governance — sitting above an opcode IR — admits structural enforcement of governance properties at compile time.
*Evidence:* `core/semantos-sir/`, `core/semantos-ir/`, golden-file α-equivalence corpus, SEMANTIC-IR-ARCHITECTURE.md.
*Target:* POPL / OOPSLA.
*Status:* The "core model" paper. Cites A1 as motivation; A3 as substrate.

**A3. A Bounded 2-PDA Execution Model with Substructural Cell Types**
*Claim:* A two-stack PDA over fixed-size typed cells with linearity classes (LINEAR/AFFINE/RELEVANT) and bounded execution implements a primitive substructural language sufficient for verifiable economic state transitions.
*Evidence:* `core/cell-engine/` (Zig source + WASM artifacts), Lean K1, K5 theorems.
*Target:* POPL / TOPLAS.
*Status:* The "machine" paper. Has Lean proofs as evidence.

**A4. History-Indexed Types via Cryptographic Anchoring**
*Claim:* Type validity can depend on cryptographically verifiable state lineage, yielding a discipline stronger than ordered types: types whose correctness depends on provable history.
*Evidence:* Anchor cell design, hash-chain state envelope, Lean K6 (model-checked) + TLA+ EvidenceChain.
*Target:* POPL / TYPES workshop.
*Status:* The "big swing." Less mechanized than A2/A3 today; needs more Lean for full publishability.

### Cluster B — Formal Methods (mechanized verification)

**B1. Mechanized Kernel Invariants for a Verifiable Execution Substrate**
*Claim:* The execution invariants K1–K5, K7 of a 2-PDA semantic kernel are mechanically provable in Lean 4. Distributed protocol invariants K6 + replay/revocation/partition properties are model-checkable in TLA+.
*Evidence:* `proofs/lean/Semantos/Theorems/`, `proofs/tla/`, FORMAL-VERIFICATION-STRATEGY.md.
*Target:* CAV / ITP / TACAS.
*Status:* Real work; needs the proofs cleaned up for publication. The "we did it" paper.

**B2. Lexicons as Substrate-Polymorphic Types**
*Claim:* Domain vocabularies can be encoded as Lean lexicons over a generic substrate, with substrate-level theorems (M1–M4, D1–D3, renderCard correctness) automatically applying to every concrete lexicon by specialisation.
*Evidence:* The 8 lexicon files; the `Lexicon` typeclass in `proofs/lean/Semantos/Substrate/`; the per-lexicon obligations.
*Target:* Lean Together / CPP / TYPES.
*Status:* Methodology paper. Strong if framed as "scale up domain modelling without per-domain proof effort."

### Cluster C — Applied (blockchain + industry)

**C1. UTXO Systems as Substructural Execution Environments**
*Claim:* UTXO-based blockchains already implement a constrained linear-resource model; Semantos generalises this, treating Bitcoin Script as the primitive substrate of a richer typed semantics.
*Evidence:* BRC-43 mapping, custom opcode range 0xC0–0xCF, on-chain anchor protocol.
*Target:* Financial Crypto / IEEE S&P.
*Status:* The "blockchain bridge" paper. Easy to write because the mapping is concrete.

**C2. Identity-Linked Capability Tokens with Auditable Recovery**
*Claim:* BRC-108 capability tokens combined with a deterministic recovery substrate (Plexus) provide non-custodial sovereignty without sacrificing recoverability. Threshold recovery via Shamir Secret Sharing protects high-security roots and capabilities without single-point-of-failure exposure.
*Evidence:* Plexus client + technical requirements docs (RBS IP, Dusk-implemented), recovery protocol §4.4, threshold recovery §9, BRC-108 token format.
*Target:* Financial Crypto.
*Status:* RBS-authored. Dusk engineers invited as co-authors for engineering credit (not IP necessity).

**C3. Compliance by Architecture: An Auditable Substrate for Regulated Computation**
*Claim:* The mapping from kernel invariants to regulatory requirements (IEC 62443, EU AI Act, GDPR, Basel III/IV, HIPAA, NIS2) yields a fundamentally different posture from "compliance by control."
*Evidence:* FORMAL-VERIFICATION-STRATEGY.md §6 (full mapping table), 240+ conformance tests.
*Target:* Industry venues (RSA Conference, FIRST, Black Hat) for talks; ACM CCS workshop for paper.
*Status:* High commercial value. Needs an enterprise reviewer pass.

**C4. The Dispatch Envelope: Cross-Domain Semantic Objects with Faceted Visibility**
*Claim:* A semantic object with per-facet RELEVANT/AFFINE patches enables auditable cross-organisational workflows without point-to-point integration.
*Evidence:* `PLATFORM-ARCHITECTURE.md`, `channelService.ts`, `policyEvaluator.ts`.
*Target:* CSCW / ICSE-SEIP / industry track.
*Status:* The "this is actually useful for organisations" paper.

**C5. CDM Lifecycle as Semantic Objects**
*Claim:* The ISDA Common Domain Model's lifecycle events map cleanly onto the seven jural categories; on-chain settlement of CDM events is implementable today.
*Evidence:* `extensions/cdm/`, the CDM lexicon, the regulatory reporting pipeline.
*Target:* Capital Markets Industry Forum, Journal of Financial Market Infrastructures.
*Status:* The "derivatives industry" paper. Probably co-authored with someone in capital markets.

**C6. BREM: A Structural-Process-Persistence Model of Distributed System Failure**
*Claim:* (You have this dataset already.) Most distributed system failures fall into a small structural taxonomy; Semantos's substructural discipline addresses the highest-impact classes.
*Evidence:* The BREM dataset; `extensions/cdm/risk-assessment/`; the risk-assessment lexicon.
*Target:* DSN / SOSP / industry analytics.
*Status:* You said this was a "commercial wedge"; it's also a credible research paper.

**C7. Single-Substrate Computing Across Three Scales**
*Claim:* The same Zig/WASM kernel — 29 KB embedded, 185 KB full — runs unmodified across embedded (esp32-class microcontrollers), VPS-tier sovereign nodes, and federated full nodes. Four pluggable adapter axes (Storage / Identity / Anchor / Network) span the entire matrix. This is a structural argument that there is no "edge vs cloud" duality at the protocol layer.
*Evidence:* `core/cell-engine/` two profiles, `esp32-hackkit/`, `SOVEREIGN-NODE-PLAN.md`, the running World Host adapter.
*Target:* OSDI / SoCC / EdgeSys.
*Status:* Architecture paper. The "single substrate" claim is genuinely novel relative to most current edge / fog / cloud work.

**C8. Persistent Multi-User Worlds on a Substructural Substrate**
*Claim:* "Ready Player One"-class persistent 3D shared spaces are implementable as a finite delta on a substructural cell engine + an OTP authoritative-region runtime + client-side WASM prediction. Substructural types remove continuous drift and make conflict resolution discrete — no CRDTs, no partial-credit merges.
*Evidence:* `WORLD-PROTOCOL.md`, `apps/world-host` (Elixir), `apps/world-client` (three.js + WASM), Lean K1.
*Target:* SIGGRAPH / NetGames / IEEE Multimedia.
*Status:* Highly publishable; would resonate with the metaverse research community. Could be a talk before a paper.

### Cluster D — Pedagogy / book-as-paper

**D1. Teaching Verifiable Semantic Computation: A Discipline-First Curriculum**
*Claim:* The textbook itself, summarised. Useful for SIGCSE-adjacent audiences and for talks pitching the educational angle.
*Status:* Write only after the textbook is half-drafted.

---

## 4. Versioning and freeze policy (proposal)

**The Unification Roadmap is the canonical state-of-the-build doc.** Every version cut should reference the Matrix snapshot it pinned to. The textbook ships when the Matrix is ✓ end-to-end (boot sequence runs under proper BRC enforcement).

The protocol is "slightly in flux." We need a discipline.

### Three layers, three policies

| Layer | What's in it | Versioning | Freeze cadence |
|---|---|---|---|
| **Kernel** (frozen) | 2-PDA structure, three linearity classes, K1–K10 invariants, IR pipeline shape, BRC suite mapping | SemVer; breaking changes are major bumps and require Lean re-proof | Frozen as `Kernel v1.0` once K6 model-check is stable |
| **Protocol** (stable) | Opcode set, capability token format, anchor envelope, transfer record, recovery export | SemVer with a `CHANGELOG.md`; minor for additions, major for breaking | Cut a `Protocol v0.6` (or whatever current is) immediately. Cadence: every 2-3 months until v1.0 |
| **Frontier** (exploratory) | New lexicons, new domains, new dimensions of substrate projection | "Workshop release" tags, dated; no SemVer guarantee | Released when interesting; nothing else pins to it |

### Concrete actions

1. Cut `protocol-v0.5.md` from current state of the live spec docs. Date it. Tag it in git.
2. Add a `CHANGELOG.md` at `docs/spec/CHANGELOG.md` that records every protocol change going forward.
3. Textbook front matter pins to a protocol version. Bump the textbook version when the protocol bumps.
4. Papers cite the protocol version they were written against in the references section.
5. Frontier work lives under `docs/frontier/` with dated filenames, never referenced normatively by spec or textbook.

---

## 5. The Plexus boundary (resolved)

**RBS owns Plexus 70%; Dusk Inc built it for 30% sweat equity plus business support.** The Plexus PDFs in Dusk's branding are work-for-hire deliverables produced by the dev shop on behalf of the IP owner. Plexus IP is majority RBS-owned.

Implication: **the boundary collapses.** The integrated stack — naming system + identity substrate + execution kernel + IR pipeline + lexicons + verticals — is one product, documented as one product, under RBS.

What this means concretely:

- **Textbook**: Plexus is covered in full. Chapter 5 (identity, hats, capabilities) is a real chapter, not a cross-reference stub. Appendix F documents the Plexus protocol in full.
- **Reference Spec**: The Semantos spec absorbs the Plexus protocol as a normative section. Section 4 of the existing v0.01 spec doesn't get cut — it gets *expanded* using the more detailed v1.3 technical requirements PDF as source material.
- **Papers**: RBS is sole or lead author on every paper in the portfolio. C2 (identity-linked capability tokens with auditable recovery) is no longer "joint required." It's RBS-authored, with Dusk team members invited as co-authors *as a goodwill / engineering-credit gesture* rather than an IP necessity.
- **Lean libraries**: The Plexus-related theorems (K2 authorisation, BRC-42 derivation lemmas) live in `proofs/lean/Semantos/` like everything else. No separate library.
- **Voice**: The textbook can say "Plexus" the same way SICP says "Scheme" — the substrate this book teaches you to use, presented as part of the integrated whole. No tip-toeing.

**Outstanding courtesy items (not blockers):**
- Engineering attribution: Dusk team members named in acknowledgements / contributor list of the textbook and on relevant technical paper bylines if they want it.
- A short "Plexus was implemented by Dusk Inc on behalf of Real Blockchain Solutions" line in the protocol spec colophon.
- Heads-up to Dusk before any public publication about Plexus components, even though we don't need their permission. Reasonable partnership hygiene.

**One useful upshot:** the Plexus technical requirements PDF (v1.3) is your *most current* protocol-level source for the identity substrate. It supersedes Protocol Spec v0.01 §4 for that surface. We should pull from it directly when refreshing the spec.

---

## 6. What to do first (suggested sequence)

The Unification Roadmap pins documentation to engineering reality. Documentation work that *races ahead* of the Matrix risks shipping prose for a node that doesn't yet boot. Documentation work that *trails* the Matrix wastes weeks once the engineering completes. The plan below interleaves them.

### Week 1 — decisions and freeze

This is the human-only critical path: the four half-day items below unblock ~6 months of agent-drivable execution. None are content; all are decisions that, once made, propagate mechanically through the canon-driven render pipeline (§9).

1. ~~Decide the Plexus boundary~~ — resolved (§5: integrated stack under RBS).
2. ~~Glossary scaffold~~ — landed (`docs/canon/glossary.yml`, 51 entries, PR #189). **Next:** the canonical-decision sit-down — for each glossary entry, pick one alias as the canonical, fill `definition:`, write a one-line `notes:` recording the rationale. Without this, every chapter agent has to guess. Half a day.
3. Cut `protocol-v0.5.md` from current docs, *absorbing* the Plexus technical requirements v1.3 content into a unified identity section. Tag it; reference the Unification Matrix snapshot it was cut against. Half a day, with the canon machinery in place.
4. Resolve the five governance questions in Unification Roadmap §8 (verifier topology default, namespace partition policy, document-branching semantics, recurring-rule policy, world-host-as-named-component decision). Half a day. Decisions, not text.
5. Whitepaper v3 outline / draft red-pen pass. Half a day. (v3 draft now exists at `docs/Semantos-Whitepaper-v3-DRAFT.md`; one final pass before going public.)
6. Fix the duplicated §10 in `SEMANTIC-IR-ARCHITECTURE.md`. Trivial.
7. Send Dusk a heads-up email re: engineering credits on the textbook + paper bylines.

### Weeks 2–3 — refreshed whitepaper (sovereign-node frame)

The whitepaper v3 outline (§8 below) made concrete. New frame, boot-sequence as the mechanism, Unification Matrix as the roadmap. Marketing-grade prose. Ships as a `.docx` + a published cell on the sovereign node once A4 (Md Editor) gets to ⚠ status. **This is the lead-magnet artifact** and the thing that makes Semantos legible to the people Todd needs to convince before the textbook lands.

### Weeks 4–6 — paper A1 (compression gradient)

arXiv-targeted. Drafts from the SIR architecture doc, the Intent Pipeline doc, and the live Anthropic API integration evidence. Keeps the technical claim crisp and gives us our first citable artifact.

### Weeks 7–10 — textbook spine, Parts I–IV

Chapters 1–14: from "why a sovereign node" through verification. Voice: refreshed-whitepaper voice extended. Each chapter ends in a working program. Published incrementally on the Md Editor surface as it matures (A4 of the Matrix).

### Weeks 11–14 — papers A2 + A3 in parallel with textbook Parts V–VI

A2 (two-IR architecture) and A3 (bounded 2-PDA) draft from the textbook chapters that exist by then. Textbook chapters 15–22 (adapters / mesh / time / recovery / metering) draft alongside. By end of Q3, three arXiv papers live and 22 textbook chapters drafted.

### Quarter 4 — domain chapters + broader paper portfolio

Textbook chapters 23–26 (the four most-developed lexicons). Papers B1 (mechanized invariants) and C1 (UTXO bridge). C3 (compliance by architecture) drafted but held for an enterprise reviewer pass.

### Publication trigger — when the Unification Matrix completes

Chapter 27 (boot a sovereign node) and chapter 28 (build your first adapter) ship the moment the Matrix is ✓ end-to-end. The textbook 1.0 release is timed to the boot-sequence-runs-under-proper-BRC-enforcement milestone, not the calendar. C2 (joint paper with engineering credits to Dusk) ships shortly after.

### Year 2 — verticals + paper portfolio fill

C4 (dispatch envelope), C5 (CDM), C6 (BREM). Remaining lexicon work in Appendix G. D1 (pedagogy paper) drafted from the published textbook.

---

## 7. Open questions for the next round

1. ~~Plexus boundary~~ — resolved (§5).
2. ~~First deliverable~~ — resolved (refreshed whitepaper, then A1).
3. ~~Canonical worked example~~ — resolved (boot sequence as primary; kanban as "build your first adapter" in chapter 28).
4. **WORLD-PROTOCOL.md and the sovereign-node PRD** — I haven't read them. Should I read them next, or do you want to summarise the bits relevant to the whitepaper? Especially: what's the sovereign-node PRD path (`docs/prd/SOVEREIGN-NODE-NORTH-STAR.md` is mentioned as forthcoming — does it exist yet, or do I outline the whitepaper without it?).
5. **Textbook publication model** — fully open / source available, paywalled, or lead-magnet for RBS engagements? Affects A4 (Md Editor) requirements.
6. **Voice constraints** — anything off-limits? (e.g. competitors, commercial customers, claims about production-readiness for things still in slices)

## 8. Refreshed whitepaper v3 — outline

Working title: *Semantos: A Sovereign Node from Voice to Economic Execution*
Length target: 25–30 pages, prose-led with diagrams and one boxed worked example.
Audience: blockchain devs (will read whole thing), business leaders (will read intro + §3 + §6 + conclusion), regulators (will read §5 + §6).
Voice: Whitepaper v2 carried forward — "operationally boring," precise, declarative. Replace "DNS for meaning" with "voice to economic execution" as the headline, but keep the DNS analogy as a paragraph.

| § | Working title | Pulls from | What it does |
|---|---|---|---|
| 0 | Abstract (1 p) | new | One paragraph: claim + mechanism + state-of-the-art |
| 1 | The naming problem | Whitepaper v2 §1 | Refreshed: same critique, slight repositioning toward voice/AI execution |
| 2 | The sovereign node | new + Unification Roadmap §6 | The 15-step boot sequence as a single picture. Voice in, economic effect out, one cryptographic substrate. **The headline figure of the paper.** |
| 3 | The substrate | Whitepaper v2 §2 + Plexus Tech §1 | The 10 substrate components (cell engine, Plexus core, identity, capability domain, verifier sidecar, mesh, VFS, SIR, Lean, MFP) and what each enforces |
| 4 | The pipeline | PIPELINE.md + SEMANTIC-IR-ARCHITECTURE.md | Lisp → SIR → OIR → opcodes → 2-PDA. The compression gradient. Seven jural categories. |
| 5 | Verification | FORMAL-VERIFICATION-STRATEGY.md (compressed to ~3 pages) | K1–K10 + TLA+ + WASM-hash anchoring. The compliance-by-architecture posture. Honest limitations register. |
| 6 | Adapters and verticals | PLATFORM-ARCHITECTURE.md + Unification §2b | The 8 adapter surfaces. The dispatch envelope pattern. How an extension becomes a vertical. |
| 7 | Where this is going | Unification Roadmap §4 + §6 | Phased completion of the matrix. Boot-sequence end-to-end as the success metric. |
| 8 | Conclusion (1 p) | new | The substrate is not a blockchain project; it is the foundation a thousand sovereign nodes will run on. |

**Two worked examples, both threaded through.**

1. **The commercial demo:** `curl -fsSL https://get.semantos.sh | sh` on a fresh $5 VPS produces a sovereign node in ≤5 minutes. Identity issued, wallet created, storage / messaging / wallet / headers wired, healthz green. *This is the picture readers carry away.* It's the M3 milestone of the Sovereign Node Plan; the whitepaper claims it as the production reality of the boot sequence.

2. **The user-facing scenario, threaded through:** an avatar in a World Host Region (3D space) reports a problem via voice, the dispatch envelope flows out to a tradie's flat 2D inbox, the work is done, payment settles on-chain via MFP. Shows voice-in / economic-effect-out across multiple adapter surfaces simultaneously. Lands harder than a bare chat-bot example for the audiences Todd is after, and every primitive (BRC-52 cert, K1 enforcement, signed bundle, dispatch envelope, hash chain, MFP tick) appears in service of the same story.

**Diagrams required:**
- **The Adapter Matrix** (IoT × VPS × Full Node × {Storage, Identity, Anchor, Network}). One picture explains the whole product strategy: same kernel, three deployment scales. Lifted from `SOVEREIGN-NODE-PLAN.md`.
- **The 15-step boot sequence** (one big figure, with the curl-one-URL annotation showing where steps 1-14 collapse into a single command).
- **Substrate / adapter layered architecture** with all 10 substrate components and 8 named adapter surfaces.
- **The six-piece session-protocol skeleton** (Discovery / Formation / Runtime / Broadcast / Transport / Metering Hook) with `StateMachine` plug-in.
- **The compression gradient** (NL → effect, with byte counts at each layer).
- **The Unification Matrix snapshot** at publication date.
- **The cell wire format** (256-byte header + 1KB cells).

**What this whitepaper deliberately does NOT do:**
- Replace the textbook (not a teaching artifact)
- Cite specific conference venues (it's marketing-grade, not academic)
- Make production-readiness claims about anything past boot-sequence step 7
- Pre-announce commercial customers
- Compare to other blockchain projects by name

I'd want a green light on this outline before drafting the prose. Once green-lit, ~2 weeks to a tight first draft.

---

## 9. The canon as source of truth

The whitepaper, textbook, spec, and paper portfolio share one technical kernel. As of PR #189 that sharing is *literal*: structured-data files under `docs/canon/` that every artifact hydrates from. Drift goes to zero, status changes propagate, and agents drafting prose work from a closed input set rather than "go read 8 PRDs and synthesise."

### 9.1 Layout

```
docs/canon/
├── README.md              # full schema documentation + production workflow
├── glossary.yml           # canonical terms (51 entries scaffolded; canonical decisions pending)
├── theorems.yml           # K1–K10 statements + Lean file refs + status
├── opcodes.yml            # full opcode table, sourced from cell-engine zig
├── boot-sequence.yml      # the 15 steps, each annotated with matrix cells it depends on
├── adapter-matrix.yml     # IoT × VPS × Full Node × {Storage, Identity, Anchor, Network}
├── unification-matrix.yml # live status of every (surface, axis) cell
├── deliverables.yml       # D-V1, D-A0, D-Dsub-md... structured (id, owner, deps, status)
├── lexicons.yml           # 8 lexicons + Lean refs + dev status
├── brc-mapping.yml        # BRC-42/52/100/108/etc → repo location + spec section
├── examples/              # the worked examples, reused across artifacts
│   ├── handyman-intake.{md,ts}      # ch 2 + paper A1
│   ├── boot-sovereign-node.{md,sh}  # ch 27 (the canonical demo)
│   ├── kanban-30min.{md,ts}         # ch 28
│   └── pm-tradie-dispatch.{md,ts}   # ch 29 + paper C4
└── render/                # tooling that turns canon → textbook MD / spec MD / paper LaTeX
    ├── glossary-to-md.ts   ✓ landed
    ├── matrix-to-roadmap.ts ✓ landed
    └── opcodes-to-spec.ts   pending
```

Both renderers run today against the (mostly-empty) canon and emit sensible placeholders. The pipeline is provable now; what's left is to fill the YAML and add the per-artifact templates.

### 9.2 Three downstream consequences

1. **Textbook chapters become composition.** Chapter 5 ("Hats, facets, and capability tokens") is `chapter-template.md` + the rendered subset of `glossary.yml` for the relevant terms + `brc-mapping.yml` filtered to BRC-100 / BRC-108 + `boot-sequence.yml` step 5 + the relevant slice of `examples/kanban-30min.ts`. An agent drafting it has a closed input set, not "read everything in `docs/`."
2. **Spec freeze becomes mechanical.** `protocol-v0.5.md` is a render output with the canon snapshot's git SHA in its frontmatter. Re-cut by re-running the render against a tagged canon revision.
3. **The unification matrix becomes live state.** `docs/canon/unification-matrix.yml` updates per-PR; CI re-renders the matrix in `docs/prd/SEMANTOS-UNIFICATION-ROADMAP.md`. PRs cite deliverable ids (`D-A1`, `D-Dsub-md`, etc.) in commit messages; a CI hook flips the cell.

### 9.3 The agent draft-brief template

Every chapter and paper draft is commissioned with a brief of this shape. The closed input set prevents the "agent reads everything, hallucinates connections" failure mode.

```
ARTIFACT:        textbook chapter 5  (or paper A1, or spec section 4, etc.)
TITLE:           Hats, facets, and capability tokens
TARGET LENGTH:   4,500 words
VOICE:           Whitepaper v2 — operationally boring, declarative.

INPUTS (closed set):
  - docs/canon/glossary.yml § entries: {hat, facet, cert_id, capability_token, ...}
  - docs/canon/brc-mapping.yml § BRC-100, BRC-108
  - docs/canon/boot-sequence.yml § steps 4–6
  - docs/PLATFORM-ARCHITECTURE.md § "Hats and Facets"
  - docs/canon/examples/kanban-30min.{md,ts} § lines 120–180

MUST-CITE:       K2, K7
ENDS IN:         a working program (extract from canon/examples/kanban-30min.ts:Section3)
                 + a Lean snippet (proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean)
                 + boot-sequence step the chapter unlocks (5)

DELIVERABLE:     docs/textbook/05-hats-facets-capabilities.md
PR BASE:         main
PR BRANCH:       feat/textbook-ch05
```

Agents draft in parallel; a single human voice/coherence pass at the end is the only sequential step in the textbook execution.

### 9.4 What parallelises, what doesn't

| Highly parallel (agents) | Sequential / human-only |
|---|---|
| Chapter drafts 1–30, each its own PR | Voice consistency editing across drafts |
| Paper A1–C8 first drafts | Glossary canonical decisions (one term, one entry) |
| Per-deliverable matrix work (D-V1, D-A1, …) — proven workflow | The five governance questions in Unification Roadmap §8 |
| Per-lexicon appendix G entries | Whitepaper final voice pass — single voice, not parallelisable |
| Per-BRC reference appendix C entries | Decision: textbook publication model (open / paywalled / lead-magnet) |

The Unification Matrix has 70+ deliverables. They cluster naturally — Phase 1b is 7 surfaces × axis A, six of which parallelise. Phase 3 has 4 sub-axes × ~5 surfaces each. Same shape as the parallel agent waves already proven on the monolith refactor.

### 9.5 Workflow shift

Going forward:
- **PR descriptions cite canon ids** (`cell`, `hat`, `bca`, etc.) for stable cross-doc references — even before the canonical-decision pass lands. The 51 ids in the glossary are the stable handle set the rest of the docs can use today.
- **New terms get added to `glossary.yml` first**, then used. Variants accumulate as `aliases:`; canonical-decision pass picks one.
- **New deliverables go into `deliverables.yml`** with structured `(id, owner, deps, status)`. The matrix YAML references them.
- **Worked examples go into `docs/canon/examples/`** as `(md, ts)` pairs — prose for humans, code that compiles for the test suite. One example per multi-chapter arc.

---

*End of plan. The next move is yours: either pick from the open questions, or tell me which artifact (textbook chapter, paper draft, refreshed whitepaper, glossary) you want me to start producing.*
