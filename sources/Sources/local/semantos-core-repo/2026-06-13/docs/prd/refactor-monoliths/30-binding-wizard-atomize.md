---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/30-binding-wizard-atomize.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.767085+00:00
---

# 30 — Atomize `apps/loom-react/src/panels/BindingWizard.tsx`

**Phase:** 10 (Loom-react panels) · **Depends on:** 01, 03 · **Est. effort:** 1 day · **Branch:** `refactor/30-binding-wizard`

## Why

658 LOC 6-step modal wizard mixing credential encryption, L0/L1 constraint validation, version compatibility checks, test connection, grammar inspection, and binding object creation. Textbook case for atomic state + step-per-file extraction.

## Deliverables

Add React bindings for `@semantos/state`:

- `core/state/src/react.ts` — `useAtom(atom)`, `useAtomValue(atom)`, `useSetAtom(atom)`. Minimal hooks over subscribe. Published from `core/state` with a `"./react"` export.

Create under `apps/loom-react/src/panels/binding-wizard/`:

- `atoms.ts` — `wizardStepAtom`, `credentialValuesAtom`, `overridesAtom`, `versionPolicyAtom`, `testResultAtom`. Derived: `canProceedSelector`.
- `steps/step-1-select-extension.tsx`
- `steps/step-2-credentials.tsx`
- `steps/step-3-overrides.tsx`
- `steps/step-4-version-policy.tsx`
- `steps/step-5-test-connection.tsx`
- `steps/step-6-confirm.tsx`
- `services/binding-validator.ts` — L0/L1 constraint enforcement, version compat. Pure.
- `services/credential-encryptor.ts` — crypto wrapping. Effect atom.
- `services/binding-payload-builder.ts` — pure `buildBindingPayload()`.
- `default-governance-policy.ts` — reusable constants.
- `binding-wizard.tsx` — orchestrator component (≤100 LOC).
- `__tests__/*.test.{ts,tsx}`.

Edit:

- `apps/loom-react/src/panels/BindingWizard.tsx` → re-export the orchestrator.

## Acceptance criteria

- [ ] Orchestrator component ≤ 100 LOC.
- [ ] Each step component ≤ 120 LOC.
- [ ] Validators are pure and independently tested.
- [ ] Encryption testable without real crypto (stub `credentialEncryptorPort`).
- [ ] All existing wizard tests pass.
- [ ] `pnpm --filter @semantos/loom-react check` passes.

## Out of scope

- Changing wizard steps or UX.
- Designing new React bindings beyond the minimal hooks in `core/state/src/react.ts`.

## Test plan

Playwright (or existing equivalent) walk-through of the wizard: start → finish produces identical binding payload to pre-refactor run.
