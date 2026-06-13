---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.391228+00:00
---

# runtime/shell/src/vfs/path-resolver/types.ts

```ts
/**
 * Public types for the VFS path-resolver split. Shapes preserved 1:1
 * from the pre-split monolith.
 */

export interface VfsEntry {
  type: 'file' | 'directory';
  name: string;
  size: number;
}

export interface VfsFileContent {
  data: Buffer;
  size: number;
}

/** Top-level VFS prefixes the resolver knows how to dispatch on. */
export const VFS_PREFIXES = ['objects', 'identities', 'taxonomy', 'governance', 'flows'] as const;

export type VfsPrefix = (typeof VFS_PREFIXES)[number];

/** Result of `parseVfsPath` — the prefix plus the remaining segments. */
export interface ParsedVfsPath {
  segments: string[];
  prefix: VfsPrefix | null;
  tail: string[];
}

export interface ResolverDeps {
  store: import('@semantos/runtime-services').LoomStore;
  identity: import('@semantos/runtime-services').IdentityStore;
  config: import('@semantos/runtime-services').ConfigStore;
  semanticFs?: import('@semantos/protocol-types').SemanticFS;
}

```
