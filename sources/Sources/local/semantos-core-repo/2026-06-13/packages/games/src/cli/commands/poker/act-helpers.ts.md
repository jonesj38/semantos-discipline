---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/poker/act-helpers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.423373+00:00
---

# packages/games/src/cli/commands/poker/act-helpers.ts

```ts
/**
 * Shared helpers for the `fold|check|call|all-in|bet|raise` poker
 * commands. Each command file is a thin wrapper around `runSimpleAction`
 * (no amount) or `runAmountAction` (bet / raise).
 */

import { renderPokerTable } from '../../../cards/poker-renderer';
import type { PlayerActionType } from '../../../cards/poker-types';
import { session } from '../../session';
import { autoPlayAI } from './auto-play';

export async function runSimpleAction(
  type: PlayerActionType,
): Promise<Record<string, unknown>> {
  if (!session.pokerGame) return { error: 'No active game.' };
  const active = session.pokerGame.getActivePlayer();
  if (!active) return { error: 'No active player. Deal a new hand.' };

  const result = session.pokerGame.act(active.id, { type });
  const table = session.pokerGame.getTable();
  const players = session.pokerGame.getPlayers();

  const response: Record<string, unknown> = {
    action: result.message,
    table: renderPokerTable(table, players, 'player-0'),
    phase: table.phase,
    pot: table.pot,
  };

  await autoPlayAI(response);
  return response;
}

export async function runAmountAction(
  type: 'bet' | 'raise',
  amount: number,
): Promise<Record<string, unknown>> {
  if (!session.pokerGame) return { error: 'No active game.' };
  const active = session.pokerGame.getActivePlayer();
  if (!active) return { error: 'No active player.' };
  if (!amount) return { error: `Usage: semantos game poker ${type} --amount <chips>` };

  const result = session.pokerGame.act(active.id, { type, amount });
  const table = session.pokerGame.getTable();
  const players = session.pokerGame.getPlayers();

  const response: Record<string, unknown> = {
    action: result.message,
    table: renderPokerTable(table, players, 'player-0'),
    phase: table.phase,
    pot: table.pot,
  };

  await autoPlayAI(response);
  return response;
}

```
