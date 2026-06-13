---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/tree-distance.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.097910+00:00
---

# runtime/services/src/services/tree-distance.ts

```ts
/**
 * Tree distance and LCA — pure functions on path arrays.
 *
 * Corresponds to the graph distance in the poset category from
 * proofs/lean/Semantos/Category.lean. The taxonomy tree is a forest
 * rooted at domain nodes; distance is the number of edges on the
 * shortest path through the lowest common ancestor.
 */

/**
 * Find the lowest common ancestor of two paths.
 * Returns the longest common prefix.
 *
 * Examples:
 *   lca(["create", "job"], ["create", "quote"]) = ["create"]
 *   lca(["create", "job"], ["navigate", "objects"]) = []
 *   lca(["create"], ["create"]) = ["create"]
 */
export function lowestCommonAncestor(a: string[], b: string[]): string[] {
  const len = Math.min(a.length, b.length);
  const prefix: string[] = [];
  for (let i = 0; i < len; i++) {
    if (a[i] === b[i]) {
      prefix.push(a[i]);
    } else {
      break;
    }
  }
  return prefix;
}

/**
 * Compute the tree distance between two nodes in the taxonomy tree.
 * Distance = number of edges on the shortest path.
 *
 * Algorithm: find the lowest common ancestor (LCA), then
 * distance = (depth(a) - depth(lca)) + (depth(b) - depth(lca)).
 *
 * Examples:
 *   treeDistance(["create", "job"], ["create", "quote"]) = 2  (sibling)
 *   treeDistance(["create", "job"], ["create"]) = 1           (parent)
 *   treeDistance(["create", "job"], ["navigate", "objects"]) = 4  (cross-domain)
 *   treeDistance(["create"], ["create"]) = 0                  (identity)
 */
export function treeDistance(a: string[], b: string[]): number {
  const lca = lowestCommonAncestor(a, b);
  return (a.length - lca.length) + (b.length - lca.length);
}

```
