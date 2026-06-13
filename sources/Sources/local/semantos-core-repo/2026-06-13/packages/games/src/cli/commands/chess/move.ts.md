---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/chess/move.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.418052+00:00
---

# packages/games/src/cli/commands/chess/move.ts

```ts
/**
 * `semantos game chess move --move <e2e4|e2 e4|e7e8q>` — apply a move.
 *
 * Parses algebraic squares and an optional promotion suffix, then
 * delegates to the engine's `move()` method.
 */

import { renderBoard } from '../../../chess/renderer';
import { toFEN } from '../../../chess/fen';
import { algebraicToSquare, type PieceType } from '../../../chess/types';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

const PROMO_MAP: Record<string, PieceType> = {
  q: 'queen', r: 'rook', b: 'bishop', n: 'knight',
};

export const chessMove: CommandSpec = {
  game: 'chess',
  action: 'move',
  summary: 'Apply an algebraic-notation chess move.',
  args: [
    { name: 'move', description: 'Move spec, e.g. e2e4 or e7e8q for promotion.', required: true },
  ],
  handler(cmd) {
    if (!session.chessGame) return { error: 'No active game. Run: semantos game chess new' };
    const moveStr = (cmd.flags.move as string)
      ?? (cmd.flags.expression as string)
      ?? '';
    const cleaned = moveStr.replace(/\s+/g, '');
    if (cleaned.length < 4) {
      return { error: `Invalid move format: "${moveStr}". Use: e2e4 or e2 e4` };
    }
    const fromAlg = cleaned.slice(0, 2);
    const toAlg = cleaned.slice(2, 4);
    const promoChar = cleaned[4];

    try {
      const fromSq = algebraicToSquare(fromAlg);
      const toSq = algebraicToSquare(toAlg);
      const result = session.chessGame.move(
        fromSq,
        toSq,
        promoChar ? PROMO_MAP[promoChar] : undefined,
      );
      session.chessMoves.push(result.notation);
      return {
        move: result.notation,
        captured: result.captured ? `${result.captured.color} ${result.captured.pieceType}` : null,
        status: result.status,
        board: renderBoard(result.board),
        fen: toFEN(result.board),
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
