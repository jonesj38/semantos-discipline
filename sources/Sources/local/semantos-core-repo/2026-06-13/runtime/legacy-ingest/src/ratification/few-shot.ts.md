---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/ratification/few-shot.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.163930+00:00
---

# runtime/legacy-ingest/src/ratification/few-shot.ts

```ts
/**
 * Few-shot correction retrieval — LI4.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI4 deliverable 4.
 *
 * The extractor's prompt for each provider includes the K most recent
 * correction-edge cells as in-context training examples. Pinned
 * corrections always appear; the rest fill remaining slots in
 * recency order.
 *
 * v1 retrieval is purely chronological + pinned-first. Future
 * iterations may rank by similarity (TODO LI5).
 */

import type { CorrectionEdge } from './types';
import type { CorrectionEdgeStore } from './store';

export interface FewShotRetrieverOpts {
  store: CorrectionEdgeStore;
  k?: number;
}

export class FewShotRetriever {
  private readonly store: CorrectionEdgeStore;
  private readonly k: number;

  constructor(opts: FewShotRetrieverOpts) {
    this.store = opts.store;
    this.k = opts.k ?? 8;
  }

  async retrieve(providerId: string): Promise<CorrectionEdge[]> {
    const all = await this.store.list(providerId);
    const sorted = [...all].sort((a, b) => {
      if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
      return b.createdAt.localeCompare(a.createdAt);
    });
    return sorted.slice(0, this.k).reverse();
  }

  static renderBlock(corrections: CorrectionEdge[]): string {
    if (corrections.length === 0) return '';
    const lines: string[] = ['## Past corrections from the operator', ''];
    for (const c of corrections) {
      lines.push('---');
      lines.push(`Original (extractor v${c.source.extractorVersion}):`);
      lines.push(JSON.stringify(c.original, null, 2));
      lines.push('Operator corrected to:');
      lines.push(JSON.stringify(c.corrected, null, 2));
      if (c.reason) lines.push(`Reason: ${c.reason}`);
      lines.push('');
    }
    return lines.join('\n');
  }
}

```
