---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/go/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.413186+00:00
---

# packages/games/src/go/renderer.ts

```ts
/**
 * ASCII Go board renderer.
 *
 * Uses + for empty intersections, X for black stones, O for white stones.
 * Star points (hoshi) are marked with * when empty.
 */

import type { GoBoard } from './types';
import { intersectionRow, intersectionCol } from './types';

// -- Star Points (hoshi) for standard board sizes -------------------------

const STAR_POINTS: Record<number, number[][]> = {
  9: [[2, 2], [2, 6], [4, 4], [6, 2], [6, 6]],
  13: [[3, 3], [3, 9], [6, 6], [9, 3], [9, 9]],
  19: [
    [3, 3], [3, 9], [3, 15],
    [9, 3], [9, 9], [9, 15],
    [15, 3], [15, 9], [15, 15],
  ],
};

function isStarPoint(row: number, col: number, size: number): boolean {
  const points = STAR_POINTS[size];
  if (!points) return false;
  return points.some(([r, c]) => r === row && c === col);
}

/** Render a Go board as an ASCII string. */
export function renderBoard(board: GoBoard): string {
  const { size, intersections } = board;
  const lines: string[] = [];

  // Column header: skip 'I' in Go convention
  const colLabels: string[] = [];
  for (let c = 0; c < size; c++) {
    colLabels.push(String.fromCharCode(c < 8 ? 65 + c : 66 + c));
  }
  const headerPad = size >= 10 ? '   ' : '  ';
  lines.push(headerPad + colLabels.join(' '));

  for (let r = 0; r < size; r++) {
    const rowNum = size - r;
    const rowPad = rowNum < 10 && size >= 10 ? ' ' : '';
    let line = `${rowPad}${rowNum} `;

    for (let c = 0; c < size; c++) {
      const idx = r * size + c;
      const stone = intersections[idx];

      if (stone) {
        line += stone.color === 'black' ? 'X' : 'O';
      } else if (isStarPoint(r, c, size)) {
        line += '*';
      } else {
        line += '+';
      }

      if (c < size - 1) line += ' ';
    }

    line += ` ${rowNum}`;
    lines.push(line);
  }

  lines.push(headerPad + colLabels.join(' '));

  // Capture info
  lines.push(`Captured: Black ${board.capturedBlack}, White ${board.capturedWhite}`);

  return lines.join('\n');
}

```
