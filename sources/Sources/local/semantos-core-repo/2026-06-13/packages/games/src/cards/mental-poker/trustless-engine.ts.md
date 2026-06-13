---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/mental-poker/trustless-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.435473+00:00
---

# packages/games/src/cards/mental-poker/trustless-engine.ts

```ts
/**
 * TrustlessPokerEngine — Texas Hold'em with mental poker cryptography.
 *
 * Wraps the regular PokerEngine with the SRA mental poker protocol:
 *   - No single party can see any card until legitimately revealed
 *   - Every shuffle, deal, and reveal produces a cryptographic proof
 *   - All proofs are stored as RELEVANT cells in the DAG
 *   - Full game can be verified post-hoc by replaying the protocol
 *
 * Architecture:
 *   MentalPokerProtocol (crypto layer)
 *     ↓ card identities
 *   PokerEngine (game logic)
 *     ↓ entity cells
 *   GameCellEngine (cell persistence)
 *     ↓ StorageAdapter
 *   CellStore (Merkle-chained DAG)
 *
 * Trust model:
 *   - Card secrecy: guaranteed by SRA commutative encryption
 *   - Shuffle fairness: guaranteed by sequential encrypt-and-shuffle
 *   - No duplication: guaranteed by LINEAR cell semantics
 *   - Tamper evidence: guaranteed by Merkle-chained DAG
 *   - Verifiability: guaranteed by key reveal + proof replay
 */

import { GameCellEngine, type CreateOptions } from '../../../../game-sdk/src/engine';
import { GameEntityType } from '../../../../game-sdk/src/types';
import { MentalPokerProtocol } from './protocol';
import { bigintToHex } from './crypto';
import type {
  PlayerKeyPair,
  ShuffleProof,
  DecryptionProof,
  KeyRevealProof,
  CardIdentity,
  VerificationResult,
} from './types';
import type { PokerConfig, ShowdownResult, GamePhase, EvaluatedHand } from '../poker-types';
import { DEFAULT_POKER_CONFIG, HAND_RANK_NAMES } from '../poker-types';
import { evaluateHand, compareHands } from '../hand-evaluator';
import type { Card, Suit, Rank } from '../types';
import { SUITS, RANKS } from '../types';

// ── Constants ──────────────────────────────────────────────

const RELEVANT = 3;
const PROOF_OWNER = new Uint8Array(16);
PROOF_OWNER[0] = 0x80;

// ── Player State ───────────────────────────────────────────

interface TrustlessPlayer {
  id: string;
  name: string;
  chips: number;
  keyPair: PlayerKeyPair;
  /** Card positions in the shuffled deck (assigned during deal). */
  holeCardPositions: number[];
  /** Revealed card identities (only the player knows these until showdown). */
  holeCardIdentities: CardIdentity[];
  currentBet: number;
  folded: boolean;
  allIn: boolean;
  hasActed: boolean;
}

// ── TrustlessPokerEngine ───────────────────────────────────

export class TrustlessPokerEngine {
  private protocol: MentalPokerProtocol;
  private cellEngine: GameCellEngine;
  private config: PokerConfig;
  private players: TrustlessPlayer[];
  private communityPositions: number[];
  private communityIdentities: CardIdentity[];
  private burnPositions: number[];
  private dealerIndex: number;
  private activeIndex: number;
  private pot: number;
  private currentBet: number;
  private minRaise: number;
  private phase: GamePhase;
  private handNumber: number;
  private nextCardPosition: number;
  private lastProofCell: Uint8Array | null = null;
  private dagHistory: string[] = [];

  private constructor(
    protocol: MentalPokerProtocol,
    cellEngine: GameCellEngine,
    config: PokerConfig,
  ) {
    this.protocol = protocol;
    this.cellEngine = cellEngine;
    this.config = config;
    this.players = [];
    this.communityPositions = [];
    this.communityIdentities = [];
    this.burnPositions = [];
    this.dealerIndex = 0;
    this.activeIndex = 0;
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = config.bigBlind;
    this.phase = 'waiting';
    this.handNumber = 0;
    this.nextCardPosition = 0;
  }

  /**
   * Create a new trustless poker engine.
   * Initializes the mental poker protocol and cell engine.
   */
  static async create(
    config?: Partial<PokerConfig>,
    opts?: CreateOptions,
  ): Promise<TrustlessPokerEngine> {
    const fullConfig = { ...DEFAULT_POKER_CONFIG, ...config };
    const cellEngine = await GameCellEngine.create(opts);
    const protocol = MentalPokerProtocol.create();
    return new TrustlessPokerEngine(protocol, cellEngine, fullConfig);
  }

  // ── Player Management ──────────────────────────────────────

  /**
   * Add a player. Generates their SRA key pair and commits the
   * key hash to the protocol. Returns the key pair (keep secret!).
   */
  addPlayer(name: string, chips?: number): PlayerKeyPair {
    if (this.players.length >= this.config.maxPlayers) {
      throw new Error(`Table full (max ${this.config.maxPlayers})`);
    }

    const playerId = `player-${this.players.length}`;
    const keyPair = this.protocol.registerPlayer(playerId);

    this.players.push({
      id: playerId,
      name,
      chips: chips ?? this.config.startingChips,
      keyPair,
      holeCardPositions: [],
      holeCardIdentities: [],
      currentBet: 0,
      folded: false,
      allIn: false,
      hasActed: false,
    });

    // Commit key registration as a proof cell
    this.commitProof('key-registration', {
      playerId,
      keyCommitment: keyPair.keyCommitment,
    });

    return keyPair;
  }

  // ── Deal a Hand ────────────────────────────────────────────

  /**
   * Start a new hand with the full mental poker protocol:
   *   1. Each player encrypts and shuffles the deck in sequence
   *   2. Hole cards are dealt via selective decryption
   *   3. Blinds are posted
   */
  startHand(): { shuffleProofs: ShuffleProof[] } {
    const activePlayers = this.players.filter(p => p.chips > 0);
    if (activePlayers.length < 2) {
      throw new Error('Need at least 2 players with chips');
    }

    // Reset
    this.handNumber++;
    this.protocol = MentalPokerProtocol.create();
    this.communityPositions = [];
    this.communityIdentities = [];
    this.burnPositions = [];
    this.pot = 0;
    this.currentBet = 0;
    this.minRaise = this.config.bigBlind;
    this.nextCardPosition = 0;

    // Re-register all players with new keys for this hand
    for (const p of this.players) {
      p.keyPair = this.protocol.registerPlayer(p.id);
      p.holeCardPositions = [];
      p.holeCardIdentities = [];
      p.currentBet = 0;
      p.folded = p.chips === 0;
      p.allIn = false;
      p.hasActed = false;
    }

    // Rotate dealer
    if (this.handNumber > 1) {
      this.dealerIndex = this.nextActive(this.dealerIndex);
    }

    // Step 2: Each player encrypts and shuffles in sequence
    const shuffleProofs: ShuffleProof[] = [];
    for (const p of this.players) {
      if (!p.folded) {
        const proof = this.protocol.encryptAndShuffle(p.id);
        shuffleProofs.push(proof);

        // Commit shuffle proof as a cell
        this.commitProof('shuffle', {
          playerId: p.id,
          inputCommitment: proof.inputCommitment,
          outputCommitment: proof.outputCommitment,
        });
      }
    }

    // Step 3: Deal hole cards via selective decryption
    for (const p of this.players) {
      if (p.folded) continue;

      const pos1 = this.nextCardPosition++;
      const pos2 = this.nextCardPosition++;
      p.holeCardPositions = [pos1, pos2];

      // Other players decrypt their layer for these positions
      p.holeCardIdentities = this.protocol.dealHoleCards(p.id, [pos1, pos2]);
    }

    // Post blinds
    this.postBlinds();
    this.phase = 'preflop';

    // Set active player
    const bbIndex = this.players.length === 2
      ? this.dealerIndex
      : this.nextActive(this.nextActive(this.dealerIndex));
    this.activeIndex = this.nextActive(bbIndex);

    this.commitProof('hand-started', {
      handNumber: this.handNumber,
      dealerIndex: this.dealerIndex,
      players: this.players.filter(p => !p.folded).map(p => p.id),
    });

    return { shuffleProofs };
  }

  private postBlinds(): void {
    const active = this.players.filter(p => !p.folded);
    let sbIdx: number, bbIdx: number;

    if (active.length === 2) {
      sbIdx = this.dealerIndex;
      bbIdx = this.nextActive(sbIdx);
    } else {
      sbIdx = this.nextActive(this.dealerIndex);
      bbIdx = this.nextActive(sbIdx);
    }

    this.placeBet(this.players[sbIdx], this.config.smallBlind);
    this.placeBet(this.players[bbIdx], this.config.bigBlind);
    this.currentBet = this.config.bigBlind;
  }

  private placeBet(player: TrustlessPlayer, amount: number): number {
    const actual = Math.min(amount, player.chips);
    player.chips -= actual;
    player.currentBet += actual;
    this.pot += actual;
    if (player.chips === 0) player.allIn = true;
    return actual;
  }

  // ── Betting Actions ───────────────────────────────────────

  act(playerId: string, action: { type: string; amount?: number }): { success: boolean; message: string } {
    const player = this.players.find(p => p.id === playerId);
    if (!player) return { success: false, message: 'Player not found' };
    if (player.id !== this.players[this.activeIndex]?.id) {
      return { success: false, message: 'Not your turn' };
    }
    if (player.folded || player.allIn) {
      return { success: false, message: 'Cannot act' };
    }

    let msg: string;

    switch (action.type) {
      case 'fold':
        player.folded = true;
        player.hasActed = true;
        msg = `${player.name} folds.`;
        break;
      case 'check':
        if (player.currentBet < this.currentBet) {
          return { success: false, message: 'Cannot check — there is a bet to you' };
        }
        player.hasActed = true;
        msg = `${player.name} checks.`;
        break;
      case 'call': {
        const toCall = this.currentBet - player.currentBet;
        const actual = this.placeBet(player, toCall);
        player.hasActed = true;
        msg = `${player.name} calls ${actual}.`;
        break;
      }
      case 'raise': {
        const total = action.amount ?? this.currentBet + this.minRaise;
        const toWager = total - player.currentBet;
        this.placeBet(player, toWager);
        this.currentBet = player.currentBet;
        this.minRaise = Math.max(this.minRaise, player.currentBet - this.currentBet + this.minRaise);
        player.hasActed = true;
        this.resetActed(player);
        msg = `${player.name} raises to ${player.currentBet}.`;
        break;
      }
      case 'all-in': {
        const amount = player.chips;
        this.placeBet(player, amount);
        if (player.currentBet > this.currentBet) {
          this.minRaise = Math.max(this.minRaise, player.currentBet - this.currentBet);
          this.currentBet = player.currentBet;
          this.resetActed(player);
        }
        player.hasActed = true;
        msg = `${player.name} goes all-in for ${amount}!`;
        break;
      }
      default:
        return { success: false, message: `Unknown action: ${action.type}` };
    }

    this.commitProof('action', { playerId, action: action.type, amount: action.amount });
    this.advance();
    return { success: true, message: msg };
  }

  private resetActed(actor: TrustlessPlayer): void {
    for (const p of this.players) {
      if (p.id !== actor.id && !p.folded && !p.allIn) p.hasActed = false;
    }
  }

  private advance(): void {
    const activePlayers = this.players.filter(p => !p.folded);
    if (activePlayers.length <= 1) {
      this.awardToLast();
      return;
    }

    const needToAct = this.players.filter(p => !p.folded && !p.allIn && !p.hasActed);
    if (needToAct.length > 0) {
      this.activeIndex = this.nextActive(this.activeIndex);
      return;
    }

    const canAct = this.players.filter(p => !p.folded && !p.allIn);
    if (canAct.length <= 1) {
      this.dealRemaining();
      return;
    }

    this.nextPhase();
  }

  private nextPhase(): void {
    for (const p of this.players) {
      p.currentBet = 0;
      p.hasActed = false;
    }
    this.currentBet = 0;
    this.minRaise = this.config.bigBlind;

    switch (this.phase) {
      case 'preflop':
        this.phase = 'flop';
        this.dealCommunity(3);
        break;
      case 'flop':
        this.phase = 'turn';
        this.dealCommunity(1);
        break;
      case 'turn':
        this.phase = 'river';
        this.dealCommunity(1);
        break;
      case 'river':
        this.showdown();
        return;
    }

    this.activeIndex = this.nextActive(this.dealerIndex);
  }

  /**
   * Deal community cards using the mental poker protocol.
   * All players decrypt → cards are publicly revealed.
   */
  private dealCommunity(count: number): void {
    // Burn a card (all players decrypt, but we don't record the identity)
    const burnPos = this.nextCardPosition++;
    this.burnPositions.push(burnPos);
    this.protocol.revealCard(burnPos);

    for (let i = 0; i < count; i++) {
      const pos = this.nextCardPosition++;
      this.communityPositions.push(pos);
      const identity = this.protocol.revealCard(pos);
      this.communityIdentities.push(identity);
    }

    this.commitProof('community-dealt', {
      phase: this.phase,
      cards: this.communityIdentities.slice(-count).map(c => ({
        suit: c.suit,
        rank: c.rank,
      })),
    });
  }

  private dealRemaining(): void {
    while (this.communityIdentities.length < 5) {
      this.dealCommunity(this.communityIdentities.length === 0 ? 3 : 1);
    }
    this.showdown();
  }

  // ── Showdown ──────────────────────────────────────────────

  private showdown(): void {
    this.phase = 'showdown';

    // Players reveal their keys for verification
    const reveals: KeyRevealProof[] = [];
    for (const p of this.players) {
      if (!p.folded) {
        reveals.push(this.protocol.revealKey(p.id));
      }
    }

    // Evaluate hands
    const results: { playerId: string; name: string; hand: EvaluatedHand }[] = [];
    for (const p of this.players) {
      if (p.folded || p.holeCardIdentities.length < 2) continue;

      const holeCards = p.holeCardIdentities.map(identityToCard);
      const communityCards = this.communityIdentities.map(identityToCard);
      const allCards = [...holeCards, ...communityCards];
      const hand = evaluateHand(allCards);
      results.push({ playerId: p.id, name: p.name, hand });
    }

    // Award pot to best hand
    if (results.length > 0) {
      results.sort((a, b) => compareHands(b.hand, a.hand));
      const best = results[0].hand;
      const winners = results.filter(r => compareHands(r.hand, best) === 0);
      const share = Math.floor(this.pot / winners.length);

      for (const w of winners) {
        const player = this.players.find(p => p.id === w.playerId)!;
        player.chips += share;
      }
    }

    this.commitProof('showdown', {
      hands: results.map(r => ({
        playerId: r.playerId,
        hand: HAND_RANK_NAMES[r.hand.rank],
        description: r.hand.description,
      })),
      keyReveals: reveals.length,
    });

    this.phase = 'hand-complete';
    this.pot = 0;
  }

  private awardToLast(): void {
    const winner = this.players.find(p => !p.folded);
    if (winner) winner.chips += this.pot;
    this.pot = 0;
    this.phase = 'hand-complete';
  }

  // ── Verification ──────────────────────────────────────────

  /**
   * Verify the entire game's cryptographic integrity.
   * Replays all protocol steps and checks commitments.
   */
  verify(): VerificationResult {
    return this.protocol.verify();
  }

  // ── Proof Cell DAG ────────────────────────────────────────

  private commitProof(proofType: string, data: Record<string, unknown>): void {
    const entity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: PROOF_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'mental-poker-proof',
        proofType,
        handNumber: this.handNumber,
        ...data,
      },
      state: 'committed',
      prevCell: this.lastProofCell ?? undefined,
    });

    this.lastProofCell = entity.cell;
    this.dagHistory.push(entity.id);
  }

  // ── Navigation ────────────────────────────────────────────

  private nextActive(from: number): number {
    let idx = (from + 1) % this.players.length;
    let safety = this.players.length;
    while (safety-- > 0) {
      if (!this.players[idx].folded) return idx;
      idx = (idx + 1) % this.players.length;
    }
    return from;
  }

  // ── Accessors ─────────────────────────────────────────────

  getPhase(): GamePhase { return this.phase; }
  getPot(): number { return this.pot; }
  getHandNumber(): number { return this.handNumber; }
  getDagHistory(): string[] { return [...this.dagHistory]; }

  getPlayers() {
    return this.players.map(p => ({
      id: p.id,
      name: p.name,
      chips: p.chips,
      folded: p.folded,
      allIn: p.allIn,
      keyCommitment: p.keyPair.keyCommitment,
    }));
  }

  getActivePlayer() {
    if (this.phase === 'waiting' || this.phase === 'hand-complete' || this.phase === 'showdown') {
      return null;
    }
    return this.players[this.activeIndex] ?? null;
  }

  /** Get a player's hole cards (only the player should call this). */
  getHoleCards(playerId: string): CardIdentity[] {
    const player = this.players.find(p => p.id === playerId);
    return player ? [...player.holeCardIdentities] : [];
  }

  getCommunityCards(): CardIdentity[] {
    return [...this.communityIdentities];
  }

  /** Get all shuffle proofs for this hand. */
  getShuffleProofs(): ShuffleProof[] {
    return this.protocol.getShuffleProofs();
  }

  /** Get all decryption proofs for this hand. */
  getDecryptionProofs(): DecryptionProof[] {
    return this.protocol.getDecryptionProofs();
  }

  /** Evaluate a player's best hand (if enough community cards). */
  evaluatePlayerHand(playerId: string): EvaluatedHand | null {
    const player = this.players.find(p => p.id === playerId);
    if (!player || player.folded || player.holeCardIdentities.length < 2) return null;
    const allCards = [
      ...player.holeCardIdentities.map(identityToCard),
      ...this.communityIdentities.map(identityToCard),
    ];
    if (allCards.length < 5) return null;
    return evaluateHand(allCards);
  }
}

// ── Helpers ─────────────────────────────────────────────────

/** Convert a CardIdentity to a mock Card for hand evaluation. */
function identityToCard(id: CardIdentity): Card {
  return {
    entity: { id: `virtual-${id.index}`, cell: new Uint8Array(0) } as any,
    suit: id.suit as Suit,
    rank: id.rank as Rank,
    faceUp: true,
  };
}

```
