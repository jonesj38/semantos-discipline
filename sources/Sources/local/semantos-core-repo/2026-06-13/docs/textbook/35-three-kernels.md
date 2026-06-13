---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/35-three-kernels.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.649541+00:00
---

# Chapter 35 — Three Kernels: 2PDA, Pask, and HRR

The public framing of Semantos collapses everything load-bearing into the cell engine — *"cells + linearity + 2PDA + intent"*. That framing names one kernel but the substrate actually ships **three**, each providing a different mathematical guarantee, each compiled to a separate WASM module, each useful without the others.

This chapter names all three and the property each contributes:

- **2PDA (`core/cell-engine/`)** — *deterministic execution.* The verifiable-bytecode kernel. K1, K4, K5 live here.
- **Pask (`core/pask/`)** — *convergence over interaction streams.* The constraint-graph learning kernel. ΔH stability and stable-thread surfacing live here.
- **HRR (`core/hrr/`)** — *semantic encoding.* The intent-to-vector mapper. Plate (1995) circular convolution lives here.

Each is a sibling library at the `core/` layer. None depends on the others at the WASM/library level. They compose in the runtime, not in their build artifacts. The combined `pask-and-cell.wasm` (42 KB) is a convenience packaging, not a tighter coupling.

---

## 35.1 The Three Guarantees

| Kernel | Guarantees | Does not guarantee |
|---|---|---|
| **2PDA** | Deterministic, bounded execution; linearity enforcement; failure atomicity | Learning, generalization, similarity |
| **Pask** | Convergence on stable patterns under repeated interaction; bounded memory | Verifiable execution; deterministic output |
| **HRR** | Similarity-preserving encoding; bidirectional bind/unbind; orthogonality across domains | Correctness; learning; execution |

The load-bearing claim: **no kernel substitutes for another.** The cell engine cannot learn. Pask cannot prove. HRR cannot execute. The system needs all three because the substrate's job — turning intent into mathematically grounded action — spans three domains of guarantee.

---

## 35.2 The Cell Engine (2PDA) — Deterministic Execution

Lives at `core/cell-engine/`. Ships as ~36 KB WASM. Implements a two-stack pushdown automaton evaluating Bitcoin Script extended with the Plexus opcodes 0xC0–0xCF (see `core/cell-ops/dist/opcodes.d.ts`).

### What it provides

- **K1 (Linearity)**: every cell carries a linearity class (LINEAR / AFFINE / RELEVANT / DEBUG per `core/protocol-types/src/constants.ts:25-30`); the kernel rejects executions that would consume a LINEAR cell twice or drop a RELEVANT cell silently.
- **K4 (Failure atomicity)**: execution failures roll the machine state back byte-for-byte. Half-mutations are impossible. The opcode-hardening plan at `core/cell-engine/OPCODE-HARDENING-PLAN.md` is exactly the discipline that makes K4 hold across the macro and Plexus opcode families.
- **K5 (Deterministic termination)**: no loops, bounded opcount, bounded stack depth. Every execution terminates in at most `opcountLimit` steps (`docs/FORMAL-VERIFICATION-STRATEGY.md:26, :153-155`).

### What it cannot do

- **No learning.** The kernel has no memory of past executions. Two identical inputs produce identical outputs every time — that's K5 working — but the kernel itself does not generalize.
- **No similarity.** Two cells whose payloads differ by a single byte have different cell IDs and are unrelated from the kernel's perspective. "These two intents mean the same thing" is not a question the 2PDA can answer.
- **No projection.** The kernel does not predict; it executes. A cell engine cannot say "users who did X usually do Y next."

These are not limitations to be removed; they are the *price* the kernel pays for being verifiable. A deterministic kernel that learned would no longer be deterministic; a verifiable kernel that generalized would no longer be verifiable. The trade is intentional.

---

## 35.3 Pask — Convergence Over Interaction Streams

Lives at `core/pask/`. Ships as ~7 KB WASM (freestanding) or ~7 KB WASI. Implements constraint-graph learning per the Pask substrate paradigm — *not* a neural network, *not* a backprop trainer.

The canonical reader's guide is `core/pask/PRIMER.md`. The README at `core/pask/README.md` summarises:

