---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/reducer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.793531+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/reducer.ts

```ts
/**
 * Payment-channel reducer — pure FSM dispatcher.
 *
 * `channelReducer(state, event)` returns the next state plus a list
 * of commands the effect layer must execute. The reducer never makes
 * wallet calls or broadcasts — see prompts 14 (ports) + 15 (effects)
 * for the side-effectful wiring that consumes the emitted commands.
 */

import {
  transitionAttachSpv,
  transitionClose,
  transitionExtract,
  transitionFlowActivate,
  transitionFlowDeactivate,
  transitionFlowReady,
  transitionFund,
  transitionSettleBegin,
} from './transitions';
import type {
  ChannelEvent,
  ChannelStateValue,
  ReducerResult,
} from './types';

export function channelReducer(
  state: ChannelStateValue,
  event: ChannelEvent,
): ReducerResult {
  switch (event.type) {
    case 'fund':
      return transitionFund(state, event);
    case 'extract':
      return transitionExtract(state, event);
    case 'attach-spv':
      return transitionAttachSpv(state, event);
    case 'flow-ready':
      return transitionFlowReady(state);
    case 'flow-activate':
      return transitionFlowActivate(state);
    case 'flow-deactivate':
      return transitionFlowDeactivate(state);
    case 'settle-begin':
      return transitionSettleBegin(state, event);
    case 'close':
      return transitionClose(state);
    default:
      return {
        next: { ...state, lastError: `unknown event: ${(event as { type: string }).type}` },
        emitted: [],
      };
  }
}

```
