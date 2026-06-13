---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/kernel-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.835395+00:00
---

# archive/apps-mud/src/kernel-provider.ts

```ts
/**
 * MUD HostFunctionProvider — wraps registerMUDHostFunctions
 * for PolicyRuntime integration.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry } from '@semantos/cell-engine';
import type { HostFunctionProvider } from '../../../packages/policy-runtime/src/types';
import { registerMUDHostFunctions } from './host-functions';

export class MUDHostFunctionProvider implements HostFunctionProvider {
  register(registry: HostFunctionRegistry): void {
    registerMUDHostFunctions(registry);
  }
}

export function createMUDHostFunctionProvider(): HostFunctionProvider {
  return new MUDHostFunctionProvider();
}

```
