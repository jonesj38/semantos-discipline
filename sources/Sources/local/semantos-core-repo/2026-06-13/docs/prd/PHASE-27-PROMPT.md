---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-27-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.664520+00:00
---

# Phase 27 Execution Prompt — Simple Games (Chess, Go, Card Games)

> Paste this prompt into a fresh session to execute Phase 27.

## Context

You are working in the `semantos-core` repo (npm: `@semantos/core`). Phase 26 built the Game Engine SDK — a TypeScript wrapper over the 28KB Zig/WASM cell engine with game-domain types (GameEntity, Inventory, TradeProposal), linearity enforcement, and a Lisp policy surface for game designers. Phase 25.5 added `OP_CALLHOST` (0xD0), the generic host function dispatch opcode, and the `HostFunctionRegistry` that lets domain packages register named predicates without modifying the cell engine.

This phase proves the SDK works by building games that exercise every primitive. Chess is the primary target:

- **Pieces are LINEAR cells.** A rook is a single cell. It cannot be duplicated. It exists in exactly one square.
- **Capture is consumption.** Taking a piece executes the `consume` opcode on the captured cell. The cell is destroyed — linearity enforced, not checked.
- **The board is a semantic object.** 64 squares, each an optional cell reference. Board state is a cell whose payload contains 64 cell pointers.
- **Move legality is a policy.** "A bishop moves diagonally" is a Lisp constraint that compiles to opcodes. The cell engine evaluates it before the move executes.
- **Game state is a DAG.** Each move produces a new board cell that references the previous one. The game history is an immutable chain — the same structure Semantos uses everywhere.

Chess is not the point. The point is that chess forces you to exercise: entity creation (pieces), linearity enforcement (no duplication), state transitions (moves), policy evaluation (legal move checking), consumption (captures), and DAG persistence (game history). If the SDK handles chess, it handles any turn-based game.

Go and a simple card game provide secondary proof points — different linearity models (AFFINE stones, LINEAR cards with hidden information).

---

## CRITICAL: READ THESE FILES FIRST

Before writing a single line of code, read every file listed below.

**Read first** (the PRDs — your requirements chain):
- `docs/prd/PHASE-27-SIMPLE-GAMES.md` — Full spec with D27.1–D27.5, gate tests, completion criteria
- `docs/prd/PHASE-26-GAME-ENGINE-SDK.md` — The SDK you're building on (read the type definitions)

**Read second** (the SDK you are consuming — do NOT modify these):
- `packages/game-sdk/src/types.ts` — GameEntity, Inventory, TradeProposal, EntityState
- `packages/game-sdk/src/engine.ts` — GameCellEngine (create, transition, executeTrade, evaluatePolicy, serialize, deserialize)
- `packages/game-sdk/src/policies/` — Policy templates and compilation

**Read third** (the host function dispatch — Phase 25.5):
- `packages/cell-engine/bindings/host-function-registry.ts` — `HostFunctionRegistry` (how you register game predicates)
- `packages/cell-engine/bindings/builtin-host-functions.ts` — Built-in generics (pattern for registering functions)

**Read fourth** (the Lisp policy system for move rules):
- `packages/shell/src/lisp/compiler.ts` — LispCompiler class (with OP_CALLHOST and `(predicate?)` sugar)
- `packages/shell/src/lisp/parser.ts` — S-expression parser
- `packages/shell/src/lisp/types.ts` — PolicyForm, ConstraintExpr, HostCallExpr types

**Read fourth** (cell engine internals for board representation):
- `packages/cell-engine/src/opcodes.ts` — Opcode table
- `packages/protocol-types/src/index.ts` — Cell header types, linearity modes

**Read fifth** (branching policy):
- `docs/BRANCHING-AND-CI-POLICY.md` — Branch as `phase-27-simple-games`. Commits as `phase-27/D27.N: description`.

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

### 1. RULES ARE POLICIES, NOT IF-STATEMENTS

Chess move legality is NOT:
```typescript
if (piece.type === 'bishop' && isDiagonal(from, to) && isPathClear(from, to, board)) { ... }
```

It IS:
```lisp
(define-policy bishop-move
  :subject player :action move
  :constraint (and (= piece-type "bishop") (diagonal-path?) (path-clear?))
  :linearity LINEAR)
```

