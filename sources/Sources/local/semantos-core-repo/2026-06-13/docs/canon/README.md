---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.624637+00:00
---

# `docs/canon/` — the structured-data kernel

**Status:** scaffold. Schemas defined; entries minimal; no canonical
decisions yet. The next-session deliverable is to land canonical
definitions and start hydrating downstream artifacts (textbook chapters,
spec sections, paper drafts) from this directory.

**Audience:** internal. Not a public artifact.

---

## What this is

The textbook, the protocol spec, the paper portfolio, and the website
all describe the same primitives — cells, identity, capability tokens,
the IR pipeline, the kernel invariants. Today those descriptions drift
between docs (`cell` vs `LoomObject` vs `SemanticObject`; `hat` vs
`facet`; `IR` vs `SIR` vs `OIR` used inconsistently).

`docs/canon/` is the single source of truth for the structured
backbone. Each downstream artifact is a *render* of canon plus
artifact-specific prose:

```
                                                 ┌──────────────────┐
                                       ┌────────►│ textbook chapter │
                                       │         └──────────────────┘
                                       │
   ┌──────────────────┐    ┌─────────────────┐   ┌──────────────────┐
   │ docs/canon/*.yml │───►│ render/*.ts     │──►│ protocol spec    │
   │  (structured)    │    │  (composes      │   └──────────────────┘
   │                  │    │   prose +       │   ┌──────────────────┐
   │                  │    │   data)         │──►│ paper section    │
   └──────────────────┘    └─────────────────┘   └──────────────────┘
                                       │         ┌──────────────────┐
                                       └────────►│ glossary appendix│
                                                 └──────────────────┘
```

Drift goes to zero because the structured fields (definitions, BRC
mappings, opcode tables, K-invariant statements, deliverable status)
are defined once and cited by id everywhere.

The doc plan (`docs/SEMANTOS-DOC-PLAN.md`) describes the artifacts.
The unification roadmap (`docs/prd/SEMANTOS-UNIFICATION-ROADMAP.md`)
describes the matrix and per-deliverable IDs. This directory is what
both consume.

---

## Files

