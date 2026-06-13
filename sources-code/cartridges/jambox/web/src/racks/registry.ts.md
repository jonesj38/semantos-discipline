---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/racks/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.612749+00:00
---

# cartridges/jambox/web/src/racks/registry.ts

```ts
/**
 * In-memory JamRack registry.
 *
 * Racks register themselves on construction. The sequencer and surface
 * look up racks by id when routing note/trigger events.
 *
 * Usage:
 *   import { rackRegistry } from './registry';
 *   rackRegistry.register(myRack);
 *   const rack = rackRegistry.get('jam.rack.drum-808');
 */

import type { JamRack } from './contract';

export class JamRackRegistry {
  private readonly racks = new Map<string, JamRack>();

  /** Register a rack instance. Overwrites any previous registration for the same id. */
  register(rack: JamRack): void {
    this.racks.set(rack.id, rack);
  }

  /** Unregister a rack by id. No-op if not registered. */
  unregister(rackId: string): void {
    this.racks.delete(rackId);
  }

  /** Look up a rack by id. Returns undefined if not registered. */
  get(rackId: string): JamRack | undefined {
    return this.racks.get(rackId);
  }

  /** Get all registered racks. */
  all(): JamRack[] {
    return Array.from(this.racks.values());
  }

  /** Check if a rack is registered. */
  has(rackId: string): boolean {
    return this.racks.has(rackId);
  }

  /** Number of registered racks. */
  get size(): number {
    return this.racks.size;
  }
}

/** Singleton rack registry for the jam-room. */
export const rackRegistry = new JamRackRegistry();

```
