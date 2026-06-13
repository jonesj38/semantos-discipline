---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.399141+00:00
---

# packages/games/src/chess/renderer.ts

```ts
/**
 * ASCII chess board renderer.
 */

import type { ChessBoard } from './types';
import { toSquare } from './types';

const PIECE_CHARS: Record<string, Record<string, string>> = {
  white: { king: 'K', queen: 'Q', rook: 'R', bishop: 'B', knight: 'N', pawn: 'P' },
  black: { king: 'k', queen: 'q', rook: 'r', bishop: 'b', knight: 'n', pawn: 'p' },
};

/** Render a chess board as an ASCII string. */
export function renderBoard(board: ChessBoard): string {
  const lines: string[] = [];
  lines.push('  a b c d e f g h');
  for (let r = 0; r < 8; r++) {
    const rankNum = 8 - r;
    let line = `${rankNum} `;
    for (let f = 0; f < 8; f++) {
      const sq = toSquare(f, r);
      const piece = board.squares[sq];
      if (piece) {
        line += PIECE_CHARS[piece.color][piece.pieceType] ?? '?';
      } else {
        line += '.';
      }
      if (f < 7) line += ' ';
    }
    line += ` ${rankNum}`;
    lines.push(line);
  }
  lines.push('  a b c d e f g h');
  return lines.join('\n');
}

```
