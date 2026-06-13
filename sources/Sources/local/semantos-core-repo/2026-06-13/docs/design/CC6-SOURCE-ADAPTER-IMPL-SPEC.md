---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CC6-SOURCE-ADAPTER-IMPL-SPEC.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.724364+00:00
---

# CC6 — Ingest Source-Adapter (configs-as-intents): Implementation Spec

**Version**: 1.0 (2026-05-21 — **CC6 DONE**; CC6.4 matrix render + roadmap freshness gate landed)
**Date**: 2026-05-21
**Status**: **DONE.** CC6.1 ON MAIN (#486). CC6.2 ON MAIN (#491). CC6.3a ON MAIN (#495). CC6.3b ON MAIN (#499). CC6.4 ON MAIN (PR will follow). CC5 closed via #469/#478/#482/#484. Path note: CC4 ext-dissolution moved `extensions/extraction/` → **`packages/extraction/`** — the inference pipeline CC6.1 ratifies lives at `packages/extraction/src/inference/pipeline.ts` (this spec's earlier `extensions/extraction/...` references read as the new path). CC6 core remains unchanged by P3 (cell-identity layer); CC6 is the payload/source layer.

**CC6.4 ratified design (this version):** The unification-matrix renderer-in-loop discipline is enforced. `docs/canon/unification-matrix.yml` is the source of truth for U11 (Canonical Cartridge) row's axis statuses. `docs/canon/render/matrix-to-roadmap.ts` renders §2 of `docs/prd/UNIFICATION-ROADMAP.md` from the YAML; the rendered block in the roadmap is bounded by `<!-- GENERATED:matrix-start ... -->` and `<!-- GENERATED:matrix-end -->` markers. The renderer was enhanced (CC6.4) to render all deliverables in a `deliverables[]` array (previously truncated to deliverables[0], which hid CC6 landing on U11 axes B and C). U11 axis B's deliverables list now reads `CC5.B1, CC5.B2a, CC5.B2b, CC6.2`; U11 axis C reads `CC0, CC2, DLO.1c, CC6.2`. The freshness gate (`tests/gates/cc6-4-matrix-render-freshness.test.ts`) re-runs the renderer at test-time and asserts the marker-bounded block matches — preventing quiet drift between the canon YAML and the rendered roadmap section.

**CC6.3b ratified design (this version):** The `PROMPT_TEMPLATE` constant inside `email.ts` (262–565) was a static string baking three agency NAMES (Clever Property, Robert James Realty, Bricks + Agent) into five imperative zones of LLM pedagogy: the maintenance_order classification mention, the not-a-job digest-summary example, the point-of-contact dispatcher example list, the per-agency POC heuristics, and the billing-rules section. CC6.3b retires this hardcode: `PROMPT_TEMPLATE` becomes a function `buildPromptTemplate(config)` at `runtime/legacy-ingest/src/extractor/prompt-builder.ts`; the static skeleton retains generic instruction + placeholder tokens, and the agency-specific pedagogy lives in `BillingRule.prompt_fragments` (new optional field on the type — `rules_section_text` + `heuristic_text`, both strings). The `EmailExtractor` instance now stores a per-instance `promptTemplate` + `promptHash`, both computed from its `adapterConfig` at construction time. A fresh adapter-config produces a prompt with NONE of the OJT agency names in the imperative zones; default config preserves equivalent behaviour. `promptHash` is config-dependent so re-extraction naturally triggers when an operator updates the config.

**Residual coupling (intentional, documented):** the DEEP-STRUCTURED-FIELDS worked-example BLOCK (~100 lines of canonical Clever Property PDF text + its expected JSON output) stays verbatim in `prompt-builder.ts`'s static skeleton. It is OJT-specific TRAINING DATA that teaches the LLM the STRUCTURE of a property-management PDF — a fresh config still benefits from this example structurally even when its declared agencies differ. A future CC6.3c (or follow-up) could add `worked_examples?` to `AdapterConfigMetadata` to make the example itself config-driven. For now the acceptance test asserts the IMPERATIVE zones (rules section, heuristics, classification mentions) are agency-clean — the worked-example block is acknowledged as a separate concern.

**CC6.3a ratified design (this version):** The hardcoded runtime data inside `runtime/legacy-ingest/src/extractor/email.ts` (the `FALLBACK_OPERATOR_EMAILS` constant + `CLEVER_PROPERTY_NAME`/`ROBERT_JAMES_NAME` consts + the three sender-domain billing rules + their body-substring fallback) has been retired into a typed `AdapterConfigMetadata` interface at `runtime/legacy-ingest/src/adapter-config/`. The shape mirrors what CC6.2's adapter-config cell carries in its `metadata` field — when a brain-side read seam ships (post-CC6.3b), `EmailExtractor` will deserialize this same struct from the cell payload. For CC6.3a the data still lives in the legacy-ingest tree as the default seed (`DEFAULT_ODDJOBZ_ADAPTER_CONFIG`); the seam established is dependency-injection on `EmailExtractor`'s constructor. Adding a new operator/agency = a new `BillingRule[]` entry in the config; zero edits to `email.ts`. Acceptance demonstrated in `runtime/legacy-ingest/src/__tests__/cc6-3a-adapter-config-extension.test.ts` (5 tests). Backward-compat verified: 798/798 legacy-ingest tests pass under default config.

**CC6.3b deferred:** The agency-name string literals embedded in `PROMPT_TEMPLATE` (LLM pedagogy at `email.ts:262–564`, calling out Clever Property / Robert James Realty / Bricks + Agent as worked examples) are a separate refactor — they teach the LLM rather than execute at runtime. Staging them as a follow-up keeps each PR small + reversible per wave §2.

**CC6.2 ratified design (this version):** Adapter-config is a **platform-level cell type** (`TAG_ADAPTER_CONFIG = 0x10`, `SPEC_ADAPTER_CONFIG` in `runtime/semantos-brain/src/substrate_entity.zig`) — *not* a new walker. The substrate's existing `substrate.entity.encode` walker is the canonical persistence primitive; CC6.2 adds one more `EntityTypeSpec` and rides the existing dispatch path. Rationale (substrate-spine §5, no-AI-in-substrate, no-domain-verbs-in-substrate): a dedicated `substrate.configure_adapter` walker would put operator-meaningful semantics in the substrate verb-set — same layer violation as `substrate.create_invoice`. Operator-meaningful intents like "configure source" live SHELL-SIDE and compose `verb.dispatch → substrate.entity.encode` with `tag = TAG_ADAPTER_CONFIG`. The substrate's verb-set stays orthogonal (encode / get / query); domain meaning stays at the edge.

**Adapter-config cell shape (CC6.2 canonical):**

```
SPEC_ADAPTER_CONFIG:
  tag         : 0x10
  type_path   : "platform.adapter_config"          (no cartridge id — platform-level)
  how_slug    : "configure"
  inst_path   : "inst.platform.adapter-config.v1"
  domain_flag : 0x00010120                          (well clear of oddjobz 0x000101xx)

payload_json (≤ 768 B inline; octave-1 escalation otherwise):
  {
    "extensionId":  "<cartridge-id>",          // e.g. "oddjobz"
    "sourceId":     "<operator-named-source>", // e.g. "todd-gmail-propertyme"
    "providerId":   "<legacy-ingest-provider>",// e.g. "gmail", "meta"
    "grammarId":    "<ratified-grammar-id>",   // → InferredGrammar from CC6.1
    "status":       "draft" | "active" | "retired",
    "metadata":     "<json-string-blob>"       // CC6.3 fills this with the
                                               //  retired FALLBACK_OPERATOR_EMAILS
                                               //  + per-agency rules.
  }

linearity_class:
  status == "draft"  → AFFINE   (operator-ratification pending — same draft pattern as CC6.1)
  otherwise          → RELEVANT (immutable artifact, multi-read; updates create new cells)
```

The walker (`substrate.entity.encode`) accepts whichever linearity the intent specifies; `linearityFor(TAG_ADAPTER_CONFIG, status)` is the ingest-path *convention*, not an enforcement.

**Parent / governed by:**
- `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` §4.2, §9
- `docs/canon/commissions/wave-canonical-cartridge.md` §3 row **CC6**, §2, §4 acceptance 8
- `docs/SHELL-CARTRIDGES-HATS.md` §172–173 (config-as-intents via `verb.dispatch`), §70 (`/api/v1/info` GET-only)
- `docs/design/CC5-SCHEMA-SECTION-IMPL-SPEC.md` **v0.2** (CC6 maps raw sources into CC5.B's `cartridge.json` `objectTypes`/`payloadSchema`)
- `docs/design/UNIVERSAL-CARTRIDGE-BOOT.md` §3.6 (P3 boundary — does *not* touch ingest; CC6 unaffected)
**Branch prefix (when executed):** `feat/cc6-source-adapter` (one PR per sub-step, stacked off CC5.B's tip)

---

## 1. One-sentence scope

A per-source **adapter** maps raw source data → the CC5 canonical schema; the adapter is
*grammar data* (`source.entities[]` + `entityMappings[]`), not code; operator source selection
is delivered as `verb.dispatch` **config-as-intents**; the bootstrap is the **already-tested**
inference pipeline; the per-operator hardcode in `legacy-ingest` is retired into adapter config.

## 2. What already exists (verified on origin/main — do not rebuild)

| Asset | Location | State |
|---|---|---|
| The adapter contract (declarative) | `core/protocol-types/src/extension-grammar.ts:47,271` — `entityMappings: EntityMapping[]`; `sourceEntityId`, `targetObjectType`, `fieldMappings[]`, `condition?` (`:294,371` polymorphic) | typed; *this is the adapter* — data, not code |
| Bootstrap inferrer | `extensions/extraction/src/inference/pipeline.ts:57,79` `InferenceAgent.infer()` → `analyzeStructure`→`mapTaxonomy`→`diffGrammars`→`composeGrammar`→ **AFFINE** `InferredGrammar` cell (`:8` "never auto-publishes — all inferred grammars are AFFINE drafts") | works; tests `__tests__/{propertyme-auto,scada-auto}.test.ts` |
| Transport half (keep as-is) | `runtime/legacy-ingest/src/providers/{gmail,meta}.ts`; `LegacyProvider` + grant-store + `providerId` (`types.ts:34,80,109`) | generic OAuth/fetch — **not** the hardcode |
| The hardcode to retire | `runtime/legacy-ingest/src/extractor/email.ts:71` `FALLBACK_OPERATOR_EMAILS`; per-agency rules embedded in prompt strings `:298–371` (“Bricks + Agent”, “Robert James Realty (RJR)”, billing-party inference) | operator-specific; prompt-baked |
| Config-as-intents pattern | `SHELL-CARTRIDGES-HATS.md:172–173` per-cartridge config → cells via `verb.dispatch`; `:70` `/api/v1/info` GET-only; `:93` walkers in `verb_dispatcher.zig` | established — CC6 uses it, does not invent |

**Consequence:** CC6 is *ratify the inferrer + express adapters as grammar data + move config to
intents + delete the hardcode*. The transport layer is untouched.

## 3. The model

```
raw source (Gmail thread · PropertyMe PDF · Meta lead)
   │  generic transport — providers/{gmail,meta}.ts  (UNCHANGED)
   ▼
source.entities[]            ← grammar declares the raw shape (CC5/grammar)
   │  entityMappings[] (declarative: coerce/map_enum/compute/template/condition)
   ▼  THE ADAPTER — data, not code
CC5 canonical objectTypes[]  ← one schema, many sources
```

- A new operator/source ⇒ a new `source.entities[]` + `entityMappings[]` block. **Zero
  extractor code.** Todd's handyman instance becomes *adapter-config #1*.
- **Bootstrap:** feed sample source responses to `InferenceAgent.infer()` → AFFINE
  `InferredGrammar` draft cell → operator ratifies (promotes AFFINE→published) → installed as
  the cartridge's grammar. CC6 *ratifies this existing flow as canonical*; it is not greenfield.
- **AI placement:** the inferrer's `mapTaxonomy` LLM stage and any fuzzy field/agency matching
  live **inside the adapter/inferrer (an edge)** — never in pask/brain/cells (spine §5,
  no-AI-in-substrate). CC6 must not regress this boundary.

## 4. Config-as-intents (the operator surface)

Operator source/adapter selection + credentials-binding is **not** a config endpoint and
**not** code. Per `SHELL-CARTRIDGES-HATS.md:172–173`:

- Operator picks/configures sources in the shell → shell emits `verb.dispatch` intents →
  brain walkers (`verb_dispatcher.zig`) persist adapter-config **cells**.
- `/api/v1/info` stays **GET-only** discovery (no config writes there).
- Provisioning a new operator = ratify an inferred grammar + bind provider credentials, all as
  intents. No rebuild, no per-operator code.

## 5. The deletion (the actual point of CC6)

- `runtime/legacy-ingest/src/extractor/email.ts`: remove `FALLBACK_OPERATOR_EMAILS` (`:71`) and
  the per-agency/billing-party rules baked into prompt strings (`:298–371`). These become
  **adapter-config cells** (operator emails, agency→billing rules) consumed by the declarative
  `entityMappings[].condition` + `fieldMappings`, not prompt literals.
- Keep `providers/{gmail,meta}.ts` and the grant-store untouched (generic transport).
- Net: a non-handyman operator with different sources produces valid canonical cells with
  **zero extractor code edits** — the wave-§4.8 acceptance.

## 6. PR decomposition (one PR per row, gates green every commit — wave §2)

| PR | Content | Acceptance / gate |
|---|---|---|
| **CC6.1** | Ratify the inference pipeline as the canonical bootstrap: doc + a conformance test asserting `infer()` yields an **AFFINE** draft (never auto-published) for a fixture source | `bun run check`; `propertyme-auto`/`scada-auto` green; AFFINE-only invariant test added |
| **CC6.2** | Adapter-config-as-intents: walker(s) in `verb_dispatcher.zig` persisting adapter-config cells; shell emits intents; `/api/v1/info` stays GET-only. **Landed** as platform `EntityTypeSpec` (TAG=0x10) riding the existing `substrate.entity.encode` walker — no new walker; adapter-config is a typed substrate primitive, operator-meaningful intent names live shell-side | a source config round-trips as `verb.dispatch`→cell→read; no new endpoint; brain `zig build test -j1` exit 0; `tests/gates/cc6-2-info-get-only.test.ts` green (regression gate on the two GET-only enforcement points) |
| **CC6.3a** | **Landed** — runtime hardcode retirement. `FALLBACK_OPERATOR_EMAILS` + `CLEVER_PROPERTY_NAME`/`ROBERT_JAMES_NAME` + the 3 sender-domain billing rules in `normaliseBillingParty()` + body-substring fallback retired into `AdapterConfigMetadata` (typed `BillingRule[]` + `fallback_operator_emails`). `EmailExtractor` takes an optional `adapterConfig`; default is `DEFAULT_ODDJOBZ_ADAPTER_CONFIG` (byte-equivalent prior behaviour). | **Met** — `cc6-3a-adapter-config-extension.test.ts` (5 tests): new operator/agency/Meta-source routes via `adapterConfig` alone, zero `email.ts` edits; backward-compat 798/798 legacy-ingest tests green; `entityMappings[].condition` left untouched (operator set `eq`/`neq`/`in`/`not_in`/`exists`/`not_exists` is insufficient for the field-assignment semantics these rules carry — routed via `AdapterConfigMetadata` directly). |
| **CC6.3b** | **Landed** — `PROMPT_TEMPLATE` retired into `buildPromptTemplate(config)` at `runtime/legacy-ingest/src/extractor/prompt-builder.ts`. Five imperative zones in the prompt (maintenance-order routing mention, not-a-job dispatcher digest example, POC dispatcher list, POC per-agency heuristics, billing-rules section) now interpolated from `BillingRule.agency_name` + `BillingRule.prompt_fragments` (new optional `rules_section_text` + `heuristic_text` on `BillingRule`). `EmailExtractor` stores per-instance `promptTemplate` + `promptHash`. | **Met** — `cc6-3b-prompt-template-parameterization.test.ts` (20 tests): fresh-config builds a prompt where billing-rules section + heuristics + classification mentions contain ONLY its declared agencies; default config preserves OJT agency mentions; promptHash deterministic per config + sensitive to config change; full email-extractor regression 38/38; full legacy-ingest 818/818. Worked-example BLOCK remains in static skeleton (training data; residual coupling documented). |
| **CC6.4** | **Landed** — Matrix row columns via renderer-in-loop; spec status → DONE. U11 row YAML axes B + C updated to include CC6.2 deliverable; renderer enhanced to render full `deliverables[]` arrays (was truncating to first); roadmap §2 regenerated and bounded by `<!-- GENERATED:matrix-start/end -->` markers; freshness gate `tests/gates/cc6-4-matrix-render-freshness.test.ts` re-runs the renderer at test-time to prevent drift. | **Met** — `cc6-4-matrix-render-freshness.test.ts` (3 tests): markers present; renderer output equals checked-in block; U11 B/C cite CC6.2. Renderer regression suite 7/7. Roadmap §2 is now generated; hand-edits are mechanically rejected. |

STOP (note + `AskUserQuestion`) if: the hardcode encodes a rule `entityMappings` genuinely
can't express (→ real contract gap, propose a *declarative* extension, not a prompt hack); or
config-as-intents would require a non-GET `/api/v1/info` (forbidden — escalate).

## 7. Sequencing, gates, coordination

- **After CC5.B** (CC6 maps into CC5.B's payload-schema). **Not gated on CC4** (≈done) or any
  parallel session. P3 (cell-identity) is orthogonal — CC6 may proceed independently of P3.
- **Coordination (verified-still-live landmine):** CC6 touches `provision_tenant.zig` step 7
  `stepCopyExtensionBundles` (`:868`). The src dir `extension_bundle_src_dir =
  "/opt/semantos/extensions"` (`provision_tenant.zig:169`) is **still stale on `main`** —
  verified 2026-05-19: the ext-dissolution moved *repo* `extensions/`→`packages/`/`cartridges/`
  but **not** this *runtime install path* or the copy step. D-LIFT-ODDJOBZ also touches it.
  Resolve `/opt/semantos/extensions` → cartridge install path **once** (here or in D-LIFT),
  not twice; sequence so they don't concurrently rewrite it. D-LIFT remains a *separate* lift
  (its superseding note governs) — **not** a CC5–CC7 deliverable.
- **No-AI-in-substrate** boundary must stay green: fuzziness only in adapter/inferrer edges.

## 8. Acceptance (concrete form of wave §4.8)

1. Per-source adapters are `source.entities[]`+`entityMappings[]` grammar data; the inference
   pipeline (AFFINE-draft, operator-ratified) is the ratified bootstrap.
2. Operator source/adapter config flows as `verb.dispatch` cells; `/api/v1/info` still GET-only.
3. `FALLBACK_OPERATOR_EMAILS` + per-agency prompt hardcode deleted; a different
   operator/source/agency yields valid canonical cells with zero `extractor/` code edits.
4. AI stays at the edge; greenfield/R-3/§9/namespace + no-AI-in-substrate gates green every
   CC6.x commit; CC3 golden path still green.