The Lisp policy compiles to opcodes. `(diagonal-path?)` compiles to `push "diagonal-path?" OP_CALLHOST` via Phase 25.5. The host function reads from/to/board from the evaluation context (set before script execution). Your game code calls `evaluatePolicy()` and gets back a boolean. If you write a single `if (piece.type === 'bishop')` move validation check in TypeScript, you have violated this rule.

### 2. CAPTURE IS CELL CONSUMPTION

Capture is NOT `board[square] = null`. Capture is `cellEngine.transition(capturedPiece, 'CONSUMED')` which executes the consume opcode on a LINEAR cell. The cell is destroyed at the engine level. Your code surfaces the result. It does not implement the destruction.

### 3. BOARD IS A CELL, NOT AN ARRAY

The board is a semantic object (a cell) whose payload contains 64 cell references. It is NOT a `ChessPiece[]` array that you manipulate directly. When you move a piece, you create a new board cell referencing the previous board cell. The old board state is immutable.

### 4. DO NOT MODIFY THE GAME SDK

`packages/game-sdk/` was built in Phase 26. If it's missing something, note it for errata but do NOT modify it here. Build your games using the SDK's public API only.

### 5. EVERY MOVE CREATES A NEW BOARD CELL

The board's `previousBoardCell` creates a DAG. After 40 moves, you have 40 board cells linked in a chain. This is how the game history works. There is no separate move list. The DAG IS the move list.

### 6. FEN IS A VIEW, NOT THE SOURCE OF TRUTH

`toFEN()` is a read-only export. The source of truth is the board cell and its piece cell references. FEN is derived from the cell state, not the other way around. `fromFEN()` creates cells from FEN for convenience, but the cells are authoritative.

### 7. NO GAME AI

No minimax, no alpha-beta, no MCTS, no evaluation functions. This phase is about the semantic object model, not game-playing strength. Two human players (via CLI or programmatic API).

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Verify Phase 26 prerequisites

```bash
# Game SDK exists
ls packages/game-sdk/src/types.ts
ls packages/game-sdk/src/engine.ts
ls packages/game-sdk/src/policies/

# Phase 26 tests pass
bun test packages/__tests__/phase26-gate.test.ts

# Lisp compiler exists
ls packages/shell/src/lisp/compiler.ts
ls packages/shell/src/lisp/parser.ts

# Full build passes
bun run check
bun run build
```

All must pass. If anything fails, STOP.

### 0.3 Create Phase 27 branch

```bash
git checkout -b phase-27-simple-games
```

---

## Step 1: Chess Engine — Board and Pieces (D27.1a)

Create `packages/games/src/chess/types.ts` and `packages/games/src/chess/engine.ts`.

**Requirements**:

- `ChessBoard` interface:
  - `cellId` — board cell address
  - `squares` — array of 64 `(ChessPiece | null)` entries, a8=0 through h1=63
  - `activeColor`, `castlingRights`, `enPassantTarget`, `halfMoveClock`, `fullMoveNumber`
  - `previousBoardCell` — DAG link to prior state

- `ChessPiece` interface extending `GameEntity`:
  - `entityType` — king, queen, rook, bishop, knight, pawn
  - `color` — white, black
  - `square` — current position (0-63)
  - `hasMoved` — for castling/pawn double-move

- `SemanticChessEngine` class:
  - `static async create()` — initializes standard position, creates 32 piece cells + board cell
  - `move(from, to, promotion?)` — validates via policy, executes, returns new board
  - `legalMoves(square)` — evaluates policies for all target squares
  - `toFEN()` — export board as FEN string
  - `static fromFEN(fen)` — import board from FEN, creates cells
  - `history()` — returns cell DAG of all board states
  - `status()` — playing, check, checkmate, stalemate, draw

**Move execution flow** (implement exactly this):
1. Parse (from, to) coordinates
2. Load piece cell from source square
3. Evaluate move policy (compiled Lisp → 2-PDA)
4. If capture: consume target piece cell (LINEAR destruction)
5. Update piece cell's square field (state transition)
6. Create new board cell referencing previous board cell (DAG append)
7. Return MoveResult

Create `packages/games/package.json` with name `@semantos/games`, dependency on `@semantos/game-sdk`.

**Commit**: `phase-27/D27.1a: chess board, piece types, and SemanticChessEngine with move execution`

---

