---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/__tests__/help-renderer.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.416240+00:00
---

# packages/games/src/cli/__tests__/help-renderer.test.ts

```ts
/**
 * Snapshot test for the help renderer + the unknown-action error wording.
 *
 * Pins the byte-for-byte output of:
 *   - renderUnknownActionError(game, action, available) — which the
 *     dispatcher feeds to the user when the action doesn't match
 *   - renderHelp() — the new multi-game help block
 *
 * The unknown-action wording must match the legacy router exactly:
 * `Unknown <game> command: <action>. Available: <a, b, c, …>`.
 */

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';

import {
  _resetRegistry,
  listActions,
  registerCommands,
  type CommandSpec,
} from '../command-registry';
import { renderHelp, renderUnknownActionError } from '../help-renderer';

// Stub specs mirroring the real registration order — keeps the help
// snapshot deterministic without importing every game engine.
type SpecLite = Omit<CommandSpec, 'handler'>;
const liteFixtures: SpecLite[] = [
  { game: 'chess', action: 'new', summary: 'Start a fresh chess game.', args: [] },
  { game: 'chess', action: 'move', summary: 'Apply an algebraic-notation chess move.', args: [{ name: 'move', description: 'Move spec, e.g. e2e4 or e7e8q for promotion.', required: true }] },
  { game: 'chess', action: 'board', summary: 'Render the current chess board.', args: [] },
  { game: 'chess', action: 'status', summary: 'Report the engine status (active, check, checkmate, draw).', args: [] },
  { game: 'chess', action: 'fen', summary: 'Emit FEN notation for the current chess position.', args: [] },
  { game: 'chess', action: 'history', summary: 'Return the move list and underlying cell history.', args: [] },
  { game: 'life', action: 'new', summary: 'Create a Game-of-Life board, optionally seeded.', args: [
    { name: 'width', description: 'Board width (default 20).' },
    { name: 'height', description: 'Board height (default 20).' },
    { name: 'pattern', description: 'Named seed pattern (e.g. glider).' },
    { name: 'density', description: 'Random-fill density 0..1 if no pattern.' },
  ] },
  { game: 'life', action: 'step', summary: 'Advance Game-of-Life by N generations.', args: [
    { name: 'count', description: 'Number of generations to step (default 1).' },
  ] },
  { game: 'life', action: 'board', summary: 'Render the current Game-of-Life board.', args: [] },
  { game: 'life', action: 'status', summary: 'Report generation, population, stability, and history length.', args: [] },
  { game: 'risk', action: 'new', summary: 'Start a new Risk match.', args: [
    { name: 'players', description: 'Number of players (default 3).' },
  ] },
  { game: 'risk', action: 'board', summary: 'Render the Risk territory map.', args: [] },
  { game: 'risk', action: 'summary', summary: 'Per-player territory + army summary.', args: [] },
  { game: 'risk', action: 'reinforce', summary: 'Place armies on a territory you own.', args: [
    { name: 'territory', description: 'Territory index.', required: true },
    { name: 'armies', description: 'Armies to place (default 1).' },
  ] },
  { game: 'risk', action: 'attack', summary: 'Attack a neighbouring territory.', args: [
    { name: 'from', description: 'Attacker territory index.', required: true },
    { name: 'to', description: 'Defender territory index.', required: true },
    { name: 'dice', description: 'Number of attacker dice (default: max).' },
  ] },
  { game: 'risk', action: 'endattack', summary: 'End the attack phase, advancing to fortify.', args: [] },
  { game: 'risk', action: 'fortify', summary: 'Move armies between two of your connected territories.', args: [
    { name: 'from', description: 'Source territory index.', required: true },
    { name: 'to', description: 'Destination territory index.', required: true },
    { name: 'armies', description: 'Armies to move (default 1).' },
  ] },
  { game: 'risk', action: 'endfortify', summary: 'End the fortify phase and advance to the next player.', args: [] },
  { game: 'risk', action: 'status', summary: 'Report status, phase, current player, and territory summary.', args: [] },
  { game: 'dungeon', action: 'new', summary: 'Generate a fresh dungeon and place the player.', args: [] },
  { game: 'dungeon', action: 'move', summary: 'Move the player one tile in a cardinal direction.', args: [
    { name: 'direction', description: 'n, s, e, or w.', required: true },
  ] },
  { game: 'dungeon', action: 'attack', summary: 'Attack the adjacent monster in a cardinal direction.', args: [
    { name: 'direction', description: 'n, s, e, or w.', required: true },
  ] },
  { game: 'dungeon', action: 'take', summary: 'Pick up an item from the current tile.', args: [
    { name: 'item', description: 'Optional item index when several are present.' },
  ] },
  { game: 'dungeon', action: 'use', summary: 'Use a held inventory item by index.', args: [
    { name: 'item', description: 'Inventory item index.', required: true },
  ] },
  { game: 'dungeon', action: 'open', summary: 'Open the door in the given direction.', args: [
    { name: 'direction', description: 'n, s, e, or w.', required: true },
  ] },
  { game: 'dungeon', action: 'descend', summary: 'Descend to the next dungeon floor.', args: [] },
  { game: 'dungeon', action: 'inventory', summary: 'List items currently carried by the player.', args: [] },
  { game: 'dungeon', action: 'look', summary: 'Describe the player\u2019s immediate surroundings.', args: [] },
  { game: 'dungeon', action: 'map', summary: 'Render the explored region of the dungeon map.', args: [] },
  { game: 'dungeon', action: 'status', summary: 'Player status, run status, and history length.', args: [] },
  { game: 'dungeon', action: 'history', summary: 'Return the underlying cell history list.', args: [] },
  { game: 'poker', action: 'new', summary: 'Create a Texas Hold\u2019em table with N players (1\u20139).', args: [
    { name: 'players', description: 'Number of seats (default 4, max 9).' },
    { name: 'sb', description: 'Small blind (default 5).' },
    { name: 'bb', description: 'Big blind (default 10).' },
    { name: 'chips', description: 'Starting chips per seat (default 1000).' },
  ] },
  { game: 'poker', action: 'deal', summary: 'Deal hole cards and post blinds for the next hand.', args: [] },
  { game: 'poker', action: 'fold', summary: 'Fold the current hand.', args: [] },
  { game: 'poker', action: 'check', summary: 'Check when there is no bet to call.', args: [] },
  { game: 'poker', action: 'call', summary: 'Match the current outstanding bet.', args: [] },
  { game: 'poker', action: 'bet', summary: 'Open a bet on a no-action street.', args: [
    { name: 'amount', description: 'Bet size in chips.', required: true },
  ] },
  { game: 'poker', action: 'raise', summary: 'Raise the current bet.', args: [
    { name: 'amount', description: 'Total chips after the raise.', required: true },
  ] },
  { game: 'poker', action: 'all-in', summary: 'Push every remaining chip.', args: [] },
  { game: 'poker', action: 'table', summary: 'Render the current poker table.', args: [] },
  { game: 'poker', action: 'hand', summary: 'Show your hole cards and current best hand.', args: [] },
  { game: 'poker', action: 'status', summary: 'Phase, pot, hand number, and per-player chip stacks.', args: [] },
];

const fixtures: CommandSpec[] = liteFixtures.map((s) => ({
  ...s,
  handler: () => ({ ok: true }),
}));

beforeEach(() => {
  _resetRegistry();
  registerCommands(fixtures);
});

afterEach(() => {
  _resetRegistry();
});

describe('renderUnknownActionError', () => {
  test('matches the legacy chess wording', () => {
    expect(
      renderUnknownActionError('chess', 'badaction', listActions('chess')),
    ).toBe('Unknown chess command: badaction. Available: new, move, board, status, fen, history');
  });

  test('matches the legacy life wording', () => {
    expect(
      renderUnknownActionError('life', 'wat', listActions('life')),
    ).toBe('Unknown life command: wat. Available: new, step, board, status');
  });

  test('matches the legacy risk wording', () => {
    expect(
      renderUnknownActionError('risk', 'wat', listActions('risk')),
    ).toBe(
      'Unknown risk command: wat. Available: new, board, summary, reinforce, attack, endattack, fortify, endfortify, status',
    );
  });

  test('matches the legacy dungeon wording', () => {
    expect(
      renderUnknownActionError('dungeon', 'wat', listActions('dungeon')),
    ).toBe(
      'Unknown dungeon command: wat. Available: new, move, attack, take, use, open, descend, inventory, look, map, status, history',
    );
  });

  test('matches the legacy poker wording', () => {
    expect(
      renderUnknownActionError('poker', 'wat', listActions('poker')),
    ).toBe(
      'Unknown poker command: wat. Available: new, deal, fold, check, call, bet, raise, all-in, table, hand, status',
    );
  });
});

describe('renderHelp', () => {
  test('snapshot — full multi-game help block is stable', () => {
    expect(renderHelp()).toMatchSnapshot();
  });
});

```
