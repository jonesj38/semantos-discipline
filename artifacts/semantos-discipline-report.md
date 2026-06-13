# Semantos Discipline Report

**Published artifact path:**  
`/home/jake/.edwinpai/disciplines/semantos/artifacts/semantos-discipline-report.md`

**Publication status:** Written with explicit approval from the assembling task.

**Evidence scope:** Semantos vault context only, primarily the Semantos core repository documentation and planning artifacts surfaced from the `semantos-discipline` collection.

---

## 1. Executive Summary

Semantos is described as a sovereign semantic execution substrate: a deployable node that accepts ambiguous human input, such as voice or natural language, and transforms it through typed, inspectable, cryptographically anchored layers before any economic or operational effect occurs. Its stated gap is that DNS resolves location, databases record state, and blockchains prove existence, but none of them resolve meaning. Semantos positions the missing primitive as “a typed semantic object with provable identity, linearity-constrained consumption, a cryptographic evidence chain, and a verifiable lineage from intent to effect.” [Semantos-Whitepaper-v3-DRAFT.md]

The discipline around Semantos is not just a protocol description. It is a structured engineering and verification practice spanning:

- fixed-size semantic cells;
- linearity classes and consumption rules;
- SIR / OIR compilation layers;
- a bounded Zig/WASM 2-PDA execution kernel;
- identity and capability gating through Plexus / BRC protocols;
- Lean and TLA+ verification;
- Paskian cognition and stability kernels;
- multi-tier storage and event infrastructure;
- documentation, textbook, and paper artifacts sharing one canonical technical kernel. [SEMANTOS-DOC-PLAN.md; Semantos-Whitepaper-v3-DRAFT.md; SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md; cognition-implementation-plan.md]

At a discipline level, Semantos’ central rule is: do not jump from language to action. Every executable action must pass through a recoverable compression gradient from surface intent to semantic representation to opcode-level execution, preserving enough evidence that the system can explain, verify, refuse, or ratify the transition. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md; Semantos-Whitepaper-v3-DRAFT.md]

---

## 2. Scope and Source Basis

This report is grounded in the provided Semantos vault context and the surfaced source documents:

1. `docs/Semantos-Whitepaper-v3-DRAFT.md` — public-facing architectural statement and sovereign-node framing.
2. `docs/SEMANTOS-DOC-PLAN.md` — internal documentation plan, textbook outline, gap analysis, and canonical artifact strategy.
3. `docs/canon/glossary.yml` — canonical terminology and decision principles.
4. `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` — implementation pipeline, invariants, DB topology, and milestone structure.
5. `research/cognition-implementation-plan.md` — Paskian cognition implementation plan, event spine, TDD work items, and multiparticipant agreement experiment.

No external sources are used.

---

## 3. Core Concept: Semantos as a Sovereign Node

The whitepaper defines Semantos as “a sovereign node — a single deployable substrate that takes voice in, produces cryptographically anchored economic effect out, and proves every step in between.” [Semantos-Whitepaper-v3-DRAFT.md]

The sovereign-node claim is made concrete through a 15-step boot sequence. The sequence begins with user identity creation and BRC-52 certificate derivation, proceeds through capability minting, cell-engine boot, verifier-sidecar startup, mesh participation, adapter subscription, recovery backup, and metered service activation, and ends with the user “online, sovereign, federated.” [Semantos-Whitepaper-v3-DRAFT.md]

The target installer experience is intentionally operationally simple:

```sh
curl -fsSL https://get.semantos.sh | sh
```

The stated M3 criterion is that this command should produce a running Semantos node on a clean Ubuntu 22.04 $5-tier VPS in five minutes or less, including a BRC-100 wallet, BRC-52 identity certificate, optional DNS publication, and a healthy node URL. [Semantos-Whitepaper-v3-DRAFT.md]

The discipline implication is that Semantos treats deployment, identity, execution, verification, storage, recovery, federation, and metering as one coherent substrate rather than separate application features.

---

## 4. The Naming Problem and Semantic Object Primitive

Semantos’ motivating problem is that existing infrastructure resolves partial truths:

