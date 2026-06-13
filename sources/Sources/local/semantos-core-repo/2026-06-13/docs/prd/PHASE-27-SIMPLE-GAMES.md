---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-27-SIMPLE-GAMES.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.714963+00:00
---

# Phase 27 — Simple Games (Chess, Go, Card Games)

**Version**: 1.0
**Date**: March 2026
**Status**: Exploratory — depends on Phase 26 (Game Engine SDK)
**Duration**: 4 weeks (with 40% buffer: 5.6 weeks)
**Prerequisites**: Phase 26 complete (GameCellEngine, entity types, inventory, trade). Phase 25.5 complete (OP_CALLHOST + HostFunctionRegistry for game-domain predicates). Phase 21 complete (Lisp policy compiler for rule authoring).
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` + `COMMERCIAL-CONTEXT.md`
**Branch**: `phase-27-simple-games`

---

## Context

Phase 26 built the SDK. This phase proves it works by implementing games that exercise every primitive. Chess is the primary target because its rules map cleanly to cell engine semantics:

- **Pieces are LINEAR cells.** A rook is a single cell. It cannot be duplicated. It exists in exactly one square.
- **Capture is consumption.** Taking a piece executes the `consume` opcode on the captured cell. The cell is destroyed — linearity enforced, not checked.
- **The board is a semantic object.** 64 squares, each an optional cell reference. Board state is a cell whose payload contains 64 cell pointers (Phase 6 octave addressing).
- **Move legality is a policy.** "A bishop moves diagonally" is a Lisp constraint that compiles to opcodes. The cell engine evaluates it before the move executes.
- **Game state is a DAG.** Each move produces a new board cell that references the previous one. The game history is an immutable chain of cells — the same structure Semantos uses for audit trails.

Chess is not the point. The point is that chess forces you to use: entity creation (pieces), linearity enforcement (no duplication), state transitions (moves), policy evaluation (legal move checking), consumption (captures), and DAG persistence (game history). If the SDK handles chess, it handles any turn-based game.

Secondary games (Go, a simple card game) are included to verify that the SDK generalizes beyond chess-like piece models.

### The Compression Gradient (Chess Domain)

```
Game designer: "bishops move diagonally, any number of squares, can't jump pieces"
    ↓ (policy authoring)
(define-policy bishop-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "bishop")
    (diagonal-path?)
    (path-clear?))
  :linearity LINEAR)
    ↓ (Lisp compiler)
"bishop" "piece-type" OP_LOADFIELD OP_EQUAL "diagonal-path?" OP_CALLHOST BOOLAND "path-clear?" OP_CALLHOST BOOLAND VERIFY
    ↓ (cell engine)
2-PDA evaluates → move is legal or rejected at opcode level
```

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `SDK:TYPES` | `packages/game-sdk/src/types.ts` | GameEntity, Inventory, TradeProposal, EntityState |
| `SDK:ENGINE` | `packages/game-sdk/src/engine.ts` | GameCellEngine — the runtime wrapper |
| `SDK:POLICIES` | `packages/game-sdk/src/policies/` | Policy templates and compilation |
| `LISP:COMPILER` | `packages/shell/src/lisp/compiler.ts` | LispCompiler — constraint compilation |
| `CELL:OPCODES` | `packages/cell-engine/src/opcodes.ts` | Opcode table — what the 2-PDA can execute |
| `OCTAVE:POINTER` | `packages/cell-engine/src/octave.ts` | Pointer cells — how board references pieces |
| `TRANSFER:CORE` | `src/kernel/transfer.ts` | Transfer protocol — how pieces change ownership |
| `HOST:REGISTRY` | `packages/cell-engine/bindings/host-functions.ts` | HostFunctionRegistry class — register chess/Go predicates |
| `HOST:BUILTIN` | `packages/cell-engine/bindings/builtin-host-functions.ts` | Built-in host functions — pattern for registering domain predicates |
| `HOST:CALLZIG` | `packages/cell-engine/src/opcodes/hostcall.zig` | OP_CALLHOST Zig implementation |

---

## Deliverables

### D27.1 — Chess Engine (Semantic)

**File**: `packages/games/src/chess/`

A complete chess implementation where every piece is a cell and every rule is a compiled policy:

```typescript
/** Board is a semantic object containing 64 cell references */
interface ChessBoard {
  cellId: string;                          // board cell address
  squares: (ChessPiece | null)[];          // 64 slots, a8=0 → h1=63
  activeColor: 'white' | 'black';
  castlingRights: CastlingRights;
  enPassantTarget: number | null;          // square index or null
  halfMoveClock: number;
  fullMoveNumber: number;
  previousBoardCell?: string;              // DAG link to prior state
}

