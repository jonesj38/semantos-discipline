---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/server/config-loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.931092+00:00
---

# archive/apps-loom-react/server/config-loader.ts

```ts
import { readdirSync, readFileSync, watch } from 'fs';
import { join } from 'path';

const CONFIG_DIR = join(import.meta.dir, '../../../configs/extensions');

export async function loadExtensionConfigs(): Promise<Record<string, unknown>> {
  const configs: Record<string, unknown> = {};
  try {
    const files = readdirSync(CONFIG_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const content = readFileSync(join(CONFIG_DIR, file), 'utf-8');
        const parsed = JSON.parse(content);
        if (parsed.id) {
          configs[parsed.id] = parsed;
        }
      } catch (e) {
        console.error(`Failed to parse ${file}:`, e);
      }
    }
  } catch (e) {
    console.error(`Failed to read config directory:`, e);
  }
  return configs;
}

export function watchConfigs(onChange: () => void): void {
  try {
    watch(CONFIG_DIR, { persistent: false }, () => {
      onChange();
    });
  } catch {
    // Config directory may not exist yet
  }
}

```
