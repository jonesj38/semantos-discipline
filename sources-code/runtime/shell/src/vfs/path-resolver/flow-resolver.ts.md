---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/flow-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.390944+00:00
---

# runtime/shell/src/vfs/path-resolver/flow-resolver.ts

```ts
/**
 * Flows VFS view — projects each ConversationFlow into
 * `<id>/schema.json` and an empty `<id>/active/` directory.
 */

import type { ConfigStore } from '@semantos/runtime-services';

import { jsonContent } from './path-parser';
import type { VfsEntry, VfsFileContent } from './types';

export function readdirFlows(
  config: ConfigStore,
  segments: string[],
): string[] | null {
  const cfg = config.getConfig();
  const flows = cfg?.flows ?? [];

  if (segments.length === 0) return flows.map((f) => f.id);

  const flow = flows.find((f) => f.id === segments[0]);
  if (!flow) return null;
  if (segments.length === 1) return ['schema.json', 'active'];
  if (segments[1] === 'active' && segments.length === 2) return [];
  return null;
}

export function readFlow(
  config: ConfigStore,
  segments: string[],
): VfsFileContent | null {
  if (segments.length < 2) return null;
  const flows = config.getConfig()?.flows ?? [];
  const flow = flows.find((f) => f.id === segments[0]);
  if (!flow) return null;
  if (segments[1] === 'schema.json') return jsonContent(flow);
  return null;
}

export function getattrFlow(
  config: ConfigStore,
  segments: string[],
): VfsEntry | null {
  const flows = config.getConfig()?.flows ?? [];

  if (segments.length === 1) {
    if (flows.find((f) => f.id === segments[0])) {
      return { type: 'directory', name: segments[0] as string, size: 0 };
    }
    return null;
  }

  if (segments.length === 2) {
    if (segments[1] === 'active') return { type: 'directory', name: 'active', size: 0 };
    const content = readFlow(config, segments);
    if (content) return { type: 'file', name: segments[1] as string, size: content.size };
  }
  return null;
}

```
