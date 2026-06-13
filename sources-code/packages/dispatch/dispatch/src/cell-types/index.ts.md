---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/cell-types/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.515730+00:00
---

# packages/dispatch/dispatch/src/cell-types/index.ts

```ts
/**
 * Cell-type registry for the dispatch extension.
 *
 * Three cell types: dispatch.envelope.v1, dispatch.accepted.v1,
 * dispatch.completion.v1. The trio composes the cross-vertical
 * federation seam — dispatch out, accepted back, completion back.
 */

import type { CellTypeDef } from '@semantos/oddjobz/cell-types';
import {
  dispatchEnvelopeCellType,
  type DispatchEnvelope,
} from './envelope.js';
import {
  dispatchAcceptedCellType,
  type DispatchAccepted,
} from './accepted.js';
import {
  dispatchCompletionCellType,
  type DispatchCompletion,
  type CompletionKind,
  COMPLETION_KINDS,
} from './completion.js';

export {
  dispatchEnvelopeCellType,
  dispatchAcceptedCellType,
  dispatchCompletionCellType,
  type DispatchEnvelope,
  type DispatchAccepted,
  type DispatchCompletion,
  type CompletionKind,
  COMPLETION_KINDS,
};

export type AnyDispatchCellTypeDef =
  | CellTypeDef<DispatchEnvelope>
  | CellTypeDef<DispatchAccepted>
  | CellTypeDef<DispatchCompletion>;

export const DISPATCH_CELL_TYPES: readonly AnyDispatchCellTypeDef[] =
  Object.freeze([
    dispatchEnvelopeCellType,
    dispatchAcceptedCellType,
    dispatchCompletionCellType,
  ]);

export const cellTypeByName: Readonly<
  Record<string, AnyDispatchCellTypeDef>
> = Object.freeze(
  Object.fromEntries(
    DISPATCH_CELL_TYPES.map((t) => [t.name, t]),
  ) as Record<string, AnyDispatchCellTypeDef>,
);

export const cellTypeByHashHex: Readonly<
  Record<string, AnyDispatchCellTypeDef>
> = Object.freeze(
  Object.fromEntries(
    DISPATCH_CELL_TYPES.map((t) => [t.typeHashHex, t]),
  ) as Record<string, AnyDispatchCellTypeDef>,
);

```