> Feed it interactions between named cells. It maintains a graph where edges accumulate weight on co-occurrence, propagates local constraint effects 1–3 hops per interaction, and surfaces the cells whose ΔH has settled near zero as **stable threads** — the structures the data has converged on.

### The model in five lines

```
G = (V, E)              graph of nodes and edges
h_i ∈ R                  state of node i
C_ij ∈ R                 constraint weight on edge (i, j)
ΔH(i) ≈ avg|recent ΔC|  node i's recent activity
stable(i) iff ΔH(i) < ε  node i has settled
```

The `interact(primary, kind, strength, related[], now_ms)` call is the only mutation primitive. It:

1. Upserts the primary and related nodes
2. Upserts edges and accumulates weight on co-occurrence
3. Propagates constraints by region expansion (one hop per propagation step, 1–3 steps per call)
4. Periodically checks stability and prunes nodes with low inbound edge trend

### The empirical claim

Pask's load-bearing conformance test is `zig build chess` — 1500 grandmaster PGN games fed as move-prefix transitions. With no domain knowledge baked in, Pask converges on the canonical chess opening moves ranked by traffic:

```
chess: games=1500 nodes=4900 edges=4899 stable=1022
top first-ply moves by traffic:
  n=   705  p:e4
  n=   509  p:d4
  n=   148  p:Nf3
  n=   119  p:c4
```

The chess test is the load-bearing conformance harness; the README is explicit:

> If you change the propagation math and it stops finding e4/d4 in the top moves at 1500 GM games, the change is wrong.

### What Pask provides

- **Convergence**: settling around stable threads is the discovered structure of the input.
- **Bounded memory**: fixed-pool arrays (default 16k nodes, 32k edges, 64k delta-ring ≈ 18 MB).
- **Replayability**: clock arguments are caller-supplied; replays are bit-identical given the same interaction stream.
- **Snapshot ABI**: capture a ~16 MB blob, persist it as cells or to disk, restore later.

### What Pask is not

The PRIMER lists four explicit non-claims:

1. **Not a database** — runs in linear memory, persisted via snapshot.
2. **Not a graph database** — fixed-pool arrays, no arbitrary queries.
3. **Not a recommendation engine** — tells you what's *settled*, not what's *next*.
4. **Not online-learnable in the ML sense** — no backprop, no model weights.

The fourth point is the one that surprises practitioners coming from machine learning. Pask is a *substrate*, not a *model*. It has no objective function being minimized. It records what happened, accumulates weight on co-occurrence, and surfaces what stuck. The discovered structure is not a prediction; it's a measurement.

---

## 35.4 HRR — Semantic Encoding via Circular Convolution

Lives at `core/hrr/`. Ships as a TypeScript library (no WASM yet — the math is light enough that JS suffices). Implements Plate (1995) Holographic Reduced Representations.

### What HRR provides

A way to map a structured intent program (an `IRProgram` from `core/semantos-ir/`) to a single fixed-dimensional vector such that:

- Two programs with similar structure have high cosine similarity
- Two programs in different domains have cosine ≈ 0 (via orthogonal role-vector bases)
- A program vector can be *unbound* (approximately decoded) given a role vector

### The primitives

From `core/hrr/src/index.ts`:

```ts
encodeSIRProgram(program, domainFlag) → Float64Array  // D=1024 unit vector
bind(role, filler)                   → Float64Array  // circular convolution
unbind(bound, role)                  → Float64Array  // circular correlation
cosine(a, b)                         → number        // similarity ∈ [-1, 1]
```

Each `IRBinding` in the program maps to one `(role ⊛ filler)` term where `⊛` is circular convolution. The program vector is the L2-normalised superposition of all binding terms (`core/hrr/src/encode.ts:14`).

Structural slots are mapped:

| Slot | Filler seed |
|---|---|
| `kind` | `binding.kind` |
| `op` | `binding.op` (comparison) |
| `field` | `binding.field` (comparison) |
| `value_class` | `quantise(value)` — buckets `<0`, `0`, `0-1k`, `1k-100k`, `>100k` |
| `capability` | `String(cap number)` |
| `domain` | `String(domainFlag)` |
| `time_op` | `binding.timeOp` |

