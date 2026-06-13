---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/object-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.392905+00:00
---

# runtime/shell/src/vfs/path-resolver/object-resolver.ts

```ts
/**
 * Per-object VFS view — projects each LoomObject into a directory
 * containing `header.bin`, `payload.json`, optional `proof.spv`, and
 * a `patches/` subdirectory.
 */

import type { LoomStore, ObjectPatch } from '@semantos/runtime-services';

import { jsonContent } from './path-parser';
import { serializeHeaderBin } from './vfs-metadata-serializer';
import type { VfsEntry, VfsFileContent } from './types';

export function readdirObjects(
  store: LoomStore,
  segments: string[],
): string[] | null {
  const state = store.getState();

  if (segments.length === 0) return Array.from(state.objects.keys());

  const obj = state.objects.get(segments[0] as string);
  if (!obj) return null;

  if (segments.length === 1) {
    const entries = ['header.bin', 'payload.json'];
    if (obj.patches.length > 0) entries.push('patches');
    if (obj.packedCell) entries.push('proof.spv');
    return entries;
  }

  if (segments[1] === 'patches' && segments.length === 2) {
    return obj.patches.map(
      (p: ObjectPatch, i: number) => `${String(i).padStart(4, '0')}-${p.kind}.json`,
    );
  }

  return null;
}

export function readObject(
  store: LoomStore,
  segments: string[],
): VfsFileContent | null {
  if (segments.length < 2) return null;
  const obj = store.getState().objects.get(segments[0] as string);
  if (!obj) return null;

  if (segments[1] === 'payload.json') return jsonContent(obj.payload);
  if (segments[1] === 'header.bin') return serializeHeaderBin(obj.header);
  if (segments[1] === 'proof.spv' && obj.packedCell) {
    const buf = Buffer.from(obj.packedCell);
    return { data: buf, size: buf.length };
  }
  if (segments[1] === 'patches' && segments.length === 3) {
    const match = (segments[2] as string).match(/^(\d+)-/);
    if (!match) return null;
    const idx = parseInt(match[1] as string, 10);
    if (idx >= 0 && idx < obj.patches.length) return jsonContent(obj.patches[idx]);
  }
  return null;
}

export function getattrObject(
  store: LoomStore,
  segments: string[],
): VfsEntry | null {
  const state = store.getState();

  if (segments.length === 1) {
    if (state.objects.has(segments[0] as string)) {
      return { type: 'directory', name: segments[0] as string, size: 0 };
    }
    return null;
  }

  const obj = state.objects.get(segments[0] as string);
  if (!obj) return null;

  if (segments.length === 2) {
    if (segments[1] === 'patches') {
      return { type: 'directory', name: 'patches', size: 0 };
    }
    const content = readObject(store, segments);
    if (content) return { type: 'file', name: segments[1] as string, size: content.size };
  }

  if (segments.length === 3 && segments[1] === 'patches') {
    const content = readObject(store, segments);
    if (content) return { type: 'file', name: segments[2] as string, size: content.size };
  }

  return null;
}

```
