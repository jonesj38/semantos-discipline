---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/persistence-hook.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.527180+00:00
---

# packages/game-sdk/src/engine/persistence-hook.ts

```ts
/**
 * Persistence hook — subscribes to engine state changes and writes
 * cells to the bound `cellStorePort`.
 *
 * Mirrors the prompt-15 `persist-effect.ts` shape: the hook is
 * declarative; concrete implementations bind a `CellStoreFacade`
 * via `cellStorePort`. The default fallback is a no-op so engines
 * run in-memory in tests without forcing every test to bind a fake.
 */

import { port, type Port } from '@semantos/state';

export interface CellStoreFacade {
  write(path: string, bytes: Uint8Array): void | Promise<void>;
  read(path: string): Promise<Uint8Array | null> | Uint8Array | null;
  delete(path: string): void | Promise<void>;
  list(prefix: string): Promise<string[]> | string[];
}

export const cellStorePort: Port<CellStoreFacade> = port<CellStoreFacade>('cell-store');

/** No-op facade — used when nothing's bound. */
export const noopCellStore: CellStoreFacade = {
  async write() {},
  async read() {
    return null;
  },
  async delete() {},
  async list() {
    return [];
  },
};

export function resolveCellStore(): CellStoreFacade {
  return cellStorePort.isBound() ? cellStorePort.get() : noopCellStore;
}

```
