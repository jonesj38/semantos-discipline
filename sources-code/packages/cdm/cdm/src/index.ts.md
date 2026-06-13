---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.495257+00:00
---

# packages/cdm/cdm/src/index.ts

```ts
/**
 * @semantos/cdm — ISDA Common Domain Model integration for Semantos.
 *
 * Maps CDM types onto Semantos semantic objects:
 * - CDM Product → LINEAR cell with three-axis taxonomy
 * - CDM Event → State transition on a cell
 * - CDM Party → Identity hat with capability tokens
 * - CDM Lineage → Cell DAG (prevStateHash chain)
 * - CDM Qualification → Lisp policy compiled to capability cell
 *
 * Phase 28
 */

// Types
export {
  type CDMProduct,
  type CDMProductType,
  type CDMLifecycleState,
  type CDMEventType,
  type CDMPartyRole,
  type CDMPartyRoleType,
  type CDMLifecycleEvent,
  type EconomicTerms,
  type EconomicEffect,
  type RegulatoryReport,
  type RegulatoryRegime,
  type RegulatoryTag,
  type CDMDispute,
  type CDMResolution,
  type CloseOutResult,
  type Result,
  createCDMProduct,
  createLifecycleEvent,
  createRegulatoryReport,
  computeCDMTypeHash,
  generateUTI,
} from './types';

// Lifecycle Engine
export { CDMLifecycleEngine } from './lifecycle';

// Regulatory Reporting
export { RegulatoryReportGenerator } from './regulatory';

// Bridge
export { CDMBridge } from './bridge/index';
export {
  importProduct,
  exportProduct,
  importEvent,
  exportEvent,
} from './bridge/cdm-json';
export { importFpML, exportFpML } from './bridge/fpml';

// Policy Compiler
export {
  compileCDMPolicy,
  loadAndCompilePolicy,
  packPolicyCell,
  loadAllPolicies,
  POLICY_NAMES,
  type PolicyName,
} from './policies/compiler';

// Host Functions (Phase 29.5)
export {
  registerCDMHostFunctions,
  createCDMHostFunctionProvider,
} from './policies/host-functions';

```
