---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/governance-index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.392630+00:00
---

# runtime/shell/src/vfs/path-resolver/governance-index.ts

```ts
/**
 * Governance VFS view — projects the LoomStore object map into the
 * `ballots/` and `disputes/` directories. Pure helpers; no I/O.
 */

import type { LoomStore } from '@semantos/runtime-services';

import { jsonContent } from './path-parser';
import type { VfsEntry, VfsFileContent } from './types';

const CATEGORIES = new Set(['ballots', 'disputes']);

/** Map a category bucket to the `obj.typeDefinition.category` substring. */
function categoryMatches(category: string, objCategory: string | undefined): boolean {
  const cat = objCategory ?? '';
  if (category === 'ballots' && cat.includes('ballot')) return true;
  if (category === 'disputes' && cat.includes('dispute')) return true;
  return false;
}

export function readdirGovernance(
  store: LoomStore,
  segments: string[],
): string[] | null {
  if (segments.length === 0) return ['ballots', 'disputes'];

  if (segments.length === 1) {
    const category = segments[0] as string;
    if (!CATEGORIES.has(category)) return null;
    const state = store.getState();
    const entries: string[] = [];
    for (const [id, obj] of state.objects) {
      if (categoryMatches(category, obj.typeDefinition?.category)) {
        entries.push(`${id}.json`);
      }
    }
    return entries;
  }

  return null;
}

export function readGovernance(
  store: LoomStore,
  segments: string[],
): VfsFileContent | null {
  if (segments.length < 2) return null;
  const fileName = segments[1] as string;
  if (!fileName.endsWith('.json')) return null;
  const objId = fileName.replace('.json', '');
  const obj = store.getState().objects.get(objId);
  if (!obj) return null;
  return jsonContent({ ...obj.payload, id: obj.id, visibility: obj.visibility });
}

export function getattrGovernance(
  store: LoomStore,
  segments: string[],
): VfsEntry | null {
  if (segments.length === 1) {
    const category = segments[0] as string;
    if (CATEGORIES.has(category)) return { type: 'directory', name: category, size: 0 };
    return null;
  }
  if (segments.length === 2) {
    const content = readGovernance(store, segments);
    if (content) return { type: 'file', name: segments[1] as string, size: content.size };
  }
  return null;
}

```