## Step 2: Chess Move Policies (D27.2)

Create `packages/games/src/chess/policies/`.

**CRITICAL**: ALL chess predicates are zero-arity host functions registered via `HostFunctionRegistry`. The evaluation context is set before each move evaluation with `{ from, to, board, color, pieceType, enPassantTarget, castlingRights, hasMoved }`. Predicates read from this frozen context and return 0/1. Do NOT pass arguments to predicates in Lisp policy forms.

**Requirements**:

Write Lisp policies for each piece type's movement rules:

- `pawn-move.policy` — forward one/two, diagonal capture, en passant
- `knight-move.policy` — L-shape, can jump
- `bishop-move.policy` — diagonal, can't jump
- `rook-move.policy` — orthogonal, can't jump
- `queen-move.policy` — diagonal or orthogonal, can't jump
- `king-move.policy` — one square any direction + castling (kingside/queenside)

Each policy uses these constraint primitives (implement as host functions):
- `forward-one?`, `forward-two?`, `diagonal-one-forward?` — pawn geometry
- `diagonal-path?`, `orthogonal-path?`, `l-shape?` — piece geometry
- `path-clear?` — no pieces blocking the path
- `square-empty?`, `has-enemy-piece?` — target square queries
- `on-start-rank?`, `not-in-check?`, `no-check-through-path?` — special rules

Create `packages/games/src/chess/host-functions.ts` — register each predicate with `HostFunctionRegistry`:

- Import `HostFunctionRegistry` from `@semantos/cell-engine/bindings/host-function-registry`
- Export `registerChessHostFunctions(registry: HostFunctionRegistry): void`
- Register every predicate used in the policies (`diagonal-path?`, `path-clear?`, `square-empty?`, etc.)
- Each host function reads from `ctx` (the frozen context) and returns 0 or 1
- Pure geometry helpers (`isDiagonal`, `isLShape`, etc.) are private functions — the host functions call them

In the `SemanticChessEngine`, wire it up:
1. At initialization: `registerChessHostFunctions(this.registry)`
2. Before each move evaluation: `this.registry.setContext({ from, to, board, color, ... })`
3. After evaluation: `this.registry.clearContext()`

**Commit**: `phase-27/D27.2: chess move policies (Lisp) with board-query host functions`

---

## Step 3: Chess Special Moves (D27.1b)

Extend `packages/games/src/chess/engine.ts`.

**Requirements**:

Implement the special cases that make chess chess:

- **Castling**: atomic two-cell transition (king + rook). Requires unmoved king, unmoved rook, clear path, not in check, no check through path. Both cells move in one operation.
- **En passant**: diagonal pawn capture where the captured pawn is on a different square than the destination. Policy must reference both squares. Consume the correct pawn cell.
- **Promotion**: pawn reaches 8th rank. Destroy pawn cell, create new piece cell (queen/rook/bishop/knight). Atomic consume + create.
- **Check detection**: after each move, verify the opposing king is not in check. If the current player's king would be in check after a move, the move is illegal.
- **Checkmate/stalemate**: after each move, check if the opponent has any legal moves. If no legal moves and in check → checkmate. If no legal moves and not in check → stalemate.
- **Draw conditions**: 50-move rule (halfMoveClock), threefold repetition (compare board cell DAG for identical positions), insufficient material.

**Commit**: `phase-27/D27.1b: castling, en passant, promotion, check, checkmate, stalemate, draw`

---

## Step 4: Go Engine (D27.3)

Create `packages/games/src/go/`.

**Requirements**:

- `GoBoard` — semantic object with `size*size` intersections, captured counts, ko point
- `GoStone` — AFFINE entity (can be captured/destroyed, not relocated)
- `SemanticGoEngine`:
  - `static async create(size?)` — creates empty board (9, 13, or 19)
  - `play(intersection, color)` — places stone, evaluates legality, handles captures
  - `pass(color)` — pass turn
  - `legalMoves(color)` — all legal placements
  - `score()` — territory scoring
  - `status()` — playing, scoring, finished

