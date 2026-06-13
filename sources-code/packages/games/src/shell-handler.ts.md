---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/shell-handler.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.397379+00:00
---

# packages/games/src/shell-handler.ts

```ts
/**
 * @semantos/games/shell-handler — verb registration entry.
 *
 * Loaded dynamically by shell at startup (see runtime/shell/src/index.ts
 * loadExtensions). Importing this module has the side effect of
 * registering the 'game' verb with the runtime-services verb registry.
 *
 * Subcommands (chess, go, life, risk, dungeon, cards/poker) are dispatched
 * inside routeGame.
 */

import { registerVerb } from "@semantos/runtime-services";
import { routeGame } from "./cli/game-commands";

registerVerb("game", routeGame as (cmd: unknown, ctx: unknown) => Promise<unknown>);

```
