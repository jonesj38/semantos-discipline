---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/config-merger.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.114228+00:00
---

# runtime/services/src/services/config-store/config-merger.ts

```ts
/**
 * Pure config merger — combines a core extension with a domain
 * extension, de-duplicating object types by name (domain wins) and
 * capabilities by id.
 *
 * No I/O. Same merge semantics as the pre-split monolith.
 */

import type { ExtensionConfig } from '../../config/extensionConfig';

export function mergeExtensions(
  core: ExtensionConfig,
  domain: ExtensionConfig,
): ExtensionConfig {
  const domainTypeNames = new Set(domain.objectTypes.map((t) => t.name));
  const mergedTypes = [
    ...core.objectTypes.filter((t) => !domainTypeNames.has(t.name)),
    ...domain.objectTypes,
  ];

  const capMap = new Map(core.capabilities.map((c) => [c.id, c]));
  for (const cap of domain.capabilities) capMap.set(cap.id, cap);

  return {
    id: domain.id,
    name: domain.name,
    objectTypes: mergedTypes,
    capabilities: [...capMap.values()],
    scripts: [...core.scripts, ...domain.scripts],
    commercePhases: domain.commercePhases,
    taxonomy: domain.taxonomy ?? core.taxonomy,
    policies: domain.policies ?? core.policies,
    theme: domain.theme ?? core.theme,
    flows: [...(core.flows ?? []), ...(domain.flows ?? [])],
  };
}

```
