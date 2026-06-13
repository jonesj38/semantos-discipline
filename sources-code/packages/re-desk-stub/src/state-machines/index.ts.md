---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/state-machines/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.539860+00:00
---

# packages/re-desk-stub/src/state-machines/index.ts

```ts
/**
 * D-O11 phase O11a — re-desk-stub state-machine surface.
 */

export {
  MAINTENANCE_REQUEST_FSM_STATES,
  MAINTENANCE_REQUEST_TRANSITIONS,
  findMaintenanceRequestTransition,
  isMaintenanceRequestFsmState,
  maintenanceRequestCellId,
  maintenanceRequestTransition,
  genesisDraft,
  type MaintenanceRequestFsmState,
  type MaintenanceRequestTransitionSpec,
  type MaintenanceRequestTransitionInput,
  type MaintenanceRequestTransitionOutput,
  type MaintenanceRequestGenesisInput,
} from './maintenance-request-fsm.js';

export {
  ok,
  err,
  presentedFlag,
  checkDomainFlag,
  assertLinear,
  type ConsumedCellSet,
  type KernelGateFailure,
  type PresentedCap,
  type Result,
  type SigningPrincipal,
} from './kernel-gate.js';

```
