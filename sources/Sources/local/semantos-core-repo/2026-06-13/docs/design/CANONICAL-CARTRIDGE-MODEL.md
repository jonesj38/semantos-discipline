---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/CANONICAL-CARTRIDGE-MODEL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.731723+00:00
---

# Canonical Cartridge Model — Design

**Version:** 0.1 DRAFT
**Status:** RATIFIED (Todd 2026-05-17 — "Ratify all C1–C6; commission the wave"). C1–C6 accepted; migration commissioned as its own gated wave — `docs/canon/commissions/wave-canonical-cartridge.md`. No code until that wave runs; golden-path-first, greenfield/R-3/§9 gates green every step.
**Amendment C7 RATIFIED** (Todd 2026-05-18 — "Amend the ratified model; CC4-M first"): the model assumed every non-`infra` cartridge declares a *cell* discourse surface (taxonomy/flows/prompts). CC4 found this false — jambox is a real experience cartridge whose Brain part is an imperative **verb-walkers** module (`jambox_walkers.zig`) with no taxonomy/flows/prompts. C7 adds the explicit **brain-surface kind** so jambox is first-class without faking empty dirs (handoff §8 forbids that).
**Amendment RATIFIED (Todd 2026-05-19 — "yeah").** CC0 scope-gap acknowledged: CC0 folded grammar/lexicon/taxonomy/capabilities but did **not** make the manifest's object-type/cell-**schema** section load-bearing — the data-half of the C2 manifest-as-source / §4.3 "stop hand-mirroring, generate from manifest" principle. **CC5–CC7 accepted** into the in-flight wave as that data-half (schema section + carrier bindings; ingest source-adapter as configs-as-intents; generic schema-driven renderer) — see `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` and `wave-canonical-cartridge.md` §3. Not a scope expansion: it plugs the already-typed `extension-grammar.ts` seam and deprecates the `job.v2.ts` hand-mirror. Same gated discipline — no code until the rows run, CC5–CC7 sequence **after CC3**, one PR per row, gates green every commit.
**Author:** Todd

**Capstone of / composes with (RATIFIED — this doc is their convergence, not greenfield):**
- `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md` — Decision A (affine PushDrop license UTXO), B (compose via typed `consumes`/`provides`, **never** an `extends` edge), C (atomic pay-for-rights).
- `docs/design/SELLABLE-NODE-LICENSE.md` — N1–N4 (node = cert + license-UTXO; provisioner data-blind; kill-switch). NL-1 delivered.
- DLO.1c Option C — the Brain disk-driven cartridge registry (`enumerateUserInstalled`); the `setLicenseGate` loader hook.

**Must slot into (do not duplicate):** `docs/canon/unification-matrix.yml` + its `SEMANTOS-UNIFICATION-ROADMAP.md` (substrate×axes deliverable matrix), `docs/canon/lexicons.yml` (lexicon registry), R-3 page registry, the `no-tessera-in-brain-core` / namespace / domain-flag-page greenfield gates, the §9 oddjobz cap mirror-list invariant.

---

## 0. Headline

There is **one unit: the cartridge.** "App" and "extension" cease to exist as concepts. A cartridge is a single self-describing thing with **one manifest** that declares everything it is — identity, grammar, lexicon, taxonomy, verbs, capabilities, `consumes`/`provides`, license, governance — and **two loadable parts**: a *Brain part* (cells/FSM/handlers) and a *PWA-experience part* (the Flutter surface). The **Brain shell** and the **PWA shell** are the only two loaders, and they load the *same* canonical manifest. Classification is by **role** (infra / experience / grammar-lexicon), never by directory.

Today the same logical cartridge is smeared across ≥3 directories and ≥5 parallel metadata systems. This doc defines the one model, maps every legacy concept onto it, reconciles the tensions, and proposes the migration. **Doc-first: no code until N-decisions below are ratified.**

## 1. The fragmentation today (verified inventory)

**5 directory homes for "a unit":**
| Home | Holds | Kind |
|---|---|---|
| `extensions/` (22) | oddjobz, bsv-anchor-bundle, metering, scada, cdm… | Brain-side TS/Zig FSM/operational |
| `apps/` (~20) | semantos-shell (the PWA shell!), wallet-browser, oddjobz-mobile, loom-react/svelte, demos, legacy-cli | grab-bag (shell + infra + clients + cruft) |
| `apps/world-apps/` | jam-room, swarm-pso-chess | "world-app" |
| `packages/*_experience` | oddjobz_experience, jam_experience, tessera_experience | Flutter PWA surfaces |
| `packages/` (infra) | cell-relay, content-store-*, world-sdk | substrate libs |

**≥5 parallel metadata systems per logical cartridge** (oddjobz, concretely): `extensions/oddjobz/manifest.json` + `src/manifest.ts` + `src/capabilities.ts` + `src/lexicon.ts` + taxonomy/flows/prompts dirs + the **Zig mirror** in `runtime/semantos-brain/src/extensions.zig` (§9 gate) + `packages/oddjobz_experience` (separate pubspec, no link back) + `apps/oddjobz-mobile`. One logical cartridge ≈ **3 physical locations, 6+ metadata files, zero single binding.**

