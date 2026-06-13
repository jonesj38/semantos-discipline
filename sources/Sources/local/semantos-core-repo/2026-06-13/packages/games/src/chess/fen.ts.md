---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/fen.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.398010+00:00
---

# packages/games/src/chess/fen.ts

```ts
/**
 * FEN import/export — read-only views derived from board cell state.
 *
 * FEN is NOT the source of truth. The board cell and its piece cell
 * references are authoritative. FEN is a derived export format.
 */

import type { ChessBoard, ChessPiece, PieceType, Color, CastlingRights } from './types';
import { squareFile, squareRank, toSquare } from './types';

const PIECE_TO_FEN: Record<string, string> = {
  'king-white': 'K', 'queen-white': 'Q', 'rook-white': 'R',
  'bishop-white': 'B', 'knight-white': 'N', 'pawn-white': 'P',
  'king-black': 'k', 'queen-black': 'q', 'rook-black': 'r',
  'bishop-black': 'b', 'knight-black': 'n', 'pawn-black': 'p',
};

const FEN_TO_PIECE: Record<string, { pieceType: PieceType; color: Color }> = {
  K: { pieceType: 'king', color: 'white' },
  Q: { pieceType: 'queen', color: 'white' },
  R: { pieceType: 'rook', color: 'white' },
  B: { pieceType: 'bishop', color: 'white' },
  N: { pieceType: 'knight', color: 'white' },
  P: { pieceType: 'pawn', color: 'white' },
  k: { pieceType: 'king', color: 'black' },
  q: { pieceType: 'queen', color: 'black' },
  r: { pieceType: 'rook', color: 'black' },
  b: { pieceType: 'bishop', color: 'black' },
  n: { pieceType: 'knight', color: 'black' },
  p: { pieceType: 'pawn', color: 'black' },
};

/** Export a ChessBoard to FEN string. */
export function toFEN(board: ChessBoard): string {
  // Piece placement
  const ranks: string[] = [];
  for (let r = 0; r < 8; r++) {
    let rankStr = '';
    let empty = 0;
    for (let f = 0; f < 8; f++) {
      const sq = toSquare(f, r);
      const piece = board.squares[sq];
      if (piece) {
        if (empty > 0) { rankStr += String(empty); empty = 0; }
        rankStr += PIECE_TO_FEN[`${piece.pieceType}-${piece.color}`] ?? '?';
      } else {
        empty++;
      }
    }
    if (empty > 0) rankStr += String(empty);
    ranks.push(rankStr);
  }

  // Active color
  const active = board.activeColor === 'white' ? 'w' : 'b';

  // Castling
  let castling = '';
  if (board.castlingRights.whiteKingside) castling += 'K';
  if (board.castlingRights.whiteQueenside) castling += 'Q';
  if (board.castlingRights.blackKingside) castling += 'k';
  if (board.castlingRights.blackQueenside) castling += 'q';
  if (castling === '') castling = '-';

  // En passant
  let enPassant = '-';
  if (board.enPassantTarget !== null) {
    const f = squareFile(board.enPassantTarget);
    const r = squareRank(board.enPassantTarget);
    enPassant = String.fromCharCode(97 + f) + String(8 - r);
  }

  return `${ranks.join('/')} ${active} ${castling} ${enPassant} ${board.halfMoveClock} ${board.fullMoveNumber}`;
}

/** Parse a FEN string into board state fields (does NOT create cells — use engine.fromFEN for that). */
export function parseFEN(fen: string): {
  pieces: Array<{ pieceType: PieceType; color: Color; square: number }>;
  activeColor: Color;
  castlingRights: CastlingRights;
  enPassantTarget: number | null;
  halfMoveClock: number;
  fullMoveNumber: number;
} {
  const parts = fen.split(' ');
  const placement = parts[0];
  const activeColor: Color = parts[1] === 'b' ? 'black' : 'white';
  const castlingStr = parts[2] ?? '-';
  const enPassantStr = parts[3] ?? '-';
  const halfMoveClock = parseInt(parts[4] ?? '0', 10);
  const fullMoveNumber = parseInt(parts[5] ?? '1', 10);

  const pieces: Array<{ pieceType: PieceType; color: Color; square: number }> = [];
  const ranks = placement.split('/');
  for (let r = 0; r < 8; r++) {
    let f = 0;
    for (const ch of ranks[r]) {
      if (ch >= '1' && ch <= '8') {
        f += parseInt(ch, 10);
      } else if (FEN_TO_PIECE[ch]) {
        pieces.push({ ...FEN_TO_PIECE[ch], square: toSquare(f, r) });
        f++;
      }
    }
  }

  const castlingRights: CastlingRights = {
    whiteKingside: castlingStr.includes('K'),
    whiteQueenside: castlingStr.includes('Q'),
    blackKingside: castlingStr.includes('k'),
    blackQueenside: castlingStr.includes('q'),
  };

  let enPassantTarget: number | null = null;
  if (enPassantStr !== '-') {
    const ef = enPassantStr.charCodeAt(0) - 97;
    const er = 8 - parseInt(enPassantStr[1], 10);
    enPassantTarget = toSquare(ef, er);
  }

  return { pieces, activeColor, castlingRights, enPassantTarget, halfMoveClock, fullMoveNumber };
}

```
