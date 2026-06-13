---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/RESTRUCTURING-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.334937+00:00
---

# Semantos Restructuring Plan

*A response to Damian's "this repo is all over the shop" feedback. Plan-only — no code moves in this pass.*

## TL;DR

The repo contains a genuinely clean core (a 185 KB Zig/WASM VM plus a working TypeScript IR pipeline) wrapped in a sprawl of 28 packages, 27 git worktrees, and a pile of loose HTML prototypes at the root. The README documents 7 packages; there are actually 28. **React is not the coupling problem** — it's already quarantined to `packages/loom/`. The real problems are:

1. There's no named boundary between "core" (pipeline + WASM + shell runtime) and "apps" (games, mud, piggybank, poker-agent, navigation_app, settlement, loom), so everything feels equally weighted.
2. The **dual IR pipeline** (SIR → OIR → opcodes) is only half-wired: OIR is live, SIR is typed but dormant (nothing calls `lowerSIR()`).
3. The README overstates what's integrated — readers can't tell what's load-bearing vs. experimental.
4. 10 packages have zero workspace importers (consumed only by gate tests or reserved for future integration). That's fine, but it needs to be *said*.

The good news: a clean `semantos-core` is achievable without rewriting anything. It's mostly a renaming, a quarantine line, and a documentation rewrite. The Svelte scaffold is trivial because loom already exposes framework-free service classes that the React UI wraps via `useSyncExternalStore` — Svelte can wrap the exact same services.

---

## 1. Current state, honestly

### What exists

| Layer | Status | Location |
|---|---|---|
| Zig/WASM 2-PDA VM (185 KB full, 29 KB embedded) | **Shippable today.** 13 exports, no Node/DOM dependencies. | `packages/cell-engine/zig-out/bin/cell-engine.wasm` |
| TypeScript compiler: Lisp → OIR → opcode bytes | **Live.** Golden-file tested. | `packages/semantos-ir/` + `packages/shell/src/lisp/` |
| Dual IR (SIR above OIR) | **Dormant.** Types defined, no caller. | `packages/semantos-sir/` |
| Shell (REPL + one-shot CLI + 30+ verbs) | **Built and wired.** `semantos-shell` binary. | `packages/shell/` |
| Loom (three-panel React UI, services, LoomStore) | **Built.** Only React-using package in the repo. | `packages/loom/` |
| Lean/TLA+ formal proofs | **Maintained.** K1–K5, K7 invariants + 7 TLA specs. | `proofs/` |

### What's sprawl

- **28 packages, ~10 with zero workspace importers** (metering, recovery, scada, consciousness, semantos-sir, settlement, piggybank, mud, poker-agent, navigation_app). Some are reserved library leaves (metering, recovery); others are standalone apps (piggybank, mud, poker-agent, navigation_app).
- **27 git worktrees in `.claude/worktrees/`** (affectionate-hodgkin, angry-villani, …). Each is a full repo copy. Noisy for grep and for Damian's first impression.
- **Loose HTML at root**: `chess-stakes-viewer.html`, four `prd-*.html` files, `prd-analysis-data.json`, `multipane_viewer_testing/`, `navigation-reviews/`. None are built or referenced. Archive or delete.
- **README overstates integration.** It lists 7 packages and a tidy dependency graph; reality is 28 packages, several orphan leaves, and a second IR layer that isn't wired.

### What React/frontend coupling actually looks like

Better than Damian implied. Only `packages/loom/package.json` declares `react` / `react-dom` (both at 19.0.0). No other package imports React, DOM APIs, or browser globals. The shell even has an explicit `// Never import React` comment in `packages/shell/src/formatters.ts`. The only cross-cutting dependency is that `shell` imports service classes (`LoomStore`, `FlowRunner`, `IdentityStore`, `ConfigStore`, …) from `@semantos/loom`. Those service classes are framework-free and documented as such. The fix is a name change: extract the services from `loom/` into a new `@semantos/services` (or fold them into `core-runtime/`), and loom becomes purely the React wrapper on top.

---

## 2. Proposed target structure

Four tiers. Every directory has a single reason to exist.

