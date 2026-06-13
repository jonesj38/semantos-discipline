---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/taxonomy-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.390099+00:00
---

# runtime/shell/src/vfs/path-resolver/taxonomy-resolver.ts

```ts
/**
 * Taxonomy VFS view — projects each `taxonomy.dimensions[*]` into a
 * directory of `<name>` (subdirectory if children) + `<name>.json`
 * (the node payload). Walking + reading is delegated to the pure
 * helpers in `taxonomy-walker.ts`.
 */

import type { ConfigStore } from '@semantos/runtime-services';

import { readTaxonomyNode, walkTaxonomyDir } from './taxonomy-walker';
import type { VfsEntry, VfsFileContent } from './types';

export function readdirTaxonomy(
  config: ConfigStore,
  segments: string[],
): string[] | null {
  const cfg = config.getConfig();
  if (!cfg?.taxonomy) return segments.length === 0 ? [] : null;

  const dimensions = cfg.taxonomy.dimensions;
  if (segments.length === 0) return dimensions.map((d) => d.id);

  const dim = dimensions.find((d) => d.id === segments[0]);
  if (!dim) return null;
  return walkTaxonomyDir(dim.nodes, segments.slice(1));
}

export function readTaxonomy(
  config: ConfigStore,
  segments: string[],
): VfsFileContent | null {
  const cfg = config.getConfig();
  if (!cfg?.taxonomy || segments.length < 2) return null;
  const dim = cfg.taxonomy.dimensions.find((d) => d.id === segments[0]);
  if (!dim) return null;
  return readTaxonomyNode(dim.nodes, segments.slice(1));
}

export function getattrTaxonomy(
  config: ConfigStore,
  segments: string[],
): VfsEntry | null {
  const cfg = config.getConfig();
  if (!cfg?.taxonomy) return null;

  if (segments.length === 1) {
    const dim = cfg.taxonomy.dimensions.find((d) => d.id === segments[0]);
    if (dim) return { type: 'directory', name: segments[0] as string, size: 0 };
    return null;
  }

  const lastSeg = segments[segments.length - 1] as string;
  if (lastSeg.endsWith('.json')) {
    const content = readTaxonomy(config, segments);
    if (content) return { type: 'file', name: lastSeg, size: content.size };
    return null;
  }

  const entries = readdirTaxonomy(config, segments);
  if (entries) return { type: 'directory', name: lastSeg, size: 0 };
  return null;
}

```
