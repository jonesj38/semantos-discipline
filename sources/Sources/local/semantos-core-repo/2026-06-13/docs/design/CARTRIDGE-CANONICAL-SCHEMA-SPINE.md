---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.726404+00:00
---

# Cartridge Canonical Schema Spine — one abstraction, inserted twice

**Version**: 0.1 (initial draft)
**Date**: 2026-05-19
**Status**: Design principle — pre-implementation. Composes with RATIFIED `CANONICAL-CARTRIDGE-MODEL.md` (C2/C3); it does not re-decide the unit, it specifies the *data/UI plane* of the one manifest. No code until tracked as a wave row (see Acceptance §9).
**Scope**: What the one manifest's schema/object-type section must drive — adapter-in at ingest, renderer-out at the shell. oddjobz is the reference implementation; the principle is cartridge-general.
**Parent (RATIFIED — this composes with it, does not duplicate):**
- [`docs/design/CANONICAL-CARTRIDGE-MODEL.md`](CANONICAL-CARTRIDGE-MODEL.md) — C1–C6; one cartridge, one manifest, two parts. This spine = the manifest's `objectTypes`/schema section made load-bearing (C2 derived-registries, C3 Brain↔PWA binding).
- [`docs/design/CC4-CARTRIDGE-FAN-OUT-HANDOFF.md`](CC4-CARTRIDGE-FAN-OUT-HANDOFF.md) — the fan-out/collapse handoff this slots beside.
- [`docs/canon/commissions/wave-canonical-cartridge.md`](../canon/commissions/wave-canonical-cartridge.md) — the commission this is tracked under.
**Composes with:**
- [`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`](../CARTRIDGE-DISTRO-GAP-ANALYSIS.md) — cartridge-as-distro framing
- [`docs/SHELL-CARTRIDGES-HATS.md`](../SHELL-CARTRIDGES-HATS.md) — shell purity + config-as-intents
- [`docs/prd/D-LIFT-ODDJOBZ.md`](../prd/D-LIFT-ODDJOBZ.md) — the brain-core carve
**Must slot into (do not duplicate):** `docs/canon/unification-matrix.yml` (add a row; roadmap is *generated* by `docs/canon/render/matrix-to-roadmap.ts`, never hand-authored), and the greenfield / R-3 / §9 gates.

---

## 1. The problem in one sentence

A legacy source's *field shape* is currently the cell's shape **is** the UI's shape — nothing
normalizes it anywhere along the line — so every new operator, source, or field touches
extraction, the cell schema, the typed model, and hand-built widgets at once.

This is why the work feels like circling: there is no decoupling point, so operator-specific
specificity is solved repeatedly *in code* instead of once *as cartridge data*.

## 2. The leak, end to end (grounded)

```
PropertyMe / Bricks+Agent PDF  ·  Gmail thread  ·  Meta lead
        │
        ▼   extraction prompt — hardcoded to one operator
            extensions/oddjobz/src/prompts/pdf-extraction-prompt.ts:87  ("infer state QLD")
            runtime/legacy-ingest/src/extractor/email.ts:66             (FALLBACK_OPERATOR_EMAILS)
            runtime/legacy-ingest/src/extractor/email.ts:248            (per-agency billing rules)
        │
        ▼   cell schema = the PDF's fields verbatim
            extensions/oddjobz/src/cell-types/job.v2.ts  (workOrderNumber, billingParty, issuanceDate)
            — no extra/custom-field mechanism; Meta-sourced job ⇒ these all null ⇒ degenerate cell
        │
        ▼   typed Dart model — same named fields, fixed
            apps/oddjobz-mobile/lib/src/repl/jobs_repository.dart   (class Job { workOrderNumber; ... })
        │
        ▼   hand-built widgets, one per named field
            apps/oddjobz-mobile/lib/src/helm/job_detail_screen.dart  (_row('Work Order', ...) ...)
            — chained carrier (octave-1) cells are NOT fetched or rendered at all
```

Four stages, one shape, **zero abstraction between them**. The provider adapters
(`runtime/legacy-ingest/src/providers/{gmail,meta}.ts`) exist but feed this single hardcoded
path; the cartridge manifest already declares `objectTypes` (a schema) and **nothing reads it
for UI**. Those two facts are the unused halves of the seam.

