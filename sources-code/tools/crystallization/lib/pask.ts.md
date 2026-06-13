---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/pask.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.556417+00:00
---

# tools/crystallization/lib/pask.ts

```ts
/**
 * Lightweight Pask stability engine — pure TypeScript, no WASM.
 *
 * Models concept co-occurrence in documents as a constraint graph.
 * Nodes = concepts.  Edge (A, B) accumulates weight each time A and B
 * co-occur in a document.  Stability is assessed as the rate of change
 * in each node's h_state (constraint satisfaction magnitude).
 *
 * This captures the same invariant as the Zig Pask kernel but without
 * the full delta-tracking machinery — suitable for document-level
 * co-occurrence rather than real-time interaction streams.
 */
import type { CorpusDoc, PaskEdge } from '../types';

interface Node { h: number; interactions: number; prevH: number }
interface Edge { weight: number; coocs: number }

export class MiniPask {
  private nodes = new Map<string, Node>();
  private edges = new Map<string, Edge>(); // key = "A\0B" (sorted)
  private readonly lr: number;

  constructor(learningRate = 0.01) { this.lr = learningRate; }

  private edgeKey(a: string, b: string): string {
    return a < b ? `${a}\0${b}` : `${b}\0${a}`;
  }

  /** Feed a document's co-occurring concepts as a batch of interactions. */
  feedDocument(mentions: Map<string, number>): void {
    const concepts = [...mentions.keys()];
    for (const c of concepts) {
      if (!this.nodes.has(c)) this.nodes.set(c, { h: 0, interactions: 0, prevH: 0 });
      const n = this.nodes.get(c)!;
      const strength = mentions.get(c)! / 10; // normalise raw count
      n.prevH = n.h;
      n.h += this.lr * strength;
      n.interactions++;
    }
    // Co-occurrence edges
    for (let i = 0; i < concepts.length; i++) {
      for (let j = i + 1; j < concepts.length; j++) {
        const key = this.edgeKey(concepts[i], concepts[j]);
        const e = this.edges.get(key) ?? { weight: 0, coocs: 0 };
        const w = (mentions.get(concepts[i])! + mentions.get(concepts[j])!) / 2;
        e.weight += this.lr * (w / 10);
        e.coocs++;
        this.edges.set(key, e);
      }
    }
  }

  /** Stability score for a concept: normalised h_state weighted by interaction count. */
  stabilityScore(concept: string): number {
    const n = this.nodes.get(concept);
    if (!n || n.interactions === 0) return 0;
    const delta = Math.abs(n.h - n.prevH);
    // Higher h with low delta = stable; scale to [0,1]
    return n.h / (1 + delta * 100);
  }

  /** Build scored edges above a co-occurrence threshold. */
  topEdges(minCoocs: number, topN = 50): PaskEdge[] {
    const totalDocs = Math.max(1, [...this.nodes.values()].reduce((s, n) => s + n.interactions, 0) / this.nodes.size);
    const edges: PaskEdge[] = [];
    for (const [key, e] of this.edges) {
      if (e.coocs < minCoocs) continue;
      const [a, b] = key.split('\0');
      const na = this.nodes.get(a)?.interactions ?? 1;
      const nb = this.nodes.get(b)?.interactions ?? 1;
      const score = e.coocs / Math.sqrt(na * nb); // Jaccard-like
      edges.push({ a, b, coocs: e.coocs, score });
    }
    return edges.sort((a, b) => b.score - a.score).slice(0, topN);
  }

  allNodes(): Map<string, Node> { return this.nodes; }
}

export function buildPask(docs: CorpusDoc[]): MiniPask {
  const pask = new MiniPask();
  for (const doc of docs) pask.feedDocument(doc.mentions);
  return pask;
}

```
