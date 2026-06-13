---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/28-scada-authorization-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.775325+00:00
---

# 28 — Split `extensions/scada/src/authorization.ts`

**Phase:** 9 (Game extensions) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/28-scada-authorization`

## Why

580 LOC SCADA authorization module mixing capability evaluation, signer verification, role mapping, audit logging, and decision caching.

## Deliverables

Create under `extensions/scada/src/authorization/`:

- `capability-evaluator.ts` — pure: does cert have flag? (reuse existing `@semantos/capability-token`).
- `role-mapper.ts` — pure: role → required capabilities.
- `signer-verifier.ts` — wraps signature check via `signerPort`.
- `audit-logger.ts` — effect atom subscribed to decision events.
- `decision-cache.ts` — atom-backed cache with TTL.
- `authorization-facade.ts` — orchestrator.
- `__tests__/*.test.ts`.

Edit:

- `extensions/scada/src/authorization.ts` → re-export facade.

## Acceptance criteria

- [ ] Zero behavior change — SCADA is safety-critical.
- [ ] Audit log output structurally identical to pre-refactor (field names, ordering).
- [ ] All existing scada tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Any change to authorization semantics or policy definitions.

## Test plan

Record 50 authorization decisions from current code with fixture inputs. Replay through new facade; decisions and audit logs byte-identical.