## 3. The one missing concept

Insert a single abstraction — a **canonical, manifest-declared cell schema** — that both ends
defer to. The cartridge owns the schema; ingest maps *into* it; the shell renders *from* it.

```
                    ┌──────────────────────────────────────────┐
                    │  cartridge manifest: objectTypes (schema)  │   ◄── single source of truth
                    │  core fields · operator-extensible fields  │
                    │  carrier bindings (which overflow → octave)│
                    └──────────────────────────────────────────┘
                          ▲                              │
                          │ maps INTO                    │ renders FROM
        ┌─────────────────┴───────────┐      ┌───────────┴──────────────────┐
        │  source-adapter (per source)│      │  generic schema-driven renderer│
        │  PropertyMe-PDF · Gmail ·   │      │  walks primary cell + chained  │
        │  Meta — raw → canonical     │      │  carrier cells against schema  │
        └─────────────────────────────┘      └────────────────────────────────┘
              INGEST INSERTION POINT                 SHELL INSERTION POINT
```

## 4. The three insertion points

### 4.1 Cartridge owns the schema (manifest `objectTypes`)
The job/site/customer object types — fields, types, **core vs operator-extensible**, and which
field's overflow lives in a chained carrier cell — are declared in the cartridge manifest, not
implied by a TypeScript cell-type class or a Dart model. The manifest hook already exists
(`objectTypes` is parsed; nothing consumes it). This becomes the contract both other points
defer to. Operator-extensible fields are how a different trade captures `priority` / `budget`
without a schema migration.

### 4.2 Ingest gets a normalization seam (source-adapter)
A per-operator, per-source **adapter** maps raw source → canonical schema. PropertyMe's
`work_order_number`, Gmail thread structure, and Meta lead fields become *three adapters'
mappings into the same schema*, not three different cell shapes. Provisioning a new operator
becomes: select/configure adapters + connect accounts — expressed as **cartridge config flowing
as intents** (`verb.dispatch`), per `SHELL-CARTRIDGES-HATS.md`, **not** code edits and **not** a
config endpoint. The existing `providers/{gmail,meta}.ts` are the transport half; the adapter is
the missing mapping half. Your handyman instance reduces to *adapter-config #1*, not the
hardcoded baseline.

### 4.3 Shell renders from the schema (generic cell-renderer)
One generic renderer walks the primary cell **plus its chained carrier cells** against the
manifest's `objectTypes` and lays them out. A different operator with different fields gets a
sensible UI with zero new widgets. This is the generative UI; it also gives the octave-1
overflow (full job-sheet text) its first actual render path — currently it is stored but never
shown. No per-field `_row(...)` widgets; no typed-per-operator `Job` model on the render path.

## 5. Discipline mapping (why this keeps the layers honest)

| Layer      | Rule                                                  | Effect of the spine                                              |
|------------|-------------------------------------------------------|------------------------------------------------------------------|
| Substrate  | Generic; zero domain, zero AI (intelligence at edges) | Unchanged. Octave escalation already generic. Leave it.          |
| Shell      | Pure; renders from schema, no domain screens          | Generic renderer replaces hand-built oddjobz screens.            |
| Cartridge  | Owns the domain                                       | Owns the schema + adapters; operator specificity is its *data*.  |

AI fuzziness (e.g. fuzzy field/agency matching, the natural-language compression gradient) is
legitimate **inside a source-adapter** — that is an edge, consistent with "intelligence at the
edges, none in the substrate." It must not reach into pask/brain/cells.

## 6. Consequences (these fall out — they are not separate designs)

- **Shell de-wire** (hardcoded `oddjobz/jam/tessera` imports + routes in
  `apps/semantos/lib/main.dart` / `semantos_router.dart`) becomes a *prerequisite
  symptom*: a schema-driven renderer cannot coexist with hand-named screens.
- **Trade-profile config** (personas, ROM pricing, locality, taxonomy currently hardcoded in
  `system-prompt.ts` / `reply-generator.ts` / `pdf-extraction-prompt.ts`) is just *more
  operator-extensible schema + adapter config* — same mechanism, not a second one.
