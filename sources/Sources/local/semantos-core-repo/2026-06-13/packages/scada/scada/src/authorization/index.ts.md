---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.471334+00:00
---

# packages/scada/scada/src/authorization/index.ts

```ts
/**
 * @semantos/scada/authorization — public surface for the authorization
 * sub-module split out of the legacy `packages/scada/src/authorization.ts`.
 *
 * The legacy file remains as a deprecation re-export shim so existing
 * `import { CommandAuthorizationEngine } from '../authorization'`
 * statements keep working byte-identically.
 */

export {
  CommandAuthorizationEngine,
  type SCADAAuthorizationOptions,
} from './authorization-facade';

export {
  evaluateCapability,
  getRequiredCapabilityForCommand,
  tokenHasCapability,
  type CapabilityDecision,
  type CapabilityRejectReason,
} from './capability-evaluator';

export {
  capabilitiesForRole,
  isSupervisorRole,
  ROLE_CAPABILITIES,
  type OperatorRole,
} from './role-mapper';

export {
  verifyCapabilitySignature,
  type VerifySignatureOptions,
  type VerifySignatureResult,
} from './signer-verifier';

export {
  eventToAuditEntry,
  makeAuditor,
  makeDecisionEventBus,
  type Auditor,
  type DecisionEvent,
} from './audit-logger';

export {
  decisionKey,
  getDecisionCacheAtoms,
  invalidateForToken,
  lookupDecision,
  recordDecision,
  resetDecisionCache,
  type CachedDecision,
  type DecisionCacheAtoms,
} from './decision-cache';

export {
  evaluateInterlocks,
  type EvaluateInterlocksDeps,
  type InterlockShimEvaluator,
} from './interlock-evaluator';

export {
  issueCommand,
  type IssueCommandDeps,
  type IssueCommandInput,
} from './issue-command-flow';

export { shiftHandover, type GrantCapabilityFn } from './shift-handover-flow';

export { acknowledgeAlarm } from './alarm-flow';

export { makeEngineState, type EngineState, type OperatorRecord } from './engine-state';

```
