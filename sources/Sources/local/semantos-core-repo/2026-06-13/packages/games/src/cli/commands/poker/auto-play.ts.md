---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/auto-play.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.421605+00:00
---

# packages/games/src/cli/commands/poker/auto-play.ts

```ts
/**
 * Simple AI loop for the poker CLI: checks when possible, calls small
 * bets, folds to large raises. Stops at the human player (`player-0`)
 * or once the hand finishes. Mutates the response object in place with
 * the post-AI table render — same shape the legacy router emitted.
 */

import { renderPokerTable, renderActionPrompt } from '../../../cards/poker-renderer';
import type { PokerAction } from '../../../cards/poker-types';
import { session } from '../../session';

export async function autoPlayAI(response: Record<string, unknown>): Promise<void> {
  const game = session.pokerGame;
  if (!game) return;

  let safety = 50;
  while (safety-- > 0) {
    const table = game.getTable();
    if (table.phase === 'hand-complete' || table.phase === 'showdown' || table.phase === 'waiting') break;

    const active = game.getActivePlayer();
    if (!active || active.id === 'player-0') break; // Stop at human player

    const toCall = table.currentBet - active.currentBet;

    let aiAction: PokerAction;
    if (toCall === 0) {
      aiAction = Math.random() < 0.3
        ? { type: 'bet', amount: table.bigBlind }
        : { type: 'check' };
    } else if (toCall <= table.bigBlind * 3) {
      aiAction = Math.random() < 0.8 ? { type: 'call' } : { type: 'fold' };
    } else {
      aiAction = Math.random() < 0.4 ? { type: 'call' } : { type: 'fold' };
    }

    const result = game.act(active.id, aiAction);
    if (!result.success) {
      // If action fails, fold as a safe fallback.
      game.act(active.id, { type: 'fold' });
    }
  }

  const finalTable = game.getTable();
  const finalPlayers = game.getPlayers();
  response.table = renderPokerTable(finalTable, finalPlayers, 'player-0');
  response.phase = finalTable.phase;
  response.pot = finalTable.pot;

  if (finalTable.phase === 'hand-complete' || finalTable.phase === 'showdown') {
    response.result = 'Hand complete!';
    const you = finalPlayers.find((p) => p.id === 'player-0');
    if (you) response.yourChips = you.chips;
  } else {
    const nextActive = game.getActivePlayer();
    if (nextActive && nextActive.id === 'player-0') {
      response.prompt = renderActionPrompt(nextActive, finalTable);
    }
  }
}

```
