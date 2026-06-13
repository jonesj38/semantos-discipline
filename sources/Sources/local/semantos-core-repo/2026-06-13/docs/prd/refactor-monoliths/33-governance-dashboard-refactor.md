---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/33-governance-dashboard-refactor.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.769585+00:00
---

# 33 — Refactor `apps/loom-react/src/panels/GovernanceDashboard.tsx`

**Phase:** 10 (Loom-react panels) · **Depends on:** 03 · **Est. effort:** 0.5 day · **Branch:** `refactor/33-governance-dashboard`

## Why

543 LOC dashboard rendering ballots, disputes, capability overrides, bindings. Same pattern.

## Deliverables

Create under `apps/loom-react/src/panels/governance-dashboard/`:

- `atoms.ts` — `ballotsAtom`, `disputesAtom`, `bindingsAtom`; derived from `loomStateAtom`.
- `components/ballots-table.tsx`
- `components/disputes-table.tsx`
- `components/capability-override-editor.tsx`
- `components/binding-list.tsx`
- `governance-dashboard.tsx` — orchestrator (≤120 LOC).
- `__tests__/*.test.tsx`.

Edit:

- `apps/loom-react/src/panels/GovernanceDashboard.tsx` → re-export orchestrator.

## Acceptance criteria

- [ ] Zero direct `loomStore.getState()`.
- [ ] Every component ≤ 150 LOC.
- [ ] All existing tests pass.
- [ ] `pnpm --filter @semantos/loom-react check` passes.

## Out of scope

- Changing governance semantics or UX.

## Test plan

Fixture state → identical rendered table content for 10 scenarios.
