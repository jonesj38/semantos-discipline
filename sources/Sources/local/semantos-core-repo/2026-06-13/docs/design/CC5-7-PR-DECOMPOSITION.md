---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CC5-7-PR-DECOMPOSITION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.743560+00:00
---

# CC5–CC7 — PR Decomposition & Sequencing

**Version**: 0.3 (2026-05-19 — adds the verified preservation boundary / coupling map: FSM + conversation are the stable spine; ratify-handler the one coupled surface; name-preserving CC5.B2 safety)
**Date**: 2026-05-19
**Status**: SPEC ONLY — **not gated on CC4** (≈done: `extensions/` gone, oddjobz canonical) and **not on any parallel session** (none — single Todd stream). A *wave-execution decomposition*, **not** a parallel roadmap (roadmap is generated from `docs/canon/unification-matrix.yml` via `render/matrix-to-roadmap.ts`).
**Governs:** the three specs — `CC5-SCHEMA-SECTION-IMPL-SPEC.md` **v0.3**, `CC6-SOURCE-ADAPTER-IMPL-SPEC.md` **v0.2**, `CC7-SCHEMA-RENDERER-IMPL-SPEC.md` **v0.2**
**Discipline source:** `docs/canon/commissions/wave-canonical-cartridge.md` §2 (binding), §3 (CC-rows), §4 (acceptance 7–9)

---

## 1. The one rule

CC5–CC7 are the **data/UI half of the ratified canonical-cartridge model** (CANONICAL-
CARTRIDGE-MODEL C2/§4.3, amendment ratified 2026-05-19). They **plug already-landed seams**,
do not re-decide anything. As of 2026-05-19 the cell-identity half is **built and merged by
tessera-P3** (do not rebuild):

- `substrate_entity.registerSpec` additive registry — **P3a #458 (merged)**.
- `cartridge_boot.registerCells` boot pass + `tessera_cell_specs.zig` reference —
  **P3b #460 (merged)**.
- octave escalation is the **default** mint/read path (`UNIVERSAL-CARTRIDGE-BOOT` §3.6) —
  no carrier *mechanism* to build.
- §3.7: boot table to be code-generated from `cartridge.json`.

Every PR below is **doc-verified to be a plug, a wire, or a deletion** — not new architecture,
and not a rebuild of P3.

## 2. Dependency order (corrected — the CC4 gate was stale)

```
CC3 (golden path)            LANDED
CC4 (directory collapse)     ≈DONE (extensions/ gone; only apps/world-apps/jam-room remains)
P3a #458 / P3b #460          LANDED  (cell-identity registry + registerCells)
        │
        ▼
CC5.B  payload-schema: cartridge.json objectTypes replaces job.v2.ts   (core/protocol-types + cartridges/oddjobz + bridge)
        │   (CC5.A — oddjobz SPECs via registerCells — small; likely subsumed by §3.7)
        ▼
CC6    source-adapter + configs-as-intents   (legacy-ingest + verb_dispatcher + grammar data)
        │   a non-handyman source proves the schema is real
        ▼
CC7    generic renderer + shell de-wire      (apps/semantos + oddjobz experience)
        │
        ▼
matrix row (renderer-in-loop CC task; NOT hand-edited)  ─▶  roadmap regenerates
```

No phantom CC4 gate. Order rationale: CC6 maps **into** CC5.B's schema; CC7 renders **from**
it (+ proven generic by CC6). CC5.A is independent and may fall out of §3.7's
`cartridge.json`-generation rather than being hand-authored. CC5.B / CC6 / CC7 are different
layers/files and the only hard edges are the data dependencies shown.

## 2.1 Preservation boundary (verified 2026-05-19) — the stable spine

Three code investigations traced every oddjobz surface vs the hand-coded `job.v2.ts`
field-shape (full table + invariants in `CC5-SCHEMA-SECTION-IMPL-SPEC.md` §2.1):

