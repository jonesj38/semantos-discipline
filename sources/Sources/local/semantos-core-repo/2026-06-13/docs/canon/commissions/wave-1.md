---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-1.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.756483+00:00
---

# Wave 1 — Documentation Industrialisation Commission

**Audience:** Claude Code (orchestrator) and the parallel-agent fleet it dispatches.
**Author:** Todd Price, RBS.
**Date:** 2026-04-26.
**Status:** Active commission. One PR per artifact; merge under the acceptance gate in §9.

---

## 1. Mission

Produce, in one parallel wave, the next layer of Semantos documentation:

- **One paper:** A2 — *A Two-IR Architecture for Verifiable Computation* (~7,500 words, arXiv-targeted, OOPSLA / POPL-grade rigour).
- **Thirty textbook chapters:** Parts I–VIII of the *Semantos: Booting a Sovereign Node* textbook spine, per `docs/SEMANTOS-DOC-PLAN.md` §2.

The wave is parallelisable because every artifact draws from a closed, frozen input set and produces an independent file under an independent PR branch. There are no cross-artifact dependencies that block dispatch. A single human voice/coherence pass at the end is the only sequential step.

The yield: 31 PRs, each independently reviewable. Voice consistency is enforced by the canonical-term discipline (§5) and the binding voice constraints (§4); no PR is permitted to merge until it cites only canonical terms and matches the voice rubric.

---

## 2. Canonical inputs (read-only by every agent)

Every agent in this wave MUST treat the following as the source of truth. No agent may contradict, paraphrase, or "improve" the canonical content; agents that need a clarification submit a `BLOCKED:` note in their PR description rather than guess.

| Doc | Path | Role |
|---|---|---|
| Doc plan | `docs/SEMANTOS-DOC-PLAN.md` | The textbook outline (§2), the canon workflow (§9), the artifact portfolio (§3). |
| Unification Roadmap (v0.3) | `docs/prd/UNIFICATION-ROADMAP.md` | The matrix, the 15-step boot sequence (§6), the resolved §8 governance decisions, the deliverable IDs. |
| Canon | `docs/canon/` | Structured-data backbone. The glossary (51 entries, all canonicals decided) is normative. Agents cite by `id`. |
| Protocol Spec v0.5 | `docs/spec/protocol-v0.5.md` | The frozen protocol baseline; all wire formats, kernel invariants, opcode set, identity protocol. Authoritative for any implementation claim. |
| Whitepaper v3 | `docs/Semantos-Whitepaper-v3-DRAFT.md` | Voice template; substrate / adapter / boot-sequence / verification framing. Voice carried forward. |
| Paper A1 | `docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md` | Cited by A2 (the compression-gradient discipline that A2 extends). Several textbook chapters reference it. |

**Wave 0 prerequisite:** if `docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md` does not exist on the filesystem, the orchestrator MUST fail-fast and surface the missing file to the human owner before dispatching any A2 agent. (A1 has been drafted and revised; it may need re-saving from the prior session if the workspace was cleaned.) Textbook chapters that cite A1 may proceed without it (it is a back-reference, not a load-bearing dependency).

Supporting reads available to agents that need deeper context:

| Doc | When to consult |
|---|---|
| `docs/SEMANTIC-IR-ARCHITECTURE.md` | Deep dive on SIR + jural categories (Part III chapters; A2). |
| `docs/PIPELINE.md` | Compilation pipeline status (Part III chapters; A2). |
| `docs/INTENT-PIPELINE.md` | The Intent shape; the eight producers (Part IV chapter 20). |
| `docs/FORMAL-VERIFICATION-STRATEGY.md` | K1–K10 rationale; three-layer argument (Part IV chapters 12–14; A2 §5). |
| `docs/EXTENSIONS-VS-TYPES.md` | The four-tier model (Part II chapter 6). |
| `docs/PLATFORM-ARCHITECTURE.md` | Cross-vertical dispatch (Part VIII chapter 29). |
| `docs/prd/WORLD-PROTOCOL.md` | World Host architecture (Part V chapter 16). |
| `docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md` | The six-piece session skeleton (Part V chapter 17). |
| `docs/prd/SOVEREIGN-NODE-PLAN.md` | The three-track engineering plan; M3 milestone (Part VIII chapter 27). |
| `proofs/lean/Semantos/Theorems/*.lean` | Lean snippet sources (any chapter MUST-CITEing a K-invariant). |
| `proofs/lean/Semantos/Lexicons/*.lean` | Per-lexicon Lean code (Part VII chapters 23–26). |
| `core/cell-engine/src/*.zig` | Implementation source (any chapter discussing the cell engine). |