/** Each piece is a LINEAR cell */
interface ChessPiece extends GameEntity {
  entityType: 'king' | 'queen' | 'rook' | 'bishop' | 'knight' | 'pawn';
  color: 'white' | 'black';
  square: number;                          // current position (0-63)
  hasMoved: boolean;                       // for castling/pawn double-move
}

class SemanticChessEngine {
  private engine: GameCellEngine;
  private board: ChessBoard;
  private moveHistory: string[];           // cell IDs of board states (DAG)

  /** Initialize standard chess position — creates 32 piece cells */
  static async create(): Promise<SemanticChessEngine>;

  /** Attempt a move — validates via compiled policy, returns new board state */
  move(from: number, to: number, promotion?: PieceType): Result<MoveResult, MoveError>;

  /** Get legal moves for a piece — evaluates policies for all target squares */
  legalMoves(square: number): number[];

  /** Export board to FEN string */
  toFEN(): string;

  /** Import board from FEN string — creates cells for each piece */
  static fromFEN(fen: string): Promise<SemanticChessEngine>;

  /** Get game history as cell DAG */
  history(): string[];

  /** Check game status */
  status(): 'playing' | 'check' | 'checkmate' | 'stalemate' | 'draw';
}
```

**Move execution flow**:
1. Parse algebraic notation or (from, to) coordinates
2. Load the piece cell from the source square
3. Evaluate the move policy (compiled Lisp → opcodes → 2-PDA)
4. If capture: execute `consume` opcode on target piece cell (LINEAR destruction)
5. Update piece cell's square field (state transition)
6. Create new board cell referencing previous board cell (DAG append)
7. Return MoveResult with new board state

**Critical constraints**:
- Every piece is a distinct cell with a unique cellId. No two pieces share a cell.
- Capture DESTROYS the captured piece's cell via the consume opcode. It is not "removed from a list."
- Castling is an atomic two-cell transition (king + rook move simultaneously).
- En passant capture destroys a piece on a different square than the destination — the policy must reference both squares.
- Promotion destroys the pawn cell and creates a new piece cell (consume + create, atomic).
- The board cell's `previousBoardCell` link creates an append-only game history DAG.

---

### D27.2 — Chess Move Policies (Lisp)

**File**: `packages/games/src/chess/policies/`

Move legality as compiled Lisp constraints. One policy per piece type:

```lisp
;; ============================================================
;; EVALUATION CONTEXT (set once before each policy evaluation):
;; {
;;   from: <source-square-index>,      ;; 0-63
;;   to: <target-square-index>,        ;; 0-63
;;   board: <board-state-object>,      ;; 64-element array of piece|null
;;   color: "white" | "black",         ;; active player
;;   piece-type: "pawn"|"knight"|...,  ;; type of piece being moved
;;   en-passant-target: <index>|null,  ;; en passant square if applicable
;;   castling-rights: <object>,        ;; king/rook moved flags
;;   has-moved: <boolean>,             ;; whether the piece has moved before
;; }
;; All predicates below are ZERO-ARITY — they read from this context.
;; ============================================================