**The concept layers that must collapse into one manifest:** `ExtensionManifest` (loader contract — already accreting the superset: taxonomy/flows/prompts/caps/grammar/governance/license/consumes/provides/extendsInterfaces), `ExtensionGrammar` (`extension-grammar.ts` — data-source + grammar-evolution, has its own `GrammarExtends`), `governance.ts` (L0/L1/L2), **lexicons** (`docs/canon/lexicons.yml` + `proofs/lean/Semantos/Lexicons/*` + `core/semantos-sir/src/lexicons.ts` + per-cartridge `src/lexicon.ts` re-export), taxonomy, capabilities.

## 2. The canonical cartridge (the model)

**A cartridge = one directory, one manifest, two parts, one identity.**

- **One manifest** (`cartridge.json`, the evolved `ExtensionManifest` — it is already 80% the superset): the *sole* contract. It does not point at five sibling metadata files; it declares (or refs, in-tree) each concern as a typed section:
  - identity: `id`, `version`, `ownerLicense` (Decision A `licenseOutpointRef`/`licenseLinearity`).
  - **role**: `infra` (must declare `provides`) | `experience` | `grammar-lexicon` (pure vocabulary, no Brain handlers).
  - composition: `consumes` / `provides` typed adapter interfaces (Decision B — **never** a cartridge-id `extends`).
  - **grammar** + **lexicon** + **taxonomy** + **verbs** + **capabilities** + **governance** — sections of the one manifest, with the canon registries (`lexicons.yml`, `unification-matrix.yml`) becoming **derived indices generated from manifests**, not parallel sources of truth.
  - **two parts**: `brain: { entry, flows, handlers }` and `experience: { flutterPackage }` — the *missing binding* today (a cartridge's Brain half and Flutter half are currently unrelated dirs). This single field is what unifies `extensions/X` ↔ `packages/X_experience`.
- **One directory** per cartridge: `cartridges/<id>/` containing `cartridge.json`, `brain/`, `experience/`, `grammar/`, `lexicon/`, `taxonomy/`. `extensions/`, `apps/world-apps/`, `packages/*_experience` collapse into it. `apps/` retains only true non-cartridges (the PWA shell binary, legacy-cli, demos) — and even `semantos-shell` is *the loader*, not a cartridge.
- **One identity**: the cartridge's owner is its license-UTXO holder (Decision A); first-party vs marketplace is the same model.
- **Two loaders, one model**: the **Brain shell** loads `cartridge.json` → resolves `consumes`/`provides` (topological, infra-before-experience) → license-gates (`setLicenseGate`) → registers verbs/handlers into dispatcher + `hat_registry`. The **PWA shell** (`semantos-shell`) reads the *same* manifest (via the Brain discovery endpoint, shell next-steps §3) → loads the declared `experience.flutterPackage` → routes user actions as `verb.dispatch` intents. Adding a cartridge = drop one directory; **neither shell is edited**.

## 3. Mapping every legacy concept onto the model

| Legacy concept | Becomes |
|---|---|
| `extensions/<x>` (FSM) | a cartridge with `role: experience\|infra`, `brain.flows` = its state-machines |
| `apps/world-apps/<x>` | a cartridge (`role: experience`); "world-app" is not a kind, just a cartridge. If its Brain part is a verb-walkers module (jambox ↔ `jambox_walkers.zig`), it declares `brain.surface: 'walkers'` + `brain.verbsModule` (C7) — no taxonomy/flows/prompts |
| `packages/<x>_experience` | that cartridge's `experience.flutterPackage` (now *bound* by the manifest) |
| `apps/wallet-browser`, `bsv-anchor-bundle` | `role: infra` cartridges that `provides` SpvVerifier/headers/wallet/anchor (closes the SW2/cartridge-license/NL-1 SpvContext debt — shell next-steps §1) |
| `ExtensionManifest` | **becomes `cartridge.json`** (the one manifest) — already the accreting superset |
| `ExtensionGrammar` / `GrammarExtends` | the manifest's `grammar` section. **Reconciliation:** `GrammarExtends` is *grammar-version inheritance* (a base-grammar semver), a different layer from Decision-B cartridge composition. Both kept; the doc states they never conflate — cartridges never `extends` cartridges; grammars may version-extend grammars. |
| `lexicons.yml` / `src/lexicon.ts` / Lean `Lexicons/*` | the manifest's `lexicon` section is the **source**; `lexicons.yml` + the Lean lexicon files become **generated/derived indices** (one source, not three parallel) |
| `capabilities.ts` + the §9 Zig mirror | the manifest's `capabilities` section; the §9 mirror-list invariant is preserved as a generated-conformance gate against the manifest (not a hand-kept Zig copy) |
| `taxonomy` / `flows` / `prompts` dirs | manifest-declared sections under the one cartridge dir |

## 4. Tensions this must reconcile (named, not hidden)

1. **`GrammarExtends` vs ratified Decision-B "no extends".** Resolved by layering: cartridge composition = `consumes`/`provides` only (no cartridge-id edge); grammar evolution = a grammar may declare a base-grammar semver. Different planes; the manifest schema keeps them in separate sections so they can't be conflated.
2. **`lexicons.yml` / `unification-matrix.yml` as parallel sources.** Under the model the **manifest is the source**; these canon files become **renderer outputs** (the matrix-to-roadmap.ts pattern already does this for the matrix). Avoids a 4th parallel truth.
3. **§9 oddjobz cap mirror-list (TS↔Zig).** Stays a gate, but rebased: conformance is *manifest → generated Zig*, not a hand-maintained mirror — this also subsumes the deferred DLO.1c "Option A" question (caps have one home: the manifest).
4. **Brain/PWA two-part binding.** The single new `experience.flutterPackage` manifest field is the linchpin; everything else is reorganization.
5. **Greenfield gates.** `no-tessera-in-brain-core` etc. must keep passing through the directory collapse — migration is per-cartridge, gates green every step (same discipline as the cap-substrate wave).

## 5. Decisions for Todd (ratify before any code)

- **C1 — The unit & the death of app/extension.** Ratify: one `cartridge`, one `cartridge.json`, role-classified (infra/experience/grammar-lexicon); "app" and "extension" removed from canon vocabulary; `apps/` keeps only the shell binary + non-cartridge tooling.
- **C2 — One manifest, derived registries.** Ratify: `ExtensionManifest`→`cartridge.json` is the single source; `lexicons.yml`/`unification-matrix.yml`/the §9 Zig cap table become **generated** from it.
- **C3 — The Brain↔PWA binding.** Ratify the `experience.flutterPackage` manifest field as the canonical link (collapses `extensions/X` ↔ `packages/X_experience`).
- **C4 — Directory collapse.** Ratify `cartridges/<id>/` as the single home; `extensions/`, `apps/world-apps/`, `packages/*_experience` migrate in.
- **C5 — Grammar-extends vs cartridge-no-extends layering** (§4.1) accepted as canon.
- **C6 — Migration shape**: per-cartridge, gates-green-every-step, golden-path first (oddjobz: infra wallet/headers cartridge + oddjobz experience cartridge end-to-end through both shells — the shell next-steps §5), then fan out (jamroom, tessera, the rest).
- **C7 — Brain-surface kind (RATIFIED Todd 2026-05-18, amendment).** A cartridge's Brain part is one of three surfaces, declared by `brain.surface`:
  - `cells` (default / absent — back-compat) — a declarative discourse surface; **requires** `taxonomyPath`/`flowsDir`/`promptsDir` (oddjobz).
  - `walkers` — an imperative verb-registering module (`brain.verbsModule`, the brain `@import` name; e.g. jambox's `jambox_walkers`); the declared `verbs[]` + that module **are** the Brain surface. **Exempt** from taxonomy/flows/prompts (mirrors the `role:infra` exemption, C1).
  - `none` — a PWA-only experience with no Brain part; also exempt.
  Rationale: the C1 role axis (infra/experience/grammar-lexicon) classifies *what a cartridge is for*; C7's `brain.surface` classifies *how its Brain part is shaped*. They are orthogonal — an `experience` cartridge may legitimately have a `walkers` (jambox) or `cells` (oddjobz) brain. Faking empty taxonomy/flows/prompts to satisfy the old rule is forbidden (handoff §8); C7 is the principled fix. Validator + CC0a conformance updated in lockstep (CC4-M); jambox golden-path proves it (CC4-2).

## 6. Migration path (post-ratification — a wave, not this doc)

1. **Manifest superset finalize** (C2/C3): `ExtensionManifest` → `cartridge.json` schema (add `role`, `experience.flutterPackage`, fold grammar/lexicon/taxonomy/capabilities as sections); validator + generated-registry renderers (`lexicons.yml`, §9 cap mirror) from it.
2. **Dual-shell loader** (shell next-steps §2/§3/§4): Brain consumes/provides resolver + discovery endpoint; PWA shell cartridge-SPI.
3. **Wallet/headers infra cartridge** (shell next-steps §1) — the keystone; retires the SpvContext stub debt.
4. **Golden path**: oddjobz end-to-end through both shells (C6).
5. **Fan-out + directory collapse**: migrate each cartridge into `cartridges/<id>/`, delete `apps`/`extensions`/`world-apps`/`*_experience` split, greenfield gates green every commit. Cite `unification-matrix.yml` (this is a new unification axis — add the row, don't duplicate the roadmap).

## 7. Acceptance for this doc

1. C1–C6 ratified (or amended) by Todd.
2. A new row added to `docs/canon/unification-matrix.yml` for the canonical-cartridge axis (not a parallel roadmap).
3. The migration (§6) commissioned as its own wave with the golden-path-first, gates-green discipline; this doc + the RATIFIED A/B/C + N1–N4 are its inputs.
4. No code until 1–3; the model must not regress the greenfield / R-3 / §9 gates.