Anything not in the canonical or supporting lists is OUT OF SCOPE for the agent's input set. Agents may not read the wider repo "to be thorough"; they work from the closed set above.

---

## 3. Per-agent brief template

Every agent in this wave receives a brief in the following shape. The orchestrator generates one brief per row of the Wave 1 manifest (§7) by filling the placeholders.

```
ARTIFACT:        <textbook-chapter-N | paper-A2>
TITLE:           <chapter title from §7>
TARGET LENGTH:   <words from §7>
VOICE:           Whitepaper v3 carried forward — operationally boring,
                 declarative, no marketing-tone hype, no competitor
                 naming, no production claims past boot step 7. For paper
                 A2: more academic than the whitepaper (cite related
                 work, use formal notation, match the A1 register).

CANON DISCIPLINE (binding):
  - Use only the canonical alias for every term in docs/canon/glossary.yml.
  - Do NOT introduce new terms without first proposing them in a
    BLOCKED: note in the PR description.
  - Cite kernel invariants by their canonical id (K1, K2, K3, ...) when
    used; expand inline only on first citation.
  - Cite BRC standards by their canonical id (BRC-100, BRC-108, ...)
    when used; expand inline only on first citation.

INPUTS (closed set — do not read outside this list):
  - <ordered list from §7 manifest, each entry with the exact path>

MUST-CITE:       <K-invariants from §7>
ENDS IN:         <chapter-specific closer from §7>

DELIVERABLE:     <path from §7>
PR BASE:         main
PR BRANCH:       <branch from §7>
PR TITLE:        <title from §7>

ACCEPTANCE GATE (the orchestrator runs these before merge):
  1. The deliverable file exists at the deliverable path and is
     within ±15% of TARGET LENGTH (word count).
  2. No glossary alias appears outside the canonical alias for that
     entry. (Run: `bun docs/canon/render/glossary-to-md.ts` to get
     the canonical list; grep the deliverable for each non-canonical
     alias.)
  3. Every K-invariant in MUST-CITE appears at least once in the
     deliverable.
  4. The deliverable ends with the section described in ENDS IN.
  5. No competitor names appear (Ethereum, Solana, AWS, OpenAI by
     name, etc.). Generic categorical references are fine.
  6. No production claims past boot step 7 unless the deliverable
     explicitly cites the Unification Matrix gating that claim.
  7. PR description names every BLOCKED: item if any.

If any acceptance check fails, the PR is held; the agent receives the
specific failure and may revise once, then surface to the human owner.
```

---

## 4. Voice and style constraints (binding on every agent)

These are not negotiable. Drift is the failure mode this wave exists to eliminate.

**Voice:** carry forward the *Whitepaper v3* register. Operationally boring. Declarative. Each section earns its keep with a specific load. No motivational language. No "compelling," "transformative," "revolutionary" — the value is in the architecture, not in the description of the architecture. For paper A2 specifically: more academic than the whitepaper, matching A1's register — formal definitions where appropriate, related-work citations, explicit limitations section.

**No competitor naming.** Categorical references are fine ("modern LLM agent frameworks," "centralised cloud-database architectures"). Specific product names are not.

**No production claims past boot step 7.** The substrate runs end-to-end through step 7 (`kernel_set_enforcement(1)`); steps 8–15 work in feasibility but are not yet enforced under proper BRC verification across every adapter. Any chapter or paper section discussing capability beyond step 7 MUST cite the Unification Matrix as gating that claim ("when the Matrix completes" / "currently in feasibility, full enforcement scheduled with deliverable D-XXX").

**No commercial-customer naming.** None are named in the public artifacts. Reference deployments are described as architectural patterns.

**Formatting:**

- Markdown only. No `.docx`.
- Headings: `#` for the artifact title, `##` for top-level sections, `###` for subsections. No deeper than `####`.
- Code in fenced blocks with language hint when known.
- Tables with header rows and alignment colons where appropriate.
- ASCII diagrams marked with `[FIGURE — needs real graphic for layout pass]` callout if they would benefit from later vector rendering.
- Worked examples as boxed blocks (`>` blockquote) when they thread through multiple sections.
- Notation: Lean snippets in fenced `lean` blocks; opcode bytes as `0xXX`; canonical glossary terms in body prose without typographic emphasis (no italics, no monospace) unless they are the first introduction.

