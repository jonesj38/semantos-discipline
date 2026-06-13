---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/transfer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.385715+00:00
---

# runtime/shell/src/router/verb-handlers/transfer.ts

```ts
/**
 * `transfer <id> --to <hat-id>` — records a transfer patch in the
 * evidence chain. The full Plexus transfer is Phase 17 work.
 */

import type { ObjectPatch } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { requireObject, isShellError } from '../../route-helpers';
import { MISSING_TO_FLAG } from '../../error-codes';
import { getActiveHat } from '../shared/helpers';
import type { VerbHandler } from '../types';

const transferHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'transfer');
  if (isShellError(obj)) return obj;

  const toHat = cmd.flags.to;
  if (typeof toHat !== 'string') {
    return { error: 'Transfer requires --to <hat-id>', code: MISSING_TO_FLAG };
  }

  const hat = getActiveHat(ctx);

  const patch: ObjectPatch = {
    id: `patch-${Date.now()}-transfer`,
    kind: 'state_transition',
    timestamp: Date.now(),
    delta: {
      action: 'transfer',
      from: hat?.id ?? 'unknown',
      to: toHat,
      transferredAt: new Date().toISOString(),
    },
    hatId: hat?.id,
    hatCapabilities: hat?.capabilities,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: cmd.objectId, patch });

  return {
    objectId: cmd.objectId,
    transferred: true,
    from: hat?.id ?? 'unknown',
    to: toHat,
    note: 'Transfer recorded in evidence chain. Full Plexus transfer requires Phase 17.',
  };
};

export const transferHandlers = { transfer: transferHandler };

```
