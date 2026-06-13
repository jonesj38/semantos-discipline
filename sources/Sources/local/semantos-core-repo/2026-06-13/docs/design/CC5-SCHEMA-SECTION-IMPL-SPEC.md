---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CC5-SCHEMA-SECTION-IMPL-SPEC.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.723843+00:00
---

# CC5 — Schema Section: Implementation Spec (collapsed — rides P3)

**Version**: 0.3 (2026-05-19 — adds the verified coupling map: FSM/conversation orthogonal & preserved-for-free; ratify-handler is the one coupled surface; name-preserving migration safety)
**Date**: 2026-05-19
**Status**: SPEC ONLY — **no longer gated behind CC4** (CC4 ≈ done: `extensions/` gone from `main`, oddjobz at `cartridges/oddjobz/cartridge.json`, CC3 landed). The cell-identity mint seam CC5 was going to fight for is **already on `main`** (P3a #458 + P3b #460). CC5 now reduces to its irreducible payload-schema core. Real dependency is **§3.7 manifest-generation**, not CC4.
**Parent / governed by:**
- `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` §4.1, §9 (the ratified principle)
- `docs/design/UNIVERSAL-CARTRIDGE-BOOT.md` §3.6 (cells fold-in, CORRECTED 2026-05-20), §3.7 (manifest-driven end-state), §8 (mint-path plan)
- `docs/canon/commissions/wave-canonical-cartridge.md` §3 row **CC5**, §2, §4 acceptance 7
- `docs/design/CANONICAL-CARTRIDGE-MODEL.md` C2 (manifest-as-source), §4.3 (stop hand-mirroring)
**Branch prefix (when executed):** `feat/cc5-payload-schema` (one PR per sub-step)

---

## 0. The reframe (why this rewrite — supersedes v0.1)

Investigation 2026-05-19: the tessera-P3 line **already built the generic seam** v0.1 assumed
CC5 must build. There are **two distinct layers** — conflating them was v0.1's error:

| Layer | What it is | Owner | Status |
|---|---|---|---|
| **Cell-identity** (Zig) | `EntityTypeSpec { tag, type_path, how_slug, inst_path, domain_flag }` — kernel-header identity (type-hash triple + domain flag @ offset 24) | **P3** | **LANDED on `main`** |
| **Payload-schema** (TS) | what's *inside* the 768 B payload — field defs + validators + source→canonical mapping | **CC5/CC6** | the irreducible residue, not done |

P3 does **not** touch the payload-schema layer. CC5's residue is exactly that layer — which is
the actual spine point (the 514-LOC `job.v2.ts` hand-mirror). v0.1's §3/§4/§5/§7 (carrier
mechanism, cell-mint wiring, "build the escalation honoring") are **withdrawn** — that work
is P3, already merged.

## 1. What P3 already delivers (verified on `main` — DO NOT rebuild)

- **Generic typed-cell mint path exists end-to-end**: `entity.encode` (verb_dispatcher walker)
  → `substrate_entity` encodes the 1024 B cell → `cell_store.put` (`UNIVERSAL-CARTRIDGE-BOOT`
  §3.6).
