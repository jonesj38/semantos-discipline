---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/new.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.422489+00:00
---

# packages/games/src/cli/commands/poker/new.ts

```ts
/** `semantos game poker new` — create a poker table with N players. */

import { PokerEngine } from '../../../cards/poker';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

const PLAYER_NAMES = ['You', 'Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Hank'];

export const pokerNew: CommandSpec = {
  game: 'poker',
  action: 'new',
  summary: 'Create a Texas Hold\u2019em table with N players (1\u20139).',
  args: [
    { name: 'players', description: 'Number of seats (default 4, max 9).' },
    { name: 'sb', description: 'Small blind (default 5).' },
    { name: 'bb', description: 'Big blind (default 10).' },
    { name: 'chips', description: 'Starting chips per seat (default 1000).' },
  ],
  async handler(cmd) {
    const playerCount = Number(cmd.flags.players ?? cmd.flags.expression ?? 4);
    const smallBlind = Number(cmd.flags.sb ?? 5);
    const bigBlind = Number(cmd.flags.bb ?? 10);
    const chips = Number(cmd.flags.chips ?? 1000);

    session.pokerGame = await PokerEngine.create({ smallBlind, bigBlind, startingChips: chips });

    for (let i = 0; i < Math.min(playerCount, 9); i++) {
      session.pokerGame.addPlayer(PLAYER_NAMES[i]);
    }

    return {
      status: 'created',
      players: session.pokerGame.getPlayers().map((p) => ({ name: p.name, chips: p.chips })),
      blinds: `${smallBlind}/${bigBlind}`,
      message: `Poker table created with ${playerCount} players. Run: semantos game poker deal`,
    };
  },
};

```
