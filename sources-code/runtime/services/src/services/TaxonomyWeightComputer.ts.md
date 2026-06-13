---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/TaxonomyWeightComputer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.095850+00:00
---

# runtime/services/src/services/TaxonomyWeightComputer.ts

```ts
/**
 * TaxonomyWeightComputer — pure function computing activity weights per taxonomy node.
 *
 * Counts objects at each coordinate path within a given axis, producing a weight map
 * that drives activity-based sorting in TaxonomyBrowser.
 */

import type { LoomObject } from '../types/loom';

/** Weight data for a single taxonomy node. */
export interface TaxonomyWeight {
  activity: number;     // count of objects at or below this coordinate
  relevance: number;    // reputation-weighted activity (future: use identity reputation)
  lastUpdated: number;  // timestamp of most recent object patch at this coordinate
}

/**
 * Compute taxonomy weights for a given axis by scanning all objects.
 *
 * For the "what" axis: matches against object.typeCoordinate.what and object.typeDefinition.category
 * For "how"/"why" axes: matches against object.typeCoordinate.how[] / object.typeCoordinate.why[]
 *
 * Returns a Map of path -> TaxonomyWeight. Weights accumulate up the tree:
 * an object at "what.service.fabrication.carpentry" also counts toward
 * "what.service.fabrication" and "what.service".
 */
export function computeTaxonomyWeights(
  allObjects: Map<string, LoomObject>,
  axis: 'what' | 'how' | 'why',
): Map<string, TaxonomyWeight> {
  const weights = new Map<string, TaxonomyWeight>();

  for (const obj of allObjects.values()) {
    const paths = extractPaths(obj, axis);
    const latestPatchTime = obj.patches.length > 0
      ? Math.max(...obj.patches.map(p => p.timestamp))
      : obj.createdAt;

    for (const path of paths) {
      // Accumulate at this path and all ancestor paths
      const ancestors = getAncestorPaths(path);
      for (const ancestorPath of ancestors) {
        const existing = weights.get(ancestorPath);
        if (existing) {
          existing.activity += 1;
          existing.relevance += 1;  // 1:1 with activity for now; future: weight by reputation
          existing.lastUpdated = Math.max(existing.lastUpdated, latestPatchTime);
        } else {
          weights.set(ancestorPath, {
            activity: 1,
            relevance: 1,
            lastUpdated: latestPatchTime,
          });
        }
      }
    }
  }

  return weights;
}

/** Extract taxonomy paths from an object for a given axis. */
function extractPaths(obj: LoomObject, axis: 'what' | 'how' | 'why'): string[] {
  const coord = obj.typeCoordinate;

  if (axis === 'what') {
    const paths: string[] = [];
    if (coord?.what) paths.push(coord.what);
    // Also check the category from the type definition as a fallback
    const category = obj.typeDefinition.category;
    if (category && !paths.some(p => p === category)) {
      // Map category to what-axis if it starts with "what." or is a domain path
      if (category.startsWith('what.')) {
        paths.push(category);
      }
    }
    return paths;
  }

  if (axis === 'how') {
    return coord?.how ?? [];
  }

  if (axis === 'why') {
    return coord?.why ?? [];
  }

  return [];
}

/** Get all ancestor paths including the path itself. "what.service.fabrication" -> ["what.service.fabrication", "what.service", "what"] */
function getAncestorPaths(path: string): string[] {
  const parts = path.split('.');
  const ancestors: string[] = [];
  for (let i = parts.length; i >= 1; i--) {
    ancestors.push(parts.slice(0, i).join('.'));
  }
  return ancestors;
}

```
