---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cli/commands/risk/attack.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.431323+00:00
---

# packages/games/src/cli/commands/risk/attack.ts

```ts
/** `semantos game risk attack --from <i> --to <i> [--dice <n>]` — declare attack. */

import { TERRITORIES } from '../../../risk/map';
import type { CommandSpec } from '../../command-registry';
import { session } from '../../session';

export const riskAttack: CommandSpec = {
  game: 'risk',
  action: 'attack',
  summary: 'Attack a neighbouring territory.',
  args: [
    { name: 'from', description: 'Attacker territory index.', required: true },
    { name: 'to', description: 'Defender territory index.', required: true },
    { name: 'dice', description: 'Number of attacker dice (default: max).' },
  ],
  handler(cmd) {
    if (!session.riskGame) return { error: 'No active game.' };
    const from = Number(cmd.flags.from ?? -1);
    const to = Number(cmd.flags.to ?? -1);
    const dice = cmd.flags.dice ? Number(cmd.flags.dice) : undefined;
    try {
      const result = session.riskGame.attack(from, to, dice);
      return {
        from: TERRITORIES[from].name,
        to: TERRITORIES[to].name,
        attackerDice: result.combat.attackerDice,
        defenderDice: result.combat.defenderDice,
        attackerLosses: result.combat.attackerLosses,
        defenderLosses: result.combat.defenderLosses,
        conquered: result.combat.territoryConquered,
        status: session.riskGame.status(),
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  },
};

```
