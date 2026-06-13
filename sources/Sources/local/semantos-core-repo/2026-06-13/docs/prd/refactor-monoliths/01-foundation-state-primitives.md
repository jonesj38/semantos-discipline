---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/01-foundation-state-primitives.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.774814+00:00
---

# 01 — Foundation: state primitives

**Phase:** 1 (Foundation) · **Depends on:** none · **Est. effort:** 1 day · **Branch:** `refactor/01-state-primitives`

## Why

Every subsequent prompt in this set relies on a small, consistent atomic-state vocabulary (`atom`, `derived`, `effect`, `port`, `registry`, `eventBus`, `slice`). Today, each monolith reinvents its own state ownership model — class fields, module-level singletons, optional setter services. This prompt introduces the shared primitives layer so the rest of the refactor is mechanical.

Read `MONOLITH_DECOMPOSITION.md` § "Cross-cutting architectural moves" § 1 for the target shape.

## Deliverables

Create a new workspace package `core/state/` (new entry in `pnpm-workspace.yaml` already matches `core/*`).

- `core/state/package.json` — `@semantos/state`, private, TypeScript ESM.
- `core/state/tsconfig.json` — extends `../../tsconfig.base.json`.
- `core/state/src/atom.ts` — `atom<T>(initial: T): Atom<T>`; `get(atom)`, `set(atom, value)`, `subscribe(atom, fn)`.
- `core/state/src/derived.ts` — `derived<T>(fn: (get) => T): Atom<T>` — memoized read, re-fires on dependency change.
- `core/state/src/effect.ts` — `effect(fn: (get) => void | (() => void)): Dispose` — runs now, re-runs on dependency change, supports teardown.
- `core/state/src/port.ts` — `port<T>(name: string): Port<T>` with `bind(impl)`, `get()` (throws if unbound with helpful message), `unbind()` for tests.
- `core/state/src/registry.ts` — `Registry<H>()` with `register(key, handler)`, `require(key)`, `get(key)`, `has(key)`, `keys()`.
- `core/state/src/event-bus.ts` — `eventBus<E>()` with `emit(e)`, `on(fn): Dispose`, `once(fn): Dispose`.
- `core/state/src/slice.ts` — `slice<S, A>({ reducer, initial })` returns `{ stateAtom, dispatch }`. Built on `atom` + `effect`.
- `core/state/src/index.ts` — public re-exports only.
- `core/state/src/__tests__/*.test.ts` — bun tests per primitive (≥5 cases each).

## Constraints

- Zero runtime deps. TypeScript strict mode. ESM only.
- `atom` must be synchronous read, synchronous set. No Promises inside the primitive.
- `derived` must track dependencies only on reads that happen during `fn` execution (no static dep lists).
- `port` unbound behavior: throws `PortUnboundError` with `{ portName }` and a clear message telling the dev to call `bind()` at app boot.
- `slice` is sugar over `atom` — do not duplicate atom internals.

## Acceptance criteria

- [ ] `pnpm -r check` passes.
- [ ] `pnpm --filter @semantos/state test` — all tests pass.
- [ ] No export from `index.ts` uses `any` in its public signature.
- [ ] README at `core/state/README.md` with 5 ~10-line examples (atom, derived, effect, port, slice).
- [ ] Added to `pnpm-workspace.yaml` if needed (verify `core/*` glob picks it up).
- [ ] `tests/gates/import-boundaries.test.ts` not modified.

## Out of scope

- No React bindings in this PR (do those in prompt 30 alongside loom-react changes).
- No refactors of existing code to use the primitives — that's prompt 02 onward.
- No persistence or devtools integration.

## Test plan

- atom: init, get, set, subscribe, unsubscribe.
- derived: memoization, cascading deps, cycle detection throws.
- effect: initial run, re-run on dep change, teardown called on dep change, teardown called on dispose.
- port: unbound throws, bound returns impl, unbind resets, double-bind warning.
- registry: register/require, require throws on missing key with helpful msg, keys().
- eventBus: emit before subscribe → not received; subscribe after → receives new events; once() fires exactly once.
- slice: dispatch updates stateAtom, subscribers see new state, reducer is pure.
