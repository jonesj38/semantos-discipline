---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/__tests__/route-game.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.417108+00:00
---

# packages/games/src/cli/__tests__/route-game.test.ts

```ts
/**
 * Snapshot tests for the dispatcher (`routeGame`) covering the full
 * error matrix that pre-dates this refactor.
 *
 * The dispatcher is the registry-driven replacement for the legacy
 * `routeGame` switch. We exercise it with a *stub* registry so the
 * tests don't transitively import every game engine — the per-engine
 * happy-path behaviour is covered by the engine suites themselves.
 *
 * Every assertion below pins the exact byte-for-byte error wording the
 * legacy router emitted. If a string changes, the snapshot will fail.
 */

import { describe, expect, test } from 'bun:test';
import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';

import { routeGame, type RegistryLookup } from '../dispatcher';
import type { CommandSpec } from '../command-registry';

const ctx = {} as ShellContext;

function cmd(opts: {
  game?: string;
  subcommand?: string;
  flags?: Record<string, string | boolean>;
}): ShellCommand {
  return {
    verb: 'game',
    objectId: opts.game,
    flags: {
      ...(opts.subcommand !== undefined ? { subcommand: opts.subcommand } : {}),
      ...(opts.flags ?? {}),
    },
    rawArgs: [],
  } as ShellCommand;
}

function makeLookup(specs: readonly CommandSpec[]): RegistryLookup {
  return {
    getCommand: (game, action) => specs.find((s) => s.game === game && s.action === action),
    listActions: (game) => specs.filter((s) => s.game === game).map((s) => s.action),
  };
}

const stubChess: CommandSpec[] = [
  { game: 'chess', action: 'new', summary: '', handler: () => ({ status: 'created' }) },
  { game: 'chess', action: 'move', summary: '', handler: () => ({ status: 'ok' }) },
  { game: 'chess', action: 'board', summary: '', handler: () => ({}) },
  { game: 'chess', action: 'status', summary: '', handler: () => ({}) },
  { game: 'chess', action: 'fen', summary: '', handler: () => ({}) },
  { game: 'chess', action: 'history', summary: '', handler: () => ({}) },
];

const stubLife: CommandSpec[] = [
  { game: 'life', action: 'new', summary: '', handler: () => ({}) },
  { game: 'life', action: 'step', summary: '', handler: () => ({}) },
  { game: 'life', action: 'board', summary: '', handler: () => ({}) },
  { game: 'life', action: 'status', summary: '', handler: () => ({}) },
];

const stubRisk: CommandSpec[] = [
  { game: 'risk', action: 'new', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'board', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'summary', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'reinforce', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'attack', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'endattack', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'fortify', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'endfortify', summary: '', handler: () => ({}) },
  { game: 'risk', action: 'status', summary: '', handler: () => ({}) },
];

const stubDungeon: CommandSpec[] = [
  { game: 'dungeon', action: 'new', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'move', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'attack', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'take', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'use', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'open', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'descend', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'inventory', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'look', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'map', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'status', summary: '', handler: () => ({}) },
  { game: 'dungeon', action: 'history', summary: '', handler: () => ({}) },
];

const stubPoker: CommandSpec[] = [
  { game: 'poker', action: 'new', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'deal', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'fold', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'check', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'call', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'bet', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'raise', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'all-in', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'table', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'hand', summary: '', handler: () => ({}) },
  { game: 'poker', action: 'status', summary: '', handler: () => ({}) },
];

const lookup = makeLookup([
  ...stubChess,
  ...stubLife,
  ...stubRisk,
  ...stubDungeon,
  ...stubPoker,
]);

describe('routeGame — top-level dispatch errors', () => {
  test('missing game type returns the usage error', async () => {
    expect(await routeGame(cmd({}), ctx, lookup)).toEqual({
      error: 'Usage: semantos game <chess|go|cards|poker|life|risk|dungeon> <command>',
    });
  });

  test('go is a stub with the documented message', async () => {
    expect(await routeGame(cmd({ game: 'go', subcommand: 'new' }), ctx, lookup)).toEqual({
      error: 'Go CLI not yet implemented. Use the programmatic API.',
    });
  });

  test('cards is a stub with the documented message', async () => {
    expect(await routeGame(cmd({ game: 'cards', subcommand: 'new' }), ctx, lookup)).toEqual({
      error: 'Cards CLI not yet implemented. Use the programmatic API.',
    });
  });

  test('unknown game type is enumerated', async () => {
    expect(await routeGame(cmd({ game: 'tetris' }), ctx, lookup)).toEqual({
      error: 'Unknown game type: tetris. Available: chess, go, cards, poker, life, risk, dungeon',
    });
  });
});

describe('routeGame — unknown action per game', () => {
  test('chess', async () => {
    expect(await routeGame(cmd({ game: 'chess', subcommand: 'wat' }), ctx, lookup)).toEqual({
      error: 'Unknown chess command: wat. Available: new, move, board, status, fen, history',
    });
  });

  test('life', async () => {
    expect(await routeGame(cmd({ game: 'life', subcommand: 'wat' }), ctx, lookup)).toEqual({
      error: 'Unknown life command: wat. Available: new, step, board, status',
    });
  });

  test('risk', async () => {
    expect(await routeGame(cmd({ game: 'risk', subcommand: 'wat' }), ctx, lookup)).toEqual({
      error:
        'Unknown risk command: wat. Available: new, board, summary, reinforce, attack, endattack, fortify, endfortify, status',
    });
  });

  test('dungeon', async () => {
    expect(await routeGame(cmd({ game: 'dungeon', subcommand: 'wat' }), ctx, lookup)).toEqual({
      error:
        'Unknown dungeon command: wat. Available: new, move, attack, take, use, open, descend, inventory, look, map, status, history',
    });
  });

  test('poker', async () => {
    expect(await routeGame(cmd({ game: 'poker', subcommand: 'wat' }), ctx, lookup)).toEqual({
      error:
        'Unknown poker command: wat. Available: new, deal, fold, check, call, bet, raise, all-in, table, hand, status',
    });
  });
});

describe('routeGame — defaults + delegation', () => {
  test('omitting subcommand defaults to status', async () => {
    const seen: string[] = [];
    const trace = makeLookup([
      { game: 'chess', action: 'status', summary: '', handler: () => {
        seen.push('chess.status');
        return { ok: true };
      } },
    ]);
    expect(await routeGame(cmd({ game: 'chess' }), ctx, trace)).toEqual({ ok: true });
    expect(seen).toEqual(['chess.status']);
  });

  test('handler receives the original ShellCommand', async () => {
    let received: ShellCommand | null = null;
    const trace = makeLookup([
      { game: 'chess', action: 'move', summary: '', handler: (c) => {
        received = c;
        return { ok: true };
      } },
    ]);
    const incoming = cmd({ game: 'chess', subcommand: 'move', flags: { move: 'e2e4' } });
    await routeGame(incoming, ctx, trace);
    expect(received).toBe(incoming);
  });

  test('typePath / flags.type are accepted as the game type', async () => {
    const trace = makeLookup([
      { game: 'life', action: 'new', summary: '', handler: () => ({ ok: 'life.new' }) },
    ]);
    expect(
      await routeGame(
        { verb: 'game', typePath: 'life', flags: { subcommand: 'new' }, rawArgs: [] } as ShellCommand,
        ctx,
        trace,
      ),
    ).toEqual({ ok: 'life.new' });
  });
});

```
