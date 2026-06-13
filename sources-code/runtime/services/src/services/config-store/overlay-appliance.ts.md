---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/overlay-appliance.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.115364+00:00
---

# runtime/services/src/services/config-store/overlay-appliance.ts

```ts
/**
 * Pure overlay application — folds every governance-driven taxonomy
 * extension into a config's `taxonomy.dimensions`, dedup'd by node
 * path. Used both at config-switch time and after a single overlay is
 * appended.
 */

import type {
  ConfigOverlay,
  ExtensionConfig,
  TaxonomyNode,
} from '../../config/extensionConfig';
import { flattenNodePaths } from './taxonomy-seed-applicator';

/**
 * Immutably insert `newNode` as a child of the node whose `path`
 * matches `parentPath`. Returns null if no such ancestor exists.
 */
export function insertNodeAtParent(
  nodes: TaxonomyNode[],
  parentPath: string,
  newNode: TaxonomyNode,
): TaxonomyNode[] | null {
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i]!;
    if (node.path === parentPath) {
      const updatedNode = { ...node, children: [...(node.children ?? []), newNode] };
      return [...nodes.slice(0, i), updatedNode, ...nodes.slice(i + 1)];
    }
    if (node.children) {
      const updatedChildren = insertNodeAtParent(node.children, parentPath, newNode);
      if (updatedChildren) {
        const updatedNode = { ...node, children: updatedChildren };
        return [...nodes.slice(0, i), updatedNode, ...nodes.slice(i + 1)];
      }
    }
  }
  return null;
}

/** Apply every overlay to the supplied config, returning a new one. */
export function applyAllOverlays(
  config: ExtensionConfig,
  overlays: ConfigOverlay[],
): ExtensionConfig {
  if (overlays.length === 0) return config;

  let taxonomy = config.taxonomy ?? { dimensions: [] };

  for (const overlay of overlays) {
    if (!overlay.taxonomyNodes) continue;
    for (const node of overlay.taxonomyNodes) {
      const axis = node.axis ?? 'what';
      const dimIdx = taxonomy.dimensions.findIndex((d) => d.id === axis);
      if (dimIdx < 0) continue;

      const dim = taxonomy.dimensions[dimIdx]!;
      if (flattenNodePaths(dim.nodes).has(node.path)) continue;

      const parentPath = node.path.split('.').slice(0, -1).join('.');
      const updatedNodes = insertNodeAtParent(dim.nodes, parentPath, node);
      taxonomy = {
        ...taxonomy,
        dimensions: taxonomy.dimensions.map((d, i) =>
          i === dimIdx ? { ...d, nodes: updatedNodes ?? [...d.nodes, node] } : d,
        ),
      };
    }
  }

  return { ...config, taxonomy, overlays };
}

```
