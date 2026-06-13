---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.386279+00:00
---

# runtime/shell/src/router/verb-handlers/new.ts

```ts
/**
 * `new <type-path>` — creates a fresh object from the type definition,
 * applies any field flags as initial-value patches, and returns the
 * serialized result.
 */

import type { ObjectPatch } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { requireType, isShellError } from '../../route-helpers';
import {
  getActiveHat,
  getObject,
  serializeObject,
} from '../shared/helpers';
import type { VerbHandler } from '../types';

const newHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const typeDef = requireType(ctx, cmd.typePath, 'new');
  if (isShellError(typeDef)) return typeDef;

  const hat = getActiveHat(ctx);
  const hatId = hat?.id ?? ctx.activeHatId ?? undefined;
  const hatCaps = hat?.capabilities;

  const objectId = ctx.store.createObjectFromType(typeDef, undefined, hatId, hatCaps, false);
  const obj = getObject(ctx, objectId);

  const fieldNames = new Set(typeDef.fields.map((f) => f.name));
  const fieldFlags = Object.entries(cmd.flags).filter(
    ([k]) => fieldNames.has(k) && k !== 'dry-run' && k !== 'format',
  );

  if (fieldFlags.length > 0 && obj) {
    const delta: Record<string, unknown> = {};
    for (const [k, v] of fieldFlags) delta[k] = v;

    const patch: ObjectPatch = {
      id: `patch-${Date.now()}-shell-init`,
      kind: 'action',
      timestamp: Date.now(),
      delta,
      hatId,
      hatCapabilities: hatCaps,
    };
    ctx.store.dispatch({ type: 'ADD_PATCH', objectId, patch });
    ctx.store.dispatch({
      type: 'UPDATE_OBJECT',
      id: objectId,
      updates: { payload: { ...obj.payload, ...delta } },
    });
  }

  const created = getObject(ctx, objectId);
  return created ? serializeObject(created) : { id: objectId, status: 'created' };
};

export const newHandlers = { new: newHandler };

```