```
semantos/
├── core/                          # the thing you can compile, ship, and sell
│   ├── cell-engine/               # Zig/WASM VM — unchanged
│   ├── cell-ops/                  # opcode enum + WASM interface
│   ├── semantos-ir/               # OIR: opcode IR (ANF)
│   ├── semantos-sir/              # SIR: semantic IR — to be wired
│   ├── protocol-types/            # cell headers, WASM contract, interfaces
│   ├── constants/                 # single-source codegen → Zig + TS
│   ├── compiler/                  # moved from src/compiler — consumption rules
│   └── types/                     # moved from src/types — LINEAR/AFFINE/RELEVANT
│
├── runtime/                       # entry surfaces built on core
│   ├── shell/                     # REPL + CLI + verbs (currently packages/shell)
│   ├── services/                  # framework-free stores/services (from loom)
│   └── node/                      # daemon + admin API (currently packages/node)
│
├── extensions/                    # domain algorithms that EXTEND core, optional
│   ├── policy-runtime/
│   ├── cdm/                       # ISDA CDM
│   ├── extraction/                # grammar-inference engine
│   ├── metering/                  # 8-state FSM
│   ├── recovery/                  # export + challenge
│   ├── scada/                     # industrial control
│   └── navigation/ + navigator/   # semantic navigation layer
│
└── apps/                          # everything you can SHIP to end users
    ├── loom-react/                # current packages/loom, renamed
    ├── loom-svelte/               # NEW scaffold — stub that consumes runtime/services
    ├── games/ + game-sdk/
    ├── mud/
    ├── piggybank/                 # incl. esp32-hackkit firmware
    ├── poker-agent/
    ├── settlement/
    └── navigation-app/            # Flutter
```

Three structural invariants this enforces:

- **`core/` imports nothing outside `core/`.** Any package in core that reaches into an extension or app is a bug.
- **`runtime/` imports only `core/`.** This is the line where the sellable library ends and the integration surface begins.
- **`apps/` imports anything. No app may import another app.** This is the line where "it's a product, not a library" starts.

`extensions/` sits between runtime and apps — they may import core and runtime, and apps may import them, but core may not. This is where domain-specific paid extensions live (per your commercial note).

### Why this split survives the commercial uncertainty

You said: "I want to find something useful to sell, but then monetise extensions for domain-specific businesses. MVP may be the app and something that replaces the webserver." The shape above works for every version of that:

