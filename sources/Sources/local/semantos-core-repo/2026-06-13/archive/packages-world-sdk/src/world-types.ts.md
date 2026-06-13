---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-world-sdk/src/world-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.703245+00:00
---

# archive/packages-world-sdk/src/world-types.ts

```ts
/**
 * Wire types for the Semantos world protocol.
 *
 * Canonical source for types shared between world-host (Elixir/BEAM),
 * world-client (Three.js browser), and world applications (jam-room, etc.).
 *
 * Spec source: docs/spec/protocol-v0.5.md §4, §12.1.
 */

export type Vec3 = [number, number, number];
export type Quat = [number, number, number, number];

export type Linearity = "linear" | "affine" | "relevant" | "unrestricted";

export interface SpatialState {
  position: Vec3;
  orientation: Quat;
  velocity: Vec3;
}

export interface EntityDelta {
  entity_id: string;
  spatial: SpatialState;
  linearity: Linearity;
  prev_hash: string;
  state_hash: string;
  version: number;
  controller?: string | null;
  color?: number | null;
}

export interface WorldTick {
  region_id: string;
  tick_seq: number;
  prev_state_hash: string;
  state_hash: string;
  wall_clock_hint: number;
}

export type WorldFrame =
  | { kind: "snapshot"; region_id: string; tick_seq: number; state_hash: string; entities: EntityDelta[] }
  | { kind: "tick_delta"; region_id: string; tick: WorldTick; deltas: EntityDelta[] }
  | { kind: "entity_spawn"; region_id: string; entity: EntityDelta }
  | { kind: "entity_despawn"; region_id: string; entity_id: string; reason: string }
  | {
      kind: "entity_action_result";
      region_id: string;
      action_id: string;
      outcome:
        | { ok: true; tick_seq?: number; state_hash?: string }
        | { ok: false; reason: string; detail?: string };
    };

export interface EntityAction {
  entity_id: string;
  op: "move" | "dup" | "drop" | "noop";
  args?: Record<string, unknown>;
  action_id: string;
  local_predicted_state_hash?: string;
}

```