- DNS resolves location, not identity.
- Databases record state, not meaning.
- Blockchains prove existence, not type.
- LLMs can interpret language but can hallucinate or act without a verifiable intermediate form. [Semantos-Whitepaper-v3-DRAFT.md]

The proposed primitive is not a database record, token, transaction, or LLM completion. It is a semantic object with:

- cryptographic identity;
- type enforcement;
- linearity-constrained consumption;
- history anchoring;
- capability gating;
- evidence lineage from intent to effect. [Semantos-Whitepaper-v3-DRAFT.md]

This is the heart of the Semantos discipline: meaning must be represented as a typed, governable, inspectable, and executable object.

---

## 5. Architecture: Substrate, Adapters, and Deployment Scales

The whitepaper distinguishes a substrate from adapters. The substrate consists of ten named components:

1. Cell Engine — Zig/WASM 2-PDA execution and cell packing.
2. Plexus Core / Vendor SDK — identity, recovery, BRC-100 control plane.
3. Identity / Derivation / Recovery — BRC-42 keys, BRC-52 certificates, monotonic indices.
4. Capability Domain — LINEAR BRC-108 UTXO capabilities.
5. Verifier Sidecar — BRC-100 enforcement, certificate authenticity, SPV checks.
6. Mesh — IPv6 multicast over signed bundles, BCA peer ID, heartbeats.
7. VFS / Octaves — content-addressed storage and hash-chained patches.
8. SIR + Lexicons — jural categories, governance context, lexicon-domain types.
9. Lean Proof Layer — mechanized K1–K10 invariants and lexicon substrate proofs.
10. Metering Engine — MFP channel FSM, tick proofs, settlement. [Semantos-Whitepaper-v3-DRAFT.md]

The same kernel is intended to run across three deployment scales:

- IoT / embedded devices;
- edge or VPS nodes;
- federated full nodes. [Semantos-Whitepaper-v3-DRAFT.md]

At each scale, adapters vary across storage, identity, anchor, and network choices, but the protocol substrate remains one system. [Semantos-Whitepaper-v3-DRAFT.md]

The documentation plan reinforces this distinction by treating substrate components as “✓ by construction” and adapters as the place where unification work concentrates. [SEMANTOS-DOC-PLAN.md]

---

## 6. Cells, Linearity, and the Execution Kernel

The execution heart of Semantos is a deterministic, bounded two-stack pushdown automaton implemented in Zig and compiled to WebAssembly. The whitepaper describes it as using a 1024-cell main stack and a 256-cell auxiliary stack, with no loops, no jumps, and execution time proportional to opcount. [Semantos-Whitepaper-v3-DRAFT.md]

Every datum the engine touches is a fixed-size 1024-byte cell with a 256-byte typed header. Header fields include magic bytes, linearity class, version, type hash, owner identifier, timestamp, cell count, payload size, pipeline phase, and hash-chain pointers such as `parentHash` and `prevStateHash`. [Semantos-Whitepaper-v3-DRAFT.md]

The implementation pipeline makes the 1024-byte cell shape a non-negotiable invariant: “1024-byte cell shape (256 hdr + 768 payload)” must be preserved because it affects page geometry and the K5 termination argument. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

Linearity is an economic and semantic constraint, not a metadata hint. The implementation pipeline lists K1 linearity as a core invariant: a LINEAR cell is consumed exactly once. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The whitepaper states that no opcode modifies the linearity class of a cell on the stack, corresponding to invariant K7 cell immutability. [Semantos-Whitepaper-v3-DRAFT.md]

Together, cell shape, linearity, and the 2-PDA kernel form Semantos’ first-order execution discipline.

---

## 7. Compilation Discipline: Compression Gradient from Intent to Bytes

Semantos’ documentation plan frames the technical pipeline as a “compression gradient” — a stack of typed transformations from surface input down to executable bytes. [SEMANTOS-DOC-PLAN.md]

The textbook outline breaks this into chapters:

- Surface to AST;
- Semantic IR / SIR;
- Opcode IR / OIR;
- 2-PDA cell engine. [SEMANTOS-DOC-PLAN.md]

