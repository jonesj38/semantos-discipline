---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.398299+00:00
---

# packages/games/src/chess/types.ts

```ts
/**
 * Chess types — semantic cell model for chess.
 *
 * Every piece is a LINEAR cell. The board is a RELEVANT cell
 * whose payload references 64 piece cells. Each move produces
 * a new board cell linked to the previous one (DAG).
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// ── Piece Types ──────────────────────────────────────────────────

export type PieceType = 'king' | 'queen' | 'rook' | 'bishop' | 'knight' | 'pawn';
export type Color = 'white' | 'black';

/** A chess piece backed by a LINEAR GameEntity cell. */
export interface ChessPiece {
  /** The underlying GameEntity (1024-byte cell) */
  entity: GameEntity;
  pieceType: PieceType;
  color: Color;
  /** Current square index 0-63 (a8=0, b8=1, ..., h1=63) */
  square: number;
  hasMoved: boolean;
}

// ── Board ────────────────────────────────────────────────────────

export interface CastlingRights {
  whiteKingside: boolean;
  whiteQueenside: boolean;
  blackKingside: boolean;
  blackQueenside: boolean;
}

/** The board is a semantic object (RELEVANT cell) containing 64 square refs. */
export interface ChessBoard {
  /** Board cell ID */
  cellId: string;
  /** 64 squares, a8=0 through h1=63 */
  squares: (ChessPiece | null)[];
  activeColor: Color;
  castlingRights: CastlingRights;
  /** Square index of en passant target, or null */
  enPassantTarget: number | null;
  halfMoveClock: number;
  fullMoveNumber: number;
  /** DAG link to previous board state cell */
  previousBoardCellId: string | null;
}

// ── Game Status ──────────────────────────────────────────────────

export type GameStatus = 'playing' | 'check' | 'checkmate' | 'stalemate' | 'draw';

export interface MoveResult {
  board: ChessBoard;
  captured: ChessPiece | null;
  promotion: PieceType | null;
  status: GameStatus;
  /** Algebraic notation of the move (e.g., "e2e4", "Qxf7#") */
  notation: string;
}

// ── Square Helpers ───────────────────────────────────────────────

/** Convert square index (0-63) to file (0-7, a-h). */
export function squareFile(sq: number): number {
  return sq % 8;
}

/** Convert square index (0-63) to rank (0-7, 8-1). */
export function squareRank(sq: number): number {
  return Math.floor(sq / 8);
}

/** Convert file and rank to square index. */
export function toSquare(file: number, rank: number): number {
  return rank * 8 + file;
}

/** Convert algebraic notation (e.g., "e2") to square index. */
export function algebraicToSquare(algebraic: string): number {
  const file = algebraic.charCodeAt(0) - 97; // 'a' = 0
  const rank = 8 - parseInt(algebraic[1], 10); // '8' = 0, '1' = 7
  return toSquare(file, rank);
}

/** Convert square index to algebraic notation. */
export function squareToAlgebraic(sq: number): string {
  const file = String.fromCharCode(97 + squareFile(sq));
  const rank = String(8 - squareRank(sq));
  return file + rank;
}

// ── Initial Position ─────────────────────────────────────────────

export const INITIAL_CASTLING: CastlingRights = {
  whiteKingside: true,
  whiteQueenside: true,
  blackKingside: true,
  blackQueenside: true,
};

/** Standard starting position piece layout. */
export const INITIAL_PIECES: Array<{ pieceType: PieceType; color: Color; square: number }> = [
  // Black back rank (rank 8, squares 0-7)
  { pieceType: 'rook', color: 'black', square: 0 },
  { pieceType: 'knight', color: 'black', square: 1 },
  { pieceType: 'bishop', color: 'black', square: 2 },
  { pieceType: 'queen', color: 'black', square: 3 },
  { pieceType: 'king', color: 'black', square: 4 },
  { pieceType: 'bishop', color: 'black', square: 5 },
  { pieceType: 'knight', color: 'black', square: 6 },
  { pieceType: 'rook', color: 'black', square: 7 },
  // Black pawns (rank 7, squares 8-15)
  ...Array.from({ length: 8 }, (_, i) => ({
    pieceType: 'pawn' as PieceType,
    color: 'black' as Color,
    square: 8 + i,
  })),
  // White pawns (rank 2, squares 48-55)
  ...Array.from({ length: 8 }, (_, i) => ({
    pieceType: 'pawn' as PieceType,
    color: 'white' as Color,
    square: 48 + i,
  })),
  // White back rank (rank 1, squares 56-63)
  { pieceType: 'rook', color: 'white', square: 56 },
  { pieceType: 'knight', color: 'white', square: 57 },
  { pieceType: 'bishop', color: 'white', square: 58 },
  { pieceType: 'queen', color: 'white', square: 59 },
  { pieceType: 'king', color: 'white', square: 60 },
  { pieceType: 'bishop', color: 'white', square: 61 },
  { pieceType: 'knight', color: 'white', square: 62 },
  { pieceType: 'rook', color: 'white', square: 63 },
];

```
