---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/bus.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.792053+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/bus.ts

```ts
/**
 * Effect bus — the single dispatch surface effect atoms subscribe to.
 *
 * The facade pushes `EffectCommand`s here; each effect atom subscribes
 * to the slice it cares about (broadcast, persist, spv, fee-credit,
 * log). One bus keeps wiring centralised — bind once at boot, then
 * each effect attaches a filter.
 */

import { eventBus, type Dispose, type EventBus } from '@semantos/state';

import type { EffectCommand } from './types';

export const effectBus: EventBus<EffectCommand> = eventBus<EffectCommand>();

/**
 * Subscribe to a specific command type. Returns a `Dispose` so tests
 * can unsubscribe between cases.
 */
export function subscribeEffect<T extends EffectCommand['type']>(
  type: T,
  handler: (cmd: Extract<EffectCommand, { type: T }>) => void,
): Dispose {
  return effectBus.on((cmd) => {
    if (cmd.type === type) {
      handler(cmd as Extract<EffectCommand, { type: T }>);
    }
  });
}

```
