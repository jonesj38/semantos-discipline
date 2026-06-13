---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/patch.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.385157+00:00
---

# runtime/shell/src/router/verb-handlers/patch.ts

```ts
/**
 * `patch <id> --field value …` — append a manual_override patch and
 * merge the deltas into the object's payload.
 */

import type { ObjectPatch } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { requireObject, isShellError } from '../../route-helpers';
import { NO_PATCH_FIELDS } from '../../error-codes';
import { getActiveHat, getObject, serializeObject } from '../shared/helpers';
import type { VerbHandler } from '../types';

const patchHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'patch');
  if (isShellError(obj)) return obj;

  const hat = getActiveHat(ctx);
  const delta: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(cmd.flags)) {
    if (k !== 'dry-run' && k !== 'format') delta[k] = v;
  }

  if (Object.keys(delta).length === 0) {
    return { error: 'No fields to patch. Provide --field value pairs.', code: NO_PATCH_FIELDS };
  }

  const patch: ObjectPatch = {
    id: `patch-${Date.now()}-shell`,
    kind: 'manual_override',
    timestamp: Date.now(),
    delta,
    hatId: hat?.id,
    hatCapabilities: hat?.capabilities,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: cmd.objectId, patch });
  ctx.store.dispatch({
    type: 'UPDATE_OBJECT',
    id: cmd.objectId,
    updates: { payload: { ...obj.payload, ...delta } },
  });

  const updated = getObject(ctx, cmd.objectId);
  return updated ? serializeObject(updated) : { id: cmd.objectId, status: 'patched' };
};

export const patchHandlers = { patch: patchHandler };

```
