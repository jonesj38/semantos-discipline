---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/37-navigator-js-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.773058+00:00
---

# 37 — Split `apps/navigation_app/bsv-app/navigator.js`

**Phase:** 11 (Site + navigation) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/37-navigator-split`

## Why

607 LOC general-purpose object navigator: navigation lenses, extension management, command bar, LLM intent classification with fallback, object card rendering, activity view.

## Deliverables

Port to TS and split under `apps/navigation_app/bsv-app/navigator/`:

- `constants/lenses.ts` — `LENSES`, `DIM_TO_LENS`.
- `atoms.ts` — `activeLensAtom`, `listeningAtom`, `commandHistoryAtom`, `objectsAtom`.
- `services/llm-classifier.ts` — intent classification with fallback.
- `services/command-handler.ts` — dispatcher for `/help`, `/extensions`, `/objects`, `/create`, `/lenses`, `/status`.
- `services/command-executor.ts` — creates/modifies objects; uses port from prompt 36 if available.
- `services/object-filter.ts` — pure `filterByLens(objects, lens)`.
- `views/extension-viewer.tsx`
- `views/activity-viewer.tsx`
- `views/object-cards.tsx`
- `navigator.tsx` — composer (≤150 LOC).
- `__tests__/*.test.ts`.

Edit:

- `apps/navigation_app/bsv-app/navigator.js` → replace with thin re-export once ported to `.ts`.

## Acceptance criteria

- [ ] No file over 200 LOC.
- [ ] Kernel access via port with an explicit in-memory fallback (no silent optional chaining).
- [ ] `pnpm --filter navigation_app check` passes.

## Out of scope

- Changing navigator UX or command grammar.

## Test plan

Snapshot tests of each command's rendered output; filter tests with 5 lens × 20 object fixtures.