**Length discipline:** target lengths in §7 are firm to ±15%. Agents that overshoot 15% MUST cut. Agents that undershoot 15% have probably failed to reach the chapter's content depth and should be flagged for human review.

---

## 5. Glossary discipline (mandatory)

Every agent MUST use only the canonical alias for any term in `docs/canon/glossary.yml`. The 51 entries have all decided canonicals; the orchestrator's acceptance check (§3 gate item 2) enforces this mechanically.

The high-stakes resolutions (drift pairs) — agents that produce non-canonical aliases for any of these are auto-failed:

| Drift pair | Canonical | Non-canonical (auto-fail) |
|---|---|---|
| cell vs object | **cell** | LoomObject (except as type-name code reference), SemanticObject, SemObj |
| facet vs hat | **hat** | facet, faceted, cross-facet |
| capability vs permission (for the BRC-108 token) | **capability token** | permission (when used to mean the BRC-108 thing) |
| trust domain vs governance domain | **governance domain** | trust domain (except when referring specifically to the *trust kind* of governance domain) |
| Helm vs Loom | **Helm** | Loom (except as `loom-react` package-name reference) |
| Jural categories | **declaration, obligation, permission, prohibition, power, condition, transfer** (the seven adapted categories) | The raw Hohfeldian eight (right/duty, privilege/no-right, etc.) — except in §s explicitly discussing Hohfeld 1913 as theoretical source |

When introducing a canonical term for the first time in a chapter or paper section, agents MAY include a short parenthetical with the standard alias only if the alias is itself canonical-adjacent (e.g. "*SignedBundle* (BRC-100 envelope)") — this is permitted because both are canonical aliases of the same `signed-bundle` glossary entry. Agents MUST NOT introduce non-canonical aliases for clarification.

---

## 6. Coordination rules

**One PR per artifact.** No agent merges its own; the human owner does the final voice/coherence pass and merges.

**Branch naming:** `feat/textbook-chXX` for chapter `XX` (zero-padded); `feat/paper-aN` for paper `aN`. Branch off `main`.

**No cross-PR dependencies.** Each artifact is independently reviewable. If artifact A would benefit from referencing artifact B, the agent for A includes a "(see chapter B / paper B for depth)" forward-reference and does not block on B's existence.

**File ownership:** each PR touches only its own deliverable and (optionally) `docs/canon/commissions/wave-1.md` to record the artifact's completion. No PR may modify the canon, the doc plan, the unification roadmap, the protocol spec, the whitepaper, or A1 (those are inputs, not targets of this wave).

**Commit-message convention:** PR commits cite the artifact id in the subject line (`feat(textbook-ch05): draft hats and capability tokens`). PR description includes the canonical-glossary discipline confirmation (one line: "Glossary discipline: passed canonical-alias check.") and any BLOCKED: items.

**Conflict avoidance:** because each PR touches a single new file under a unique path, no merge conflicts are expected. Two PRs that accidentally write to the same path is a wave-orchestration bug; surface to human owner.

