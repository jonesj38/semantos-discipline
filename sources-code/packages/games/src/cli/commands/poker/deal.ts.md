---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/deal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.422777+00:00
---

# packages/games/src/cli/commands/poker/deal.ts

```ts
/** `semantos game poker deal` — deal hole cards and post blinds. */

import { renderPokerTable, renderActionPrompt } from '../../../cards/poker-renderer';
import type { CommandSpec } from '../../command-registry';
import { formatCards } from '../../output-formatter';
import { session } from '../../session';

export const pokerDeal: CommandSpec = {
  game: 'poker',
  action: 'deal',
  summary: 'Deal hole cards and post blinds for the next hand.',
  args: [],
  handler() {
    if (!session.pokerGame) return { error: 'No active game. Run: semantos game poker new' };
    try {
      session.pokerGame.startHand();
      const table = session.pokerGame.getTable();
      const players = session.pokerGame.getPlayers();
      const active = session.pokerGame.getActivePlayer();
      const holeCards = session.pokerGame.getHoleCards('player-0');
      return {
        table: renderPokerTable(table, players, 'player-0'),
        hand: holeCards.length > 0 ? `Your cards: ${formatCards(holeCards)}` : undefined,
        prompt: active ? renderActionPrompt(active, table) : undefined,
        phase: table.phase,
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