- If the MVP is a **library + WASM** (Damian's art-project case, or a SaaS core): ship `core/` + `runtime/services/` + the WASM artifact. Apps and extensions stay out.
- If the MVP is **an app + replacement webserver**: ship `apps/loom-svelte/` (or whichever app becomes the hero) + `runtime/node/` + `core/`. The "webserver replacement" is just `runtime/node/` serving the shell over HTTP/WS.
- If the commercial wedge turns out to be **per-domain extensions** (CDM for finance, SCADA for industry, CDM for games): `extensions/` is where each SKU lives, priced and gated independently. Core stays free/OSS; extensions become the licensed layer.

You don't have to decide which wedge yet. You do have to make the boundaries real so the decision can be made later without a second rewrite.

---

## 3. Package classification (all 28)

Actions per package. "Move" means rename the directory under the new tree; "Archive" means move to `archive/` or delete with a note in CHANGELOG; "Wire" means the code exists but needs to be imported by something.

### core/ (9 packages)
| Package | Action | Note |
|---|---|---|
| cell-engine | Move | Zig/WASM kernel, keeps its build.zig |
| cell-ops | Move | opcode enum + WASM interface |
| semantos-ir | Move | OIR — live |
| semantos-sir | Move + **Wire** | SIR — types only; `lowerSIR()` has no caller. See §4 |
| protocol-types | Move | hub type layer |
| constants | Move | codegen utility |
| (new) `core/compiler` | Move from `src/compiler/` | consumption rule validation |
| (new) `core/types` | Move from `src/types/` | LINEAR/AFFINE/RELEVANT |
| `src/ffi/` | Inspect then move | haven't audited; likely belongs in core |

### runtime/ (3 packages)
| Package | Action | Note |
|---|---|---|
| shell | Move | REPL + CLI. Currently imports services from loom — redirect to `runtime/services` after extraction |
| node | Move | node daemon; top-level entry, no internal importers |
| (new) runtime/services | **Extract** from `packages/loom/src/services/` + `state/` + `engine/` | framework-free stores; loom's own readme already says these are usable from plain TS |

### extensions/ (7 packages)
| Package | Action | Note |
|---|---|---|
| policy-runtime | Move | imported by cdm, scada |
| cdm | Move | ISDA CDM; imported by shell |
| extraction | Move | grammar inference; imported by shell |
| metering | Move + **Document** | no workspace importers; referenced by phase11.5 gate. Either wire into shell or mark "reserved, tested via gate" |
| recovery | Move + **Document** | same shape as metering; referenced via phase26a gate |
| scada | Move + **Document** | no importers; domain package. Commercial candidate for an extension SKU |
| navigation + navigator | Move together | navigator depends on navigation; keep as a pair |

### apps/ (8 packages)
| Package | Action | Note |
|---|---|---|
| loom (React) | Rename → `apps/loom-react` | stop importing shell from loom; let shell be the top-level entry instead |
| (new) apps/loom-svelte | **Scaffold** | Svelte+Vite stub that imports from `runtime/services`. See §6 |
| games + game-sdk | Move together | game-sdk depends-up from games |
| mud | Move | standalone app, no importers |
| piggybank | Move (incl. `esp32-hackkit/`) | consolidate the ESP32 firmware under its owning app |
| poker-agent | Move | Claude-driven poker |
| settlement | Move | only importer is itself |
| navigation_app | Move | Flutter; lives alongside other apps but has its own toolchain |

### Archive / delete
| Item | Action | Note |
|---|---|---|
| consciousness | Archive | experiment; no importers; interesting but not load-bearing |
| `chess-stakes-viewer.html` | Delete or `archive/prototypes/` | orphan |
| `prd-*.html` + `prd-analysis-data.json` | Move to `docs/prd/analyses/` | useful history, wrong location |
| `multipane_viewer_testing/` | Archive | old testing artifact |
| `navigation-reviews/` | Move to `docs/reviews/` | notes, not code |
| `platforms/`, `include/` | Inspect | likely Zig include paths — confirm and document or remove |
| `.claude/worktrees/*` (27 of them) | **Prune** | each is a full repo copy; review, keep any active ones, delete the rest |

### Keep in place
`configs/taxonomy/` (runtime config), `proofs/` (formal verification artifacts), `docs/` (with reorganization, see §5), `__tests__/` (cross-package gates; rename to `tests/gates/` under the new root).

---

## 4. NL → IR → opcodes pipeline documentation map

The pipeline is already specified in `docs/SEMANTIC-IR-ARCHITECTURE.md` — but the doc describes the intended shape (including SIR) and reality only implements half. The plan needs two things: (1) make the pipeline truthful on the page, (2) wire SIR so truth and page match.

**Current live flow:**
```
Lisp source  ──parser.ts──▶  ConstraintExpr (AST)
             ──compiler.ts──▶ IRProgram (OIR, ANF bindings)
             ──emit.ts──────▶ Uint8Array (opcode bytes, 0x4C–0xD0)
             ──cell-engine──▶ 2-PDA execution (Zig/WASM)
```

**Intended flow (docs):**
```
NL / voice / signals
  │
  ▼
Surface grammar  (Lisp ✓ │ LaTeX ✗ │ Lean-ish ✗ │ Ricardian ✗ │ EDI ✗)
  │
  ▼
SEMANTIC IR (SIR)  — jural categories, trust tier, execution authority, proof requirement
  │
  ▼  lowerSIR()  ← no caller today
  │
OPCODE IR (OIR, ANF)
  │
  ▼  emit()
  │
Opcode bytes
  │
  ▼
Cell Engine (Zig/WASM, 2-PDA)
```

**What "compression gradient" means, on paper.** Each stage compresses the previous: a paragraph of NL → dozens of SIR bindings → dozens of OIR bindings → hundreds of bytes of opcode. Claim-to-prove: the same intent lowered through two different surface grammars (Lisp and LaTeX, say) produces OIR programs that are equivalent under α-renaming. This is the structural argument that the pipeline *compresses meaning* rather than just encoding syntax. It's also what justifies monetizing extensions — a paid LaTeX front-end can be added without forking core if the golden-file equivalence holds.

**Doc deliverables this pass:**
1. **`docs/PIPELINE.md`** — one canonical doc showing the diagram above, with file pointers for each stage and an explicit "built / dormant / not started" label next to each surface grammar.
2. **`docs/PIPELINE-SIR-WIRING.md`** — design note for the first call to `lowerSIR()`. Minimum viable: the Lisp compiler emits trivial SIR bindings (`declaration` for every top-level form, `condition` for every guard) and then lowers SIR → OIR via identity. This is a no-op at runtime but establishes the seam.
3. **Strike or rewrite the README dependency graph.** It's misleading. Replace with the full graph based on §3.

---

## 5. Shell / RPL / CLI documentation map

The shell has no single doc describing what it *is* today. It has two architectural docs (`SHELL-SESSION-ARCHITECTURE.md`, `SHELL-ALIGNMENT-VS-ARCHITECTURE-VISION.md`) that read as future-state specs.

**Doc deliverables:**
1. **`docs/SHELL.md`** — single entry point. One page: what `semantos-shell` is, the three modes (REPL / one-shot CLI / watch), the verb categories, how to install and run. Link out to deeper docs.
2. **`docs/SHELL-VERBS.md`** — auto-generate if possible, manual otherwise. The REPL's `HELP_TEXT` (repl.ts:44–82) already has this in source; extract it.
3. **Mark watch mode as "stub."** The `StoreBridgeServer` exists but no user-facing `semantos watch` command ships. Be honest on the page.
4. **Document the binary.** `package.json.bin.semantos-shell → dist/index.js`. State it. A new reader has to guess right now.

The shell is the *most useful* surface to hand Damian — he can clone, `bun install`, `bun run build`, and have a working REPL against the WASM kernel in minutes. That user journey deserves a QUICKSTART.

---

## 6. React quarantine + Svelte scaffold

Short because Agent 3's finding was definitive: React touches only `packages/loom/`. Core is already React-free.

**Two-step extraction:**

1. **Split loom.** Move `packages/loom/src/services/`, `state/`, `engine/`, `identity/`, and `commands/` (if framework-free — spot check needed) into `runtime/services/`. Those directories already expose classes that work without a DOM; loom's own docs say so. What remains in `apps/loom-react/` is: `canvas/`, `sidebar/`, `inspector/`, `shell/` (the app shell, not the semantos shell), and the Vite config. After the split, `apps/loom-react` has ~96 .tsx files and depends on `runtime/services` + React, nothing else.

2. **Scaffold `apps/loom-svelte/`.** Minimal initial target: a single-panel Svelte app that instantiates `LoomStore` from `runtime/services`, lists the object taxonomy, and emits shell commands. Not feature-parity. Just a demonstration that Svelte can consume the services. Damian can extend from there. Suggested stack: SvelteKit + Vite + TypeScript strict. No Tailwind initially — let Damian pick.

**Cost:** Extraction is mostly `git mv` + updating import paths. The services have no React internals to strip. Estimated <1 day of focused work; put it in the migration plan as Phase 2.

---

## 7. WASM artifact for Damian's art projects

Confirmed: both profiles exist on disk right now.

```
packages/cell-engine/zig-out/bin/cell-engine.wasm             185,818 bytes
packages/cell-engine/zig-out/bin/cell-engine-embedded.wasm     29,613 bytes
```

29 exports (13 kernel + 16 debug/cell/BCA/SPV/capability), 9 host imports. The embedded profile uses host-provided crypto — ideal for a browser art project that already has crypto libraries loaded. The full profile is standalone. No Node, no DOM, no React dependency in the artifact itself.

**For Damian specifically:** give him `cell-engine-embedded.wasm` + `packages/protocol-types/src/wasm-contract.ts` (the 13 required exports and their types) + a 40-line `index.html` that `instantiateStreaming`s the module and pushes bytes onto the stack. That's a 10-minute onboarding. We can ship a `apps/demo-wasm-playground/` as part of this restructuring to make it copy-pasteable.

**Caveat worth saying out loud:** the WASM kernel is a *2-PDA script executor*, not a semantic engine. If Damian wants CT primitives (conversation theory) exposed as WASM functions — which is what he seemed to mean — those would have to be compiled down to cell scripts and loaded via `kernel_load_script`. The compression-gradient claim is exactly what makes that possible; but it means the "CT-as-WASM-module" story is really "CT-as-a-program-run-by-the-WASM-module." Worth clarifying with him before he builds against the wrong mental model.

---

## 8. Staged migration plan

Three phases, each independently shippable. No phase breaks builds.

### Phase 1 — Paper only (this document + followups)
*Goal: make the repo legible without moving a file.*

- Ship this plan.
- Rewrite README to match reality (28 packages, honest dependency graph, honest status per package).
- Write `docs/PIPELINE.md` and `docs/SHELL.md`.
- Prune the 27 worktrees (keep any actively in use, archive the rest).
- Move loose HTML to `archive/prototypes/` or `docs/prd/analyses/`.

*Risk: near zero. Cost: 1–2 days.*

### Phase 2 — Extract services, scaffold Svelte
*Goal: prove the quarantine boundary is real by building something against it.*

- Create `runtime/services/` as a new workspace package. Move loom's framework-free code into it.
- Update loom's imports to consume `runtime/services`. Update shell's imports.
- Scaffold `apps/loom-svelte/` with a minimal object-browser.
- Ship a `apps/demo-wasm-playground/` (static HTML + the embedded WASM) for Damian.

*Risk: medium — touches imports across shell, loom, node. Gate with the existing phase tests.*
*Cost: 3–5 days.*

### Phase 3 — The big rename
*Goal: the directory tree reflects the architecture.*

- Introduce `core/`, `runtime/`, `extensions/`, `apps/` as top-level directories.
- Move packages into place via `git mv` + `pnpm-workspace.yaml` update. One PR per tier to keep diffs legible.
- Add enforcement: a pre-commit or CI check that `core/*` has no imports outside `core/`, and `runtime/*` has no imports outside `core/` or `runtime/`.
- Rename `@semantos/loom` → `@semantos/loom-react`. Deprecate old name with a re-export shim for one release.
- Wire SIR (the trivial identity-lowering pass described in §4).

*Risk: higher — lots of path churn. Publish a branch for Damian to preview.*
*Cost: 1 week.*

---

## 9. Commercial wedge (keeping options open)

You said you haven't picked the monetization angle. The structure above doesn't force a pick. But a few observations worth carrying forward:

- **If core is OSS and extensions are paid:** the current `extensions/` candidates that look most sellable are `cdm` (financial derivatives / ISDA compliance — regulated industries pay for this), `scada` (industrial SCADA — big margins, small number of buyers), and `extraction` (grammar inference — sellable as a consulting + platform bundle). `metering` and `recovery` are plumbing, not products.
- **If the MVP is an app:** the current app most advanced toward production is `loom-react`. But loom is a developer tool, not a product. The nearest-to-shippable *end-user* app looks like `piggybank` (has firmware, clear use case) or a yet-to-build Svelte app targeted at Damian's education-space ambition.
- **"Replace the webserver" reading:** `runtime/node/` + `runtime/shell/` can already serve shell sessions over a store-bridge. Framing this as "semantic backend replacing Express" is a credible positioning; needs a doc and a demo.

None of these bets need to be made now. They all survive the restructure.

---

## 10. Open questions for you

Marked in priority order. These are decisions the plan can't make without you.

1. **SIR urgency.** Wire SIR in Phase 3 (trivial identity lowering), or defer until a second surface grammar lands and the compression claim actually needs testing? Defer is cheaper, wire-now is what Damian would expect the repo to demonstrate.
2. **Worktree purge scope.** Can I propose deleting all 27 `.claude/worktrees/*` in Phase 1, or are some still in use?
3. **"Extracted but orphan" packages.** metering, recovery, scada, consciousness, settlement, piggybank, mud, poker-agent, navigation_app all have zero workspace importers. Keep all, archive some, or delete some? My default: keep metering/recovery/scada (gate-tested or reserved), archive consciousness, move the rest into `apps/`.
4. **Default app target for a demo.** For the Svelte scaffold — object browser (closest to loom), or something closer to Damian's education interest (interactive conversation-theory sandbox)?
5. **README rewrite — in this branch or a separate one?** Rewriting README is the single highest-ROI move for external legibility. I'd do it first, before the renames, so Damian (and any future external reader) sees the honest picture immediately.

---

*End of plan.*