**Key semantics**:
- Stones are AFFINE (not LINEAR) — captured stones are destroyed but never transferred
- Group capture: stones in a group with zero liberties are all consumed in a single atomic operation
- Ko rule: prevent recreating previous board state — compare against DAG history (simple cellId lookup)
- Suicide prevention: placing a stone that immediately has zero liberties (and doesn't capture) is illegal

Go policies are simpler than chess: placement legality, suicide check, ko check. Write them as Lisp constraints.

**Commit**: `phase-27/D27.3: Go engine with AFFINE stones, group capture, ko rule, territory scoring`

---

## Step 5: Card Game Framework (D27.4)

Create `packages/games/src/cards/`.

**Requirements**:

- `Card` — LINEAR entity with suit, rank, faceUp flag
- `Deck` — inventory with shuffle (reorder references) and draw (transfer to hand)
- `Hand` — private inventory (visibility: private)
- A single simple card game (War) proving the hidden information model works

**Hidden information model**:
- Cards in a hand are cells encrypted to the owner's identity key (Phase 8.5)
- "Showing a card" creates a visibility proof by decrypting the cell payload
- Drawing from deck = transfer from deck inventory to hand inventory
- Shuffle = reorder cell references (no cells created or destroyed)

Keep this simple. War is: draw top card each, higher card wins both. Winner collects cards. Game ends when one player has all cards.

**Commit**: `phase-27/D27.4: card game framework with LINEAR deck, hidden hands, and War implementation`

---

## Step 6: CLI Integration (D27.5)

Create `packages/games/src/cli/`.

**Requirements**:

Wire game commands into the semantic shell (Phase 19):

```bash
semantos game chess new                    → creates game, returns ID
semantos game chess move e2 e4             → validates + executes move
semantos game chess status                 → playing/check/checkmate/stalemate/draw
semantos game chess history                → cell DAG of board states
semantos game chess board                  → ASCII board display
semantos game chess export --format pgn    → PGN export
semantos game go new --size 19             → creates Go game
semantos game go play D4                   → places stone
semantos game go pass                      → passes turn
semantos game go board                     → ASCII board display
```

For chess, include ASCII board rendering:
```
  a b c d e f g h
8 r n b q k b n r 8
7 p p p p p p p p 7
6 . . . . . . . . 6
5 . . . . . . . . 5
4 . . . . . . . . 4
3 . . . . . . . . 3
2 P P P P P P P P 2
1 R N B Q K B N R 1
  a b c d e f g h
```

**Commit**: `phase-27/D27.5: CLI integration with game commands, ASCII board rendering, PGN export`

---

## Step 7: Gate Tests

Create `packages/__tests__/phase27-gate.test.ts`.

### Chess Piece Cells (T1–T4)

```typescript
describe("D27.1 — Chess piece creation", () => {
  // T1: 32 pieces created at game start, each with unique cellId
  // T2: each piece is LINEAR — cell header confirms linearity byte
  // T3: piece metadata contains type, color, square, hasMoved
  // T4: board cell contains 64 cell references
});
```

### Chess Move Legality (T5–T14)

```typescript
describe("D27.2 — Move policies", () => {
  // T5: pawn forward one from e2 to e3 — legal
  // T6: pawn forward two from e2 to e4 — legal
  // T7: pawn forward two from e3 — illegal
  // T8: bishop diagonal, blocked by piece — illegal
  // T9: knight L-shape over pieces — legal
  // T10: castling with all conditions met — legal
  // T11: castling through check — illegal
  // T12: en passant captures the correct pawn cell
  // T13: promotion destroys pawn cell and creates queen cell
  // T14: move into check is rejected
});
```

### Capture Semantics (T15–T18)

```typescript
describe("D27.1 — Capture", () => {
  // T15: captured piece cell is consumed (destroyed via opcode)
  // T16: captured cellId no longer resolves
  // T17: capturing piece occupies target square
  // T18: capture is atomic — no intermediate two-pieces-on-one-square state
});
```

### Game History DAG (T19–T22)

```typescript
describe("D27.1 — History DAG", () => {
  // T19: each move creates a new board cell
  // T20: new board cell references previous board cell
  // T21: history chain is traversable from latest to initial
  // T22: FEN export matches board state at each DAG node
});
```

### Scholar's Mate Integration (T23)

```typescript
describe("D27 — Scholar's Mate", () => {
  // T23: 1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#
  //   - 7 moves via SemanticChessEngine
  //   - 7 board cells in DAG
  //   - f7 pawn cell consumed by Qxf7
  //   - status() === 'checkmate'
  //   - FEN matches expected final position
});
```

### Go Tests (T24–T27)

```typescript
describe("D27.3 — Go", () => {
  // T24: stone with zero liberties is captured (AFFINE consume)
  // T25: group capture removes all stones atomically
  // T26: ko rule prevents recreating previous board state
  // T27: suicide move is rejected
});
```

### Card Tests (T28–T31)

```typescript
describe("D27.4 — Cards", () => {
  // T28: deck contains exactly 52 LINEAR card cells
  // T29: drawing transfers card from deck to hand
  // T30: drawn card no longer in deck
  // T31: shuffle reorders references without creating new cells
});
```

### Anti-Lock (T32–T33)

```typescript
describe("D27 — Anti-lock", () => {
  // T32: no React imports in games package
  // T33: no game-sdk modifications (package.json unchanged)
});
```

**Commit**: `phase-27/T1-T33: full gate test suite — chess, go, cards, integration, anti-lock`

---

## Step 8: Errata Sprint

After all tests pass, run errata protocol in a fresh session:

1. Play through 5 famous chess games (Scholar's Mate, Fool's Mate, Opera Game, Immortal Game, Evergreen Game) — all must produce correct results
2. Verify all special moves: castling (both sides), en passant, promotion (all 4 piece types)
3. Verify stalemate detection with known stalemate positions
4. Verify 50-move rule and threefold repetition
5. Verify Go group capture with complex multi-stone groups
6. Verify card deck is exactly 52 after any number of shuffles
7. Check that no move validation happens in TypeScript (all via policy evaluation)
8. Check that DAG chain length equals move count
9. Measure full game throughput — a 40-move chess game should complete in <5 seconds
10. Write errata doc as `docs/prd/PHASE-27-ERRATA.md`

---

## Completion Criteria

- [ ] `packages/games/src/chess/` implements full chess rules via semantic cells
- [ ] Every piece is a LINEAR cell with unique cellId
- [ ] Capture destroys the captured cell via consume opcode
- [ ] Move legality enforced by compiled Lisp policies (NOT by if-statements)
- [ ] Game history is a DAG of board cells (one per move)
- [ ] FEN import/export works correctly
- [ ] Scholar's Mate integration test passes
- [ ] All special moves work: castling, en passant, promotion
- [ ] Check, checkmate, stalemate, draw detected correctly
- [ ] Go engine handles placement, group capture, ko rule, suicide prevention
- [ ] Card framework demonstrates LINEAR deck with hidden information
- [ ] CLI commands work via `semantos game` verb
- [ ] ASCII board rendering for chess and Go
- [ ] PGN export for chess
- [ ] Tests T1–T33 all pass
- [ ] `bun run check` passes
- [ ] `bun run build` succeeds
- [ ] No React imports in games package
- [ ] Errata sprint complete with `docs/prd/PHASE-27-ERRATA.md`
- [ ] All commits follow `phase-27/D27.N:` naming convention
- [ ] Branch is `phase-27-simple-games`

---

## What NOT to Do

1. Do NOT implement a chess AI — no minimax, no MCTS, no evaluation
2. Do NOT implement networking — local two-player only
3. Do NOT implement a GUI — CLI and programmatic API only
4. Do NOT bypass the cell engine for performance — optimize policies, not enforcement
5. Do NOT hardcode chess rules in TypeScript — rules are Lisp policies
6. Do NOT implement full poker — the card framework is a proof-of-concept
7. Do NOT modify the Game SDK, cell engine, or Lisp compiler — register predicates via Phase 25.5 HostFunctionRegistry
8. Do NOT implement ELO/matchmaking — out of scope

---

## After Phase 27: Games Are Semantic Objects

After Phase 27, you have three working games where every object is a cell, every rule is a compiled policy, and every state change is a cell engine operation. The chess engine alone exercises:

- Entity creation (32 pieces + board)
- Linearity enforcement (no piece duplication)
- State transitions (move execution)
- Policy evaluation (6 piece-type policies + special move rules)
- Cell consumption (captures)
- DAG persistence (game history)
- Serialization (FEN import/export)

This is the most accessible demonstration of the Semantos thesis. The compression gradient is visible in every move: Lisp policy → opcode sequence → 2-PDA evaluation → cell state update → DAG append. Same pipeline, whether you're authorizing a valve command, novating a derivative, or moving a bishop.
