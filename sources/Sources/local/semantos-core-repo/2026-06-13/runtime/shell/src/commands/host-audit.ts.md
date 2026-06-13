---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/commands/host-audit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.373054+00:00
---

# runtime/shell/src/commands/host-audit.ts

```ts
/**
 * host.audit verb — read-only cryptographic verification of HostCommand invariants.
 *
 * Checks:
 *   1. Signature: recompute sha256 of canonical payload, compare to hatSig.
 *   2. Linearity: object must be in 'published' visibility.
 *   3. Patch chain: timestamps monotonically increasing, no regressions.
 *   4. Result: at least one patch with delta.action === 'handler_result'.
 *
 * Pure inspection — no dispatch, no mutation, no publish.
 */

import { createHash } from 'crypto';
import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';

export interface AuditReport {
  hostCommandId: string;
  handler: string;
  hatId: string;
  requestedAt: string;
  signatureValid: boolean;
  linearityValid: boolean;
  patchChainValid: boolean;
  resultPresent: boolean;
  allInvariantsHold: boolean;
  issues: string[];
}

function errorReport(id: string, issues: string[]): AuditReport {
  return {
    hostCommandId: id ?? '',
    handler: '',
    hatId: '',
    requestedAt: '',
    signatureValid: false,
    linearityValid: false,
    patchChainValid: false,
    resultPresent: false,
    allInvariantsHold: false,
    issues,
  };
}

export async function routeHostAudit(cmd: ShellCommand, ctx: ShellContext): Promise<AuditReport> {
  const id = cmd.objectId;
  if (!id) return errorReport('', ['missing hostCommandId']);

  const obj = ctx.store.getState().objects.get(id);
  if (!obj) return errorReport(id, ['object not found']);
  if (obj.typeDefinition?.name !== 'HostCommand') {
    return errorReport(id, [`not a HostCommand (type: ${obj.typeDefinition?.name ?? 'unknown'})`]);
  }

  const issues: string[] = [];
  const handler = String(obj.payload.handler ?? '');
  const argsJson = String(obj.payload.args ?? '{}');
  const hatId = String(obj.payload.hatId ?? '');
  const requestedAt = String(obj.payload.requestedAt ?? '');
  const hatSig = String(obj.payload.hatSig ?? '');

  // 1. Signature: recompute canonical payload exactly as host.exec signed it
  const args = JSON.parse(argsJson);
  const sortedArgs = JSON.stringify(args, Object.keys(args).sort());
  const canonical = `${handler}|${sortedArgs}|${hatId}|${requestedAt}`;
  const expectedSig = createHash('sha256').update(canonical).digest('hex');
  const signatureValid = hatSig === expectedSig;
  if (!signatureValid) issues.push('hatSig does not match recomputed signature over canonical payload');

  // 2. Linearity: must be published
  const linearityValid = obj.visibility === 'published';
  if (!linearityValid) issues.push(`expected visibility=published, got ${obj.visibility}`);

  // 3. Patch chain: timestamps must be monotonically non-decreasing
  const patches = obj.patches ?? [];
  let patchChainValid = true;
  for (let i = 1; i < patches.length; i++) {
    if (patches[i].timestamp < patches[i - 1].timestamp) {
      patchChainValid = false;
      issues.push(`patch ${i} timestamp regresses (${patches[i].timestamp} < ${patches[i - 1].timestamp})`);
    }
  }

  // 4. Result: at least one patch with delta.action === 'handler_result'
  const resultPresent = patches.some(p => p.delta?.action === 'handler_result');
  if (!resultPresent) issues.push('no handler_result patch found (no result recorded)');

  const allInvariantsHold = signatureValid && linearityValid && patchChainValid && resultPresent;

  return {
    hostCommandId: id,
    handler,
    hatId,
    requestedAt,
    signatureValid,
    linearityValid,
    patchChainValid,
    resultPresent,
    allInvariantsHold,
    issues,
  };
}

```
