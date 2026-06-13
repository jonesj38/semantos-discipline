---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/status.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.422203+00:00
---

# packages/games/src/cli/commands/poker/status.ts

```ts
/** `semantos game poker status` — table-wide status report. */

import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const pokerStatus: CommandSpec = {
  game: 'poker',
  action: 'status',
  summary: 'Phase, pot, hand number, and per-player chip stacks.',
  args: [],
  handler() {
    if (!session.pokerGame) return { error: 'No active game. Run: semantos game poker new' };
    const table = session.pokerGame.getTable();
    const players = session.pokerGame.getPlayers();
    return {
      phase: table.phase,
      hand: table.handNumber,
      pot: table.pot,
      players: players.map((p) => ({
        name: p.name,
        chips: p.chips,
        folded: p.folded,
        allIn: p.allIn,
      })),
      historyLength: session.pokerGame.getHistory().length,
    };
  },
};

```
