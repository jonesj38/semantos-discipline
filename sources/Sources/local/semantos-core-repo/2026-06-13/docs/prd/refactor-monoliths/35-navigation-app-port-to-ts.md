---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/35-navigation-app-port-to-ts.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.767340+00:00
---

# 35 — Port `apps/navigation_app/bsv-app/navigation.js` to TypeScript

**Phase:** 11 (Site + navigation) · **Depends on:** none · **Est. effort:** 1 day · **Branch:** `refactor/35-navigation-ts-port`

## Why

1114 LOC vanilla JS file with DOM munging mixed into business logic. Before splitting, get TypeScript checking in place so the subsequent split (prompt 36) has type guarantees.

## Deliverables

- Rename `apps/navigation_app/bsv-app/navigation.js` → `apps/navigation_app/bsv-app/navigation.ts`.
- Add types for: `ProcessCycle`, `ObjectType`, `Dimension`, `Overlay`, `ChatMessage`, `LoomObject`.
- Fix all implicit-any errors; enable strict mode for the file.
- Update any `apps/navigation_app/bsv-app/kernel-bridge.ts` build-script reference that depended on the `.js` filename (e.g. in root `package.json` `build:bridge` script — note: this currently references `kernel-bridge.ts`, not navigation.ts, so likely no change needed; verify).

## Acceptance criteria

- [ ] `tsc --noEmit` on the navigation_app package passes.
- [ ] Zero `any` or `@ts-ignore` introductions (if unavoidable, add comment + filed TODO with follow-up).
- [ ] Runtime behavior unchanged — app still boots and reaches the main dashboard.
- [ ] `pnpm -r check` passes.

## Out of scope

- Splitting the file (prompt 36).
- Changing app UX.

## Test plan

Manual smoke: app loads, dashboard renders, chat accepts input, one release wizard run completes.
