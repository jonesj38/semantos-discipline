---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/coherence-checker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.108521+00:00
---

# runtime/services/src/services/intent-classifier/coherence-checker.ts

```ts
/**
 * Coherence checker — pure adapter over the bound coherence port.
 */

import type { CoherenceWarning } from '../intent-types';
import { getCoherence } from './ports';

/**
 * Build a CoherenceWarning when the bound coherence port flags the
 * given node path as misaligned. Returns null otherwise (and when no
 * coherence port is bound).
 */
export function checkCoherence(path: string[]): CoherenceWarning | null {
  if (path.length < 2) return null;
  const checker = getCoherence();
  if (!checker) return null;

  const misalignment = checker.checkNode(path);
  if (!misalignment) return null;

  return {
    nodePath: misalignment.nodePath,
    embeddingNearest: misalignment.embeddingNearest,
    severity: misalignment.severity,
    message: `Taxonomy node "${misalignment.nodePath}" is nearest to "${misalignment.embeddingNearest}" in embedding space (${misalignment.severity}). Consider reviewing via govern.challenge-classification.`,
  };
}

```
