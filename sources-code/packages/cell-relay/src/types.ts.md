---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cell-relay/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.440833+00:00
---

# packages/cell-relay/src/types.ts

```ts
/**
 * Cell-relay wire-protocol types.
 *
 * A "room" is a named append-only signed-cell log. Anything that wants
 * collaborative versioning over a stream of cells — the jam-room
 * browser client, the repo-wide release pipeline, future helm-side
 * tools — talks to a cell-relay through this protocol.
 *
 * Two interchangeable implementations of the relay live in apps/:
 *   - runtime/world-beam/apps/cell_relay/        Elixir/OTP/BEAM (production)
 *   - apps/demo-collab-versioning/ Bun (dev-only)
 *
 * Both speak the wire shape below and persist to the same per-room
 * JSONL format on disk; clients pick whichever runtime is up:
 *
 *   client → server  { type: 'commit', cell }
 *   client → server  { type: 'live', payload }
 *   client → server  { type: 'reset' }
 *
 *   server → client  { type: 'snapshot', cells, presence, your: { id, identity, room } }
 *   server → client  { type: 'commit', cell, from: { identity } }
 *   server → client  { type: 'live', payload, from: { identity } }
 *   server → client  { type: 'presence', identities, joined?, left? }
 *   server → client  { type: 'reset' }
 */

/**
 * SerializedCell — the unit of authenticated, hash-chained, append-only
 * state on a world. Authored by a hat, addressed by stateHashHex,
 * linked by parentHashes for the DAG. Persisted by World Host as one
 * line in the room's JSONL log; broadcast to other subscribers.
 */
export interface SerializedCell {
  /** Short id assigned at commit (typically derived from stateHashHex). */
  id: string;
  /** sha256 of canonical-JSON-encoded cell core. The pin. */
  stateHashHex: string;
  /** Parent stateHashes for the DAG. Empty for root cells. */
  parentHashes: string[];
  /** The semantic content + op. World Host treats this as opaque. */
  patch: { op: string; payload: Record<string, unknown> };
  /** Authoring hat (BRC-52 cert subject placeholder until signing wires up). */
  hat: string;
  /** Distance from root in the chain. */
  depth: number;
  /** Branch tag (e.g. "main", "0.1.x"). */
  branch: string;
  /** If this cell was cherry-picked, the source stateHash. */
  cherryPickedFromHash: string | null;
  /** Audit flag set by World Host on detected tamper. */
  tampered: boolean;
  /** Identity that authored this cell — set by relay on commit. */
  author?: string;
}

// ── Client → Server ──────────────────────────────────────────────────

export type ClientMsg =
  | { type: 'commit'; cell: SerializedCell }
  | { type: 'live'; payload: unknown }
  | { type: 'reset' };

// ── Server → Client ──────────────────────────────────────────────────

export interface SnapshotMsg {
  type: 'snapshot';
  cells: SerializedCell[];
  presence: string[];
  your: { id: string; identity: string; room: string };
}

export interface CommitMsg {
  type: 'commit';
  cell: SerializedCell;
  from: { identity: string };
}

export interface LiveMsg {
  type: 'live';
  payload: unknown;
  from: { identity: string };
}

export interface PresenceMsg {
  type: 'presence';
  identities: string[];
  joined?: string;
  left?: string;
}

export interface ResetMsg {
  type: 'reset';
}

export type ServerMsg = SnapshotMsg | CommitMsg | LiveMsg | PresenceMsg | ResetMsg;

// ── Connection ───────────────────────────────────────────────────────

export interface ConnectOptions {
  /** ws:// or wss:// URL, e.g. "ws://localhost:5178". Path is "/". */
  url: string;
  /** Room (= world) identifier. Sanitised to [a-zA-Z0-9_-]{1,64} by the relay. */
  room: string;
  /** Identity string the relay uses for `your` + `from`. */
  identity: string;
}

```
