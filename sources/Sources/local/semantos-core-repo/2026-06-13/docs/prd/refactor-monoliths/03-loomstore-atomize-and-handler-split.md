---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/03-loomstore-atomize-and-handler-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.769085+00:00
---

# 03 — LoomStore: atomize state + split handlers

**Phase:** 2 (LoomStore) · **Depends on:** 01, 02 · **Est. effort:** 1 day · **Branch:** `refactor/03-loomstore-atoms`

## Why

With the reducer pure (prompt 02), we can now move state ownership into atoms. Every loom-react panel currently calls `loomStore.getState()` and reaches into a big object; once state lives in atom selectors, panels subscribe to the slice they need. This is the largest downstream win in the whole refactor — Phase 10 panels shed ~40% of their code because of it.

Also splits lifecycle / dispute / channel handlers out of `LoomStore.ts` so the facade shrinks to a thin orchestrator.

## Deliverables

Create:

- `runtime/services/src/services/loom/loom-atoms.ts` —
  - `export const loomStateAtom = atom<LoomState>(initial)`
  - `export const dispatch = (a: LoomAction) => set(loomStateAtom, loomReducer(get(loomStateAtom), a))`
  - Derived atoms: `objectsByHatAtom(hatId)`, `selectedObjectAtom`, `channelsByStatusAtom(status)`, `patchQueueAtom`. (Uses post-rename vocabulary from prompt 00A.)
- `runtime/services/src/services/loom/handlers/object-lifecycle.ts` — `createObjectFromType`, `consumeObject`, `transitionVisibility`. Each accepts ports from `core/protocol-types` (see prompt 14 for the port definitions — if not yet available, define a local `UnresolvedPort` placeholder to unblock).
- `runtime/services/src/services/loom/handlers/dispute-resolution.ts` — `resolveDisputeReclassification`.
- `runtime/services/src/services/loom/handlers/channel-metering.ts` — `createPaymentChannel`, `advanceChannelPhase`, `recordChannelTransaction`, `recordSettlement`. Calls the Plexus + CashLanes ports.
- `runtime/services/src/services/loom/ports.ts` — port declarations used by handlers: `hashPort`, `plexusPort`, `cashLanesPort`, `flowRunnerPort`.
- `runtime/services/src/services/loom/effects/patch-recorder.ts` — effect atom that watches `patchQueueAtom` and persists via the configured adapter.
- `runtime/services/src/services/loom/__tests__/handlers/*.test.ts` — one test file per handler module, 10+ cases each.

Edit:

- `runtime/services/src/services/LoomStore.ts` — shrink to a facade exposing the same public API by delegating to atoms + handlers. Keep deprecation JSDoc: `@deprecated — prefer importing loomStateAtom + dispatch from loom/loom-atoms.ts`.

## Acceptance criteria

- [ ] `LoomStore.ts` ≤ 150 LOC.
- [ ] Every handler file ≤ 200 LOC.
- [ ] All existing LoomStore tests pass unchanged.
- [ ] Three new tests that read state via `get(loomStateAtom)` instead of `loomStore.getState()` — same result.
- [ ] One panel (`ChatView.tsx`) is pointed at the atom directly as proof-of-concept (spot-check only; full migration is prompt 31).
- [ ] `pnpm -r check` passes.
- [ ] `grep -rn "new LoomStore" apps/loom-react | wc -l` — no new instantiations added.

## Out of scope

- Converting all loom-react panels (prompts 30–33).
- Building the Plexus/CashLanes ports' real impls (prompt 14).
- Removing LoomStore class — it stays as a facade for now.

## Test plan

Reuse the golden snapshot from prompt 02's test plan. `LoomStore` facade must produce the same output. Add: atom subscription test showing a panel-style consumer sees updates on dispatch.
