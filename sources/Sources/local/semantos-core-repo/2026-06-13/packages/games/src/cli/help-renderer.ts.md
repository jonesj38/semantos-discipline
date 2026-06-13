---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/help-renderer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.399758+00:00
---

# packages/games/src/cli/help-renderer.ts

```ts
/**
 * Pure help-text renderer for the game CLI.
 *
 * Walks the command registry and emits a stable, snapshot-friendly
 * string. The dispatcher in `commands/index.ts` returns the same
 * `{ error: "Unknown … command: …. Available: …" }` shape the legacy
 * router returned for unknown actions; this renderer is for the more
 * verbose `--help` flow that lists every game and action.
 */

import { listCommands, type CommandSpec } from './command-registry';

/**
 * Render the unknown-action error message a per-game router emits when
 * the supplied action does not match any registered command. Matches
 * the exact wording of the legacy `routeChess`/`routeLife`/… defaults.
 */
export function renderUnknownActionError(
  game: string,
  action: string,
  available: readonly string[],
): string {
  return `Unknown ${game} command: ${action}. Available: ${available.join(', ')}`;
}

/**
 * Render the full multi-game help block — one section per game, with
 * each command's summary + arg list. Stable output (sort by game then
 * action) so a snapshot test can pin it.
 */
export function renderHelp(commands: readonly CommandSpec[] = listCommands()): string {
  if (commands.length === 0) return 'No game commands registered.';

  const byGame = new Map<string, CommandSpec[]>();
  for (const spec of commands) {
    const list = byGame.get(spec.game) ?? [];
    list.push(spec);
    byGame.set(spec.game, list);
  }

  const out: string[] = [];
  out.push('semantos game <type> <action> [flags]');
  out.push('');

  for (const game of [...byGame.keys()].sort()) {
    out.push(`# ${game}`);
    const specs = byGame.get(game)!;
    for (const spec of specs) {
      out.push(`  ${game} ${spec.action} \u2014 ${spec.summary}`);
      for (const arg of spec.args ?? []) {
        const req = arg.required ? ' (required)' : '';
        out.push(`      --${arg.name}${req}: ${arg.description}`);
      }
    }
    out.push('');
  }

  return out.join('\n').replace(/\n+$/, '\n');
}

```
