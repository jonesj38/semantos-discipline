---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/risk/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.409430+00:00
---

# packages/games/src/risk/engine.ts

```ts
/**
 * RiskEngine — classic Risk via semantic cells.
 *
 * Territories are tracked in a RELEVANT board cell (DAG of turns).
 * Armies are LINEAR cells — consumed in combat.
 * Cards are LINEAR cells — turned in for reinforcements, then consumed.
 *
 * Move legality is enforced by Lisp policies compiled to opcodes and
 * evaluated in the WASM cell engine via OP_CALLHOST. Reinforce, attack,
 * and fortify actions each have a dedicated policy.
 *
 * Turn phases: reinforce → attack → fortify → next player.
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType, type GameEntity } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import { registerRiskHostFunctions } from './host-functions';
import { compileRiskPolicies, type CompiledRiskPolicies } from './policies';
import { TERRITORIES, CONTINENTS, areAdjacent, hasPath } from './map';
import type {
  PlayerId,
  Player,
  TerritoryId,
  TerritoryState,
  RiskBoard,
  RiskGameStatus,
  TurnPhase,
  CombatResult,
  AttackResult,
  FortifyResult,
  ReinforceResult,
  CardType,
  RiskCard,
} from './types';
import { PLAYER_COLORS } from './types';

// ── Constants ───────────────────────────────────────────────────

const LINEAR = 1;
const RELEVANT = 3;
const TERRITORY_COUNT = 42;
const CARD_TYPES: CardType[] = ['infantry', 'cavalry', 'artillery'];

const GAME_OWNER = new Uint8Array(16);
GAME_OWNER[0] = 0x20;

function ownerBytes(id: PlayerId): Uint8Array {
  const b = new Uint8Array(16);
  b[0] = 0x30 + id;
  return b;
}

// ── RiskEngine ──────────────────────────────────────────────────

export class RiskEngine {
  private cellEngine: GameCellEngine;
  private registry: HostFunctionRegistry;
  private policies: CompiledRiskPolicies;
  private currentBoard: RiskBoard;
  private boardHistory: string[];
  private consumedCells: Set<string>;

  private players: Player[];
  private _status: RiskGameStatus;
  private reinforcementsRemaining: number;
  private conqueredThisTurn: boolean;
  private cardDeck: RiskCard[];
  private playerCards: Map<PlayerId, RiskCard[]>;
  private cardSetsTurnedIn: number;
  private lastBoardCell: Uint8Array | null;

  private constructor(
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policies: CompiledRiskPolicies,
    board: RiskBoard,
    players: Player[],
    boardCellBytes: Uint8Array,
  ) {
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.policies = policies;
    this.currentBoard = board;
    this.boardHistory = [board.cellId];
    this.consumedCells = new Set();
    this.lastBoardCell = boardCellBytes;
    this.players = players;
    this._status = 'playing';
    this.reinforcementsRemaining = 0;
    this.conqueredThisTurn = false;
    this.cardDeck = [];
    this.playerCards = new Map();
    this.cardSetsTurnedIn = 0;

    for (const p of players) {
      this.playerCards.set(p.id, []);
    }
  }

  /**
   * Create a new Risk game.
   * Registers host functions, compiles policies to WASM opcodes,
   * distributes territories randomly and places initial armies.
   */
  static async create(
    playerCount: number,
    opts?: CreateOptions,
  ): Promise<RiskEngine> {
    if (playerCount < 2 || playerCount > 6) {
      throw new Error('Risk requires 2-6 players');
    }

    const registry = new HostFunctionRegistry();
    registerRiskHostFunctions(registry);

    const cellEngine = await GameCellEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const policies = compileRiskPolicies();

    // Create players
    const players: Player[] = [];
    for (let i = 0; i < playerCount; i++) {
      players.push({
        id: i,
        name: `Player ${i + 1}`,
        color: PLAYER_COLORS[i],
        eliminated: false,
        cardCount: 0,
      });
    }

    // Distribute territories randomly
    const territoryOrder = Array.from({ length: TERRITORY_COUNT }, (_, i) => i);
    shuffle(territoryOrder);

    const initialArmiesPerPlayer: Record<number, number> = {
      2: 40, 3: 35, 4: 30, 5: 25, 6: 20,
    };
    const startingArmies = initialArmiesPerPlayer[playerCount];

    const territories: TerritoryState[] = new Array(TERRITORY_COUNT);
    const armiesPlaced = new Array(playerCount).fill(0);

    for (let i = 0; i < TERRITORY_COUNT; i++) {
      const tid = territoryOrder[i];
      const owner = i % playerCount;
      territories[tid] = { owner, armies: 1 };
      armiesPlaced[owner]++;
    }

    // Distribute remaining armies randomly
    for (let p = 0; p < playerCount; p++) {
      let remaining = startingArmies - armiesPlaced[p];
      const owned = territories
        .map((t, idx) => t.owner === p ? idx : -1)
        .filter(idx => idx >= 0);

      while (remaining > 0) {
        const tid = owned[Math.floor(Math.random() * owned.length)];
        territories[tid].armies++;
        remaining--;
      }
    }

    // Create board cell
    const boardEntity = cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: GAME_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'risk',
        owners: territories.map(t => t.owner),
        armies: territories.map(t => t.armies),
        turn: 1,
        phase: 'reinforce',
        player: 0,
      },
      state: 'playing',
    });

    const board: RiskBoard = {
      cellId: boardEntity.id,
      territories,
      currentPlayer: 0,
      phase: 'reinforce',
      turnNumber: 1,
      previousBoardCellId: null,
    };

    const engine = new RiskEngine(cellEngine, registry, policies, board, players, boardEntity.cell);

    // Build card deck
    engine.buildCardDeck();

    // Calculate initial reinforcements
    engine.reinforcementsRemaining = engine.calculateReinforcements(0);

    return engine;
  }

  // ── Accessors ─────────────────────────────────────────────────

  getBoard(): RiskBoard { return this.currentBoard; }
  status(): RiskGameStatus { return this._status; }
  getPlayers(): Player[] { return [...this.players]; }
  currentPhase(): TurnPhase { return this.currentBoard.phase; }
  currentPlayerId(): PlayerId { return this.currentBoard.currentPlayer; }
  history(): string[] { return [...this.boardHistory]; }
  getReinforcements(): number { return this.reinforcementsRemaining; }

  getPlayerCards(player: PlayerId): RiskCard[] {
    return [...(this.playerCards.get(player) ?? [])];
  }

  territoriesOwned(player: PlayerId): TerritoryId[] {
    return this.currentBoard.territories
      .map((t, idx) => t.owner === player ? idx : -1)
      .filter(idx => idx >= 0);
  }

  totalArmies(player: PlayerId): number {
    return this.currentBoard.territories
      .filter(t => t.owner === player)
      .reduce((sum, t) => sum + t.armies, 0);
  }

  // ── WASM Policy Evaluation ──────────────────────────────────

  /**
   * Evaluate a Risk policy via OP_CALLHOST.
   * Sets the frozen context and runs the compiled policy bytecode in WASM.
   */
  private evaluatePolicy(
    action: 'reinforce' | 'attack' | 'fortify',
    opts: {
      territory: number;
      fromTerritory?: number;
      armies?: number;
    },
  ): boolean {
    const b = this.currentBoard;
    this.registry.setContext({
      action,
      player: b.currentPlayer,
      territory: opts.territory,
      fromTerritory: opts.fromTerritory ?? -1,
      armies: opts.armies ?? 0,
      reinforcementsRemaining: this.reinforcementsRemaining,
      owners: b.territories.map(t => t.owner),
      armyCounts: b.territories.map(t => t.armies),
    });

    const policyBytes = this.policies[action].scriptBytes;
    const result = this.cellEngine.evaluatePolicy(policyBytes);
    this.registry.clearContext();
    return result;
  }

  // ── Reinforcement Phase ───────────────────────────────────────

  /** Place reinforcements on a territory you own. */
  reinforce(territory: TerritoryId, armies: number): ReinforceResult {
    this.assertPhase('reinforce');
    const player = this.currentBoard.currentPlayer;

    // Validate via compiled Lisp policy (WASM execution via OP_CALLHOST)
    if (!this.evaluatePolicy('reinforce', { territory, armies })) {
      throw new Error(
        `Illegal reinforcement: territory=${territory}, armies=${armies} ` +
        `(player=${player}, remaining=${this.reinforcementsRemaining})`,
      );
    }

    this.currentBoard.territories[territory].armies += armies;
    this.reinforcementsRemaining -= armies;

    // Create army entities (LINEAR)
    for (let i = 0; i < armies; i++) {
      this.cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: ownerBytes(player),
        linearity: LINEAR,
        metadata: { domain: 'risk-army', territory, player },
        state: 'deployed',
      });
    }

    // Auto-advance to attack phase when all reinforcements placed
    if (this.reinforcementsRemaining === 0) {
      this.currentBoard.phase = 'attack';
    }

    return {
      territory,
      armiesPlaced: armies,
      armiesRemaining: this.reinforcementsRemaining,
    };
  }

  /** Turn in a set of 3 cards for bonus reinforcements. */
  turnInCards(cardIndices: [number, number, number]): number {
    this.assertPhase('reinforce');
    const player = this.currentBoard.currentPlayer;
    const hand = this.playerCards.get(player)!;

    const cards = cardIndices.map(i => {
      if (i < 0 || i >= hand.length) throw new Error(`Invalid card index: ${i}`);
      return hand[i];
    });

    if (!isValidSet(cards)) {
      throw new Error('Invalid card set — need 3 of a kind or one of each');
    }

    // Calculate bonus
    this.cardSetsTurnedIn++;
    const bonus = this.cardSetBonus();

    // Consume cards (LINEAR destruction)
    const toRemove = new Set(cardIndices);
    for (const idx of toRemove) {
      this.consumedCells.add(hand[idx].entity.id);
    }
    this.playerCards.set(
      player,
      hand.filter((_, i) => !toRemove.has(i)),
    );
    this.players[player].cardCount = this.playerCards.get(player)!.length;

    this.reinforcementsRemaining += bonus;
    return bonus;
  }

  // ── Attack Phase ──────────────────────────────────────────────

  /** Attack from one territory to an adjacent territory. */
  attack(from: TerritoryId, to: TerritoryId, attackDice?: number): AttackResult {
    this.assertPhase('attack');
    const player = this.currentBoard.currentPlayer;
    const territories = this.currentBoard.territories;

    // Validate via compiled Lisp policy (WASM execution via OP_CALLHOST)
    if (!this.evaluatePolicy('attack', { territory: to, fromTerritory: from })) {
      throw new Error(
        `Illegal attack: from=${from} to=${to} (player=${player})`,
      );
    }

    const maxAttackDice = Math.min(3, territories[from].armies - 1);
    const numAttackDice = attackDice
      ? Math.min(attackDice, maxAttackDice)
      : maxAttackDice;
    const numDefendDice = Math.min(2, territories[to].armies);

    const combat = resolveCombat(numAttackDice, numDefendDice);

    // Apply losses
    territories[from].armies -= combat.attackerLosses;
    territories[to].armies -= combat.defenderLosses;

    // Consume LINEAR army cells for losses
    this.consumeArmies(combat.attackerLosses);
    this.consumeArmies(combat.defenderLosses);

    // Check conquest
    if (territories[to].armies === 0) {
      combat.territoryConquered = true;
      const defender = territories[to].owner;
      territories[to].owner = player;
      // Move attacking armies into conquered territory
      const movedArmies = numAttackDice;
      territories[from].armies -= movedArmies;
      territories[to].armies = movedArmies;

      this.conqueredThisTurn = true;

      // Check if defender is eliminated
      if (!territories.some(t => t.owner === defender)) {
        this.players[defender].eliminated = true;

        // Take defender's cards
        const defenderCards = this.playerCards.get(defender) ?? [];
        const playerHand = this.playerCards.get(player)!;
        playerHand.push(...defenderCards);
        this.playerCards.set(defender, []);
        this.players[player].cardCount = playerHand.length;
        this.players[defender].cardCount = 0;
      }

      // Check win condition
      const activePlayers = this.players.filter(p => !p.eliminated);
      if (activePlayers.length === 1) {
        this._status = 'gameover';
        this.currentBoard.phase = 'gameover';
      }
    }

    const board = this.commitBoard();
    return { from, to, combat, board };
  }

  /** End the attack phase and move to fortify. */
  endAttack(): void {
    this.assertPhase('attack');
    this.currentBoard.phase = 'fortify';
  }

  // ── Fortify Phase ─────────────────────────────────────────────

  /** Move armies between two connected territories you own. */
  fortify(from: TerritoryId, to: TerritoryId, armies: number): FortifyResult {
    this.assertPhase('fortify');
    const player = this.currentBoard.currentPlayer;
    const territories = this.currentBoard.territories;

    // Validate via compiled Lisp policy (WASM execution via OP_CALLHOST)
    if (!this.evaluatePolicy('fortify', { territory: to, fromTerritory: from, armies })) {
      throw new Error(
        `Illegal fortify: from=${from} to=${to} armies=${armies} (player=${player})`,
      );
    }

    territories[from].armies -= armies;
    territories[to].armies += armies;

    const board = this.commitBoard();
    this.endTurn();
    return { from, to, armies, board };
  }

  /** Skip fortification and end turn. */
  endFortify(): void {
    this.assertPhase('fortify');
    this.commitBoard();
    this.endTurn();
  }

  // ── Card Deck ─────────────────────────────────────────────────

  private buildCardDeck(): void {
    for (let i = 0; i < TERRITORY_COUNT; i++) {
      const cardType = CARD_TYPES[i % 3];
      const entity = this.cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: GAME_OWNER,
        linearity: LINEAR,
        metadata: { domain: 'risk-card', territory: i, cardType },
        state: 'in-deck',
      });
      this.cardDeck.push({ entity, territory: i, cardType });
    }
    // Add 2 wild cards
    for (let i = 0; i < 2; i++) {
      const entity = this.cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: GAME_OWNER,
        linearity: LINEAR,
        metadata: { domain: 'risk-card', territory: null, cardType: 'wild' },
        state: 'in-deck',
      });
      this.cardDeck.push({ entity, territory: null, cardType: 'wild' });
    }
    shuffle(this.cardDeck);
  }

  private drawCard(player: PlayerId): RiskCard | null {
    if (this.cardDeck.length === 0) return null;
    const card = this.cardDeck.pop()!;
    const hand = this.playerCards.get(player)!;
    hand.push(card);
    this.players[player].cardCount = hand.length;
    return card;
  }

  // ── Turn Management ───────────────────────────────────────────

  private endTurn(): void {
    if (this._status === 'gameover') return;

    // Draw card if conquered a territory this turn
    if (this.conqueredThisTurn) {
      this.drawCard(this.currentBoard.currentPlayer);
    }

    // Advance to next active player
    let next = (this.currentBoard.currentPlayer + 1) % this.players.length;
    while (this.players[next].eliminated) {
      next = (next + 1) % this.players.length;
    }

    this.currentBoard.currentPlayer = next;
    this.currentBoard.phase = 'reinforce';
    this.currentBoard.turnNumber++;
    this.conqueredThisTurn = false;

    this.reinforcementsRemaining = this.calculateReinforcements(next);
  }

  calculateReinforcements(player: PlayerId): number {
    const territories = this.currentBoard.territories;
    const ownedCount = territories.filter(t => t.owner === player).length;

    // Base: territories / 3, minimum 3
    let reinforcements = Math.max(3, Math.floor(ownedCount / 3));

    // Continent bonuses
    for (const continent of CONTINENTS) {
      if (continent.territories.every(tid => territories[tid].owner === player)) {
        reinforcements += continent.bonus;
      }
    }

    return reinforcements;
  }

  private cardSetBonus(): number {
    // Classic escalating bonuses
    const bonuses = [4, 6, 8, 10, 12, 15];
    const idx = Math.min(this.cardSetsTurnedIn - 1, bonuses.length - 1);
    if (this.cardSetsTurnedIn > bonuses.length) {
      return 15 + (this.cardSetsTurnedIn - bonuses.length) * 5;
    }
    return bonuses[idx];
  }

  // ── Board Commit ──────────────────────────────────────────────

  private commitBoard(): RiskBoard {
    const b = this.currentBoard;
    const boardEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: GAME_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'risk',
        owners: b.territories.map(t => t.owner),
        armies: b.territories.map(t => t.armies),
        turn: b.turnNumber,
        phase: b.phase,
        player: b.currentPlayer,
        prev: b.cellId,
      },
      state: this._status === 'gameover' ? 'gameover' : 'playing',
      prevCell: this.lastBoardCell ?? undefined,
    });

    const newBoard: RiskBoard = {
      cellId: boardEntity.id,
      territories: b.territories.map(t => ({ ...t })),
      currentPlayer: b.currentPlayer,
      phase: b.phase,
      turnNumber: b.turnNumber,
      previousBoardCellId: b.cellId,
    };

    this.currentBoard = newBoard;
    this.lastBoardCell = boardEntity.cell;
    this.boardHistory.push(boardEntity.id);
    return newBoard;
  }

  private consumeArmies(count: number): void {
    for (let i = 0; i < count; i++) {
      // Create and immediately consume an army cell
      const entity = this.cellEngine.createEntity({
        entityType: GameEntityType.ITEM,
        ownerId: GAME_OWNER,
        linearity: LINEAR,
        metadata: { domain: 'risk-army-casualty' },
        state: 'consumed',
      });
      this.consumedCells.add(entity.id);
    }
  }

  private assertPhase(expected: TurnPhase): void {
    if (this._status === 'gameover') {
      throw new Error('Game is over');
    }
    if (this.currentBoard.phase !== expected) {
      throw new Error(
        `Wrong phase: expected '${expected}', currently '${this.currentBoard.phase}'`,
      );
    }
  }
}

// ── Combat Resolution ───────────────────────────────────────────

function rollDice(count: number): number[] {
  return Array.from({ length: count }, () => Math.floor(Math.random() * 6) + 1)
    .sort((a, b) => b - a);
}

function resolveCombat(attackDice: number, defendDice: number): CombatResult {
  const attackerRolls = rollDice(attackDice);
  const defenderRolls = rollDice(defendDice);

  let attackerLosses = 0;
  let defenderLosses = 0;

  const comparisons = Math.min(attackerRolls.length, defenderRolls.length);
  for (let i = 0; i < comparisons; i++) {
    if (attackerRolls[i] > defenderRolls[i]) {
      defenderLosses++;
    } else {
      attackerLosses++; // Ties go to defender
    }
  }

  return {
    attackerLosses,
    defenderLosses,
    attackerDice: attackerRolls,
    defenderDice: defenderRolls,
    territoryConquered: false,
  };
}

// ── Card Set Validation ─────────────────────────────────────────

function isValidSet(cards: RiskCard[]): boolean {
  if (cards.length !== 3) return false;

  const types = cards.map(c => c.cardType);
  const wildCount = types.filter(t => t === 'wild').length;

  if (wildCount >= 2) return true; // 2 wilds + anything
  if (wildCount === 1) return true; // 1 wild completes any pair

  // All same type
  if (types[0] === types[1] && types[1] === types[2]) return true;

  // One of each
  const typeSet = new Set(types);
  if (typeSet.size === 3) return true;

  return false;
}

// ── Utilities ───────────────────────────────────────────────────

function shuffle<T>(arr: T[]): void {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}

```