The SIR layer is described as using seven jural categories, Hohfeldian roots, taxonomy coordinates, governance context, proof requirements, execution authority, linearity, and allowed emit operations. [SEMANTOS-DOC-PLAN.md]

The OIR layer uses ANF and lowering rules per jural category before emitting executable bytes. [SEMANTOS-DOC-PLAN.md]

The implementation pipeline hardens this into an invariant: “Compression gradient = teachback.” It states:

- no surface bypasses SIR;
- no runtime SIR interpretation;
- no best-effort lowering;
- every action-phase cell must carry a recoverable explanation chain back to its SIR program. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

This is one of the clearest discipline rules in the corpus: Semantos must not allow direct action from ambiguous input. Action requires a traceable semantic reduction.

---

## 8. Identity, Capability, and Authority

Semantos uses Plexus and BRC protocols as its identity and authority substrate. The sovereign-node boot sequence includes:

- PBKDF2 root seed generation;
- BRC-52 certificate derivation;
- BCA computation;
- BRC-100 wallet initialization;
- capability-domain minting of initial UTXOs. [Semantos-Whitepaper-v3-DRAFT.md]

The documentation plan identifies identity as Part II of the textbook, covering:

- Plexus and the identity DAG;
- BRC-42 derivation;
- BRC-52 certificates;
- BRC-100 wallet interface;
- BRC-108 capability tokens;
- capability tokens as LINEAR semantic resources. [SEMANTOS-DOC-PLAN.md]

The implementation pipeline lists capability and authority boundaries as invariants, including:

- K3 domain isolation;
- BRC-100 enforcement through the verifier sidecar;
- SPV checks for capability UTXOs;
- cell-carried proofs;
- domain flags as governance and isolation boundaries. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The discipline therefore separates semantic proposal from authorized action. Meaning can be represented and reduced, but authority must be capability-gated.

---

## 9. Formal Verification and Runtime Gates

The documentation plan identifies Semantos as having Lean 4 theorems K1, K2, K3, K4, K5, K7, K8, K9, and K10 already mechanized, plus TLA+ specs for revocation, demotion, evidence chains, metering FSMs, partition resilience, replay prevention, semantic types, transaction DAGs, and zone boundaries. [SEMANTOS-DOC-PLAN.md]

The DB implementation pipeline enumerates key invariants:

- K1 linearity;
- K3 domain isolation;
- K4 failure atomicity;
- K5 termination;
- K6 hash-chain integrity;
- K7 cell immutability;
- cell carries its own proof;
- LMDB remains dumb storage;
- Pask determinism;
- existing vtable contracts;
- kernel composition;
- MNCA-as-Pask-federation;
- three-order cybernetic layering;
- compression gradient as teachback. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The reportable discipline here is that verification is not decorative. Verification obligations are attached to implementation gates and storage design. Any deliverable that weakens an invariant must stop and produce a design note rather than silently loosen the system. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

---

## 10. Paskian Cognition and Agreement

The cognition implementation plan extends Semantos beyond first-order execution into second- and third-order cybernetic layers. It defines a plan for observing intent outcomes, stable transitions, analogical encodings, and multiparticipant agreement. [cognition-implementation-plan.md]

The event spine is NATS JetStream, with producers in `runtime/semantos-brain/src/nats_event_producer.zig` and `runtime/semantos-brain/src/nats_client.zig`. Events follow a per-operator subject hierarchy:

```text
op.<op_pkh16>.<hat_id>.<event_type>
```

and a per-operator stream:

```text
op_<op_pkh16>
``` 

[cognition-implementation-plan.md]

The plan defines work items such as:

- `emitIntentOutcome` after intent processing;
- `emitStableTransition` from the Pask stability layer;
- HRR encoding feasibility experiments;
- analogical library construction;
- pragmatic-ranking reducer passes. [cognition-implementation-plan.md]

A central hypothesis is that “a node is agreed-upon when independent Pask kernels subscribed to overlapping streams converge on its stability.” [cognition-implementation-plan.md]

This gives Semantos a cognition discipline: semantic execution is not merely verified at the cell layer, but also observed, compared, stabilized, and eventually federated across kernels.

---

## 11. Storage and Event Topology

The DB implementation pipeline defines a four-tier storage topology over roughly six months:

