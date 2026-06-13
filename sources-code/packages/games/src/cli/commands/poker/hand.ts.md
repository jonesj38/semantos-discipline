---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/hand.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.421029+00:00
---

# packages/games/src/cli/commands/poker/hand.ts

```ts
/** `semantos game poker hand` — describe your current best hand. */

import { HAND_RANK_NAMES } from '../../../cards/poker-types';
import type { CommandSpec } from '../../command-registry';
import { formatCards } from '../../output-formatter';
import { session } from '../../session';

export const pokerHand: CommandSpec = {
  game: 'poker',
  action: 'hand',
  summary: 'Show your hole cards and current best hand.',
  args: [],
  handler() {
    if (!session.pokerGame) return { error: 'No active game.' };
    const hand = session.pokerGame.evaluatePlayerHand('player-0');
    const holeCards = session.pokerGame.getHoleCards('player-0');
    return {
      holeCards: formatCards(holeCards),
      bestHand: hand ? `${HAND_RANK_NAMES[hand.rank]} \u2014 ${hand.description}` : '(not enough cards)',
      community: formatCards(session.pokerGame.getCommunityCards()),
    };
  },
};

```
