---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-36-EXTENSION-ECOSYSTEM-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.713625+00:00
---

# Phase 36 — Extension Ecosystem: Semantic Extraction, Governance & Marketplace (Master PRD)

**Version**: 1.0
**Date**: April 2026
**Status**: Draft — architecture review
**Duration**: 12–16 weeks (across 6 sub-phases)
**Prerequisites**: Phase 26A–26H complete (four adapter interfaces + extension loading + rename). Phase 30F.2 (CAS storage). Phase 18 (metering control plane). Phase 19 (semantic shell). Phase 20 (VFS).
**Branch prefix**: `phase-36-extension-ecosystem`

---

## Context

Semantos has a kernel (cell engine, linearity, capability validation), a type system (256-byte cell headers, WHAT/HOW/WHY taxonomy), a shell (typed grammar, VFS, REPL), a loom (React UI), identity (Plexus facets), governance (ballots, disputes, constitutions), metering (payment channels), and storage adapters (NodeFs, Memory, Overlay, BSV). What it does not yet have is a **generalised connector framework** that can wire up arbitrary external systems — PropertyMe, Jira, GitHub, kanban boards, SCADA historians, ISDA trade repositories, git repos — and extract their data into semantic objects through a uniform pipeline.

Phases 28 (ISDA CDM), 29 (SCADA), 32 (Bills of Lading), and 35 (Music Production) each define domain-specific type mappings. But each one hand-crafts its own extraction logic. This phase extracts the *pattern itself* into a reusable framework: a declarative Extension Grammar JSON schema, a staged extraction pipeline, an inference agent that can propose new grammars from unfamiliar APIs, and a governance model that enables both Semantos-governed first-party extensions and autonomously-governed third-party extensions.

### The Commercial Imperative

The Semantos node ships as a $500 product. Extensions are the recurring revenue and ecosystem growth mechanism:

- **First-party extensions** (PropertyMe, Trades, Dispatch Envelope) — sold on the marketplace, governed by Semantos
- **Third-party extensions** — built by developers, sold or open-sourced, governed by their authors within platform constraints
- **Enterprise extensions** — custom connectors for internal systems (SAP, Salesforce, internal APIs), governed by the enterprise

The extension ecosystem needs three things to work:

1. **A standard contract** — the Extension Grammar JSON schema that every connector must implement
2. **A standard pipeline** — fetch → parse → typecheck → infer → commit, shared across all connectors
3. **A standard governance model** — hierarchical step-down where Semantos governs the meta-schema, extension authors govern their schemas, and consumers configure their bindings

### Why Hierarchical Step-Down Governance

Flat governance doesn't work for marketplaces. If Semantos governs everything, third-party developers have no autonomy and won't build. If extension authors govern everything, there's no quality floor and the ecosystem degrades. The solution is hierarchical:

- **Level 0 (Kernel)**: Semantos governs the Extension Grammar meta-schema, the extraction pipeline contract, capability requirements, and platform safety policies. Changes here require a formal governance process (Constitution-type RELEVANT object with ballot).
- **Level 1 (Extension Author)**: Each extension author governs their grammar's evolution — field mappings, object types, taxonomy coordinates, versioning strategy. They can accept community patches, run their own ballots, set their own linearity rules for schema objects.
- **Level 2 (Consumer Binding)**: Each consumer who installs an extension can configure local bindings — API credentials, field overrides, custom taxonomy mappings, version pinning. Bindings are AFFINE objects scoped to the consumer's node.

Constraints flow downward: the meta-schema constrains what grammars can declare; grammars constrain what bindings can override. Disputes flow upward: consumers can dispute grammar changes; authors can dispute meta-schema changes.

---

## Sub-Phase Overview

| Phase | Name | Duration | What It Builds |
|-------|------|----------|----------------|
| 36A | Extension Grammar Schema | 2 weeks | The JSON meta-schema every connector must implement. Declares source entities, field mappings, taxonomy coordinates, capability requirements, versioning. |
| 36B | Semantic Extraction Pipeline | 3 weeks | The five-stage pipeline (fetch → parse → typecheck → infer → commit). Storage-adapter-agnostic. Extension-grammar-driven. Evidence-chained. |
| 36C | Schema Inference Agent | 2 weeks | Agent that reads unfamiliar API responses, diffs against known grammars, proposes new Extension Grammar JSON as AFFINE draft objects. |
| 36D | Extension Governance Model | 3 weeks | Hierarchical governance: GovernancePolicy (L0), ExtensionManifest governance (L1), ConsumerBinding governance (L2). Dispute escalation. Version compatibility. |
| 36E | Extension Manager UI | 2 weeks | Loom panel: marketplace registry, extension lifecycle (install/update/remove), governance dashboard, version compatibility matrix, trust signals. |
| 36F | Connector Reference Implementation | 2 weeks | PropertyMe connector as the reference implementation: full grammar, pipeline integration, governance setup, tests. Proves the framework works end-to-end. |

---

## Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│  EXTENSION MANAGER (UI + CLI)                                     │
│  Registry browse / search / install / update / remove             │
│  Governance dashboard: L0 policies, L1 author governance, L2 bind│
│  Trust signals: Glow weight, object count, version history        │
├───────────────────────────────────────────────────────────────────┤
│  GOVERNANCE LAYER                                                 │
│  GovernancePolicy (L0, RELEVANT) ← constrains ─┐                │
│  ExtensionManifest (L1, AFFINE→RELEVANT)        │                │
│  ConsumerBinding (L2, AFFINE)  ← constrained by ┘               │
│  Dispute escalation: L2→L1→L0 via existing Ballot/Resolution     │
├───────────────────────────────────────────────────────────────────┤
│  SEMANTIC EXTRACTION PIPELINE                                     │
│  ┌─────┐  ┌───────┐  ┌───────────┐  ┌───────┐  ┌────────┐      │
│  │FETCH│→ │ PARSE │→ │TYPECHECK  │→ │ INFER │→ │ COMMIT │      │
│  └─────┘  └───────┘  └───────────┘  └───────┘  └────────┘      │
│  Grammar-driven  Normalise  Validate against   Propose new  Create│
│  API calls       to IR      DB schema+taxonomy schemas      cells │
├───────────────────────────────────────────────────────────────────┤
│  EXTENSION GRAMMAR (JSON)                                         │
│  Source entities, field mappings, taxonomy coords, capabilities    │
│  Versioned. Governed. Itself a semantic object.                   │
├───────────────────────────────────────────────────────────────────┤
│  STORAGE ADAPTERS (existing)                                      │
│  NodeFs │ Memory │ Overlay │ BSV                                  │
└───────────────────────────────────────────────────────────────────┘
```

---

## Cross-Cutting Concerns

### Extension Grammar as Semantic Object

An Extension Grammar JSON is itself a semantic object:
- **Linearity**: AFFINE while in draft (author is developing), RELEVANT once published (immutable, globally visible)
- **Taxonomy**: `what.platform.extension.connector`, `how.technical.api.[rest|graphql|grpc|file]`, `why.integration.data-sync`
- **Provenance**: Every patch to the grammar carries facet provenance — who changed what field mapping and when
- **Governance**: Subject to the same Ballot/Dispute/Resolution flow as any other semantic object

### Schema Versioning

Extension grammars use semantic versioning (major.minor.patch):
- **Major**: Breaking change to object types or field mappings — consumers must migrate
- **Minor**: New object types or fields added — backward compatible
- **Patch**: Bug fixes to field mappings — no schema change

The meta-schema (L0) enforces that major version bumps require a governance ballot. Minor and patch versions can be published by the author directly.

### Capability Gating

Extensions declare required capabilities in their grammar:
- `network.outbound` — extension needs to call external APIs
- `storage.write` — extension writes objects to the store
- `identity.read` — extension reads identity/facet information
- `metering.consume` — extension consumes metered resources

The kernel validates capability requirements at install time. Consumers grant capabilities when creating their binding.

### Evidence Chain Continuity

Every object extracted through the pipeline carries a full evidence chain:
- Source record (API response hash, timestamp, endpoint)
- Parse record (grammar version used, field mapping applied)
- Typecheck record (validation result, taxonomy coordinates assigned)
- Inference record (if schema was inferred: proposed grammar diff, confidence score)
- Commit record (cell ID, storage adapter, facet provenance)

---

## Dependencies Between Sub-Phases

```
36A (Grammar Schema)
 ├──→ 36B (Extraction Pipeline) — pipeline reads grammars
 │     └──→ 36C (Inference Agent) — agent produces grammars, uses pipeline
 ├──→ 36D (Governance Model) — governance operates on grammar objects
 │     └──→ 36E (Manager UI) — UI renders governance state
 └──→ 36F (Reference Impl) — reference impl uses grammar + pipeline + governance
       ↑
       └── 36B, 36D (pipeline + governance must be complete)
```

36A is the foundation — everything depends on it. 36B and 36D can run in parallel after 36A. 36C depends on 36B. 36E depends on 36D. 36F is the integration test that depends on 36A + 36B + 36D.

---

## What NOT to Do

- **Don't build per-domain extraction logic.** The pipeline is generic. Domain-specific behavior lives in the Extension Grammar JSON, not in pipeline code. If you're writing `if (domain === 'property')` in the pipeline, you've failed.
- **Don't bypass existing governance primitives.** Extension governance uses the same Ballot/Dispute/Resolution/Constitution objects from `core.json`. No separate governance engine.
- **Don't create a separate identity system for extensions.** Extension authors are identity facets. Extension trust scores are Glow weights. No new identity model.
- **Don't hardcode API protocols.** The grammar declares whether the source is REST, GraphQL, gRPC, file-based, or event-driven. The fetch stage adapts. The pipeline doesn't care.
- **Don't skip evidence chains.** Every extraction must produce a full evidence chain. No "fast path" that skips provenance. The evidence chain IS the value proposition.
- **Don't conflate grammar authoring with grammar governance.** An author can write a grammar (AFFINE draft). Publishing it (transition to RELEVANT) requires meeting the meta-schema constraints. These are separate operations.

---

## Success Criteria (Phase 36 Complete)

- [ ] Extension Grammar JSON meta-schema defined and enforced by kernel
- [ ] Five-stage extraction pipeline operational for at least one real API (PropertyMe)
- [ ] Schema inference agent can propose grammars from unfamiliar API responses
- [ ] Hierarchical governance operational: L0 constrains L1 constrains L2
- [ ] Extension Manager UI in loom: browse, install, update, remove, govern
- [ ] PropertyMe reference connector passes end-to-end extraction with evidence chains
- [ ] Third-party developer can create, test, publish, and govern an extension without touching pipeline code
- [ ] All gate tests pass across sub-phases
- [ ] `bun run check` and `bun run build` succeed
- [ ] Errata sprint complete for each sub-phase

---

## Post-Phase 36

With the extension ecosystem in place, adding a new industry vertical becomes:

1. Write (or have the inference agent propose) an Extension Grammar JSON
2. Configure API credentials in a ConsumerBinding
3. Run the extraction pipeline
4. Objects appear in the VFS, queryable via shell, visible in loom

Phases 28 (ISDA), 29 (SCADA), 32 (Bills of Lading), and 35 (Music Production) can be reimplemented as Extension Grammar JSONs on top of this framework, replacing their hand-crafted extraction logic with the standard pipeline.
