---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/kernel-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.404002+00:00
---

# packages/games/src/dungeon/kernel-provider.ts

```ts
/**
 * Dungeon HostFunctionProvider — wraps registerDungeonHostFunctions
 * for PolicyRuntime integration.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry } from '@semantos/cell-engine';
import type { HostFunctionProvider } from '../../../policy-runtime/src/types';
import { registerDungeonHostFunctions } from './host-functions';

export class DungeonHostFunctionProvider implements HostFunctionProvider {
  register(registry: HostFunctionRegistry): void {
    registerDungeonHostFunctions(registry);
  }
}

export function createDungeonHostFunctionProvider(): HostFunctionProvider {
  return new DungeonHostFunctionProvider();
}

```
