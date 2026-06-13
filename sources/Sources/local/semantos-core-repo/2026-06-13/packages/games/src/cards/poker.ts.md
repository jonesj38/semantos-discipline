---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/poker.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.410360+00:00
---

# packages/games/src/cards/poker.ts

```ts
/**
 * Texas Hold'em No-Limit Poker Engine
 *
 * Built on the card framework — every card is a LINEAR cell.
 * Folded cards are consumed (LINEAR destruction).
 * Community cards are shared references.
 *
 * Supports:
 *   - 2-9 players
 *   - Blinds (small/big), dealer button rotation
 *   - Preflop, flop, turn, river betting rounds
 *   - No-limit betting (min raise = previous raise size)
 *   - All-in with side pot calculation
 *   - Showdown with best-5-of-7 hand evaluation
 *   - Board state as a RELEVANT cell DAG
 */

import { CardGameEngine } from './engine';
import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType } from '../../../game-sdk/src/types';
import type { Card, Deck } from './types';
import {
  type PokerPlayer,
  type PokerTable,
  type PokerAction,
  type PokerConfig,
  type SidePot,
  type ShowdownResult,
  type GamePhase,
  DEFAULT_POKER_CONFIG,
} from './poker-types';
import { evaluateHand, compareHands, type EvaluatedHand } from './hand-evaluator';

// ── Constants ──────────────────────────────────────────────

const RELEVANT = 3;
const TABLE_OWNER = new Uint8Array(16);
TABLE_OWNER[0] = 0x70;

// ── PokerEngine ────────────────────────────────────────────

export class PokerEngine {
  private cardEngine: CardGameEngine;
  private config: PokerConfig;
  private players: PokerPlayer[];
  private table: PokerTable;
  private deck: Deck;
  private lastBoardCell: Uint8Array | null = null;
  private dagHistory: string[] = [];

  private constructor(
    cardEngine: CardGameEngine,
    config: PokerConfig,
  ) {
    this.cardEngine = cardEngine;
    this.config = config;
    this.players = [];
    this.deck = { cards: [] };
    this.table = {
      smallBlind: config.smallBlind,
      bigBlind: config.bigBlind,
      dealerIndex: 0,
      activeIndex: 0,
      communityCards: [],
      phase: 'waiting',
      pot: 0,
      sidePots: [],
      currentBet: 0,
      minRaise: config.bigBlind,
      handNumber: 0,
      activePlayers: 0,
    };
  }

  /** Create a new poker game. */
  static async create(config?: Partial<PokerConfig>, opts?: CreateOptions): Promise<PokerEngine> {
    const fullConfig = { ...DEFAULT_POKER_CONFIG, ...config };
    const cardEngine = await CardGameEngine.create(opts);
    return new PokerEngine(cardEngine, fullConfig);
  }

  // ── Player Management ──────────────────────────────────────

  /** Add a player to the table. Returns seat index. */
  addPlayer(name: string, chips?: number): number {
    if (this.players.length >= this.config.maxPlayers) {
      throw new Error(`Table is full (max ${this.config.maxPlayers} players)`);
    }
    if (this.table.phase !== 'waiting' && this.table.phase !== 'hand-complete') {
      throw new Error('Cannot add player during a hand');
    }

    const seat = this.players.length;
    this.players.push({
      id: `player-${seat}`,
      name,
      chips: chips ?? this.config.startingChips,
      holeCards: [],
      currentBet: 0,
      folded: false,
      allIn: false,
      hasActed: false,
      seat,
    });
    return seat;
  }

  // ── Deal a New Hand ───────────────────────────────────────

  /** Start a new hand. Shuffles deck, posts blinds, deals hole cards. */
  startHand(): void {
    const eligible = this.players.filter(p => p.chips > 0);
    if (eligible.length < 2) {
      throw new Error('Need at least 2 players with chips to start a hand');
    }

    // Reset state
    this.table.handNumber++;
    this.table.communityCards = [];
    this.table.pot = 0;
    this.table.sidePots = [];
    this.table.currentBet = 0;
    this.table.minRaise = this.config.bigBlind;
    this.table.phase = 'preflop';

    for (const p of this.players) {
      p.holeCards = [];
      p.currentBet = 0;
      p.folded = p.chips === 0; // busted players are auto-folded
      p.allIn = false;
      p.hasActed = false;
    }

    this.table.activePlayers = this.players.filter(p => !p.folded).length;

    // Rotate dealer
    if (this.table.handNumber > 1) {
      this.table.dealerIndex = this.nextActivePlayer(this.table.dealerIndex);
    }

    // Create and shuffle deck (52 LINEAR cells)
    this.deck = this.cardEngine.createDeck();
    this.deck = this.cardEngine.shuffle(this.deck);

    // Post blinds
    this.postBlinds();

    // Deal 2 hole cards to each active player
    for (const p of this.players) {
      if (!p.folded) {
        const { dealt, remaining } = this.cardEngine.deal(this.deck, 2);
        p.holeCards = dealt;
        this.deck = remaining;
      }
    }

    // Set active player (left of big blind for preflop)
    const bbIndex = this.players.length === 2
      ? this.table.dealerIndex // heads-up: dealer is SB, other is BB
      : this.nextActivePlayer(this.nextActivePlayer(this.table.dealerIndex));
    this.table.activeIndex = this.nextActivePlayer(bbIndex);

    this.commitState();
  }

  private postBlinds(): void {
    let sbIndex: number;
    let bbIndex: number;

    if (this.players.filter(p => !p.folded).length === 2) {
      // Heads-up: dealer is small blind
      sbIndex = this.table.dealerIndex;
      bbIndex = this.nextActivePlayer(sbIndex);
    } else {
      sbIndex = this.nextActivePlayer(this.table.dealerIndex);
      bbIndex = this.nextActivePlayer(sbIndex);
    }

    this.placeBet(this.players[sbIndex], this.config.smallBlind);
    this.placeBet(this.players[bbIndex], this.config.bigBlind);
    this.table.currentBet = this.config.bigBlind;
  }

  private placeBet(player: PokerPlayer, amount: number): number {
    const actual = Math.min(amount, player.chips);
    player.chips -= actual;
    player.currentBet += actual;
    this.table.pot += actual;
    if (player.chips === 0) player.allIn = true;
    return actual;
  }

  // ── Player Actions ────────────────────────────────────────

  /** Get the player whose turn it is. */
  getActivePlayer(): PokerPlayer | null {
    if (this.table.phase === 'waiting' || this.table.phase === 'hand-complete' || this.table.phase === 'showdown') {
      return null;
    }
    return this.players[this.table.activeIndex] ?? null;
  }

  /** Execute a player action. Returns true if the action was valid. */
  act(playerId: string, action: PokerAction): { success: boolean; message: string } {
    const player = this.players.find(p => p.id === playerId);
    if (!player) return { success: false, message: 'Player not found' };
    if (player.id !== this.players[this.table.activeIndex]?.id) {
      return { success: false, message: 'Not your turn' };
    }
    if (player.folded || player.allIn) {
      return { success: false, message: 'Cannot act (folded or all-in)' };
    }

    let msg: string;

    switch (action.type) {
      case 'fold':
        msg = this.handleFold(player);
        break;
      case 'check':
        msg = this.handleCheck(player);
        if (!msg) return { success: false, message: 'Cannot check — there is a bet to you' };
        break;
      case 'call':
        msg = this.handleCall(player);
        break;
      case 'bet':
        msg = this.handleBet(player, action.amount ?? this.config.bigBlind);
        if (!msg) return { success: false, message: `Invalid bet amount` };
        break;
      case 'raise':
        msg = this.handleRaise(player, action.amount ?? 0);
        if (!msg) return { success: false, message: `Invalid raise amount` };
        break;
      case 'all-in':
        msg = this.handleAllIn(player);
        break;
      default:
        return { success: false, message: `Unknown action: ${action.type}` };
    }

    // Advance to next player or next phase
    this.advance();
    this.commitState();

    return { success: true, message: msg };
  }

  private handleFold(player: PokerPlayer): string {
    player.folded = true;
    player.hasActed = true;
    this.table.activePlayers--;

    // Consume folded hole cards (LINEAR destruction)
    for (const card of player.holeCards) {
      this.cardEngine.playCard(card);
    }

    return `${player.name} folds.`;
  }

  private handleCheck(player: PokerPlayer): string {
    if (player.currentBet < this.table.currentBet) return '';
    player.hasActed = true;
    return `${player.name} checks.`;
  }

  private handleCall(player: PokerPlayer): string {
    const toCall = this.table.currentBet - player.currentBet;
    const actual = this.placeBet(player, toCall);
    player.hasActed = true;
    return `${player.name} calls ${actual}.`;
  }

  private handleBet(player: PokerPlayer, amount: number): string {
    if (this.table.currentBet > 0) return ''; // must raise, not bet
    if (amount < this.config.bigBlind && amount < player.chips) return '';

    const actual = this.placeBet(player, amount);
    this.table.currentBet = player.currentBet;
    this.table.minRaise = actual;
    player.hasActed = true;
    this.resetActedFlags(player);
    return `${player.name} bets ${actual}.`;
  }

  private handleRaise(player: PokerPlayer, totalAmount: number): string {
    const toCall = this.table.currentBet - player.currentBet;
    const raiseBy = totalAmount - this.table.currentBet;

    // Minimum raise check (unless going all-in)
    if (raiseBy < this.table.minRaise && totalAmount < player.chips + player.currentBet) return '';
    if (totalAmount <= this.table.currentBet) return '';

    const toWager = totalAmount - player.currentBet;
    const actual = this.placeBet(player, toWager);
    this.table.currentBet = player.currentBet;
    this.table.minRaise = Math.max(this.table.minRaise, player.currentBet - (this.table.currentBet - this.table.minRaise));
    player.hasActed = true;
    this.resetActedFlags(player);
    return `${player.name} raises to ${player.currentBet}.`;
  }

  private handleAllIn(player: PokerPlayer): string {
    const amount = player.chips;
    this.placeBet(player, amount);
    player.hasActed = true;

    if (player.currentBet > this.table.currentBet) {
      this.table.minRaise = Math.max(this.table.minRaise, player.currentBet - this.table.currentBet);
      this.table.currentBet = player.currentBet;
      this.resetActedFlags(player);
    }

    return `${player.name} goes all-in for ${amount}!`;
  }

  private resetActedFlags(actor: PokerPlayer): void {
    for (const p of this.players) {
      if (p.id !== actor.id && !p.folded && !p.allIn) {
        p.hasActed = false;
      }
    }
  }

  // ── Round Advancement ─────────────────────────────────────

  private advance(): void {
    // Check if only one player remains
    if (this.table.activePlayers <= 1) {
      this.awardPotToLastPlayer();
      return;
    }

    // Check if all active (non-all-in, non-folded) players have acted
    const needToAct = this.players.filter(p => !p.folded && !p.allIn && !p.hasActed);
    if (needToAct.length > 0) {
      this.table.activeIndex = this.nextActivePlayer(this.table.activeIndex);
      return;
    }

    // Check if only one non-all-in player remains (or all are all-in)
    const canAct = this.players.filter(p => !p.folded && !p.allIn);
    if (canAct.length <= 1) {
      // Everyone is all-in or folded — deal remaining community cards
      this.dealRemainingCards();
      return;
    }

    // All active players have acted — move to next phase
    this.nextPhase();
  }

  private nextPhase(): void {
    // Reset for next betting round
    for (const p of this.players) {
      p.currentBet = 0;
      p.hasActed = false;
    }
    this.table.currentBet = 0;
    this.table.minRaise = this.config.bigBlind;

    switch (this.table.phase) {
      case 'preflop':
        this.table.phase = 'flop';
        this.dealCommunity(3);
        break;
      case 'flop':
        this.table.phase = 'turn';
        this.dealCommunity(1);
        break;
      case 'turn':
        this.table.phase = 'river';
        this.dealCommunity(1);
        break;
      case 'river':
        this.showdown();
        return;
    }

    // Set active player (left of dealer post-flop)
    this.table.activeIndex = this.nextActivePlayer(this.table.dealerIndex);
  }

  private dealCommunity(count: number): void {
    // Burn a card
    if (this.deck.cards.length > count) {
      const { dealt: burned, remaining } = this.cardEngine.deal(this.deck, 1);
      this.cardEngine.playCard(burned[0]); // burn = consumed
      this.deck = remaining;
    }

    const { dealt, remaining } = this.cardEngine.deal(this.deck, count);
    for (const card of dealt) {
      card.faceUp = true;
    }
    this.table.communityCards.push(...dealt);
    this.deck = remaining;
  }

  private dealRemainingCards(): void {
    // Deal remaining community cards without betting
    while (this.table.communityCards.length < 5 && this.deck.cards.length > 1) {
      this.dealCommunity(this.table.communityCards.length === 0 ? 3 : 1);
    }
    this.showdown();
  }

  // ── Showdown ──────────────────────────────────────────────

  private showdown(): void {
    this.table.phase = 'showdown';

    // Calculate side pots first
    const pots = this.calculateSidePots();

    // Evaluate hands for all non-folded players
    const hands: { playerId: string; hand: EvaluatedHand }[] = [];
    for (const p of this.players) {
      if (!p.folded && p.holeCards.length === 2) {
        const allCards = [...p.holeCards, ...this.table.communityCards];
        const hand = evaluateHand(allCards);
        hands.push({ playerId: p.id, hand });
      }
    }

    const winners: ShowdownResult['winners'] = [];

    // Award each pot to the best hand among eligible players
    for (const pot of pots) {
      const eligible = hands.filter(h => pot.eligible.includes(h.playerId));
      if (eligible.length === 0) continue;

      // Sort by hand strength, best first
      eligible.sort((a, b) => compareHands(b.hand, a.hand));
      const bestHand = eligible[0].hand;

      // Find all players tied for the best hand
      const potWinners = eligible.filter(h => compareHands(h.hand, bestHand) === 0);
      const share = Math.floor(pot.amount / potWinners.length);
      let remainder = pot.amount - share * potWinners.length;

      for (const w of potWinners) {
        const player = this.players.find(p => p.id === w.playerId)!;
        const won = share + (remainder > 0 ? 1 : 0);
        if (remainder > 0) remainder--;
        player.chips += won;
        winners.push({ playerId: w.playerId, hand: w.hand, potWon: won });
      }
    }

    this.table.phase = 'hand-complete';
    this.table.pot = 0;

    // Consume remaining cards in deck
    for (const card of this.deck.cards) {
      this.cardEngine.playCard(card);
    }

    // Consume losing players' hole cards
    for (const p of this.players) {
      if (!p.folded) {
        for (const card of p.holeCards) {
          if (!this.cardEngine.isConsumed(card.entity.id)) {
            this.cardEngine.playCard(card);
          }
        }
      }
    }

    // Consume community cards
    for (const card of this.table.communityCards) {
      if (!this.cardEngine.isConsumed(card.entity.id)) {
        this.cardEngine.playCard(card);
      }
    }
  }

  private awardPotToLastPlayer(): void {
    const winner = this.players.find(p => !p.folded);
    if (winner) {
      winner.chips += this.table.pot;
    }
    this.table.pot = 0;
    this.table.phase = 'hand-complete';

    // Consume remaining deck + community cards
    for (const card of this.deck.cards) {
      if (!this.cardEngine.isConsumed(card.entity.id)) {
        this.cardEngine.playCard(card);
      }
    }
    for (const card of this.table.communityCards) {
      if (!this.cardEngine.isConsumed(card.entity.id)) {
        this.cardEngine.playCard(card);
      }
    }
    // Winner's hole cards are also consumed (hand is over)
    if (winner) {
      for (const card of winner.holeCards) {
        if (!this.cardEngine.isConsumed(card.entity.id)) {
          this.cardEngine.playCard(card);
        }
      }
    }
  }

  private calculateSidePots(): SidePot[] {
    // Collect all bets
    const betters = this.players
      .filter(p => !p.folded || p.currentBet > 0)
      .map(p => ({ id: p.id, totalBet: p.currentBet, folded: p.folded }));

    // For simplicity with single pot (no all-in), return main pot
    // When there are all-in players, calculate proper side pots
    const allInAmounts = this.players
      .filter(p => p.allIn && !p.folded)
      .map(p => p.currentBet)
      .sort((a, b) => a - b);

    if (allInAmounts.length === 0) {
      // Simple case: one main pot
      return [{
        amount: this.table.pot,
        eligible: this.players.filter(p => !p.folded).map(p => p.id),
      }];
    }

    // Build side pots from all-in levels
    const pots: SidePot[] = [];
    let processedAmount = 0;

    const uniqueAmounts = [...new Set(allInAmounts)];

    for (const level of uniqueAmounts) {
      const contribution = level - processedAmount;
      const eligible = this.players.filter(p => !p.folded && p.currentBet >= level).map(p => p.id);
      const contributors = this.players.filter(p => p.currentBet > processedAmount);
      const potSize = contributors.reduce((sum, p) => sum + Math.min(contribution, p.currentBet - processedAmount), 0);

      if (potSize > 0) {
        pots.push({ amount: potSize, eligible });
      }
      processedAmount = level;
    }

    // Remaining pot for non-all-in players
    const remaining = this.table.pot - pots.reduce((sum, p) => sum + p.amount, 0);
    if (remaining > 0) {
      const eligible = this.players.filter(p => !p.folded && !p.allIn).map(p => p.id);
      if (eligible.length === 0) {
        // All remaining eligible are all-in players at the highest level
        const highestAllIn = this.players.filter(p => !p.folded).map(p => p.id);
        pots.push({ amount: remaining, eligible: highestAllIn });
      } else {
        pots.push({ amount: remaining, eligible });
      }
    }

    return pots;
  }

  // ── Navigation Helpers ────────────────────────────────────

  private nextActivePlayer(fromIndex: number): number {
    let idx = (fromIndex + 1) % this.players.length;
    let safety = this.players.length;
    while (safety-- > 0) {
      if (!this.players[idx].folded && this.players[idx].chips >= 0) {
        return idx;
      }
      idx = (idx + 1) % this.players.length;
    }
    return fromIndex;
  }

  // ── State Persistence (DAG) ───────────────────────────────

  private commitState(): void {
    const boardEntity = this.cardEngine.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: TABLE_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'poker-table',
        hand: this.table.handNumber,
        phase: this.table.phase,
        pot: this.table.pot,
        community: this.table.communityCards.length,
        active: this.table.activePlayers,
      },
      state: 'active',
      prevCell: this.lastBoardCell ?? undefined,
    });

    this.lastBoardCell = boardEntity.cell;
    this.dagHistory.push(boardEntity.id);
  }

  // ── Public Accessors ──────────────────────────────────────

  getTable(): PokerTable { return { ...this.table }; }
  getPlayers(): PokerPlayer[] { return this.players.map(p => ({ ...p, holeCards: [...p.holeCards] })); }
  getPlayer(id: string): PokerPlayer | undefined { return this.players.find(p => p.id === id); }
  getCommunityCards(): Card[] { return [...this.table.communityCards]; }
  getHistory(): string[] { return [...this.dagHistory]; }
  getPhase(): GamePhase { return this.table.phase; }
  getPot(): number { return this.table.pot; }

  /** Get a player's hole cards (only visible to that player). */
  getHoleCards(playerId: string): Card[] {
    const player = this.players.find(p => p.id === playerId);
    return player ? [...player.holeCards] : [];
  }

  /** Evaluate a player's current best hand (if community cards are dealt). */
  evaluatePlayerHand(playerId: string): EvaluatedHand | null {
    const player = this.players.find(p => p.id === playerId);
    if (!player || player.folded || player.holeCards.length < 2) return null;
    const allCards = [...player.holeCards, ...this.table.communityCards];
    if (allCards.length < 5) return null;
    return evaluateHand(allCards);
  }

  /** Get legal actions for the active player. */
  getLegalActions(): PokerAction[] {
    const player = this.getActivePlayer();
    if (!player) return [];

    const actions: PokerAction[] = [];
    const toCall = this.table.currentBet - player.currentBet;

    actions.push({ type: 'fold' });

    if (toCall === 0) {
      actions.push({ type: 'check' });
      // Can bet (no current bet)
      actions.push({ type: 'bet', amount: this.config.bigBlind });
    } else {
      actions.push({ type: 'call', amount: toCall });
      // Can raise
      const minRaiseTotal = this.table.currentBet + this.table.minRaise;
      if (player.chips + player.currentBet > this.table.currentBet) {
        actions.push({ type: 'raise', amount: Math.min(minRaiseTotal, player.chips + player.currentBet) });
      }
    }

    actions.push({ type: 'all-in', amount: player.chips });

    return actions;
  }
}

```
