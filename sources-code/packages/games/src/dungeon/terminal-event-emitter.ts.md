---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/terminal-event-emitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.402898+00:00
---

# packages/games/src/dungeon/terminal-event-emitter.ts

```ts
/**
 * Terminal event emitter — anchors victory/death cells via the Phase
 * 29.5 `AnchorEmitter`. Configurable so downstream variants can opt
 * into different terminal-event lists (e.g. timed runs that anchor on
 * "timeout" too).
 *
 * The legacy engine inlined the hardcoded `['dead', 'victory']` set
 * + the `dungeon-${id}-${status}` idempotency key shape. The split
 * keeps both behind a single emit point so the wiring stays
 * audit-able and the terminal list is injectable for tests.
 */

import type { AnchorEmitter } from '../../../policy-runtime/src/anchor-emitter';

import type { DungeonGameStatus } from './types';

/** Default set of statuses that warrant on-chain anchoring. */
export const DEFAULT_TERMINAL_EVENTS: readonly DungeonGameStatus[] = [
  'dead',
  'victory',
];

export interface TerminalEventArgs {
  /** Cell bytes of the freshly committed board. */
  cellBytes: Uint8Array;
  /** Cell id of the freshly committed board. */
  cellId: string;
  /** Current status — emit only if it's in `terminalEvents`. */
  status: DungeonGameStatus;
}

export interface TerminalEventEmitter {
  /**
   * Emit (idempotently) when `status` is one of the configured terminal
   * events. Returns true when the emit fired, false when skipped (no
   * emitter bound or status not terminal).
   */
  maybeEmit(args: TerminalEventArgs): boolean;
}

export interface MakeTerminalEventEmitterArgs {
  /** Source emitter — typically `engine.anchorEmitter`. */
  anchorEmitter?: AnchorEmitter;
  /** Override list of terminal statuses. Defaults to dead+victory. */
  terminalEvents?: readonly DungeonGameStatus[];
}

/**
 * Build a terminal-event emitter wired to the dungeon's anchor
 * pipeline. Emits a fire-and-forget `anchorEmitter.emit()` for cells
 * matching the configured terminal status set.
 */
export function makeTerminalEventEmitter(
  args: MakeTerminalEventEmitterArgs,
): TerminalEventEmitter {
  const events = args.terminalEvents ?? DEFAULT_TERMINAL_EVENTS;
  return {
    maybeEmit({ cellBytes, cellId, status }) {
      if (!args.anchorEmitter) return false;
      if (!events.includes(status)) return false;
      void args.anchorEmitter.emit(cellBytes, {
        linearity: 'RELEVANT',
        anchorPolicy: 'terminal-only',
        idempotencyKey: `dungeon-${cellId}-${status}`,
      });
      return true;
    },
  };
}

```
