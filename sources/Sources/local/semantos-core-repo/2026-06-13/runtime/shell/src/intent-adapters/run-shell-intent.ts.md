---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/intent-adapters/run-shell-intent.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.370015+00:00
---

# runtime/shell/src/intent-adapters/run-shell-intent.ts

```ts
/**
 * runShellIntent — bridge that runs a ShellCommand through the intent
 * pipeline end-to-end.
 *
 * This is the Slice 1 seam. It demonstrates the full flow using the
 * real modules for the cheap, deterministic stages:
 *
 *   - `buildSIR` — real, pure
 *   - `lowerSIR` — real, from @semantos/semantos-sir
 *   - `emit` (IR → bytes) — real, from @semantos/semantos-ir
 *   - stage event logging — real, correlation IDs flow end-to-end
 *
 * Kernel execution, StorageAdapter, and signing are Slice-3 wiring;
 * this helper takes them as `PipelineDeps` and the caller plugs
 * whatever fits their context. The gate test passes minimal test
 * doubles; a production callsite will pass real wiring.
 *
 * Usage — Slice 1.9 does NOT yet edit the router. Callers opt in by
 * calling this helper explicitly (e.g. from the gate test or behind
 * an INTENT_PIPELINE=1 feature flag at the router's verb dispatch).
 * The pattern is: flag on → runShellIntent; flag off → existing
 * direct dispatch. Both produce a user-visible result; only the
 * pipeline path produces a cryptographic receipt.
 *
 * See docs/INTENT-PIPELINE.md §"Slice plan".
 */

import type { ShellCommand } from '../parser';
import type { IdentityServiceLike, PipelineDeps } from '@semantos/intent';
import {
  buildHatContext,
  defaultTrustCeiling,
  processIntent,
  createJsonlStderrLogger,
  type Logger,
  type IntentResult,
  type IntentContext,
} from '@semantos/intent';
import { emit as emitIR } from '@semantos/semantos-ir';
import type { IRProgram } from '@semantos/semantos-ir';
import { shellCommandToIntent } from './shell-to-intent';

// ── ShellContext narrowing ──────────────────────────────────
//
// The shell's full ShellContext has many services; we only need
// identity here. Taking a narrow slice keeps this module decoupled
// from runtime/shell/src/types.ts so we can test it in isolation.

export interface ShellIntentCtxLike {
  identity: IdentityServiceLike;
  extension: { extensionId: string; domainFlag: number };
}

// ── Options ─────────────────────────────────────────────────

export interface RunShellIntentOptions {
  /** UUID generator for Intent.id and correlationId auto-fill. */
  generateId: () => string;
  /** Optional correlationId (e.g. per-REPL-session). */
  correlationId?: string;
  /** Optional logger override; defaults to JSONL on stderr. */
  logger?: Logger;
  /**
   * Kernel / storage / sign deps. Slice 1 callers may pass stubs;
   * Slice 3 callers pass real cell-engine + StorageAdapter + signer
   * wiring.
   */
  deps: PipelineDeps;
}

/** Shape returned when the command is not a pipeline-eligible mutation. */
export type RunShellIntentResult =
  | { kind: 'bypassed'; reason: string }
  | { kind: 'ran'; result: IntentResult };

/**
 * Run the pipeline for a single ShellCommand. Returns 'bypassed' when
 * the verb is read-only (shell-to-intent returned null) — the caller
 * should route those through existing direct handlers.
 */
export async function runShellIntent(
  cmd: ShellCommand,
  ctx: ShellIntentCtxLike,
  opts: RunShellIntentOptions,
): Promise<RunShellIntentResult> {
  // Producer-side — deterministic, no LLM retry loop.
  const intent = shellCommandToIntent(cmd, {
    generateId: opts.generateId,
    correlationId: opts.correlationId,
  });
  if (intent === null) {
    return {
      kind: 'bypassed',
      reason: `verb '${cmd.verb}' is read-only; bypass the intent pipeline`,
    };
  }

  const hat = buildHatContext({
    identity: ctx.identity,
    extension: ctx.extension,
    resolveMaxTrustClass: defaultTrustCeiling,
  });

  const intentCtx: IntentContext = {
    hat,
    logger: opts.logger ?? createJsonlStderrLogger(),
    correlationId: intent.correlationId,
  };

  const result = await processIntent(intent, intentCtx, opts.deps);
  return { kind: 'ran', result };
}

// ── Default emitBytes implementation ────────────────────────
//
// Convenience wrapper — most callers want `emit` from @semantos/
// semantos-ir but `PipelineDeps.emitBytes` has an opaque IR surface
// for decoupling. This wrapper bridges the two without exporting
// the full IR type graph out of runtime/intent.

export function defaultEmitBytes(ir: unknown): Uint8Array {
  return emitIR(ir as IRProgram);
}

```
