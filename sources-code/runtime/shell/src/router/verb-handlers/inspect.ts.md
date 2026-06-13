---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/verb-handlers/inspect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.382859+00:00
---

# runtime/shell/src/router/verb-handlers/inspect.ts

```ts
/**
 * Read-only verbs: `inspect`, `trace`, `verify`, `sign`. They all
 * read from `LoomStore.getState()` and (in `sign`'s case) append a
 * single signature patch.
 */

import type { ObjectPatch } from '@semantos/runtime-services';
import type { ShellCommand } from '../../parser';
import type { ShellContext } from '../../types';
import { requireObject, isShellError } from '../../route-helpers';
import { NO_ACTIVE_HAT } from '../../error-codes';
import { routeVerifyPolicy } from '../../commands/eval';
import { getActiveHat, linearityName, serializeObject } from '../shared/helpers';
import type { VerbHandler } from '../types';

const inspectHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'inspect');
  if (isShellError(obj)) return obj;

  return {
    ...serializeObject(obj),
    header: {
      linearity: linearityName(obj.header.linearity),
      version: obj.header.version,
      flags: obj.header.flags,
      refCount: obj.header.refCount,
      typeHash: Array.from(obj.header.typeHash)
        .map((b) => b.toString(16).padStart(2, '0'))
        .join(''),
      ownerId: Array.from(obj.header.ownerId)
        .map((b) => b.toString(16).padStart(2, '0'))
        .join(''),
      timestamp: obj.header.timestamp.toString(),
      // RM-032b: commerce phase removed from CellHeader surface; the
      // inspect view drops the field. Domain-aware UIs decode from the
      // cell payload via commerceSchemaV1 if they need it.
    },
    evidence: obj.patches.map((p) => ({
      id: p.id,
      kind: p.kind,
      timestamp: new Date(p.timestamp).toISOString(),
      delta: p.delta,
      hatId: p.hatId,
    })),
  };
};

const traceHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'trace');
  if (isShellError(obj)) return obj;
  return obj.patches.map((p) => ({
    HASH: p.id,
    AUTHOR: p.hatId ?? 'system',
    ACTION: p.delta.action ?? p.kind,
    TIMESTAMP: new Date(p.timestamp).toISOString(),
  }));
};

const verifyHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  if (cmd.flags.policy) {
    const policyResult = await routeVerifyPolicy(cmd, ctx);
    if (policyResult !== null) return policyResult;
  }

  const obj = requireObject(ctx, cmd.objectId, 'verify');
  if (isShellError(obj)) return obj;

  const patches = obj.patches;
  let valid = true;
  const issues: string[] = [];

  for (let i = 1; i < patches.length; i++) {
    if (patches[i].timestamp < patches[i - 1].timestamp) {
      valid = false;
      issues.push(`Patch ${i} has timestamp before patch ${i - 1}`);
    }
  }
  if (patches.length === 0) issues.push('No patches in evidence chain');

  return {
    objectId: cmd.objectId,
    chainLength: patches.length,
    valid,
    issues: issues.length > 0 ? issues : undefined,
    message: valid
      ? 'Evidence chain valid: all patches are in chronological order'
      : 'Evidence chain INVALID',
  };
};

const signHandler: VerbHandler = async (cmd: ShellCommand, ctx: ShellContext) => {
  const obj = requireObject(ctx, cmd.objectId, 'sign');
  if (isShellError(obj)) return obj;

  const hat = getActiveHat(ctx);
  if (!hat) {
    return {
      error:
        'No active hat. Set one with SEMANTOS_HAT or `switch <hat-id>` in REPL.',
      code: NO_ACTIVE_HAT,
    };
  }

  const signPatch: ObjectPatch = {
    id: `patch-${Date.now()}-sign`,
    kind: 'action',
    timestamp: Date.now(),
    delta: { action: 'signed', signedBy: hat.id, signedAt: new Date().toISOString() },
    hatId: hat.id,
    hatCapabilities: hat.capabilities,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: cmd.objectId, patch: signPatch });

  return { objectId: cmd.objectId, signedBy: hat.id, status: 'signed' };
};

export const inspectHandlers = {
  inspect: inspectHandler,
  trace: traceHandler,
  verify: verifyHandler,
  sign: signHandler,
};

```
