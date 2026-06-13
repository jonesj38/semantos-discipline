---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/08-verb-registry-router-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.766826+00:00
---

# 08 — Verb registry + collapse `router.ts` / `router-browser.ts`

**Phase:** 4 (Router) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/08-verb-registry`

## Why

`runtime/shell/src/router.ts` (800 LOC) and `runtime/shell/src/router-browser.ts` (677 LOC) duplicate ~80% of their code. The browser variant stubs node-only verbs with `NOT_IN_BROWSER`. Merge both into a single registry; per-platform differences become registration-time choices.

## Deliverables

Create under `runtime/shell/src/router/`:

- `verb-registry.ts` — built on `Registry<VerbHandler>` from `@semantos/state`.
- `capability-gate.ts` — pure `checkPlexusCapability(ctx, verb): { allowed, requiredCapability, message }`.
- `dry-run-mode.ts` — selector/helper.
- `intent-pipeline-adapter.ts` — conditional intent-pipeline routing.
- `verb-handlers/` — one handler per file: `new.ts`, `patch.ts`, `transition.ts`, `flow.ts`, `governance.ts`, `taxonomy.ts`, `grammar.ts`, `infer.ts`, `extract.ts`, `cdm.ts`, `game.ts`, `extension.ts`, plus any others in the current switch.
- `verb-stub.ts` — factory for `NOT_IN_BROWSER` stubs given a reason.
- `router-core.ts` — `route(cmd, ctx)` dispatches via registry + capability gate.
- `bootstrap-node.ts` — registers all handlers.
- `bootstrap-browser.ts` — registers only browser-safe handlers; binds stubs for the rest.
- `__tests__/*.test.ts`.

Edit:

- `runtime/shell/src/router.ts` → `export { route } from './router/router-core'; export { bootstrapNode } from './router/bootstrap-node';` plus deprecation JSDoc.
- `runtime/shell/src/router-browser.ts` → export from `bootstrap-browser.ts`.

## Acceptance criteria

- [ ] Every handler file ≤ 150 LOC.
- [ ] Zero code duplication between the two boot files (diff them: they must import different registration sets only).
- [ ] Existing router tests pass unchanged.
- [ ] New test: adding a verb at runtime via `register()` works end-to-end.
- [ ] Net LOC deletion of ~500 across `router.ts` + `router-browser.ts`.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing what any specific verb does.
- Plugin-installed verbs at runtime (the registry enables it, but wiring the extension-manager comes later).

## Test plan

Contract test: every verb that existed pre-refactor resolves to its handler and returns identical results under both boot files for the node-safe subset.
