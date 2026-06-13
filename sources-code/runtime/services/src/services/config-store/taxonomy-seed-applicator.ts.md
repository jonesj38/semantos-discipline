---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/taxonomy-seed-applicator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.113940+00:00
---

# runtime/services/src/services/config-store/taxonomy-seed-applicator.ts

```ts
/**
 * Pure three-axis taxonomy seed application.
 *
 * `applyTaxonomySeed(config, seed)` produces a new config whose
 * `taxonomy.dimensions` is the seed dimensions merged with any domain
 * dimensions that share an id. Domain-only dimensions (e.g.
 * "instrument") pass through untouched.
 */

import type {
  ExtensionConfig,
  TaxonomyDimensionDef,
  TaxonomyNode,
} from '../../config/extensionConfig';
import type { SeedAxis, SeedNode } from './atoms';

/** Convert seed nodes into the public TaxonomyNode shape. */
export function seedToTaxonomyNodes(seedNodes: SeedNode[]): TaxonomyNode[] {
  return seedNodes.map((sn) => ({
    path: sn.path,
    name: sn.name,
    axis: sn.axis,
    metadata: sn.metadata,
    children: sn.children ? seedToTaxonomyNodes(sn.children) : undefined,
  }));
}

/** Merge seed taxonomy into the config's taxonomy.dimensions. */
export function applyTaxonomySeed(
  config: ExtensionConfig,
  seed: Record<string, SeedAxis> | null,
): ExtensionConfig {
  if (!seed) return config;

  const seedDimensions: TaxonomyDimensionDef[] = [];
  for (const [axisKey, axis] of Object.entries(seed)) {
    seedDimensions.push({
      id: axisKey,
      name: axis.name,
      rootPath: axis.rootPath,
      nodes: seedToTaxonomyNodes(axis.nodes),
    });
  }

  const existingDims = config.taxonomy?.dimensions ?? [];
  const mergedDims = [...seedDimensions];

  for (const existingDim of existingDims) {
    const seedIdx = mergedDims.findIndex((d) => d.id === existingDim.id);
    if (seedIdx >= 0) {
      const seedDim = mergedDims[seedIdx]!;
      const existingPaths = flattenNodePaths(seedDim.nodes);
      const newNodes = existingDim.nodes.filter((n) => !existingPaths.has(n.path));
      mergedDims[seedIdx] = {
        ...seedDim,
        nodes: [...seedDim.nodes, ...newNodes],
      };
    } else {
      mergedDims.push(existingDim);
    }
  }

  return { ...config, taxonomy: { dimensions: mergedDims } };
}

/** Collect every node path from a tree into a Set. */
export function flattenNodePaths(nodes: TaxonomyNode[]): Set<string> {
  const paths = new Set<string>();
  const walk = (ns: TaxonomyNode[]): void => {
    for (const n of ns) {
      paths.add(n.path);
      if (n.children) walk(n.children);
    }
  };
  walk(nodes);
  return paths;
}

```