;; Pawn move — forward one (or two from start), diagonal capture only
(define-policy pawn-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "pawn")
    (or
      ;; Forward one square (no capture)
      (and (forward-one?)
           (square-empty?))
      ;; Forward two from starting rank (no capture)
      (and (on-start-rank?)
           (forward-two?)
           (square-empty?)
           (path-clear?))
      ;; Diagonal capture (must capture enemy piece)
      (and (diagonal-one-forward?)
           (has-enemy-piece?))
      ;; En passant
      (and (diagonal-one-forward?)
           (en-passant-target?))))
  :linearity LINEAR)

;; Knight move — L-shape, can jump
(define-policy knight-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "knight")
    (l-shape?))
  :linearity LINEAR)

;; Bishop move — diagonal, can't jump
(define-policy bishop-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "bishop")
    (diagonal-path?)
    (path-clear?))
  :linearity LINEAR)

;; Rook move — orthogonal, can't jump
(define-policy rook-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "rook")
    (orthogonal-path?)
    (path-clear?))
  :linearity LINEAR)

;; Queen move — diagonal or orthogonal, can't jump
(define-policy queen-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "queen")
    (or (diagonal-path?)
        (orthogonal-path?))
    (path-clear?))
  :linearity LINEAR)

;; King move — one square any direction (castling handled separately)
(define-policy king-move
  :subject player
  :action move
  :constraint (and
    (= piece-type "king")
    (or
      (one-square-any-direction?)
      ;; Kingside castling
      (and (not (moved?))
           (kingside-castle-target?)
           (kingside-rook-unmoved?)
           (kingside-path-clear?)
           (not-in-check?)
           (no-check-through-path?))
      ;; Queenside castling
      (and (not (moved?))
           (queenside-castle-target?)
           (queenside-rook-unmoved?)
           (queenside-path-clear?)
           (not-in-check?)
           (no-check-through-path?))))
  :linearity LINEAR)
```

- Each policy compiles to an opcode sequence via the Phase 21 Lisp compiler
- All predicates (`square-empty?`, `path-clear?`, `diagonal-path?`, `l-shape?`, etc.) are zero-arity host functions registered via `HostFunctionRegistry`
- Predicates read from the frozen evaluation context (set via `registry.setContext()` before evaluation) and return 0/1

**File**: `packages/games/src/chess/host-functions.ts` (new)

Register each chess predicate with the `HostFunctionRegistry`. Every function reads from the frozen evaluation context set before policy evaluation. Every function returns 0 (false) or 1 (true).

```typescript
import { HostFunctionRegistry } from '@semantos/cell-engine/bindings/host-function-registry';

