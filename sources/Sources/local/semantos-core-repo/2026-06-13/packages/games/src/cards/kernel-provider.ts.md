---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/kernel-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.411489+00:00
---

# packages/games/src/cards/kernel-provider.ts

```ts
/**
 * Poker HostFunctionProvider — wraps registerPokerHostFunctions
 * for PolicyRuntime integration.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry } from '@semantos/cell-engine';
import type { HostFunctionProvider } from '../../../policy-runtime/src/types';
import { registerPokerHostFunctions } from './poker-policies';

export class PokerHostFunctionProvider implements HostFunctionProvider {
  register(registry: HostFunctionRegistry): void {
    registerPokerHostFunctions(registry);
  }
}

export function createPokerHostFunctionProvider(): HostFunctionProvider {
  return new PokerHostFunctionProvider();
}

```
