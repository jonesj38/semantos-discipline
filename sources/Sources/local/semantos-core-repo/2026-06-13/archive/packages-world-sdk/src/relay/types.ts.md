---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/src/relay/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.705034+00:00
---

# archive/packages-world-sdk/src/relay/types.ts

```ts
/**
 * Wire types for the cell-relay WebSocket protocol.
 *
 * The relay (runtime/world-beam/apps/cell_relay) speaks a simple JSON
 * protocol over a bare WebSocket. These types mirror the Elixir side
 * exactly — do not diverge without updating CellRelay.WSHandler.
 */

import type { Patch, Hat } from "../dag/index.js";

export interface SerializedCell {
  id: string;
  stateHashHex: string;
  parentHashes: string[];
  patch: Patch;
  hat: Hat;
  depth: number;
  branch: Hat;
  cherryPickedFromHash: string | null;
  tampered: boolean;
  /** Author identity, populated server-side on commit. */
  author?: string;
}

/** Transient broadcast — not persisted; used for real-time note triggers. */
export interface LiveTrigger {
  kind: "trigger";
  track: string;
  vel: number;
  semitone: number;
  accent?: boolean;
  slide?: boolean;
}
export type LivePayload = LiveTrigger;

export type RelayServerMsg =
  | {
      type: "snapshot";
      cells: SerializedCell[];
      presence?: string[];
      your: { id: string; identity: string; room: string };
    }
  | { type: "commit"; cell: SerializedCell; from: { identity: string } }
  | {
      type: "presence";
      identities: string[];
      joined?: string;
      left?: string;
    }
  | { type: "live"; payload: LivePayload; from: { identity: string } }
  | { type: "reset" };

export interface RelayCallbacks {
  onSnapshot(
    cells: SerializedCell[],
    your: { id: string; identity: string; room: string },
    presence: string[],
  ): void;
  onCell(cell: SerializedCell, from: { identity: string }): void;
  onPresence(
    identities: string[],
    change: { joined?: string; left?: string },
  ): void;
  onLive(payload: LivePayload, from: { identity: string }): void;
  onReset(): void;
  onStatus(status: "connecting" | "open" | "closed" | "error"): void;
  /** Called for any message type the relay doesn't recognise (e.g. clock_pong, beat). */
  onRawMessage?: (msg: Record<string, unknown>) => void;
}

```
