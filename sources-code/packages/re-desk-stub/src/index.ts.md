---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.536187+00:00
---

# packages/re-desk-stub/src/index.ts

```ts
/**
 * @semantos/re-desk-stub — stub property-management vertical extension.
 *
 * D-O11 phase O11a per `docs/design/ODDJOBZ-EXTENSION-PLAN.md` §3 phase
 * O11. Single MaintenanceRequest cell type, single capability, single
 * state machine — minimal scaffolding sufficient to validate the
 * chapter-29 federation primitive end-to-end with the full
 * `@semantos/oddjobz` extension. The extension is intentionally not a
 * real PM vertical; the point is to prove the cross-vertical dispatch
 * pattern composes correctly.
 */

export * from './cell-types/index.js';
export * from './state-machines/index.js';
export {
  RE_DESK_CAPABILITIES,
  RE_DESK_CAP_NAMES,
  capDispatchReDesk,
  capabilityByName,
  mintReDeskCapability,
  type ReDeskCapability,
  type ReDeskCapName,
} from './capabilities.js';
export {
  parseTenantHatRef,
  formatTenantHatRef,
  isTenantHatRef,
  InvalidTenantHatRefError,
  type TenantHatRef,
} from './tenant-hat-ref.js';

```
