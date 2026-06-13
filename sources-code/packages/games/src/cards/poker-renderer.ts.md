---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/poker-renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.411216+00:00
---

# packages/games/src/cards/poker-renderer.ts

```ts
/**
 * Poker Renderer — ASCII display for Texas Hold'em.
 *
 * Shows the table, community cards, pot, player chip counts,
 * and the active player's hole cards.
 */

import type { Card } from './types';
import type { PokerPlayer, PokerTable, GamePhase } from './poker-types';
import { HAND_RANK_NAMES, type EvaluatedHand } from './poker-types';
import { rankName, suitSymbol, formatHand } from './hand-evaluator';

// ── Card Display ────────────────────────────────────────────

const SUIT_SYMBOLS: Record<string, string> = {
  hearts: '\u2665',
  diamonds: '\u2666',
  clubs: '\u2663',
  spades: '\u2660',
};

function cardDisplay(card: Card, hidden = false): string {
  if (hidden) return '[??]';
  const r = rankName(card.rank);
  const s = SUIT_SYMBOLS[card.suit] ?? '?';
  return `[${r}${s}]`;
}

// ── Table Render ────────────────────────────────────────────

export function renderPokerTable(
  table: PokerTable,
  players: PokerPlayer[],
  viewerId?: string,
): string {
  const lines: string[] = [];
  const phase = table.phase;

  lines.push('╔══════════════════════════════════════════╗');
  lines.push(`║  Texas Hold'em NL  |  Hand #${table.handNumber}`.padEnd(43) + '║');
  lines.push('╠══════════════════════════════════════════╣');

  // Community cards
  const community = table.communityCards.map(c => cardDisplay(c)).join(' ');
  const boardLabel = phase === 'preflop' ? '(no cards yet)' : community;
  lines.push(`║  Board: ${boardLabel}`.padEnd(43) + '║');
  lines.push(`║  Pot: ${table.pot}`.padEnd(43) + '║');
  lines.push('╠══════════════════════════════════════════╣');

  // Players
  for (const p of players) {
    const isDealer = p.seat === table.dealerIndex;
    const isActive = p.seat === table.activeIndex && phase !== 'waiting' && phase !== 'hand-complete' && phase !== 'showdown';
    const marker = isDealer ? ' (D)' : '';
    const arrow = isActive ? ' <<' : '';
    const status = p.folded ? ' [FOLD]' : p.allIn ? ' [ALL-IN]' : '';

    // Show hole cards for viewer, hide others (except at showdown)
    let cards = '';
    if (p.holeCards.length > 0) {
      if (p.id === viewerId || phase === 'showdown' || phase === 'hand-complete') {
        cards = p.holeCards.map(c => cardDisplay(c)).join(' ');
      } else {
        cards = p.folded ? '' : '[??] [??]';
      }
    }

    const line = `║  ${p.name}${marker}: ${p.chips} chips${status} ${cards}${arrow}`;
    lines.push(line.padEnd(43) + '║');

    if (p.currentBet > 0) {
      lines.push(`║    bet: ${p.currentBet}`.padEnd(43) + '║');
    }
  }

  lines.push('╠══════════════════════════════════════════╣');

  // Phase
  const phaseDisplay: Record<GamePhase, string> = {
    waiting: 'Waiting for players...',
    preflop: 'Pre-Flop',
    flop: 'Flop',
    turn: 'Turn',
    river: 'River',
    showdown: 'Showdown!',
    'hand-complete': 'Hand Complete',
  };
  lines.push(`║  Phase: ${phaseDisplay[phase]}`.padEnd(43) + '║');
  lines.push('╚══════════════════════════════════════════╝');

  return lines.join('\n');
}

// ── Action Prompt ───────────────────────────────────────────

export function renderActionPrompt(
  player: PokerPlayer,
  table: PokerTable,
): string {
  const toCall = table.currentBet - player.currentBet;
  const parts: string[] = [];

  parts.push(`Your turn, ${player.name}. (${player.chips} chips)`);
  if (player.holeCards.length > 0) {
    parts.push(`Hand: ${player.holeCards.map(c => cardDisplay(c)).join(' ')}`);
  }

  if (toCall > 0) {
    parts.push(`To call: ${toCall}`);
    parts.push('Actions: fold | call | raise <amount> | all-in');
  } else {
    parts.push('Actions: check | bet <amount> | fold | all-in');
  }

  return parts.join('\n');
}

// ── Showdown Result ─────────────────────────────────────────

export function renderShowdown(
  players: PokerPlayer[],
  communityCards: Card[],
  evaluateHand: (playerId: string) => EvaluatedHand | null,
): string {
  const lines: string[] = [];
  lines.push('=== SHOWDOWN ===');
  lines.push(`Board: ${communityCards.map(c => cardDisplay(c)).join(' ')}`);
  lines.push('');

  for (const p of players) {
    if (p.folded) continue;
    const hand = evaluateHand(p.id);
    if (hand) {
      const holeStr = p.holeCards.map(c => cardDisplay(c)).join(' ');
      lines.push(`${p.name}: ${holeStr} => ${HAND_RANK_NAMES[hand.rank]} (${hand.description})`);
    }
  }

  return lines.join('\n');
}

// ── Player Status ───────────────────────────────────────────

export function renderPlayerStatus(player: PokerPlayer, hand?: EvaluatedHand | null): string {
  const parts: string[] = [];
  parts.push(`${player.name} | ${player.chips} chips | Seat ${player.seat}`);
  if (player.holeCards.length > 0) {
    parts.push(`Hand: ${player.holeCards.map(c => cardDisplay(c)).join(' ')}`);
  }
  if (hand) {
    parts.push(`Best: ${HAND_RANK_NAMES[hand.rank]} — ${hand.description}`);
  }
  if (player.folded) parts.push('[FOLDED]');
  if (player.allIn) parts.push('[ALL-IN]');
  return parts.join('\n');
}

```
