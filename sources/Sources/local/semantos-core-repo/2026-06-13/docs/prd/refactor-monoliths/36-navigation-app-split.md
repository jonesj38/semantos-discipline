---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/36-navigation-app-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.765797+00:00
---

# 36 — Split `apps/navigation_app/bsv-app/navigation.ts`

**Phase:** 11 (Site + navigation) · **Depends on:** 01, 35 · **Est. effort:** 1 day · **Branch:** `refactor/36-navigation-split`

## Why

With TS in place (prompt 35), break the 1114 LOC shell into focused modules using atoms for state.

## Deliverables

Create under `apps/navigation_app/bsv-app/navigation/`:

- `constants/process-cycles.ts` — `PROCESS_CYCLES` array.
- `constants/object-types.ts` — `OBJECT_TYPES`, icon/label mappings.
- `constants/dimensions.ts` — `DIMENSIONS`.
- `atoms.ts` — `messagesAtom`, `objectsAtom`, `dimensionScoresAtom`, `releaseTimerAtom`, `streakAtom`, `apiKeyAtom`.
- `services/llm-service.ts` — OpenRouter BYOK wrapper; action extraction.
- `services/kernel-bridge.ts` — detectKernel/detectCWI/CardDataManager integration.
- `services/object-factory.ts` — InMemory + Kernel impls behind a port.
- `overlays/release-wizard.tsx` — form + timer + word count.
- `overlays/review-wizard.tsx` — evening review multi-step.
- `overlays/intention-wizard.tsx` — morning intention multi-step.
- `views/dashboard.tsx`, `views/insights.tsx`, `views/process-map.tsx`, `views/chat.tsx`.
- `navigation-app.tsx` — shell composer (≤150 LOC).
- `__tests__/*.test.ts`.

Edit:

- `apps/navigation_app/bsv-app/navigation.ts` → re-export shell composer.

## Acceptance criteria

- [ ] No file over 220 LOC.
- [ ] DOM manipulation isolated to view components; no `innerHTML` in shell or services.
- [ ] API key accessed via atom (no direct `localStorage` reads scattered across files).
- [ ] `pnpm --filter navigation_app check` passes.

## Out of scope

- Changing UX or process cycle content.

## Test plan

Manual smoke through each overlay; all complete end-to-end identically.
