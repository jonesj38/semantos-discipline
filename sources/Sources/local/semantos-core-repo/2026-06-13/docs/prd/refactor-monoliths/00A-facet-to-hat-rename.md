---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/00A-facet-to-hat-rename.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.777835+00:00
---

# 00A — Rename `Facet` → `Hat` across the codebase

**Phase:** 0 (Pre-refactor) · **Depends on:** none · **Est. effort:** 1–1.5 days · **Branch:** `refactor/00A-facet-to-hat`

## Why

`docs/design/LOOM-SELF-HOSTING.md` (lines 25–51) already specifies the rename: the user-facing concept is a **Hat**, not a Facet. The migration was started at the top of the intent pipeline (`HatContext`, `hat-context.ts`, calendar `HatPayload`/`HatRecord`) but never pushed through to the canonical type, the IdentityStore surface, the UI components, or the shell commands. Current snapshot:

- 1,842 occurrences of `facet`/`Facet` across 246 files.
- Mixed vocabulary in a single file: `buildHatContext` does `const hat = input.identity.getActiveFacet()` and returns `{ hatId, facetId }` — both names, same value.
- Canonical type still `interface Facet` at `runtime/services/src/types/loom.ts:95`.

Do this **before** the monolith split (prompts 01–44). Two of the 44 prompts (03, 11) currently use "facet" in their deliverable names; if the rename lands after splits, every newly created sub-file inherits the old name and the rename surface area multiplies.

## Scope