- **Octave escalation is the DEFAULT path** — payloads >768 B transparently → octave-1
  content store (`encodeEntityEscalating` + `content_store_local_fs`); `{"__o1":{slot,size,
  sha256}}` deref automatic on read. *No carrier mechanism to build* (§3.6: "the >1 KB reality
  is handled, no octave-API change").
- **Hardcoded brain-core `specByTag` switch de-hardcoded** — P3a (#458, merged):
  `substrate_entity.registerSpec(EntityTypeSpec)` additive registry (`builtinSpecByTag` first
  for back-compat, then runtime table; tag-collision-safe, idempotent, boot-only).
- **`registerCells` boot pass landed** — P3b (#460, merged):
  `runtime/semantos-brain/cartridge_boot.zig` registers each cartridge's `EntityTypeSpec`s at
  boot, out-of-`src/` (greenfield gate preserved). Reference contributor:
  `cartridges/tessera/brain/tessera_cell_specs.zig` — **the exact pattern oddjobz copies**.
- **Manifest-driven end-state** (§3.7): the boot table is to be code-generated from
  `cartridge.json` (`brain.verbsModule`/`verbs[]`) with a drift gate, mirroring
  `tools/cartridge-manifest/generate.ts`.

So CC5 adds **no** carrier mechanism, does **not** de-hardcode the switch, builds **no**
registry, writes **no** cross-language serialization. Those are P3, done.

## 2. The collapsed CC5 scope (two sub-rows)

### CC5.A — oddjobz rides `registerCells` (small; possibly subsumed by §3.7)
Add `cartridges/oddjobz/brain/oddjobz_cell_specs.zig` mirroring `tessera_cell_specs.zig`,
contributing oddjobz's 9 `EntityTypeSpec`s (data already exists as `SPEC_JOB`/`SPEC_SITE`/… in
`substrate_entity.zig`) via the landed `cartridge_boot.registerCells` pass — so oddjobz is
registry-driven like tessera/chess, off the legacy `builtinSpecByTag` switch. **Non-urgent:**
`builtinSpecByTag` keeps oddjobz working today; this likely **falls out of §3.7's
`cartridge.json`-generated boot table** rather than being hand-authored. Decide at execution:
hand-add now vs. wait for §3.7.

### CC5.B — payload-schema becomes manifest-declared (the real, irreducible work)
The spine. P3 does nothing here.
1. `cartridge.json` carries a load-bearing `objectTypes`/`payloadSchema` section for oddjobz
   job/site/customer. Structure is *already typed* in
   `core/protocol-types/src/extension-grammar.ts:216,245`; the gap is two optional fields.
2. Extend `PayloadSchemaField` (`:245`) — additive, absent ⇒ byte-identical:
   ```ts
   tier?: 'core' | 'operator-extensible';   // provenance/ownership
   carrier?: { octave: 1 };                  // RENDER HINT only — which field
   //   overflows >768 B. Mechanism already automatic (P3 octave default);
   //   this annotation just tells CC7 to expect/deref a carrier for that field.
   ```
3. Derive oddjobz payload encode/validate from the declared `payloadSchema` via the existing
   `grammar-config-bridge.ts` (`grammarToExtensionConfig`/`mapObjectType`) + extend
   `extension-grammar-validator.ts` for the two new fields.
4. **Delete the 514-LOC hand-mirror** `cartridges/oddjobz/brain/src/cell-types/job.v2.ts`
   (hand-coded field defs + `assert*` validators) + retire `cartridge.json:"objectTypesDir"`
   for oddjobz. The §4.3 "stop hand-mirroring, generate from manifest" rebase applied to the
   data plane — the data-half of CC0's ratified verb-half. Back-compat: legacy
   `objectTypesDir` still accepted (CC0a); oddjobz becomes the first to declare `objectTypes[]`.

## 2.1 Preservation boundary (verified 2026-05-19) — the coupling map

Three code investigations traced every oddjobz surface against the hand-coded `job.v2.ts`
field-shape. Result: **the refactor reduces to two serialize points; the FSM and conversation
machinery are structurally immune.**

| Surface | Coupled to `job.v2.ts` field-shape? | Evidence | Consequence |
|---|---|---|---|
| **FSM** (`job_fsm.zig`, visit/quote/invoice) | **No — orthogonal** | reads only state strings + capability + principal-kind; grep shows zero refs to `workOrderNumber/billingParty/siteRef/…`; transitions append a *state-only* cell `{ts,kind:updated,id,state,scheduled_at}`; `type_hash` is from the SPEC triple, not payload | preserved **for free** |
| **Conversation/intent** (`intent_action_router`, `quote_seed_router`, `visit_rollup_router`, voice-extract) | **No — orthogonal** | marshals `dispatcher.dispatch("jobs","transition",{id,to_state,principal_kind})` → FSM; never inspects payload | preserved **for free** |
| **Ratification** (`oddjobz_ratify_handler.zig`) | **Yes — coupled** | hard-codes `jobs.appendCreatedV2(.{ .workOrderNumber=…, .issuanceDate=…, .billingParty=… })` (field names baked in) | the **one** real piece of work — see decision below |
| **Flutter UI** | Decoupled from payload; coupled to the **query-API JSON shape** | binds to `oddjobz_query_handler.writeJob`'s JSON (walks the typed store row), not `job.v2.ts` | breakage controllable at one encoder (CC7) |

### Preservation invariants (binding — hold these and FSM/conversation cannot break)
1. **Do not change** the `status`/`state` enum values or the 13-state job transition table
   (likewise visit/quote/invoice FSMs).
2. **Do not rename** verbs / intent contracts / FSM state names — the conversation layer speaks
   the *verb/FSM* language, not the *payload-schema* language.
3. **Keep the SPEC triple stable** (`type_path/how_slug/inst_path` per `EntityTypeSpec`) — cell
   identity and `type_hash` derive from it, not from payload; schema edits never touch identity.

### The one coupled surface — ratify handler decision (pick at CC5.B2 execution)
- **(a) Name-preserving (recommended first cut, low risk):** the declared `objectTypes` field
  names **exactly match** the existing `workOrderNumber/issuanceDate/dueDate/billingParty/
  hasPhotos/photoCount/propertyKey/siteRef/customerRefs[]/attachmentRefs[]`.
  `oddjobz_ratify_handler.zig`'s `appendCreatedV2` keeps compiling unchanged; only the
  *definition* moves to the manifest. This is what makes deleting `job.v2.ts` safe in one PR.
- **(b) Schema-walking (the true end-state, deferred):** rewrite the ratify handler to populate
  cells from declared field metadata instead of hard-coded names — fully generic, larger
  change. Schedule once a *second* trade exists to prove the genericity (don't generalize on
  N=1).

### Migration safety pattern
CC5.B2 does **(a)** — declare name-preserving `objectTypes`, ratify handler untouched, query
handler shims new→old JSON keys if needed — then delete `job.v2.ts` in the *same* PR with the
validators' outcomes diffed (no behaviour change). The work-order fields are declared
`tier:'operator-extensible'` (they are PropertyMe's shape, not oddjobz's core) so a different
trade simply omits them — that *is* the decoupling, achieved without touching FSM/conversation.

## 3. PR decomposition (one PR per row — wave §2)

| PR | Content | Acceptance |
|---|---|---|
| **CC5.A** | `oddjobz_cell_specs.zig` + wire into landed `cartridge_boot.registerCells` (OR defer to §3.7 — decide at execution) | oddjobz mints via the registry path, not `builtinSpecByTag`; brain `zig build test -j1` green; zero cartridge id in `src/` |
| **CC5.B1** | `tier`+`carrier` on `PayloadSchemaField` + validator + `mapObjectType` carry-through | `bun run check`; carrier-less manifests byte-identical; greenfield/§9/namespace gates green |
| **CC5.B2** | oddjobz `cartridge.json` declares `objectTypes[]` **with name-preserving field names** (§2.1 option a — `oddjobz_ratify_handler.zig` `appendCreatedV2` stays untouched); payload encode/validate derived from it; **delete `job.v2.ts`** (+ site/customer mirrors) in the same PR | ratify handler compiles unchanged; oddjobz cells derive from declared schema; CC3 golden path green; deleted-validators' outcomes diffed = no behaviour change; FSM/conversation untouched (§2.1 invariants) |
| **CC5.B3** | matrix row via renderer-in-loop (do **not** hand-edit `unification-matrix.yml`) | generated; roadmap regenerates |

STOP (note + `AskUserQuestion`) if: deleting `job.v2.ts` surfaces a validator rule the
declarative schema genuinely can't express (→ propose a *declarative* extension, not a hack);
or §3.7 manifest-generation lands first and changes how SPECs/objectTypes are sourced (→
re-ground CC5.A/B against it); or option (a) name-preserving turns out infeasible (a declared
field can't carry an existing `appendCreatedV2` name/nesting) → that forces option (b)
schema-walking *now*, which is a Todd-decision (don't silently expand CC5.B2 into a ratify
rewrite).

## 4. Sequencing & non-conflation

- **Not gated on CC4** (≈ done). **Not gated on a phantom parallel session** — single Todd
  stream; P3a/P3b already merged; only `p3c-tessera-mint` in flight.
- **Composes with §3.7**: the *same* `cartridge.json` is the source for both P3's SPEC
  boot-table (cell-identity) and CC5.B's `objectTypes` (payload-schema). Sequence CC5.A to
  ride §3.7's generation rather than duplicate it; CC5.B can proceed in parallel (different
  layer, different files).
- **Active-churn flag**: `substrate_entity.zig` / `cartridge_boot.zig` are P3's live area
  (#458/#460 merged, `p3c-tessera-mint` in flight). CC5.A must re-ground against
  `tessera_cell_specs.zig` + the landed `registerCells` signature at execution time.
- **Non-conflation (three distinct LANDED seams):** Zig `EntityTypeSpec` (cell identity, P3) ≠
  TS `PayloadSchemaField` (field shape, CC5) ≠ octave **storage escalation** (default).
  CC5.B depends only on the octave default; CC5.A only on `registerCells`; neither touches the
  tessera walker/loader registration.

## 5. Acceptance (concrete form of wave §4.7)

1. oddjobz's cell SPECs register via `cartridge_boot.registerCells` (or §3.7 generation), not
   the legacy hardcoded switch.
2. oddjobz job/site/customer payload derives from `cartridge.json` `objectTypes`/`payloadSchema`
   (+ `tier`/`carrier`); **`job.v2.ts` deleted**; carrier-less manifests byte-identical.
3. A >768 B `carrier`-annotated field round-trips via the *already-default* octave path (zero
   new escalation code); CC7 uses the annotation to deref on render.
4. CC3 golden path green; greenfield/R-3/§9/namespace gates green every CC5.x commit; matrix
   row generated (no parallel truth).
5. **FSM + conversation preserved with zero changes** to FSM state enums/tables, verb/intent
   contracts, or the SPEC triple (§2.1 invariants) — verified-orthogonal, must stay so.
