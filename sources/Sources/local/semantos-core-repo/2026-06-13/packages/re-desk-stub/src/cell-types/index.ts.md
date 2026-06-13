---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/re-desk-stub/src/cell-types/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.538932+00:00
---

# packages/re-desk-stub/src/cell-types/index.ts

```ts
/**
 * Cell-type registry for the re-desk-stub extension.
 *
 * One cell type — `re-desk.maintenance-request.v1`. The stub
 * intentionally ships only this; cross-vertical dispatch composition
 * is what's being proven, not a real PM cell suite.
 */

import type { CellTypeDef } from '@semantos/oddjobz/cell-types';
import {
  maintenanceRequestCellType,
  type MaintenanceRequest,
  type MaintenanceRequestState,
  type MaintenanceUrgency,
  MAINTENANCE_REQUEST_STATES,
  MAINTENANCE_URGENCIES,
} from './maintenance-request.js';

export {
  maintenanceRequestCellType,
  type MaintenanceRequest,
  type MaintenanceRequestState,
  type MaintenanceUrgency,
  MAINTENANCE_REQUEST_STATES,
  MAINTENANCE_URGENCIES,
};

export type AnyReDeskCellTypeDef = CellTypeDef<MaintenanceRequest>;

export const RE_DESK_CELL_TYPES: readonly AnyReDeskCellTypeDef[] = Object.freeze(
  [maintenanceRequestCellType],
);

export const cellTypeByName: Readonly<
  Record<string, AnyReDeskCellTypeDef>
> = Object.freeze(
  Object.fromEntries(RE_DESK_CELL_TYPES.map((t) => [t.name, t])) as Record<
    string,
    AnyReDeskCellTypeDef
  >,
);

export const cellTypeByHashHex: Readonly<
  Record<string, AnyReDeskCellTypeDef>
> = Object.freeze(
  Object.fromEntries(
    RE_DESK_CELL_TYPES.map((t) => [t.typeHashHex, t]),
  ) as Record<string, AnyReDeskCellTypeDef>,
);

```
