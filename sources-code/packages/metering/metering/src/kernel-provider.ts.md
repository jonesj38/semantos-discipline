---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/metering/metering/src/kernel-provider.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.486634+00:00
---

# packages/metering/metering/src/kernel-provider.ts

```ts
/**
 * Metering HostFunctionProvider — wraps registerMeteringHostFunctions
 * for PolicyRuntime integration.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry } from '../../cell-engine/bindings/host-functions';
import type { HostFunctionProvider } from '../../policy-runtime/src/types';
import { registerMeteringHostFunctions } from './host-functions';

export class MeteringHostFunctionProvider implements HostFunctionProvider {
  register(registry: HostFunctionRegistry): void {
    registerMeteringHostFunctions(registry);
  }
}

export function createMeteringHostFunctionProvider(): HostFunctionProvider {
  return new MeteringHostFunctionProvider();
}

```
