---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/43-grammar-validator-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.767833+00:00
---

# 43 — Split `core/protocol-types/src/extension-grammar-validator.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/43-grammar-validator`

## Why

770 LOC of nested validators for extension grammar (capabilities, verbs, schemas, bindings, policy). One error in one section blocks work on another.

## Deliverables

Create under `core/protocol-types/src/grammar/`:

- `error-collector.ts` — `ValidationErrorCollector` with path tracking; immutable `withPath(segment)`.
- `validators/capabilities.ts`
- `validators/verbs.ts`
- `validators/schemas.ts`
- `validators/bindings.ts`
- `validators/policy.ts`
- `validators/manifest.ts` — top-level manifest shape.
- `grammar-validator.ts` — orchestrator that composes the above (≤150 LOC) and exposes `validate(grammar) → Result<Valid, ValidationError[]>`.
- `__tests__/*.test.ts` — table-driven fixtures per section.

Edit:

- `core/protocol-types/src/extension-grammar-validator.ts` → re-export orchestrator.

## Acceptance criteria

- [ ] No validator file over 200 LOC.
- [ ] All existing validator tests pass unchanged.
- [ ] Error collector never mutates shared state (easy to verify: no `this` mutation in collector; `withPath` returns new instance).
- [ ] `pnpm --filter @semantos/protocol-types check` passes.

## Out of scope

- Changing the grammar or validation rules.

## Test plan

Replay an existing fixture set of ~20 valid and ~40 invalid manifests; identical pass/fail + identical error messages (snapshot).
