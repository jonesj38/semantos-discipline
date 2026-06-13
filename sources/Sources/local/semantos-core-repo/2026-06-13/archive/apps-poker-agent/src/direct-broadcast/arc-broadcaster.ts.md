---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/arc-broadcaster.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.784613+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/arc-broadcaster.ts

```ts
/**
 * Direct-broadcast ARC adapter.
 *
 * The single `new ARC(...)` instantiation in the poker-agent lives
 * in `apps/poker-agent/src/broadcasters/arc-broadcaster.ts` (added
 * in prompt 14). This module re-exports that factory under the
 * prompt-18 module path so consumers of the direct-broadcast tree
 * have a single import location for ARC wiring.
 *
 * Acceptance criterion:
 *
 *     `new ARC` appears exactly once in `arc-broadcaster.ts`.
 *
 * The single occurrence is in `broadcasters/arc-broadcaster.ts`;
 * everything else routes through the `broadcasterPort` from prompt
 * 14 + the helper functions below.
 */

import {
  broadcasterPort,
  type Broadcaster,
} from '@semantos/protocol-types/ports';

import { DEFAULT_ARC_URL, makeArcBroadcaster } from '../broadcasters/arc-broadcaster';

export { DEFAULT_ARC_URL, makeArcBroadcaster };

export interface BindArcBroadcasterOptions {
  arcUrl?: string;
}

/**
 * Bind an ARC-backed broadcaster onto `broadcasterPort` if nothing
 * is bound yet. Idempotent — respects existing bindings (e.g. test
 * doubles).
 */
export function bindArcBroadcaster(
  opts: BindArcBroadcasterOptions = {},
): Broadcaster {
  if (broadcasterPort.isBound()) return broadcasterPort.get();
  const broadcaster = makeArcBroadcaster(opts.arcUrl ?? DEFAULT_ARC_URL);
  broadcasterPort.bind(broadcaster);
  return broadcaster;
}

/**
 * Resolve the active broadcaster — returns the one already bound,
 * otherwise creates + binds an ARC adapter.
 */
export function getArcBroadcaster(opts: BindArcBroadcasterOptions = {}): Broadcaster {
  return bindArcBroadcaster(opts);
}

```
