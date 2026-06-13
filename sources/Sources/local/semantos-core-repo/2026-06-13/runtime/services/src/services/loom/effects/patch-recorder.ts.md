---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/effects/patch-recorder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.115721+00:00
---

# runtime/services/src/services/loom/effects/patch-recorder.ts

```ts
/**
 * patch-recorder — observability effect that watches `patchQueueAtom`
 * and forwards every newly-attached patch to a caller-supplied sink.
 *
 * The default sink is a no-op so that wiring the recorder doesn't
 * change behaviour. Real persistence (CellStore append, network sync,
 * etc.) plugs in via `attachPatchRecorder({ sink })` at app boot — the
 * adapter pattern lives in the adapter layer, not in loom.
 *
 * Dedup is keyed off `patch.id`, so adapters can rely on each id being
 * delivered exactly once per process lifetime.
 */

import { effect, type Dispose } from '@semantos/state';

import { patchQueueAtom } from '../loom-atoms';
import type { ObjectPatch } from '../../../types/loom';

/** Sink callback invoked once per never-before-seen patch. */
export type PatchSink = (patch: ObjectPatch) => void;

export interface PatchRecorderOptions {
  /** Defaults to a no-op. */
  sink?: PatchSink;
}

/**
 * Subscribe to the singleton `patchQueueAtom`. Returns a Dispose so
 * tests and shutdown handlers can detach.
 */
export function attachPatchRecorder(options: PatchRecorderOptions = {}): Dispose {
  const sink = options.sink ?? (() => {});
  const seen = new Set<string>();

  return effect((read) => {
    const queue = read(patchQueueAtom);
    for (const patch of queue) {
      if (seen.has(patch.id)) continue;
      seen.add(patch.id);
      try {
        sink(patch);
      } catch {
        // Sink errors must never break the loom — log and swallow once
        // a logger port lands. For now we silently continue so the
        // reactive graph remains consistent.
      }
    }
  });
}

```
