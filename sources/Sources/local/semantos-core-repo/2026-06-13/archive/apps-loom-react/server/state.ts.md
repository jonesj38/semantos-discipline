---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/server/state.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.930564+00:00
---

# archive/apps-loom-react/server/state.ts

```ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const BASE_DIR = join(homedir(), '.semantos', 'workspaces');

function ensureDir(dir: string) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

export function loadWorkspace(extensionId: string): unknown | null {
  const filePath = join(BASE_DIR, extensionId, 'workspace.json');
  try {
    if (existsSync(filePath)) {
      return JSON.parse(readFileSync(filePath, 'utf-8'));
    }
  } catch (e) {
    console.error(`Failed to load workspace ${extensionId}:`, e);
  }
  return null;
}

const saveTimers = new Map<string, Timer>();

export function saveWorkspace(extensionId: string, data: unknown): void {
  // Debounce saves to 2s
  const existing = saveTimers.get(extensionId);
  if (existing) clearTimeout(existing);

  saveTimers.set(extensionId, setTimeout(() => {
    try {
      const dir = join(BASE_DIR, extensionId);
      ensureDir(dir);
      writeFileSync(join(dir, 'workspace.json'), JSON.stringify(data, null, 2));
    } catch (e) {
      console.error(`Failed to save workspace ${extensionId}:`, e);
    }
    saveTimers.delete(extensionId);
  }, 2000));
}

```
