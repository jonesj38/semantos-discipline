---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/02-loomstore-pure-reducer.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.777584+00:00
---

# 02 — LoomStore: extract pure reducer

**Phase:** 2 (LoomStore) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/02-loomstore-reducer`

## Why

`runtime/services/src/services/LoomStore.ts` is 583 LOC mixing pure reducer logic with object creation, service calls (Plexus, CashLanes, FlowRunner), sha256 hashing, and patch recording side effects. Before we can atomize it (prompt 03), the reducer has to be pulled out as a pure function. This is the smallest, safest first step — zero behavior change, all new pure logic covered by snapshot tests.

Read the file first. Key sections:
- Lines 34–120: state shape, init.
- Lines 142–183: visibility transition logic (pure).
- Lines 200–320: ADD_CARD / REMOVE_CARD / PATCH_OBJECT handling.
- Lines 372–541: payment channel orchestration (side-effectful — leave in class for now).

## Deliverables

Create:

- `runtime/services/src/services/loom/loom-reducer.ts` — `export function loomReducer(state: LoomState, action: LoomAction): LoomState`. Pure; no `this`, no async, no service calls.
- `runtime/services/src/services/loom/loom-types.ts` — move `LoomState`, `LoomAction` (all union members) here. Export from this file.
- `runtime/services/src/services/loom/visibility-rules.ts` — `isVisibilityTransitionAllowed(from, to)` + transition validation used by reducer.
- `runtime/services/src/services/loom/__tests__/loom-reducer.test.ts` — 30+ cases covering each action type, invalid transitions, edge cases.

Edit:

- `runtime/services/src/services/LoomStore.ts` — replace its internal transition logic with a call to `loomReducer`. All class methods that were case-handlers now dispatch a typed action to `loomReducer` and assign the result to `this.state`. Service calls (FlowRunner, channel metering, sha256) stay in the class for this PR.

## Constraints

- Reducer must be pure: `(state, action) => state`. No mutations. Use structural sharing (spread) not deep clone.
- All ambient imports into reducer file must be types only (`import type`).
- No behavior change. The facade class LoomStore continues to expose the same public API.

## Acceptance criteria

- [ ] `pnpm --filter @semantos/runtime-services test` — all old LoomStore tests still pass.
- [ ] New reducer tests: 30+ cases, cover every action type in the union, plus invalid-transition cases.
- [ ] Reducer file has zero runtime imports except from `@semantos/state` (if used for type tokens) and peer pure helpers.
- [ ] `grep -n "this\." runtime/services/src/services/loom/loom-reducer.ts` returns 0 results.
- [ ] `pnpm -r check` passes.
- [ ] LOC of `LoomStore.ts` drops by ~150 LOC.

## Out of scope

- Converting state to atoms (prompt 03).
- Splitting lifecycle/dispute/channel handlers (prompt 03).
- Any change to how callers use LoomStore.

## Test plan

Golden snapshots: before merging, record `JSON.stringify(loomStore.getState())` after a scripted sequence of 20 actions from an existing e2e test. After merging, the same sequence must produce byte-identical snapshot.