export function registerChessHostFunctions(registry: HostFunctionRegistry): void {
  // Geometry predicates
  registry.register('diagonal-path?', (ctx) =>
    isDiagonal(ctx.from as number, ctx.to as number) ? 1 : 0);
  registry.register('orthogonal-path?', (ctx) =>
    isOrthogonal(ctx.from as number, ctx.to as number) ? 1 : 0);
  registry.register('l-shape?', (ctx) =>
    isLShape(ctx.from as number, ctx.to as number) ? 1 : 0);
  registry.register('one-square-any-direction?', (ctx) =>
    isOneSquare(ctx.from as number, ctx.to as number) ? 1 : 0);

  // Pawn predicates
  registry.register('forward-one?', (ctx) =>
    isForwardOne(ctx.from as number, ctx.to as number, ctx.color as string) ? 1 : 0);
  registry.register('forward-two?', (ctx) =>
    isForwardTwo(ctx.from as number, ctx.to as number, ctx.color as string) ? 1 : 0);
  registry.register('diagonal-one-forward?', (ctx) =>
    isDiagonalOneForward(ctx.from as number, ctx.to as number, ctx.color as string) ? 1 : 0);
  registry.register('on-start-rank?', (ctx) =>
    isOnStartRank(ctx.from as number, ctx.color as string) ? 1 : 0);

  // Board-query predicates
  registry.register('square-empty?', (ctx) =>
    isSquareEmpty(ctx.to as number, ctx.board as Board) ? 1 : 0);
  registry.register('path-clear?', (ctx) =>
    isPathClear(ctx.from as number, ctx.to as number, ctx.board as Board) ? 1 : 0);
  registry.register('has-enemy-piece?', (ctx) =>
    hasEnemyPiece(ctx.to as number, ctx.board as Board, ctx.color as string) ? 1 : 0);

  // Check/safety predicates
  registry.register('not-in-check?', (ctx) =>
    !isInCheck(ctx.color as string, ctx.board as Board) ? 1 : 0);
  registry.register('no-check-through-path?', (ctx) =>
    !checksThrough(ctx.from as number, ctx.to as number, ctx.color as string, ctx.board as Board) ? 1 : 0);

  // Castling predicates
  registry.register('kingside-rook-unmoved?', (ctx) =>
    isRookUnmoved('kingside', ctx.color as string, ctx.board as Board) ? 1 : 0);
  registry.register('queenside-rook-unmoved?', (ctx) =>
    isRookUnmoved('queenside', ctx.color as string, ctx.board as Board) ? 1 : 0);
  registry.register('kingside-path-clear?', (ctx) =>
    isCastlePathClear('kingside', ctx.color as string, ctx.board as Board) ? 1 : 0);
  registry.register('queenside-path-clear?', (ctx) =>
    isCastlePathClear('queenside', ctx.color as string, ctx.board as Board) ? 1 : 0);
  registry.register('kingside-castle-target?', (ctx) =>
    (ctx.to === kingsideCastleTarget(ctx.color as string)) ? 1 : 0);
  registry.register('queenside-castle-target?', (ctx) =>
    (ctx.to === queensideCastleTarget(ctx.color as string)) ? 1 : 0);

  // En passant
  registry.register('en-passant-target?', (ctx) =>
    (ctx.to === ctx.enPassantTarget) ? 1 : 0);

  // Piece moved check
  registry.register('moved?', (ctx) =>
    (ctx.hasMoved as boolean) ? 1 : 0);
}
```

The pure geometry functions (`isDiagonal`, `isLShape`, `isForwardOne`, etc.) are private helper functions in the same file — they implement the actual math. The host functions are the bridge between the cell engine (OP_CALLHOST) and the TypeScript logic.

---

### D27.3 — Go Engine (Semantic)

**File**: `packages/games/src/go/`

Go as a second proof point — different from chess in critical ways:

- Pieces (stones) are placed, never moved. AFFINE linearity (can be captured/removed, but not relocated).
- Capture removes groups, not individual pieces. Group detection is a graph traversal over cell references.
- Ko rule prevents recreating a previous board state — the DAG history makes this a simple lookup.
- Territory scoring counts empty intersections surrounded by one color — a semantic graph query.

```typescript
interface GoBoard {
  cellId: string;
  size: 9 | 13 | 19;
  intersections: (GoStone | null)[];       // size*size slots
  capturedBlack: number;
  capturedWhite: number;
  previousBoardCell?: string;              // DAG link (ko detection)
  koPoint: number | null;
}

interface GoStone extends GameEntity {
  entityType: 'stone';
  color: 'black' | 'white';
  intersection: number;
  linearity: 'AFFINE';                    // can be captured (destroyed) but not moved
}