- **FSM** (`job_fsm.zig` + visit/quote/invoice) and **conversation/intent** pipelines
  (`intent_action_router`, `quote_seed_router`, `visit_rollup_router`, voice-extract) are
  **verified-orthogonal** to the payload field-shape — they speak the *verb/FSM* language
  (`dispatcher.dispatch("jobs","transition",…)` → state-only appended cells). **Preserved for
  free.** They are the *stable spine the whole stack pivots around* — no row below changes
  FSM state enums/tables, verb/intent contracts, or the `EntityTypeSpec` triple.
- **Ratification** (`oddjobz_ratify_handler.zig`) is the **one coupled surface**
  (`appendCreatedV2(.{.workOrderNumber=…})` hard-codes field names). CC5.B2 handles it
  **name-preservingly** (declared `objectTypes` field names == existing names → ratify handler
  compiles unchanged); the generic schema-walking rewrite is **deferred** (option b, needs a
  2nd trade — don't generalize on N=1).
- **Flutter UI** is decoupled from the payload, coupled to the **query-API JSON shape**
  (`oddjobz_query_handler.writeJob`) — CC7's single shim/encoder point.

**Binding consequence for this stack:** every row is a *serialize/encode* change or a
*declarative-mapping* wire. None is permitted to touch the FSM/conversation spine — if a row
appears to require it, that is a STOP (Todd decision), not silent scope expansion.

## 3. Full PR stack (one PR per row — wave §2)

| # | Branch | Touches | Net |
|---|---|---|---|
| **CC5.A** | `feat/cc5-cell-specs` | `cartridges/oddjobz/brain/oddjobz_cell_specs.zig` + landed `cartridge_boot.registerCells` | oddjobz SPECs registry-driven (mirrors `tessera_cell_specs.zig`), off `builtinSpecByTag`. **Decide at exec:** hand-add vs wait for §3.7 manifest-gen |
| **CC5.B1** | `feat/cc5-payload-schema` | `extension-grammar.ts`,`-validator.ts`,`grammar-config-bridge.ts` | +`tier`/`carrier` *annotations* + validator + carry-through (carrier-less ⇒ byte-identical) |
| **CC5.B2** | ↳ stacked | `cartridges/oddjobz/cartridge.json` (**name-preserving** objectTypes — §2.1 opt-a, ratify handler untouched); **delete** `brain/src/cell-types/job.v2.ts` | ratify handler compiles unchanged; oddjobz payload derives from declared `objectTypes`; 514-LOC mirror gone; no validation-behaviour change; FSM/conversation spine untouched |
| **CC5.B3** | ↳ stacked | renderer-in-loop matrix task | matrix row generated |
| **CC6.1** | `feat/cc6-source-adapter` | `extensions/extraction` (+ conformance test) | ratify inferrer as bootstrap; AFFINE-only invariant |
| **CC6.2** | ↳ stacked | `verb_dispatcher.zig` walker + shell intent emit | adapter-config-as-intents; `/api/v1/info` stays GET-only |
| **CC6.3** | ↳ stacked | `runtime/legacy-ingest/src/extractor/email.ts` | delete `FALLBACK_OPERATOR_EMAILS`+per-agency prompt rules → adapter config |
| **CC6.4** | ↳ stacked | renderer-in-loop matrix task | matrix columns generated |
| **CC7.1** | `feat/cc7-schema-renderer` | `apps/semantos` (new generic renderer) | renders any `payloadSchema`; greenfield |
| **CC7.2** | ↳ stacked | shell carrier *presentation* (already-deref'd) | large field shows fully — **no client `__o1` fetch** |
| **CC7.3** | ↳ stacked | `main.dart`/`semantos_router.dart`; delete hand-built oddjobz screens | zero cartridge-name literals; shell pure |
| **CC7.4** | ↳ stacked | renderer-in-loop matrix task | matrix columns generated; specs → DONE |

CC5.A is standalone (own branch). CC5.B / CC6 / CC7 each stack internally. One reviewable PR
per row.

## 4. Gates green every commit (wave §2, binding — local, since GitHub CI is off by design)

`no-tessera-in-brain-core`, `namespace-partition-single-source`, `domain-flag-page-registry`,
greenfield/R-3/§9, **`no-AI-in-substrate`** (CC6-critical: fuzziness only at adapter/inferrer
edges). Where TS touched: `bun install` then `bun run check` + relevant conformance (root
`bun install` works — the `gate.yml` "broken" note was stale, corrected #457). Where brain
Zig touched: `zig build test -j1` in `runtime/semantos-brain` exit 0 (no summary = success,
Zig 0.15; include `-Denable-wasmtime=true` for the conformance half). **CC3 golden path stays
green every commit** — the regression anchor.

## 5. STOP conditions (wave §2 — one-paragraph note + `AskUserQuestion`)

- A PR can't be one reviewable unit, or a row needs a Todd decision.
- **Genuine contract gap:** the `job.v2.ts` deletion (CC5.B2) or the hardcode retirement
  (CC6.3) surfaces a rule the declarative grammar can't express → propose a *declarative*
  extension, **never** a prompt/widget hack (the whole point of the spine).
- Config-as-intents would need a non-GET `/api/v1/info` → forbidden, escalate.
- A `carrier` field reaches the shell **not** deref'd → brain read-path gap (CC5/escalation
  scope); escalate, do **not** add client `__o1` fetching.
- §3.7 manifest-generation lands and changes how SPECs/objectTypes are sourced → re-ground
  CC5.A/B against it (don't duplicate the generator).

## 6. Cross-track coordination (verified-live landmine)

- **`provision_tenant.zig` step 7** (`stepCopyExtensionBundles:868`): src
  `extension_bundle_src_dir = "/opt/semantos/extensions"` (`:169`) is **still stale on
  `main`** — verified 2026-05-19. The ext-dissolution moved *repo* paths, **not** this
  *runtime install path* or the copy step. Touched by **CC6** *and* **D-LIFT-ODDJOBZ** —
  resolve **once**, sequence so they don't concurrently rewrite it. D-LIFT remains a
  *separate* lift (its superseding note governs); the oddjobz↔brain decoupling will **not**
  fall out of this wave — flag if anyone assumes it does.
- **Three distinct landed seams — keep separate:** Zig `EntityTypeSpec` registry (P3,
  cell-identity) ≠ octave storage escalation (default, mechanism) ≠ tessera walker/loader
  registration. CC5.B depends only on the octave default; CC5.A only on `registerCells`;
  CC7 only on the effect (full payload on read).
- **CC7 is isolated:** no brain / no `provision_tenant.zig` — lowest blast radius; safe last.

## 7. Definition of done (rolls up wave §4 acceptance 7–9)

CC5: oddjobz SPECs register via `cartridge_boot.registerCells` (or §3.7 generation), payload
derives from `cartridge.json` `objectTypes`/`payloadSchema`, **`job.v2.ts` deleted**,
`carrier`/`tier` are annotations (carrier mechanism already free via P3 octave default). CC6:
per-source adapters are grammar data, the inferrer is the ratified bootstrap, hardcode deleted,
a different operator/source needs zero `extractor/` code. CC7: one generic renderer, large
fields render from the already-deref'd payload, shell carries zero cartridge literals. All:
matrix row generated (no parallel truth); CC3 green throughout; local gates green every
commit. **Throughout: the FSM + conversation spine is unchanged** — same state enums/tables,
verb/intent contracts, and `EntityTypeSpec` triple (§2.1 invariants); a row that appears to
need otherwise is a STOP, not scope creep. Then — and only then — the oddjobtodd↔oddjobz and
oddjobz↔PWA decouplings are *structurally complete*; oddjobz↔brain remains D-LIFT's separate
job.