- **O10 provisioning** (`provision_tenant.zig`, referenced by `D-LIFT-ODDJOBZ.md`) gains a
  concrete payload: "which adapters, which accounts, which schema extensions" — instead of
  forking code per operator.

## 7. Explicitly out of scope for this doc

Wire format of the manifest `objectTypes` schema; the adapter interface signature; the
renderer's widget vocabulary; migration of existing `job.v2` cells. Those are implementation
specs that follow once the spine is accepted. This document fixes only the *one concept and its
three insertion points* so there is a stable thing to design against.

## 8. Non-conflation note

The octave **storage escalation** seam (landed on `main`, generic, content-addressed) is *not*
the tessera "generic walker/octave **registration loader**" blocker (`feat/tessera-wave-1`
§11). This spine depends on the former (carrier cells exist and deref) and is orthogonal to the
latter. Do not merge the two in planning.

## 9. Grounding & cross-reference (added 2026-05-19, verified)

**This is an unplugged seam, not new design.** `core/protocol-types/src/extension-grammar.ts`
already types the whole spine: `source.entities` (raw API), `objectTypes[].payloadSchema`
(`:236`, canonical), `entityMappings[]` with declarative `coerce`/`map_enum`/`compute`/`template`
(the adapter), `visibility` (`:321`), `objectType.capabilities` (`:239`). A working instance
exists at `configs/extensions/propertyme/grammar.json` (545 LOC, real `compute`). A validator
(`extension-grammar-validator.ts`) and `grammar-config-bridge.ts` exist. **What's missing is a
consumer:** `extensions/oddjobz/src/cell-types/job.v2.ts` is 514 LOC of hand-coded payload that
*mirrors* the propertyme grammar instead of being generated from it. CC5 = plug the existing
typed seam into the loader→cell-mint path and deprecate the hand-mirror.

**CC0 symmetry (makes the gap a symmetry, not an addition).** CANONICAL-CARTRIDGE-MODEL §4.3
already rebased the §9 oddjobz cap mirror-list to *manifest → generated Zig, not a hand-kept
mirror*. CC5 is the **same rebase applied to the data plane**: typed Dart models + hand-built
widgets + `job.v2.ts` stop being hand-mirrors of manifest data. CC5 is the *schema-half of
CC0's already-ratified lexicon/grammar/caps fold* — not a new concept.

**Relationship to the inbuilt package manager (separation that must hold).** The package
manager is the cell-DAG release pipeline (`tools/release/` — `build`/`submit`/`fetch`/
`analytics`, `release.config.ts` per package, deps pinned by sha256, no npm). It is
**deliberately blob-opaque**: `ReleaseManifest` is a hash envelope and does *not* understand
grammar/objectTypes — and it must **stay** that way. CC5's schema section is a
**loader/provisioning** concern (`extension-loader.ts` → `ExtensionConfig`;
`provision_tenant.zig` step 7; `extensions.zig enumerateUserInstalled`), **not** a
release-pipeline concern. `grammar.json` rides inside the content-addressed cartridge bundle as
opaque bytes to the pipeline but as load-bearing schema to the loader. **Do not push CC5 schema
into `tools/release/`.** (consumes/provides resolver + license gate are promised, not shipped —
CC5–CC7 sequence after CC3 accordingly.)

**CC6 already has a bootstrap path.** `extensions/extraction/src/inference/pipeline.ts`
(structure-analyzer → taxonomy-mapper → grammar-diff → grammar-composer → AFFINE
`InferredGrammar` cell; tests `propertyme-auto`/`scada-auto`) is the operator-provisioning flow
the spine names "adapter-config #1" — already wired. CC6 ratifies it as the bootstrap, it is
not greenfield.

**Corrections to the source analysis (do not propagate the originals).**
- `extensions/navigator` is **not** a generic schema-walking renderer — it is a lens-based
  nav/filter UI. CC7's generic renderer is a *genuine* gap; do not claim it is half-built.
- Lexicons number **12, not 13**, and **`tessera` is not a lexicon** (it is a cartridge).
  `core/semantos-sir/src/lexicons.ts` ALL_LEXICONS: Jural, ControlSystems, CircuitCommands,
  CDM, BillsOfLading, ProjectManagement, PropertyManagement, RiskAssessment, Calendar, Trades,
  BRAP, + relationLexicon. Cite this count, not 13.
