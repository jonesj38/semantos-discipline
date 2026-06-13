---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/action-dispatcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.524428+00:00
---

# packages/game-sdk/src/engine/action-dispatcher.ts

```ts
/**
 * Action dispatcher — `Registry<ActionHandler<S, A>>` keyed by
 * action type. Wraps the pure reducer with side-effecting handlers
 * that fire after the reducer accepts an action.
 *
 * Handlers don't mutate state directly; they observe transitions
 * and emit events / persist / broadcast. The pure FSM stays clean
 * (see `reducer-base.ts`); the dispatcher is where IO attaches.
 */

import type { EngineSlice } from './reducer-base';

export interface ActionContext<S, A> {
  action: A;
  prev: S;
  next: S;
}

export type ActionHandler<S, A> = (
  ctx: ActionContext<S, A>,
) => void | Promise<void>;

export interface ActionDispatcher<S, A extends { type: string }> {
  /** Register a handler for one action type. Returns a `dispose()`. */
  on(type: A['type'], handler: ActionHandler<S, A>): () => void;
  /** Register a handler that fires for every action regardless of type. */
  onAny(handler: ActionHandler<S, A>): () => void;
  /** Dispatch an action; runs the reducer + any registered handlers. */
  dispatch(action: A): Promise<S>;
  /** Read the slice's current state. */
  state(): S;
}

export function makeActionDispatcher<S, A extends { type: string }>(
  slice: EngineSlice<S, A>,
): ActionDispatcher<S, A> {
  const typed = new Map<string, Set<ActionHandler<S, A>>>();
  const any = new Set<ActionHandler<S, A>>();

  return {
    on(type, handler) {
      let set = typed.get(type);
      if (!set) {
        set = new Set();
        typed.set(type, set);
      }
      set.add(handler);
      return () => {
        set!.delete(handler);
      };
    },
    onAny(handler) {
      any.add(handler);
      return () => {
        any.delete(handler);
      };
    },
    async dispatch(action) {
      const prev = slice.state();
      const next = slice.dispatch(action);
      const ctx: ActionContext<S, A> = { action, prev, next };
      const handlers = typed.get(action.type);
      if (handlers) {
        for (const h of handlers) await h(ctx);
      }
      for (const h of any) await h(ctx);
      return next;
    },
    state: () => slice.state(),
  };
}

```
