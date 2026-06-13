---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/34-interactive-demo-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.770093+00:00
---

# 34 — Split `apps/site/src/components/InteractiveDemo.tsx`

**Phase:** 11 (Site + navigation) · **Depends on:** 03 · **Est. effort:** 0.5 day · **Branch:** `refactor/34-interactive-demo`

## Why

610 LOC marketing-site interactive demo: scripted flow through a Loom experience. All of it sits in one component.

## Deliverables

Create under `apps/site/src/components/interactive-demo/`:

- `atoms.ts` — local demo state atoms (`stepAtom`, `scriptedMessagesAtom`, `highlightAtom`).
- `steps/` — one file per demo step; each exports a small component + its scripted content.
- `components/demo-canvas.tsx`, `demo-navigation.tsx`, `demo-hint-overlay.tsx`.
- `scripts/scenario-*.ts` — pure data files defining the scripted runs.
- `interactive-demo.tsx` — orchestrator (≤120 LOC).
- `__tests__/*.test.tsx`.

Edit:

- `apps/site/src/components/InteractiveDemo.tsx` → re-export orchestrator.

## Acceptance criteria

- [ ] Orchestrator ≤ 120 LOC.
- [ ] Scripted content separated from render logic (pure data in `scripts/`).
- [ ] All existing site tests pass.
- [ ] `pnpm --filter @semantos/site check` passes.

## Out of scope

- Changing demo content.

## Test plan

Visual snapshot per step is unchanged.