This is a **naming-only** refactor. Zero behavior change. Zero schema change on the wire. The `LoomObject.kind` string for a hat stays whatever it is today (audit and note it — do not rename it in this PR; that's a separate data-migration concern).

## Deliverables

### 1. Canonical type rename

- `runtime/services/src/types/loom.ts` — `interface Facet` → `interface Hat`. Keep a deprecated `type Facet = Hat` alias and mark with `/** @deprecated use Hat */` so any dependent source outside this repo still compiles one release.
- `runtime/services/src/types/loom.ts` — on `Identity`:
  - `facets: Facet[]` → `hats: Hat[]`.
  - `activeFacetId: string` → `activeHatId: string`.
  - Add a deprecated getter/property shim layer ONLY if any external consumer is expected; otherwise do a hard rename (preferred — grep shows all consumers are in-repo).
- `runtime/services/src/types/loom.ts` — on `ConversationMessage`: `facetId: string` → `hatId: string`.
- Mirror all of the above in `apps/loom-react/src/types/loom.d.ts`.

### 2. IdentityStore API rename

- `runtime/services/src/services/IdentityStore.ts`:
  - `getActiveFacet()` → `getActiveHat()`.
  - `setActiveFacet(id)` → `setActiveHat(id)`.
  - `addFacet` / `removeFacet` / `updateFacet` → `addHat` / `removeHat` / `updateHat`.
  - Any internal `#facets`, `facetsById`, etc. renamed.
- `apps/loom-react/src/services/IdentityStore.js` / `.d.ts` — same.

### 3. Intent pipeline cleanup

- `runtime/intent/src/hat-context.ts`:
  - `FacetLike` → `HatLike`.
  - `IdentityLike.facets: FacetLike[]` → `hats: HatLike[]`.
  - `IdentityLike.activeFacetId` → `activeHatId`.
  - `IdentityServiceLike.getActiveFacet()` → `getActiveHat()`.
  - Remove the `facetId` field from `HatContext` (it duplicates `hatId`). Update all consumers.
- `runtime/intent/src/types.ts` `HatContext` — drop `facetId` duplicate.

### 4. UI components

- File renames (also update all imports + the component's default export name):
  - `apps/loom-react/src/helm/FacetSwitcher.tsx` → `HatSwitcher.tsx`.
  - `apps/loom-react/src/identity/FacetSelector.tsx` → `HatSelector.tsx`.
  - `apps/loom-react/src/identity/FacetManager.tsx` → `HatManager.tsx`.
- User-visible strings: `"facet"` / `"Facet"` → `"hat"` / `"Hat"` in JSX, labels, placeholders, toasts, aria-labels. This is the user-visible payoff — "Switch hat" is the target UX.

### 5. Config / JSON data

- `configs/extensions/*.json` — audit every occurrence; rename JSON keys **only if** they're consumed by TypeScript code paths that also get renamed. If a key is part of a published extension manifest schema, leave it and file a follow-up instead.
- Add a note in the PR description listing any JSON keys deliberately left on the old name, with a link to the follow-up issue.

### 6. Shell commands / CLI

- `switch <name>` currently maps to "switch active facet". Keep the verb `switch` (user-facing), but rename underlying handler functions + any internal event names (`facet_switched` → `hat_switched`). Cross-reference `docs/design/LOOM-SELF-HOSTING.md` lines 138–175 (evidence chain `hat_switched` patch kind).
- If any config or JSON mentions `facet_switched`, decide: keep wire name for replay compatibility (document), or migrate with a data script (out of scope here — file a follow-up).

### 7. Tests

- Test file renames tracked with `git mv` so history is preserved.
- Fixture data inside tests (`facets: [...]`) renamed.
- Snapshot files updated in one commit with `-u`.

### 8. Design docs

- `docs/prd/PHASE-8.5-PROMPT.md`, `docs/prd/PHASE-8.5-IDENTITY-PLANE.md` — rename `interface Facet` → `interface Hat` in the code samples (these are not executable; fine to edit in this PR).
- `docs/INTENT-PIPELINE.md` — audit `HatContext` section; remove any `facetId` references if the field is being dropped.
- Leave `docs/design/LOOM-SELF-HOSTING.md` mostly alone — the "Old/New" rename table is historical context; keep it.

## Mechanics — do this as a codemod, not a blind search-and-replace

Write a one-off `scripts/rename-facet-to-hat.ts` (or `.mjs`) using `ts-morph` that:

1. Renames the `Facet` type → `Hat` (via `SymbolExtension.rename`, not text replace — this handles all references).
2. Renames the listed methods (`getActiveFacet` → `getActiveHat`, etc.) via symbol rename.
3. Renames property names (`facets` → `hats`, `activeFacetId` → `activeHatId`, `facetId` → `hatId`) via symbol rename — ts-morph will refuse if a conflict exists, which is what we want.
4. Renames files with `Facet` in the name via `SourceFile.move`.

Then a **second pass** for strings/comments/docs that the AST-aware pass won't touch:

5. `rg -l '\bfacet\b' | xargs sed -i 's/\bfacet\b/hat/g; s/\bFacet\b/Hat/g'` — but run it only over `.tsx`/`.jsx`/`.md` files and only for JSX strings/comments. Review the diff by hand before commit.

Never commit the codemod output without reviewing the JSON configs and any wire-level identifiers.

## Acceptance criteria

- [ ] `rg -i '\bfacet\b' -g '!docs/design/LOOM-SELF-HOSTING.md' -g '!**/.git/**'` returns only intentional uses (deprecated aliases, historical design docs, changelog entries) — with each one listed and justified in the PR description.
- [ ] `pnpm -r check` passes.
- [ ] `pnpm -r test` passes.
- [ ] `bun test tests/gates/` passes (no new allowlist entries; no gate breakage).
- [ ] Grep for `facetId.*hatId` or `hatId.*facetId` on the same object literal returns zero — no dual-name return shapes.
- [ ] Every UI component rendering a hat uses the word "hat" in its user-visible strings.
- [ ] No wire/schema change: the `LoomObject.kind` value used for hats is unchanged; no extension manifest `.json` schema keys were renamed unless audited.

## Out of scope

- Renaming `Workbench → Loom` (already done per design doc).
- Renaming `LoomObject → SemanticObject` (separate migration; not in this PR).
- Renaming `LoomObject.kind` string values (data migration; file a follow-up).
- Any behavior change — reducers, selectors, FSM transitions stay bit-identical.
- Changing extension manifest JSON schema keys (audit and note; don't migrate here).

## Risks & mitigations

- **Risk:** a downstream consumer (e.g. an extension package) imports `Facet`. *Mitigation:* keep `export type Facet = Hat` alias with `@deprecated` for one release.
- **Risk:** UI state persisted to disk/localStorage under key `activeFacetId`. *Mitigation:* add a one-shot read-time shim in whatever hydration code touches that key: prefer `activeHatId`, fall back to `activeFacetId`, write back as `activeHatId`. Document in PR.
- **Risk:** evidence-chain `hat_switched` vs. current `facet_switched` patch kind. *Mitigation:* decide and document — keep the old wire name for replay compatibility (preferred), or add a mapping in the reader side.

## Test plan

1. `pnpm -r check && pnpm -r test && bun test tests/gates/` all green.
2. Manual smoke in loom-react: sign in, open `HatSwitcher`, switch hats, confirm evidence-chain entry appears, confirm conversation attribution still shows correct hat.
3. Replay a persisted session fixture (if one exists) to verify `activeFacetId` shim reads old state correctly.
4. Grep audit — paste the output into PR description: `rg -i '\bfacet\b' -g '!docs/design/LOOM-SELF-HOSTING.md'`.

## Follow-ups to file (out of scope here)

- FUP-1: migrate `facet_switched` evidence-chain patch kind (needs data plan).
- FUP-2: rename `LoomObject` → `SemanticObject`.
- FUP-3: audit and rename extension manifest JSON schema keys.
