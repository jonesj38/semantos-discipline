---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.414093+00:00
---

# packages/games/src/chess-stakes/types.ts

```ts
/**
 * Chess Stakes — Doubling Cube Types
 *
 * The doubling cube is a LINEAR cell. Exactly one exists per game.
 * It cannot be duplicated. Ownership transfers between players when
 * a double is "taken" — the same transfer primitive the SDK uses
 * for trading items between inventories.
 *
 * Cube values follow the backgammon progression: 1 → 2 → 4 → 8 → 16 → 32 → 64.
 * The cube starts "centered" (neither player owns it, either can offer first).
 * After a take, only the player who accepted owns the cube and only
 * the OTHER player (the one who does NOT hold the cube) can offer the next double.
 *
 * Wait — correction: in backgammon, the player who TAKES the double
 * receives the cube. That player now "holds" the cube. Only the holder
 * can propose the NEXT double. Actually no — only the NON-holder can
 * propose. Let me get this right:
 *
 * Backgammon rules:
 *   - Cube starts centered (value 1, no holder).
 *   - Either player can make the first double.
 *   - After a take, the taker holds the cube.
 *   - Only the holder can propose the NEXT double.
 *   - Wait, that's wrong too. In backgammon, the player who was
 *     DOUBLED (and accepted) now holds the cube, meaning only THEY
 *     can propose the next double. This is correct.
 *
 * So: the holder is the only one who CAN double next time.
 */

import type { GameEntity } from '../../../game-sdk/src/types';
import type {
  ChessBoard,
  ChessPiece,
  Color,
  PieceType,
  GameStatus as ChessGameStatus,
} from '../chess/types';

// ── Cube State Machine ──────────────────────────────────────────

/**
 * Cube states:
 *   centered — value 1, no holder, either player can first-double
 *   held     — a player holds the cube (they alone can next double)
 *   offered  — a double has been proposed, awaiting response
 */
export type CubeState = 'centered' | 'held' | 'offered';

/** Valid cube values (powers of 2). */
export type CubeValue = 1 | 2 | 4 | 8 | 16 | 32 | 64;

export const CUBE_VALUES: readonly CubeValue[] = [1, 2, 4, 8, 16, 32, 64];

/** Next cube value. Returns null if already at max (64). */
export function nextCubeValue(current: CubeValue): CubeValue | null {
  const idx = CUBE_VALUES.indexOf(current);
  return idx < CUBE_VALUES.length - 1 ? CUBE_VALUES[idx + 1] : null;
}

// ── Doubling Cube Entity ────────────────────────────────────────

/**
 * The doubling cube — a LINEAR cell.
 *
 * In semantic terms:
 *   - LINEAR: exactly one cube per game, cannot be duplicated
 *   - ownership transfers on "take" (same as item trade)
 *   - state machine governs when doubles can be offered
 */
export interface DoublingCube {
  /** The underlying GameEntity (1024-byte LINEAR cell) */
  entity: GameEntity;
  /** Current displayed value */
  value: CubeValue;
  /** Current state in the cube state machine */
  state: CubeState;
  /**
   * Who holds the cube. null when centered (value=1, game start).
   * The holder is the only player who can propose the next double.
   */
  holder: Color | null;
  /**
   * When state='offered': who proposed the double.
   * null otherwise.
   */
  offeredBy: Color | null;
}

// ── Stakes Game Status ──────────────────────────────────────────

/**
 * Extended game status that includes forfeit-by-drop.
 * All standard chess endings apply, plus:
 *   - 'forfeited' when a player drops (declines) the double
 */
export type StakesGameStatus =
  | ChessGameStatus
  | 'forfeited';

/** Who won, how, and at what stakes. */
export interface StakesGameResult {
  /** Final game status */
  status: StakesGameStatus;
  /** Winner color (null for draw) */
  winner: Color | null;
  /** Final cube value — the multiplier for the result */
  cubeValue: CubeValue;
  /**
   * Point value of the result.
   * In backgammon this would be cubeValue × gammon/backgammon multiplier.
   * In chess-stakes: cubeValue × 1 for normal win, cubeValue × 2 for
   * checkmate (optional "gammon" variant).
   */
  points: number;
}

// ── Action Types ────────────────────────────────────────────────

/** Actions a player can take on their turn (before moving). */
export type CubeAction =
  | { type: 'double' }              // propose doubling the stakes
  | { type: 'take' }                // accept a proposed double
  | { type: 'drop' }                // decline a proposed double (forfeit)
  | { type: 'move'; from: number; to: number; promotion?: PieceType }; // normal chess move

/** Result of a cube action. */
export interface CubeActionResult {
  /** Updated cube state */
  cube: DoublingCube;
  /** Updated board (only changes on 'move') */
  board: ChessBoard;
  /** Game result if the game ended */
  gameResult: StakesGameResult | null;
  /** Human-readable description */
  description: string;
}

// ── Stakes Board (extends ChessBoard with cube) ─────────────────

export interface StakesChessBoard {
  /** The chess board state */
  chess: ChessBoard;
  /** The doubling cube */
  cube: DoublingCube;
  /**
   * Turn phase:
   *   'cube-or-move' — active player can double or move
   *   'awaiting-response' — opponent must take or drop
   *   'must-move' — double was taken (or not offered), now must move
   */
  phase: 'cube-or-move' | 'awaiting-response' | 'must-move';
}

// ── Cube State Machine Definition ───────────────────────────────

/**
 * The cube state machine as an EntityStateMachine.
 * Transitions:
 *   centered → offered  (first double, by either player)
 *   held → offered      (subsequent double, by holder only)
 *   offered → held      (take — cube transfers to taker)
 *   offered → forfeited (drop — game over)
 */
export const CUBE_STATE_MACHINE = {
  states: [
    { name: 'centered' },
    { name: 'held' },
    { name: 'offered' },
  ],
  transitions: [
    { from: 'centered', to: 'offered', policy: '(can-double?)' },
    { from: 'held', to: 'offered', policy: '(can-double?)' },
    { from: 'offered', to: 'held', policy: '(is-response-player?)' },
    // 'drop' doesn't transition the cube — it ends the game
  ],
  initialState: 'centered',
};

```
