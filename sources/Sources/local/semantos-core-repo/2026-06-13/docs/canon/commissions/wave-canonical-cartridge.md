---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/commissions/wave-canonical-cartridge.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.756769+00:00
---

# Wave Canonical-Cartridge — One-Cartridge Unification Commission

**Audience:** Claude Code (orchestrator) + parallel-agent fleet.
**Author:** Todd Price.
**Date:** 2026-05-17.
**Companion to:** `docs/design/CANONICAL-CARTRIDGE-MODEL.md` (RATIFIED — C1–C6).
**Composes with (RATIFIED, binding inputs):** `docs/design/CARTRIDGE-MARKETPLACE-OWNERSHIP.md` (A/B/C), `docs/design/SELLABLE-NODE-LICENSE.md` (N1–N4; NL-1 delivered), DLO.1c Option-C disk registry + `setLicenseGate`.
**Schema-spine extension (CC5–CC7 below):** `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md` — the data/UI plane of the one manifest (object-type/schema section + ingest source-adapter + generic schema-driven renderer). Added 2026-05-19; closes a CC0 scope gap (see note under §3).
**Milestone:** one unit — the cartridge. "App"/"extension" removed from canon; one `cartridge.json` is the sole source; Brain shell + PWA shell load the *same* manifest; wallet/headers are infra cartridges; the SpvContext stub-debt across SW2/cartridge-license/NL-1 is retired.

## 1. Mission

Execute the §6 migration of `CANONICAL-CARTRIDGE-MODEL.md`. Collapse `extensions/` + `apps/world-apps/` + `packages/*_experience` into one `cartridges/<id>/` model bound by one `cartridge.json`. **Doc-first is done — this wave is the deep fix.** Golden-path-first; greenfield / R-3 / §9 / namespace gates green on every commit; the RATIFIED A/B/C + N1–N4 are constraints, not open questions.

## 2. Discipline (binding)

- **One PR per CC-row.** Branch `feat/cc-<row>-<slug>` off the prior CC branch (stacked). Commit scoped to touched paths (`git commit <paths>`, never bare `-m`). First Bash call each iteration: branch + ahead/behind main + dirty entries.
- **Gates green every commit:** `no-tessera-in-brain-core`, `namespace-partition-single-source`, `domain-flag-page-registry`; `bun run check`/relevant conformance where TS touched; `zig build test -j1` in `runtime/semantos-brain` exit 0 where brain Zig touched; `lake build` zero-sorry where Lean touched. No regression to the proven cap/license substrate (K15/K3/cartridge-license/NL-1 suites stay green).
- **No new parallel truth.** `cartridge.json` is the source; `lexicons.yml` / the §9 Zig cap table / the unification roadmap become **generated from it** (C2). Do not hand-edit the schema-bound `unification-matrix.yml` renderer blindly — the matrix row is an explicit CC0 canon task done with the renderer in the loop.
- **STOP** (one-paragraph stop note + actionable `AskUserQuestion`) when a row needs a Todd decision, can't be one reviewable PR, or surfaces a canon/owner ambiguity. Do **not** force a sprawling cross-cartridge change or fake a binding.

## 3. CC-rows (sequenced; golden-path-first)

