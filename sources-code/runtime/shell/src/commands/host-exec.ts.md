---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/host-exec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.374758+00:00
---

# runtime/shell/src/commands/host-exec.ts

```ts
/**
 * host.exec verb — publish-before-execute dispatcher for host handlers.
 *
 * Lifecycle:
 *   1. Parse handler id + args from command
 *   2. Gate on active hat with certId
 *   3. Canonicalize args, compute hatSig
 *   4. Create draft HostCommand object
 *   5. Transition LINEAR → AFFINE, then publish
 *   6. If --dry-run, return here (handler NOT invoked)
 *   7. Invoke handler via registry
 *   8. Append result as evidence patch (append-only, no state rewrite)
 *
 * Even if the handler crashes, the published object is evidence.
 */

import { createHash } from 'crypto';
import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';
import type { ObjectPatch } from '@semantos/runtime-services';
import { invokeHandler } from '../host-exec/registry';
import {
  MISSING_HANDLER,
  NO_ACTIVE_HAT,
  NO_HAT_CERT,
  NO_CONFIG,
  PUBLISH_FAILED,
} from '../error-codes';

/**
 * Collect args from command flags. Parses `--arg key=value` and also
 * scans rawArgs for repeated `--arg` flags (the parser only keeps the last).
 */
function collectArgs(cmd: ShellCommand): Record<string, unknown> {
  const args: Record<string, unknown> = {};

  // Walk rawArgs to collect ALL --arg key=value pairs (parser collapses repeats).
  for (let i = 0; i < cmd.rawArgs.length; i++) {
    if (cmd.rawArgs[i] === '--arg' && i + 1 < cmd.rawArgs.length) {
      const pair = cmd.rawArgs[i + 1];
      const eq = pair.indexOf('=');
      if (eq > 0) {
        args[pair.slice(0, eq)] = parseArgValue(pair.slice(eq + 1));
      }
      i++; // skip the value
    }
  }

  // Fallback: if rawArgs walking found nothing, use the single flag
  if (Object.keys(args).length === 0 && typeof cmd.flags.arg === 'string') {
    const eq = cmd.flags.arg.indexOf('=');
    if (eq > 0) {
      args[cmd.flags.arg.slice(0, eq)] = parseArgValue(cmd.flags.arg.slice(eq + 1));
    }
  }

  return args;
}

/** Parse a string value into number if it looks numeric. */
function parseArgValue(raw: string): unknown {
  const n = Number(raw);
  if (!Number.isNaN(n) && raw.trim() !== '') return n;
  return raw;
}

/**
 * Build canonical payload for signing.
 * Format: handler|sortedArgsJSON|hatId|requestedAt
 */
function canonicalize(handler: string, args: Record<string, unknown>, hatId: string, requestedAt: string): string {
  const sortedArgs = JSON.stringify(args, Object.keys(args).sort());
  return `${handler}|${sortedArgs}|${hatId}|${requestedAt}`;
}

export async function routeHostExec(cmd: ShellCommand, ctx: ShellContext): Promise<unknown> {
  // 1. Extract handler id
  const handlerId = cmd.flags.handler;
  if (typeof handlerId !== 'string' || !handlerId) {
    return { error: 'host.exec requires a handler id. Usage: host.exec <handler> [--arg key=value]', code: MISSING_HANDLER };
  }

  // 2. Active hat + certId
  const hat = ctx.identity.getActiveHat();
  if (!hat) {
    return { error: 'No active hat. Set one with SEMANTOS_HAT or identity register.', code: NO_ACTIVE_HAT };
  }
  const certId = ctx.activeHatCertId ?? hat.certId;
  if (!certId) {
    return { error: 'Active hat has no BRC-100 cert. Register an identity first.', code: NO_HAT_CERT };
  }

  // 3. Collect args + build canonical payload
  const args = collectArgs(cmd);
  const requestedAt = new Date().toISOString();
  const canonical = canonicalize(handlerId, args, hat.id, requestedAt);
  const hatSig = createHash('sha256').update(canonical).digest('hex');

  // 4. Look up HostCommand type def
  const config = ctx.config.getConfig();
  if (!config) {
    return { error: 'No extension config loaded', code: NO_CONFIG };
  }
  const typeDef = config.objectTypes.find(t => t.name === 'HostCommand');
  if (!typeDef) {
    return { error: 'HostCommand type not found in config. Load host-ops extension.', code: NO_CONFIG };
  }

  // 5. Create draft HostCommand
  const hatCaps = hat.capabilities ?? [];
  const objId = ctx.store.createObjectFromType(typeDef, undefined, hat.id, hatCaps, false);

  // Populate fields
  const fields: Record<string, unknown> = {
    handler: handlerId,
    args: JSON.stringify(args),
    hatId: hat.id,
    hatCertId: certId,
    hatSig,
    requestedAt,
  };
  for (const [k, v] of Object.entries(fields)) {
    ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: k, value: v });
  }

  // 6. Transition LINEAR(1) → AFFINE(2) so publish is allowed
  ctx.store.dispatch({ type: 'TRANSITION_LINEARITY', objectId: objId, newLinearity: 2 });

  // 7. Publish (AFFINE → RELEVANT via publishTransition)
  try {
    ctx.store.transitionVisibility(objId, 'published', hatCaps);
  } catch (e) {
    return { error: e instanceof Error ? e.message : String(e), code: PUBLISH_FAILED };
  }

  // 8. Dry-run short-circuit: do NOT invoke handler
  if (cmd.flags['dry-run']) {
    return { ok: true, hostCommandId: objId, dryRun: true };
  }

  // 9. Invoke handler
  const timeoutMs = Number(cmd.flags.timeout ?? 10_000);
  const startedAt = new Date().toISOString();
  const result = await invokeHandler(handlerId, args, {
    hatId: hat.id,
    hatCertId: certId,
    timeoutMs,
  });
  const finishedAt = new Date().toISOString();

  // 10. Append result patch (append-only evidence, does not rewrite state)
  const resultPatch: ObjectPatch = {
    id: `patch-${Date.now()}-result`,
    kind: 'action',
    timestamp: Date.now(),
    delta: {
      action: 'handler_result',
      startedAt,
      finishedAt,
      ...result,
    },
    hatId: hat.id,
    hatCapabilities: hatCaps,
  };
  ctx.store.dispatch({ type: 'ADD_PATCH', objectId: objId, patch: resultPatch });

  // Update payload fields for quick reads
  ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: 'startedAt', value: startedAt });
  ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: 'finishedAt', value: finishedAt });
  if (result.ok) {
    ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: 'exitCode', value: result.exitCode });
    ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: 'stdout', value: result.stdout });
    ctx.store.dispatch({ type: 'UPDATE_PAYLOAD', objectId: objId, field: 'stderr', value: result.stderr });
  }

  return { ok: true, hostCommandId: objId, result };
}

```
