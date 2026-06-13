---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/__tests__/command-registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.416533+00:00
---

# packages/games/src/cli/__tests__/command-registry.test.ts

```ts
/**
 * Tests for the registry primitive — register, lookup, list-actions
 * preserves insertion order, and `_resetRegistry` clears state.
 *
 * Note: this file does NOT import `commands/index` because that registers
 * every real command on import and we want a clean slate. The route-game
 * test exercises the full integration with the real registry contents.
 */

import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  _resetRegistry,
  getCommand,
  listActions,
  listCommands,
  registerCommand,
  registerCommands,
  type CommandSpec,
} from '../command-registry';

const stub = (game: string, action: string): CommandSpec => ({
  game,
  action,
  summary: `${game} ${action}`,
  args: [],
  handler: () => ({ ok: `${game}:${action}` }),
});

beforeEach(() => {
  _resetRegistry();
});

afterEach(() => {
  _resetRegistry();
});

describe('command-registry', () => {
  test('registerCommand + getCommand round-trip', () => {
    const spec = stub('chess', 'new');
    registerCommand(spec);
    expect(getCommand('chess', 'new')).toBe(spec);
  });

  test('getCommand returns undefined for unknown entries', () => {
    expect(getCommand('chess', 'wat')).toBeUndefined();
  });

  test('registerCommands batches inserts', () => {
    registerCommands([stub('chess', 'a'), stub('chess', 'b')]);
    expect(listCommands().map((s) => s.action)).toEqual(['a', 'b']);
  });

  test('listActions preserves registration order', () => {
    registerCommands([
      stub('poker', 'new'),
      stub('poker', 'deal'),
      stub('poker', 'fold'),
      stub('poker', 'check'),
    ]);
    expect(listActions('poker')).toEqual(['new', 'deal', 'fold', 'check']);
  });

  test('listActions filters by game', () => {
    registerCommands([
      stub('chess', 'new'),
      stub('life', 'new'),
      stub('chess', 'move'),
    ]);
    expect(listActions('chess')).toEqual(['new', 'move']);
    expect(listActions('life')).toEqual(['new']);
  });

  test('last-write-wins on duplicate keys', () => {
    const a = stub('chess', 'new');
    const b = stub('chess', 'new');
    registerCommand(a);
    registerCommand(b);
    expect(getCommand('chess', 'new')).toBe(b);
  });

  test('_resetRegistry clears every entry', () => {
    registerCommand(stub('chess', 'new'));
    _resetRegistry();
    expect(listCommands()).toHaveLength(0);
  });
});

```
