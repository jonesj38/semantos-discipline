# Semantos Discipline Methodology and Evidence Rules

## Status

This methodology is a deterministic discipline policy artifact created after the first Shad methodology stage stopped partial with `budget_time` and produced no usable result. It is intentionally concise and serves as the authority contract for the subsequent focused Semantos discipline runs.

## Source authority hierarchy

For Semantos, claims must be ranked by the type of source they cite.

| Tier | Evidence type | Use for | Examples |
|---|---|---|---|
| 1 | Executable/source behavior | Runtime, architecture, APIs, services, data/control flow, implemented protocols | `runtime/**`, `core/**`, `packages/**`, `apps/**`, `cartridges/**`, `db/**` |
| 2 | Verification/build evidence | Formal methods, tests, CI/build/deploy status, supported commands | `proofs/**`, `tests/**`, fuzz files, `package.json`, `pnpm-workspace.yaml`, `tsconfig*.json`, Docker/systemd/scripts |
| 3 | Configuration/operations | Deployment shape, runtime wiring, environment assumptions | `configs/**`, `scripts/**`, `tools/**`, Docker files, systemd units, `.github/**` |
| 4 | Documentation/plans | Terminology, intent, roadmap, explanatory framing | `docs/**`, `research/**`, READMEs, planning notes |
| 5 | Prior Shad outputs | Draft interpretations only | `runs/**`, prior `artifacts/**` |

## Conflict rule

If docs/plans conflict with code, proofs, tests, manifests, or config, prefer the executable/formal/config evidence and record the discrepancy.

Docs may explain why something exists, but they cannot prove that behavior is currently implemented.

## Required citation policy

Major claims in discipline artifacts should cite concrete file paths and, where possible, symbols/modules/commands. Avoid generic references like “the codebase says.”

Minimum evidence expectations:

- Runtime behavior: cite `runtime/**`, `core/**`, package/app/cartridge source, or tests.
- Protocol/security/capability claims: cite implementation files, tests, config, or protocol packages; docs are secondary.
- Storage/data model claims: cite `db/**`, data model source, config, persistence code, or tests.
- Formal verification claims: cite Lean/TLA/fuzz/test assets under `proofs/**` or test folders. Do not claim end-to-end verification unless the source evidence supports it.
- Developer workflow claims: cite manifests, scripts, Docker/systemd files, CI config, or checked commands.
- Product/domain framing: docs may be used, but should be labeled as framing/intent unless backed by implementation.

## Focused analysis questions

The Semantos discipline should be built from separate focused runs/artifacts:

1. `architecture.md` — What are the major source subsystems, packages, apps, cartridges, and runtime components?
2. `runtime-concepts.md` — What runtime/execution model is actually represented in source?
3. `protocols-security.md` — What identity, authorization, capability, protocol, and trust-boundary surfaces exist?
4. `storage-data-model.md` — What persistence/data models, stores, schemas, events, and storage flows exist?
5. `formal-methods.md` — What Lean/TLA/fuzz/test assets exist, and what claims do they support?
6. `developer-workflows.md` — What build/test/dev/deploy workflows are supported by manifests/scripts/config?
7. `pitfalls-checklists.md` — What mistakes should future agents avoid when modifying Semantos?
8. `routing-hints.md` — When should future agents use this discipline and which artifacts should they consult?
9. Final synthesis — What should future agents know after reading verified focused artifacts?

## Quality gate rules

A Semantos discipline artifact should fail or be marked partial if it:

- relies primarily on docs/plans for behavior claims;
- lacks concrete file-path evidence;
- claims artifacts/files/commits exist without filesystem verification;
- overclaims formal proof coverage;
- hides uncertainty or stale-source risk;
- invents implementation plans rather than describing current source;
- omits runtime, formal/test, workflow, or source-authority caveats.

## Output package requirements

The final discipline package should include:

- `00-Final-Reports/semantos-discipline-report.md`
- `01-Methodology/evidence-rules.md`
- `01-Methodology/quality-gate.md`
- `02-Source-Map/source-map.md`
- `03-Analysis/architecture.md`
- `03-Analysis/runtime-concepts.md`
- `03-Analysis/protocols-security.md`
- `03-Analysis/storage-data-model.md`
- `03-Analysis/formal-methods.md`
- `03-Analysis/developer-workflows.md`
- `03-Analysis/pitfalls-checklists.md`
- `03-Analysis/routing-hints.md`
- `04-Data/corpus-manifest.json`
- `04-Data/source-authority.json`
- `04-Data/artifact-manifest.json`
- raw run prompts/logs/outputs under `07-Out-Reports/`

## Operating principle

The discipline is not a marketing summary. It is a future-agent operating manual grounded in source evidence. It should help an agent answer, “What is safe and true to assume about this corpus, and where must I inspect source before acting?”
