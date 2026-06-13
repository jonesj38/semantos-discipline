---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/config-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.113652+00:00
---

# runtime/services/src/services/config-store/config-loader.ts

```ts
/**
 * Async config loader — looks the id up in the bundledExtensionsPort
 * first, falls back to the `/api/extensions/<id>` HTTP path. Always
 * runs the loaded shape through `validateExtensionConfig` so callers
 * never see un-validated data.
 */

import {
  type ExtensionConfig,
  validateExtensionConfig,
} from '../../config/extensionConfig';
import { getBundledExtensions } from './ports';

export async function loadConfig(id: string): Promise<ExtensionConfig> {
  const bundled = getBundledExtensions();
  let data: unknown;
  if (bundled.hasExtension(id)) {
    const mod = await bundled.loadExtension(id);
    data = (mod as { default: unknown }).default;
  } else {
    const res = await fetch(`/api/extensions/${id}`);
    if (!res.ok) throw new Error(`Failed to load extension ${id}: ${res.status}`);
    data = await res.json();
  }
  return validateExtensionConfig(data);
}

```
