---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/game-commands.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.400875+00:00
---

# packages/games/src/cli/game-commands.ts

```ts
/**
 * @deprecated — kept for backwards-compat with `@semantos/games/cli/game-commands`.
 *
 * The CLI command surface has moved into per-command modules under
 * `./commands/<game>/<action>.ts`, dispatched by a registry. Import
 * `routeGame` from `./commands/index.ts` (or the package's `./cli` path)
 * instead. This file now only re-exports the dispatcher.
 *
 * See refactor/27 for the full split.
 */

export { routeGame } from './commands/index';

```
