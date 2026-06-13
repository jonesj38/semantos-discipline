---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/session.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.400326+00:00
---

# packages/games/src/cli/session.ts

```ts
/**
 * Per-process session state for the game CLI.
 *
 * The legacy game-commands.ts kept module-level singletons for each
 * game type (`chessGame`, `lifeGame`, …). We preserve that behaviour —
 * a single in-process session shared by every command handler — but
 * gather the singletons into one object so handlers can be registered
 * in separate files without re-introducing module globals everywhere.
 */

import type { SemanticChessEngine } from '../chess/engine';
import type { GameOfLifeEngine } from '../life/engine';
import type { RiskEngine } from '../risk/engine';
import type { DungeonEngine } from '../dungeon/engine';
import type { PokerEngine } from '../cards/poker';

export interface CliGameSession {
  chessGame: SemanticChessEngine | null;
  chessMoves: string[];
  lifeGame: GameOfLifeEngine | null;
  riskGame: RiskEngine | null;
  dungeonGame: DungeonEngine | null;
  pokerGame: PokerEngine | null;
}

/** The single per-process session. */
export const session: CliGameSession = {
  chessGame: null,
  chessMoves: [],
  lifeGame: null,
  riskGame: null,
  dungeonGame: null,
  pokerGame: null,
};

/** Test-only — wipe the session back to its initial state. */
export function _resetSession(): void {
  session.chessGame = null;
  session.chessMoves = [];
  session.lifeGame = null;
  session.riskGame = null;
  session.dungeonGame = null;
  session.pokerGame = null;
}

```