| Row | What | Acceptance |
|---|---|---|
| **CC0** | `ExtensionManifest`→`cartridge.json` superset: add `role` (infra\|experience\|grammar-lexicon), `experience.flutterPackage`, fold grammar/lexicon/taxonomy/capabilities as sections; validator; renderers that **generate** `lexicons.yml` + the §9 Zig cap table + the unification-matrix row from manifests. | schema + validator + generators land; existing manifests still validate; generated `lexicons.yml`/§9 table byte-equal the current hand-kept ones (proves the generator is faithful); gates green. |
| **CC1 (keystone)** | Package wallet + headers as **infra cartridges** that `provides` SpvVerifier/headers/wallet adapters (mirror `bsv-anchor-bundle` `provides`). | a real `SpvContext` is constructible from the wallet/headers cartridge; SW2/cartridge-license/NL-1 can consume it (the documented stub-debt retires); cap-UTXO conformance now exercises the real verifier path. |
| **CC2** | Dual-shell loader: Brain `consumes`/`provides` topological resolver (infra-before-experience) + license gate + dispatcher/hat registration; Brain→PWA discovery endpoint; PWA `semantos-shell` cartridge-SPI. | a cartridge loads in both shells from its manifest with **zero shell edits**; resolver orders infra→experience; unlicensed cartridge gated (reuse `setLicenseGate`). |
| **CC3 (golden path)** | oddjobz end-to-end: Brain loads it (license-gated) consuming CC1's real SpvContext; PWA shell renders `oddjobz_experience` bound by `cartridge.json`; an intent (`verb.dispatch`) round-trips. | the golden path passes as a conformance; this is the acceptance gate before fan-out. |
| **CC4…** | Fan-out + directory collapse: migrate each cartridge into `cartridges/<id>/`; bind its `experience.flutterPackage`; delete the `apps`/`extensions`/`world-apps`/`*_experience` split; add the `unification-matrix.yml` canonical-cartridge row. One PR per cartridge; per-cartridge owner sign-off = its license-UTXO holder (Decision A; first-party = brain-core). | each migrated cartridge loads via both shells; gates green; `apps/` retains only the shell binary + non-cartridge tooling. |
| **CC5** | **Schema section (closes the CC0 gap — see note). Plug the existing seam, don't design one.** The structure is *already typed*: `core/protocol-types/src/extension-grammar.ts` (`objectTypes[].payloadSchema` `:236`, `entityMappings[]` coerce/map_enum/compute/template, `visibility` `:321`, `objectType.capabilities` `:239`); working instance `configs/extensions/propertyme/grammar.json` (545 LOC); validator `extension-grammar-validator.ts` + `grammar-config-bridge.ts`. CC5 adds **carrier binding** (which field's overflow → octave-1 chained cell), wires it into the loader→cell-mint path (`extension-loader.ts`→`ExtensionConfig`; `provision_tenant.zig` step 7), and **deprecates the 514-LOC hand-mirror** `extensions/oddjobz/src/cell-types/job.v2.ts`. **Same rebase as §4.3's §9 cap-mirror** (manifest→generated, stop hand-mirroring) — the data-half of CC0's ratified verb-half. Roadmap presence is a CC0-style **renderer-in-loop** matrix task (do **not** hand-edit `unification-matrix.yml`). | carrier-binding + loader wiring land; oddjobz job/site/customer derive from the grammar (job.v2.ts hand-mirror deleted/generated); existing `cartridge.json`/`manifest.json` still validate; generated matrix row via the renderer; greenfield/R-3/§9/namespace gates green. |
| **CC6** | **Ingest normalization seam.** Per-source **adapter** maps raw source → canonical schema (CC5). PropertyMe-PDF / Gmail-thread / Meta-lead become *adapter configs flowing as `verb.dispatch` intents* (per `SHELL-CARTRIDGES-HATS.md`), not code. **Bootstrap path already exists:** `extensions/extraction/src/inference/pipeline.ts` (structure→taxonomy→diff→compose→AFFINE `InferredGrammar` cell; tests `propertyme-auto`/`scada-auto`) — CC6 ratifies it as the provisioning flow, not greenfield. AI fuzzy/field matching permitted **inside an adapter only** (an edge — no AI in substrate). | a non-handyman source produces a valid canonical cell with **zero extractor code edits** via the inference pipeline; `FALLBACK_OPERATOR_EMAILS` + per-agency billing hardcode (`runtime/legacy-ingest/src/extractor/email.ts`) retired to adapter config; gates green. |
| **CC7** | **Generic schema-driven renderer** in `semantos-shell`: walks the primary cell + chained carrier cells against the CC5 schema; retires hand-built oddjobz screens. **Greenfield — `extensions/navigator` is a lens-based nav/filter UI, NOT a schema renderer; do not mistake it for half-built.** The shell-purity de-wire (hardcoded `oddjobz/jam/tessera` imports+routes in `apps/semantos/lib/main.dart`,`semantos_router.dart`) falls out as a prerequisite. | a different field-set renders a sensible UI with **zero new widgets**; octave-1 overflow gets its first render path; no cartridge-name literal remains in shell `main.dart`/router; gates green. |

> **CC0 scope note (added 2026-05-19).** CC0 folded grammar/lexicon/taxonomy/capabilities into `cartridge.json` but **did not** add a load-bearing object-type/cell-**schema** section with adapter-in / renderer-out semantics. That gap is why oddjobz leaks a legacy source's field shape end-to-end (source → cell → typed model → hand-built widget, no normalization seam). **CC5 closes it**; CC6/CC7 are the ingest and shell halves. Design source: `docs/design/CARTRIDGE-CANONICAL-SCHEMA-SPINE.md`. Sequencing: CC5–CC7 land **after CC3** (golden path) and compose with CC4 fan-out (a collapsed cartridge declares its schema section). Non-conflation: the octave **storage escalation** seam (on `main`) is *not* the tessera walker/octave **registration loader**; CC5 carrier-binding depends on the former only. **Package-manager separation:** the inbuilt package manager (cell-DAG release pipeline `tools/release/`) is deliberately blob-opaque and **stays so** — CC5 schema is a loader/provisioning concern (`extension-loader.ts`/`provision_tenant.zig` step 7), never a `tools/release/` concern; `grammar.json` rides the content-addressed bundle as opaque bytes to the pipeline, load-bearing schema to the loader.

## 4. Acceptance gate (end-of-wave)

1. `cartridge.json` is the single manifest; `lexicons.yml`/§9-cap-table/matrix-row are generated from it (no parallel truth).
2. `extensions/`, `apps/world-apps/`, `packages/*_experience` collapsed into `cartridges/<id>/`; "app"/"extension" gone from canon vocabulary.
3. Brain shell + PWA shell load the same manifest; adding a cartridge edits no shell code.
4. wallet/headers infra cartridges provide the real SpvContext; SW2/cartridge-license/NL-1 stub-debt retired; their conformance exercises the real path.
5. oddjobz golden path green; jamroom + tessera + the rest migrated.
6. greenfield / R-3 / §9 / namespace gates green on `main`; K15/K3/cartridge-license/NL-1 suites unbroken; a `unification-matrix.yml` row records the axis.
7. (CC5) `cartridge.json` carries a load-bearing schema/object-type section with carrier bindings; it is the single source the adapter maps into and the renderer renders from (no parallel cell-type/typed-model truth).
8. (CC6) onboarding a different operator/trade/source adds **no extractor code**; sources are adapter configs delivered as intents; substrate stays AI-free (fuzziness lives only in adapters).
9. (CC7) the shell renders any cartridge's cells (primary + carriers) from the schema with zero per-field widgets and zero cartridge-name literals; octave-1 overflow is visible.

---

*Doc-first complete (CANONICAL-CARTRIDGE-MODEL.md RATIFIED). This wave is the deep fix; execute under `/loop`, golden-path-first, one PR per CC-row, gates green every commit.*
