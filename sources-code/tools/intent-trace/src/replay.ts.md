---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/intent-trace/src/replay.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.549692+00:00
---

# tools/intent-trace/src/replay.ts

```ts
/**
 * RM-095 — replay from stage with mutated payload.
 *
 * The existing pipeline entry point `processIntent(intent, ctx, deps)`
 * already supports partial replay: a caller starts from any pre-built
 * Intent and the pipeline runs forward from `sir_built`. RM-095 adds a
 * thin replay helper on top:
 *
 *   - Accepts an `intent` (from a reducer run or a captured trace).
 *   - Applies a typed `Partial<Intent>` of overrides BEFORE calling
 *     `processIntent`.
 *   - Returns the full IntentResult plus the events the supplied
 *     in-memory logger captured.
 *
 * The "replay from stage X" framing in the roadmap reduces to: pick the
 * intent's input shape that lives at stage X-1, mutate it, re-enter the
 * pipeline. For stages above `sir_built` the Intent itself is the
 * mutation surface; for stages below (`ir_emitted`, `script_executed`)
 * the caller has to override the corresponding `PipelineDeps` injection
 * (`emitBytes`, `executeScript`). The helper is structural — it does
 * NOT duplicate stage logic. Aligns with the no-hardcoded-workarounds
 * rule: we re-use the same pipeline, not a clone.
 */

import { processIntent, type PipelineDeps } from '../../../runtime/intent/src/pipeline.js';
import type { Intent, IntentContext, IntentResult, StageEvent } from '../../../runtime/intent/src/types.js';
import type { InMemoryLogger } from '../../../runtime/intent/src/logger.js';

export interface ReplayInput {
  /** The base intent — typically produced by the reducer or extracted
   *  from a captured trace. */
  intent: Intent;
  /** Typed override patch applied before re-entering the pipeline. */
  overrides?: Partial<Intent>;
  /** Required — caller supplies the hat/logger context. */
  ctx: IntentContext;
  /** Required — caller supplies pipeline deps (stubs in tests). */
  deps: PipelineDeps;
}

export interface ReplayResult {
  result: IntentResult;
  /** Convenience — events the supplied logger captured during this run.
   *  Empty array when the caller didn't pass an `InMemoryLogger`. */
  events: ReadonlyArray<StageEvent>;
}

/** Apply `overrides` to `intent` and run `processIntent`. The override
 *  surface is `Partial<Intent>` — for finer-grained replay (e.g. mutate
 *  IR bytes), inject a custom `emitBytes` into `deps`. */
export async function replayIntent(input: ReplayInput): Promise<ReplayResult> {
  const merged = mergeIntent(input.intent, input.overrides ?? {});
  const result = await processIntent(merged, input.ctx, input.deps);
  const logger = input.ctx.logger as InMemoryLogger;
  const events = Array.isArray(logger?.events) ? logger.events.slice() : [];
  return { result, events };
}

/** Deep-merge an override patch into an intent. `taxonomy`, `producerMeta`,
 *  and `constraints` get the same merge semantics the reducer uses; every
 *  other key is a flat overwrite. */
function mergeIntent(base: Intent, patch: Partial<Intent>): Intent {
  const out: Intent = { ...base };
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    const key = k as keyof Intent;
    if (key === 'constraints' && Array.isArray(v)) {
      (out as Record<string, unknown>)[key] = v;
    } else if (key === 'taxonomy' && v && base.taxonomy) {
      (out as Record<string, unknown>)[key] = { ...base.taxonomy, ...(v as object) };
    } else if (key === 'producerMeta' && v && base.producerMeta) {
      (out as Record<string, unknown>)[key] = { ...base.producerMeta, ...(v as object) };
    } else {
      (out as Record<string, unknown>)[key] = v;
    }
  }
  return out;
}

```
