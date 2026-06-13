---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/10-config-store-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.766576+00:00
---

# 10 — Split `runtime/services/src/services/ConfigStore.ts`

**Phase:** 5 (Runtime services) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/10-config-store`

## Why

497 LOC mixing extension config loading, core/domain merging, taxonomy seed application, overlay persistence (localStorage + adapter dual write), and ballot resolution.

## Deliverables

Create under `runtime/services/src/services/config-store/`:

- `config-loader.ts` — async load by ID; bundled or API; accepts `bundledExtensionsPort`.
- `config-merger.ts` — pure: `mergeExtensions(core, domain)`; de-dup types by name.
- `taxonomy-seed-applicator.ts` — pure: `applyTaxonomySeed(config, seed)`.
- `overlay-appliance.ts` — pure: `applyAllOverlays(config, overlays)`.
- `intent-taxonomy-manager.ts` — load + register taxonomies; exposes `register/unregister`.
- `ballot-resolver.ts` — pure: `resolveTaxonomyBallot(ballot)`.
- `ports.ts` — `bundledExtensionsPort`, `overlayPersistencePort`, `intentTaxonomyRegistrarPort`.
- `atoms.ts` — `configAtom`, `activeExtensionIdAtom`, `overlaysAtom`, `taxonomySeedAtom`, `coreTaxonomyLoadedAtom`.
- `__tests__/*.test.ts`.

Edit:

- `runtime/services/src/services/ConfigStore.ts` → thin facade.

## Acceptance criteria

- [ ] Dual localStorage + adapter persistence collapsed to single port (impl handles any required migration at init).
- [ ] All existing config tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing the bundled extension set.
- Changing ballot semantics.

## Test plan

Fixture: 10 real extension configs + 5 overlays + 3 ballots. Golden merge/apply output identical pre- and post-refactor.
