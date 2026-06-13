---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CC7-SCHEMA-RENDERER-IMPL-SPEC.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.736086+00:00
---

# CC7 — Generic Schema-Driven Renderer + Shell De-wire: Implementation Spec

**Version**: 0.3 (2026-05-20 — adds `primaryAnchor`/`hierarchy` per-cartridge surfacing declaration; "come-to-site vs services-at-a-location" framing)
**Date**: 2026-05-19
**Status**: SPEC ONLY — **not gated on CC4** (≈done) or any parallel session (none). Depends on **CC5.B** (renders *from* CC5.B's `cartridge.json` `payloadSchema`). CC7 core is **unchanged by P3** — P3 is the brain cell-identity layer; CC7 is the shell. The one P3-relevant fact: octave deref is **already the default server-side read path** (landed escalation + `UNIVERSAL-CARTRIDGE-BOOT.md` §3.6), so `carrier` is a *presentation hint*, not a client-side fetch (see §3.3). Deferred spine §4.3 detail.
**Parent / governed by:**
- `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` §4.3, §9 (esp. the navigator correction)
- `docs/design/CC5-SCHEMA-SECTION-IMPL-SPEC.md` **v0.2** (the schema CC7 renders; `carrier` = render hint)
- `docs/design/UNIVERSAL-CARTRIDGE-BOOT.md` §3.6 (octave deref is the default read path; P3 boundary excludes the shell)
- `docs/canon/commissions/wave-canonical-cartridge.md` §3 row **CC7**, §2, §4 acceptance 9
- `docs/SHELL-CARTRIDGES-HATS.md` (shell purity; loader, not domain screens)
**Branch prefix (when executed):** `feat/cc7-schema-renderer` (one PR per sub-step, after CC6)

---

## 1. One-sentence scope

One generic renderer walks a cell's CC5.B `payloadSchema` and lays out a sensible UI for *any*
cartridge with *any* field-set; hand-built oddjobz screens and the shell's hardcoded cartridge
wiring are retired in its wake.

## 2. What already exists (verified on origin/main — do not rebuild / do not overclaim)

| Asset | Location | State |
|---|---|---|
| Generic provisioning infra (KEEP) | `apps/semantos/lib/main.dart:32` `ManifestProvisioner`, `:49` `GrammarRegistry.fromProvisioned`, `:50` `HatRegistry`; `semantos_router.dart:40` home lists active extensions via `GrammarRegistry` | works — the de-wire *finishes* this abstraction, doesn't invent it |
| Hardcoded wiring (DE-WIRE TARGET) | `main.dart:2–5` hardcoded `jam/oddjobz/tessera` experience imports; `:65–67` hardcoded `*IntentGrammar()`; (+ route/icon maps in `semantos_router.dart`) | compile-time coupling; the only thing between “3 pilots” and “any cartridge” |
| Generic cell/schema renderer | — | **NONE. Greenfield.** No `CellRenderer`/`SchemaRenderer`/schema-walker in `apps/semantos` or `packages` |
| `extensions/navigator` | `package.json:4` “renders any extension's types”; `navigator-types.ts:4,8` “like Finder/Explorer … 7 lenses” | **lens organiser, NOT a payload-schema renderer** (spine §9 correction). Do not mistake it for a half-built renderer. |
| Octave-1 carrier deref | brain read path (landed escalation; `UNIVERSAL-CARTRIDGE-BOOT` §3.6) | **already automatic server-side** — the shell receives the *full* payload; CC7 does **not** fetch chained cells |
| Hand-built oddjobz screens (retire) | the oddjobz `experience.flutterPackage`; per-field `_row(label,value)` widgets + typed `Job` model | exact widget-file enumeration is a CC7.1 task |

**Consequence:** CC7 is *one greenfield generic renderer* + *finishing an existing
abstraction* + *deleting hand-built screens*. Navigator does not shortcut it; P3 does not
change it.

## 3. The renderer (what to build)

A schema-driven Flutter renderer that, given a cell:

1. Resolves the cell's `objectType` → CC5.B `payloadSchema` (`Record<string,PayloadSchemaField>`).
2. For each field: render by `PayloadSchemaField.type` (`string/number/boolean/date/datetime/
   object/array/enum`); respect `tier` (visual grouping core vs operator-extensible) and
   `FieldMapping.visibility` (`visible/hidden/redacted_value/approval_required` —
   `extension-grammar.ts:321`) — hidden/redacted not rendered raw.
3. **(§3.3 carrier — corrected)** A field annotated `carrier:{octave:1}` arrives **already
   resolved**: the brain derefs `{"__o1":…}` transparently on read (landed; §3.6). CC7 does
   **not** detect the descriptor or fetch a chained cell. The annotation is a **presentation
   hint** only — render that field as expandable / lazily-revealed / "large" affordance
   (it's a big text blob). No client-side deref, no brain call beyond the normal cell read.
4. Lay out generically (sectioned by `tier`, FSM `phases` for status) — **zero per-field
   widgets, zero cartridge-name literals.**

No typed-per-operator `Job` model on the render path; the model becomes "a cell + its schema".

## 3.5 Primary-anchor: per-cartridge surfacing hierarchy (declarative)

The generic renderer needs to know *which objectType to lead with* when surfacing a cartridge.
For oddjobz, that's **the site** — for the class of trades oddjobz serves. But this is **not
universal**, and embedding "site-primary" in the substrate or the shell would re-create the
exact anti-pattern the spine retires.

### 3.5.1 The categorical line (Todd 2026-05-20, verbatim — adopted as scope marker)

> *"service-based business especially which come to sites, rather than that do services at a location"*

That sentence is the canonical boundary for when a cartridge declares site as `primaryAnchor`:

- **Come-to-site recurring trades** (site-primary fits): handyman, gardener, cleaner, pool,
  pest control, HVAC service, lawn care, property maintenance, mobile groomer-at-residence.
  Site is the most stable node in the graph; tenants/agencies cycle but the address is
  forever; logistics + route optimisation + accumulated site knowledge all anchor there.
  PropertyMe/Bricks+Agent are *themselves* site-primary upstream — matching that data shape.
- **Services-at-a-location** (NOT site-primary): one-shot locksmith call-outs, courier,
  emergency-only plumber, mobile vet (animal is the anchor), mobile mechanic (vehicle),
  tutor (student). Location is incidental; site has no accumulation to anchor.
- **CRM-style customer-anchored** (Jobber/ServiceTitan-like): customer-primary. Works when
  customer ≡ homeowner forever; breaks for property-managed work.

The substrate must support all three. The declaration must be per-cartridge.

### 3.5.2 The declaration (manifest, optional, additive)

Two fields on `cartridge.json` — both **optional**; back-compat is "first declared
objectType is primary" if absent (matches current behaviour for cartridges that don't
declare):

```jsonc
// cartridges/oddjobz/cartridge.json
{
  ...
  "objectTypes": [
    { "typePath": "oddjobz.site", "primaryAnchor": true, ...payloadSchema... },
    { "typePath": "oddjobz.customer", ... },
    { "typePath": "oddjobz.job", ... }
  ],
  "ui": {
    "primaryAnchor": "oddjobz.site",
    "hierarchy": [
      "oddjobz.site",
      "oddjobz.customer",
      "oddjobz.job",
      "oddjobz.attachment"
    ]
  }
}
```

- **`objectTypes[].primaryAnchor: boolean`** (per-objectType flag) — exactly one objectType
  per cartridge may set `true`. Default = first declared. The schema/typing-side declaration.
- **`ui.primaryAnchor: <typePath>`** + **`ui.hierarchy: <typePath>[]`** (top-level) — the
  rendering instruction the shell reads. `hierarchy` orders the surfacing walk; the renderer
  follows graph refs (`siteRef`/`customerRefs[]`/`attachmentRefs[]`) accordingly.
- Validator (CC5.B1's path): if `ui.primaryAnchor` set, it must match the typePath of the
  single `objectTypes[].primaryAnchor:true` entry; if both absent, first-declared wins.

### 3.5.3 The renderer behaviour

Given the declaration above:

```
oddjobz.site (primaryAnchor)
   │  walks `oddjobz.customer[]` via Customer.siteRef == Site.cellId
   ├─ Customer A (role:agency,  primary:true)
   ├─ Customer B (role:tenant)
   ├─ Customer C (role:owner)
   │  walks `oddjobz.job[]` via Job.siteRef == Site.cellId
   ├─ Job W (state: in_progress)
   │     └─ Attachment refs via Job.attachmentRefs[]
   ├─ Job X (state: lead)
   └─ Job Y (state: paid)
```

A courier cartridge declaring `"primaryAnchor": "courier.parcel"` (+ corresponding
hierarchy) gets a parcel-primary view from the same generic renderer — zero shell change.
A direct-trade cartridge that declares no `ui` block gets first-declared-objectType primary
(job-primary for legacy oddjobz-style cartridges).

### 3.5.4 Why this fits the spine

This is *not* a new mechanism. It is one more **declarative manifest field** consumed by the
generic renderer — same pattern as `payloadSchema`/`tier`/`carrier` from CC5.B1. The shell
contains no string literal of `site`, `parcel`, `animal`, or `oddjobz`. Per-cartridge surfacing
intent travels as cartridge *data*, not as code.

## 4. The de-wire (finish the abstraction)

- `main.dart`: remove the hardcoded `jam/oddjobz/tessera` imports (`:2–5`) and concrete
  `*IntentGrammar()` instantiations (`:65–67`). Experiences + `IntentGrammar` discovered via
  the **already-present** `ManifestProvisioner`/`GrammarRegistry`.
- `semantos_router.dart`: routes/icons derived from `GrammarRegistry` (home already reads it
  `:40`), not hardcoded maps.
- Acceptance: **no cartridge-name string literal anywhere in `main.dart`/router**; adding a
  cartridge edits no shell code (the ratified C-model promise).

## 5. PR decomposition (one PR per row, gates green every commit — wave §2)

| PR | Content | Acceptance / gate |
|---|---|---|
| **CC7.1** | Generic schema renderer (§3 steps 1–2 + §3.5 surfacing): renders any `payloadSchema`, respects `tier`+`visibility`, leads with the manifest's `ui.primaryAnchor`/`hierarchy` (defaults to first-declared-objectType if absent); oddjobz job/site/customer render through it behind a flag | a synthetic non-oddjobz schema renders sensibly, zero new widgets; a fixture cartridge declaring a different `primaryAnchor` (e.g. `courier.parcel`) gets a corresponding primary view with zero shell change; analyzer/tests green |
| **CC7.2** | Carrier *presentation* (§3.3): a `carrier`-annotated field (arriving already-deref'd from the brain) renders as an expandable/large affordance — **no client deref** | a >768 B field shows full text; no extra brain call; no `__o1` parsing in the shell |
| **CC7.3** | Shell de-wire: remove hardcoded imports + `*IntentGrammar()`; routes/icons from `GrammarRegistry`; **delete** hand-built oddjobz screens | no cartridge-name literal in `main.dart`/router; a fixture cartridge needs zero shell edits; CC3 golden path still green through the generic renderer |
| **CC7.4** | Matrix row columns via renderer-in-loop; spec status → DONE | generated; no hand-edit of `unification-matrix.yml`; roadmap regenerates |

STOP (note + `AskUserQuestion`) if: a `payloadSchema` type can't render sensibly without a
domain assumption (→ propose a *declarative* schema hint in CC5.B, not a hardcoded widget); or
a `carrier` field arrives **not** deref'd (→ that's a brain read-path gap, CC5/escalation
scope — escalate, do **not** add client-side `__o1` fetching to the shell).

## 6. Sequencing, gates, coordination

- **After CC5.B** (the schema) **and after CC6 ideally** (a non-handyman source proves the
  renderer is truly generic). **Not gated on CC4** (≈done) or any parallel session.
- Touches only `apps/semantos` + the oddjobz experience package — **no brain, no
  `provision_tenant.zig`** (no D-LIFT/CC6 file collision; lowest blast radius of CC5–CC7).
- **Non-conflation:** P3 (cell-identity registry) and the octave storage seam are brain-side
  and *already landed*; CC7 consumes their *effect* (full payload on read), builds none of it.
- Shell-purity gate: post-CC7 the shell contains *zero* domain/cartridge literals — itself the
  regression test.

## 7. Acceptance (concrete form of wave §4.9)

1. A generic renderer renders any cartridge's cells from CC5.B `payloadSchema` with zero
   per-field widgets and zero cartridge-name literals; hand-built oddjobz screens deleted.
2. A `carrier`-annotated >768 B field renders fully **using the already-deref'd payload** — no
   client-side `__o1` handling, no extra brain call.
3. `main.dart`/router carry no cartridge-name literal; adding a cartridge edits no shell code.
4. CC3 golden path green *through the generic renderer*; greenfield/R-3/§9/namespace +
   shell-purity gates green every CC7.x commit.
5. **Per-cartridge surfacing is declarative** (§3.5): the renderer reads `ui.primaryAnchor`
   and `ui.hierarchy` from `cartridge.json` and surfaces accordingly; the shell contains zero
   literals of `site`/`job`/`parcel`/`animal`/etc. (a fixture cartridge declaring a different
   primary anchor flips the view with no shell edit — the regression test for §3.5).
   Cartridges with no `ui` block fall back to first-declared-objectType (back-compat).
