---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/policy-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.780502+00:00
---

# archive/apps-poker-agent/src/game-loop/policy-validator.ts

```ts
/**
 * Kernel-policy adapter — wraps the `HostFunctionRegistry` +
 * `CompiledPokerPolicies` from the cell-engine + packages/games.
 *
 * The legacy GameLoop method froze a context, dispatched
 * compound-policy predicates, then cleared the context. This module
 * is a pure-ish reimplementation: deterministic given the same
 * registry + frozen context, and tests can swap a stub registry.
 */

import { HostFunctionRegistry } from '../../../../core/cell-engine/bindings/host-functions';
import {
  compilePokerPolicies,
  registerPokerHostFunctions,
  type CompiledPokerPolicies,
} from '../../../../packages/games/src/cards/poker-policies';

import type { PlayerDecision, SimplePlayer, SimpleTable } from './types';

export interface PolicyValidatorOptions {
  bigBlind: number;
}

export interface PolicyValidator {
  /** Run the policy for the player's decision. Returns `true` if legal. */
  validate(
    player: SimplePlayer,
    table: SimpleTable,
    decision: PlayerDecision,
  ): boolean;
}

/**
 * Build a fresh validator. Idempotent in the sense that calling
 * twice gives you two distinct registries — useful for tests.
 */
export function makePolicyValidator(opts: PolicyValidatorOptions): PolicyValidator {
  const registry = new HostFunctionRegistry();
  registerPokerHostFunctions(registry);
  const policies = compilePokerPolicies();
  return {
    validate: (player, table, decision) =>
      runPolicy({ registry, policies, opts, player, table, decision }),
  };
}

interface RunArgs {
  registry: HostFunctionRegistry;
  policies: CompiledPokerPolicies;
  opts: PolicyValidatorOptions;
  player: SimplePlayer;
  table: SimpleTable;
  decision: PlayerDecision;
}

function runPolicy(args: RunArgs): boolean {
  const actionKey = args.decision.action === 'all-in' ? 'allIn' : args.decision.action;
  const policy = args.policies[actionKey as keyof CompiledPokerPolicies];
  if (!policy) return true; // Unknown action — let the engine handle.

  const toCall = args.table.currentBet - args.player.currentBet;
  args.registry.setContext({
    isActivePlayer: true,
    betToCall: toCall,
    betAmount: args.decision.amount ?? args.opts.bigBlind,
    bigBlind: args.opts.bigBlind,
    raiseBy:
      (args.decision.amount ?? args.table.currentBet + args.table.minRaise) -
      args.table.currentBet,
    minRaise: args.table.minRaise,
    playerChips: args.player.chips,
  });

  const isActive = args.registry.call('is-active-player?') === 1;
  let pass = isActive;
  switch (actionKey) {
    case 'fold':
      break;
    case 'check':
      pass = isActive && args.registry.call('no-bet-to-call?') === 1;
      break;
    case 'call':
      pass = isActive && args.registry.call('has-bet-to-call?') === 1;
      break;
    case 'bet':
      pass =
        isActive &&
        args.registry.call('no-bet-to-call?') === 1 &&
        args.registry.call('meets-minimum-bet?') === 1;
      break;
    case 'raise':
      pass =
        isActive &&
        args.registry.call('has-bet-to-call?') === 1 &&
        args.registry.call('meets-minimum-raise?') === 1;
      break;
    case 'allIn':
      pass = isActive && args.registry.call('has-chips?') === 1;
      break;
  }
  args.registry.clearContext();
  return pass;
}

```
