---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/TaxonomyCoherence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.091698+00:00
---

# runtime/services/src/services/TaxonomyCoherence.ts

```ts
/**
 * TaxonomyCoherence — triangulation engine comparing tree structure
 * against embedding geometry.
 *
 * Checks the monotonicity property from Phase 22's Lean model:
 * for each node a with parent b, dist(a, b) ≤ dist(a, c) for all c
 * at the same depth as b that are not ancestors of a.
 *
 * Produces diagnostic reports with severity ratings and governance
 * ballot suggestions for taxonomy restructuring.
 *
 * See proofs/lean/Semantos/Category.lean for formal definitions.
 */

import { cosineDistance } from './cosine';
import { treeDistance, lowestCommonAncestor } from './tree-distance';
import type { EmbeddingService } from './EmbeddingService';

// ── Report Types ───────────────────────────────────────────

export interface CoherenceReport {
  timestamp: string;
  totalNodes: number;
  totalPairs: number;
  /** Fraction of parent-child pairs where the child is closer to its parent
      in embedding space than to any other node at the parent's depth. */
  monotonicity: number;
  /** Fraction of sibling pairs where embedding distance < cross-branch distance. */
  siblingCohesion: number;
  /** Nodes whose nearest embedding neighbor is NOT their tree-nearest neighbor. */
  misalignments: Misalignment[];
  /** Suggested taxonomy restructuring actions. */
  suggestions: CoherenceSuggestion[];
}

export interface Misalignment {
  nodePath: string;
  treeNearest: string;
  embeddingNearest: string;
  treeDistance: number;
  embeddingDistance: number;
  severity: 'info' | 'warning' | 'critical';
}

export interface CoherenceSuggestion {
  type: 'move' | 'merge' | 'split' | 'rename';
  nodePath: string;
  suggestedParent?: string;
  reason: string;
  governanceAction?: {
    flowId: string;
    payload: Record<string, unknown>;
  };
}

// ── Analyzer ───────────────────────────────────────────────

export class TaxonomyCoherence {
  private _embeddingService: EmbeddingService | null = null;

  /** Set the embedding service reference. */
  setEmbeddingService(service: EmbeddingService): void {
    this._embeddingService = service;
  }

  /**
   * Run full coherence analysis. Requires embeddingService.isReady().
   * Returns null if embeddings are unavailable.
   */
  analyze(): CoherenceReport | null {
    const emb = this._embeddingService;
    if (!emb || !emb.isReady()) return null;

    const paths = emb.getEmbeddedPaths();
    if (paths.length === 0) return null;

    const segmentsMap = new Map<string, string[]>();
    for (const p of paths) {
      segmentsMap.set(p, p.split('.'));
    }

    // Compute all pairwise embedding distances
    const embDist = new Map<string, number>();
    for (let i = 0; i < paths.length; i++) {
      for (let j = i + 1; j < paths.length; j++) {
        const a = paths[i];
        const b = paths[j];
        const va = emb.getEmbedding(a)!;
        const vb = emb.getEmbedding(b)!;
        const d = cosineDistance(va, vb);
        embDist.set(`${a}|${b}`, d);
        embDist.set(`${b}|${a}`, d);
      }
    }

    const getEmbDist = (a: string, b: string): number => {
      if (a === b) return 0;
      return embDist.get(`${a}|${b}`) ?? NaN;
    };

    // Group nodes by depth
    const byDepth = new Map<number, string[]>();
    for (const [p, segs] of segmentsMap) {
      const depth = segs.length;
      if (!byDepth.has(depth)) byDepth.set(depth, []);
      byDepth.get(depth)!.push(p);
    }

    // ── Monotonicity check ──
    let monoPasses = 0;
    let monoTotal = 0;

    for (const [nodePath, nodeSegs] of segmentsMap) {
      if (nodeSegs.length < 2) continue; // root nodes have no parent

      const parentSegs = nodeSegs.slice(0, -1);
      const parentPath = parentSegs.join('.');
      if (!segmentsMap.has(parentPath)) continue;

      const parentDepth = parentSegs.length;
      const nodesAtParentDepth = byDepth.get(parentDepth) ?? [];

      const distToParent = getEmbDist(nodePath, parentPath);
      if (isNaN(distToParent)) continue;

      let passes = true;
      for (const c of nodesAtParentDepth) {
        if (c === parentPath) continue;
        const cSegs = segmentsMap.get(c)!;
        // Skip if c is an ancestor of nodePath
        if (isPrefix(cSegs, nodeSegs)) continue;

        const distToC = getEmbDist(nodePath, c);
        if (isNaN(distToC)) continue;

        if (distToParent > distToC) {
          passes = false;
          break;
        }
      }

      monoTotal++;
      if (passes) monoPasses++;
    }

    // ── Sibling cohesion check ──
    let siblingPasses = 0;
    let siblingTotal = 0;

    // Group nodes by parent
    const byParent = new Map<string, string[]>();
    for (const [p, segs] of segmentsMap) {
      if (segs.length < 2) continue;
      const parentPath = segs.slice(0, -1).join('.');
      if (!byParent.has(parentPath)) byParent.set(parentPath, []);
      byParent.get(parentPath)!.push(p);
    }

    for (const [parentPath, siblings] of byParent) {
      if (siblings.length < 2) continue;

      const parentSegs = parentPath.split('.');
      const parentDepth = parentSegs.length;
      const nodesAtSiblingDepth = byDepth.get(parentDepth + 1) ?? [];

      // Compute average cross-branch distance at sibling depth
      const crossBranchDists: number[] = [];
      for (const sib of siblings) {
        for (const other of nodesAtSiblingDepth) {
          if (siblings.includes(other)) continue; // skip same-parent siblings
          const d = getEmbDist(sib, other);
          if (!isNaN(d)) crossBranchDists.push(d);
        }
      }
      const avgCrossBranch = crossBranchDists.length > 0
        ? crossBranchDists.reduce((a, b) => a + b, 0) / crossBranchDists.length
        : Infinity;

      // Check each sibling pair
      for (let i = 0; i < siblings.length; i++) {
        for (let j = i + 1; j < siblings.length; j++) {
          siblingTotal++;
          const d = getEmbDist(siblings[i], siblings[j]);
          if (!isNaN(d) && d < avgCrossBranch) {
            siblingPasses++;
          }
        }
      }
    }

    // ── Misalignment detection ──
    const misalignments: Misalignment[] = [];

    for (const nodePath of paths) {
      const nodeSegs = segmentsMap.get(nodePath)!;

      // Find tree-nearest neighbor (smallest tree distance, excluding self)
      let treeNearestPath = '';
      let treeNearestDist = Infinity;
      for (const other of paths) {
        if (other === nodePath) continue;
        const td = treeDistance(nodeSegs, segmentsMap.get(other)!);
        if (td < treeNearestDist) {
          treeNearestDist = td;
          treeNearestPath = other;
        }
      }

      // Find embedding-nearest neighbor
      let embNearestPath = '';
      let embNearestDist = Infinity;
      for (const other of paths) {
        if (other === nodePath) continue;
        const ed = getEmbDist(nodePath, other);
        if (!isNaN(ed) && ed < embNearestDist) {
          embNearestDist = ed;
          embNearestPath = other;
        }
      }

      if (treeNearestPath && embNearestPath && treeNearestPath !== embNearestPath) {
        const severity = classifySeverity(nodeSegs, segmentsMap.get(embNearestPath)!);
        misalignments.push({
          nodePath,
          treeNearest: treeNearestPath,
          embeddingNearest: embNearestPath,
          treeDistance: treeNearestDist,
          embeddingDistance: embNearestDist,
          severity,
        });
      }
    }

    // ── Suggestion generation ──
    const suggestions: CoherenceSuggestion[] = [];

    for (const m of misalignments) {
      if (m.severity === 'critical') {
        const embNearestSegs = segmentsMap.get(m.embeddingNearest)!;
        const suggestedParent = embNearestSegs.slice(0, -1).join('.') || embNearestSegs[0];
        suggestions.push({
          type: 'move',
          nodePath: m.nodePath,
          suggestedParent,
          reason: `Embedding nearest neighbor "${m.embeddingNearest}" is in a different domain than tree nearest "${m.treeNearest}".`,
          governanceAction: {
            flowId: 'challenge-classification',
            payload: {
              nodePath: m.nodePath,
              currentParent: segmentsMap.get(m.nodePath)!.slice(0, -1).join('.'),
              suggestedParent,
              embeddingDistance: m.embeddingDistance,
            },
          },
        });
      }
    }

    // Check for merge candidates: siblings closer to each other than to parent
    for (const [parentPath, siblings] of byParent) {
      for (let i = 0; i < siblings.length; i++) {
        for (let j = i + 1; j < siblings.length; j++) {
          const sibDist = getEmbDist(siblings[i], siblings[j]);
          const distToParentI = getEmbDist(siblings[i], parentPath);
          const distToParentJ = getEmbDist(siblings[j], parentPath);
          if (!isNaN(sibDist) && !isNaN(distToParentI) && !isNaN(distToParentJ)) {
            if (sibDist < distToParentI && sibDist < distToParentJ) {
              suggestions.push({
                type: 'merge',
                nodePath: siblings[i],
                reason: `Siblings "${siblings[i]}" and "${siblings[j]}" are closer to each other (${sibDist.toFixed(4)}) than either is to parent "${parentPath}".`,
              });
            }
          }
        }
      }
    }

    const totalPairs = (paths.length * (paths.length - 1)) / 2;

    return {
      timestamp: new Date().toISOString(),
      totalNodes: paths.length,
      totalPairs,
      monotonicity: monoTotal > 0 ? monoPasses / monoTotal : 1.0,
      siblingCohesion: siblingTotal > 0 ? siblingPasses / siblingTotal : 1.0,
      misalignments,
      suggestions,
    };
  }

  /**
   * Check monotonicity for a single node against all alternatives at parent depth.
   */
  checkNode(nodePath: string[]): Misalignment | null {
    const emb = this._embeddingService;
    if (!emb || !emb.isReady()) return null;
    if (nodePath.length < 2) return null;

    const nodePathStr = nodePath.join('.');
    const paths = emb.getEmbeddedPaths();

    // Find tree-nearest
    let treeNearestPath = '';
    let treeNearestDist = Infinity;
    for (const other of paths) {
      if (other === nodePathStr) continue;
      const td = treeDistance(nodePath, other.split('.'));
      if (td < treeNearestDist) {
        treeNearestDist = td;
        treeNearestPath = other;
      }
    }

    // Find embedding-nearest
    let embNearestPath = '';
    let embNearestDist = Infinity;
    for (const other of paths) {
      if (other === nodePathStr) continue;
      const va = emb.getEmbedding(nodePathStr);
      const vb = emb.getEmbedding(other);
      if (!va || !vb) continue;
      const d = cosineDistance(va, vb);
      if (d < embNearestDist) {
        embNearestDist = d;
        embNearestPath = other;
      }
    }

    if (treeNearestPath && embNearestPath && treeNearestPath !== embNearestPath) {
      return {
        nodePath: nodePathStr,
        treeNearest: treeNearestPath,
        embeddingNearest: embNearestPath,
        treeDistance: treeNearestDist,
        embeddingDistance: embNearestDist,
        severity: classifySeverity(nodePath, embNearestPath.split('.')),
      };
    }

    return null;
  }
}

// ── Helpers ────────────────────────────────────────────────

/** Check if `pre` is a prefix of `xs`. */
function isPrefix(pre: string[], xs: string[]): boolean {
  if (pre.length > xs.length) return false;
  for (let i = 0; i < pre.length; i++) {
    if (pre[i] !== xs[i]) return false;
  }
  return true;
}

/**
 * Classify severity of a misalignment based on domain relationship.
 * - info: same domain (same level-1 branch)
 * - warning: different subtree at same depth but same domain
 * - critical: completely different domain
 */
function classifySeverity(
  nodeSegs: string[],
  embNearestSegs: string[],
): 'info' | 'warning' | 'critical' {
  if (nodeSegs.length === 0 || embNearestSegs.length === 0) return 'critical';

  // Same domain?
  if (nodeSegs[0] === embNearestSegs[0]) {
    // Same subtree at depth 2?
    if (nodeSegs.length > 1 && embNearestSegs.length > 1 && nodeSegs[1] === embNearestSegs[1]) {
      return 'info';
    }
    return 'warning';
  }

  return 'critical';
}

/** Singleton instance. */
export const taxonomyCoherence = new TaxonomyCoherence();

```
