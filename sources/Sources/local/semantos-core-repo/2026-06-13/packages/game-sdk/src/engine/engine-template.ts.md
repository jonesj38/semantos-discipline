---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/engine-template.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.525061+00:00
---

# packages/game-sdk/src/engine/engine-template.ts

```ts
/**
 * Engine template — combines the abstract pattern modules into a
 * single dispatch surface downstream games inherit:
 *
 *   reducer-base    → pure FSM
 *   policy-hook     → pre-action gate
 *   action-dispatcher → handler registry on top of the slice
 *   persistence-hook → state-change → cell-store
 *   event-emitter   → typed bus per engine
 *
 * Game extensions construct one `EngineTemplate<S, A, E>` and bind
 * their own concrete reducer, policy evaluator, persistence facade,
 * and event union. The template is generic — it doesn't know
 * anything about cards, dungeons, or chess.
 */

import type { EventBus } from '@semantos/state';

import {
  makeActionDispatcher,
  type ActionDispatcher,
  type ActionHandler,
} from './action-dispatcher';
import { gameEventBus } from './event-emitter';
import { resolvePolicy } from './policy-hook';
import { resolveCellStore, type CellStoreFacade } from './persistence-hook';
import {
  makeEngineSlice,
  type EngineSlice,
  type Reducer,
} from './reducer-base';

export interface EngineTemplateOptions<S, A extends { type: string }> {
  reducer: Reducer<S, A>;
  initial: S;
  /** Skip the policy gate (test mode). */
  bypassPolicy?: boolean;
  /** Persist on every state change via cellStorePort. */
  persistOnChange?: (state: S, prev: S) => { path: string; bytes: Uint8Array } | null;
}

export interface EngineTemplate<S, A extends { type: string }, E> {
  slice: EngineSlice<S, A>;
  dispatcher: ActionDispatcher<S, A>;
  events: EventBus<E>;
  cellStore(): CellStoreFacade;
  /** Register an action handler. Sugar over `dispatcher.on`. */
  on(type: A['type'], handler: ActionHandler<S, A>): () => void;
  /** Dispatch with policy + persistence + handlers fanning out. */
  dispatch(action: A): Promise<S>;
}

/** Build a fresh engine template. */
export function makeEngineTemplate<S, A extends { type: string }, E>(
  opts: EngineTemplateOptions<S, A>,
): EngineTemplate<S, A, E> {
  const slice = makeEngineSlice<S, A>(opts.reducer, opts.initial);
  const dispatcher = makeActionDispatcher<S, A>(slice);
  const events = gameEventBus<E>();

  if (opts.persistOnChange) {
    slice.subscribe((next, prev) => {
      const op = opts.persistOnChange?.(next, prev);
      if (op) void Promise.resolve(resolveCellStore().write(op.path, op.bytes));
    });
  }

  return {
    slice,
    dispatcher,
    events,
    cellStore: () => resolveCellStore(),
    on: (type, handler) => dispatcher.on(type, handler),
    async dispatch(action: A): Promise<S> {
      if (!opts.bypassPolicy) {
        const policy = resolvePolicy();
        const decision = await policy.evaluate({
          action,
          state: slice.state(),
        });
        if (decision.decision === 'reject') {
          throw new Error(`policy rejected ${action.type}: ${decision.reason}`);
        }
      }
      return dispatcher.dispatch(action);
    },
  };
}

```
