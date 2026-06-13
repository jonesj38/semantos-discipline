---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.398853+00:00
---

# packages/games/src/chess/host-functions.ts

```ts
/**
 * Chess host functions — registered with HostFunctionRegistry.
 *
 * Every predicate is zero-arity: it reads from the frozen evaluation context
 * set via registry.setContext() before WASM policy evaluation.
 *
 * Context shape:
 * {
 *   from: number,          // source square (0-63)
 *   to: number,            // target square (0-63)
 *   pieceType: string,     // "pawn"|"knight"|"bishop"|"rook"|"queen"|"king"
 *   color: string,         // "white"|"black"
 *   hasMoved: boolean,     // whether the piece has moved before
 *   board: (object|null)[], // 64-element array of {pieceType, color}|null
 *   enPassantTarget: number|null,
 *   castlingRights: { whiteKingside, whiteQueenside, blackKingside, blackQueenside },
 * }
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';

// ── Context Accessors ────────────────────────────────────────────

type Ctx = HostFunctionContext;
type BoardSlot = { pieceType: string; color: string } | null;

function from(ctx: Ctx): number { return ctx.from as number; }
function to(ctx: Ctx): number { return ctx.to as number; }
function color(ctx: Ctx): string { return ctx.color as string; }
function board(ctx: Ctx): BoardSlot[] { return ctx.board as BoardSlot[]; }

// ── Square Math ──────────────────────────────────────────────────

function file(sq: number): number { return sq % 8; }
function rank(sq: number): number { return Math.floor(sq / 8); }

// ── Geometry Helpers ─────────────────────────────────────────────

function isDiagonal(f: number, t: number): boolean {
  const df = Math.abs(file(f) - file(t));
  const dr = Math.abs(rank(f) - rank(t));
  return df === dr && df > 0;
}

function isOrthogonal(f: number, t: number): boolean {
  return (file(f) === file(t) || rank(f) === rank(t)) && f !== t;
}

function isLShape(f: number, t: number): boolean {
  const df = Math.abs(file(f) - file(t));
  const dr = Math.abs(rank(f) - rank(t));
  return (df === 1 && dr === 2) || (df === 2 && dr === 1);
}

function isOneSquare(f: number, t: number): boolean {
  const df = Math.abs(file(f) - file(t));
  const dr = Math.abs(rank(f) - rank(t));
  return df <= 1 && dr <= 1 && (df + dr) > 0;
}

/** Get squares between two squares on a straight/diagonal line (exclusive). */
function squaresBetween(f: number, t: number): number[] {
  const df = file(t) - file(f);
  const dr = rank(t) - rank(f);
  const steps = Math.max(Math.abs(df), Math.abs(dr));
  if (steps <= 1) return [];
  const stepF = df === 0 ? 0 : df / Math.abs(df);
  const stepR = dr === 0 ? 0 : dr / Math.abs(dr);
  const between: number[] = [];
  for (let i = 1; i < steps; i++) {
    between.push((rank(f) + stepR * i) * 8 + (file(f) + stepF * i));
  }
  return between;
}

function isPathClear(f: number, t: number, b: BoardSlot[]): boolean {
  return squaresBetween(f, t).every(sq => b[sq] === null);
}

// ── Pawn Helpers ─────────────────────────────────────────────────

/** Direction of pawn movement: white moves up (rank decreases), black down. */
function pawnDir(c: string): number { return c === 'white' ? -1 : 1; }

function isForwardOne(f: number, t: number, c: string): boolean {
  return file(f) === file(t) && rank(t) === rank(f) + pawnDir(c);
}

function isForwardTwo(f: number, t: number, c: string): boolean {
  return file(f) === file(t) && rank(t) === rank(f) + 2 * pawnDir(c);
}

function isDiagonalOneForward(f: number, t: number, c: string): boolean {
  return Math.abs(file(f) - file(t)) === 1 && rank(t) === rank(f) + pawnDir(c);
}

function isOnStartRank(sq: number, c: string): boolean {
  return c === 'white' ? rank(sq) === 6 : rank(sq) === 1;
}

// ── Castling Helpers ─────────────────────────────────────────────

function kingsideCastleTarget(c: string): number {
  return c === 'white' ? 62 : 6; // g1 or g8
}

function queensideCastleTarget(c: string): number {
  return c === 'white' ? 58 : 2; // c1 or c8
}

function kingsideRookSquare(c: string): number {
  return c === 'white' ? 63 : 7; // h1 or h8
}

function queensideRookSquare(c: string): number {
  return c === 'white' ? 56 : 0; // a1 or a8
}

function castlePathSquares(side: 'kingside' | 'queenside', c: string): number[] {
  if (c === 'white') {
    return side === 'kingside' ? [61, 62] : [57, 58, 59];
  }
  return side === 'kingside' ? [5, 6] : [1, 2, 3];
}

/** Check if a square is attacked by the opponent. */
export function isSquareAttacked(sq: number, byColor: string, b: BoardSlot[]): boolean {
  for (let i = 0; i < 64; i++) {
    const piece = b[i];
    if (!piece || piece.color !== byColor) continue;
    if (canAttack(piece.pieceType, i, sq, byColor, b)) return true;
  }
  return false;
}

/** Can a piece of given type on `from` attack `target`? */
function canAttack(type: string, f: number, target: number, c: string, b: BoardSlot[]): boolean {
  switch (type) {
    case 'pawn':
      return isDiagonalOneForward(f, target, c);
    case 'knight':
      return isLShape(f, target);
    case 'bishop':
      return isDiagonal(f, target) && isPathClear(f, target, b);
    case 'rook':
      return isOrthogonal(f, target) && isPathClear(f, target, b);
    case 'queen':
      return (isDiagonal(f, target) || isOrthogonal(f, target)) && isPathClear(f, target, b);
    case 'king':
      return isOneSquare(f, target);
    default:
      return false;
  }
}

/** Find the king square for a given color. */
export function findKing(c: string, b: BoardSlot[]): number {
  for (let i = 0; i < 64; i++) {
    if (b[i]?.pieceType === 'king' && b[i]?.color === c) return i;
  }
  return -1;
}

/** Is the given color's king currently in check? */
export function isInCheck(c: string, b: BoardSlot[]): boolean {
  const kingSq = findKing(c, b);
  if (kingSq === -1) return false;
  const opponent = c === 'white' ? 'black' : 'white';
  return isSquareAttacked(kingSq, opponent, b);
}

// ── Registration ─────────────────────────────────────────────────

export function registerChessHostFunctions(registry: HostFunctionRegistry): void {
  // Piece type checks
  registry.register('is-pawn?', (ctx) => ctx.pieceType === 'pawn' ? 1 : 0);
  registry.register('is-knight?', (ctx) => ctx.pieceType === 'knight' ? 1 : 0);
  registry.register('is-bishop?', (ctx) => ctx.pieceType === 'bishop' ? 1 : 0);
  registry.register('is-rook?', (ctx) => ctx.pieceType === 'rook' ? 1 : 0);
  registry.register('is-queen?', (ctx) => ctx.pieceType === 'queen' ? 1 : 0);
  registry.register('is-king?', (ctx) => ctx.pieceType === 'king' ? 1 : 0);

  // Geometry predicates
  registry.register('diagonal-path?', (ctx) => isDiagonal(from(ctx), to(ctx)) ? 1 : 0);
  registry.register('orthogonal-path?', (ctx) => isOrthogonal(from(ctx), to(ctx)) ? 1 : 0);
  registry.register('l-shape?', (ctx) => isLShape(from(ctx), to(ctx)) ? 1 : 0);
  registry.register('one-square-any-direction?', (ctx) => isOneSquare(from(ctx), to(ctx)) ? 1 : 0);

  // Pawn predicates
  registry.register('forward-one?', (ctx) => isForwardOne(from(ctx), to(ctx), color(ctx)) ? 1 : 0);
  registry.register('forward-two?', (ctx) => isForwardTwo(from(ctx), to(ctx), color(ctx)) ? 1 : 0);
  registry.register('diagonal-one-forward?', (ctx) => isDiagonalOneForward(from(ctx), to(ctx), color(ctx)) ? 1 : 0);
  registry.register('on-start-rank?', (ctx) => isOnStartRank(from(ctx), color(ctx)) ? 1 : 0);

  // Board queries
  registry.register('square-empty?', (ctx) => board(ctx)[to(ctx)] === null ? 1 : 0);
  registry.register('path-clear?', (ctx) => isPathClear(from(ctx), to(ctx), board(ctx)) ? 1 : 0);
  registry.register('has-enemy-piece?', (ctx) => {
    const target = board(ctx)[to(ctx)];
    return target !== null && target.color !== color(ctx) ? 1 : 0;
  });
  registry.register('target-not-friendly?', (ctx) => {
    const target = board(ctx)[to(ctx)];
    return target === null || target.color !== color(ctx) ? 1 : 0;
  });

  // Check/safety predicates
  registry.register('not-in-check?', (ctx) => !isInCheck(color(ctx), board(ctx)) ? 1 : 0);
  registry.register('no-check-through-path?', (ctx) => {
    const c = color(ctx);
    const opponent = c === 'white' ? 'black' : 'white';
    const f = from(ctx);
    const t = to(ctx);
    // Check that king doesn't pass through check during castling
    const between = squaresBetween(f, t);
    return between.every(sq => !isSquareAttacked(sq, opponent, board(ctx))) ? 1 : 0;
  });

  // Piece state
  registry.register('moved?', (ctx) => (ctx.hasMoved as boolean) ? 1 : 0);

  // En passant
  registry.register('en-passant-target?', (ctx) =>
    ctx.enPassantTarget !== null && to(ctx) === (ctx.enPassantTarget as number) ? 1 : 0);

  // Castling predicates
  registry.register('kingside-castle-target?', (ctx) =>
    to(ctx) === kingsideCastleTarget(color(ctx)) ? 1 : 0);
  registry.register('queenside-castle-target?', (ctx) =>
    to(ctx) === queensideCastleTarget(color(ctx)) ? 1 : 0);

  registry.register('kingside-rook-unmoved?', (ctx) => {
    const rookSq = kingsideRookSquare(color(ctx));
    const piece = board(ctx)[rookSq];
    return piece?.pieceType === 'rook' && piece?.color === color(ctx) ? 1 : 0;
  });
  registry.register('queenside-rook-unmoved?', (ctx) => {
    const rookSq = queensideRookSquare(color(ctx));
    const piece = board(ctx)[rookSq];
    return piece?.pieceType === 'rook' && piece?.color === color(ctx) ? 1 : 0;
  });

  registry.register('kingside-path-clear?', (ctx) => {
    const squares = castlePathSquares('kingside', color(ctx));
    return squares.every(sq => board(ctx)[sq] === null) ? 1 : 0;
  });
  registry.register('queenside-path-clear?', (ctx) => {
    const squares = castlePathSquares('queenside', color(ctx));
    return squares.every(sq => board(ctx)[sq] === null) ? 1 : 0;
  });
}

```
