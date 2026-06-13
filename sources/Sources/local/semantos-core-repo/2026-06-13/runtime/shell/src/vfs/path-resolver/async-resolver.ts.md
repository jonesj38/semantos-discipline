---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/async-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.391786+00:00
---

# runtime/shell/src/vfs/path-resolver/async-resolver.ts

```ts
/**
 * Async resolver delegates — try the optional `SemanticFS` for
 * `objects/*` paths and fall back to the synchronous resolver on any
 * miss. Mirrors the legacy `readdirAsync` / `readAsync` /
 * `getattrAsync` behaviour: SemanticFS errors and empty results both
 * fall through.
 */

import type { SemanticFS } from '@semantos/protocol-types';

import { parseSegments } from './path-parser';
import type { VfsEntry, VfsFileContent } from './types';

export async function readdirAsyncForObjects(
  semanticFs: SemanticFS,
  path: string,
): Promise<string[] | null> {
  const segments = parseSegments(path);
  if (segments.length === 0 || segments[0] !== 'objects') return null;

  try {
    const semPath = segments.join('/');
    const refs = await semanticFs.list(semPath, { depth: 1 });
    if (refs.length === 0) return null;
    const prefix = semPath + '/';
    const names = new Set<string>();
    for (const ref of refs) {
      const relative = ref.key.startsWith(prefix) ? ref.key.slice(prefix.length) : ref.key;
      const firstSeg = relative.split('/')[0];
      if (firstSeg) names.add(firstSeg);
    }
    return Array.from(names);
  } catch {
    return null;
  }
}

export async function readAsyncForObjects(
  semanticFs: SemanticFS,
  path: string,
): Promise<VfsFileContent | null> {
  const segments = parseSegments(path);
  if (segments.length < 2 || segments[0] !== 'objects') return null;

  try {
    const cell = await semanticFs.get(segments.join('/'));
    if (!cell) return null;
    const buf = Buffer.from(cell.payload);
    return { data: buf, size: buf.length };
  } catch {
    return null;
  }
}

export async function getattrAsyncForObjects(
  semanticFs: SemanticFS,
  path: string,
): Promise<VfsEntry | null> {
  const segments = parseSegments(path);
  if (segments.length < 2 || segments[0] !== 'objects') return null;

  try {
    const semPath = segments.join('/');
    const refs = await semanticFs.list(semPath, { depth: 1 });
    if (refs.length > 0) {
      return {
        type: 'directory',
        name: segments[segments.length - 1] as string,
        size: 0,
      };
    }
    const cell = await semanticFs.get(semPath);
    if (cell) {
      return {
        type: 'file',
        name: segments[segments.length - 1] as string,
        size: cell.payload.length,
      };
    }
    return null;
  } catch {
    return null;
  }
}

```
