---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/chess/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.428733+00:00
---

# cartridges/chess/web/src/chess/types.ts

```ts
/**
 * Wire types for the chess cartridge walkers.
 *
 * Mirrors `cartridges/chess/brain/chess_walkers.zig::gameJson` byte-for-
 * byte. Do not diverge without updating both sides.
 */

export type Color = 'white' | 'black';
/** Mirrors `chess_game_store.zig::Status`. */
export type GameStatus = 'waiting' | 'active' | 'white_won' | 'black_won' | 'draw' | 'cancelled';
/** Mirrors `chess_game_store.zig::EndReason` exactly. Update both
 *  sides together if a new reason is added. */
export type EndReason =
  | 'none'
  | 'checkmate'
  | 'stalemate'
  | 'fifty_move'
  | 'insufficient_material'
  | 'threefold'
  | 'decline_forfeit'
  | 'timeout'
  | 'timeout_pending'
  | 'cancelled'
  | 'resign';

/** Human-readable label for an end reason — used in the game-end overlay. */
export function endReasonLabel(reason: EndReason): string {
  switch (reason) {
    case 'none': return '';
    case 'checkmate': return 'Checkmate';
    case 'stalemate': return 'Stalemate';
    case 'fifty_move': return 'Fifty-move draw';
    case 'insufficient_material': return 'Insufficient material';
    case 'threefold': return 'Threefold repetition';
    case 'decline_forfeit': return 'Double declined — forfeit';
    case 'timeout': return 'Flag (clock ran out)';
    case 'timeout_pending': return 'Flag during pending double';
    case 'cancelled': return 'Cancelled by host';
    case 'resign': return 'Resigned';
  }
}

export function isTerminal(s: GameStatus): boolean {
  return s === 'white_won' || s === 'black_won' || s === 'draw' || s === 'cancelled';
}

export interface PendingDouble {
  readonly offerer: Color;
  readonly levelBefore: number;
  readonly levelAfter: number;
}

export interface GameRecord {
  readonly ok: true;
  readonly gameId: string;
  readonly status: GameStatus;
  readonly endReason: EndReason;
  readonly winner: Color | null;
  readonly fen: string;
  readonly white: string;
  readonly black: string;
  readonly stakeSats: number;
  /** Cube multiplier — starts at 1, doubles per accepted offer. */
  readonly multiplier: number;
  /** Cube owner (null = centred; otherwise the side that holds it). */
  readonly cubeOwner: Color | null;
  /** Remaining ms on each clock. */
  readonly whiteMs: number;
  readonly blackMs: number;
  /** Side whose clock is running, null when no clock is ticking. */
  readonly running: Color | null;
  readonly pending: PendingDouble | null;
}

export interface RejectionBody {
  readonly ok: false;
  readonly reason: string;
}

export type WalkerResponse = GameRecord | RejectionBody;

export function isGameRecord(r: unknown): r is GameRecord {
  return typeof r === 'object' && r !== null && (r as { ok?: unknown }).ok === true;
}

/** Convert cube multiplier (1,2,4,8,…) to Linearity for the cube-object renderer. */
export function multiplierToLinearity(m: number): 0 | 1 | 2 {
  // Cube linearity reflects the kernel's substructural type:
  //   1×  → AFFINE  (no doubles yet, cube is freely droppable)
  //   2×  → LINEAR  (single accepted double, exactly one consumption path)
  //   ≥4× → RELEVANT (must be eventually consumed; can't be silently dropped)
  if (m <= 1) return 1;
  if (m === 2) return 0;
  return 2;
}

```
