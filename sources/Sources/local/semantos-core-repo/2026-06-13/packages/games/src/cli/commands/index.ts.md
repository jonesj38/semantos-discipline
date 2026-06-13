---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.415872+00:00
---

# packages/games/src/cli/commands/index.ts

```ts
/**
 * Per-game CLI command aggregation + boot-time registration.
 *
 * Importing this module pulls in every game's per-action handlers and
 * registers them with the central registry. The dispatcher itself
 * lives in `../dispatcher.ts` so it can be unit-tested with a stub
 * registry without dragging in every game engine at module load.
 */

import { registerCommands } from '../command-registry';
import { chessCommands } from './chess';
import { lifeCommands } from './life';
import { riskCommands } from './risk';
import { dungeonCommands } from './dungeon';
import { pokerCommands } from './poker';

// ── boot-time registration ──────────────────────────────────────

registerCommands([
  ...chessCommands,
  ...lifeCommands,
  ...riskCommands,
  ...dungeonCommands,
  ...pokerCommands,
]);

export { routeGame } from '../dispatcher';

```