| File | Owns | Schema |
|---|---|---|
| `glossary.yml` | Canonical terms, aliases, definitions, source refs | §[Glossary](#glossaryyml) |
| `theorems.yml` | K1–K10 invariants, statements, Lean refs, status | §[Theorems](#theoremsyml) |
| `opcodes.yml` | Full opcode table (standard 0x00–0x4B + Plexus 0x4C–0xD0) | §[Opcodes](#opcodesyml) |
| `boot-sequence.yml` | The 15-step canonical boot, each step annotated with deliverables it depends on | §[Boot sequence](#boot-sequenceyml) |
| `adapter-matrix.yml` | IoT × VPS × Full Node × {Storage, Identity, Anchor, Network} | §[Adapter matrix](#adapter-matrixyml) |
| `unification-matrix.yml` | Live status of every (surface, axis) cell from the unification roadmap | §[Unification matrix](#unification-matrixyml) |
| `deliverables.yml` | D-V1, D-A0, ..., D-G3 — structured (id, owner, deps, status) | §[Deliverables](#deliverablesyml) |
| `lexicons.yml` | The 8 lexicons + Lean refs + dev status | §[Lexicons](#lexiconsyml) |
| `brc-mapping.yml` | BRC-42/52/100/108/etc → repo location + spec section | §[BRC mapping](#brc-mappingyml) |
| `examples/` | Worked examples reused across artifacts (each as `.md` + executable companion) | §[Examples](#examples) |
| `render/` | Scripts that turn canon into MD/LaTeX/whatever | §[Renderers](#renderers) |

All YAML files are sorted: list-of-entries shape with stable `id` keys.
Sort canonically before commit so diffs are readable.

---

## Schemas

### `glossary.yml`

```yaml
- id: cell                          # stable identifier; never changes
  canonical: null                   # the chosen primary spelling — null until decided
  aliases:                          # all known variants in the codebase + docs
    - cell
    - LoomObject
    - SemanticObject
  definition: null                  # filled during the canonical-decision pass
  short: |                          # one-line summary; safe to draft now
    Primary type of the 2-PDA cell engine; 1KB max with 256-byte header.
  sources:                          # repo paths or doc paths where this term appears
    - core/cell-engine/src/cell.zig
    - docs/PIPELINE.md
    - docs/Semantos-Protocol-Spec-v0.01.docx
  notes: |                          # optional working notes for the glossary editor
    Some older docs use SemanticObject. The TS world-client app uses
    LoomObject. Production code paths are 'cell' across cell-engine,
    plexus-vendor-sdk, and the protocol spec — leaning toward 'cell'
    as canonical.
  related:                          # cross-references to other glossary ids
    - cell-header
    - linearity
```

### `theorems.yml`

```yaml
- id: K1
  name: Linearity enforcement
  status: proven                    # proven | model-checked | sketched | TODO
  layer: kernel                     # kernel | distributed | recovery | metering
  statement: |
    No cell of LINEARITY=LINEAR may be DUP'd or DROP'd in the
    bytecode-execution semantics of the 2-PDA cell engine.
  lean_file: proofs/lean/Semantos/Theorems/LinearityK1.lean
  tla_file: null                    # null if not also model-checked
  tested_in:                        # repo paths of conformance / golden tests
    - core/cell-engine/tests/linearity_test.zig
  related: [K2, K7]
```

### `opcodes.yml`

```yaml
- code: 0x00
  name: OP_FALSE
  category: standard                # standard | plexus | reserved
  source: bitcoin                   # bitcoin | plexus | semantos | reserved
  pops: 0
  pushes: 1
  description: Push false (empty byte vector).
  reference: BRC-43 §2
  notes: null
```

### `boot-sequence.yml`

```yaml
- step: 1
  title: User provides email + answers challenges
  enables: ["P1a", "Plexus existing"]
  status: complete
  description: |
    User-facing identity registration. PBKDF2 100k iterations on
    device. No private material crosses the network.
  references:
    - "Plexus Tech §1, §11"
    - core/identity-ports
  unblocks: [step-2, step-3]
```

### `adapter-matrix.yml`

```yaml
deployments:
  - id: iot
    name: IoT (esp32-class)
    storage: tiny embedded KV
    identity: hardware-backed seed
    anchor: relayed via VPS
    network: BLE / LoRa / WiFi
    kernel: cell-engine-embedded.wasm (29 KB)
  - id: vps
    name: VPS-tier sovereign node
    ...
```

### `unification-matrix.yml`

```yaml
substrate:
  - id: U1
    name: Cell Engine (Zig WASM)
    axes:
      A: { status: ✓, note: "BCA derive" }
      B: { status: ✓, note: "PDA + cell" }
      C: { status: n/a }
      D-sub: { status: ✓, note: "K1 gate" }
      D-lex: { status: ⚠, deliverable: "via SIR upcall" }
      ...
adapters:
  - id: A1
    name: World Host (OTP)
    axes:
      A: { status: ⚠, deliverable: D-A1 }
      ...
```

Each row carries its per-axis cells under `axes:` (not `cells:`). The
renderer at `docs/canon/render/matrix-to-roadmap.ts` turns this back
into the §2 matrix tables in the unification roadmap.

### `deliverables.yml`

```yaml
- id: D-V1
  title: VerifierStub interface + reference implementation
  phase: 0.5
  status: pending                   # pending | in_progress | merged | superseded
  owner: null                       # pr URL when in flight
  blocks: [D-A1, D-V3]
  description: |
    Define BRC-100 verification protocol as a TS interface...
  acceptance: |
    ...
  pr: null                          # github URL when merged
  references:
    - core/identity-ports/src/types.ts
```

### `lexicons.yml`

```yaml
- id: jural
  status: built                     # built | partial | planned
  lean_file: proofs/lean/Semantos/Lexicons/Jural.lean
  ts_file: extensions/jural/src/lexicon.ts
  description: |
    Hohfeldian decomposition of legal acts. The canonical lexicon —
    the example used in the textbook to teach the lexicon pattern.
  obligations:                      # M1, M2, ... per the FORMAL-VERIFICATION-STRATEGY
    - obligation: M1
      status: proven
      lean_ref: "JuralLexicon.M1_HeaderInjective"
```

### `brc-mapping.yml`

```yaml
- id: BRC-42
  name: Client-side key derivation
  domain: identity
  status: implemented               # implemented | partial | not-yet
  upstream_url: https://brc.dev/brc-0042
  semantos_paths:
    - core/plexus-vendor-sdk/src/crypto.ts
    - core/cell-engine/src/bca.zig
  textbook_chapter: 4
  spec_section: "v0.5 §4.1"
  notes: |
    Used for both root-seed reconstruction (PBKDF2 100k) and
    deterministic child derivation under a parent cert.
```

### Examples

Worked examples live as `examples/<name>.md` (the prose) plus an
executable companion (`.ts`, `.sh`, etc.) when the example is meant
to run. Filenames are stable; chapters cite them by basename.

| Example | Used in |
|---|---|
| `examples/handyman-intake.md` | Chapter 2 + Paper A1 |
| `examples/boot-sovereign-node.md` | Chapter 27 (canonical demo) |
| `examples/kanban-30min.md` | Chapter 28 (build your first adapter) |
| `examples/pm-tradie-dispatch.md` | Chapter 29 + Paper C4 |

---

## Renderers

Run from the repo root (or this directory — they accept either):

```bash
bun docs/canon/render/glossary-to-md.ts > docs/textbook/appendix-A-glossary.md
bun docs/canon/render/matrix-to-roadmap.ts \
  > /tmp/matrix.md   # then merge into docs/prd/SEMANTOS-UNIFICATION-ROADMAP.md §2
```

Renderers are intentionally thin: they parse YAML, format MD, exit.
No template engine, no string interpolation framework. Add a new
renderer per artifact format as needed (e.g. `glossary-to-tex.ts`
for paper appendices when that arrives).

---

## How to update canon

1. **Adding an entry**: edit the relevant `.yml`; preserve sort order
   by `id`. Open a small PR, label `canon`. The PR description should
   say which downstream artifacts will need re-rendering.
2. **Promoting a deliverable**: change `status: pending` →
   `status: merged` and fill `pr:` in `deliverables.yml`. Re-run
   `matrix-to-roadmap.ts`. Commit the regenerated MD alongside the
   YAML change.
3. **Resolving a glossary canonical**: pick a `canonical:` value from
   the `aliases:` list, fill `definition:`. Document the decision in
   `notes:` (one-line "Decided 2026-XX-XX, reason: ...").
4. **Never** edit the rendered downstream MD directly when the change
   originates in canon — edit canon, regenerate. The render is the
   committed output, not a hand-edited document.

---

## Stages of completion

Tracking the rig itself separately from the content it holds.

| Stage | What's done | Where |
|---|---|---|
| **0 — scaffold** | Directory + empty YAML files + README + two renderer stubs | This PR |
| **1 — initial fill** | ~50 high-drift terms in `glossary.yml` (no canonicals yet); K1–K10 entries in `theorems.yml` (statements only); the 15-step boot sequence stubbed; the §2 unification matrix translated to YAML | Next session, day 1 |
| **2 — canonical decisions** | Glossary canonicals chosen per term (Todd's call); §8 governance Q's resolved; `protocol-v0.5.md` cut from canon | Next session, day 2 |
| **3 — first artifact** | Refreshed whitepaper v3 hydrated from canon (per doc plan §2 weeks 2–3) | Subsequent sessions |
| **4 — textbook spine** | Chapters 1–14 drafted, each from a closed input set per the agent draft-brief template | Subsequent sessions |
| **5 — paper portfolio** | A1, A2, A3 drafts on arXiv | Subsequent sessions |

Currently at stage 0.