**Failure handling:** an agent that cannot satisfy a brief (e.g. a MUST-CITE invariant has no canonical statement, or an INPUT path doesn't exist) MUST submit a `BLOCKED:` PR with the specific blocker. The human owner resolves blockers; the agent is then re-dispatched with the resolved input.

---

## 7. Wave 1 manifest

31 artifacts. Each row defines one parallel agent. The orchestrator dispatches all 31 in parallel.

### 7.1 Paper A2

| Field | Value |
|---|---|
| Artifact | paper-A2 |
| Title | A Two-IR Architecture for Verifiable Computation |
| Target length | ~7,500 words |
| Inputs (closed set) | `docs/SEMANTIC-IR-ARCHITECTURE.md` (full); `docs/PIPELINE.md` (full); `docs/canon/glossary.yml` § ir, sir, oir, anf, jural-category, lexicon, linearity, kernel-invariant, compression-gradient, cell-engine; `docs/spec/protocol-v0.5.md` § 2.2, 7, 8, 9.1; `docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md` (full — cited as the compression-gradient prior); `core/semantos-sir/src/types.ts`; `core/semantos-ir/src/types.ts`; `core/semantos-sir/src/__tests__/equivalence.test.ts` (the α-equivalence corpus). |
| Must-cite | K1, K2, K3, K4, K5; SIR; OIR; ANF; the seven jural categories; α-equivalence claim |
| Ends in | a formal-block restating the SIR → OIR lowering as a function `lowerSIR : SIR → Error + OIR` with the trust-tier enforcement clause; an honest-limitations register in the §7 register style |
| Voice | Academic — A1 register, more rigour than the whitepaper. Cite Hohfeld 1913, Sabry & Felleisen 1992, Wadler 1990. Honest limitations explicit. No competitor naming. |
| Deliverable | `docs/papers/Semantos-A2-Two-IR-Architecture-DRAFT.md` |
| PR branch | `feat/paper-a2` |
| PR title | `feat(paper-a2): draft two-IR architecture paper` |
| Notes | The claim is: a two-IR architecture in which an upper IR carries jural / governance metadata and a lower IR carries operational predicates admits structural enforcement of governance properties at compile time. Distinguish from compiler-IR-as-optimisation work. Cite A1 as the compression-gradient discipline that A2 extends with the specific upper/lower IR shape. |

### 7.2 Textbook Part I — Why a Sovereign Node

Each chapter ~3,000 words unless otherwise noted. Part I chapters do NOT need to end in a working program (they are motivational); they MUST end with a paragraph naming the sovereign-node boot step or matrix axis the chapter motivates.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 01 | The naming problem | `docs/Semantos-Whitepaper-v3-DRAFT.md` § 1; `docs/canon/glossary.yml` § sovereign-node, substrate; `docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md` § 1 | (none — motivational) | a paragraph framing the substrate as the missing layer | `docs/textbook/01-the-naming-problem.md` | `feat/textbook-ch01` |
| 02 | What goes wrong with LLM-driven systems | `docs/INTENT-PIPELINE.md` § "Why this is the core primitive"; `docs/papers/Semantos-A1-Compression-Gradient-DRAFT.md` § 1, § 5.2 (handyman intake) | (none — motivational) | the canonical handyman-intake worked example, foreshadowing the gradient | `docs/textbook/02-llm-failure-modes.md` | `feat/textbook-ch02` |
| 03 | The sovereign node, end-to-end | `docs/Semantos-Whitepaper-v3-DRAFT.md` § 2; `docs/prd/UNIFICATION-ROADMAP.md` § 6; `docs/prd/SOVEREIGN-NODE-PLAN.md` § "Three-Part Handoff"; `docs/canon/glossary.yml` § sovereign-node, boot-sequence | K1, K2 (named only; depth is later chapters) | the 15-step boot sequence as a single picture; the curl-one-URL M3 reveal; reader exit "by the end of this book you will boot one yourself" | `docs/textbook/03-sovereign-node-end-to-end.md` | `feat/textbook-ch03` |

### 7.3 Textbook Part II — Identity (boot steps 1–6)

Each chapter ~4,500 words.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 04 | Plexus and the identity DAG | `docs/spec/protocol-v0.5.md` § 4.1, 4.2, 4.4; `docs/canon/glossary.yml` § plexus, brc-42, brc-52, cert-id, edge, recovery-payload, challenge-set; § 6 (recovery flow) | K2 | a Lean snippet from `proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean`; boot-sequence steps 1–3 unlocked | `docs/textbook/04-plexus-identity-dag.md` | `feat/textbook-ch04` |
| 05 | Hats and capability tokens | `docs/spec/protocol-v0.5.md` § 4.7, § 5; `docs/canon/glossary.yml` § hat, capability-token, brc-100, brc-108; `docs/EXTENSIONS-VS-TYPES.md` (full) | K1, K7 | a worked example (kanban card movement as capability consumption — extract from any future `docs/canon/examples/kanban-30min.{md,ts}` if present, otherwise sketch); boot-sequence steps 4–6 unlocked | `docs/textbook/05-hats-and-capabilities.md` | `feat/textbook-ch05` |
| 06 | Domain flags as sovereign boundaries | `docs/spec/protocol-v0.5.md` § 4.5, § 8.2; `docs/canon/glossary.yml` § domain-flag, governance domain (id `trust-domain`); `docs/SEMANTIC-IR-ARCHITECTURE.md` § 10 (governance domain model) | K3 | a Lean snippet from `proofs/lean/Semantos/Theorems/DomainIsolationK3.lean`; the trust-/estate-/realm-/corporate-/cooperative- worked example | `docs/textbook/06-domain-flags-sovereign-boundaries.md` | `feat/textbook-ch06` |

### 7.4 Textbook Part III — Cells & The Pipeline (boot step 7)

Each chapter ~4,500 words.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 07 | Cells, types, linearity | `docs/spec/protocol-v0.5.md` § 3 (full); `docs/canon/glossary.yml` § cell, linearity, hash-chain | K1, K7 | a worked program: hand-pack a cell from raw bytes; show the `prevStateHash` chain advance | `docs/textbook/07-cells-types-linearity.md` | `feat/textbook-ch07` |
| 08 | Surface to AST | `docs/PIPELINE.md` § "Live flow today"; `runtime/shell/src/lisp/parser.ts`, `compiler.ts`; `docs/canon/glossary.yml` § ir | (none required; structural chapter) | a worked program: hand-write a Lisp constraint and trace through the AST | `docs/textbook/08-surface-to-ast.md` | `feat/textbook-ch08` |
| 09 | Semantic IR (SIR) | `docs/SEMANTIC-IR-ARCHITECTURE.md` (full); `docs/canon/glossary.yml` § sir, jural-category | (none required; structural) | a worked program: a SIR program with jural category, taxonomy, governance context, identity binding; reference forward to A2 for the formal model | `docs/textbook/09-semantic-ir.md` | `feat/textbook-ch09` |
| 10 | Opcode IR (OIR), ANF, and emit | `docs/PIPELINE.md` § "Why a dual IR"; `docs/canon/glossary.yml` § oir, anf; `core/semantos-ir/src/types.ts`; `core/semantos-ir/src/lower.ts`; `core/semantos-ir/src/emit.ts` | (none required; structural) | a worked program: trace one SIR program through SIR → OIR → bytes; show the byte-budget table from the whitepaper § 3.6 | `docs/textbook/10-opcode-ir-and-emit.md` | `feat/textbook-ch10` |
| 11 | The 2-PDA cell engine | `docs/spec/protocol-v0.5.md` § 8 (full); `docs/canon/glossary.yml` § cell-engine, opcode | K1, K3, K4, K5, K7 | a Lean snippet from `proofs/lean/Semantos/Theorems/LinearityK1.lean`; boot-sequence step 7 unlocked (`kernel_set_enforcement(1)`) | `docs/textbook/11-2pda-cell-engine.md` | `feat/textbook-ch11` |

### 7.5 Textbook Part IV — Verification (boot step 8)

Each chapter ~4,500 words.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 12 | The K1–K10 invariants | `docs/spec/protocol-v0.5.md` § 9 (full); `docs/FORMAL-VERIFICATION-STRATEGY.md` § 1; `docs/canon/glossary.yml` § kernel-invariant | K1, K2, K3, K4, K5, K7, K8, K9, K10 | a paragraph stating each invariant and what it rules out; a forward-reference to chapter 13 for the proofs themselves | `docs/textbook/12-k1-k10-invariants.md` | `feat/textbook-ch12` |
| 13 | Lean 4 + TLA+ walkthrough | `proofs/lean/Semantos/Theorems/LinearityK1.lean` (full); `proofs/tla/ReplayPrevention.tla` (full); `docs/FORMAL-VERIFICATION-STRATEGY.md` § 3, § 4, § 10 (limitations) | K1, K6 | a step-by-step trace of one Lean proof; an explicit limitations register section | `docs/textbook/13-lean-tla-walkthrough.md` | `feat/textbook-ch13` |
| 14 | The Verifier Sidecar | `docs/spec/protocol-v0.5.md` § 9.5; `docs/prd/UNIFICATION-ROADMAP.md` § 5 (D-V1, D-V2, D-V3); § 8 Q3 resolution; `docs/canon/glossary.yml` § verifier-sidecar | K2 | the three deployment topologies with trade-offs; boot-sequence step 8 unlocked | `docs/textbook/14-verifier-sidecar.md` | `feat/textbook-ch14` |

### 7.6 Textbook Part V — Adapters & The Mesh (boot steps 9–11)

Each chapter ~4,500 words.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 15 | The substrate / adapter distinction | `docs/prd/UNIFICATION-ROADMAP.md` § 1, § 2 (full matrix), § 3 (axes); `docs/canon/glossary.yml` § substrate, adapter | (none required; structural) | the matrix snapshot at writing time; a pointer to `docs/canon/unification-matrix.yml` as the live state | `docs/textbook/15-substrate-vs-adapter.md` | `feat/textbook-ch15` |
| 16 | World Host and the Region model | `docs/prd/WORLD-PROTOCOL.md` (full); `docs/canon/glossary.yml` § world-host, region, avatar | K1 (linearity removes drift / no-CRDT claim) | a worked program: trace one entity-action through region authority + WorldTick; boot-sequence step 9 unlocked | `docs/textbook/16-world-host-regions.md` | `feat/textbook-ch16` |
| 17 | The Mesh — IPv6 multicast and the codec port | `docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md` (full); `docs/spec/protocol-v0.5.md` § 12; `docs/canon/glossary.yml` § mesh, signed-bundle, bca | (none required; structural) | the six-piece session skeleton diagram; "every vertical is a state machine over a shared session skeleton" framing; boot-sequence step 10 unlocked | `docs/textbook/17-mesh-and-session-skeleton.md` | `feat/textbook-ch17` |
| 18 | Helm — the convergence surface | `docs/PLATFORM-ARCHITECTURE.md` (full); `docs/canon/glossary.yml` § helm | (none required; structural) | a description of the three-panel React workbench; boot-sequence step 11 unlocked; a note that voice (A8) is the placeholder for the next input modality | `docs/textbook/18-helm-convergence-surface.md` | `feat/textbook-ch18` |

### 7.7 Textbook Part VI — Time, Recovery & Metering (boot steps 12–14)

Each chapter ~4,500 words.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 19 | Time as a stack of hash chains | `docs/canon/glossary.yml` § hash-chain, ticks; `docs/prd/UNIFICATION-ROADMAP.md` § 8 Q4 + Q5 resolutions (branching policies); `docs/spec/protocol-v0.5.md` § 3.6, § 11.1 | K6, K9 | the four named chain scopes (cell / region / channel / domain) with disambiguation; boot-sequence step 12 unlocked | `docs/textbook/19-hash-chains-as-time.md` | `feat/textbook-ch19` |
| 20 | Universal Intent and the evidence chain | `docs/INTENT-PIPELINE.md` (full); `docs/canon/glossary.yml` § compression-gradient, signed-bundle | (none required; structural) | a worked program: trace one user-turn from message to anchored cell with all 8 stage events tagged with the same correlation ID | `docs/textbook/20-universal-intent.md` | `feat/textbook-ch20` |
| 21 | Recovery substrate | `docs/spec/protocol-v0.5.md` § 6 (full); `docs/canon/glossary.yml` § recovery-payload, challenge-set, brc-42, brc-69 | (none required; mostly Plexus-protocol) | the four-phase recovery flow worked through; threshold recovery for high-security roots; boot-sequence step 13 unlocked | `docs/textbook/21-recovery-substrate.md` | `feat/textbook-ch21` |
| 22 | Metered Flow Protocol | `docs/spec/protocol-v0.5.md` § 11 (full); `docs/canon/glossary.yml` § mfp, ticks, capability-token | (none required; mostly protocol) | the 8-state FSM with all transitions; nSequence settlement; boot-sequence step 14 unlocked | `docs/textbook/22-metered-flow-protocol.md` | `feat/textbook-ch22` |

### 7.8 Textbook Part VII — Domains (lexicon chapters)

Each chapter ~3,500 words. Same template per chapter: domain's economic problem → its Hohfeldian decomposition (which jural categories appear) → the Lean lexicon code → a 30-min runnable demo → what extensions someone might write next.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 23 | Jural — the canonical lexicon | `proofs/lean/Semantos/Lexicons/Jural.lean` (full); `docs/canon/glossary.yml` § jural-category, lexicon | (none required; lexicon walkthrough) | the full 40-line Lean file annotated; a worked program: encode one Hohfeldian relation as a SIR program | `docs/textbook/23-jural-lexicon.md` | `feat/textbook-ch23` |
| 24 | CDM — derivatives lifecycle | `proofs/lean/Semantos/Lexicons/CDM.lean` (full); `extensions/cdm/` (skim for vocabulary); `docs/SEMANTIC-IR-ARCHITECTURE.md` § 3.4 (CDM mapping table) | (none required; lexicon walkthrough) | the lexicon code; a worked program: a CDM novation as a `power + transfer` SIR program | `docs/textbook/24-cdm-lexicon.md` | `feat/textbook-ch24` |
| 25 | Property management — leases, maintenance, dispatch envelopes | `proofs/lean/Semantos/Lexicons/PropertyManagement.lean` (full); `docs/PLATFORM-ARCHITECTURE.md` § "Property management vertical"; `docs/canon/glossary.yml` § dispatch-envelope, hat | (none required; lexicon walkthrough) | the lexicon code; the leaky-tap worked example from Whitepaper v3 § 4 retold from the lexicon's perspective | `docs/textbook/25-property-management-lexicon.md` | `feat/textbook-ch25` |
| 26 | Control systems / SCADA — telemetry, interlocks, alarms | `proofs/lean/Semantos/Lexicons/ControlSystems.lean` (full); `docs/SEMANTIC-IR-ARCHITECTURE.md` § 3.4 (SCADA mapping table) | (none required; lexicon walkthrough) | the lexicon code; a worked program: an interlock policy as a `prohibition` SIR program with logical negation | `docs/textbook/26-control-systems-lexicon.md` | `feat/textbook-ch26` |

### 7.9 Textbook Part VIII — Building

Chapter 27 is ~5,500 words (the canonical demo); the others ~4,500.

| # | Title | Inputs (closed set) | Must-cite | Ends in | Deliverable | Branch |
|---|---|---|---|---|---|---|
| 27 | Boot a sovereign node | `docs/prd/SOVEREIGN-NODE-PLAN.md` (full); `docs/prd/UNIFICATION-ROADMAP.md` § 6; `docs/spec/protocol-v0.5.md` § 2.3 | K1, K2, K3, K4, K5 (the boot exercises them all) | the full 15-step walkthrough on the reader's own machine; a `docker compose up` happy path; the `semantos node status` output showing all-green | `docs/textbook/27-boot-a-sovereign-node.md` | `feat/textbook-ch27` |
| 28 | Build your first adapter — kanban in 30 minutes | `docs/canon/glossary.yml` (kanban-relevant entries); `docs/EXTENSIONS-VS-TYPES.md` (full); `docs/SEMANTIC-IR-ARCHITECTURE.md` § 3.4 (jural category mappings) | K1 (cards as LINEAR resources moving across columns) | a complete kanban adapter sketch: cells, columns as state machine, comments as patches, audit trail as evidence chain; deployment via `semantos install extension kanban` (or sketched if not yet built) | `docs/textbook/28-build-your-first-adapter-kanban.md` | `feat/textbook-ch28` |
| 29 | Cross-vertical dispatch and federation | `docs/PLATFORM-ARCHITECTURE.md` (full); `docs/prd/PHASE-35A-SESSION-PROTOCOL-PROMOTION.md` (Phase 35B mentioned); `docs/canon/glossary.yml` § dispatch-envelope, hat, mesh | (none required; integration patterns) | the dispatch envelope worked example; federation via Phase 35B; "when to anchor, when not to" guidance | `docs/textbook/29-cross-vertical-dispatch-and-federation.md` | `feat/textbook-ch29` |
| 30 | Compliance posture | `docs/spec/protocol-v0.5.md` § 9, § 13.6; `docs/FORMAL-VERIFICATION-STRATEGY.md` § 6, § 7, § 11 | K1–K10 collectively | a sample regulator-facing document section: kernel contribution to one named requirement (pick from the §6 mapping) + assumption register + WASM hash anchor citation | `docs/textbook/30-compliance-posture.md` | `feat/textbook-ch30` |

---

## 8. Summary tally

| Block | Artifacts | Total target words |
|---|---|---|
| Paper A2 | 1 | ~7,500 |
| Part I (motivational) | 3 | ~9,000 |
| Part II (identity) | 3 | ~13,500 |
| Part III (pipeline) | 5 | ~22,500 |
| Part IV (verification) | 3 | ~13,500 |
| Part V (adapters & mesh) | 4 | ~18,000 |
| Part VI (time / recovery / metering) | 4 | ~18,000 |
| Part VII (domain lexicons) | 4 | ~14,000 |
| Part VIII (building) | 4 | ~19,000 |
| **Wave total** | **31** | **~135,000 words** |

A 135 000-word output across 31 parallel agents: roughly the size of HTDP, produced in one wave.

---

## 9. Acceptance gate (orchestrator-runnable)

For each PR, the orchestrator runs the seven-item gate from §3 verbatim. Specifically:

```sh
# Gate 1: file exists + length within ±15% of target
test -f "${DELIVERABLE}" || fail "missing: ${DELIVERABLE}"
WORDS=$(wc -w "${DELIVERABLE}" | awk '{print $1}')
LOW=$(echo "${TARGET_WORDS} * 0.85" | bc -l | cut -d. -f1)
HIGH=$(echo "${TARGET_WORDS} * 1.15" | bc -l | cut -d. -f1)
test "${WORDS}" -ge "${LOW}" && test "${WORDS}" -le "${HIGH}" \
  || fail "length ${WORDS} outside [${LOW}, ${HIGH}]"

# Gate 2: canonical-glossary discipline
# For every glossary entry, every alias OTHER than the canonical
# must NOT appear in the deliverable (with the documented exceptions
# in §5: code-path references, type-name references).
bun docs/canon/render/glossary-to-md.ts > /tmp/canonical-list.md
# (orchestrator implements the exception-aware grep here)

# Gate 3: MUST-CITE invariants present
for k in ${MUST_CITE_INVARIANTS}; do
  grep -q "\\b${k}\\b" "${DELIVERABLE}" || fail "missing must-cite: ${k}"
done

# Gate 4: ENDS IN section present (orchestrator checks for the
# specified section name or block at the end of the file)

# Gate 5: no competitor names
for name in Ethereum Solana Avalanche Cardano Polygon AWS Azure GCP \
            OpenAI Anthropic LangChain AutoGPT; do
  grep -qi "\\b${name}\\b" "${DELIVERABLE}" \
    && fail "competitor named: ${name} (use generic categorical reference)"
done
true

# Gate 6: production claims past boot step 7 must cite the matrix
# (orchestrator implements a heuristic: any sentence containing
# "production" / "in production" must be within K lines of a citation
# of "Unification Matrix" or "deliverable D-")

# Gate 7: PR description includes glossary-discipline confirmation
# and any BLOCKED items
```

A PR that passes all seven gates is queued for human voice/coherence review. A PR that fails any gate is held with the specific failure surfaced; the agent gets one revision; then it surfaces to the human owner.

---

## 10. Execution

To dispatch this wave with Claude Code:

1. Confirm the canonical inputs (§2) all exist on disk. If A1 is missing per the Wave 0 prerequisite, restore or regenerate it first.
2. Confirm the canon's `glossary.yml` is at the post-canonical-decision-pass state (51 entries, all canonicals decided, definitions filled). If not, abort and run the canonical-decision pass first.
3. Confirm the protocol spec, whitepaper, doc plan, unification roadmap, and supporting reads are at the versions listed.
4. Dispatch all 31 agents in parallel, each with the brief generated from the §7 manifest row using the template in §3.
5. Each agent opens a single PR per the §6 conventions.
6. The orchestrator runs the §9 gate on each PR; failed PRs are returned to the agent for one revision; double-failures escalate to the human owner.
7. The human owner runs the voice/coherence pass across the wave (the only sequential step) and merges in any order.

Expected wave duration: bounded by the slowest individual agent (typically Part IV chapter 13 or Part VII chapter 24 — the chapters that require deepest source-material absorption). Empirically, the parallel wave should complete in roughly the time of the slowest single artifact rather than the sum.

---

## 11. Post-wave

When Wave 1 merges:

- The textbook draft exists end-to-end (~135 000 words across Parts I–VIII).
- Paper A2 exists alongside A1 — two arXiv-targeted theory papers ready for submission.
- The canon now has new deliverable inputs (citations from A2 and 30 chapters reflecting back into glossary entries that may need refinement).
- The next wave (Wave 2) likely commissions: Papers A3 / A4 (the bounded-2-PDA paper and the history-indexed-types paper); Appendix G of the textbook (the four remaining lexicon chapters); reference deployments / Sovereign Node Plan implementation tracks.

A Wave 2 manifest will be drafted after Wave 1 completes its voice/coherence pass — the experience of running Wave 1 will inform refinements to the brief template, the gate, and the parallelisation envelope.

---

*End of Wave 1 commission.*
