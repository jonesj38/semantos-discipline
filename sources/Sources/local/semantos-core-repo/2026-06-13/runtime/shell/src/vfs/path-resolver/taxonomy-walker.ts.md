---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/taxonomy-walker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.391502+00:00
---

# runtime/shell/src/vfs/path-resolver/taxonomy-walker.ts

```ts
/**
 * Pure taxonomy directory walker. Same semantics as the legacy
 * `walkTaxonomyDir` + `readTaxonomyNode`: every node is exposed as
 * both `<name>.json` (file) and, when it has children, `<name>` (a
 * directory).
 */

import type { TaxonomyNode } from '@semantos/protocol-types';

import { jsonContent } from './path-parser';
import type { VfsFileContent } from './types';

/** Last segment of a dotted taxonomy path. */
function tailName(node: TaxonomyNode): string {
  return node.path.split('.').pop() ?? node.path;
}

/**
 * List entries at the given depth into a taxonomy dimension. Returns
 * null if the segments don't resolve to a directory.
 */
export function walkTaxonomyDir(
  nodes: TaxonomyNode[],
  segments: string[],
): string[] | null {
  if (segments.length === 0) {
    const entries: string[] = [];
    for (const node of nodes) {
      const name = tailName(node);
      if (node.children && node.children.length > 0) entries.push(name);
      entries.push(`${name}.json`);
    }
    return entries;
  }

  const target = (segments[0] as string).replace('.json', '');
  for (const node of nodes) {
    if (tailName(node) === target && node.children) {
      return walkTaxonomyDir(node.children, segments.slice(1));
    }
  }
  return null;
}

/** Resolve a taxonomy file path to its JSON envelope. */
export function readTaxonomyNode(
  nodes: TaxonomyNode[],
  segments: string[],
): VfsFileContent | null {
  const fileName = segments[segments.length - 1] as string;
  if (!fileName.endsWith('.json')) return null;
  const targetName = fileName.replace('.json', '');

  if (segments.length === 1) {
    const node = nodes.find((n) => tailName(n) === targetName);
    if (node) return jsonContent(node);
    return null;
  }

  const dirName = segments[0] as string;
  for (const node of nodes) {
    if (tailName(node) === dirName && node.children) {
      return readTaxonomyNode(node.children, segments.slice(1));
    }
  }
  return null;
}

```