class SemanticGoEngine {
  static async create(size?: 9 | 13 | 19): Promise<SemanticGoEngine>;
  play(intersection: number, color: 'black' | 'white'): Result<PlayResult, PlayError>;
  pass(color: 'black' | 'white'): void;
  legalMoves(color: 'black' | 'white'): number[];
  score(): { black: number; white: number };
  status(): 'playing' | 'scoring' | 'finished';
}
```

**Key difference from chess**: Go stones are AFFINE (not LINEAR) because captured stones are destroyed but never transferred. The capture operation is a group-level consume — all stones in a group with zero liberties are consumed in a single atomic operation.

---

### D27.4 — Card Game Framework (Semantic)

**File**: `packages/games/src/cards/`

A simple card game framework proving the SDK handles hidden information:

```typescript
/** A card is a LINEAR cell — exactly one copy in the game */
interface Card extends GameEntity {
  entityType: 'card';
  suit: 'hearts' | 'diamonds' | 'clubs' | 'spades';
  rank: 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13;
  faceUp: boolean;                         // visibility state
  linearity: 'LINEAR';                     // exactly one of each card
}

/** A deck is an inventory with shuffle and draw operations */
interface Deck extends Inventory {
  shuffle(): void;                         // reorder cell references (no cell mutation)
  draw(count: number): Card[];             // transfer cards from deck to hand
  peek(count: number): Card[];             // read without transfer (visibility-only)
}

/** A hand is a private inventory — other players can't see contents */
interface Hand extends Inventory {
  readonly visibility: 'private';          // cell payload encrypted to owner's key
}
```

**Hidden information model**:
- Cards in a hand are cells encrypted to the owner's identity key (Phase 8.5 facets)
- "Showing a card" decrypts the cell payload and creates a visibility proof
- Drawing from a deck is a transfer from the deck's inventory to the player's hand
- Deck shuffle reorders cell references without creating or destroying cells

This is deliberately simple — a single card game (e.g., War or simple Poker variant) to prove the hidden information model works.

---

### D27.5 — CLI Integration

**File**: `packages/games/src/cli/`

Shell commands for playing games via the semantic shell (Phase 19):

```bash
semantos game chess new
  → Creates 32 piece cells + board cell, returns game ID

semantos game chess move e2 e4
  → Evaluates pawn-move policy, executes move, returns new board FEN

semantos game chess status
  → Returns: playing | check | checkmate | stalemate | draw

semantos game chess history
  → Returns cell DAG of all board states (FEN per state)

semantos game chess export --format pgn
  → Exports game as PGN (standard chess notation)

semantos game go new --size 19
  → Creates 19x19 board cell

semantos game go play D4
  → Places stone, evaluates legality, handles captures
