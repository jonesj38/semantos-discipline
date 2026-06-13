---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.397067+00:00
---

# packages/games/src/index.ts

```ts
/**
 * @semantos/games — Game implementations proving the semantic cell model.
 *
 * Chess: LINEAR pieces, compiled Lisp policies, DAG history
 * Go: AFFINE stones, group capture, ko rule
 * Cards: LINEAR deck, hidden information model
 * Life: AFFINE cells, Conway's rules, generation DAG
 * Risk: LINEAR armies/cards, RELEVANT territories, dice combat
 */

// Chess
export { SemanticChessEngine } from './chess/engine';
export { registerChessHostFunctions } from './chess/host-functions';
export { compileChessPolicies } from './chess/policies';
export { toFEN, parseFEN } from './chess/fen';
export { toPGN } from './chess/pgn';
export { renderBoard as renderChessBoard } from './chess/renderer';
export type {
  ChessPiece,
  ChessBoard,
  PieceType,
  Color,
  GameStatus,
  MoveResult,
  CastlingRights,
} from './chess/types';
export {
  algebraicToSquare,
  squareToAlgebraic,
  squareFile,
  squareRank,
  toSquare,
} from './chess/types';

// Go
export { SemanticGoEngine } from './go/engine';
export { registerGoHostFunctions } from './go/host-functions';
export type { GoBoard, GoStone } from './go/types';

// Cards
export { CardGameEngine } from './cards/engine';
export { WarGame } from './cards/war';
export type { Card, Deck, Hand, Suit, Rank } from './cards/types';

// Poker (Texas Hold'em NL)
export { PokerEngine } from './cards/poker';
export { evaluateHand, compareHands, formatHand } from './cards/hand-evaluator';
export { compilePokerPolicies, registerPokerHostFunctions } from './cards/poker-policies';
export {
  renderPokerTable,
  renderActionPrompt,
  renderShowdown,
  renderPlayerStatus as renderPokerPlayerStatus,
} from './cards/poker-renderer';
export type {
  PokerPlayer,
  PokerTable,
  PokerAction,
  PokerConfig,
  SidePot,
  ShowdownResult,
  EvaluatedHand,
  HandRank,
  GamePhase as PokerPhase,
} from './cards/poker-types';
export { HandRank as PokerHandRank, HAND_RANK_NAMES } from './cards/poker-types';

// Mental Poker (trustless protocol)
export { MentalPokerProtocol, TrustlessPokerEngine } from './cards/mental-poker';
export {
  generateKeyPair as generatePokerKeyPair,
  sraEncrypt,
  sraDecrypt,
  SRA_PRIME,
} from './cards/mental-poker';
export type {
  PlayerKeyPair,
  ShuffleProof,
  DecryptionProof,
  KeyRevealProof,
  VerificationResult as PokerVerificationResult,
  CardIdentity,
} from './cards/mental-poker';

// Poker Transport (shard multicast)
export { PokerTableTransport } from './cards/mental-poker';
export type {
  PokerMessage,
  PokerMessageType,
  PokerTransportConfig,
} from './cards/mental-poker';

// Game of Life
export { GameOfLifeEngine } from './life/engine';
export { registerLifeHostFunctions } from './life/host-functions';
export { compileLifePolicy } from './life/policies';
export { renderBoard as renderLifeBoard } from './life/renderer';
export type { LifeBoard, LifeCell, LifeStepResult, PatternName } from './life/types';
export { PATTERNS as LIFE_PATTERNS } from './life/types';

// Risk
export { RiskEngine } from './risk/engine';
export { registerRiskHostFunctions } from './risk/host-functions';
export { compileRiskPolicies } from './risk/policies';
export { renderBoard as renderRiskBoard, renderSummary as renderRiskSummary } from './risk/renderer';
export { TERRITORIES, CONTINENTS, areAdjacent } from './risk/map';
export type {
  Player as RiskPlayer,
  RiskBoard,
  RiskCard,
  TerritoryState,
  CombatResult,
  AttackResult,
  FortifyResult,
  ReinforceResult,
} from './risk/types';

// Dungeon
export { DungeonEngine } from './dungeon/engine';
export { registerDungeonHostFunctions } from './dungeon/host-functions';
export { compileDungeonPolicies } from './dungeon/policies';
export { createDungeonHostFunctionProvider, DungeonHostFunctionProvider } from './dungeon/kernel-provider';

// Poker kernel provider
export { createPokerHostFunctionProvider, PokerHostFunctionProvider } from './cards/kernel-provider';
export { renderMap as renderDungeonMap, renderStatus, renderInventory } from './dungeon/renderer';
export { generateFloor } from './dungeon/map-gen';
export type {
  DungeonBoard,
  DungeonPlayer,
  DungeonItem,
  Monster,
  DungeonFloor,
  DungeonGameStatus,
  ActionResult as DungeonActionResult,
  Direction,
} from './dungeon/types';
export {
  Tile,
  MONSTER_TYPES,
  ITEM_TEMPLATES,
  ITEM_CHARS,
} from './dungeon/types';

// CLI
export { routeGame } from './cli/game-commands';

```
