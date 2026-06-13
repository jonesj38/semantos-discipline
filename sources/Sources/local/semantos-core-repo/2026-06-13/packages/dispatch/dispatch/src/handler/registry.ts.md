---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/dispatch/dispatch/src/handler/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.517889+00:00
---

# packages/dispatch/dispatch/src/handler/registry.ts

```ts
/**
 * D-O11 phase O11b — accept-handler registry.
 *
 * Receiving extensions call `register(payloadType, handler)` at brain
 * boot. The dispatch handler routes envelopes to the registered
 * handler for the inner payload type.
 */

import type {
  AcceptHandlerFn,
  AcceptHandlerRegistry,
} from './types.js';

class AcceptHandlerRegistryImpl implements AcceptHandlerRegistry {
  private readonly handlers: Map<string, AcceptHandlerFn> = new Map();

  register(payloadType: string, handler: AcceptHandlerFn): void {
    if (typeof payloadType !== 'string' || payloadType.length === 0) {
      throw new Error('register: payloadType must be a non-empty string');
    }
    if (this.handlers.has(payloadType)) {
      throw new Error(
        `register: payloadType ${payloadType} already has a registered handler`,
      );
    }
    this.handlers.set(payloadType, handler);
  }

  get(payloadType: string): AcceptHandlerFn | undefined {
    return this.handlers.get(payloadType);
  }

  registeredTypes(): readonly string[] {
    return [...this.handlers.keys()].sort();
  }
}

export function makeAcceptHandlerRegistry(): AcceptHandlerRegistry {
  return new AcceptHandlerRegistryImpl();
}

```
