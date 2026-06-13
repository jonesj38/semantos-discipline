---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/dispatcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.400035+00:00
---

# packages/games/src/cli/dispatcher.ts

```ts
/**
 * Pure registry-driven dispatcher for the `game` verb.
 *
 * Split out from `commands/index.ts` so it can be unit-tested with a
 * fake/stub registry without paying the cost of importing every game
 * engine. `commands/index.ts` is the eager boot-time registration entry
 * point; this file is just (cmd, registry-lookup) → response.
 *
 * Behavioural contract (matches the legacy `routeGame` byte-for-byte):
 *
 *   - missing game type            → "Usage: …"
 *   - go / cards (no CLI yet)      → "<X> CLI not yet implemented."
 *   - unknown game type            → "Unknown game type: <X>. Available: …"
 *   - unknown action for known game → renderUnknownActionError(…)
 */

import type { ShellCommand } from '@semantos/shell/parser';
import type { ShellContext } from '@semantos/shell/types';

import {
  getCommand as defaultGetCommand,
  listActions as defaultListActions,
  type CommandSpec,
} from './command-registry';
import { renderUnknownActionError } from './help-renderer';

// Game types that have a CLI surface.
const SUPPORTED_GAMES = new Set(['chess', 'life', 'risk', 'dungeon', 'poker']);

// Game types that exist as engines but have no CLI yet.
const STUB_GAMES: Record<string, string> = {
  go: 'Go CLI not yet implemented. Use the programmatic API.',
  cards: 'Cards CLI not yet implemented. Use the programmatic API.',
};

const AVAILABLE_GAMES = 'chess, go, cards, poker, life, risk, dungeon';

/** Hooks the dispatcher uses to look up commands. Defaults to the real registry. */
export interface RegistryLookup {
  getCommand: (game: string, action: string) => CommandSpec | undefined;
  listActions: (game: string) => string[];
}

const defaultLookup: RegistryLookup = {
  getCommand: defaultGetCommand,
  listActions: defaultListActions,
};

/**
 * Top-level CLI entry registered as the `game` verb. Pulls the requested
 * command spec from `lookup` (defaulting to the real registry) and
 * delegates to the spec's handler. Error wording matches the legacy
 * router byte-for-byte.
 */
export async function routeGame(
  cmd: ShellCommand,
  _ctx: ShellContext,
  lookup: RegistryLookup = defaultLookup,
): Promise<unknown> {
  const subcommand = cmd.flags.subcommand as string | undefined;
  const gameType = cmd.objectId ?? cmd.typePath ?? (cmd.flags.type as string | undefined);

  if (!gameType) {
    return { error: 'Usage: semantos game <chess|go|cards|poker|life|risk|dungeon> <command>' };
  }

  if (gameType in STUB_GAMES) {
    return { error: STUB_GAMES[gameType] };
  }

  if (!SUPPORTED_GAMES.has(gameType)) {
    return { error: `Unknown game type: ${gameType}. Available: ${AVAILABLE_GAMES}` };
  }

  const action = subcommand ?? 'status';
  const spec = lookup.getCommand(gameType, action);
  if (!spec) {
    return {
      error: renderUnknownActionError(gameType, action, lookup.listActions(gameType)),
    };
  }

  return spec.handler(cmd);
}

```
