---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/path-parser.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.392350+00:00
---

# runtime/shell/src/vfs/path-resolver/path-parser.ts

```ts
/**
 * Pure path parser — splits a VFS path into segments and identifies
 * the dispatch prefix. Same semantics as the legacy `parsePath`
 * (strips leading/trailing slashes, drops empties).
 */

import { VFS_PREFIXES, type ParsedVfsPath, type VfsPrefix } from './types';

/** Split a VFS path into normalized segments. */
export function parseSegments(path: string): string[] {
  return path
    .replace(/^\/+|\/+$/g, '')
    .split('/')
    .filter(Boolean);
}

/** Parse a VFS path into its prefix + tail. */
export function parseVfsPath(path: string): ParsedVfsPath {
  const segments = parseSegments(path);
  if (segments.length === 0) {
    return { segments, prefix: null, tail: [] };
  }
  const head = segments[0] as string;
  const prefix = (VFS_PREFIXES as readonly string[]).includes(head) ? (head as VfsPrefix) : null;
  return {
    segments,
    prefix,
    tail: segments.slice(1),
  };
}

/** Render a `data` value into a VfsFileContent JSON envelope. */
export function jsonContent(data: unknown): import('./types').VfsFileContent {
  const json = JSON.stringify(data, null, 2) + '\n';
  const buf = Buffer.from(json, 'utf-8');
  return { data: buf, size: buf.length };
}

```
