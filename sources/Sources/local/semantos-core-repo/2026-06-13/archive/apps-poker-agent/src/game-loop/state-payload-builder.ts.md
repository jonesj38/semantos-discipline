---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/state-payload-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.780777+00:00
---

# archive/apps-poker-agent/src/game-loop/state-payload-builder.ts

```ts
/**
 * Pure HandStatePayload + GameEvent shaping helpers shared by the
 * pre-hand setup, phase loop, and post-hand flows.
 */

import type { AnchorResult, HandStatePayload, PokerPhase } from '../poker-state-machine';

import type { HandResult, SimplePlayer, SimpleTable, GameLoopConfig } from './types';

export interface BuildStateArgs {
  config: GameLoopConfig;
  players: SimplePlayer[];
  table: SimpleTable;
  phase: PokerPhase;
  actions: HandResult['actions'];
}

export function buildState(args: BuildStateArgs): HandStatePayload {
  return {
    gameId: args.config.gameId,
    handNumber: args.table.handNumber,
    phase: args.phase,
    dealer: args.players[args.table.dealerIndex].name,
    players: args.players.map((p) => ({
      name: p.name,
      chips: p.chips,
      folded: p.folded,
      allIn: p.allIn,
    })),
    pot: args.table.pot,
    communityCards: args.table.communityCards.map((c) => c.label),
    currentBet: args.table.currentBet,
    actions: [...args.actions],
  };
}

export interface EmitTxArgs {
  log: (label: string, msg: string) => void;
  emit: (
    type: 'hand-start' | 'deal' | 'phase' | 'action' | 'tx' | 'hand-end' | 'game-over',
    data: Record<string, unknown>,
  ) => void;
  anchor: AnchorResult;
  label: string;
  version: number;
}

export function emitTx(args: EmitTxArgs): void {
  args.log(
    'TX',
    `\x1b[32m✓ CellToken v${args.version}\x1b[0m ${args.anchor.txid} \x1b[90m(${args.label})\x1b[0m`,
  );
  args.log('TX', `  https://whatsonchain.com/tx/${args.anchor.txid}`);
  args.emit('tx', {
    txid: args.anchor.txid,
    kind: 'celltoken',
    label: args.label,
    version: args.version,
    kernelValidated: args.anchor.kernelValidated ?? false,
    kernelOpcodeCount: args.anchor.kernelOpcodeCount ?? 0,
  });
}

export function placeBlind(player: SimplePlayer, table: SimpleTable, amount: number): void {
  const actual = Math.min(amount, player.chips);
  player.chips -= actual;
  player.currentBet += actual;
  table.pot += actual;
  if (player.chips === 0) player.allIn = true;
}

```