- LMDB hot path;
- SQLite browser tier;
- Pravega streams;
- Postgres reasoning tier. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

It also states that the topology must slot in behind existing vtable patterns in `*_store_fs.zig`, preserving kernel independence from storage implementation. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

Milestones include:

- M0 baseline;
- M1 LMDB hot path;
- M2 SQLite browser tier;
- M3 Pravega streaming;
- M4 Octave 1+ escalation;
- M5 Postgres reasoning tier;
- M6 Octave registry source of truth;
- M7 federated tier. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The implementation invariants explicitly say “LMDB is dumb storage” and “DB is not the verifier.” [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The discipline implication is that storage can optimize access, indexing, and replay, but must not become an implicit execution or trust layer.

---

## 12. Canonical Terminology and Documentation Discipline

The documentation plan identifies terminology drift as a major gap and records that the canonical glossary resolves it. [SEMANTOS-DOC-PLAN.md]

The glossary itself states decision principles:

1. production code usage is the strongest signal;
2. Whitepaper v3 and paper A1 usage are secondary;
3. conciseness wins ties;
4. established initialisms such as BRC-100, MFP, SIR, and OIR are canonical;
5. CamelCase type names are canonical in code contexts;
6. snake_case identifiers are canonical for wire formats and YAML. [glossary.yml]

The glossary entry for `cartridge` supersedes older distinctions such as app, extension, world-app, and adapter, defining cartridge as the single canonical packaging, ownership, and composition unit with a `cartridge.json` manifest, role classification, typed consumes/provides relationships, and PushDrop license ownership. [glossary.yml]

The documentation plan proposes three artifacts sharing one kernel:

- Reference Spec;
- Textbook;
- Paper Portfolio. [SEMANTOS-DOC-PLAN.md]

The same definitions, theorems, and examples should appear across all three, diverging only at the prose layer. [SEMANTOS-DOC-PLAN.md]

Thus, Semantos’ discipline includes documentation as an executable alignment mechanism: terminology, examples, specifications, proofs, and teaching materials must remain synchronized.

---

## 13. Acceptance and Operational Discipline

Across the source materials, Semantos’ acceptance posture can be summarized as follows:

### 13.1 Execution acceptance

A valid action must pass through the compression gradient and produce a cell-level effect with recoverable explanation lineage. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

### 13.2 Verification acceptance

Core invariants such as linearity, domain isolation, failure atomicity, termination, hash-chain integrity, and cell immutability must remain preserved. If a deliverable requires weakening one, implementation must stop and produce a design note. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

### 13.3 Deployment acceptance

The sovereign node should eventually be installable with a one-command flow that produces a functioning node, wallet, identity certificate, and healthy endpoint in five minutes or less on a $5 VPS. [Semantos-Whitepaper-v3-DRAFT.md]

### 13.4 Documentation acceptance

The Reference Spec, Textbook, and Paper Portfolio must share one technical kernel, with canonical terminology governed by the glossary. [SEMANTOS-DOC-PLAN.md; glossary.yml]

### 13.5 Cognition acceptance

Paskian and analogical layers proceed through falsifiable gates, such as HRR cosine thresholds and event-driven stability convergence. Tier B does not proceed if Tier A measurements fail. [cognition-implementation-plan.md]

---

## 14. Risks, Gaps, and Open Work

The documentation plan records several gaps or refresh needs:

- existing whitepaper/spec material is partly stale relative to the Zig/WASM kernel;
- opcode ranges require reconciliation;
- SIR/OIR layers need fuller integration into older specs;
- K1–K7 or K1–K10 invariants need to be stated clearly in reference materials;
- the canonical glossary was needed to resolve term drift;
- versioning and freeze policy were pending;
- runnable examples for every chapter were pending;
- an end-to-end “build a thing in 30 minutes” walkthrough was pending. [SEMANTOS-DOC-PLAN.md]

The DB implementation pipeline identifies the database work as plan-only and warns not to implement directly from the document without reading companion docs and confirming dependencies. [SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md]

The cognition implementation plan similarly uses staged gates: no Tier B analogical work begins until Tier A measurements validate the encoding assumptions. [cognition-implementation-plan.md]

The discipline therefore treats uncertainty as part of the process: unproven claims must become measurements, gates, or design notes before becoming implementation commitments.

---

## 15. Semantos Discipline Definition

Based on the surfaced corpus, the Semantos discipline can be defined as:

> A practice for building sovereign semantic systems in which human intent is transformed into authorized economic effect only through a typed, inspectable, cryptographically anchored, formally constrained, capability-gated, and replayable pipeline.

Its core commitments are:

1. **Meaning before action** — no direct natural-language-to-execution shortcut.
2. **Typed semantic objects** — every executable object carries type, identity, lineage, and governance context.
3. **Linearity as law** — consumption rules are enforced at the kernel, not left to application convention.
4. **Authority separation** — semantic interpretation does not imply execution authority.
5. **Proof-carrying state** — storage and transport do not replace verification.
6. **Bounded execution** — the kernel remains deterministic, finite, and analyzable.
7. **Canonical terminology** — docs, specs, papers, and code share one vocabulary.
8. **Falsifiable cognition** — learning and agreement layers advance through measurable convergence gates.
9. **Sovereign deployment** — the node runs under operator-owned identity, hardware, and storage.
10. **Documentation as infrastructure** — the reference spec, textbook, and paper portfolio are synchronized expressions of the same kernel. [Semantos-Whitepaper-v3-DRAFT.md; SEMANTOS-DOC-PLAN.md; glossary.yml; SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md; cognition-implementation-plan.md]

---

## 16. Source Matrix

| Topic | Primary source(s) |
|---|---|
| Sovereign node framing | `docs/Semantos-Whitepaper-v3-DRAFT.md` |
| Naming problem | `docs/Semantos-Whitepaper-v3-DRAFT.md` |
| Boot sequence | `docs/Semantos-Whitepaper-v3-DRAFT.md` |
| Substrate components | `docs/Semantos-Whitepaper-v3-DRAFT.md` |
| Cell engine | `docs/Semantos-Whitepaper-v3-DRAFT.md`; `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` |
| Linearity and invariants | `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` |
| SIR / OIR / compression gradient | `docs/SEMANTOS-DOC-PLAN.md`; `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` |
| Identity / BRC / capability model | `docs/Semantos-Whitepaper-v3-DRAFT.md`; `docs/SEMANTOS-DOC-PLAN.md` |
| Verification posture | `docs/SEMANTOS-DOC-PLAN.md`; `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` |
| Paskian cognition | `research/cognition-implementation-plan.md` |
| Storage topology | `docs/prd/SEMANTOS-DB-IMPLEMENTATION-PIPELINE.md` |
| Canonical terminology | `docs/canon/glossary.yml`; `docs/SEMANTOS-DOC-PLAN.md` |
| Documentation artifacts | `docs/SEMANTOS-DOC-PLAN.md` |

---

---

## 17. Completion Note for Future EdwinPAI Agents

**Source coverage:** Covered the Semantos whitepaper draft, documentation plan, canonical glossary, DB implementation pipeline, and cognition implementation plan from the Semantos discipline/vault corpus. Retrieved task context also identified related discipline lifecycle and approval-contract references, but the report content intentionally stays grounded in Semantos source material.

**Verification status:** PASS for assembly constraints: required report sections are present, the target path is exact, no external web evidence was used, and the report is source-grounded with inline source references. Earlier Shad verification marked the contract-first surface as passing and found no implicit writes before this approved publication step.

**Unresolved risks:** Some cited Semantos materials are planning/draft documents rather than final specs; direct quote density is moderate rather than exhaustive; QMD URI-level citations should be preferred if this report is later converted into a machine-verifiable discipline bundle; implementation/proof status should be rechecked against the live repo before agents perform code changes.

**Recommended next steps:**
1. Convert the source matrix into QMD URI citations for runtime retrieval.
2. Add `useWhen` / `avoidWhen` metadata to the discipline manifest.
3. Re-run verification against current Semantos HEAD before code work.
4. Expand the report with exact proof/test file references for TLA+, Lean, fuzzing, and package build surfaces.
5. Keep glossary/canon files as the highest authority when terminology conflicts arise.

