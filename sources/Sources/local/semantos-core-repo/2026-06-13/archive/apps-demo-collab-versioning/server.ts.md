---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-collab-versioning/server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.684808+00:00
---

# archive/apps-demo-collab-versioning/server.ts

```ts
/**
 * Bun dev variant of the cell-relay protocol — the simpler Bun
 * counterpart to runtime/world-beam/apps/cell_relay/ (Elixir/OTP). Same wire shape,
 * same JSONL persistence format, same port 5178; pick whichever is up.
 * Defined in @semantos/cell-relay.
 *
 * Used by the jam-room browser client and by the repo-wide release
 * pipeline (tools/release/) for local dev. For local dev it's a tiny
 * Bun server that:
 *
 *   • Routes WebSocket clients into rooms via `?room=<id>` (default: lobby).
 *   • Appends every committed cell to `data/<roomId>.jsonl` for replay.
 *   • Snapshots the room's full chain to new clients on connect.
 *   • Broadcasts each commit to other room members in real time.
 *
 * Protocol (JSON over WebSocket):
 *
 *   server → client on connect:
 *     { type: 'snapshot', cells: SerializedCell[], your: { id, identity, room } }
 *
 *   client → server on commit:
 *     { type: 'commit', cell: SerializedCell }
 *
 *   server → other clients in room:
 *     { type: 'commit', cell: SerializedCell, from: { id, identity } }
 *
 *   client → server reset (room-scoped):     { type: 'reset' }
 *   server → all-in-room on reset:           { type: 'reset' }
 */

import { mkdirSync, existsSync, appendFileSync, writeFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

interface Connection {
  id: string;
  identity: string;
  room: string;
}

interface SerializedCell {
  id: string;
  stateHashHex: string;
  parentHashes: string[];
  patch: { op: string; payload: Record<string, unknown> };
  hat: string;
  depth: number;
  branch: string;
  cherryPickedFromHash: string | null;
  tampered: boolean;
  /** Identity that authored this cell (set by relay on commit). */
  author?: string;
}

const CORS_HEADERS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};

type ClientMsg =
  | { type: 'commit'; cell: SerializedCell }
  | { type: 'reset' };

const DATA_DIR = join(import.meta.dir, 'data');
mkdirSync(DATA_DIR, { recursive: true });

interface RoomState {
  cells: SerializedCell[];
  byHash: Map<string, SerializedCell>;
  subs: Set<Bun.ServerWebSocket<Connection>>;
}

const rooms = new Map<string, RoomState>();

function logFileFor(room: string): string {
  // Sanitise: allow only alnum, underscore, hyphen.
  const safe = room.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 64) || 'lobby';
  return join(DATA_DIR, `${safe}.jsonl`);
}

function getRoom(roomId: string): RoomState {
  let r = rooms.get(roomId);
  if (r) return r;
  r = { cells: [], byHash: new Map(), subs: new Set() };
  // Replay persisted log.
  const file = logFileFor(roomId);
  if (existsSync(file)) {
    try {
      const text = readFileSync(file, 'utf8');
      for (const line of text.split('\n')) {
        if (!line) continue;
        try {
          const cell = JSON.parse(line) as SerializedCell;
          if (!r.byHash.has(cell.stateHashHex)) {
            r.cells.push(cell);
            r.byHash.set(cell.stateHashHex, cell);
          }
        } catch { /* skip malformed line */ }
      }
      console.log(`  ${paint('relay')}↺${RESET_C} replayed ${r.cells.length} cells for room "${roomId}"`);
    } catch (err) {
      console.warn(`  ${paint('relay')}!${RESET_C} replay failed for room "${roomId}":`, err);
    }
  }
  rooms.set(roomId, r);
  return r;
}

function persistCell(roomId: string, cell: SerializedCell): void {
  const file = logFileFor(roomId);
  try {
    if (!existsSync(dirname(file))) mkdirSync(dirname(file), { recursive: true });
    appendFileSync(file, JSON.stringify(cell) + '\n');
  } catch (err) {
    console.warn(`  ${paint('relay')}!${RESET_C} persist failed for "${roomId}":`, err);
  }
}

function clearRoomLog(roomId: string): void {
  try {
    writeFileSync(logFileFor(roomId), '');
  } catch {/* ignore */}
}

function paint(identity: string): string {
  switch (identity) {
    case 'alice': return '\x1b[34m';
    case 'bob': return '\x1b[32m';
    case 'dj': return '\x1b[33m';
    case 'relay': return '\x1b[35m';
    default: return '\x1b[37m';
  }
}
const RESET_C = '\x1b[0m';

const server = Bun.serve<Connection>({
  port: 5178,
  fetch(req, srv) {
    const url = new URL(req.url);
    if (req.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }
    if (url.pathname === '/health') {
      const summary = {
        rooms: [...rooms.entries()].map(([id, r]) => ({
          id,
          cells: r.cells.length,
          clients: r.subs.size,
        })),
      };
      return new Response(JSON.stringify(summary), {
        headers: { 'content-type': 'application/json', ...CORS_HEADERS },
      });
    }
    if (url.pathname === '/rooms') {
      // Discovery: list active rooms (with at least one client) for the UI.
      const list = [...rooms.entries()]
        .filter(([_, r]) => r.subs.size > 0)
        .map(([id, r]) => ({ id, clients: r.subs.size, cells: r.cells.length }));
      return new Response(JSON.stringify(list), {
        headers: { 'content-type': 'application/json', ...CORS_HEADERS },
      });
    }
    const identity = url.searchParams.get('as') ?? 'observer';
    const roomQ = (url.searchParams.get('room') ?? 'lobby').replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 64) || 'lobby';
    const id = crypto.randomUUID().slice(0, 6);
    if (srv.upgrade(req, { data: { id, identity, room: roomQ } })) return undefined;
    return new Response('semantos jam relay — connect via WebSocket\n');
  },
  websocket: {
    open(ws) {
      const { id, identity, room: roomId } = ws.data;
      const r = getRoom(roomId);
      r.subs.add(ws);
      console.log(
        `${paint(identity)}+ ${identity}@${roomId} (${id})${RESET_C}  ` +
        `clients=${r.subs.size}  cells=${r.cells.length}`,
      );
      ws.send(JSON.stringify({ type: 'snapshot', cells: r.cells, your: ws.data }));
    },
    message(ws, raw) {
      const text = typeof raw === 'string' ? raw : new TextDecoder().decode(raw as ArrayBuffer);
      let m: ClientMsg;
      try {
        m = JSON.parse(text) as ClientMsg;
      } catch {
        return;
      }
      const r = getRoom(ws.data.room);
      if (m.type === 'commit') {
        const cell = m.cell;
        if (r.byHash.has(cell.stateHashHex)) return; // dedupe
        // Attribute the cell to its author so other clients can bucket it
        // into the right per-peer DAG (used by the 4-channel mixer).
        cell.author = ws.data.identity;
        r.cells.push(cell);
        r.byHash.set(cell.stateHashHex, cell);
        persistCell(ws.data.room, cell);
        const out = JSON.stringify({ type: 'commit', cell, from: ws.data });
        for (const sub of r.subs) {
          if (sub !== ws) sub.send(out);
        }
        console.log(
          `  ${paint(ws.data.identity)}${ws.data.identity}@${ws.data.room}${RESET_C} → ` +
          `${cell.patch.op}  ${cell.stateHashHex.slice(0, 10)}…`,
        );
      } else if (m.type === 'reset') {
        r.cells.length = 0;
        r.byHash.clear();
        clearRoomLog(ws.data.room);
        const out = JSON.stringify({ type: 'reset' });
        for (const sub of r.subs) sub.send(out);
        console.log(`  ${paint(ws.data.identity)}${ws.data.identity}@${ws.data.room}${RESET_C} → RESET`);
      }
    },
    close(ws) {
      const r = rooms.get(ws.data.room);
      if (r) r.subs.delete(ws);
      const { id, identity, room: roomId } = ws.data;
      console.log(
        `${paint(identity)}- ${identity}@${roomId} (${id})${RESET_C}  ` +
        `remaining=${r?.subs.size ?? 0}`,
      );
    },
  },
});

console.log(`semantos jam relay listening on :${server.port}`);
console.log(`  rooms persisted at: ${DATA_DIR}/<roomId>.jsonl`);
console.log(`  open multi-room URLs:`);
console.log(`    http://localhost:5180/?room=lobby&as=alice`);
console.log(`    http://localhost:5180/?room=warehouse&as=bret`);
console.log(`    http://localhost:5180/?room=studio&as=charlie`);

```
