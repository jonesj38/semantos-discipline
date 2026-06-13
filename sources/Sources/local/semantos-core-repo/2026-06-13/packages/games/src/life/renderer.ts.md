---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/life/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.407421+00:00
---

# packages/games/src/life/renderer.ts

```ts
/**
 * ASCII Game of Life renderer.
 *
 * Uses # for alive cells and . for dead cells.
 */

import type { LifeBoard } from './types';

/** Render a Game of Life board as an ASCII string. */
export function renderBoard(board: LifeBoard): string {
  const { width, height, alive, generation } = board;
  const lines: string[] = [];

  lines.push(`Generation ${generation}  Population ${alive.size}  (${width}x${height})`);
  lines.push('');

  for (let r = 0; r < height; r++) {
    let line = '';
    for (let c = 0; c < width; c++) {
      const pos = r * width + c;
      line += alive.has(pos) ? '#' : '.';
    }
    lines.push(line);
  }

  return lines.join('\n');
}

```
