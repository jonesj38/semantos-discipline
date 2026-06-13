---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.469391+00:00
---

# packages/scada/scada/src/authorization.ts

```ts
/**
 * @deprecated Import from `./authorization/` (the sub-module split out
 * of this file in refactor prompt 28). This file remains as a
 * byte-identical re-export shim so existing
 *   `import { CommandAuthorizationEngine } from '.../authorization'`
 * call sites continue to compile while they migrate.
 *
 * Per-concern modules under `./authorization/`:
 *   - capability-evaluator.ts   role x capability rule (pure)
 *   - role-mapper.ts            role -> caps; supervisor predicate
 *   - signer-verifier.ts        wraps `signerPort`
 *   - audit-logger.ts           DecisionEvent bus -> AuditEntry[]
 *   - decision-cache.ts         atom-backed TTL cache
 *   - interlock-evaluator.ts    Phase 29.5 kernel + legacy shim path
 *   - issue-command-flow.ts     multi-step command pipeline
 *   - shift-handover-flow.ts    capability transfer
 *   - alarm-flow.ts             LINEAR alarm acknowledgement
 *   - authorization-facade.ts   `CommandAuthorizationEngine` orchestrator
 *   - index.ts                  barrel
 */

export {
  CommandAuthorizationEngine,
  type SCADAAuthorizationOptions,
} from './authorization/index';

```