The domain slot is present in every program so that **cross-domain cosines converge to ≈ 0**, empirically confirmed in work item WI-A4 (per `core/hrr/src/encode.ts:26-28`).

### Why D = 1024

The HRR vector dimension is **1024** — the same number as the cell size. Not a coincidence. A 1024-dimensional `Float64Array` is 8 KB, which fits in a small fixed-size payload region; a quantised or reduced-precision form (e.g. 16-bit floats at D=1024 = 2 KB) fits in a single cell's payload (768 B) with room left over.

The interplay matters because **Pask graph nodes can carry HRR vectors as their semantic key** alongside the existing pask-ga genome key. Per memory `semantos_hrr_design_decisions.md` (resolved 2026-04-XX):

- HRR vectors **co-exist** with the pask-ga genome slot rather than replacing it
- A collaborator actively uses the genome for GA clustering/crossover; HRR is additive
- SIR-derived nodes carry both; a flag distinguishes which is present

This is the load-bearing co-existence: HRR enables similarity-based retrieval ("show me intents similar to this one"); the genome enables evolutionary search ("cross over these two solutions"). They're different operations on the same node, not competing representations.

### What HRR does not do

- **No correctness.** A high-cosine match is not a proof of equivalence — only that the structural superpositions land near each other.
- **No execution.** HRR encodes intent shape but doesn't run anything.
- **No learning.** HRR encoding is deterministic given a program; the encoder itself doesn't adapt.

HRR is the *similarity* primitive. It tells you "these intents look alike." Whether they should be treated alike is a downstream decision belonging to the dispatch and lexicon layers.

---

## 35.5 How the Three Kernels Compose

The three kernels meet in the runtime, not in a build artifact. Their composition is best understood through the lifecycle of a single intent:

```
┌────────────────────────────────────────────────────────────┐
│  Natural language / voice / click input                    │
└──────────────────────────┬─────────────────────────────────┘
                           │
                           ▼ NL→SIR extraction (D-Dlex-voice)
┌────────────────────────────────────────────────────────────┐
│  SIR IRProgram (structured intent)                         │
└────────┬─────────────────────────────────┬─────────────────┘
         │                                 │
         │ encodeSIRProgram()              │ lowerToOIR()
         │                                 │
         ▼                                 ▼
┌──────────────────┐         ┌──────────────────────────────┐
│  HRR vector      │         │  Bytecode (Plexus opcodes)   │
│  D = 1024        │         │  variable length             │
└────────┬─────────┘         └──────────┬───────────────────┘
         │                              │
         │ similarity / retrieval       │ execute on 2PDA
         │                              │
         ▼                              ▼
┌──────────────────┐         ┌──────────────────────────────┐
│  Nearby intents  │         │  Cell write (LINEAR / AFFINE)│
│  in Pask graph   │         │  K1/K4/K5 enforced           │
└────────┬─────────┘         └──────────┬───────────────────┘
         │                              │
         │ interact()                   │ interact()
         │                              │
         └──────────────┬───────────────┘
                        ▼
┌────────────────────────────────────────────────────────────┐
│  Pask graph: edge weight accumulates; node ΔH updates;     │
│  region expansion propagates; periodically stability check │
└────────────────────────────────────────────────────────────┘
```

Three layers, three guarantees, one coherent pipeline:

- **HRR** answers *"what intents resemble this one?"* — used for retrieval, autocomplete, "did you mean…"
- **2PDA** answers *"is this intent authorized and what does it commit?"* — used for execution, provenance, anchoring
- **Pask** answers *"what patterns have settled across all observed intents?"* — used for stable-thread surfacing, proactive scheduling (in the music pass per the memory), trust accumulation

Each layer is **independently usable**. A diagnostic tool that just needs similarity scoring can use only HRR. A pure-execution path (e.g. a known bytecode program) can run on just the 2PDA. A passive observability service can drive Pask without running anything else.

The substrate combines them because the *full* lifecycle — speak an intent, verify it, execute it, learn from it — needs all three.

---

## 35.6 What Each Kernel Is Not

Common conflations the public framing invites:

| Conflation | Correction |
|---|---|
| "The 2PDA learns over time" | No. The 2PDA is a *pure* execution kernel. Learning is Pask's job. |
| "Pask is an ML model" | No. Pask is a substrate. No backprop. No objective. |
| "HRR is a neural embedding" | No. HRR is a deterministic algebraic encoding. No training data, no model weights. |
| "Pask replaces the GA genome" | No (per memory `semantos_hrr_design_decisions.md`). HRR coexists with pask-ga's genome; both stay alive. |
| "All three kernels run in one WASM" | Only in the optional `pask-and-cell.wasm` combined build. The default packaging is three sibling modules. |
| "Pask predicts the next intent" | No. Pask reports what's *settled*. Forward-projection is the music pass's job (per the same memory). |

The line between "what's settled" (Pask) and "what's next" (music) is the load-bearing distinction in the memory entry. Both are needed; they're not the same operation.

---

## 35.7 Coexistence with pask-ga (the GA Line)

The earlier pask-ga work uses genetic-algorithm operators (mutation, crossover, fitness selection) over a `genomeKey()`-derived representation of pask nodes. A collaborator's research line depends on this. Per memory `semantos_hrr_design_decisions.md`:

> HRR vectors **co-exist** with the pask-ga genome slot rather than replacing it. The genome is kept intact for the GA clustering/crossover use case (a collaborator actively uses it). SIR-derived nodes carry both; a flag distinguishes which is present.

So a Pask node, post-HRR-integration, can carry:

- An HRR vector (D=1024 Float64Array) — *similarity primitive*, set on SIR-derived intent nodes
- A genome key (`genomeKey()` output) — *GA primitive*, set on nodes participating in evolutionary search
- Both (with a flag distinguishing which is canonical for that node)

The runtime decision of which to use is per-operation:

- *Find nearby intents* → HRR cosine over vectors
- *Cluster solutions* → genome-distance over keys
- *Crossover candidate pairs* → genome operators
- *Settle on what's stable* → ΔH/region-expansion (transparent to both)

Don't migrate or deprecate the genome. HRR is additive.

---

## 35.8 Why the Podcast Missed Two of Three

The fact-check sweep on 2026-05-13 (`docs/prd/UNIFICATION-ROADMAP.md` §11) noted that the public podcast framing names only the 2PDA — Pask and HRR are absent entirely from the public architecture story. This is a presentation gap, not a code gap: both kernels are shipped, both have conformance tests, both are used by extensions.

The omission distorts the system's perceived shape in three ways:

1. **Determinism becomes the only guarantee.** Without naming Pask, the "the system learns from interactions" property has no home, and listeners assume the cell engine itself learns (it doesn't).
2. **Similarity becomes invisible.** Without naming HRR, the "show me intents like this one" capability has no obvious mechanism, and listeners assume an LLM is doing it (it isn't — HRR is deterministic).
3. **The music pass has nowhere to land.** The "proactive scheduling" idea (per memory `semantos_hrr_design_decisions.md`) needs both stable patterns from Pask and temporal projection from the music pass; the public framing has nowhere to put either.

Naming all three is the cheapest fix. They're already implemented. The doc is where they live.

---

## 35.9 Sources Referenced

- `core/cell-engine/` — 2PDA implementation
- `core/cell-engine/OPCODE-HARDENING-PLAN.md` — K1/K4/K5 opcode discipline
- `core/cell-ops/dist/opcodes.d.ts` — Plexus opcodes 0xC0–0xCF
- `core/pask/README.md` — Pask kernel summary + chess conformance test
- `core/pask/PRIMER.md` — reader's guide; non-claims; model in five lines
- `core/pask/src/` — Zig implementation
- `core/hrr/src/index.ts` — public API (encodeSIRProgram, bind, unbind, cosine, D)
- `core/hrr/src/encode.ts` — Plate 1995 encoding; slot mapping; cross-domain orthogonality
- `core/semantos-ir/` — IRProgram / IRBinding types HRR consumes
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — K1/K4/K5 invariants
- `docs/prd/UNIFICATION-ROADMAP.md` §11 — fact-check that motivated this chapter
- Memory `semantos_hrr_design_decisions.md` — HRR + pask-ga coexistence
- Memory `semantos_pask_layering.md` — Pask as kernel-layer, not extension

Three kernels. Three guarantees. Three lifecycles. Pick the right one for the question you're asking.
