---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/transition.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.384870+00:00
---

# runtime/shell/src/router/verb-handlers/transition.ts

```ts
/**
 * Visibility-transition verbs: `transition`, `publish`, `revoke`. All
 * three call `LoomStore.transitionVisibility` under the hood; only
 * the target visibility differs.
 */

import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { requireObject, isShellError } from '../../route-helpers';
import {
  INVALID_VISIBILITY_FLAG,
  PUBLISH_FAILED,
  REVOKE_FAILED,
  TRANSITION_FAILED,
} from '../../error-codes';
import { getCapabilities, getObject, serializeObject } from '../shared/helpers';
import {
  routeTransitionViaPipeline,
  shouldUsePipelineRoute,
} from '../intent-pipeline-adapter';
import type { VerbHandler } from '../types';

const transitionHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'transition');
  if (isShellError(obj)) return obj;

  const newVis = cmd.flags.visibility;
  if (typeof newVis !== 'string' || !['draft', 'published', 'revoked'].includes(newVis)) {
    return {
      error: 'Transition requires --visibility <draft|published|revoked>',
      code: INVALID_VISIBILITY_FLAG,
    };
  }

  if (shouldUsePipelineRoute(ctx)) return routeTransitionViaPipeline(cmd, ctx);

  const hatCaps = getCapabilities(ctx);
  try {
    ctx.store.transitionVisibility(
      cmd.objectId,
      newVis as 'draft' | 'published' | 'revoked',
      hatCaps,
    );
  } catch (e) {
    return {
      error: e instanceof Error ? e.message : String(e),
      code: TRANSITION_FAILED,
    };
  }

  const updated = getObject(ctx, cmd.objectId);
  return updated ? serializeObject(updated) : { id: cmd.objectId, status: 'transitioned' };
};

const publishHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'publish');
  if (isShellError(obj)) return obj;
  const hatCaps = getCapabilities(ctx);
  try {
    ctx.store.transitionVisibility(cmd.objectId, 'published', hatCaps);
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e), code: PUBLISH_FAILED };
  }
  const updated = getObject(ctx, cmd.objectId);
  return updated ? serializeObject(updated) : { objectId: cmd.objectId, status: 'published' };
};

const revokeHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'revoke');
  if (isShellError(obj)) return obj;
  const hatCaps = getCapabilities(ctx);
  try {
    ctx.store.transitionVisibility(cmd.objectId, 'revoked', hatCaps);
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e), code: REVOKE_FAILED };
  }
  const updated = getObject(ctx, cmd.objectId);
  return updated ? serializeObject(updated) : { objectId: cmd.objectId, status: 'revoked' };
};

export const transitionHandlers = {
  transition: transitionHandler,
  publish: publishHandler,
  revoke: revokeHandler,
};

```