```

---

## TDD Gate — Tests That Must Pass

### Test 1: Chess Piece Cells (TypeScript)

```typescript
describe("D27.1 — Chess piece creation", () => {
  test("32 pieces created at game start, each with unique cellId", () => {});
  test("each piece is LINEAR — cell header confirms linearity byte", () => {});
  test("piece metadata contains type, color, square, hasMoved", () => {});
  test("board cell contains 64 cell references", () => {});
});
```

### Test 2: Chess Move Legality (TypeScript)

```typescript
describe("D27.2 — Move policies", () => {
  test("pawn can move forward one from e2 to e3", () => {});
  test("pawn can move forward two from e2 to e4", () => {});
  test("pawn cannot move forward two from e3", () => {});
  test("pawn captures diagonally", () => {});
  test("bishop moves diagonally, blocked by pieces", () => {});
  test("knight jumps over pieces in L-shape", () => {});
  test("castling requires unmoved king and rook, clear path, no check", () => {});
  test("en passant captures the correct pawn", () => {});
  test("promotion destroys pawn cell and creates new piece cell", () => {});
  test("move into check is rejected by policy", () => {});
});
```

### Test 3: Chess Capture as Cell Consumption (TypeScript)

```typescript
describe("D27.1 — Capture semantics", () => {
  test("captured piece cell is consumed (destroyed via opcode)", () => {});
  test("captured piece cellId no longer resolves", () => {});
  test("capturing piece occupies target square", () => {});
  test("capture is atomic — no intermediate state with two pieces on one square", () => {});
});
```

### Test 4: Game History DAG (TypeScript)

```typescript
describe("D27.1 — History DAG", () => {
  test("each move creates a new board cell", () => {});
  test("new board cell references previous board cell", () => {});
  test("history chain is traversable from latest to initial position", () => {});
  test("FEN export matches board state at each DAG node", () => {});
});
```

### Test 5: Go Capture Groups (TypeScript)

```typescript
describe("D27.3 — Go captures", () => {
  test("stone with zero liberties is captured (AFFINE consume)", () => {});
  test("group capture removes all stones in group atomically", () => {});
  test("ko rule prevents recreating previous board state", () => {});
  test("suicide move is rejected", () => {});
});
```

### Test 6: Card Linearity (TypeScript)

```typescript
describe("D27.4 — Card game", () => {
  test("deck contains exactly 52 LINEAR card cells", () => {});
  test("drawing a card transfers it from deck to hand", () => {});
  test("drawn card no longer in deck", () => {});
  test("shuffle reorders references without creating new cells", () => {});
});
```

### Test 7: Scholar's Mate (Integration)

```typescript
describe("D27 — Full game: Scholar's Mate", () => {
  test("1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# — checkmate in 4", () => {
    // Executes 7 moves via SemanticChessEngine
    // Verifies: 7 board cells in DAG
    // Verifies: f7 pawn cell consumed by Qxf7
    // Verifies: status() === 'checkmate'
    // Verifies: FEN matches expected final position
  });
});
```

---

## Phase Completion Criteria

You are **done with Phase 27** when ALL of the following are true:

1. `packages/games/src/chess/` implements full chess rules via semantic cells
2. Every piece is a LINEAR cell with unique cellId
3. Capture destroys the captured piece's cell via consume opcode
4. Move legality enforced by compiled Lisp policies (not if-statements)
5. Game history is a DAG of board cells
6. FEN import/export works correctly
7. Scholar's Mate integration test passes (checkmate in 4 moves)
8. Go engine handles placement, capture groups, and ko rule
9. Card framework demonstrates LINEAR deck with hidden information
10. CLI commands work via `semantos game` verb
11. All gate tests pass: `bun test packages/__tests__/phase27-gate.test.ts`
12. `bun run check` passes
13. `bun run build` succeeds
14. No React imports in games package
15. Errata sprint complete with `docs/prd/PHASE-27-ERRATA.md`
16. All commits follow `phase-27/D27.N:` naming convention
17. Branch is `phase-27-simple-games`

---

## What NOT to Do

1. **Do NOT implement an AI opponent.** This phase is about the semantic object model, not game AI. Minimax/MCTS is a separate concern.
2. **Do NOT implement networking or multiplayer.** Local two-player only for now.
3. **Do NOT implement a GUI.** CLI and programmatic API only. UI is a separate phase.
4. **Do NOT bypass the cell engine for performance.** If move evaluation is slow, optimize the policy compilation, not the enforcement path.
5. **Do NOT hardcode chess rules in TypeScript.** Rules are Lisp policies that compile to opcodes via `OP_CALLHOST` (Phase 25.5). Board-query predicates are registered as host functions, not implemented as TypeScript if-statements.
6. **Do NOT implement a full poker game.** The card framework is a proof-of-concept for hidden information, not a complete game.
7. **Do NOT modify the Game SDK (Phase 26) or the cell engine.** Game predicates are registered via Phase 25.5 HostFunctionRegistry, not by adding opcodes.
8. **Do NOT implement ELO ratings or matchmaking.** Out of scope.

---

## Next Phase

Phase 27 output feeds into future work on **multiplayer state sync** (semantic game state synchronized via Plexus DAG edges) and **game marketplace** (LINEAR items traded via Phase 18 metering channels). The chess engine also serves as a demonstration vehicle for the entire Semantos thesis — from natural language rule authoring to opcode-level enforcement.
