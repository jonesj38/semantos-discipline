---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/chess/fen.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.428442+00:00
---

# cartridges/chess/web/src/chess/fen.ts

```ts
/**
 * FEN board parser — display-only.
 *
 * Move legality is enforced server-side by `chess_engine.zig`; this
 * module just unpacks a FEN string into an 8×8 piece grid + side-to-
 * move so the Svelte board can render. Click-to-move builds UCI strings
 * which the brain validates.
 */

/** Piece glyph: lowercase = black, uppercase = white. Empty square = ''. */
export type Piece = '' | 'P' | 'N' | 'B' | 'R' | 'Q' | 'K' | 'p' | 'n' | 'b' | 'r' | 'q' | 'k';

export interface BoardState {
  /** 8 ranks, each 8 files, board[0] = rank 8 (top from white's POV). */
  readonly board: readonly (readonly Piece[])[];
  readonly sideToMove: 'w' | 'b';
  readonly castling: string;
  readonly enPassant: string;
  readonly halfmove: number;
  readonly fullmove: number;
}

export function parseFen(fen: string): BoardState {
  const parts = fen.trim().split(/\s+/);
  if (parts.length < 4) throw new Error(`bad fen: ${fen}`);
  const [piecePlacement, side, castling, enPassant, halfStr, fullStr] = parts;
  const ranks = piecePlacement.split('/');
  if (ranks.length !== 8) throw new Error(`bad fen ranks: ${piecePlacement}`);

  const board: Piece[][] = [];
  for (const rank of ranks) {
    const row: Piece[] = [];
    for (const ch of rank) {
      if (/[1-8]/.test(ch)) {
        const n = parseInt(ch, 10);
        for (let i = 0; i < n; i++) row.push('');
      } else if (/[pnbrqkPNBRQK]/.test(ch)) {
        row.push(ch as Piece);
      } else {
        throw new Error(`bad fen char: ${ch}`);
      }
    }
    if (row.length !== 8) throw new Error(`bad fen rank length: ${rank}`);
    board.push(row);
  }

  return {
    board,
    sideToMove: side === 'b' ? 'b' : 'w',
    castling,
    enPassant,
    halfmove: parseInt(halfStr ?? '0', 10) || 0,
    fullmove: parseInt(fullStr ?? '1', 10) || 1,
  };
}

/**
 * Square index in BoardState.board: rank 0..7 (top → bottom, white POV),
 * file 0..7 (a..h). Returns UCI coordinate like "e4".
 */
export function squareToUci(rank: number, file: number): string {
  return String.fromCharCode(97 + file) + (8 - rank);
}

export function uciToSquare(uci: string): { rank: number; file: number } {
  const file = uci.charCodeAt(0) - 97;
  const rank = 8 - parseInt(uci[1]!, 10);
  return { rank, file };
}

```
