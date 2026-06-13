---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.399416+00:00
---

# packages/games/src/chess/engine.ts

```ts
/**
 * SemanticChessEngine — full chess via semantic cells and compiled policies.
 *
 * Every piece is a LINEAR cell. The board is a RELEVANT cell.
 * Move legality is enforced by Lisp policies compiled to opcodes
 * and evaluated in the WASM cell engine via OP_CALLHOST.
 * Game history is a DAG of board cells linked by prevStateHash.
 */

import { createHash } from 'crypto';
import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType, type GameEntity } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import { registerChessHostFunctions, isInCheck, isSquareAttacked, findKing } from './host-functions';
import { compileChessPolicies, type CompiledPolicies } from './policies';
import {
  type ChessPiece,
  type ChessBoard,
  type Color,
  type PieceType,
  type GameStatus,
  type MoveResult,
  type CastlingRights,
  INITIAL_PIECES,
  INITIAL_CASTLING,
  squareFile,
  squareRank,
  squareToAlgebraic,
} from './types';

// ── Linearity Constants ──────────────────────────────────────────

const LINEAR = 1;
const RELEVANT = 3;

// ── Owner IDs (16-byte identifiers for white/black) ─────────────

const WHITE_OWNER = new Uint8Array(16);
WHITE_OWNER[0] = 0x01;
const BLACK_OWNER = new Uint8Array(16);
BLACK_OWNER[0] = 0x02;

function ownerForColor(c: Color): Uint8Array {
  return c === 'white' ? WHITE_OWNER : BLACK_OWNER;
}

// ── Board Slot (lightweight representation for host function context) ──

type BoardSlot = { pieceType: string; color: string } | null;

function boardToSlots(board: ChessBoard): BoardSlot[] {
  return board.squares.map(p =>
    p ? { pieceType: p.pieceType, color: p.color } : null,
  );
}

// ── SemanticChessEngine ──────────────────────────────────────────

export class SemanticChessEngine {
  private cellEngine: GameCellEngine;
  private registry: HostFunctionRegistry;
  private policies: CompiledPolicies;
  private currentBoard: ChessBoard;
  private boardHistory: string[]; // cell IDs of board states (DAG)
  private lastBoardCell: Uint8Array | null;
  private consumedCells: Set<string>; // cellIds of captured pieces

  private constructor(
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policies: CompiledPolicies,
    board: ChessBoard,
    boardCellBytes: Uint8Array,
  ) {
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.policies = policies;
    this.currentBoard = board;
    this.boardHistory = [board.cellId];
    this.consumedCells = new Set();
    this.lastBoardCell = boardCellBytes;
  }

  /** Initialize a new chess game with standard starting position. */
  static async create(opts?: CreateOptions): Promise<SemanticChessEngine> {
    // Use provided registry or create a new one, then register chess predicates
    const registry = (opts?.hostRegistry as HostFunctionRegistry) ?? new HostFunctionRegistry();
    registerChessHostFunctions(registry);

    // Create the cell engine with the registry wired in
    const engine = await GameCellEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    // Compile all chess policies
    const policies = compileChessPolicies();

    // Create 32 piece cells (LINEAR)
    const squares: (ChessPiece | null)[] = new Array(64).fill(null);

    for (const def of INITIAL_PIECES) {
      const entity = engine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: ownerForColor(def.color),
        linearity: LINEAR,
        metadata: {
          pieceType: def.pieceType,
          color: def.color,
          square: def.square,
          hasMoved: false,
          domain: 'chess',
        },
        state: 'active',
      });

      squares[def.square] = {
        entity,
        pieceType: def.pieceType,
        color: def.color,
        square: def.square,
        hasMoved: false,
      };
    }

    // Create board cell (RELEVANT — can be referenced multiple times for history)
    // Board cell payload is compact: domain + move metadata only.
    // The full piece layout is tracked in-memory; the cell provides DAG linkage.
    const boardEntity = engine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: WHITE_OWNER,
      linearity: RELEVANT,
      metadata: {
        d: 'chess',
        ac: 'w',
        hm: 0,
        fm: 1,
      },
      state: 'playing',
    });

    const board: ChessBoard = {
      cellId: boardEntity.id,
      squares,
      activeColor: 'white',
      castlingRights: { ...INITIAL_CASTLING },
      enPassantTarget: null,
      halfMoveClock: 0,
      fullMoveNumber: 1,
      previousBoardCellId: null,
    };

    return new SemanticChessEngine(engine, registry, policies, board, boardEntity.cell);
  }

  /** Get the current board state. */
  getBoard(): ChessBoard {
    return this.currentBoard;
  }

  /** Get the game status. */
  status(): GameStatus {
    const b = this.currentBoard;
    const active = b.activeColor;
    const slots = boardToSlots(b);
    const hasLegalMoves = this.hasAnyLegalMove(active, slots);
    const inCheck = isInCheck(active, slots);

    if (!hasLegalMoves && inCheck) return 'checkmate';
    if (!hasLegalMoves && !inCheck) return 'stalemate';
    if (inCheck) return 'check';

    // Draw conditions
    if (b.halfMoveClock >= 100) return 'draw'; // 50-move rule
    if (this.isThreefoldRepetition()) return 'draw';
    if (this.isInsufficientMaterial(slots)) return 'draw';

    return 'playing';
  }

  /** Get the cell DAG history (board cell IDs from oldest to newest). */
  history(): string[] {
    return [...this.boardHistory];
  }

  /** Get all legal moves for a piece at the given square. */
  legalMoves(square: number): number[] {
    const piece = this.currentBoard.squares[square];
    if (!piece || piece.color !== this.currentBoard.activeColor) return [];

    const legal: number[] = [];
    for (let to = 0; to < 64; to++) {
      if (to === square) continue;
      if (this.isPolicyLegal(piece, square, to) && this.isLegalAfterMove(square, to)) {
        legal.push(to);
      }
    }
    return legal;
  }

  /**
   * Execute a move. Validates via compiled Lisp policy, then executes.
   * Returns the new board state and captured piece (if any).
   */
  move(fromSq: number, toSq: number, promotion?: PieceType): MoveResult {
    const b = this.currentBoard;
    const piece = b.squares[fromSq];
    if (!piece) throw new Error(`No piece at square ${squareToAlgebraic(fromSq)}`);
    if (piece.color !== b.activeColor) throw new Error(`Not ${piece.color}'s turn`);

    // Validate via compiled Lisp policy (WASM execution)
    if (!this.isPolicyLegal(piece, fromSq, toSq)) {
      throw new Error(`Illegal move: ${squareToAlgebraic(fromSq)}${squareToAlgebraic(toSq)}`);
    }

    // Check if move leaves own king in check
    if (!this.isLegalAfterMove(fromSq, toSq)) {
      throw new Error(`Move leaves king in check: ${squareToAlgebraic(fromSq)}${squareToAlgebraic(toSq)}`);
    }

    // Execute the move
    return this.executeMove(piece, fromSq, toSq, promotion);
  }

  // ── Policy Evaluation (WASM) ──────────────────────────────────

  private isPolicyLegal(piece: ChessPiece, fromSq: number, toSq: number): boolean {
    const policy = this.policies[piece.pieceType];
    if (!policy) return false;

    const slots = boardToSlots(this.currentBoard);

    // Set the frozen evaluation context
    this.registry.setContext({
      from: fromSq,
      to: toSq,
      pieceType: piece.pieceType,
      color: piece.color,
      hasMoved: piece.hasMoved,
      board: slots,
      enPassantTarget: this.currentBoard.enPassantTarget,
      castlingRights: this.currentBoard.castlingRights,
    });

    // Evaluate via WASM
    const result = this.cellEngine.evaluatePolicy(policy.scriptBytes);
    this.registry.clearContext();
    return result;
  }

  /** Check that the move doesn't leave own king in check. */
  private isLegalAfterMove(fromSq: number, toSq: number): boolean {
    const b = this.currentBoard;
    const piece = b.squares[fromSq]!;
    const slots = boardToSlots(b);

    // Simulate the move on slots
    const simSlots = [...slots];
    simSlots[toSq] = simSlots[fromSq];
    simSlots[fromSq] = null;

    // Handle en passant capture
    if (piece.pieceType === 'pawn' && toSq === b.enPassantTarget) {
      const capturedPawnSq = piece.color === 'white'
        ? toSq + 8 // captured pawn is one rank below target
        : toSq - 8;
      simSlots[capturedPawnSq] = null;
    }

    // Handle castling — move the rook too
    if (piece.pieceType === 'king' && Math.abs(squareFile(fromSq) - squareFile(toSq)) === 2) {
      const kingSide = squareFile(toSq) > squareFile(fromSq);
      const rookFrom = kingSide
        ? (piece.color === 'white' ? 63 : 7)
        : (piece.color === 'white' ? 56 : 0);
      const rookTo = kingSide
        ? (piece.color === 'white' ? 61 : 5)
        : (piece.color === 'white' ? 59 : 3);
      simSlots[rookTo] = simSlots[rookFrom];
      simSlots[rookFrom] = null;
    }

    return !isInCheck(piece.color, simSlots);
  }

  private hasAnyLegalMove(color: Color, slots: BoardSlot[]): boolean {
    for (let sq = 0; sq < 64; sq++) {
      const piece = this.currentBoard.squares[sq];
      if (!piece || piece.color !== color) continue;
      for (let to = 0; to < 64; to++) {
        if (to === sq) continue;
        if (this.isPolicyLegal(piece, sq, to) && this.isLegalAfterMove(sq, to)) {
          return true;
        }
      }
    }
    return false;
  }

  // ── Move Execution ────────────────────────────────────────────

  private executeMove(piece: ChessPiece, fromSq: number, toSq: number, promotion?: PieceType): MoveResult {
    const b = this.currentBoard;
    let captured: ChessPiece | null = null;
    let promotionType: PieceType | null = null;

    // Detect castling
    const isCastling = piece.pieceType === 'king' && Math.abs(squareFile(fromSq) - squareFile(toSq)) === 2;
    // Detect en passant
    const isEnPassant = piece.pieceType === 'pawn' && toSq === b.enPassantTarget && b.squares[toSq] === null;
    // Detect promotion
    const isPromotion = piece.pieceType === 'pawn' && (squareRank(toSq) === 0 || squareRank(toSq) === 7);

    // Clone squares
    const newSquares: (ChessPiece | null)[] = [...b.squares];

    // Handle capture
    if (b.squares[toSq] !== null) {
      captured = b.squares[toSq];
      // Consume the captured piece cell (LINEAR destruction)
      this.consumedCells.add(captured!.entity.id);
    }

    // Handle en passant capture
    if (isEnPassant) {
      const capturedPawnSq = piece.color === 'white' ? toSq + 8 : toSq - 8;
      captured = b.squares[capturedPawnSq]!;
      this.consumedCells.add(captured.entity.id);
      newSquares[capturedPawnSq] = null;
    }

    // Move piece
    const updatedEntity = this.cellEngine.updateEntity(piece.entity, {
      metadata: {
        ...piece.entity.metadata,
        square: toSq,
        hasMoved: true,
      },
      state: 'active',
    });

    let movedPiece: ChessPiece = {
      entity: updatedEntity,
      pieceType: piece.pieceType,
      color: piece.color,
      square: toSq,
      hasMoved: true,
    };

    // Handle promotion
    if (isPromotion) {
      const promType = promotion ?? 'queen';
      promotionType = promType;
      // Consume the pawn cell
      this.consumedCells.add(updatedEntity.id);
      // Create new piece cell
      const newEntity = this.cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: ownerForColor(piece.color),
        linearity: LINEAR,
        metadata: {
          pieceType: promType,
          color: piece.color,
          square: toSq,
          hasMoved: true,
          domain: 'chess',
          promotedFrom: 'pawn',
        },
        state: 'active',
      });
      movedPiece = {
        entity: newEntity,
        pieceType: promType,
        color: piece.color,
        square: toSq,
        hasMoved: true,
      };
    }

    newSquares[fromSq] = null;
    newSquares[toSq] = movedPiece;

    // Handle castling — move the rook
    if (isCastling) {
      const kingSide = squareFile(toSq) > squareFile(fromSq);
      const rookFrom = kingSide
        ? (piece.color === 'white' ? 63 : 7)
        : (piece.color === 'white' ? 56 : 0);
      const rookTo = kingSide
        ? (piece.color === 'white' ? 61 : 5)
        : (piece.color === 'white' ? 59 : 3);
      const rook = newSquares[rookFrom]!;
      const updatedRook = this.cellEngine.updateEntity(rook.entity, {
        metadata: { ...rook.entity.metadata, square: rookTo, hasMoved: true },
        state: 'active',
      });
      newSquares[rookTo] = { ...rook, entity: updatedRook, square: rookTo, hasMoved: true };
      newSquares[rookFrom] = null;
    }

    // Update castling rights
    const newCastling = { ...b.castlingRights };
    if (piece.pieceType === 'king') {
      if (piece.color === 'white') {
        newCastling.whiteKingside = false;
        newCastling.whiteQueenside = false;
      } else {
        newCastling.blackKingside = false;
        newCastling.blackQueenside = false;
      }
    }
    if (piece.pieceType === 'rook') {
      if (fromSq === 63) newCastling.whiteKingside = false;
      if (fromSq === 56) newCastling.whiteQueenside = false;
      if (fromSq === 7) newCastling.blackKingside = false;
      if (fromSq === 0) newCastling.blackQueenside = false;
    }
    // If a rook is captured, remove that castling right
    if (captured?.pieceType === 'rook') {
      if (toSq === 63) newCastling.whiteKingside = false;
      if (toSq === 56) newCastling.whiteQueenside = false;
      if (toSq === 7) newCastling.blackKingside = false;
      if (toSq === 0) newCastling.blackQueenside = false;
    }

    // En passant target
    let newEnPassant: number | null = null;
    if (piece.pieceType === 'pawn' && Math.abs(squareRank(fromSq) - squareRank(toSq)) === 2) {
      newEnPassant = (fromSq + toSq) / 2; // square between
    }

    // Half-move clock
    const newHalfMove = (piece.pieceType === 'pawn' || captured !== null) ? 0 : b.halfMoveClock + 1;

    // Full move number
    const newFullMove = b.activeColor === 'black' ? b.fullMoveNumber + 1 : b.fullMoveNumber;

    // Create new board cell (DAG append) — compact metadata for payload size
    // prevCell links the binary header hash chain to the previous board cell
    const boardEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: WHITE_OWNER,
      linearity: RELEVANT,
      metadata: {
        d: 'chess',
        ac: b.activeColor === 'white' ? 'b' : 'w',
        hm: newHalfMove,
        fm: newFullMove,
        ep: newEnPassant,
        prev: b.cellId,
      },
      state: 'playing',
      prevCell: this.lastBoardCell ?? undefined,
    });

    const newBoard: ChessBoard = {
      cellId: boardEntity.id,
      squares: newSquares,
      activeColor: b.activeColor === 'white' ? 'black' : 'white',
      castlingRights: newCastling,
      enPassantTarget: newEnPassant,
      halfMoveClock: newHalfMove,
      fullMoveNumber: newFullMove,
      previousBoardCellId: b.cellId,
    };

    this.currentBoard = newBoard;
    this.lastBoardCell = boardEntity.cell;
    this.boardHistory.push(boardEntity.id);

    // Build notation
    const notation = `${squareToAlgebraic(fromSq)}${squareToAlgebraic(toSq)}`;

    const status = this.status();

    return {
      board: newBoard,
      captured,
      promotion: promotionType,
      status,
      notation,
    };
  }

  // ── Draw Detection ────────────────────────────────────────────

  private isThreefoldRepetition(): boolean {
    // Simple approach: compare board position hashes
    const posHash = this.positionHash(this.currentBoard);
    let count = 0;
    // We'd need to store position hashes for all board states
    // For now, use a simple approach: count is always < 3 unless
    // we track hashes (implemented below)
    if (!this._positionHashes) this._positionHashes = [];
    this._positionHashes.push(posHash);
    for (const h of this._positionHashes) {
      if (h === posHash) count++;
    }
    return count >= 3;
  }

  private _positionHashes?: string[];

  private positionHash(b: ChessBoard): string {
    const key = b.squares.map(p => p ? `${p.pieceType[0]}${p.color[0]}` : '--').join('')
      + b.activeColor[0]
      + (b.castlingRights.whiteKingside ? 'K' : '')
      + (b.castlingRights.whiteQueenside ? 'Q' : '')
      + (b.castlingRights.blackKingside ? 'k' : '')
      + (b.castlingRights.blackQueenside ? 'q' : '')
      + (b.enPassantTarget !== null ? String(b.enPassantTarget) : '-');
    return createHash('sha256').update(key).digest('hex').slice(0, 16);
  }

  private isInsufficientMaterial(slots: BoardSlot[]): boolean {
    const pieces = slots.filter(s => s !== null) as { pieceType: string; color: string }[];
    // King vs King
    if (pieces.length === 2) return true;
    // King + minor piece vs King
    if (pieces.length === 3) {
      const nonKings = pieces.filter(p => p.pieceType !== 'king');
      if (nonKings.length === 1 && (nonKings[0].pieceType === 'bishop' || nonKings[0].pieceType === 'knight')) {
        return true;
      }
    }
    return false;
  }

  /** Check if a cell has been consumed (captured). */
  isConsumed(cellId: string): boolean {
    return this.consumedCells.has(cellId);
  }

  /** Get the underlying GameCellEngine. */
  getCellEngine(): GameCellEngine {
    return this.cellEngine;
  }
}

```
