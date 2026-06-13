---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/router/intent-pipeline-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.376721+00:00
---

# runtime/shell/src/router/intent-pipeline-adapter.ts

```ts
/**
 * Conditional intent-pipeline routing — kept as its own seam so verb
 * handlers don't have to import the pipeline machinery directly.
 *
 * Behaviour: when `INTENT_PIPELINE=1` and `ctx.intentPipeline` is
 * wired, certain verbs (currently: transition) route through the
 * cryptographic-audit pipeline; otherwise they take the direct path.
 */

import type { ShellCommand } from '../parser';
import type { ShellContext } from '../types';

export function shouldUsePipelineRoute(ctx: ShellContext): boolean {
  if (process.env.INTENT_PIPELINE !== '1') return false;
  if (!ctx.intentPipeline) return false;
  return true;
}

/**
 * Pipeline-backed transition. Delegates to `runShellIntent` with the
 * wiring on `ctx.intentPipeline`. Returns a shape compatible with the
 * direct path so REPL/CLI callers don't have to branch on which path
 * ran.
 */
export async function routeTransitionViaPipeline(
  cmd: ShellCommand,
  ctx: ShellContext,
): Promise<unknown> {
  const { runShellIntent } = await import('../intent-adapters/run-shell-intent');
  if (!ctx.intentPipeline) {
    return {
      error: 'intent pipeline route selected but wiring is missing',
      code: 'INTENT_PIPELINE_UNWIRED',
    };
  }

  const identityLike = {
    getIdentity: () => {
      const id = ctx.identity.getIdentity();
      if (!id) return null;
      return {
        id: id.id,
        certId: id.certId ?? null,
        activeHatId: id.activeHatId,
        hats: id.hats.map((f) => ({
          id: f.id,
          certId: f.certId ?? null,
          capabilities: f.capabilities,
        })),
      };
    },
    getActiveHat: () => {
      const f = ctx.identity.getActiveHat();
      if (!f) return null;
      return {
        id: f.id,
        certId: f.certId ?? null,
        capabilities: f.capabilities,
      };
    },
  };

  const out = await runShellIntent(
    cmd,
    { identity: identityLike, extension: ctx.intentPipeline.extension },
    {
      generateId: ctx.intentPipeline.generateId,
      deps: ctx.intentPipeline.deps,
    },
  );

  if (out.kind === 'bypassed') {
    return { error: out.reason, code: 'INTENT_PIPELINE_BYPASSED' };
  }

  return {
    id: cmd.objectId,
    status: out.result.ok ? 'transitioned' : 'rejected',
    correlationId: out.result.correlationId,
    ok: out.result.ok,
    rejection: out.result.rejection,
    receipt: {
      signedBy: out.result.receipt.signedBy,
      correlationId: out.result.receipt.correlationId,
      resultSigLength: out.result.receipt.resultSig.byteLength,
      issuedAt: out.result.receipt.issuedAt,
      finishedAt: out.result.receipt.finishedAt,
    },
  };
}

```
