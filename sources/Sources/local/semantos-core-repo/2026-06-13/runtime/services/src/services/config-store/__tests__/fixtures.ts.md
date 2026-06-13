---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.126839+00:00
---

# runtime/services/src/services/config-store/__tests__/fixtures.ts

```ts
/**
 * Shared fixtures for ConfigStore tests.
 */

import type { ExtensionConfig } from '../../../config/extensionConfig';
import type { SeedAxis } from '../atoms';

export function makeConfig(over: Partial<ExtensionConfig> = {}): ExtensionConfig {
  return {
    id: 'test',
    name: 'Test',
    objectTypes: [],
    capabilities: [],
    scripts: [],
    commercePhases: [],
    flows: [],
    ...over,
  } as ExtensionConfig;
}

export const sampleSeed: Record<string, SeedAxis> = {
  what: {
    name: 'what',
    rootPath: 'what',
    nodes: [
      { path: 'what.service', name: 'service', axis: 'what' },
      { path: 'what.thing', name: 'thing', axis: 'what' },
    ],
  },
};

```
